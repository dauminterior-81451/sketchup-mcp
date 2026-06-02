# SketchUp MCP Design

## Goal

Create a separate local MCP project that helps with manual SketchUp 2023 work.

## Scope

First version reads current model state, reads selected entities, and renames selected groups/components.

## Architecture

```text
Codex MCP client
  -> mcp-server/server.js
  -> http://127.0.0.1:8765
  -> SketchUp Ruby plugin
  -> SketchUp 2023 model
```

## Components

- `mcp-server/server.js`: dependency-free Node MCP stdio server.
- `sketchup-plugin/daum_mcp_bridge.rb`: SketchUp Ruby plugin with local HTTP bridge.
- `docs/INSTALL.md`: install and run instructions.

## Tools

- `sketchup_ping`: bridge connectivity check.
- `sketchup_status`: bridge running status.
- `sketchup_model_summary`: model name, counts, materials, tags, units.
- `sketchup_selection`: selected entity type, name, bounds.
- `sketchup_rename_selection`: rename selected groups/components.

## Error Handling

The MCP server returns clear errors when SketchUp is closed or the bridge is stopped.

## Test

Run:

```text
npm run check
```

Then install the Ruby plugin and start the bridge from SketchUp.
