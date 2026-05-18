# Feishu CLI Sync

This vault treats Feishu as read-only input.

## Safety Contract

Allowed:

- list readable Feishu minutes or meeting records
- read metadata, transcript, AI summary, and action items
- write local Obsidian notes and local state files

Forbidden unless explicitly approved before execution:

- edit Feishu docs
- update Feishu docs
- delete or remove Feishu docs
- upload files to Feishu
- move Feishu files
- comment on Feishu docs
- write back to Feishu in any form

## Setup

Run:

```powershell
cd "G:\AI project\obsidian"
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\feishu-probe.ps1
```

If needed, install and authenticate Feishu CLI:

```powershell
lark-cli auth login --recommend
```

Current stage: import already-transcribed Feishu content first. Do not install `ffmpeg` or `faster-whisper` yet unless you decide to enable local transcription later.

Feishu `minutes get` returns basic minute metadata but not the transcript body directly. The sync script searches Drive by the minute title, selects a related DOCX, and exports it as read-only Markdown through:

```powershell
lark-cli.cmd drive +search --query <minute-title> --as user --format json
lark-cli.cmd drive +export --as user --token <docx-token> --doc-type docx --file-extension markdown
```

Selection priority:

1. DOCX title containing `文字记录`: imported as `Feishu Transcript`, `status: transcribed`, `needs_transcription: false`
2. DOCX title containing `智能纪要`: imported as `Feishu Summary`, `status: summarized`, `needs_transcription: true`, `transcript_unavailable_reason: "no_text_record_docx_found"`
3. Other matching DOCX: treated as `unknown_doc` and not imported as a transcript

The exported Markdown is saved under `10_Sources/Attachments/Feishu/Exports/`. `文字记录` and `智能纪要` are separate document classes: a summary-only import never writes a `Feishu Transcript` section.

The Feishu app/user must approve these read scopes when prompted:

- `minutes:minutes.search:read`
- `minutes:minutes:readonly`
- `minutes:minutes.basic:read`

If you see `need_user_authorization`, re-run:

```powershell
lark-cli auth login --recommend
```

Then approve the minutes read scopes in the browser.

## Sync From Feishu CLI

Run a dry run first:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-minutes.ps1 -DaysBack 7 -DryRun
```

Then run the sync:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-minutes.ps1 -DaysBack 7
```

For a specific date range, prefer explicit window dates:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-minutes.ps1 -StartDate 2026-05-01 -EndDate 2026-05-18 -DryRun -RequestDelayMs 1500
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-minutes.ps1 -StartDate 2026-05-01 -EndDate 2026-05-18 -RequestDelayMs 1500
```

For full-history syncs, do not use one huge `DaysBack` range. Feishu search can return an incomplete slice for very large windows even when pagination is enabled. Use the history wrapper, which splits the range into smaller windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-history.ps1 -StartDate 2023-01-01 -EndDate 2026-05-18 -WindowDays 30 -DryRun -RequestDelayMs 1500
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-history.ps1 -StartDate 2023-01-01 -EndDate 2026-05-18 -WindowDays 30 -RequestDelayMs 1500
```

The sync retries `9499 too many request` errors with exponential backoff and saves local state after each successful import, so interrupted history runs can be restarted safely.

Imported Feishu source notes include local rule-based content classification:

```yaml
content_kind: interview|meeting|personal_recording|unknown
content_kind_confidence: low|medium|high
content_kind_reason: ""
```

The classifier reads transcript or summary content first and uses the title only as a low-confidence fallback.

Backfill existing Feishu notes with:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\classify-feishu-source-notes.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\classify-feishu-source-notes.ps1
```

The script uses read-only commands:

```powershell
lark-cli.cmd minutes +search --as user --start <date> --end <date> --page-size 30 --format json
lark-cli.cmd api GET /open-apis/minutes/v1/minutes/<minute-token> --as user --format json
```

Minutes without `文字记录` or `智能纪要` are skipped by default. To create placeholder notes for them:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-minutes.ps1 -DaysBack 7 -CreatePlaceholderForUntranscribed
```

## Sync From JSON

The sync script accepts JSON arrays or objects with `items`, `data.items`, or `minutes`.

Common fields:

- `id`, `token`, `minute_token`, `meeting_id`, or `object_token`
- `title`, `name`, `topic`, or `meeting_topic`
- `date`, `start_time`, `created_at`, `create_time`, or `meeting_start_time`
- `updated_at`, `update_time`, `modified_at`, or `modified_time`
- `summary`, `abstract`, or `ai_summary`
- `transcript`, `transcript_text`, `content`, `text`, or `minutes`

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-minutes.ps1 -InputJson "G:\path\to\feishu-minutes.json" -DaysBack 7
```

## Daily Sync

After the dry-run output looks right:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\install-feishu-daily-task.ps1
```

The task runs daily at 23:30 and writes logs to `90_System/Logs/`.
