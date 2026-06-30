# NodeBackend Runtime

`NodeBackend` is the AVA backend runtime on port `8080`.

## Start

```powershell
cd D:\AVA_Project
.\ava_server_control.ps1 restart
```

Or:

```powershell
cd D:\AVA_Project\NodeBackend
npm install --no-audit --no-fund
npm start
```

## Runtime Directories

- `NodeBackend/AppUpdates`: finalized platform update packages.
- `NodeBackend/ChatUploads`: chat attachments.
- `NodeBackend/AiWorkspace`: per-user AVA AI workspace files.
- `NodeBackend/LiveKit`: native AZOOM SFU runtime.
- `NodeBackend/NotivaAudio`: uploaded meeting audio.
- `NodeBackend/logs`: backend stdout/stderr and pid files.

These directories are runtime data and are ignored except for intentional release packages under `NodeBackend/AppUpdates`.
