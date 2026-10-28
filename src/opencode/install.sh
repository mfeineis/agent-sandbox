#!/bin/sh
set -eu

install_opencode() {
  echo "Installing Opencode CLI..."

  NPM_CONFIG_IGNORE_SCRIPTS=false \
    npm install -g \
    "opencode-ai@${CLIVERSION}" \
    --allow-scripts="opencode-ai@${CLIVERSION}"

  if command -v opencode >/dev/null; then
    echo "Opencode CLI installed successfully!"
    claude --version
    return 0
  else
    echo "ERROR: Opencode CLI installation failed!"
    return 1
  fi
}

# Print error message about requiring Node.js feature
print_requirements() {
  cat <<EOF

ERROR: Node.js and npm are required but could not be installed!
Please add the Node.js feature to your devcontainer.json:

  "image": "ghcr.io/mfeineis/agent-sandbox",
  "features": {
    "ghcr.io/mfeineis/agent-sandbox/base": {}
    "ghcr.io/mfeineis/agent-sandbox/opencode": {}
  }

EOF
  exit 1
}

# Main script starts here
main() {
  echo "Activating feature 'agent-sandbox/opencode'"

  echo "Opencode: ${CLIVERSION}"

  if ! command -v node >/dev/null || ! command -v npm >/dev/null; then
    echo "Node.js or npm not found, failing..."
    print_requirements
  fi

  # Install Opencode CLI
  install_opencode || exit 1

  mkdir -p "/home/$_REMOTE_USER/.local/share/opencode"
  mkdir -p "/home/$_REMOTE_USER/.local/state/"
  chown -R "$_REMOTE_USER" "/home/$_REMOTE_USER"/.local/share/opencode
  chown -R "$_REMOTE_USER" "/home/$_REMOTE_USER"/.local/state

  # claude --append-system-prompt "$(cat ./container-prompt.md)"
  exit 0
}

# Execute main function
main
