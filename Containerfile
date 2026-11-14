# syntax=docker/dockerfile-upstream:1.7
#
# fedora-gnome-bootc-ewt — Fedora Atomic GNOME image with personal customizations.
#
# Build (local / VPS — CI uses .github/workflows/build.yml):
#   ./build/build.sh
# which runs:
#   buildah bud --isolation=chroot \
#     --build-arg FEDORA_VERSION=45 \
#     -t ghcr.io/dverdonschot/fedora-gnome-bootc-ewt:45 \
#     -f Containerfile .
#
# The resulting image is an ostree-native-container; install it with:
# (substitute /dev/sda with your target disk):
#   sudo bootc install to-disk --filesystem=xfs \
#       ostree-unverified-registry:ghcr.io/dverdonschot/fedora-gnome-bootc-ewt:45 /dev/sda
#
# …or rebase an existing Fedora Atomic install to it:
#
#   sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/dverdonschot/fedora-gnome-bootc-ewt:45
#
# Notes:
# - Fedora Atomic puts every package in /usr; /usr/local is a symlink to /var/usrlocal
#   and is not layer-friendly. Helper scripts go in /usr/local/bin via COPY (single
#   files, no symlink dance).
# - /usr/lib/systemd/system-preset/ is the supported way to flip defaults in ostree
#   images without touching the unit files themselves.
# - /usr/lib/bootc/install/*.toml is the supported way to set install-time kargs
#   (applied when the user runs `bootc install`). rpm-ostree kargs is broken inside
#   container builds (see coreos/rpm-ostree#3738); the bootc install config is the
#   future-proof replacement.
# - Container runtime is `podman-docker`: the `podman-docker` package provides a
#   `/usr/bin/docker` shim that calls `podman`. Tools and CI that shell out to
#   `/usr/bin/docker` keep working without docker-ce. Podman is already in the
#   silverblue base; we add the shim and nothing else.
# - Package install uses `dnf5 install/remove` against the silverblue base image,
#   not `rpm-ostree install/override remove`. `rpm-ostree install` is a client-side
#   command meant for booted systems; it does not reliably work inside `buildah bud`
#   even on ostree hosts (see coreos/rpm-ostree#3738, fedora-silverblue/issue-tracker
#   issues against rpm-ostree container builds). dnf5 has shipped on Atomic Desktops
#   since Fedora 41 and is the supported build-time tool (Changes/DNFAndBootcInImage
#   ModeFedora).

ARG FEDORA_VERSION=45

FROM quay.io/fedora-ostree-desktops/silverblue:${FEDORA_VERSION}

ARG FEDORA_VERSION=45
ARG LINT_SKIP=--skip=var-tmpfiles

# ---- Repos ----
# Nothing to add: podman is in the base silverblue image, and the CLI/dev
# toolchain (oh-my-posh, hack-nerd-fonts included) is installed via nix from
# nix/apps.nix — see README.md "Nix". Long-term tools stay out of the image
# so they update independently of rebase.

# ---- Packages ----
# dnf5 ships on silverblue since Fedora 41. /var/cache and /var/log as cache
# mounts match the upstream uBlue / bootc container-build pattern and keep the
# resulting image layer clean (see bootc docs + ublue-os/main Containerfile).
# No --disablerepo=fedora-{modular,devel} hack needed; silverblue doesn't enable
# them by default and the base image already only pulls what it needs.
#
# Note: do NOT add `--mount=type=tmpfs,dst=/tmp` here. The base silverblue
# image already provides /tmp as a root-owned, mode-1777 tmpfs (see systemd
# tmpfiles.d defaults), which is exactly what librepo needs for its
# `mkstemp('/tmp/librepo-tmp-XXXXXX')` calls. Replacing that with a BuildKit
# tmpfs mount breaks rootless buildah on a Silverblue host: the new tmpfs
# inherits the host-builder's UID and root inside the container then fails
# `mkstemp` with EACCES (containers/buildah#1240 — observed symptom:
# `Cannot create temporary file - mkstemp '/tmp/librepo-tmp-XXXXXX':
# Permission denied`). The CI runner is privileged and runs as root, which is
# why the same Containerfile builds fine in Forgejo but fails on a host
# `sudo buildah bud --isolation=chroot` invocation. /var/cache stays mounted
# because that is the real cache hot path dnf5 also writes to.
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    set -euxo pipefail; \
    # Drop Firefox from the silverblue base. dnf5 remove on a derived layer
    # replaces the base package cleanly (the upstream Fedora bootc / ublue
    # pattern — see ublue-os/main Containerfile + Fedora wiki
    # Changes/DNFAndBootcInImageModeFedora).
    rpm -q firefox >/dev/null && dnf5 -y remove firefox firefox-langpacks || true; \
    dnf5 -y install \
        # Nix package manager. User-level CLI/dev tools are installed from
        # nix/apps.nix via `nix profile install --file nix/apps.nix` — not
        # here. Anything needing kernel/GPU/daemon integration stays below.
        nix \
        nix-daemon \
        ollama \
        # adds a `/usr/bin/docker` → podman shim so the Forgejo runner
        # (which only knows how to call `docker`) keeps working without
        # pulling in docker-ce.
        podman-docker \
        podman-compose \
        libvirt \
        libvirt-daemon-config-network \
        libvirt-daemon-kvm \
        qemu-kvm \
        virt-manager \
        virt-install \
        forgejo-runner \
        rocm-runtime \
        rocm-clinfo \
        rocm-opencl \
        rocminfo \
        # jstest/inputattach — not packaged in nixpkgs, and it's
        # kernel-input (evdev/udev) adjacent anyway.
        linuxconsoletools \
        waydroid \
        node_exporter \
        # Layered on the client via rpm-ostree install; moved into the image
        # so `bootc update` is no longer blocked by local modifications.
        systemd-devel \
        tailscale; \
    dnf5 clean all; \
    rm -rf /var/cache/dnf5 /var/cache/rpm-ostree /var/lib/rpm-ostree-pending* 2>/dev/null || true; \
    ostree container commit

# ---- Files overlay ----
# Bulk copy of /etc + /usr share + /usr/lib/systemd/system-preset.
COPY files/system/ /

# Helper scripts. Single-file COPY because /usr/local is a /var symlink on
# Fedora Atomic; recursive COPY would refuse to overwrite the symlink.
COPY files/forgejo-runner/setup-forgejo-runner.sh /usr/local/bin/setup-forgejo-runner.sh
COPY files/forgejo-runner/config.yaml.j2 /etc/forgejo-runner/config.yaml.j2
COPY files/forgejo-runner/README.md /usr/local/share/forgejo-runner/README.md
COPY files/forgejo-runner/forgejo-runner.service /usr/lib/systemd/user/forgejo-runner.service
COPY files/scripts/setup-libvirt.sh /usr/local/bin/setup-libvirt.sh

# ---- Install-time kargs ----
# AMD GPU stability kargs baked in. These are read by `bootc install` and
# applied to the installed system's kernel cmdline. Two flags:
#   - amdgpu.gpu_recovery=1     — recover the GPU on hang instead of freezing
#   - amdgpu.ppfeaturemask=0xffffffff — unlock all power/clock controls
# (See upstream bootc docs: drop-ins in /usr/lib/bootc/install/*.toml are
# processed in alphanumerical order at install time.)
COPY files/bootc/install/00-amdgpu.toml /usr/lib/bootc/install/00-amdgpu.toml

# ---- Systemd preset + enable ----
# libvirt preset is in files/system/usr/lib/systemd/system-preset/. Re-apply the
# preset so the libvirt units ship enabled by default for the user. Podman is
# already socket-activated by systemd in the base image; no preset work needed.
# ---- Systemd preset + enable ----
# libvirt + nix presets are in files/system/usr/lib/systemd/system-preset/.
# No || true here: if a unit name changes upstream, fail the build loudly
# instead of shipping a silently disabled daemon.
RUN systemctl preset libvirtd.service libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket \
        nix-daemon.socket nix-daemon.service && \
    systemctl enable node_exporter.service && \
    chmod 0755 \
        /usr/local/bin/setup-forgejo-runner.sh \
        /usr/local/bin/setup-libvirt.sh && \
    ostree container commit

# ---- Flatpaks (manifest only; installed by build/install-flatpaks.sh) ----
# NOT baked into the image: flatpaks live in /var, which bootc only seeds from
# the image on first install and never updates on upgrade — a baked copy would
# be frozen at build-day versions and would not even arrive on a rebase.
# flatpak-list.txt is the single source of truth; install (or refresh) with:
#   ./build/install-flatpaks.sh        (idempotent, run as your user)
# Firefox is already a system flatpak in the silverblue base.
COPY build/flatpak-list.txt /usr/share/fedora-gnome-bootc-ewt/flatpak-list.txt

# ---- Lint ----
# Validates that the resulting image is a well-formed bootc / ostree-native-
# container image. Required for bootc-compatible images per upstream docs;
# surfaces missing labels, bad cmd/entrypoint, etc.
#
# Skip var-tmpfiles on host (non-CI) builds. The lint walks /var to detect
# content that needs systemd tmpfiles.d entries; while doing so it ends up
# stat'ing /sys/kernel/security/ima/binary_runtime_measurements (the IMA
# runtime measurement file). On Fedora Silverblue 41+ hosts (IMA enabled in
# the kernel, default), buildah's --isolation=chroot exposes the host's
# /sys inside the build's chroot, and that file is only readable with
# CAP_SYS_ADMIN — rootless buildah hits EACCES and the lint aborts:
#
#   error: Linting: Unexpected runtime error running lint var-tmpfiles:
#   I/O error on /sys/kernel/security/ima/binary_runtime_measurements:
#   Permission denied (os error 13)
#
# Cannot mask /sys via --mount=type=tmpfs,dst=/sys or type=bind here: with
# --isolation=chroot the container's /sys is a pre-mounted sysfs that
# subsequent BuildKit mount directives cannot replace (verified
# empirically — the host sysfs remains visible). Forgejo CI is unaffected
# because the buildah/stable container kernel doesn't have IMA active.
#
# var-tmpfiles is the lint catching the `ostree container commit` mistake
# of leaving files in /var without tmpfiles.d entries. Our image is fine:
# the silverblue base ships its /var content via tmpfiles.d, our overlay
# touches nothing under /var, and dnf5 installs land in /usr. So skipping
# this specific lint loses no real safety on this image. File an upstream
# issue when this becomes annoying enough.
#
# LINT_SKIP defaults to --skip=var-tmpfiles (host builds with IMA). CI on
# GitHub runners runs the full lint: --build-arg LINT_SKIP= .
RUN bootc container lint ${LINT_SKIP}

LABEL org.opencontainers.image.title="fedora-gnome-bootc-ewt" \
      org.opencontainers.image.description="Fedora 45 GNOME bootc image with personal customizations" \
      org.opencontainers.image.source="https://github.com/dverdonschot/fedora-gnome-bootc-ewt" \
      org.opencontainers.image.licenses="Apache-2.0"
