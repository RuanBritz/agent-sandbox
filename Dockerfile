FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq ripgrep tini \
      python3 python3-pip python3-venv build-essential \
 && rm -rf /var/lib/apt/lists/*

# Rename the image's built-in "node" user (uid 1000) to "agent". The agent never runs as root.
RUN usermod -l agent -d /home/agent -m node && groupmod -n agent node \
 && mkdir -p /workspace && chown agent:agent /workspace

# Optional: preinstall agent CLIs (set to "false" to skip). They live in /opt, outside the
# home volume, so rebuilding the image actually updates them.
ARG INSTALL_CLAUDE_CODE=true
RUN if [ "$INSTALL_CLAUDE_CODE" = "true" ]; then npm install -g --prefix /opt/agent-tools @anthropic-ai/claude-code; fi
ARG INSTALL_PI=true
RUN if [ "$INSTALL_PI" = "true" ]; then npm install -g --prefix /opt/agent-tools --ignore-scripts @earendil-works/pi-coding-agent; fi
ARG INSTALL_CODEX=true
RUN if [ "$INSTALL_CODEX" = "true" ]; then npm install -g --prefix /opt/agent-tools @openai/codex; fi

USER agent
ENV HOME=/home/agent \
    NPM_CONFIG_PREFIX=/home/agent/.npm-global \
    VIRTUAL_ENV=/home/agent/.venv \
    DISABLE_AUTOUPDATER=1
ENV PATH=/opt/agent-tools/bin:/home/agent/.venv/bin:/home/agent/.local/bin:/home/agent/.npm-global/bin:$PATH

# User-owned Python venv and npm prefix, so the agent can install packages without root
RUN python3 -m venv $VIRTUAL_ENV && pip install --no-cache-dir --upgrade pip

# Pre-create pi's config dir; otherwise Docker creates it as root when mounting models.json into it
RUN mkdir -p /home/agent/.pi/agent

WORKDIR /workspace
ENTRYPOINT ["tini", "--"]
CMD ["bash"]
