# SketchUp MCP

SketchUp 2023 English desktop version helper.

## Structure

```text
mcp-server/server.js
sketchup-plugin/daum_mcp_bridge.rb
docs/INSTALL.md
```

## Available MCP tools

- `sketchup_ping`
- `sketchup_status`
- `sketchup_model_summary`
- `sketchup_selection`
- `sketchup_rename_selection`
- `sketchup_export_top_view`

## SketchUp menu

```text
Extensions > Daum MCP Bridge > Start Bridge
Extensions > Daum MCP Bridge > Status
Extensions > Daum MCP Bridge > Stop Bridge
Extensions > Daum MCP Bridge > Reload Plugin
```

## Default bridge URL

```text
http://127.0.0.1:8765
```
