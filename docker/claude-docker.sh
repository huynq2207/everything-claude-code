#!/usr/bin/env bash
# Wrapper that drops the dev into an interactive Claude session inside the
# prebuilt container, with the current working directory mounted at /workspace.
#
# Usage:
#   ./claude-docker.sh                  # interactive bash
#   ./claude-docker.sh claude           # launch Claude Code REPL
#   ./claude-docker.sh claude /code-review
#
# Auth:
#   - OAuth team plan:  ensure ~/.claude/credentials.json exists on host.
#   - API key (BYOK):   export ANTHROPIC_API_KEY before running.

set -euo pipefail

IMAGE="${ECC_IMAGE:-ghcr.io/huynq2207/everything-claude-code:latest}"
PROJECT_DIR="${PROJECT_DIR:-$PWD}"

# Detect which credentials are available on the host.
mounts=(
  -v "${PROJECT_DIR}:/workspace"
)

if [[ -f "${HOME}/.claude/credentials.json" ]]; then
  mounts+=(-v "${HOME}/.claude/credentials.json:/root/.claude/credentials.json:ro")
fi

if [[ -d "${HOME}/.ssh" ]]; then
  mounts+=(-v "${HOME}/.ssh:/root/.ssh:ro")
fi

if [[ -f "${HOME}/.gitconfig" ]]; then
  mounts+=(-v "${HOME}/.gitconfig:/root/.gitconfig:ro")
fi

env_args=()
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  env_args+=(-e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")
fi

# Forward git identity so commits made inside the container are attributed to
# the dev on the host.
git_name="$(git config --global user.name 2>/dev/null || true)"
git_email="$(git config --global user.email 2>/dev/null || true)"
if [[ -n "${git_name}" ]]; then
  env_args+=(-e "GIT_AUTHOR_NAME=${git_name}" -e "GIT_COMMITTER_NAME=${git_name}")
fi
if [[ -n "${git_email}" ]]; then
  env_args+=(-e "GIT_AUTHOR_EMAIL=${git_email}" -e "GIT_COMMITTER_EMAIL=${git_email}")
fi

exec docker run --rm -it \
  "${mounts[@]}" \
  "${env_args[@]}" \
  --workdir /workspace \
  "${IMAGE}" \
  "$@"
