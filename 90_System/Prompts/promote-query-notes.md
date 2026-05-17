# Prompt: Promote Query Notes

Use this prompt after reviewing extraction candidates.

## Task

Create or update query notes in `20_Query/` only for the approved candidates I identify. Use `90_System/Templates/query-note.md`.

## Rules

- One query note per atomic idea.
- Keep title short and searchable.
- Fill frontmatter completely.
- Set `status: reviewed` only if I explicitly reviewed the content.
- Set `status: draft` when the idea still needs confirmation.
- Add source note links in `source_notes`.
- Suggest `supports` and `contradicts`, but ask before writing uncertain links.

