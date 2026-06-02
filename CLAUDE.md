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

## Important Notes

- Preserve UTF-8 response handling. Korean model names and file paths must not break.
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
