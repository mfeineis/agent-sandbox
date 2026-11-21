# check=error=true

ARG TZ=Etc/UTC
# Debian LTS 13 "trixie"
ARG DEBIAN_VERSION=trixie
# ARG DEBIAN_IMAGE_VARIANT="-slim"
ARG DEBIAN_IMAGE_VARIANT=""
ARG NODE_VERSION=26.13.1
ARG NODE_OPTIONS="--max-old-space-size=8192"

FROM node:${NODE_VERSION}-${DEBIAN_VERSION}${DEBIAN_IMAGE_VARIANT} AS os-base

FROM os-base
LABEL dev.containers.features="common"
ARG TZ
ARG NODE_OPTIONS

ENV DEFAULT_USER=root
USER $DEFAULT_USER

ENV DEVCONTAINER=true
ENV TZ=${TZ}
ENV NODE_OPTIONS=${NODE_OPTIONS}

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

# NPM config
ENV NPM_CONFIG_AUDIT=false
ENV NPM_CONFIG_IGNORE_SCRIPTS=true
ENV NPM_CONFIG_FUND=false
ENV NPM_CONFIG_SAVE_EXACT=true
ENV NPM_CONFIG_UPDATE_NOTIFIER=false

## Python settings
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PYTHONDONTWRITEBYTECODE=1

RUN echo "Set up non-root user..." \
  && groupmod -n "${USERNAME}" node \
  && usermod -d "/home/${USERNAME}" -l "${USERNAME}" node \
  && mkdir -p "/home/${USERNAME}" \
  && mkdir -p "/home/${USERNAME}/.gnupg" \
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
    jq \
    less \
    man-db \
    nano \
    python3-full \
    shellcheck \
    ripgrep \
    tree \
    unzip \
    vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && echo "Finished installing OS packages."

RUN mkdir -p /home/${USERNAME}/.config/ \
  && mkdir -p /home/${USERNAME}/.local/state/ \
  && mkdir -p /home/${USERNAME}/.local/bin/ \
  && chown -R "${USERNAME}" "/home/${USERNAME}"

USER ${USERNAME}

# PID-1 doesn't receive SIGTERM, so trap it by hand for a clean 0 exit
CMD ["sh", "-c", "trap 'exit 0' TERM INT; sleep infinity & wait $!"]
