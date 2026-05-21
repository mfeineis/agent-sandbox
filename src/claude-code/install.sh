#!/bin/sh
set -eu

# Function to install Claude Code CLI
install_claude_code() {
    echo "Installing Claude Code CLI..."

    echo ".. Writing managed-settings.json..."
    mkdir -p /etc/claude-code \
      && cat << 'SETTINGS' > /etc/claude-code/managed-settings.json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "0",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  },
  "permissions": {
    "disableBypassPermissionsMode": "disable",
    "allow": ["Bash(git add:*)"],
    "ask": ["Bash(git commit:*)"],
    "deny": ["Read(*.env)", "Bash(rm:*)", "Bash(curl:*)"],
    "defaultMode": "default"
  },
  "companyAnnouncements": [
    "This is a Claude Code devcontainer"
  ]
}
SETTINGS
  chmod +r /etc/claude-code

  # Install Claude Code CLI
  # Manually calling postInstall script since those are disabled for the base image
  npm install -g "@anthropic-ai/claude-code@$CLAUDECODEVERSION"
  node "$NPM_CONFIG_PREFIX/lib/node_modules/@anthropic-ai/claude-code/install.cjs"

  if command -v claude >/dev/null; then
    echo "Claude Code CLI installed successfully!"
    claude --version
    return 0
  else
    echo "ERROR: Claude Code CLI installation failed!"
    return 1
  fi
}

# Print error message about requiring Node.js feature
print_requirements() {
  cat <<EOF

ERROR: Node.js and npm are required but could not be installed!
Please add the Node.js feature to your devcontainer.json:

  "features": {
    "ghcr.io/mfeineis/agent-sandbox": {}
    "ghcr.io/mfeineis/agent-sandbox/claude-code": {}
  }

EOF
  exit 1
}

# Main script starts here
main() {
  echo "Activating feature 'agent-sandbox/claude-code'"

  echo "Claude Code: ${CLAUDECODEVERSION}"

  if ! command -v node >/dev/null || ! command -v npm >/dev/null; then
      echo "Node.js or npm not found, failing..."
      print_requirements
  fi

  # Install Claude Code CLI
  install_claude_code || exit 1

  echo "git config user: ${GITUSER}"
  echo "git config email: ${GITEMAIL}"

  cat << 'GITCONFIG' > "/home/$_REMOTE_USER/.gitconfig"
[user]
  name = ${GITUSER}
  email = ${GITEMAIL}

GITCONFIG

  exit 0
}

# Execute main function
main
