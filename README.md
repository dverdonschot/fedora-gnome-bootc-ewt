# fedora-gnome-bootc-ewt

A custom Fedora Atomic image built on the official GNOME desktop (`silverblue`),
configured for personal use. Same package list, same forgejo-runner, same AMD
GPU kargs as [fedora-cosmic-atomic-ewt](https://github.com/dverdonschot/fedora-cosmic-atomic-ewt)
— the desktop is the only difference. **Container runtime is podman** (with the
`podman-docker` shim so the Forgejo runner's `docker` calls land on podman).
This repo lives at `forge.ewt-lab.dev/ewt-lab/fedora-gnome-bootc-ewt`. The image
is published to **`ghcr.io/ewt-lab/fedora-gnome-bootc-ewt`** by default; the
Forgejo runner does the build + push. **No GitHub Actions.**

## Layout

```
Containerfile              # Single source of truth. buildah / podman / kaniko.
files/
  system/                  # /etc + /usr overlay (tlp.conf, presets, …)
  bootc/install/           # bootc install-time kargs drop-ins (TOML)
  forgejo-runner/          # Runner binary + unit + post-rebase setup
  scripts/                 # One-shot post-rebase helpers (setup-libvirt.sh)
build/
  build.sh                 # `buildah bud` wrapper (local + VPS + runner)
  install-flatpaks.sh      # Post-rebase flatpak installer (idempotent)
  flatpak-list.txt         # Manifest read by install-flatpaks.sh
.forgejo/workflows/build.yml  # CI on your Forgejo runner

## Build

Local or VPS (root or rootless buildah both work). Default registry is
`ghcr.io`; override via env (see table below):

```bash
./build/build.sh                                # build only
./build/build.sh --push                         # build + push to ghcr.io/ewt-lab
FEDORA_VERSION=45 ./build/build.sh --push       # override silverblue tag
REGISTRY=quay.io REGISTRY_NAMESPACE=ewt-lab \
  ./build/build.sh --push                       # push to Quay instead
```

The raw `buildah` command is documented at the top of `Containerfile`.

### Auth for `--push`

`build.sh --push` calls `podman login` for you:

- **Env vars (CI):** set `REGISTRY_USER` + `REGISTRY_TOKEN` (GHCR PAT with
  `write:packages`, or a Quay robot account) and login is non-interactive.
- **Interactive (local):** with no env vars and a TTY, you'll be prompted
  for username + password / token.
- **No creds + no TTY:** the script exits with a clear error rather than
  pushing an unauthenticated request.

### Forgejo runner

The included `.forgejo/workflows/build.yml` runs the same `build.sh --push`
on a self-hosted runner. Required secrets (configure per Forgejo repo):

| Variable | Purpose |
| --- | --- |
| `REGISTRY_USER` | Registry username (e.g. your GitHub handle, or `ewt-lab+robot` on Quay) |
| `REGISTRY_TOKEN` | GHCR PAT (`write:packages`) or Quay robot token |

Required `vars` (optional; defaults shown):

| Variable | Default |
| --- | --- |
| `FEDORA_VERSION` | `44` |
| `REGISTRY` | `ghcr.io` |
| `REGISTRY_NAMESPACE` | `ewt-lab` |
| `IMAGE` | `fedora-gnome-bootc-ewt` |

## Install / rebase

> [!WARNING]
> [This is an experimental feature](https://www.fedoraproject.org/wiki/Changes/OstreeNativeContainerStable),
> try at your own discretion.

From an existing Fedora Atomic install:

# 1. Unsigned rebase — pulls the signing key + policy on the way.
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/ewt-lab/fedora-gnome-bootc-ewt:44
sudo systemctl reboot

# 2. Signed rebase.
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ewt-lab/fedora-gnome-bootc-ewt:44
sudo systemctl reboot
```

## Post-rebase

One-time, as your normal user:

```bash
systemctl --user enable --now podman.socket   # activate the per-user podman socket
/usr/local/bin/setup-forgejo-runner.sh --enable   # if you want CI on this box
/usr/local/bin/setup-libvirt.sh                  # if you use virt-manager
./build/install-flatpaks.sh                      # layered flatpaks
```

## Why not BlueBuild?

The cosmic repo uses [BlueBuild](https://blue-build.org) recipes, which are
great but their hosted build path is GitHub Actions. Since this repo has no
GH presence, a plain `Containerfile` is the boring choice: identical package
list, identical systemd preset, identical scripts — just a different
orchestrator. The cosmic repo can keep its BlueBuild recipe (recipe-gnome.yml
+ recipe.yml); this repo stays independent.

## Customizations vs. stock silverblue
- Podman as the container runtime (rootless via `podman.socket`). The
  Forgejo Actions runner's `DOCKER_HOST` env points at
  `unix:///run/user/<UID>/podman/podman.sock`.
- Forgejo Actions runner pre-staged (operator runs setup script).
- AMD GPU stability kargs baked in via bootc install config
  (`files/bootc/install/00-amdgpu.toml`, applied at `bootc install` time):
  `amdgpu.gpu_recovery=1`, `amdgpu.ppfeaturemask=0xffffffff`.
- TLP defaults for laptop battery care
- Flatpaks: Firefox, Flatseal, FreeTube, Zed, Zen

## Build mechanism

Package install uses `dnf5 install/remove` against the silverblue base, not
`rpm-ostree install/override remove/kargs`. `rpm-ostree install` is a client-side
command meant for booted systems; it does not reliably work inside `buildah bud`
(see [coreos/rpm-ostree#3738](https://github.com/coreos/rpm-ostree/issues/3738))
even on ostree hosts. dnf5 has shipped on Atomic Desktops since Fedora 41 and is
the supported build-time tool per
[Changes/DNFAndBootcInImageModeFedora](https://fedoraproject.org/wiki/Changes/DNFAndBootcInImageModeFedora).
AMD GPU kargs live in a bootc install config drop-in (applied at `bootc install`
time) instead of being mutated via `rpm-ostree kargs`. The build ends with
`bootc container lint`.
