# Agent sandbox

## Run
    .\sandbox.ps1                              # bash in a fresh container; removed on exit
    .\sandbox.ps1 C:\code\foo                  # also mount a folder at /mnt/foo and start there
    .\sandbox.ps1 C:\code\foo D:\data\bar:ro   # several folders; ":ro" = read-only
    .\sandbox.ps1 -Agent claude C:\code\foo    # start Claude Code, Codex or pi directly
    .\sandbox.ps1 -Memory 8g -Cpus 4 C:\code\foo   # defaults: 4g, 2 CPUs
    .\sandbox.ps1 -Port 3000,8080:80 C:\code\foo   # localhost:3000 -> 3000, localhost:8080 -> 80

`./workspace` is always mounted at `/workspace`. Each terminal gets its own container; the
home volume (logins, pip/npm installs, agent config) is shared and persists.
The image is rebuilt automatically when the Dockerfile changes.

Right-click menu: `.\context-menu\install.ps1` adds an "Agent sandbox" submenu for folders
and asks which entries to put in it (bash, Claude Code, Codex, pi; Windows 11: under "Show more
options"). Re-run it to change the
selection, or pass `-Agent bash,codex` to skip the prompt. Remove them all with
`.\context-menu\uninstall.ps1`. Entries use `context-menu\icons\<agent>.ico` if it exists,
otherwise the Docker Desktop icon; the submenu itself uses `icons\menu.ico`.
It also asks which ports every entry should publish (or pass `-Port 3000,5173`).

## What the agent can see
Everything in `./workspace` and in the folders you mount, including `.env` files and keys.
Mount only what the agent needs, and add `:ro` where it shouldn't write. You get a warning if
a mounted repo's `.git/config` has credentials in a remote URL.

## Config
- `agent-config/<agent>/` is copied into that agent's config dir each time a container starts,
  overwriting files with the same name (deleting a file here doesn't delete the copy):
  - `agent-config/claude/` → `~/.claude/` (`CLAUDE.md`, `settings.json`, `agents/`, `commands/`, ...)
  - `agent-config/codex/` → `~/.codex/` (`AGENTS.md`, `config.toml`, ...)
  - `agent-config/pi/` → `~/.pi/agent/` (`AGENTS.md`, `models.json`, `settings.json`, ...)
- Claude Code, Codex and pi are baked into the image (`/opt/agent-tools`); rebuild to update them.
- Codex runs with its own sandbox off (the container is the sandbox). No ports are published
  unless you pass `-Port`, so sign in with `codex login --device-auth` or an `OPENAI_API_KEY`.

## Reset
    docker compose down -v        # wipes the agent's home volume (logins, installs)

## Rules of thumb
- Never mount /var/run/docker.sock: it gives the agent root on your host.
- Only mount what the agent needs.
- No ports are published unless you pass `-Port`. Those are bound to 127.0.0.1, so only your
  PC can reach them, not the LAN. A server inside must listen on `0.0.0.0`, not `localhost`
  (e.g. `npm run dev -- --host 0.0.0.0`, `python -m http.server 3000`). If a host port is
  already taken (e.g. by another sandbox), it's skipped with a warning.
- The agent has full internet and LAN access. Use scoped or low-limit API keys.
