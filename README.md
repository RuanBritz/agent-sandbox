# Agent sandbox

## Run
    .\sandbox.ps1                              # bash in a fresh container; removed on exit
    .\sandbox.ps1 C:\code\foo                  # also mount a folder at /mnt/foo and start there
    .\sandbox.ps1 C:\code\foo D:\data\bar:ro   # several folders; ":ro" = read-only
    .\sandbox.ps1 -Agent claude C:\code\foo    # start Claude Code, Codex or pi directly
    .\sandbox.ps1 -Memory 8g -Cpus 4 C:\code\foo   # defaults: 4g, 2 CPUs

`./workspace` is always mounted at `/workspace`. Each terminal gets its own container; the
home volume (logins, pip/npm installs, agent config) is shared and persists.
The image is rebuilt automatically when the Dockerfile changes.

Right-click menu: `.\context-menu\install.ps1` adds "Open in agent sandbox" for folders
(Windows 11: under "Show more options"). Claude Code, Codex and pi entries are commented out
in the script; uncomment to add them. Remove them with `.\context-menu\uninstall.ps1`.

## What the agent can see
Everything in `./workspace` and in the folders you mount, including `.env` files and keys.
Mount only what the agent needs, and add `:ro` where it shouldn't write. You get a warning if
a mounted repo's `.git/config` has credentials in a remote URL.

## Config
- `pi/models.json` is mounted read-only as pi's `models.json`.
- Claude Code, Codex and pi are baked into the image (`/opt/agent-tools`); rebuild to update them.
- Codex runs with its own sandbox off (the container is the sandbox). No ports are published,
  so sign in with `codex login --device-auth` or an `OPENAI_API_KEY`.

## Reset
    docker compose down -v        # wipes the agent's home volume (logins, installs)

## Rules of thumb
- Never mount /var/run/docker.sock: it gives the agent root on your host.
- Only mount what the agent needs.
- No ports are published: nothing on your PC or LAN can connect into the container.
- The agent has full internet and LAN access. Use scoped or low-limit API keys.
