# Project Instructions

## Owner Context

- Owner: Daum Interior, Daejeon.
- Purpose: Help with manual SketchUp 2023 English desktop work through a local MCP bridge.
- Primary user is comfortable with SketchUp and wants short, practical answers.
- Respond in Korean unless code, commands, paths, or UI menu names must stay in English.

## Product Goal

This project is not the furniture drawing automation yet.

First goal:
- Let Codex read the current SketchUp model.
- Let Codex inspect selected objects.
- Let Codex perform small safe commands for work assistance.

Current workflow:

```text
Codex MCP client
  -> mcp-server/server.js
  -> http://127.0.0.1:8765
  -> SketchUp Ruby plugin
  -> SketchUp 2023 model
```

## Environment

- SketchUp: SketchUp 2023 English desktop.
- Tested SketchUp version: 23.1.340.
- Bridge URL: `http://127.0.0.1:8765`.
- Plugin install path:

```text
C:\Users\User\AppData\Roaming\SketchUp\SketchUp 2023\SketchUp\Plugins\daum_mcp_bridge.rb
```

- Codex MCP config path:

```text
C:\Users\User\.codex\config.toml
```

## Current MCP Tools

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

## Current Automation Modes

- View mode: export current SketchUp view, export practical top view, debug framing bounds.
- Memory mode: save model context and latest work report under `work-memory/`.
- Modeling mode: create basic box/wall groups and move/rotate/hide selected entities.
- Avoid destructive modeling commands unless the user explicitly asks and confirms.

## SketchUp Menu

```text
Extensions > Daum MCP Bridge > Start Bridge
Extensions > Daum MCP Bridge > Status
Extensions > Daum MCP Bridge > Stop Bridge
Extensions > Daum MCP Bridge > Reload Plugin
```

## Development Rules

- Keep changes small and practical.
- Do not start furniture drawing automation unless explicitly requested.
- Do not change ports or MCP names without updating docs and config instructions.
- Do not hardcode user project model paths.
- Keep Ruby plugin compatible with SketchUp 2023.
- Preserve UTF-8 JSON responses for Korean model names and paths.
- When the user asks to show a "top view", frame it close to the user's current working view scale instead of fitting the entire model bounds.
- When adding modeling automation, prefer safe reversible operations using `model.start_operation`.
- Do not test modeling commands on the user's active model unless the user asks for that exact change.
- Run `npm run check` after editing `mcp-server/server.js`.
- If editing the Ruby plugin, copy it to the SketchUp Plugins folder and verify through `/ping`, `/status`, and `/model_summary`.

## Git Rules

- Commit after meaningful changes.
- Push to:

```text
https://github.com/dauminterior-81451/sketchup-mcp.git
```

## Known Verification Commands

```powershell
npm run check
Invoke-RestMethod -Uri http://127.0.0.1:8765/ping -TimeoutSec 5
Invoke-RestMethod -Uri http://127.0.0.1:8765/status -TimeoutSec 5
Invoke-RestMethod -Uri http://127.0.0.1:8765/model_summary -TimeoutSec 5
```

Expected bridge status when running:

```json
{
  "running": true,
  "host": "127.0.0.1",
  "port": 8765,
  "sketchup_version": "23.1.340"
}
```
