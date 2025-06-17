# Multi-stage build for Eclipse Theia Monorepo
FROM node:18-alpine AS builder

ARG UID=1000
ARG GID=1000
ARG NAME=theia
ARG RELEASE=latest

# Install necessary system dependencies for building
RUN apk add --no-cache \
    shadow \
    make \
    gcc \
    g++ \
    pkgconfig \
    libx11-dev \
    libxkbfile-dev \
    python3 \
    py3-setuptools \
    git \
    openssh-client \
    curl grep sed ca-certificates tar \
    bash

# Prepare user - handle root case specially
RUN set -eux; \
    if [ "${UID}" = "0" ] && [ "${GID}" = "0" ] && [ "${NAME}" = "root" ]; then \
        # Root case - root user already exists, just ensure /theia directory
        mkdir -p /theia; \
    else \
        # Non-root case - create/modify user and group
        if getent group "${GID}" >/dev/null; then \
            existing_group="$(getent group "${GID}" | cut -d: -f1)"; \
            if [ "${existing_group}" != "${NAME}" ]; then \
                groupmod -n "${NAME}" "${existing_group}"; \
            fi; \
        else \
            addgroup -g "${GID}" -S "${NAME}"; \
        fi; \
        if getent passwd "${UID}" >/dev/null; then \
            existing_user="$(getent passwd "${UID}" | cut -d: -f1)"; \
            if [ "${existing_user}" != "${NAME}" ]; then \
                usermod -l "${NAME}" "${existing_user}"; \
                usermod -d "/theia" -m "${NAME}"; \
                usermod -g "${NAME}" "${NAME}"; \
            fi; \
        else \
            adduser -S -D -H \
                -u "${UID}" \
                -G "${NAME}" \
                -h "/theia" \
                -s /bin/bash \
                "${NAME}"; \
        fi; \
        mkdir -p /theia; \
    fi

# Create working directory
WORKDIR /theia

# Copy root configuration files for monorepo
RUN set -eux; \
    if [ "$RELEASE" = "latest" ]; then \
      TAG=$( \
        curl -sI https://github.com/eclipse-theia/theia/releases/latest \
        | grep -i '^location:' \
        | sed -E 's@.*/tag/([^ \r]+)@\1@' \
        | tr -d '\r\n' \
      ); \
    else \
      TAG="$RELEASE"; \
    fi; \
    echo "Selected Theia tag: $TAG"; \
    curl -SL "https://github.com/eclipse-theia/theia/archive/refs/tags/$TAG.tar.gz" \
      | tar -xzC /theia --strip-components=1

# Run node-gyp install as specified in preinstall script
RUN npm run preinstall

# Install dependencies for the entire monorepo
RUN npm install

# Run postinstall to configure all packages
RUN npm run postinstall

# Build browser application
RUN npm run build:browser

# Production stage
FROM node:18-alpine AS production

ARG UID=1000
ARG GID=1000
ARG NAME=theia
ARG PORT=3000

# Install runtime dependencies
RUN apk add --no-cache \
    shadow \
    git \
    openssh-client \
    bash \
    curl \
    python3

# Prepare user - handle root case specially
RUN set -eux; \
    if [ "${UID}" = "0" ] && [ "${GID}" = "0" ] && [ "${NAME}" = "root" ]; then \
        # Root case - root user already exists, just ensure /theia directory
        mkdir -p /theia; \
    else \
        # Non-root case - create/modify user and group
        if getent group "${GID}" >/dev/null; then \
            existing_group="$(getent group "${GID}" | cut -d: -f1)"; \
            if [ "${existing_group}" != "${NAME}" ]; then \
                groupmod -n "${NAME}" "${existing_group}"; \
            fi; \
        else \
            addgroup -g "${GID}" -S "${NAME}"; \
        fi; \
        if getent passwd "${UID}" >/dev/null; then \
            existing_user="$(getent passwd "${UID}" | cut -d: -f1)"; \
            if [ "${existing_user}" != "${NAME}" ]; then \
                usermod -l "${NAME}" "${existing_user}"; \
                usermod -d "/theia" -m "${NAME}"; \
                usermod -g "${NAME}" "${NAME}"; \
            fi; \
        else \
            adduser -S -D -H \
                -u "${UID}" \
                -G "${NAME}" \
                -h "/theia" \
                -s /bin/bash \
                "${NAME}"; \
        fi; \
        mkdir -p /theia; \
    fi

# Create working directory
WORKDIR /theia

# Set file ownership - only for non-root users
RUN chown -R ${NAME}:${NAME} /theia

# Switch to specified user
USER ${NAME}

# Expose port
EXPOSE ${PORT}

# Environment variables for Theia
ENV SHELL=/bin/bash \
    NODE_ENV=production

# Create workspace directory
RUN mkdir -p /theia/workspace

# Copy necessary configuration files
COPY --from=builder --chown=${NAME}:${NAME} /theia/package*.json ./
COPY --from=builder --chown=${NAME}:${NAME} /theia/lerna.json ./

# Copy only browser example and its dependencies
COPY --from=builder --chown=${NAME}:${NAME} /theia/examples ./examples
COPY --from=builder --chown=${NAME}:${NAME} /theia/node_modules ./node_modules

# Copy built packages
COPY --from=builder --chown=${NAME}:${NAME} /theia/packages ./packages
COPY --from=builder --chown=${NAME}:${NAME} /theia/dev-packages ./dev-packages

# Copy plugins
# COPY --from=builder --chown=${NAME}:${NAME} /theia/plugins ./plugins

# Start browser application
# CMD ["npm", "run", "start:browser", "--", "--hostname=0.0.0.0", "--port=${PORT}"] # still use localhost
WORKDIR /theia/examples/browser
CMD npx theia start /theia/workspace --hostname=0.0.0.0 --port ${PORT} --plugins=local-dir:/theia/plugins # --ovsx-router-config=../ovsx-router-config.json
