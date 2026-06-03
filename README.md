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
- `sketchup_find_entities_by_tag`
- `sketchup_cluster_window_candidates`
- `sketchup_analyze_selection`
- `sketchup_find_cleanup_targets`
- `sketchup_export_selection_view`
- `sketchup_create_box`
- `sketchup_create_wall`
- `sketchup_move_selection`
- `sketchup_rotate_selection`
- `sketchup_hide_selection`
- `sketchup_show_all`
- `sketchup_capture_work_context`
- `sketchup_save_current_view`
- `sketchup_create_scene`
- `sketchup_auto_name_selection`
- `sketchup_backup_model`
- `sketchup_measure_selection`
- `sketchup_add_dimensions_to_selection`
- `sketchup_create_or_assign_tag`
- `sketchup_apply_material_to_selection`
- `sketchup_align_selection`
- `sketchup_start_work_session`
- `sketchup_make_faces_from_selection`
- `sketchup_pushpull_selected_faces`
- `sketchup_find_open_edges`

## First automation modes

- View mode: current view, practical top view, bounds diagnosis.
- Memory mode: capture model summary, selection, and work report to `work-memory/`.
- Modeling mode: create basic boxes/walls and move/rotate/hide selected objects.
- Review mode: analyze selected entities and find cleanup targets.
- Safety mode: backup the model, save working scenes, and log assistant actions.
- Drafting mode: measure selection, add dimensions, assign tags, apply materials, and align entities.
- CAD mode: make faces from imported edges, diagnose open edges, and push/pull selected faces.

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
