# V2 Roadmap

V2 focuses on local-first semi-automation. The vault should become easier to feed, but query promotion remains human-reviewed.

## Implemented In V2.0

- Generic source import from title, URL, optional local file, and optional URL fetch.
- YouTube source note creation with optional `yt-dlp` metadata capture.
- Feishu minutes export import from local text or Markdown files.
- Extraction draft generation from source notes.

## Next V2.x Candidates

- Install and integrate `yt-dlp` subtitle download.
- Confirm the exact read-only `lark-cli` command for Feishu Minutes in this tenant and wire it into `90_System/Config/feishu-sync.json`.
- Add an Android-friendly capture file format such as `00_Inbox/mobile-capture.md`.
- Add query promotion automation that creates draft notes from approved extraction items.
- Add duplicate and backlink suggestion reports.

## Implemented In V2.1

- Read-only Feishu readiness probe.
- Feishu minutes sync state and duplicate prevention.
- Feishu source note naming as `YYYY-MM-DD_原妙记命名.md`.
- Local `faster-whisper` transcription hook for downloaded media.
- Windows daily task installer for 23:30 sync.

## Privacy Rule

Work and sensitive material stays local unless explicitly approved for GitHub or cloud AI.
