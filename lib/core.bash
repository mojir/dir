#!/bin/bash

# Core navigation logic for dir navigator with virtual filesystem support

# Main directory navigator function
dir() {
    local config_file="$HOME/.config/dir/dir.json"
    
    # Initialize constants
    _dir_init_constants
    
    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        echo "Error: Config file not found at $config_file"
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required but not installed"
        return 1
    fi
    
    # Pre-process JSON into bash arrays for instant access
    _dir_parse_json "$config_file"
    
    # Enter alternate screen buffer or save cursor position
    printf '\e[?1049h' || printf '\e[s'
    
    # Set up proper signal handling to restore terminal
    trap '_dir_cleanup; return' INT TERM
    trap '_dir_cleanup' EXIT
    
    # Start navigation at root
    _dir_navigate_level ""
    local result=$?
    
    # Cleanup on normal exit
    _dir_cleanup
    
    # Check if we should exit completely (from nvim)
    if [[ $result -eq 99 ]]; then
        return 0  # Exit the dir function completely
    fi
}

# Handle navigation input
_dir_handle_navigation() {
    local path="$1"
    local key="$2"
    
    # Convert key to index
    local index
    if [[ "$key" =~ [1-9] ]]; then
        index=$key
    else
        # Convert letter to index (a=10, b=11, etc.)
        index=$(( $(printf '%d' "'$key") - 87 ))
    fi
    
    # Build the full path for this item
    local item_path
    if [[ -z "$path" ]]; then
        item_path="/$index"
    else
        item_path="$path/$index"
    fi
    
    # Check if item exists
    if [[ -z "${_dir_items["$item_path"]}" ]]; then
        # Invalid index, just continue
        return 2  # Use return code 2 for "ignore/continue"
    fi
    
    if [[ "${_dir_types["$item_path"]}" == "group" ]]; then
        # It's a nested object, expand it
        _dir_navigate_level "$item_path"
        # When returning from sub-navigation, propagate the return code
        return $?
    else
        # It's a directory path, cd to it and exit
        local clean_path="${_dir_items["$item_path"]}"
        # Expand ~ to home directory
        local expanded_path=$(echo "$clean_path" | sed "s|^~|$HOME|")
        
        if cd "$expanded_path" 2>/dev/null; then
            printf "${_DIR_COLOR_DIR}Changed to: %s${_DIR_COLOR_RESET}\n" "$clean_path"
            return 0
        else
            printf "${_DIR_COLOR_RESET}Error: Cannot access directory %s${_DIR_COLOR_RESET}\n" "$clean_path"
            echo "Press any key to continue..."
            read -n1 -s
            return 2
        fi
    fi
}

# Handle navigation by index with virtual filesystem support
_dir_handle_navigation_by_index() {
    local path="$1"
    local index="$2"
    
    # Handle filesystem paths
    if _dir_is_filesystem_path "$path"; then
        _dir_fs_handle_navigation_by_index "$path" "$index"
        return $?
    fi
    
    # Check if this is the virtual filesystem entry (always last at root)
    if [[ -z "$path" ]]; then
        local saved_count=0
        local saved_index=1
        while [[ -n "${_dir_items["/$saved_index"]}" ]]; do
            ((saved_count++))
            ((saved_index++))
        done
        
        # If index matches the position after all saved items, it's the virtual entry
        if [[ $index -eq $((saved_count + 1)) ]]; then
            # Enter filesystem mode starting at current working directory
            _dir_fs_navigate_level "$(_dir_system_to_fs_path "$(pwd)")"
            local result=$?
            if [[ $result -eq 99 ]]; then
                return 99  # Exit completely
            fi
            return 1  # Return to saved directories view
        fi
    fi
    
    # Build the full path for this item
    local item_path
    if [[ -z "$path" ]]; then
        item_path="/$index"
    else
        item_path="$path/$index"
    fi
    
    # Check if item exists
    if [[ -z "${_dir_items["$item_path"]}" ]]; then
        return 2
    fi
    
    if [[ "${_dir_types["$item_path"]}" == "group" ]]; then
        # It's a nested object, expand it
        _dir_navigate_level "$item_path"
        return $?
    else
        # It's a directory path, cd to it and exit
        local clean_path="${_dir_items["$item_path"]}"
        local expanded_path=$(echo "$clean_path" | sed "s|^~|$HOME|")
        
        # Check if we're already in this directory
        if [[ "$(pwd)" == "$expanded_path" ]]; then
            printf "${_DIR_COLOR_DIR}Already in: %s${_DIR_COLOR_RESET}\n" "$clean_path"
            _DIR_EXIT_SCRIPT=true
            return 0
        elif cd "$expanded_path" 2>/dev/null; then
            printf "${_DIR_COLOR_DIR}Changed to: %s${_DIR_COLOR_RESET}\n" "$clean_path"
            _DIR_EXIT_SCRIPT=true
            return 0
        else
            printf "${_DIR_COLOR_RESET}Error: Cannot access directory %s${_DIR_COLOR_RESET}\n" "$clean_path"
            echo "Press any key to continue..."
            read -n1 -s
            return 2
        fi
    fi
}

# Main navigation function - delegates to filesystem or saved navigation
_dir_navigate_level() {
    local path="$1"
    
    # Delegate to filesystem navigation if it's a filesystem path
    if _dir_is_filesystem_path "$path"; then
        _dir_fs_navigate_level "$path"
        return $?
    fi
    
    # Handle saved directories navigation
    _dir_navigate_saved_level "$path"
    return $?
}
