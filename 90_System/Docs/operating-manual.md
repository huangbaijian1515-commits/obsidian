# Operating Manual

## Layer Contract

### Raw / Sources

`10_Sources/` is for evidence preservation. A source note can be messy, long, and incomplete, but it must stay traceable.

Allowed content:

- clipped web pages
- copied WeChat articles
- YouTube metadata and transcript
- Feishu minutes export
- meeting notes
- interview records
- sheet-derived summaries
- manual capture records

Do not treat a source note as a trusted knowledge unit. Treat it as material to compile.

### Query

`20_Query/` is for reviewed atomic knowledge. Every query note should be small enough to reuse in different topics.

Promotion rules:

- one note, one durable idea
- must cite at least one source note unless it is explicitly personal reasoning
- must have status and confidence
- link suggestions should be reviewed before being accepted

### Wiki

`40_Wiki/` contains generated synthesis. Wiki reports are allowed to be regenerated as the query layer improves.

### Lint

`50_Lint/` contains quality reports. Lint reports create repair work for the next compile cycle.

## Capture Policy

### Web / WeChat / Articles

Use Obsidian Web Clipper or manual copy. Save the full article when allowed, plus URL and capture date.

### YouTube

Save:

- URL
- title
- channel
- published date if available
- transcript or subtitle file
- your reason for keeping it

NotebookLM may be used for public videos, but the final source note belongs in this vault.

Use:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\import-youtube.ps1 -Url "https://www.youtube.com/watch?v=..."
```

If `yt-dlp` is installed, the script captures basic metadata. If not, it creates a shell source note for manual transcript paste.

### Feishu Minutes

Export or copy:

- meeting title
- participants if appropriate
- date
- transcript
- generated summary
- action items

For work-sensitive meetings, keep `privacy: work` or `privacy: sensitive` and do not send to cloud tools.

Use:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\import-feishu-export.ps1 -InputFile "G:\path\to\meeting-export.txt" -Title "Meeting title"
```

This v2 path is export-first rather than API-first. Feishu API sync should be added only after the app ID, app secret, tenant permission model, and privacy boundary are confirmed.

### Android Capture

Use Obsidian Mobile or a plain Markdown editor to append rough links and notes into `00_Inbox/`.

Avoid editing heavily on mobile unless necessary. Compile from desktop.

## Git Policy

Suggested commit styles:

- `capture: add source notes`
- `extract: draft query candidates`
- `review: promote query notes`
- `wiki: generate topic report`
- `lint: add vault quality report`

Avoid committing sensitive work material to private GitHub unless it is approved for that storage boundary.

## V2 Compile Draft

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\compile-extraction-draft.ps1 -Status all
```

The script creates `00_Inbox/Extraction_Drafts/extraction-draft-*.md`.

Use the generated draft as a working surface with Codex:

1. Ask Codex to fill candidate viewpoints, judgments, facts, and data.
2. Review the candidates manually.
3. Promote approved items into `20_Query/`.
4. Re-run lint after promotion.

## V2.1 Feishu CLI Sync

The Feishu sync layer is read-only. Scripts may read metadata, transcripts, summaries, action items, and recording files that your account is allowed to access. They must not edit, delete, move, comment on, upload to, or otherwise modify Feishu content.

Probe local readiness:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\feishu-probe.ps1
```

If `lark-cli` is missing or not logged in, install/authenticate it separately and run:

```powershell
lark-cli auth login --recommend
```

Sync from a local JSON export:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-minutes.ps1 -InputJson "G:\path\to\feishu-minutes.json" -DaysBack 7
```

The default sync path uses `lark-cli.cmd minutes +search --as user` and `lark-cli.cmd minutes minutes get --as user`. It imports already-transcribed content first. It does not download recordings or run local transcription in the current stage.

If sync reports `need_user_authorization`, re-run `lark-cli auth login --recommend` and approve the minutes read scopes, especially `minutes:minutes.search:read`.

Dry run:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-minutes.ps1 -DaysBack 7 -DryRun
```

Install daily sync at 23:30:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\install-feishu-daily-task.ps1
```

Feishu notes are named `YYYY-MM-DD_原妙记命名.md`. Imported notes default to `privacy: work` and are not auto-committed or auto-pushed to GitHub.
