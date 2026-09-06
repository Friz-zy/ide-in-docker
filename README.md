# code-server AI development container

A batteries-included `code-server` development image built around Fedora/Podman, rootless container tooling, AI coding CLIs, and conservative package supply-chain defaults.

The published image is intended to be usable directly through Docker Compose without rebuilding:

```text
ghcr.io/friz-zy/ide-in-docker:latest
```

For reproducible deployments, prefer an immutable build tag instead of `latest`.

## Image defaults

The published image is built with the following defaults:

| Setting | Default | Notes |
| --- | --- | --- |
| Image | `ghcr.io/friz-zy/ide-in-docker:latest` | Mutable convenience tag pointing to the newest successful build |
| Base | Fedora-based `quay.io/podman/stable` | Podman is available directly inside the IDE container |
| Architectures | `linux/amd64`, `linux/arm64` | Published by GitHub Actions |
| User | `vscode` | Non-root development user |
| UID / GID | `1000:1000` | Fixed in the published image; customize only when building locally |
| Home / workdir | `/vscode` | Persistent IDE state can be mounted here |
| Workspace | `/vscode/workspace` | Default project mount point |
| code-server port | `3000` | Exposed by the image |
| Compose host binding | `127.0.0.1:3000` | Not exposed to LAN/Internet by default |
| code-server authentication | `none` | Access must be protected by the network boundary, VPN, or reverse proxy if exposed |
| code-server version | newest stable release older than 7 days | CI resolves and pins the exact release for every build |
| Podman storage | rootless `vfs` | Avoids depending on nested overlay/kernel features |
| Docker daemon | rootless DinD sidecar | IDE uses it through `DOCKER_HOST=tcp://dind:2375` in the provided Compose file |
| npm package age policy | minimum 7 days | Newly published npm versions are quarantined |
| npm lifecycle scripts | disabled at runtime | Temporarily enabled only while the image installs trusted AI CLIs |
| uv package age policy | minimum 7 days | `UV_EXCLUDE_NEWER=P7D` |
| Python source builds | disabled for third-party dependencies | `UV_NO_BUILD=true`; wheels are preferred/required for normal dependency installs |

`latest` is intentionally mutable. Immutable builds use tags in this form:

```text
<code-server-version>-<short-git-sha>-<UTC-date>
```

Example:

```text
4.104.2-a83f912-20260906
```

## How this differs from the official code-server image

The official Coder image is intentionally a relatively small general-purpose `code-server` environment. The current upstream release image is Debian-based, uses the `coder` user, exposes port `8080`, and provides standard development utilities such as Git, SSH, editors, and `sudo`. Coder's documented Docker setup mounts the project under `/home/coder/project`. See the upstream [Dockerfile](https://github.com/coder/code-server/blob/main/ci/release-image/Dockerfile) and [installation documentation](https://coder.com/docs/code-server/install).

This image is aimed at AI-assisted development and nested container workflows instead:

| Area | Official `codercom/code-server` | This image |
| --- | --- | --- |
| Base distribution | Debian | Fedora / Podman stable |
| Default user | `coder` | `vscode` |
| Default port | `8080` | `3000` |
| Default workspace | `/home/coder/project` in the documented Docker example | `/vscode/workspace` |
| Authentication | Standard code-server configuration | Explicit `--auth none`; Compose binds to loopback by default |
| Podman | Not the primary purpose of the image | Included and configured for rootless use |
| Docker CLI | Coder documentation recommends installing it when Docker access is needed | Included |
| Docker daemon | Typically an externally mounted Docker socket if configured by the user | Rootless DinD companion service in Compose |
| AI coding CLIs | Not included | Kilo, OpenCode, OpenAI Codex |
| Python tooling | General system tooling | Python + `uv` with package-age/build restrictions |
| Node tooling | code-server runtime requirements | Node.js LTS + pinned npm security policy |
| Supply-chain quarantine | Upstream package/release policy | Explicit 7-day quarantine for code-server, npm and uv-managed packages |
| Runtime npm scripts | Normal npm behavior | Lifecycle scripts disabled after image bootstrap |
| Container-oriented tooling | Minimal/general-purpose | Podman, Docker CLI, rootless DinD, GitHub/GitLab CLIs |

This is therefore not intended as a drop-in minimal replacement for the official image. It is a larger opinionated development environment designed for AI agents that need Git, language runtimes, package managers, and isolated container execution.

## Included tools

The image includes, among other development utilities:

- [code-server](https://github.com/coder/code-server)
- Podman with rootless storage configuration
- Docker CLI with automatic routing to Docker or Podman
- Rootless Docker-in-Docker companion service via Compose
- Kilo CLI (`@kilocode/cli`)
- OpenCode (`opencode-ai`)
- OpenAI Codex CLI (`@openai/codex`)
- Git and Git LFS
- GitHub CLI (`gh`)
- GitLab CLI (`glab`)
- Python 3
- `uv`
- Go
- Node.js LTS
- npm
- common terminal/debugging utilities

## Published builds

GitHub Actions builds the image for:

```text
linux/amd64
linux/arm64
```

A build is triggered by:

- relevant pushes to `main`;
- relevant pull requests;
- the weekly scheduled build every Tuesday;
- manual `workflow_dispatch`.

Pull requests are built but are not pushed to GHCR.

### code-server release quarantine

The workflow does not blindly build the newest upstream release.

For each build, it queries the stable `code-server` releases and selects the newest non-draft, non-prerelease version that was published more than seven days ago.

That exact version is passed to the Docker build through:

```text
RELEASE=<resolved-version>
```

This keeps CI tagging and the version actually installed inside the image synchronized.

### Immutable build tags

Every published build receives an immutable tag:

```text
<code-server-version>-<short-sha>-<date>
```

For example:

```text
4.104.2-a83f912-20260906
```

Before starting the image build, CI checks whether this exact tag already exists in GHCR.

If it exists, the workflow fails instead of overwriting it.

This means immutable build tags are never intentionally reused even when the same `code-server` version remains current for several days.

### `latest`

Every successful published build also updates:

```text
latest
```

`latest` is the only intentionally mutable tag and is intended for users who want the newest successful weekly build.

For reproducibility or production-like use, pin the immutable tag:

```bash
docker pull ghcr.io/friz-zy/ide-in-docker:4.104.2-a83f912-20260906
```

For the strongest possible pinning, use the image digest:

```text
ghcr.io/friz-zy/ide-in-docker@sha256:<digest>
```

### Why rebuild every week?

The image deliberately quarantines recently published dependencies.

Even if the selected `code-server` version does not change, a later weekly build may contain newer Fedora packages or npm dependency versions that have crossed the seven-day quarantine threshold.

Weekly builds provide a compromise between keeping dependencies reasonably current and avoiding unnecessary image churn.

For that reason:

```text
4.104.2-a83f912-20260901
```

can legitimately have different contents.

They remain separate immutable images rather than silently replacing a tag named only after the `code-server` version.

### Build metadata

Published images include OCI metadata such as:

```text
org.opencontainers.image.version=<code-server-version>-<short-sha>-<date>
org.opencontainers.image.revision=<full-git-sha>
io.coder.code-server.version=<code-server-version>
```

The GitHub Actions build also enables BuildKit provenance and SBOM generation.

## Files

- `Dockerfile` — builds the development image.
- `docker-compose.yml` — runs `code-server` together with a rootless Docker daemon.
- `.github/workflows/container.yml` — builds and publishes multi-architecture images to GitHub Container Registry.

## Quick start

Create the persistent directories first:

```bash
mkdir -p ./vscode "$HOME/.vscode" "$HOME/.config/kilo" "$HOME/.codex"
mkdir -p "${WORKSPACE:-$HOME/Code}"
```

Start the environment:

```bash
docker compose up -d
```

By default, code-server is available only on the local machine:

```text
http://127.0.0.1:3000
```

Stop it with:

```bash
docker compose down
```

To explicitly update the mutable `latest` image first:

```bash
docker compose pull
docker compose up -d
```

## Runtime configuration

The Compose file accepts these runtime-oriented environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `HOST_IP` | `127.0.0.1` | Host address on which code-server is published |
| `HOST_PORT` | `3000` | Host port |
| `PORT` | `3000` | code-server port inside the container |
| `WORKSPACE` | `$HOME/Code` | Host directory mounted as `/vscode/workspace` |
| `DIND_HOST` | `tcp://dind:2375` | Rootless Docker daemon endpoint used by the IDE container |

Example:

```bash
WORKSPACE="$HOME/Code" \
HOST_PORT=3000 \
docker compose up -d
```

The published image itself already contains UID/GID `1000`, user `vscode`, and its resolved `code-server` version. `UID`, `GID`, `NAME`, and `RELEASE` are therefore build-time settings rather than a way to rewrite those properties when merely pulling the prebuilt image.

## Container engines

The IDE container contains both Podman and the Docker CLI.

The `/usr/local/bin/docker` wrapper behaves as follows:

- when `DOCKER_HOST` is set, it invokes the real Docker CLI;
- otherwise it falls back to Podman.

The supplied Compose configuration sets:

```text
DOCKER_HOST=tcp://dind:2375
```

so `docker` commands issued inside the IDE normally use the rootless DinD companion service.

You can still address Podman explicitly:

```bash
docker info
podman info
```

The rootless DinD API is intentionally not published on a host port. It is reachable only through the Compose network unless the configuration is changed.

## AI CLIs

Installed globally during the image build:

```bash
kilo --version
opencode --version
codex --version
```

Kilo and OpenCode use npm install/postinstall logic for their platform-specific native binaries. Lifecycle scripts are therefore explicitly allowed during this trusted image-bootstrap stage.

After those tools have been installed and verified, the final image switches npm into the stricter runtime policy:

```text
min-release-age=7
ignore-scripts=true
```

This means ordinary npm installs performed later inside the running development environment cannot execute package lifecycle scripts by default.

To inspect the effective settings:

```bash
npm config get min-release-age
npm config get ignore-scripts
```

The Docker build itself verifies these values and fails if the expected security controls are not active.

## Python / uv policy

The image configures:

```text
UV_EXCLUDE_NEWER=P7D
UV_NO_BUILD=true
```

The first setting excludes package releases newer than seven days.

The second prevents normal third-party source-distribution builds, reducing exposure to arbitrary Python build backends. `uv` still documents exceptions for first-party/workspace and editable project builds.

## Security notes

- code-server runs with `--auth none`.
- The default Compose binding is `127.0.0.1`, so the IDE is not exposed to the LAN or Internet by default.
- Do not set `HOST_IP=0.0.0.0` unless access is protected by an authenticated reverse proxy, VPN, or another trusted access layer.
- The rootless Docker daemon listens without TLS on the private Compose network. Do not publish port `2375` to the host or an external network.
- The containers use additional capabilities and relaxed seccomp/system-path restrictions required by nested rootless container workloads.
- Rootless Podman and rootless DinD reduce privilege compared with a privileged Docker daemon, but they are not a hardened multi-tenant security boundary.
- Package quarantine reduces exposure to very recently compromised releases; it does not replace lockfiles, dependency review, vulnerability scanning, or digest pinning.

## GitHub Container Registry

Images are published to:

```text
ghcr.io/friz-zy/ide-in-docker
```

Use the newest build:

```bash
docker pull ghcr.io/friz-zy/ide-in-docker:latest
```

Or use an immutable build tag:

```bash
docker pull ghcr.io/friz-zy/ide-in-docker:<code-server-version>-<short-sha>-<date>
```

Example:

```bash
docker pull ghcr.io/friz-zy/ide-in-docker:4.104.2-a83f912-20260906
```

## Local image build

The following options apply only when building the image yourself.

### Build arguments

| Build argument | Default | Description |
| --- | --- | --- |
| `UID` | `1000` | UID of the development user baked into the image |
| `GID` | `1000` | GID of the development user baked into the image |
| `NAME` | `vscode` | Development user name baked into the image |
| `PORT` | `3000` | code-server port exposed and used by the image |
| `RELEASE` | `latest` | Explicit code-server version, or `latest` to resolve the newest stable release older than seven days |

Build with Docker:

```bash
docker build \
  --build-arg UID="$(id -u)" \
  --build-arg GID="$(id -g)" \
  --build-arg NAME=vscode \
  --build-arg PORT=3000 \
  --build-arg RELEASE=latest \
  -t code-server-ai:local .
```

Pin a specific code-server version:

```bash
docker build \
  --build-arg RELEASE=4.104.2 \
  -t code-server-ai:4.104.2-local .
```

If `docker-compose.yml` contains both `image:` and `build:`, use explicit commands when you want deterministic behavior:

```bash
docker compose pull
docker compose up -d --no-build
```

to use the published image, or:

```bash
docker compose build
docker compose up -d
```

to build locally.
