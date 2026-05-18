#!/usr/bin/env bash
# Local multi-arch builder for the ECC dev image.
# Produces linux/amd64 + linux/arm64 manifests using docker buildx + QEMU.
#
# Usage:
#   ./build-multi-arch.sh                    # build only (no push), output to local docker
#   PUSH=1 ./build-multi-arch.sh             # push to default registry
#   IMAGE=ghcr.io/foo/bar TAG=v1 PUSH=1 ./build-multi-arch.sh
#
# Requires:
#   docker buildx (Docker Desktop or Linux with buildx plugin)
#   QEMU binfmt registered (Docker Desktop ships it; Linux: tonistiigi/binfmt)

set -euo pipefail

IMAGE="${IMAGE:-docker.weloyalty.net/devtools/everything-claude-code}"
TAG="${TAG:-dev}"
PUSH="${PUSH:-0}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Ensure binfmt is registered for cross-arch emulation on Linux hosts.
if ! docker buildx inspect ecc-builder >/dev/null 2>&1; then
  echo "[setup] creating buildx builder 'ecc-builder'"
  docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null 2>&1 || true
  docker buildx create --name ecc-builder --use --bootstrap
else
  docker buildx use ecc-builder
fi

build_args=(
  --platform "${PLATFORMS}"
  --file "${REPO_ROOT}/docker/Dockerfile"
  --tag "${IMAGE}:${TAG}"
)

if [[ "${PUSH}" == "1" ]]; then
  build_args+=(--push)
else
  # Local-only build cannot load multi-arch into the local docker store
  # (multi-platform manifests aren't supported by the classic store).
  # We export to OCI tar instead so the build at least validates.
  build_args+=(--output "type=oci,dest=${REPO_ROOT}/ecc-image-${TAG}.tar")
  echo "[info] PUSH=0 -> writing OCI tar to ecc-image-${TAG}.tar"
  echo "[info] to load a single-arch image into local docker, run:"
  echo "       docker buildx build --platform linux/amd64 -t ${IMAGE}:${TAG} -f docker/Dockerfile --load ."
fi

echo "[build] ${IMAGE}:${TAG} for ${PLATFORMS}"
docker buildx build "${build_args[@]}" "${REPO_ROOT}"

echo "[done] manifest: ${IMAGE}:${TAG}"
if [[ "${PUSH}" == "1" ]]; then
  docker buildx imagetools inspect "${IMAGE}:${TAG}"
fi
