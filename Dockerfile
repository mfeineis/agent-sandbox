# syntax=docker/dockerfile:1
# check=error=true

# Adapted from https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers
# See also https://github.com/devcontainers/images/blob/main/src/base-ubuntu/.devcontainer/Dockerfile
ARG NODE_VERSION=24.18.0
ARG UV_VERSION=0.11.26
ARG TZ=Etc/UTC


#####################################################################
# UV (for Python)
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv


#####################################################################
# Node-slim base container for Devcontainer
FROM node:${NODE_VERSION}-slim AS node-base
USER root
WORKDIR /root


#####################################################################
# Agent Sandbox Devcontainer (most agent tooling is built on Node)
FROM node-base AS sandbox
ARG TZ
ENV TZ=${TZ}
ENV NODE_OPTIONS=--max-old-space-size=4096

LABEL dev.containers.features="common"
ENV DEVCONTAINER=true

# Create non-root user
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

ENV EDITOR=nano
ENV VISUAL=nano

# Install global NPM dependencies in user-readable directory
ENV NPM_CONFIG_PREFIX=/home/$USERNAME/.npm-global
ENV PATH=$PATH:/home/$USERNAME/.npm-global/bin

# NPM config
ENV NPM_CONFIG_AUDIT=false
ENV NPM_CONFIG_IGNORE_SCRIPTS=true
ENV NPM_CONFIG_FUND=false
ENV NPM_CONFIG_SAVE_EXACT=true
ENV NPM_CONFIG_UPDATE_NOTIFIER=false

# uv settings
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV UV_LINK_MODE=copy

# 🔥🚧🌲
RUN echo "░░░ Set up non-root user..." \
  && groupmod -n "$USERNAME" node \
  && usermod -d "/home/$USERNAME" -l "$USERNAME" node \
  && mkdir -p "/home/$USERNAME" \
  && mkdir -p "/home/$USERNAME/.gnupg" \
  && mkdir -p /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R "$USERNAME" /commandhistory \
  && echo "░░░ ✅ Finished setting up non-root user." \
  && echo "░░░ Fixing timezone data..." \
  && apt-get update \
  && export DEBIAN_FRONTEND=noninteractive \
  && apt-get -y reinstall --no-install-recommends tzdata \
  && echo "Etc/UTC" > /etc/timezone \
  && echo "░░░ ✅ Fixed timezone data." \
  && echo "░░░ Installing OS packages (sudo intentionally omitted for security)..." \
  && apt-get update && export DEBIAN_FRONTEND=noninteractive \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    fd-find \
    git \
    gnupg2 \
    less \
    man-db \
    nano \
    jq \
    ripgrep \
    tree \
    unzip \
    vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && chown -R $USERNAME "/home/$USERNAME" \
  && echo "░░░ ✅ Installed additional OS packages."

COPY --from=uv /uv /usr/local/bin/uv

CMD ["sleep", "infinity"]
