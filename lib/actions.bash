#!/bin/bash

# User action functions for dir navigator

# Check if directory already exists in the current group
_dir_check_duplicate() {
    local path="$1"
    local target_dir="$2"
    local index=1
    
    # Check all items in current group
    while [[ -n "${_dir_items["$path/$index"]}" || ( -z "$path" && -n "${_dir_items["/$index"]}" ) ]]; do
        local item_path
        if [[ -z "$path" ]]; then
            item_path="/$index"
        else
            item_path="$path/$index"
        fi
        
        # Only check directories (not groups)
        if [[ "${_dir_types["$item_path"]}" == "dir" ]]; then
            local existing_dir="${_dir_items["$item_path"]}"
            # Expand ~ to full path for comparison
            local expanded_existing=$(echo "$existing_dir" | sed "s|^~|$HOME|")
            
            if [[ "$expanded_existing" == "$target_dir" ]]; then
                return 0  # Duplicate found
            fi
        fi
        
        ((index++))
    done
    
    return 1  # No duplicate
}

# Add current directory to current level
_dir_add_current_dir() {
    local path="$1"
    local config_file="$HOME/.config/dir/dir.json"
    local current_dir=$(pwd)
    
    # Check if directory already exists in this group
    if _dir_check_duplicate "$path" "$current_dir"; then
        printf "${_DIR_COLOR_GROUP}Directory already exists in this group!${_DIR_COLOR_RESET}\n"
        echo "Press any key to continue..."
        read -n1 -s
        return
    fi
    
    # Add directory to JSON and refresh
    if _dir_add_to_json "$path" "$current_dir" "$config_file"; then
        # Re-parse JSON to update in-memory arrays
        _dir_parse_json "$config_file"
    else
        printf "${_DIR_COLOR_RESET}Error: Failed to add directory${_DIR_COLOR_RESET}\n"
        echo "Press any key to continue..."
        read -n1 -s
    fi
}

# Clean invalid directories and duplicates from config file
_dir_clean_config() {
    local config_file="$HOME/.config/dir/dir.json"
    local temp_file="${config_file}.tmp.$$"
    local removed_invalid=0
    local removed_duplicates=0
    
    printf "${_DIR_COLOR_HEADER}Cleaning configuration...${_DIR_COLOR_RESET}\n"
    
    # Create backup
    cp "$config_file" "$config_file.bak" 2>/dev/null || {
        printf "${_DIR_COLOR_RESET}Error: Cannot create backup${_DIR_COLOR_RESET}\n"
        echo "Press any key to continue..."
        read -n1 -s
        return
    }
    
    # First pass: Remove invalid directories and count them
    printf "Checking for invalid directories...\n"
    _dir_clean_invalid_directories "$config_file" "$temp_file.step1"
    removed_invalid=$?
    
    if [[ $removed_invalid -lt 0 ]]; then
        rm -f "$temp_file.step1"
        printf "${_DIR_COLOR_RESET}Error: Failed to clean invalid directories${_DIR_COLOR_RESET}\n"
        echo "Press any key to continue..."
        read -n1 -s
        return
    fi
    
    # Second pass: Remove duplicates and count them
    printf "Checking for duplicate directories...\n"
    _dir_clean_duplicate_directories "$temp_file.step1" "$temp_file"
    removed_duplicates=$?
    
    if [[ $removed_duplicates -lt 0 ]]; then
        rm -f "$temp_file.step1" "$temp_file"
        printf "${_DIR_COLOR_RESET}Error: Failed to clean duplicate directories${_DIR_COLOR_RESET}\n"
        echo "Press any key to continue..."
        read -n1 -s
        return
    fi
    
    # Apply changes
    cat "$temp_file" > "$config_file" && rm -f "$temp_file.step1" "$temp_file"
    
    # Re-parse JSON to update in-memory arrays
    _dir_parse_json "$config_file"
    
    # Report results
    local total_removed=$((removed_invalid + removed_duplicates))
    if [[ $total_removed -gt 0 ]]; then
        printf "${_DIR_COLOR_DIR}Cleaning complete:${_DIR_COLOR_RESET}\n"
        if [[ $removed_invalid -gt 0 ]]; then
            printf "  - Removed %d invalid directories\n" "$removed_invalid"
        fi
        if [[ $removed_duplicates -gt 0 ]]; then
            printf "  - Removed %d duplicate directories\n" "$removed_duplicates"
        fi
    else
        printf "${_DIR_COLOR_DIR}Configuration is already clean (no invalid or duplicate directories found)${_DIR_COLOR_RESET}\n"
    fi
    
    echo "Press any key to continue..."
    read -n1 -s
}

# Remove invalid directories from JSON
_dir_clean_invalid_directories() {
    local input_file="$1"
    local output_file="$2"
    local removed_count=0
    local invalid_paths_file="${output_file}.invalid_paths"
    
    # Extract all directory paths and check validity
    jq -r '
        def extract_paths:
            if type == "array" then
                .[] | 
                if type == "object" and has("dirs") then
                    .dirs | extract_paths
                elif type == "string" then
                    .
                else
                    empty
                end
            else
                empty
            end;
        
        [.dirs | extract_paths] | .[]
    ' "$input_file" | while IFS= read -r dir_path; do
        # Expand ~ to full path for validation
        local expanded_path=$(echo "$dir_path" | sed "s|^~|$HOME|")
        
        # Check if directory exists
        if [[ ! -d "$expanded_path" ]]; then
            echo "$dir_path" >> "$invalid_paths_file"
        fi
    done
    
    # Count invalid paths
    if [[ -f "$invalid_paths_file" ]]; then
        removed_count=$(wc -l < "$invalid_paths_file" 2>/dev/null || echo 0)
    fi
    
    # Build jq filter to remove invalid paths
    local filter_expr='.'
    if [[ -f "$invalid_paths_file" && -s "$invalid_paths_file" ]]; then
        while IFS= read -r invalid_path; do
            # Escape special characters for jq
            local escaped_path=$(printf '%s' "$invalid_path" | sed 's/"/\\"/g')
            filter_expr="$filter_expr | walk(if type == \"array\" then map(select(. != \"$escaped_path\")) else . end)"
        done < "$invalid_paths_file"
        rm -f "$invalid_paths_file"
    fi
    
    # Apply filter and create output
    if jq "$filter_expr" "$input_file" > "$output_file"; then
        echo "$removed_count"
        return "$removed_count"
    else
        rm -f "$invalid_paths_file"
        return -1
    fi
}

# Remove duplicate directories from JSON
_dir_clean_duplicate_directories() {
    local input_file="$1"
    local output_file="$2"
    local removed_count=0
    
    # Use jq to recursively remove duplicates from arrays while preserving structure
    local cleaned_json=$(jq '
        def remove_duplicates:
            if type == "array" then
                # Separate objects (groups) from strings (directories)
                [
                    .[] | 
                    if type == "object" and has("name") and has("dirs") then
                        # Recursively clean nested dirs and preserve the group
                        .dirs |= remove_duplicates |
                        .
                    else
                        # Its a directory string
                        .
                    end
                ] |
                # Remove duplicate directory strings while preserving all group objects
                # We need to track seen directories separately from groups
                reduce .[] as $item (
                    {seen_dirs: [], result: []};
                    if ($item | type) == "string" then
                        if (.seen_dirs | index($item)) == null then
                            .seen_dirs += [$item] |
                            .result += [$item]
                        else
                            # This is a duplicate directory, dont add it
                            .
                        end
                    else
                        # Its a group object, always add it
                        .result += [$item]
                    end
                ) | .result
            else
                .
            end;
        
        .dirs |= remove_duplicates
    ' "$input_file")
    
    # Count how many directories were removed by comparing before and after
    local original_dir_count=$(jq '
        def count_dirs:
            if type == "array" then
                [.[] | if type == "string" then 1 elif type == "object" and has("dirs") then (.dirs | count_dirs) else 0 end] | add // 0
            else
                0
            end;
        
        .dirs | count_dirs
    ' "$input_file")
    
    local cleaned_dir_count=$(echo "$cleaned_json" | jq '
        def count_dirs:
            if type == "array" then
                [.[] | if type == "string" then 1 elif type == "object" and has("dirs") then (.dirs | count_dirs) else 0 end] | add // 0
            else
                0
            end;
        
        .dirs | count_dirs
    ')
    
    removed_count=$((original_dir_count - cleaned_dir_count))
    
    # Write cleaned JSON to output file
    if echo "$cleaned_json" > "$output_file"; then
        return "$removed_count"
    else
        return -1
    fi
}

# Edit the config file
_dir_edit_config() {
    local config_file="$HOME/.config/dir/dir.json"
    
    # Determine editor to use
    local editor="${EDITOR:-${VISUAL:-nano}}"
    
    # Temporarily restore terminal settings
    _dir_cleanup
    
    # Edit the file
    "$editor" "$config_file"
    
    # Restore our terminal settings
    printf '\e[?1049h' || printf '\e[s'
    
    # Re-parse JSON to update in-memory arrays
    if _dir_parse_json "$config_file"; then
        # Successfully parsed
        return
    else
        # JSON parsing failed, show error
        printf "${_DIR_COLOR_RESET}Error: Invalid JSON in config file!${_DIR_COLOR_RESET}\n"
        echo "Press any key to continue..."
        read -n1 -s
    fi
}

# Create a new group
_dir_create_group() {
    local path="$1"
    local config_file="$HOME/.config/dir/dir.json"
    
    # Prompt for group name
    printf "${_DIR_COLOR_HEADER}Enter group name (empty to cancel):${_DIR_COLOR_RESET}\n"
    stty echo icanon 2>/dev/null
    read -r group_name
    stty -echo -icanon 2>/dev/null
    
    # Check if empty (cancel)
    if [[ -z "$group_name" ]]; then
        return
    fi
    
    # Create group in JSON and refresh
    if _dir_add_group_to_json "$path" "$group_name" "$config_file"; then
        # Re-parse JSON to update in-memory arrays
        _dir_parse_json "$config_file"
    else
        printf "${_DIR_COLOR_RESET}Error: Failed to create group${_DIR_COLOR_RESET}\n"
        echo "Press any key to continue..."
        read -n1 -s
    fi
}

# Delete entry by index (for arrow key selection)
_dir_delete_entry_by_index() {
    local path="$1"
    local index="$2"
    local config_file="$HOME/.config/dir/dir.json"
    
    # Delete from JSON and refresh
    if _dir_delete_from_json "$path" "$index" "$config_file"; then
        # Re-parse JSON to update in-memory arrays
        _dir_parse_json "$config_file"
    fi
}

# Delete entry at specified index
_dir_delete_entry() {
    local path="$1"
    local key="$2"
    local config_file="$HOME/.config/dir/dir.json"
    
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
        # Invalid shortcut, just ignore
        return
    fi
    
    # Delete from JSON and refresh
    if _dir_delete_from_json "$path" "$index" "$config_file"; then
        # Re-parse JSON to update in-memory arrays
        _dir_parse_json "$config_file"
    fi
}
