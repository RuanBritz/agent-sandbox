# Agent sandbox

## Run
    .\sandbox.ps1                              # bash in a fresh container; removed on exit
    .\sandbox.ps1 C:\code\foo                  # also mount a folder at /mnt/foo and start there
    .\sandbox.ps1 C:\code\foo D:\data\bar:ro   # several folders; ":ro" = read-only
    .\sandbox.ps1 -Agent claude C:\code\foo    # start Claude Code (skip-permissions) or pi directly
    .\sandbox.ps1 -Memory 8g -Cpus 4 C:\code\foo   # defaults: 4g, 2 CPUs

`./workspace` is always mounted at `/workspace`. Each terminal gets its own container; the
home volume (logins, pip/npm installs, agent config) is shared and persists.
The image is rebuilt automatically when the Dockerfile changes.

Right-click menu: `.\install-context-menu.ps1` adds "Open in agent sandbox", "Open Claude
Code here" and "Open pi here" for folders (Windows 11: under "Show more options").
Remove with `-Uninstall`.

## Hiding secrets
Anything matching `.sandboxignore` (e.g. `*.env`, `.ssh`, `*.pem`) in a mounted folder is
replaced by an empty read-only placeholder; the script lists what it hid on startup.

- The scan runs once at startup. A matching file created later (e.g. `vercel env pull`, or
  copying `.env.example` to `.env` while the sandbox runs) is **not** hidden; restart the sandbox.
- Mounting a folder that is itself ignored (e.g. `~\.aws`, or anything inside `.ssh`) is refused.
- `.git/config` isn't hidden (git needs it); you get a warning if a remote URL embeds credentials.
- The scan walks the whole mounted tree, so mount project folders rather than a home dir or drive.

## Config
- `pi/models.json` is mounted read-only as pi's `models.json`.
- Claude Code and pi are baked into the image (`/opt/agent-tools`); rebuild to update them.

## Reset
    docker compose down -v        # wipes the agent's home volume (logins, installs)

## Rules of thumb
- Never mount /var/run/docker.sock: it gives the agent root on your host.
- Only mount what the agent needs; check the "Hidden from agent" list.
- No ports are published: nothing on your PC or LAN can connect into the container.
- The agent has full internet and LAN access. Use scoped or low-limit API keys.
