# Feishu WeChat Link Sync

Version 3.0 adds a read-only Feishu IM scanner for WeChat public-account links.

## What It Does

- Reads the Feishu P2P conversation named `黄佰健`.
- Extracts links whose host contains `mp.weixin.qq.com`.
- Writes a local queue item under `90_System/Queue/Wechat/`.
- Immediately creates a `status: captured` source note under `10_Sources/Wechat/` for every discovered link.
- Leaves article saving to Codex App, which can use the global `obsidian-wechat-save` skill to save the article into `10_Sources/Wechat/`.
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

Collect links and attempt a manual Codex CLI save:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\sync-feishu-wechat-links.ps1 -ContactName "黄佰健" -DaysBack 2 -SaveWithCodex
```

This is not the recommended scheduled path. The reliable scheduled path is:

1. Windows Task Scheduler collects links into `90_System/Queue/Wechat/` and creates captured source notes in `10_Sources/Wechat/`.
2. Codex App automation enriches captured notes when WeChat article content can be fetched.

## Daily Task

Install the daily 23:30 collection task:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\install-feishu-wechat-daily-task.ps1
```

Check task status and today's logs:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\check-feishu-wechat-daily-task.ps1
```

If you explicitly want to test Codex CLI saving from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\90_System\Scripts\install-feishu-wechat-daily-task.ps1 -SaveWithCodex
```

## Notes

- The global `obsidian-wechat-save` skill is not a shell executable. Do not treat it as a Windows global command.
- `codex exec` is supported for manual experiments, but it is not the default Task Scheduler execution path.
- If Codex CLI is unavailable or saving fails, the URL remains in the local queue and is not marked as saved.
- The script does not send, reply, edit, delete, upload, or download anything in Feishu.
