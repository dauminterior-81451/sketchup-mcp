# Install

## 1. Install SketchUp plugin

Copy this file:

```text
C:\Users\User\Documents\Codex\sketchup-mcp\sketchup-plugin\daum_mcp_bridge.rb
```

To:

```text
C:\Users\User\AppData\Roaming\SketchUp\SketchUp 2023\SketchUp\Plugins\daum_mcp_bridge.rb
```

Restart SketchUp.

Menu:

```text
Extensions > Daum MCP Bridge > Start Bridge
Extensions > Daum MCP Bridge > Status
Extensions > Daum MCP Bridge > Stop Bridge
```

## 2. MCP server command

Use this command in your MCP client config:

```text
node C:\Users\User\Documents\Codex\sketchup-mcp\mcp-server\server.js
```

Optional environment variable:

```text
SKETCHUP_BRIDGE_URL=http://127.0.0.1:8765
```
