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
# The resulting image is an ostree-native-container; rebase to it with:
#
#   sudo rpm-ostree rebase ostree-unverified-registry:quay.io/ewt-lab/fedora-gnome-bootc-ewt:44
#
# Notes:
# - Fedora Atomic puts every package in /usr; /usr/local is a symlink to /var/usrlocal
#   and is not layer-friendly. Helper scripts go in /usr/local/bin via COPY (single
#   files, no symlink dance).
# - /usr/lib/systemd/system-preset/ is the supported way to flip defaults in ostree
#   images without touching the unit files themselves.
# - Masking docker.service/docker.socket at build time is the only way to prevent
#   the rootful daemon from coming back; the per-user dockerd-rootless-setuptool.sh
#   generates ~/.config/systemd/user/docker.service after first rebase.
# - rpm-ostree kargs inside a Containerfile mutates the pending deployment and
#   persists across subsequent rebases (same as on a running system).

ARG FEDORA_VERSION=44

FROM quay.io/fedora-ostree-desktops/silverblue:${FEDORA_VERSION}

ARG FEDORA_VERSION=44

# ---- Repos ----
# Docker CE repo (rootless-docker needs docker-ce-rootless-extras).
COPY files/system/etc/yum.repos.d/docker-ce.repo /etc/yum.repos.d/docker-ce.repo

# nerd-fonts COPR for hack-nerd-fonts / oh-my-posh.
COPY <<EOF /etc/yum.repos.d/_copr-aquacash5-nerd-fonts.repo
[copr:copr.fedorainfracloud.org:aquacash5:nerd-fonts]
name=Copr repo for nerd-fonts owned by aquacash5
baseurl=https://download.copr.fedorainfracloud.org/results/aquacash5/nerd-fonts/fedora-${FEDORA_VERSION}-\$basearch/
enabled=1
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/aquacash5/nerd-fonts/pubkey.gpg
EOF

# ---- Packages ----
# --apply-live is harmless on a build host; --disablerepo=fedora-{modular,devel}
# keeps the modular repo out of the way (silverblue already pulls what it needs
# from the main repo).
RUN rpm-ostree override remove \
        firefox \
        firefox-langpacks && \
    rpm-ostree install \
        micro \
        nodejs \
        npm \
        python3 \
        python3-pip \
        uv \
        vim \
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
        rustup \
        cargo \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
        docker-ce-rootless-extras \
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
        node_exporter && \
    rpm-ostree kargs \
        --append=amdgpu.gpu_recovery=1 \
        --append=amdgpu.ppfeaturemask=0xffffffff && \
    ostree container commit

# ---- Files overlay ----
# Bulk copy of /etc + /usr share + /usr/lib/systemd/system-preset.
COPY files/system/ /

# Helper scripts. Single-file COPY because /usr/local is a /var symlink on
# Fedora Atomic; recursive COPY would refuse to overwrite the symlink.
COPY files/rootless-docker/bin/setup-rootless-docker.sh /usr/local/bin/setup-rootless-docker.sh
COPY files/rootless-docker/bin/verify-rootless-docker.sh /usr/local/bin/verify-rootless-docker.sh
COPY files/forgejo-runner/setup-forgejo-runner.sh /usr/local/bin/setup-forgejo-runner.sh
COPY files/forgejo-runner/config.yaml.j2 /etc/forgejo-runner/config.yaml.j2
COPY files/forgejo-runner/README.md /usr/local/share/forgejo-runner/README.md
COPY files/forgejo-runner/forgejo-runner.service /usr/lib/systemd/user/forgejo-runner.service
COPY files/scripts/setup-libvirt.sh /usr/local/bin/setup-libvirt.sh

# ---- Systemd preset + mask + enable ----
# libvirt preset is in files/system/usr/lib/systemd/system-preset/. Re-apply the
# preset so the libvirt units ship enabled by default for the user.
RUN systemctl preset docker.service docker.socket 2>/dev/null || true && \
    systemctl mask docker.service docker.socket && \
    systemctl preset libvirtd.service libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket 2>/dev/null || true && \
    systemctl enable node_exporter.service && \
    chmod 0755 \
        /usr/local/bin/setup-rootless-docker.sh \
        /usr/local/bin/verify-rootless-docker.sh \
        /usr/local/bin/setup-forgejo-runner.sh \
        /usr/local/bin/setup-libvirt.sh && \
    ostree container commit

# ---- Flatpaks (manifest only; applied at first boot by a generated unit) ----
COPY build/flatpak-list.txt /usr/share/fedora-gnome-bootc-ewt/flatpak-list.txt

LABEL org.opencontainers.image.title="fedora-gnome-bootc-ewt" \
      org.opencontainers.image.description="Fedora Atomic GNOME image with personal customizations" \
      org.opencontainers.image.source="https://forge.ewt-lab.dev/ewt-lab/fedora-gnome-bootc-ewt" \
      org.opencontainers.image.licenses="Apache-2.0"
