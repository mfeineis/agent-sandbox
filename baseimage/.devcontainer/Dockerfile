# syntax=docker/dockerfile:1
# check=error=true

# Adapted from https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers
# See also https://github.com/devcontainers/images/blob/main/src/base-ubuntu/.devcontainer/Dockerfile
ARG NODE_VERSION
ARG UV_VERSION
ARG TZ=Etc/UTC


#####################################################################
# UV (for Python)
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv


#####################################################################
# Node-slim based Devcontainer (most agent tooling is built on Node)
FROM node:${NODE_VERSION}-slim
ARG TZ
ENV TZ=${TZ}
ENV NODE_OPTIONS=--max-old-space-size=4096

ENV DEVCONTAINER=true

# Create non-root user
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USE

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

RUN echo "░░░ Set up non-root user..." \
  && usermod -d "/home/$USERNAME" -l "$USERNAME" node \
  && mkdir -p "/home/$USERNAME" \
  && chown -R $USERNAME "/home/$USERNAME" \
  && mkdir -p "/home/$USERNAME/.gnupg" \
  && mkdir -p /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R "$USERNAME" /commandhistory \
  && if [ -f "/home/$USERNAME/.bashrc" ]; then \
      sed -i '1i source ~/.config/security-harden.sh 2>/dev/null || true' "/home/$USERNAME/.bashrc"; \
    else \
      echo "source ~/.config/security-harden.sh 2>/dev/null || true" > "/home/$USERNAME/.bashrc"; \
    fi \
  && echo "░░░ ✅ Finished setting up non-root user."

# Security hardening script – sourced from .bashrc before the interactive guard
# See the "VS Code IPC hardening" section for why this is needed
COPY <<HARDEN /home/${USERNAME}/.config/security-harden.sh

# VS Code IPC sockets – can execute commands on the host
unset VSCODE_IPC_HOOK_CLI

# VS Code Git extension IPC – credential access via host
unset VSCODE_GIT_IPC_HANDLE \
  GIT_ASKPASS \
  VSCODE_GIT_ASKPASS_MAIN \
  VSCODE_GIT_ASKPASS_NODE \
  VSCODE_GIT_ASKPASS_EXTRA_ARGS

# Remote Containers extension IPC – host command execution bridge
unset REMOTE_CONTAINERS_IPC \
  REMOTE_CONTAINERS_SOCKETS \
  REMOTE_CONTAINERS_DISPLAY_SOCK

# GUI forwarding (low risk but unnecessary)
unset WAYLAND_DISPLAY

# Browser helper – can trigger actions on host via --openExternal
# Set to empty rather than unset to prevent fallback to defaults
export BROWSER=

# Agent forwarding – set to empty to prevent fallback to default socket paths
export SSH_AUTH_SOCK=
export GPG_AGENT_INFO=

HARDEN

RUN echo "░░░ Fixing timezone data..." \
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
    locales \
    man-db \
    nano \
    jq \
    ripgrep \
    tree \
    unzip \
    vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && echo "░░░ ✅ Installed additional OS packages."

COPY --from=uv /uv /usr/local/bin/uv

CMD ["sleep", "infinity"]
