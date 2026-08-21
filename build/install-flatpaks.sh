#!/usr/bin/env bash
# build/install-flatpaks.sh — install system flatpaks listed in
# build/flatpak-list.txt after a fresh rebase. Idempotent.
set -euo pipefail

LIST="$(cd "$(dirname "$0")" && cat flatpak-list.txt)"

# Ensure flathub remote exists.
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

for app in ${LIST}; do
    if flatpak list --system | grep -q "^${app}\b"; then
        echo "skip: ${app}"
        continue
    fi
    echo "install: ${app}"
    flatpak install --system --noninteractive flathub "${app}"
done

echo "==> flatpak install complete"
