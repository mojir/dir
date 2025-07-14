#!/bin/bash

# Directory Navigator - Main entry point
# Modular version with virtual filesystem support

# Get the directory where this script is located
if [[ "${BASH_SOURCE[0]}" == /* ]]; then
    # Absolute path
    SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
else
    # Relative path
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Source all module libraries in dependency order
source "${SCRIPT_DIR}/lib/utils.bash"
source "${SCRIPT_DIR}/lib/input.bash"
source "${SCRIPT_DIR}/lib/json.bash"
source "${SCRIPT_DIR}/lib/actions.bash"
source "${SCRIPT_DIR}/lib/filesystem.bash"
source "${SCRIPT_DIR}/lib/saved.bash"        # New saved navigation logic
source "${SCRIPT_DIR}/lib/render.bash"
source "${SCRIPT_DIR}/lib/core.bash"

# The dir() function is defined in lib/core.bash
# This file makes it available by sourcing all the required modules
# Virtual filesystem integration provides seamless browsing between
# saved directories and live filesystem exploration
