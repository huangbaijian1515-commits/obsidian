# Lint

Vault quality reports live here.

Lint should detect:

- missing frontmatter fields
- unprocessed source notes
- query notes without source evidence
- orphan notes
- duplicated concepts
- possible contradictions
- stale or low-confidence claims

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\vault-lint.ps1
```
