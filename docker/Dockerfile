# syntax=docker/dockerfile:1.7
# Pre-built dev image: Claude Code CLI + ECC agents/commands/skills/rules.
# Devs mount their project at /workspace and run interactive Claude sessions.

FROM node:20-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/root/.local/bin:${PATH}" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Base CLI utilities used across dev workflows.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        less \
        openssh-client \
        python3 \
        python3-pip \
        ripgrep \
        sudo \
        unzip \
        vim \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI from official apt repo.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI (official installer).
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && claude --version

# Lightweight scanners frequently called from agents.
RUN npm install -g @anthropic-ai/claude-code-action-cli@latest || true \
    && npm cache clean --force

# Pre-bake the ECC plugin (agents, commands, skills, rules, hooks).
ARG ECC_DIR=/opt/ecc
COPY agents     ${ECC_DIR}/agents
COPY commands   ${ECC_DIR}/commands
COPY skills     ${ECC_DIR}/skills
COPY rules      ${ECC_DIR}/rules
COPY hooks      ${ECC_DIR}/hooks
COPY install.sh ${ECC_DIR}/install.sh

# Symlink the plugin into the root user's ~/.claude so the CLI picks it up.
RUN mkdir -p /root/.claude \
    && ln -sf ${ECC_DIR}/agents   /root/.claude/agents   \
    && ln -sf ${ECC_DIR}/commands /root/.claude/commands \
    && ln -sf ${ECC_DIR}/skills   /root/.claude/skills   \
    && ln -sf ${ECC_DIR}/rules    /root/.claude/rules    \
    && ln -sf ${ECC_DIR}/hooks    /root/.claude/hooks

# Sane defaults — devs mount their repo here.
WORKDIR /workspace

# Show what's baked in when the image is first inspected.
LABEL org.opencontainers.image.title="everything-claude-code-dev" \
      org.opencontainers.image.description="Claude Code CLI + ECC agents preinstalled" \
      org.opencontainers.image.source="https://github.com/huynq2207/everything-claude-code"

# Interactive bash by default; override with `docker run ... claude /code-review`.
CMD ["bash"]
