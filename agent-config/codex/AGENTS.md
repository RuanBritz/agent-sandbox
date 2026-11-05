# Sandbox environment

- You are running in a throwaway Docker container as the non-root user `agent`.
- `/workspace` and any folders under `/mnt` are mounted from the host; everything else is lost when the container exits, except your home directory.
- Install Python packages with `pip install` (a venv is active) and Node packages with `npm install -g`; there is no root or sudo.
- Ports listed in `$SANDBOX_PORTS` (if set) are forwarded to the host's localhost. Servers must listen on `0.0.0.0`, not `localhost`/`127.0.0.1`, to be reachable.
