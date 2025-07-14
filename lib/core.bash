#!/bin/bash

# Core navigation logic for dir navigator

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

# Handle navigation by index
_dir_handle_navigation_by_index() {
    local path="$1"
    local index="$2"
    
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

# Optimized navigation function with selective updates
_dir_navigate_level() {
    local path="$1"
    local mode="normal"  # normal or delete
    local selected_index=1  # Start with first item selected
    local max_items=$(_dir_get_item_count "$path")
    
    # Reset number mode and key tracking
    _dir_reset_number_mode
    _DIR_LAST_KEY=""
    
    # Initial full render
    _dir_render_full "$path" "$selected_index"
    _DIR_LAST_SELECTED=$selected_index
    
    # If no items, handle empty level
    if [[ $max_items -eq 0 ]]; then
        while true; do
            printf '\e[%d;1H' "$_DIR_FOOTER_START_LINE"
            echo
            printf "${_DIR_COLOR_SHORTCUT}No items. Press ? for help, q to quit${_DIR_COLOR_RESET}\n"
            
            key=$(_dir_read_key)
            if [[ $? -ne 0 ]]; then
                continue
            fi
            
            case "$key" in
                "ESC"|'q') return 0 ;;
                "LEFT"|'h') [[ -n "$path" ]] && return 1 ;;
                '?') 
                    _dir_show_help "$path"
                    _dir_render_full "$path" 1
                    max_items=$(_dir_get_item_count "$path")
                    selected_index=1
                    _DIR_LAST_SELECTED=1
                    ;;
                'a') _dir_add_current_dir "$path"; _dir_render_full "$path" 1; max_items=$(_dir_get_item_count "$path"); selected_index=1; _DIR_LAST_SELECTED=1 ;;
                'c') _dir_clean_config; _dir_render_full "$path" 1; max_items=$(_dir_get_item_count "$path"); selected_index=1; _DIR_LAST_SELECTED=1 ;;
                'e') _dir_edit_config; _dir_render_full "$path" 1; max_items=$(_dir_get_item_count "$path"); selected_index=1; _DIR_LAST_SELECTED=1 ;;
                'g') _dir_create_group "$path"; _dir_render_full "$path" 1; max_items=$(_dir_get_item_count "$path"); selected_index=1; _DIR_LAST_SELECTED=1 ;;
            esac
        done
    fi
    
    while true; do
        # Check global exit flag first
        if [[ "$_DIR_EXIT_SCRIPT" == "true" ]]; then
            return 0
        fi
        
        if [[ "$mode" == "delete" ]]; then
            printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 1))"
            printf "${_DIR_COLOR_GROUP}Press Enter to delete selected item, or any arrow/letter to cancel:${_DIR_COLOR_RESET}\n"
        fi
        
        # Read key input
        key=$(_dir_read_key)
        if [[ $? -ne 0 ]]; then
            continue
        fi
        
        # Handle number input first if we're in number mode or if key is a digit
        if [[ "$_DIR_IN_NUMBER_MODE" == "true" || "$key" =~ [0-9] ]]; then
            _dir_handle_number_input "$key" "$path" "$selected_index" "$max_items"
            local result=$?
            
            case $result in
                0) _DIR_LAST_KEY="$key"; continue ;;  # Stay in number mode
                1) ;;  # Handle key normally (fall through)
                2) _DIR_LAST_KEY="$key"; continue ;;  # Handled, continue loop
                3) # Full redraw needed
                    max_items=$(_dir_get_item_count "$path")
                    if [[ $selected_index -gt $max_items && $max_items -gt 0 ]]; then
                        selected_index=$max_items
                    elif [[ $max_items -eq 0 ]]; then
                        selected_index=1
                    fi
                    _dir_render_full "$path" "$selected_index"
                    _DIR_LAST_SELECTED=$selected_index
                    _DIR_LAST_KEY="$key"
                    continue
                    ;;
                4) # Handle 'v' on current selection
                    local item_path
                    if [[ -z "$path" ]]; then
                        item_path="/$selected_index"
                    else
                        item_path="$path/$selected_index"
                    fi
                    
                    if [[ -n "${_dir_items["$item_path"]}" && "${_dir_types["$item_path"]}" == "dir" ]]; then
                        local clean_path="${_dir_items["$item_path"]}"
                        local expanded_path=$(echo "$clean_path" | sed "s|^~|$HOME|")
                        
                        if [[ -d "$expanded_path" ]]; then
                            _dir_cleanup
                            nvim "$expanded_path"
                            _DIR_EXIT_SCRIPT=true
                            return 0
                        fi
                    fi
                    _DIR_LAST_KEY="$key"
                    continue
                    ;;
                5) # Selection changed - update our tracking
                    selected_index="$_DIR_NUMBER_TARGET_INDEX"
                    _DIR_LAST_SELECTED=$selected_index
                    _DIR_LAST_KEY="$key"
                    continue
                    ;;
                6) # Escape - restore original selection and clear number mode
                    selected_index="$_DIR_NUMBER_TARGET_INDEX"
                    _dir_update_selection "$_DIR_LAST_SELECTED" "$selected_index" "$path" "$max_items" "false"
                    _DIR_LAST_SELECTED=$selected_index
                    _DIR_LAST_KEY="$key"
                    continue
                    ;;
                99) # Exit script completely (from nvim or navigation)
                    return 99
                    ;;
                *) _DIR_LAST_KEY="$key"; return $result ;;  # Navigation result
            esac
        fi
        
        case "$key" in
            "ESC")
                # ESC behavior: cancel number mode if active, otherwise go back one level
                if [[ "$_DIR_IN_NUMBER_MODE" == "true" ]]; then
                    # Cancel number mode and restore original selection
                    _dir_reset_number_mode
                    _dir_update_selection "$selected_index" "$_DIR_ORIGINAL_SELECTION" "$path" "$max_items" "false"
                    selected_index="$_DIR_ORIGINAL_SELECTION"
                    _DIR_LAST_SELECTED=$selected_index
                elif [[ -n "$path" ]]; then
                    # Go back one level (only if not at root)
                    return 1
                fi
                # If at root and not in number mode, do nothing (don't exit)
                ;;
            
            'q')
                return 0
                ;;
            
            'g')
                if [[ "$_DIR_LAST_KEY" == "g" ]]; then
                    # gg - go to first item
                    if [[ $max_items -gt 0 ]]; then
                        local new_index=1
                        _dir_update_selection "$_DIR_LAST_SELECTED" "$new_index" "$path" "$max_items" "false"
                        selected_index=$new_index
                        _DIR_LAST_SELECTED=$selected_index
                    fi
                fi
                # Don't reset _DIR_LAST_KEY here - let it be set at the end
                ;;
            
            'G')
                # G - go to last item
                if [[ $max_items -gt 0 ]]; then
                    local new_index=$max_items
                    _dir_update_selection "$_DIR_LAST_SELECTED" "$new_index" "$path" "$max_items" "false"
                    selected_index=$new_index
                    _DIR_LAST_SELECTED=$selected_index
                fi
                ;;
            
            '?')
                # Show help screen
                _dir_show_help "$path"
                # Redraw after help
                _dir_render_full "$path" "$selected_index"
                _DIR_LAST_SELECTED=$selected_index
                ;;
            
            ""|$'\n'|$'\r')  # Enter key
                if [[ "$mode" == "delete" ]]; then
                    _dir_delete_entry_by_index "$path" "$selected_index"
                    max_items=$(_dir_get_item_count "$path")
                    if [[ $selected_index -gt $max_items && $max_items -gt 0 ]]; then
                        selected_index=$max_items
                    elif [[ $max_items -eq 0 ]]; then
                        selected_index=1
                    fi
                    _dir_render_full "$path" "$selected_index"
                    _DIR_LAST_SELECTED=$selected_index
                    mode="normal"
                    _DIR_LAST_KEY="$key"
                    continue
                fi
                
                # Navigate to selected item
                _dir_handle_navigation_by_index "$path" "$selected_index"
                local nav_result=$?
                if [[ $nav_result -eq 0 ]]; then
                    return 99  # Exit script completely after navigation
                elif [[ $nav_result -eq 1 ]]; then
                    # Came back from group navigation, stay in current level
                    _dir_render_full "$path" "$selected_index"
                    _DIR_LAST_SELECTED=$selected_index
                    max_items=$(_dir_get_item_count "$path")
                else
                    # Other result codes, continue
                    _dir_render_full "$path" "$selected_index"
                    _DIR_LAST_SELECTED=$selected_index
                    max_items=$(_dir_get_item_count "$path")
                fi
                ;;

            "UP"|'k')
                if [[ "$mode" == "delete" ]]; then
                    mode="normal"
                    printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 1))"
                    _DIR_LAST_KEY="$key"
                    continue
                fi
                
                local new_index=$((selected_index - 1))
                if [[ $new_index -lt 1 ]]; then
                    new_index=$max_items
                fi
                
                _dir_update_selection "$_DIR_LAST_SELECTED" "$new_index" "$path" "$max_items" "false"
                selected_index=$new_index
                _DIR_LAST_SELECTED=$selected_index
                ;;
            
            "DOWN"|'j')
                if [[ "$mode" == "delete" ]]; then
                    mode="normal"
                    printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 1))"
                    _DIR_LAST_KEY="$key"
                    continue
                fi
                
                local new_index=$((selected_index + 1))
                if [[ $new_index -gt $max_items ]]; then
                    new_index=1
                fi
                
                _dir_update_selection "$_DIR_LAST_SELECTED" "$new_index" "$path" "$max_items" "false"
                selected_index=$new_index
                _DIR_LAST_SELECTED=$selected_index
                ;;
            
            "RIGHT"|'l')
                if [[ "$mode" == "delete" ]]; then
                    mode="normal"
                    printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 1))"
                    _DIR_LAST_KEY="$key"
                    continue
                fi
                
                local item_path
                if [[ -z "$path" ]]; then
                    item_path="/$selected_index"
                else
                    item_path="$path/$selected_index"
                fi
                
                if [[ -n "${_dir_items["$item_path"]}" && "${_dir_types["$item_path"]}" == "group" ]]; then
                    _dir_navigate_level "$item_path"
                    local nav_result=$?
                    if [[ $nav_result -eq 0 ]]; then
                        return 0
                    elif [[ $nav_result -eq 99 ]]; then
                        return 99  # Propagate exit signal
                    fi
                    _dir_render_full "$path" "$selected_index"
                    _DIR_LAST_SELECTED=$selected_index
                    max_items=$(_dir_get_item_count "$path")
                fi
                ;;

            "LEFT"|'h')
                if [[ "$mode" == "delete" ]]; then
                    mode="normal"
                    printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 1))"
                    _DIR_LAST_KEY="$key"
                    continue
                fi
                
                if [[ -n "$path" ]]; then
                    return 1
                fi
                ;;
            
            'd')
                if [[ "$mode" == "normal" ]]; then
                    mode="delete"
                    _DIR_LAST_KEY="$key"
                    continue
                fi
                ;;
            
            # Lowercase commands
            'a'|'c'|'e')
                if [[ "$mode" == "normal" ]]; then
                    case "$key" in
                        'a') _dir_add_current_dir "$path" ;;
                        'c') _dir_clean_config ;;
                        'e') _dir_edit_config ;;
                    esac
                    _dir_render_full "$path" 1
                    max_items=$(_dir_get_item_count "$path")
                    selected_index=1
                    _DIR_LAST_SELECTED=1
                fi
                ;;
            
            'v')
                if [[ "$mode" == "normal" ]]; then
                    local item_path
                    if [[ -z "$path" ]]; then
                        item_path="/$selected_index"
                    else
                        item_path="$path/$selected_index"
                    fi
                    
                    if [[ -n "${_dir_items["$item_path"]}" && "${_dir_types["$item_path"]}" == "dir" ]]; then
                        local clean_path="${_dir_items["$item_path"]}"
                        local expanded_path=$(echo "$clean_path" | sed "s|^~|$HOME|")
                        
                        if [[ -d "$expanded_path" ]]; then
                            _dir_cleanup
                            nvim "$expanded_path"
                            _DIR_EXIT_SCRIPT=true
                            return 0
                        fi
                    fi
                fi
                ;;
            
            *)
                # Ignore other input
                if [[ "$mode" == "delete" ]]; then
                    mode="normal"
                    printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 1))"
                fi
                ;;
        esac
        
        # Update last key for next iteration (except for 'g' which is handled specially)
        _DIR_LAST_KEY="$key"
    done
}
