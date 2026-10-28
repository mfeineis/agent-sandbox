#!/bin/bash

set -e

# Optional: Import test library
# shellcheck disable=SC1091
source dev-container-features-test-lib

# Feature-specific tests
check "opencode cli installed" command -v opencode
check "opencode version" opencode --version

# Report results
reportResults
