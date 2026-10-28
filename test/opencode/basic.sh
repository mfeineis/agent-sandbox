#!/bin/bash

set -e

# Test if Opencode CLI is installed
if ! command -v opencode &> /dev/null; then
  echo "opencode command not found"
  exit 1
fi

# # Test version output
# if ! opencode --version | grep -q "Claude Code"; then
#   echo "opencode version check failed"
#   exit 1
# fi

echo "Opencode CLI installation test passed!"
exit 0
