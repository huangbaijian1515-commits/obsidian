# Changelog

## v2.1.1 - 2026-05-18

- Fixed Feishu Minutes DOCX selection so only documents titled `文字记录` are imported as `Feishu Transcript`.
- Imported documents titled `智能纪要` only as `Feishu Summary`, with `status: summarized` and `needs_transcription: true`.
- Added `transcript_unavailable_reason` for summary-only or placeholder Feishu source notes.
- Fixed Windows PowerShell encoding and argument-passing issues that could prevent Chinese `drive +search` queries from finding the correct DOCX.
- Kept the Feishu sync read-only: no Feishu uploads, edits, recording downloads, or local transcription are run in this stage.

