# Operating Manual

## Layer Contract

### Raw / Sources

`10_Sources/` is for evidence preservation. A source note can be messy, long, and incomplete, but it must stay traceable.

Allowed content:

- clipped web pages
- copied WeChat articles
- YouTube metadata and transcript
- Feishu minutes export
- meeting notes
- interview records
- sheet-derived summaries
- manual capture records

Do not treat a source note as a trusted knowledge unit. Treat it as material to compile.

### Query

`20_Query/` is for reviewed atomic knowledge. Every query note should be small enough to reuse in different topics.

Promotion rules:

- one note, one durable idea
- must cite at least one source note unless it is explicitly personal reasoning
- must have status and confidence
- link suggestions should be reviewed before being accepted

### Wiki

`40_Wiki/` contains generated synthesis. Wiki reports are allowed to be regenerated as the query layer improves.

### Lint

`50_Lint/` contains quality reports. Lint reports create repair work for the next compile cycle.

## Capture Policy

### Web / WeChat / Articles

Use Obsidian Web Clipper or manual copy. Save the full article when allowed, plus URL and capture date.

### YouTube

Save:

- URL
- title
- channel
- published date if available
- transcript or subtitle file
- your reason for keeping it

NotebookLM may be used for public videos, but the final source note belongs in this vault.

### Feishu Minutes

Export or copy:

- meeting title
- participants if appropriate
- date
- transcript
- generated summary
- action items

For work-sensitive meetings, keep `privacy: work` or `privacy: sensitive` and do not send to cloud tools.

### Android Capture

Use Obsidian Mobile or a plain Markdown editor to append rough links and notes into `00_Inbox/`.

Avoid editing heavily on mobile unless necessary. Compile from desktop.

## Git Policy

Suggested commit styles:

- `capture: add source notes`
- `extract: draft query candidates`
- `review: promote query notes`
- `wiki: generate topic report`
- `lint: add vault quality report`

Avoid committing sensitive work material to private GitHub unless it is approved for that storage boundary.

