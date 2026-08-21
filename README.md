# fedora-gnome-bootc-ewt

A custom Fedora Atomic image built on the official GNOME desktop (`silverblue`),
configured for personal use. Same package list, same rootless Docker, same
forgejo-runner, same AMD GPU kargs as
[fedora-cosmic-atomic-ewt](https://github.com/dverdonschot/fedora-cosmic-atomic-ewt)
— the desktop is the only difference.

This repo lives at `forge.ewt-lab.dev/ewt-lab/fedora-gnome-bootc-ewt` and is
built locally, on the VPS, or by a Forgejo Actions runner. **No GitHub Actions.**

## Layout

```
Containerfile              # Single source of truth. buildah / podman / kaniko.
files/
  system/                  # /etc + /usr overlay (tlp.conf, presets, …)
  rootless-docker/bin/     # Per-user docker setup + verify scripts
  forgejo-runner/          # Runner binary + unit + post-rebase setup
  scripts/                 # One-shot post-rebase helpers (setup-libvirt.sh)
build/
  build.sh                 # `buildah bud` wrapper (local + VPS + runner)
  install-flatpaks.sh      # Post-rebase flatpak installer (idempotent)
  flatpak-list.txt         # Manifest read by install-flatpaks.sh
.forgejo/workflows/build.yml  # CI on your Forgejo runner
```

## Build

Local or VPS (root or rootless buildah both work):

```bash
./build/build.sh                       # image only
./build/build.sh --push                # build + push to quay.io/ewt-lab
FEDORA_VERSION=45 ./build/build.sh     # override silverblue tag
```

The raw `buildah` command is documented at the top of `Containerfile`.

### Forgejo runner

The included `.forgejo/workflows/build.yml` runs the same `build.sh --push`
on a self-hosted runner. Required secrets (configure per Forgejo repo):

| Variable | Purpose |
| --- | --- |
| `REGISTRY_USER` | Registry username (e.g. `ewt-lab+robot`) |
| `REGISTRY_TOKEN` | Registry password / PAT |

Required `vars` (optional; defaults shown):

| Variable | Default |
| --- | --- |
| `FEDORA_VERSION` | `44` |
| `REGISTRY` | `quay.io/ewt-lab` |
| `IMAGE` | `fedora-gnome-bootc-ewt` |

## Install / rebase

> [!WARNING]
> [This is an experimental feature](https://www.fedoraproject.org/wiki/Changes/OstreeNativeContainerStable),
> try at your own discretion.

From an existing Fedora Atomic install:

```bash
# 1. Unsigned rebase — pulls the signing key + policy on the way.
sudo rpm-ostree rebase ostree-unverified-registry:quay.io/ewt-lab/fedora-gnome-bootc-ewt:44
sudo systemctl reboot

# 2. Signed rebase.
sudo rpm-ostree rebase ostree-image-signed:docker://quay.io/ewt-lab/fedora-gnome-bootc-ewt:44
sudo systemctl reboot
```

## Post-rebase

One-time, as your normal user:

```bash
/usr/local/bin/setup-rootless-docker.sh     # rootless docker daemon
/usr/local/bin/setup-forgejo-runner.sh      # if you want CI on this box
/usr/local/bin/setup-libvirt.sh             # if you use virt-manager
./build/install-flatpaks.sh                 # layered flatpaks
```

## Why not BlueBuild?

The cosmic repo uses [BlueBuild](https://blue-build.org) recipes, which are
great but their hosted build path is GitHub Actions. Since this repo has no
GH presence, a plain `Containerfile` is the boring choice: identical package
list, identical systemd preset, identical scripts — just a different
orchestrator. The cosmic repo can keep its BlueBuild recipe (recipe-gnome.yml
+ recipe.yml); this repo stays independent.

## Customizations vs. stock silverblue

- Same dnf package list as `fedora-cosmic-atomic-ewt/recipes/recipe-gnome.yml`
- Rootless Docker (system docker.service masked)
- Forgejo Actions runner pre-staged (operator runs setup script)
- AMD GPU stability kargs baked in (`amdgpu.gpu_recovery=1`,
  `amdgpu.ppfeaturemask=0xffffffff`)
- TLP defaults for laptop battery care
- Flatpaks: Firefox, Flatseal, FreeTube, Zed, Zen
