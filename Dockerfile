## syntax=docker/dockerfile:1
# check=error=true

# Adapted from https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers
# See also https://github.com/devcontainers/images/blob/main/src/base-ubuntu/.devcontainer/Dockerfile
ARG TZ=Etc/UTC
# Debian LTS 13 "trixie"
ARG DEBIAN_VERSION=trixie
ARG NODE_VERSION=24.22.1
ARG NODE_OPTIONS="--max-old-space-size=8192"
ARG UV_VERSION=0.13.5
ARG OPENCODE_NPM_VERSION=1.19.4
ARG PYTHON_VERSION_MODERN=3.14.9
ARG PYTHON_VERSION_LEGACY=3.11.17

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM node:${NODE_VERSION}-${DEBIAN_VERSION}-slim AS os-base

FROM os-base
LABEL dev.containers.features="common"
ENV DEVCONTAINER=true
ARG TZ
ARG NODE_OPTIONS
ARG OPENCODE_NPM_VERSION
ARG PYTHON_VERSION_MODERN
ARG PYTHON_VERSION_LEGACY

ENV DEFAULT_USER=root
USER $DEFAULT_USER

ENV DEVCONTAINER=true
ENV OPENCODE_NPM_VERSION=${OPENCODE_NPM_VERSION}
ENV TZ=${TZ}
ENV NODE_OPTIONS=${NODE_OPTIONS}

ENV PYTHON_VERSION_MODERN=${PYTHON_VERSION_MODERN}
ENV PYTHON_VERSION_LEGACY=${PYTHON_VERSION_LEGACY}

# Create non-root user
ARG USERNAME=guest
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

ENV EDITOR=nano
ENV VISUAL=nano

# Install global NPM dependencies in user-readable directory
ENV NPM_CONFIG_PREFIX=/home/${USERNAME}/.npm-global

ENV PATH=/home/${USERNAME}/.npm-global/bin:$PATH
ENV PATH=/home/${USERNAME}/.local/bin:$PATH
ENV PATH=/home/${USERNAME}/.local/share/uv/python:$PATH

# NPM config
ENV NPM_CONFIG_AUDIT=false
ENV NPM_CONFIG_IGNORE_SCRIPTS=true
ENV NPM_CONFIG_FUND=false
ENV NPM_CONFIG_MIN_RELEASE_AGE=2
ENV NPM_CONFIG_PREFER_OFFLINE=true
ENV NPM_CONFIG_SAVE_EXACT=true
ENV NPM_CONFIG_UPDATE_NOTIFIER=false

## uv settings
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PYTHONDONTWRITEBYTECODE=1
#ENV UV_LINK_MODE=copy

RUN echo "Set up non-root user..." \
  && groupmod -n "${USERNAME}" node \
  && usermod -d "/home/${USERNAME}" -l "${USERNAME}" node \
  && mkdir -p "/home/${USERNAME}" \
  && mkdir -p "/home/${USERNAME}/.gnupg" \
  && echo "Persisting bash history..." \
  && mkdir -p /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R "$USERNAME" /commandhistory \
  && echo "Finished persisting bash history." \
  && echo "✅ Finished setting up non-root user." \
  && echo "Fixing timezone data..." \
  && apt-get update \
  && export DEBIAN_FRONTEND=noninteractive \
  && apt-get -y reinstall --no-install-recommends tzdata \
  && echo "Etc/UTC" > /etc/timezone \
  && echo "✅ Fixed timezone data." \
  && echo "Installing OS packages..." \
  && apt-get update && export DEBIAN_FRONTEND=noninteractive \
  && apt-get install -y --no-install-recommends \
    bash-completion \
    build-essential \
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
  && echo "Finished installing OS packages."

COPY --from=uv --chown=${USER_UID}:${USER_GID} /uv /uvx /usr/local/bin

RUN NPM_CONFIG_IGNORE_SCRIPTS=false \
  npm install -g opencode-ai@${OPENCODE_NPM_VERSION} \
    --allow-scripts=opencode-ai@${OPENCODE_NPM_VERSION}

RUN mkdir -p /home/${USERNAME}/.local/share/opencode/ \
  && mkdir -p /home/${USERNAME}/.local/state/ \
  && mkdir -p /home/${USERNAME}/.cache/uv/ \
  && mkdir -p /home/${USERNAME}/.local/bin/ \
  && mkdir -p /home/${USERNAME}/.local/share/uv/ \
  && chown -R "${USERNAME}" "/home/${USERNAME}"

USER ${USERNAME}
RUN echo "Installing python" ${PYTHON_VERSION_LEGACY} "and" ${PYTHON_VERSION_MODERN} "..." \
  && UV_PYTHON_INSTALL_MIRROR=https://releases.astral.sh/github/python-build-standalone/releases/download \
    UV_CONCURRENT_DOWNLOADS=1 \
    UV_CONCURRENT_INSTALLS=1 \
    uv python install ${PYTHON_VERSION_LEGACY} ${PYTHON_VERSION_MODERN} \
  && echo "Finished installing Python."

USER ${DEFAULT_USER}

# PID-1 doesn't receive SIGTERM, so trap it by hand for a clean 0 exit
CMD ["sh", "-c", "trap 'exit 0' TERM INT; sleep infinity & wait $!"]
