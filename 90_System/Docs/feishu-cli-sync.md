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

The script uses read-only commands:

```powershell
lark-cli.cmd minutes +search --as user --start <date> --end <date> --page-size 30 --format json
lark-cli.cmd minutes minutes get --as user --params '{"minute_token":"...","user_id_type":"open_id"}' --format json
```

Untranscribed minutes are skipped by default. To create placeholder notes for them:

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
