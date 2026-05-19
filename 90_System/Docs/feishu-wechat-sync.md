# Feishu WeChat Link Sync

Version 3.0 adds a read-only Feishu IM scanner for WeChat public-account links.

## What It Does

- Reads the Feishu P2P conversation named `黄佰健`.
- Extracts links whose host contains `mp.weixin.qq.com`.
- Writes a local queue item under `90_System/Queue/Wechat/`.
- Optionally invokes Codex CLI with the global `obsidian-wechat-save` skill to save the article into `10_Sources/Wechat/`.
- Records processed URLs in `90_System/State/feishu-wechat-sync-state.json`.

The Feishu side is read-only. The sync uses `contact +search-user` and `im +chat-messages-list`.

## Manual Dry Run

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-wechat-links.ps1 -ContactName "黄佰健" -DaysBack 2 -DryRun
```

## Manual Run

Collect links only:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-wechat-links.ps1 -ContactName "黄佰健" -DaysBack 2
```

Collect links and ask Codex to use the global `obsidian-wechat-save` skill:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-wechat-links.ps1 -ContactName "黄佰健" -DaysBack 2 -SaveWithCodex
```

## Daily Task

Install the daily 23:30 task:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\install-feishu-wechat-daily-task.ps1
```

Check task status and today's logs:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\check-feishu-wechat-daily-task.ps1
```

If you want the task to collect links only and leave saving to a later Codex session:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\install-feishu-wechat-daily-task.ps1 -CollectOnly
```

## Notes

- The global `obsidian-wechat-save` skill is not a shell executable. The scheduled task invokes `codex exec` when `-SaveWithCodex` is enabled.
- If Codex CLI is unavailable or saving fails, the URL remains in the local queue and is not marked as saved.
- The script does not send, reply, edit, delete, upload, or download anything in Feishu.
