#!/bin/sh

# Main script starts here
main() {
  echo "Activating feature 'agent-sandbox/base'"

  exit 0
}

# Execute main function
main


# "postStartCommand": "chown -R vscode /home/$_REMOTE_USER/.claude"
# "source=vscode-server-${devcontainerId},target=/home/vscode/.vscode-server,type=volume",
# "source=user-cache-${devcontainerId},target=/home/vscode/.cache,type=volume",
# "source=user-config-${devcontainerId},target=/home/vscode/.config,type=volume",
# "source=user-gitconfig-${devcontainerId},target=/home/vscode/.gitconfig,type=volume",
# "source=user-gnupg-${devcontainerId},target=/home/vscode/.gnupg,type=volume",
# "source=vscode-var-devcontainer-${devcontainerId},target=/var/devcontainer,type=volume",
# "source=vscode-etc-environment-${devcontainerId},target=/etc/environment,type=volume",
# "source=vscode-var-lib-containers-${devcontainerId},target=/var/lib/containers,type=volume",
# "source=devc-${localWorkspaceFolderBasename}-bashhistory-${devcontainerId},target=/commandhistory,type=volume",
# "source=devc-${localWorkspaceFolderBasename}-config-${devcontainerId},target=/home/vscode/.claude,type=volume",
# "source=devc-${localWorkspaceFolderBasename}-gh-${devcontainerId},target=/home/vscode/.config/gh,type=volume",
# "source=${localEnv:HOME}/.gitconfig,target=/home/vscode/.gitconfig,type=bind,readonly",
# "source=${localWorkspaceFolder}/.devcontainer,target=/workspace/.devcontainer,type=bind,readonly",
# "source=${localWorkspaceFolder}/.git/config,target=/workspace/.git/config,type=bind,readonly",
# "source=${localWorkspaceFolder}/.git/hooks,target=/workspace/.git/hooks,type=bind,readonly"

# "GIT_CONFIG_GLOBAL": "/home/vscode/.gitconfig.local",
# "TZ": "Europe/Berlin",
# "postCreateCommand": "uv run --no-project /opt/post_install.py"
