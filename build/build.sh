#!/usr/bin/env bash
# build/build.sh — build fedora-gnome-bootc-ewt locally (or on VPS) with buildah.
#
# Usage:
#   ./build/build.sh                # build only
#   ./build/build.sh --push         # build and push to ${REGISTRY}/${IMAGE}
#   FEDORA_VERSION=45 ./build/build.sh --push
#
# Env vars:
#   FEDORA_VERSION  (default 44)        — silverblue tag
#   REGISTRY        (default quay.io/ewt-lab) — image namespace
#   IMAGE           (default fedora-gnome-bootc-ewt)
#   PLATFORM        (default linux/amd64)
#
# Requires: buildah, podman (for push), skopeo (alternative push).

set -euo pipefail

FEDORA_VERSION="${FEDORA_VERSION:-44}"
REGISTRY="${REGISTRY:-quay.io/ewt-lab}"
IMAGE="${IMAGE:-fedora-gnome-bootc-ewt}"
PLATFORM="${PLATFORM:-linux/amd64}"

TAG="${FEDORA_VERSION}"
FULL_IMAGE="${REGISTRY}/${IMAGE}:${TAG}"

PUSH=0
[[ ${1:-} == "--push" ]] && PUSH=1

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

echo "==> buildah bud ${FULL_IMAGE} (fedora-${FEDORA_VERSION})"
buildah bud \
    --isolation=chroot \
    --platform="${PLATFORM}" \
    --build-arg "FEDORA_VERSION=${FEDORA_VERSION}" \
    --tag "${FULL_IMAGE}" \
    --file Containerfile \
    "${ROOT}"

if [[ ${PUSH} -eq 1 ]]; then
    echo "==> podman push ${FULL_IMAGE}"
    podman push "${FULL_IMAGE}"
    # Also push :latest pointing at the same image for ergonomics.
    podman tag "${FULL_IMAGE}" "${REGISTRY}/${IMAGE}:latest"
    podman push "${REGISTRY}/${IMAGE}:latest"
fi

echo "==> done. Rebase with:"
echo "    sudo rpm-ostree rebase ostree-unverified-registry:${FULL_IMAGE}"
