const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");

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
  },
  {
    name: "sketchup_export_top_view",
    description: "Export the current SketchUp model as a top-view PNG.",
    inputSchema: {
      type: "object",
      properties: {
        outputPath: { type: "string", minLength: 1 },
        width: { type: "number", minimum: 400 },
        height: { type: "number", minimum: 400 }
      },
      required: ["outputPath"],
      additionalProperties: false
    }
  },
  {
    name: "sketchup_export_current_view",
    description: "Export the current SketchUp viewport as a PNG without changing the camera.",
    inputSchema: {
      type: "object",
      properties: {
        outputPath: { type: "string", minLength: 1 },
        width: { type: "number", minimum: 400 },
        height: { type: "number", minimum: 400 }
      },
      required: ["outputPath"],
      additionalProperties: false
    }
  },
  {
    name: "sketchup_bounds_debug",
    description: "List largest visible top-level SketchUp entity bounds for export framing diagnosis.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "sketchup_analyze_selection",
    description: "Analyze selected SketchUp entities with dimensions, layers, materials, and cleanup hints.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "sketchup_find_cleanup_targets",
    description: "Find model cleanup targets such as far-away entities, tiny edges, unnamed groups, and hidden entities.",
    inputSchema: {
      type: "object",
      properties: {
        farDistanceMm: { type: "number", minimum: 1000 },
        tinyEdgeMm: { type: "number", minimum: 0.1 }
      },
      additionalProperties: false
    }
  },
  {
    name: "sketchup_export_selection_view",
    description: "Frame current selection from top view and export it as a PNG.",
    inputSchema: {
      type: "object",
      properties: {
        outputPath: { type: "string", minLength: 1 },
        width: { type: "number", minimum: 400 },
        height: { type: "number", minimum: 400 },
        margin: { type: "number", minimum: 1 }
      },
      required: ["outputPath"],
      additionalProperties: false
    }
  },
  {
    name: "sketchup_create_box",
    description: "Create a named box group in SketchUp using millimeter dimensions.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string" },
        width: { type: "number", minimum: 1 },
        depth: { type: "number", minimum: 1 },
        height: { type: "number", minimum: 1 },
        x: { type: "number" },
        y: { type: "number" },
        z: { type: "number" }
      },
      required: ["width", "depth", "height"],
      additionalProperties: false
    }
  },
  {
    name: "sketchup_create_wall",
    description: "Create a wall group from two plan points, thickness, and height in millimeters.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string" },
        x1: { type: "number" },
        y1: { type: "number" },
        x2: { type: "number" },
        y2: { type: "number" },
        thickness: { type: "number", minimum: 1 },
        height: { type: "number", minimum: 1 },
        z: { type: "number" }
      },
      required: ["x1", "y1", "x2", "y2", "thickness", "height"],
      additionalProperties: false
    }
  },
  {
    name: "sketchup_move_selection",
    description: "Move selected SketchUp entities by millimeter offsets.",
    inputSchema: {
      type: "object",
      properties: {
        dx: { type: "number" },
        dy: { type: "number" },
        dz: { type: "number" }
      },
      additionalProperties: false
    }
  },
  {
    name: "sketchup_rotate_selection",
    description: "Rotate selected SketchUp entities around their center.",
    inputSchema: {
      type: "object",
      properties: {
        axis: { type: "string", enum: ["x", "y", "z"] },
        angleDegrees: { type: "number" }
      },
      required: ["axis", "angleDegrees"],
      additionalProperties: false
    }
  },
  {
    name: "sketchup_hide_selection",
    description: "Hide selected SketchUp entities.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "sketchup_show_all",
    description: "Unhide all top-level SketchUp model entities.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "sketchup_capture_work_context",
    description: "Save current SketchUp model context memory and a practical work report.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
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
  if (name === "sketchup_export_top_view") {
    return requestBridge("POST", "/export_top_view", {
      outputPath: args.outputPath,
      width: args.width || 1600,
      height: args.height || 1200
    });
  }
  if (name === "sketchup_export_current_view") {
    return requestBridge("POST", "/export_current_view", {
      outputPath: args.outputPath,
      width: args.width || 1600,
      height: args.height || 1200
    });
  }
  if (name === "sketchup_bounds_debug") return requestBridge("GET", "/bounds_debug");
  if (name === "sketchup_analyze_selection") return requestBridge("GET", "/analyze_selection");
  if (name === "sketchup_find_cleanup_targets") {
    return requestBridge("POST", "/find_cleanup_targets", {
      farDistanceMm: args.farDistanceMm || 30000,
      tinyEdgeMm: args.tinyEdgeMm || 5
    });
  }
  if (name === "sketchup_export_selection_view") {
    return requestBridge("POST", "/export_selection_view", {
      outputPath: args.outputPath,
      width: args.width || 1600,
      height: args.height || 1200,
      margin: args.margin || 1.15
    });
  }
  if (name === "sketchup_create_box") return requestBridge("POST", "/create_box", args);
  if (name === "sketchup_create_wall") return requestBridge("POST", "/create_wall", args);
  if (name === "sketchup_move_selection") return requestBridge("POST", "/move_selection", args);
  if (name === "sketchup_rotate_selection") return requestBridge("POST", "/rotate_selection", args);
  if (name === "sketchup_hide_selection") return requestBridge("POST", "/hide_selection", {});
  if (name === "sketchup_show_all") return requestBridge("POST", "/show_all", {});
  if (name === "sketchup_capture_work_context") return captureWorkContext();
  throw new Error(`Unknown tool: ${name}`);
}

async function captureWorkContext() {
  const [status, model, selection, bounds] = await Promise.all([
    requestBridge("GET", "/status"),
    requestBridge("GET", "/model_summary"),
    requestBridge("GET", "/selection"),
    requestBridge("GET", "/bounds_debug")
  ]);
  const capturedAt = new Date().toISOString();
  const repoRoot = path.resolve(__dirname, "..");
  const memoryDir = path.join(repoRoot, "work-memory");
  fs.mkdirSync(memoryDir, { recursive: true });

  const memory = { capturedAt, status, model, selection, bounds };
  const memoryPath = path.join(memoryDir, "model-memory.json");
  fs.writeFileSync(memoryPath, JSON.stringify(memory, null, 2), "utf8");

  const largest = bounds.items?.[0];
  const report = [
    "# SketchUp Work Report",
    "",
    `- Captured: ${capturedAt}`,
    `- Model: ${model.title || "(untitled)"}`,
    `- Path: ${model.path || "(unsaved)"}`,
    `- Units: ${model.units}`,
    `- Entities: ${model.entities_count}`,
    `- Groups: ${model.groups_count}`,
    `- Components: ${model.component_instances_count}`,
    `- Materials: ${model.materials_count}`,
    `- Tags: ${model.tags_count}`,
    `- Selection count: ${selection.count}`,
    largest ? `- Largest visible entity: ${largest.type} ${largest.name || ""} / ${largest.diagonal_mm}mm` : "- Largest visible entity: none",
    "",
    "## Next Checks",
    "",
    "- Check far-away visible entities if top view framing is too small.",
    "- Use current-view export when the user's manual camera composition is preferred.",
    "- Use selection tools before direct modeling commands."
  ].join("\n");
  const reportPath = path.join(memoryDir, "latest-report.md");
  fs.writeFileSync(reportPath, report, "utf8");

  return { memoryPath, reportPath, capturedAt, modelTitle: model.title };
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
