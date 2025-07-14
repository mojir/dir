#!/bin/bash

# Directory Navigator - Main entry point
# Modular version that sources component libraries

# Get the directory where this script is located
if [[ "${BASH_SOURCE[0]}" == /* ]]; then
    # Absolute path
    SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
else
    # Relative path
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Source all module libraries
source "${SCRIPT_DIR}/lib/utils.bash"
source "${SCRIPT_DIR}/lib/input.bash"
source "${SCRIPT_DIR}/lib/render.bash"
source "${SCRIPT_DIR}/lib/json.bash"
source "${SCRIPT_DIR}/lib/actions.bash"
source "${SCRIPT_DIR}/lib/core.bash"
source "${SCRIPT_DIR}/lib/filesystem.bash"

# The dir() function is defined in lib/core.bash
# This file just makes it available by sourcing all the required modules
