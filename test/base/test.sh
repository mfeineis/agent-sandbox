#!/bin/bash

set -e

# Optional: Import test library
# shellcheck disable=SC1091
source dev-container-features-test-lib

# Feature-specific tests
check "node version" node --version
check "npm version" npm --version
check "uv self version" uv self version

# check "whoami is 'vscode'" [ "$(whoami)" = "vscode" ]
# check "VSCODE_IPC_HOOK_CLI is empty" [ -z "$VSCODE_IPC_HOOK" ]
# check "BROWSER is empty" [ -z "$BROWSER" ]
# check "GIT_ASKPASS is empty" [ -z "$GIT_ASKPASS" ]

# check "All capabilities dropped" [ "0000000000000000" = "$(grep 'CapEff' /proc/self/status)" ]
# check "No-new-privileges enfoced" [ "1" = "$(grep 'NoNewPrivs' /proc/self/status)" ]

# check "export HISTFILE" [ ! -z "$HISTFILE" ]
# check "export CLAUDE_CONFIG_DIR" [ ! -z "$CLAUDE_CONFIG_DIR" ]
# check "export DISABLE_AUTOUPDATER" [ ! -z "$DISABLE_AUTOUPDATER" ]

reportResults
