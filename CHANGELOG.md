# Changelog

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
