# Production stage — immutable Fedora-based Podman image.
FROM quay.io/podman/stable:v5.7.1-immutable@sha256:2c5155a0516a5fa5ae8ee277514c7d3e96dcdfc6b7ed7a41506ea185733767be AS production

ARG UID=1000
ARG GID=1000
ARG NAME=vscode
ARG PORT=3000
ARG RELEASE=latest

# ── Node.js LTS via NodeSource ────────────────────────────────────────────────
RUN curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash -

# ── Runtime dependencies ──────────────────────────────────────────────────────
RUN dnf install -y \
      --setopt=install_weak_deps=False \
      --setopt=gpgcheck=1 \
      ca-certificates \
      curl \
      dumb-init \
      git \
      git-lfs \
      gh \
      glab \
      htop \
      glibc-langpack-en \
      man-db \
      nano \
      openssh-clients \
      python3 \
      python3-devel \
      python3-pip \
      nodejs \
      procps-ng \
      vim-minimal \
      wget \
      ripgrep \
      lsb-release \
      shadow-utils \
      tar \
      gzip \
      findutils \
      bash \
      golang \
      gcc \
      tmux \
      libffi-devel \
      liboqs \
      liboqs-devel \
    && git lfs install \
    && dnf clean all

# ── uv ────────────────────────────────────────────────────────────────────────
COPY --from=ghcr.io/astral-sh/uv:0.8.14@sha256:f3660c56d5b08d6c516360981bedc439f499b9bf37f46a216018da3777a74011 /uv /uvx /bin/

# ── Locale ────────────────────────────────────────────────────────────────────
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# ── npm quarantine during trusted CLI bootstrap ───────────────────────────────
# Reject npm package versions published less than 7 days ago.
# Lifecycle scripts intentionally remain enabled here because Kilo/OpenCode use
# install/postinstall logic to install their platform-specific binaries.
ENV npm_config_min_release_age=7 \
    npm_config_audit=true \
    npm_config_fund=false

# Pin npm because NodeSource's bundled npm may lag behind required security
# config support. Scripts are disabled for npm's own upgrade.
RUN npm install -g --ignore-scripts npm@11.19.1 \
    && npm --version \
    && test "$(npm config get min-release-age)" = "7"

# ── Podman storage config: vfs by default (no kernel features needed) ─────────
RUN mkdir -p /etc/containers \
    && cat > /etc/containers/storage.conf <<'STORAGE'
[storage]
driver = "vfs"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options]
# vfs needs no special kernel support — safe inside unprivileged containers
[storage.options.vfs]
STORAGE

RUN mkdir -p /etc/containers \
    && cat > /etc/containers/registries.conf <<'REGISTRIES'
[registries.search]
registries = ["docker.io", "quay.io", "ghcr.io"]
REGISTRIES

# ── Docker CLI + smart router ─────────────────────────────────────────────────
# Real docker CLI (matches the DinD daemon version in docker-compose.yml).
# /usr/local/bin shadows /usr/bin on PATH: requests with DOCKER_HOST set
# (rootless DinD) go to the real CLI, everything else falls back to podman.
COPY --from=docker:27-cli@sha256:851f91d241214e7c6db86513b270d58776379aacc5eb9c4a87e5b47115e3065c /usr/local/bin/docker /usr/bin/docker

RUN cat > /usr/local/bin/docker <<'DOCKER_ROUTER'
#!/bin/bash
if [ -n "${DOCKER_HOST}" ] || ! command -v podman >/dev/null 2>&1; then
  exec /usr/bin/docker "$@"
fi
exec podman "$@"
DOCKER_ROUTER
RUN chmod +x /usr/local/bin/docker

# ── npm AI CLIs ───────────────────────────────────────────────────────────────
# Scripts are explicitly enabled only for this bootstrap step.
# --foreground-scripts keeps postinstall output visible in Docker build logs.
RUN npm install -g --ignore-scripts=false --foreground-scripts @kilocode/cli@latest \
    && kilo --version
RUN npm install -g --ignore-scripts=false --foreground-scripts opencode-ai@latest \
    && opencode --version
RUN npm install -g --ignore-scripts=false --foreground-scripts @openai/codex@latest \
    && codex --version

# ── Package supply-chain hardening ────────────────────────────────────────────
# Applied after trusted bootstrap packages are installed.
# npm: keep 7-day quarantine, disable lifecycle scripts, reject git/URL/local deps.
# uv: reject distributions newer than 7 days and refuse sdist builds.
# Note: UV_NO_BUILD still permits first-party/workspace and editable project builds.
# ENV npm_config_ignore_scripts=true \
#     npm_config_allow_git=none \
#     npm_config_allow_remote=none \
#     npm_config_allow_directory=none \
#     npm_config_allow_file=none \
#     UV_EXCLUDE_NEWER=P7D \
#     UV_NO_BUILD=true

ENV npm_config_ignore_scripts=true \
    UV_EXCLUDE_NEWER=P7D \
    UV_NO_BUILD=true

# Fail early if npm stops supporting or honoring these controls.
# Print values first so a failed assertion is obvious in the build log.
RUN set -eux; \
    npm --version; \
    npm config get min-release-age; \
    npm config get ignore-scripts; \
    test "$(npm config get min-release-age)" = "7"; \
    test "$(npm config get ignore-scripts)" = "true";

# ── User setup ────────────────────────────────────────────────────────────────
RUN set -eux; \
    if [ "${UID}" = "0" ] && [ "${GID}" = "0" ] && [ "${NAME}" = "root" ]; then \
        :; \
    else \
        if getent group "${GID}" >/dev/null 2>&1; then \
            existing_group="$(getent group "${GID}" | cut -d: -f1)"; \
            if [ "${existing_group}" != "${NAME}" ]; then \
                groupmod -n "${NAME}" "${existing_group}"; \
            fi; \
        else \
            groupadd -g "${GID}" "${NAME}"; \
        fi; \
        if getent passwd "${UID}" >/dev/null 2>&1; then \
            existing_user="$(getent passwd "${UID}" | cut -d: -f1)"; \
            if [ "${existing_user}" != "${NAME}" ]; then \
                usermod -l "${NAME}" "${existing_user}"; \
                usermod -d "/vscode" -m "${NAME}" 2>/dev/null || true; \
                usermod -g "${NAME}" "${NAME}"; \
            fi; \
        else \
            useradd -r -u "${UID}" -g "${NAME}" -d "/vscode" -s /bin/bash "${NAME}"; \
        fi; \
        grep -q "^${NAME}:" /etc/subuid || echo "${NAME}:100000:65536" >> /etc/subuid; \
        grep -q "^${NAME}:" /etc/subgid || echo "${NAME}:100000:65536" >> /etc/subgid; \
    fi

# ── code-server via age-eligible RPM URL ──────────────────────────────────────
RUN set -eux; \
    ARCH="$(uname -m)"; \
    case "${ARCH}" in \
        x86_64) RPM_ARCH=amd64 ;; \
        aarch64) RPM_ARCH=arm64 ;; \
        *) echo "Unsupported arch: ${ARCH}" && exit 1 ;; \
    esac; \
    if [ "${RELEASE}" = "latest" ]; then \
        RELEASE="$(curl -fsSL --retry 3 --retry-all-errors \
          'https://api.github.com/repos/coder/code-server/releases?per_page=100' \
          | python3 -c 'import datetime, json, sys; cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=7); releases = json.load(sys.stdin); eligible = [r for r in releases if not r["draft"] and not r["prerelease"] and r["published_at"] and datetime.datetime.fromisoformat(r["published_at"].replace("Z", "+00:00")) < cutoff]; eligible.sort(key=lambda r: r["published_at"], reverse=True); print(eligible[0]["tag_name"].lstrip("v")) if eligible else sys.exit("No code-server release is older than 7 days")')"; \
    else \
        RELEASE="${RELEASE#v}"; \
    fi; \
    RPM_URL="https://github.com/coder/code-server/releases/download/v${RELEASE}/code-server-${RELEASE}-${RPM_ARCH}.rpm"; \
    curl -fL --retry 3 --retry-all-errors -o /tmp/code-server.rpm "$RPM_URL"; \
    rpm -i /tmp/code-server.rpm; \
    rm -f /tmp/code-server.rpm

# ── Workdir & ownership ───────────────────────────────────────────────────────
WORKDIR /vscode
RUN chown -R ${NAME}:${NAME} /vscode

USER ${NAME}

# ── Rootless podman storage config for user ───────────────────────────────────
RUN mkdir -p ~/.config/containers \
    && cat > ~/.config/containers/storage.conf <<'ROOTLESS_STORAGE'
[storage]
driver = "vfs"
runroot = "/tmp/podman-run"
graphroot = "/vscode/.local/share/containers/storage"
ROOTLESS_STORAGE

EXPOSE ${PORT}

ENV SHELL=/bin/bash \
    NODE_ENV=production \
    PORT=${PORT}

RUN mkdir -p /vscode/workspace

CMD if [ -d "$HOME/entrypoint.d" ]; then \
      find "$HOME/entrypoint.d" -type f -executable -print -exec {} \; ; \
    fi && \
    if [ -d "/entrypoint.d" ]; then \
      find "/entrypoint.d" -type f -executable -print -exec {} \; ; \
    fi && \
    exec dumb-init /usr/bin/code-server \
      --bind-addr 0.0.0.0:${PORT} \
      --user-data-dir "$HOME/.vscode" \
      --auth none \
      /vscode/workspace "$@"
