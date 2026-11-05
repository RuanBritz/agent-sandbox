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

Right-click menu: `.\context-menu\install.ps1` adds an "Agent sandbox" submenu for folders
and asks which entries to put in it (bash, Claude Code, Codex, pi; Windows 11: under "Show more
options"). Re-run it to change the
selection, or pass `-Agent bash,codex` to skip the prompt. Remove them all with
`.\context-menu\uninstall.ps1`. Entries use `context-menu\icons\<agent>.ico` if it exists,
otherwise the Docker Desktop icon.

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
- Codex runs with its own sandbox off (the container is the sandbox). No ports are published,
  so sign in with `codex login --device-auth` or an `OPENAI_API_KEY`.

## Reset
    docker compose down -v        # wipes the agent's home volume (logins, installs)

## Rules of thumb
- Never mount /var/run/docker.sock: it gives the agent root on your host.
- Only mount what the agent needs.
- No ports are published: nothing on your PC or LAN can connect into the container.
- The agent has full internet and LAN access. Use scoped or low-limit API keys.
