# Prompt: Vault Lint

Use this prompt from the vault root.

## Task

Inspect the vault for quality problems and write a lint report into `50_Lint/`.

## Checks

- source notes missing required frontmatter
- source notes stuck in `captured` or `transcribed`
- query notes without source evidence
- query notes with low confidence but many links
- possible duplicate query notes
- possible contradictions
- orphan notes with no backlinks or topic membership
- stale reviewed notes with no `last_reviewed`
- privacy issues, especially sensitive material that may be unsuitable for cloud sync

## Output

Create an actionable report with:

- summary
- exact file paths
- recommended repairs
- priority
- whether the repair should be done by Codex or by human review

