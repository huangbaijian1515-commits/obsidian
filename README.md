# Codex + Obsidian Knowledge Vault

This vault is a local-first, Git-versioned knowledge system built around four layers:

- `raw`: traceable source material in `10_Sources/`
- `query`: reviewed atomic knowledge in `20_Query/`
- `wiki`: topic reports and knowledge maps in `40_Wiki/`
- `lint`: quality checks and repair tasks in `50_Lint/`

Obsidian is the source of truth. Codex acts as a local compiler that reads sources, proposes extracted knowledge, suggests links, drafts topic reports, and produces lint reports. Nothing should be promoted into `20_Query/` without human review.

## Daily Capture

1. Save quick links, notes, and mobile shares into `00_Inbox/`.
2. Move valuable items into `10_Sources/` using the source template.
3. Preserve full text, transcript, summary, and URL when available.
4. Mark source status as `captured`, `transcribed`, `extracted`, `reviewed`, or `archived`.

## Weekly Compile

1. Ask Codex to scan `00_Inbox/` and `10_Sources/`.
2. Generate extracted units: viewpoints, judgments, facts, and data.
3. Review candidates manually.
4. Promote durable ideas into `20_Query/` using the query template.
5. Let Codex suggest links, topic membership, duplicates, and contradictions.

## Topic Reports

For any topic, ask Codex to read related query notes and produce a report in `40_Wiki/` with:

- executive summary
- knowledge map
- core claims
- evidence
- tensions and contradictions
- open questions
- next capture or reading tasks

## Lint

Run the local lint script from the vault root:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\vault-lint.ps1
```

The script writes a timestamped report to `50_Lint/`.

## Privacy Defaults

- `privacy: sensitive` and `privacy: work` content should stay local unless explicitly approved.
- NotebookLM and other cloud tools are for public or non-sensitive sources only.
- Private GitHub is acceptable for the vault content you choose to sync, but sensitive company material should use a separate local-only or company-approved vault.
