#!/bin/sh

# Main script starts here
main() {
  echo "Activating feature 'agent-sandbox/base'"

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
