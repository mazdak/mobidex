# Mission

Mission: Fix projectless Codex chat interoperability so desktop Codex chats under `~/Documents/Codex` and Mobidex no-folder chats appear in the same iOS/Android no-folder session list.

Done criteria:
- [x] Confirm the actual local Codex folderless data shape.
- [x] Update shared folderless path classification to include the desktop Codex no-folder location.
- [x] Update iOS and Android tests for `~/Documents/Codex` chat paths.
- [x] Run focused shared, iOS, and Android validation.
- [x] Review the change and address confirmed findings.
- [x] Commit and push the fix branch.

Guardrails:
- Do not classify arbitrary `Documents` paths as folderless.
- Preserve app-owned unscoped thread ID tracking; add desktop path compatibility instead of replacing it.
- Avoid another release build until the behavior is validated.

Critical learnings:
- This Mac has `~/Documents/Codex`, and recent Codex desktop folderless chats are stored under dated subdirectories there.
- Mobidex-created no-folder chats were started with nil `cwd`; app-server filled that with its process cwd (`/Users/mazdak` here), so future starts should reuse an observed `Documents/Codex` root when available.
- Review found date-only `~/Documents/Codex/YYYY-MM-DD` paths should remain normal projects; only the root itself and date-plus-child desktop chat paths are folderless.
