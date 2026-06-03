# SketchUp MCP Context

## Short Summary

This is a local MCP bridge for helping with manual SketchUp 2023 English desktop work.

It is not yet the furniture drawing automation project.

## User Preference

- Answer in Korean.
- Keep explanations short and practical.
- State conclusion first.
- Use exact file paths, commands, and results.
- Avoid broad refactors.
- Use token-saving mode: no long dumps, no repeated summaries, and report only the key result unless detail is requested.

## Architecture

```text
Codex or Claude MCP client
  -> mcp-server/server.js
  -> http://127.0.0.1:8765
  -> SketchUp Ruby plugin
  -> SketchUp 2023 model
```

## Files

- `mcp-server/server.js`: dependency-free Node MCP stdio server.
- `sketchup-plugin/daum_mcp_bridge.rb`: SketchUp Ruby HTTP bridge.
- `docs/INSTALL.md`: install instructions.
- `README.md`: project summary.

## Runtime

- SketchUp version used by owner: SketchUp 2023 English.
- Verified SketchUp version: `23.1.340`.
- Bridge URL: `http://127.0.0.1:8765`.

## SketchUp Plugin Install Path

```text
C:\Users\User\AppData\Roaming\SketchUp\SketchUp 2023\SketchUp\Plugins\daum_mcp_bridge.rb
```

## Menu

```text
Extensions > Daum MCP Bridge > Start Bridge
Extensions > Daum MCP Bridge > Status
Extensions > Daum MCP Bridge > Stop Bridge
Extensions > Daum MCP Bridge > Reload Plugin
```

## Available Tools

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

## Automation Modes

- View mode: show current view, practical top view, selection-focused view.
- Memory mode: save reusable context to `work-memory/model-memory.json` and `work-memory/latest-report.md`.
- Modeling mode: create simple groups such as boxes and walls; move, rotate, hide, and unhide selected entities.
- Review mode: analyze selection details, find cleanup targets, and export selected objects for inspection.
- Safety mode: create `.skp` backups, save working scenes, auto-name selected objects, and log actions.
- Drafting mode: measure, dimension, tag, materialize, and align selected objects.
- CAD mode: create faces from imported CAD edges, find open endpoints, and push/pull selected faces.

## Important Notes

- Preserve UTF-8 response handling. Korean model names and file paths must not break.
- When the user asks to show a "top view", use a practical working-view scale close to the user's current SketchUp composition, not a full model-bounds fit.
- Prefer safe, undoable SketchUp operations. Avoid destructive commands unless the user clearly confirms.
- Before large modeling work, save a scene and create a backup first.
- Prefer `sketchup_start_work_session` at the beginning of a substantial SketchUp task.
- CAD conversion should start with selected edges. If no face is created, run open-edge diagnosis before trying more modeling.
- Current bridge response header must include:

```text
Content-Type: application/json; charset=utf-8
```

- Do not change the default port `8765` unless all docs and config instructions are updated.
- If SketchUp was restarted, the user must run:

```text
Extensions > Daum MCP Bridge > Start Bridge
```

## Verification

```powershell
npm run check
Invoke-RestMethod -Uri http://127.0.0.1:8765/ping -TimeoutSec 5
Invoke-RestMethod -Uri http://127.0.0.1:8765/status -TimeoutSec 5
Invoke-RestMethod -Uri http://127.0.0.1:8765/model_summary -TimeoutSec 5
```

## GitHub

```text
https://github.com/dauminterior-81451/sketchup-mcp.git
```
