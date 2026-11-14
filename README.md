# fedora-gnome-bootc-ewt

A custom Fedora 45 GNOME bootc image, configured for personal use. Same package
list, same forgejo-runner, same AMD GPU kargs as
[fedora-cosmic-atomic-ewt](https://github.com/dverdonschot/fedora-cosmic-atomic-ewt)
— the desktop is the only difference. **Container runtime is podman** (with the
`podman-docker` shim so anything that calls `docker` lands on podman).

Lives at `github.com/dverdonschot/fedora-gnome-bootc-ewt`; published to
**`ghcr.io/dverdonschot/fedora-gnome-bootc-ewt`** by GitHub Actions (weekly
scheduled rebuild + push/tag builds), cosign-signed keylessly. Bootc image
reference notes: [docs/bootc-doc-index.md](docs/bootc-doc-index.md).

## Layout

```
Containerfile                    # Single source of truth
files/
  system/                        # /usr overlay (presets, sysusers)
  bootc/install/                 # bootc install-time kargs drop-ins (TOML)
  forgejo-runner/                # Runner unit + post-rebase setup
  scripts/                       # One-shot post-rebase helpers
build/
  build.sh                       # `buildah bud` wrapper (local + VPS + CI)
  install-flatpaks.sh            # Flatpak installer (idempotent; see Flatpaks)
  flatpak-list.txt               # Flatpak manifest, read at build time
.github/workflows/build.yml      # CI: build, lint, push, sign
docs/bootc-doc-index.md          # Curated bootc references + local lessons
```

## Build

```bash
./build/build.sh                                # build only
./build/build.sh --push                         # build + push to ghcr.io/dverdonschot
FEDORA_VERSION=45 ./build/build.sh --push       # override silverblue tag
LINT_SKIP= ./build/build.sh                     # full bootc container lint
```

Env vars: `FEDORA_VERSION` (45), `REGISTRY` (ghcr.io), `REGISTRY_NAMESPACE`
(dverdonschot), `IMAGE`, `PLATFORM` (linux/amd64), `LINT_SKIP`
(`--skip=var-tmpfiles` — see the lint section in `Containerfile` for the IMA
EACCES story on Fedora hosts). Auth for `--push`: `REGISTRY_USER` +
`REGISTRY_TOKEN` (GHCR PAT with `write:packages`), else interactive prompt.
The raw `buildah` command is documented at the top of `Containerfile`.

### CI

`.github/workflows/build.yml` builds on push/PR and rebuilds weekly
(Monday 04:30 UTC) so the image always tracks the latest `silverblue:45`.
Push + signing happen only on `main`; PRs are build-only. Signing is cosign
keyless (no repository secret needed) — verify with:

```bash
cosign verify ghcr.io/dverdonschot/fedora-gnome-bootc-ewt:45
```

## Automatic updates

The machine side ships enabled with the image (verified against upstream
rpm-ostree docs and source, not README prose):

- `files/system/etc/rpm-ostreed.conf` sets `AutomaticUpdatePolicy=stage`:
  updates are downloaded and unpacked in the background and deploy at the
  next boot. Not `apply` — that initiates the reboot itself.
- `files/system/usr/lib/systemd/system-preset/80-automatic-updates.preset`
  enables `rpm-ostreed-automatic.timer`. Preset matching is lexicographic
  and first-match-wins, so the 80- file beats Fedora's 90-systemd.preset
  catchall `disable *`; the build re-applies it with `systemctl preset`.

Cadence comes from the stock timer unit (upstream
`src/daemon/rpm-ostreed-automatic.timer`): `OnBootSec=1h` +
`OnUnitInactiveSec=1d` — roughly an hour after boot, then daily while the
machine is on. A workstation that is on a few hours a day therefore stages
an update every day it is used, and boots the new deployment at the next
power-on (`ostree-finalize-staged.service` does the small remaining work at
shutdown).

Bootstrap note: a machine still running an image built *before* this
change has no timer yet, so it cannot fetch the image that enables it.
Upgrade such a machine once by hand (`sudo rpm-ostree upgrade && reboot`);
every deployment after that stages itself.

Verify on a machine:

```bash
rpm-ostree status     # header shows: AutomaticUpdates: stage; ...
```

Flatpaks and the nix toolchain are not part of this — they still update with
`flatpak update` and `nix profile upgrade`.

## Install / rebase

> [!WARNING]
> [This is an experimental feature](https://www.fedoraproject.org/wiki/Changes/OstreeNativeContainerStable),
> try at your own discretion.

From an existing Fedora Atomic install:

  # 1. Unsigned rebase — pulls the signing key + policy on the way.
  sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/dverdonschot/fedora-gnome-bootc-ewt:45
  sudo systemctl reboot

  # 2. Signed rebase.
  sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/dverdonschot/fedora-gnome-bootc-ewt:45
  sudo systemctl reboot

Fresh disk install:

  sudo bootc install to-disk --filesystem=xfs \
    ostree-image-signed:docker://ghcr.io/dverdonschot/fedora-gnome-bootc-ewt:45 /dev/sdX

### Kernel args

The AMD GPU kargs (`amdgpu.gpu_recovery=1`, `amdgpu.ppfeaturemask=0xffffffff`,
`files/bootc/install/00-amdgpu.toml`) apply at **`bootc install` time only**.
On the `rpm-ostree rebase` path the current deployment's kernel args persist —
apply them once manually if your system doesn't have them:

  sudo rpm-ostree kargs --append=amdgpu.gpu_recovery=1 \
    --append=amdgpu.ppfeaturemask=0xffffffff

## Post-rebase

One-time, as your normal user:

```bash
systemctl --user enable --now podman.socket   # activate the per-user podman socket
/usr/local/bin/setup-forgejo-runner.sh --enable   # if you want CI on this box
/usr/local/bin/setup-libvirt.sh                  # if you use virt-manager
./build/install-flatpaks.sh                      # system flatpaks (see Flatpaks)
nix profile install --file nix/apps.nix          # CLI/dev toolchain (see Nix)
```

## Flatpaks

Firefox, Flatseal, FreeTube, Zed, Zen — **not baked into the image**. Flatpaks
live in `/var`, which bootc only seeds from the image on first install and
never touches on upgrade: a baked copy would be frozen at build-day versions
and wouldn't arrive on a rebase either. `build/flatpak-list.txt` is the single
source of truth (same set as the cosmic repo's `default-flatpaks`); Firefox is
already a system flatpak in the silverblue base.

After rebase/install, run once as your user (idempotent):

```bash
./build/install-flatpaks.sh
```

## Nix

The image ships the Fedora `nix` + `nix-daemon` packages with
`nix-daemon.socket` preset-enabled; nixbld users come from
`sysusers.d/nix.conf` (created at boot).

Nix store lives in `/nix` (mutable, outside the bootc image) — installs
survive reboots and rebases, and are intentionally *not* part of the image.
The user-level CLI/dev toolchain (editors, compilers, language runtimes,
monitoring, kubectl/helm, tesseract, …) is declared in
[`nix/apps.nix`](nix/apps.nix) and applied after rebase:

```bash
# one-time: pin the nixpkgs channel apps.nix builds against
nix-channel --add https://nixos.org/channels/nixos-25.11 nixpkgs
nix-channel --update

# apply the list (idempotent once profile is empty)
nix profile install --file nix/apps.nix
```

Upgrade the toolchain without touching the image — no rebase, no reboot:

```bash
nix-channel --update && nix profile upgrade
```

**Rule of thumb for where a package lives:**
`nix/apps.nix` — pure user-space CLI tools; update independently of the
image. `Containerfile` — anything needing kernel modules, GPU access
(rocm), a system daemon (ollama, node_exporter), a preset unit (libvirt),
or the `podman-docker` shim. The image stays small; long-term tools do NOT
go back into the Containerfile package list.

## Customizations vs. stock silverblue

- Podman as the container runtime (rootless via `podman.socket`), plus the
  `podman-docker` shim.
- Forgejo Actions runner pre-staged (operator runs setup script).
- libvirt/KVM preset (`80-virtualization.preset`), virt-manager, qemu-kvm.
- Nix + nix-daemon, with the user-level CLI/dev toolchain declared in
  `nix/apps.nix` (see Nix above).
- AMD GPU stability kargs via bootc install config (see Kernel args above).
- Flatpaks via manifest + idempotent script (see Flatpaks above).
- `node_exporter` enabled.
- Automatic update staging enabled (stage policy + `rpm-ostreed-automatic.timer`, see Automatic updates).

## Build mechanism

Package install uses `dnf5 install/remove` against the silverblue base, not
`rpm-ostree install/override remove/kargs`. `rpm-ostree install` is a
client-side command meant for booted systems; it does not reliably work inside
`buildah bud` (see
[coreos/rpm-ostree#3738](https://github.com/coreos/rpm-ostree/issues/3738))
even on ostree hosts. dnf5 has shipped on Atomic Desktops since Fedora 41 and
is the supported build-time tool per
[Changes/DNFAndBootcInImageModeFedora](https://fedoraproject.org/wiki/Changes/DNFAndBootcInImageModeFedora).
AMD GPU kargs live in a bootc install config drop-in (applied at
`bootc install` time) instead of being mutated via `rpm-ostree kargs`. The
build ends with `bootc container lint`.
