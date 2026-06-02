const http = require("node:http");

const bridgeUrl = process.env.SKETCHUP_BRIDGE_URL || "http://127.0.0.1:8765";

const tools = [
  {
    name: "sketchup_ping",
    description: "Check whether the SketchUp Ruby bridge is reachable.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "sketchup_status",
    description: "Read SketchUp bridge status.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "sketchup_model_summary",
    description: "Read current SketchUp model summary.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "sketchup_selection",
    description: "Read current SketchUp selection details.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "sketchup_rename_selection",
    description: "Rename selected SketchUp groups or component instances.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", minLength: 1 }
      },
      required: ["name"],
      additionalProperties: false
    }
  }
];

function requestBridge(method, path, body) {
  const url = new URL(path, bridgeUrl);
  const payload = body ? JSON.stringify(body) : "";

  return new Promise((resolve, reject) => {
    const req = http.request(
      url,
      {
        method,
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(payload)
        },
        timeout: 5000
      },
      (res) => {
        let data = "";
        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          data += chunk;
        });
        res.on("end", () => {
          try {
            const parsed = data ? JSON.parse(data) : {};
            if (res.statusCode >= 400) {
              reject(new Error(parsed.error || `Bridge returned HTTP ${res.statusCode}`));
              return;
            }
            resolve(parsed);
          } catch (error) {
            reject(new Error(`Invalid bridge response: ${error.message}`));
          }
        });
      }
    );

    req.on("timeout", () => {
      req.destroy(new Error("SketchUp bridge request timed out."));
    });
    req.on("error", (error) => {
      reject(new Error(`SketchUp bridge is not reachable at ${bridgeUrl}: ${error.message}`));
    });
    req.write(payload);
    req.end();
  });
}

async function callTool(name, args) {
  if (name === "sketchup_ping") return requestBridge("GET", "/ping");
  if (name === "sketchup_status") return requestBridge("GET", "/status");
  if (name === "sketchup_model_summary") return requestBridge("GET", "/model_summary");
  if (name === "sketchup_selection") return requestBridge("GET", "/selection");
  if (name === "sketchup_rename_selection") {
    return requestBridge("POST", "/rename_selection", { name: args.name });
  }
  throw new Error(`Unknown tool: ${name}`);
}

function jsonRpc(id, result) {
  return JSON.stringify({ jsonrpc: "2.0", id, result });
}

function jsonRpcError(id, code, message) {
  return JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } });
}

function write(message) {
  process.stdout.write(`${message}\n`);
}

async function handle(message) {
  if (!message || message.id === undefined) return;

  try {
    if (message.method === "initialize") {
      write(jsonRpc(message.id, {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "sketchup-mcp", version: "0.1.0" }
      }));
      return;
    }

    if (message.method === "tools/list") {
      write(jsonRpc(message.id, { tools }));
      return;
    }

    if (message.method === "tools/call") {
      const params = message.params || {};
      const result = await callTool(params.name, params.arguments || {});
      write(jsonRpc(message.id, {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }]
      }));
      return;
    }

    write(jsonRpcError(message.id, -32601, `Method not found: ${message.method}`));
  } catch (error) {
    write(jsonRpcError(message.id, -32000, error.message));
  }
}

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  const lines = buffer.split(/\r?\n/);
  buffer = lines.pop() || "";
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      handle(JSON.parse(line));
    } catch (error) {
      write(jsonRpcError(null, -32700, `Parse error: ${error.message}`));
    }
  }
});
