# Changelog

## v3.0.3 - 2026-05-28

- Fixed WeChat captured notes that used unreadable placeholder titles by fetching article title and author with Defuddle before creating the source note.
- Replaced the four affected placeholder notes with readable extracted notes using real titles, authors, URLs, Feishu context, and digest sections.

## v3.0.2 - 2026-05-28

- Made the Feishu WeChat scanner create an Obsidian `status: captured` source note immediately for every discovered WeChat URL.
- Added queue frontmatter updates with `note_path` so links are still visible in Obsidian even when WeChat article extraction is blocked.
- Added fatal error logging before script exit so Task Scheduler failures produce diagnosable logs.
- Documented the new guaranteed captured-note behavior for WeChat links.

## v3.0.1 - 2026-05-23

- Fixed the Feishu WeChat scheduled task save step by resolving Codex CLI from the known desktop install path when Task Scheduler does not inherit the interactive PATH.
- Fixed the non-interactive Codex invocation to use supported `codex exec` flags.
- Kept failed article saves recoverable by preserving queued link files and marking state as `queued` instead of replacing them with unrecoverable `error` entries.
- Changed the Windows scheduled task default to collection-only; Codex App automation is responsible for consuming queued links with the global `obsidian-wechat-save` skill.

## v3.0.0 - 2026-05-20

- Added a read-only Feishu IM scanner for the P2P conversation `黄佰健`.
- Extracted `mp.weixin.qq.com` links from Feishu messages and stored a local queue in `90_System/Queue/Wechat/`.
- Added optional Codex CLI invocation so the global `obsidian-wechat-save` skill can save articles into `10_Sources/Wechat/`.
- Added daily Windows Task Scheduler install and check scripts for the 23:30 Feishu WeChat link sync.
- Added state and log tracking for processed WeChat links without editing Feishu or auto-pushing to GitHub.

## v2.1.9 - 2026-05-19

- Changed new Feishu Minutes source note output to `10_Sources/Feishu-minutes`.
- Updated Feishu classification backfill to scan the dedicated Feishu Minutes folder while remaining compatible with older root-level source notes.
- Documented the dedicated Feishu Minutes storage location.

## v2.1.8 - 2026-05-19

- Enhanced the Feishu daily scheduled task installer to include request throttling and print verification details after registration.
- Added a read-only scheduled task checker that reports task status, last/next run times, result code, and today's Feishu sync logs.
- Documented install, check, and dry-run commands for daily Feishu Minutes scanning.

## v2.1.7 - 2026-05-18

- Raised the weight of interview flow signals such as `自我介绍`.
- Added `看机会` and `离职` as strong interview motivation signals.
- Prevented generic business terms such as budget, strategy, metrics, plans, and risks from overriding strong interview evidence.

## v2.1.6 - 2026-05-18

- Sanitized Feishu Drive search queries before looking up related DOCX files.
- Truncated Drive search queries to Feishu's 30-character limit to avoid `99992402 field validation failed`.
- Decoded HTML entities and removed shell-sensitive ampersands from search text so long or encoded titles do not break `.cmd` invocation.

## v2.1.5 - 2026-05-18

- Added explicit `StartDate` and `EndDate` support to Feishu Minutes sync.
- Added `sync-feishu-history.ps1` for date-windowed history syncs, avoiding incomplete results from very large Feishu search windows.
- Updated full-history guidance to use 30-day windows with existing rate limiting, retries, and per-item state saves.

## v2.1.4 - 2026-05-18

- Added local content-based classification for Feishu source notes with `content_kind`, `content_kind_confidence`, and `content_kind_reason`.
- Updated Feishu sync dry-run and state output to include content classification.
- Added a history backfill script for classifying existing Feishu source notes without using cloud AI.

## v2.1.3 - 2026-05-18

- Added Feishu API throttling with `RequestDelayMs`, rate-limit detection, and exponential backoff retries for `9499 too many request` errors.
- Added per-item error continuation so one failing minute is logged without stopping the whole sync by default.
- Saved sync state after each successful import so interrupted full-history runs can resume without duplicating completed notes.

## v2.1.2 - 2026-05-18

- Added paginated Feishu Minutes search with `--page-token` so longer date windows can import more than one page of results.
- Required related DOCX titles to match the current minute title before importing them, preventing broad Drive search results from attaching another meeting's transcript.
- Kept the sync read-only and preserved the existing `DaysBack`, dry-run, transcript, summary, and placeholder behavior.

## v2.1.1 - 2026-05-18

- Fixed Feishu Minutes DOCX selection so only documents titled `文字记录` are imported as `Feishu Transcript`.
- Imported documents titled `智能纪要` only as `Feishu Summary`, with `status: summarized` and `needs_transcription: true`.
- Added `transcript_unavailable_reason` for summary-only or placeholder Feishu source notes.
- Fixed Windows PowerShell encoding and argument-passing issues that could prevent Chinese `drive +search` queries from finding the correct DOCX.
- Kept the Feishu sync read-only: no Feishu uploads, edits, recording downloads, or local transcription are run in this stage.
