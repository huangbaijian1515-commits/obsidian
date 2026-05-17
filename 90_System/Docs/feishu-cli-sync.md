# Feishu CLI Sync

This vault treats Feishu as read-only input.

## Safety Contract

Allowed:

- list readable Feishu minutes or meeting records
- read metadata, transcript, AI summary, and action items
- download recording files that your account can access
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

For local transcription, install:

```powershell
pip install faster-whisper
```

Install `ffmpeg` separately and make sure it is available on `PATH`.

## Sync From JSON

The sync script accepts JSON arrays or objects with `items`, `data.items`, or `minutes`.

Common fields:

- `id`, `token`, `minute_token`, `meeting_id`, or `object_token`
- `title`, `name`, `topic`, or `meeting_topic`
- `date`, `start_time`, `created_at`, `create_time`, or `meeting_start_time`
- `updated_at`, `update_time`, `modified_at`, or `modified_time`
- `summary`, `abstract`, or `ai_summary`
- `transcript`, `transcript_text`, `content`, `text`, or `minutes`
- `media_path`, `recording_path`, `audio_path`, or `video_path`
- `media_url`, `recording_url`, or `download_url`

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-minutes.ps1 -InputJson "G:\path\to\feishu-minutes.json" -DaysBack 7
```

## Daily Sync

After `90_System/Config/feishu-sync.json` contains a confirmed read-only list/export command:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\install-feishu-daily-task.ps1
```

The task runs daily at 23:30 and writes logs to `90_System/Logs/`.
