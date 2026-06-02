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
- `sketchup_export_current_view`
- `sketchup_bounds_debug`
- `sketchup_create_box`
- `sketchup_create_wall`
- `sketchup_move_selection`
- `sketchup_rotate_selection`
- `sketchup_hide_selection`
- `sketchup_show_all`
- `sketchup_capture_work_context`

## First automation modes

- View mode: current view, practical top view, bounds diagnosis.
- Memory mode: capture model summary, selection, and work report to `work-memory/`.
- Modeling mode: create basic boxes/walls and move/rotate/hide selected objects.

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
