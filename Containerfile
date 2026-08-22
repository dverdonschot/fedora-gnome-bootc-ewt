# syntax=docker/dockerfile-upstream:1.7
#
# fedora-gnome-bootc-ewt — Fedora Atomic GNOME image with personal customizations.
#
# Build (local / VPS / Forgejo runner all use the same command):
#
#   sudo buildah bud \
#     --isolation=chroot \
#     --build-arg FEDORA_VERSION=44 \
#     -t quay.io/ewt-lab/fedora-gnome-bootc-ewt:44 \
#     -f Containerfile .
#
# The resulting image is an ostree-native-container; install it with:
#
#   sudo bootc install to-disk --filesystem=xfs \
#       ostree-unverified-registry:quay.io/ewt-lab/fedora-gnome-bootc-ewt:44 /dev/sda
#
# …or rebase an existing Fedora Atomic install to it:
#
#   sudo rpm-ostree rebase ostree-unverified-registry:quay.io/ewt-lab/fedora-gnome-bootc-ewt:44
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
#   `/usr/bin/docker` shim that calls `podman`. The Forgejo Actions runner shells
#   out to `/usr/bin/docker`, so the shim keeps it working without docker-ce.
#   Podman is already in the silverblue base; we add the shim and nothing else.
# - Package install uses `dnf5 install/remove` against the silverblue base image,
#   not `rpm-ostree install/override remove`. `rpm-ostree install` is a client-side
#   command meant for booted systems; it does not reliably work inside `buildah bud`
#   even on ostree hosts (see coreos/rpm-ostree#3738, fedora-silverblue/issue-tracker
#   issues against rpm-ostree container builds). dnf5 has shipped on Atomic Desktops
#   since Fedora 41 and is the supported build-time tool (Changes/DNFAndBootcInImage
#   ModeFedora).

ARG FEDORA_VERSION=44

FROM quay.io/fedora-ostree-desktops/silverblue:${FEDORA_VERSION}

ARG FEDORA_VERSION=44

# ---- Repos ----
# nerd-fonts COPR for hack-nerd-fonts / oh-my-posh. Podman is in the base
# silverblue image; nothing to add on the repo front.
RUN cat > /etc/yum.repos.d/_copr-aquacash5-nerd-fonts.repo <<EOF
[copr:copr.fedorainfracloud.org:aquacash5:nerd-fonts]
name=Copr repo for nerd-fonts owned by aquacash5
baseurl=https://download.copr.fedorainfracloud.org/results/aquacash5/nerd-fonts/fedora-${FEDORA_VERSION}-\$basearch/
enabled=1
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/aquacash5/nerd-fonts/pubkey.gpg
EOF

# ---- Packages ----
# dnf5 ships on silverblue since Fedora 41. /var/cache and /tmp as cache/tmpfs
# mounts match the upstream uBlue / bootc container-build pattern and keep the
# resulting image layer clean (see bootc docs + ublue-os/main Containerfile).
# No --disablerepo=fedora-{modular,devel} hack needed; silverblue doesn't enable
# them by default and the base image already only pulls what it needs.
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    set -euxo pipefail; \
    # Drop Firefox from the silverblue base. dnf5 remove on a derived layer
    # replaces the base package cleanly (the upstream Fedora bootc / ublue
    # pattern — see ublue-os/main Containerfile + Fedora wiki
    # Changes/DNFAndBootcInImageModeFedora).
    rpm -q firefox >/dev/null && dnf5 -y remove firefox firefox-langpacks || true; \
    dnf5 -y install \
        micro \
        nodejs \
        npm \
        python3 \
        python3-pip \
        uv \
        neovim \
        vim-minimal \
        tmux \
        oh-my-posh \
        hack-nerd-fonts \
        git \
        gcc \
        gcc-c++ \
        pkgconf \
        python3-devel \
        dbus-devel \
        ollama \
        clang \
        llvm \
        llvm-devel \
        mesa-libOpenCL-devel \
        ranger \
        make \
        rust \
        cargo \
        rustup \
        # adds a `/usr/bin/docker` → podman shim so the Forgejo runner
        # (which only knows how to call `docker`) keeps working without
        # pulling in docker-ce.
        podman-docker \
        libvirt \
        libvirt-daemon-config-network \
        libvirt-daemon-kvm \
        qemu-kvm \
        qemu \
        virt-manager \
        virt-install \
        virt-viewer \
        kubernetes-client \
        helm \
        nmap \
        nmap-ncat \
        wireshark \
        btop \
        iotop \
        iftop \
        nethogs \
        sysstat \
        strace \
        forgejo-runner \
        rocm-runtime \
        rocm-clinfo \
        rocm-opencl \
        rocminfo \
        hwinfo \
        linuxconsoletools \
        waydroid \
        dkms \
        tesseract \
        tesseract-langpack-nld \
        net-tools \
        traceroute \
        node_exporter; \
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
RUN systemctl preset libvirtd.service libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket 2>/dev/null || true && \
    systemctl enable node_exporter.service && \
    chmod 0755 \
        /usr/local/bin/setup-forgejo-runner.sh \
        /usr/local/bin/setup-libvirt.sh && \
    ostree container commit

# ---- Flatpaks (manifest only; applied at first boot by a generated unit) ----
COPY build/flatpak-list.txt /usr/share/fedora-gnome-bootc-ewt/flatpak-list.txt

# ---- Lint ----
# Validates that the resulting image is a well-formed bootc / ostree-native-
# container image. Required for bootc-compatible images per upstream docs;
# surfaces missing labels, bad cmd/entrypoint, etc.
RUN bootc container lint

LABEL org.opencontainers.image.title="fedora-gnome-bootc-ewt" \
      org.opencontainers.image.description="Fedora Atomic GNOME image with personal customizations" \
      org.opencontainers.image.source="https://forge.ewt-lab.dev/ewt-lab/fedora-gnome-bootc-ewt" \
      org.opencontainers.image.licenses="Apache-2.0"
