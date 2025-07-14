#!/bin/bash

# Saved directories navigation logic for dir navigator

# Navigate through saved directories and groups
_dir_navigate_saved_level() {
    local path="$1"
    local mode="normal"  # normal or delete
    local selected_index=1  # Start with first item selected
    local max_items=$(_dir_get_item_count "$path")
    
    # Reset number mode and key tracking
    _dir_reset_number_mode
    _DIR_LAST_KEY=""
    
    # Initialize viewport for this level
    _dir_init_scrolling
    
    # Initial full render with smart viewport positioning
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
            _dir_handle_saved_number_input "$key" "$path" "$selected_index" "$max_items"
            local result=$?
            
            case $result in
                0) _DIR_LAST_KEY="$key"; continue ;;  # Stay in number mode, no visual changes
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
                    _dir_handle_saved_vim_action "$path" "$selected_index"
                    if [[ "$_DIR_EXIT_SCRIPT" == "true" ]]; then
                        return 0
                    fi
                    _DIR_LAST_KEY="$key"
                    continue
                    ;;
                7) # Number + directional movement
                    local old_viewport_start=$_DIR_VIEWPORT_START
                    selected_index="$_DIR_NUMBER_TARGET_INDEX"
                    
                    # Check if viewport changed (scrolling occurred)
                    if [[ $_DIR_VIEWPORT_START -ne $old_viewport_start ]]; then
                        # Full re-render needed due to scrolling
                        _dir_render_full "$path" "$selected_index"
                    else
                        # Just update selection indicator
                        _dir_update_selection "$_DIR_LAST_SELECTED" "$selected_index" "$path" "$max_items" "false"
                    fi
                    
                    _DIR_LAST_SELECTED=$selected_index
                    _DIR_LAST_KEY="$key"
                    continue
                    ;;
                8) # Absolute positioning (number + g)
                    local old_viewport_start=$_DIR_VIEWPORT_START
                    selected_index="$_DIR_NUMBER_TARGET_INDEX"
                    
                    # Check if viewport changed (scrolling occurred)
                    if [[ $_DIR_VIEWPORT_START -ne $old_viewport_start ]]; then
                        # Full re-render needed due to scrolling
                        _dir_render_full "$path" "$selected_index"
                    else
                        # Just update selection indicator
                        _dir_update_selection "$_DIR_LAST_SELECTED" "$selected_index" "$path" "$max_items" "false"
                    fi
                    
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
                    # Cancel number mode
                    _dir_reset_number_mode
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
                    # gg - go to first item with smart scrolling
                    if [[ $max_items -gt 0 ]]; then
                        local new_index=$(_dir_handle_jump_navigation "first" "$max_items")
                        _dir_update_selection "$_DIR_LAST_SELECTED" "$new_index" "$path" "$max_items" "false"
                        selected_index=$new_index
                        _DIR_LAST_SELECTED=$selected_index
                    fi
                fi
                # Don't reset _DIR_LAST_KEY here - let it be set at the end
                ;;
            
            'G')
                # G - go to last item with smart scrolling
                if [[ $max_items -gt 0 ]]; then
                    local new_index=$(_dir_handle_jump_navigation "last" "$max_items")
                    _dir_update_selection "$_DIR_LAST_SELECTED" "$new_index" "$path" "$max_items" "false"
                    selected_index=$new_index
                    _DIR_LAST_SELECTED=$selected_index
                fi
                ;;
            
            '?')
                # Show help screen
                _dir_show_help "$path"
                # Redraw after help - restore viewport state
                _dir_render_full "$path" "$selected_index"
                _DIR_LAST_SELECTED=$selected_index
                ;;
            
            ""|$'\n'|$'\r')  # Enter key
                if [[ "$mode" == "delete" ]]; then
                    # Don't allow deleting the virtual filesystem entry
                    if [[ -z "$path" ]] && _dir_is_virtual_filesystem_entry "$selected_index"; then
                        # Can't delete virtual entry, just cancel delete mode
                        mode="normal"
                        printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 1))"
                        _DIR_LAST_KEY="$key"
                        continue
                    fi
                    
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
                    # Came back from group/filesystem navigation, stay in current level
                    # Re-initialize scrolling state for return
                    _dir_init_scrolling
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
                
                # Use enhanced arrow navigation with smart scrolling
                local old_viewport_start=$_DIR_VIEWPORT_START
                local new_index=$(_dir_handle_arrow_navigation "$key" "$selected_index" "$max_items" "$path")
                
                # Check if viewport changed (scrolling occurred)
                if [[ $_DIR_VIEWPORT_START -ne $old_viewport_start ]]; then
                    # Full re-render needed due to scrolling
                    _dir_render_full "$path" "$new_index"
                else
                    # Just update selection indicator
                    _dir_update_selection "$_DIR_LAST_SELECTED" "$new_index" "$path" "$max_items" "false"
                fi
                
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
                
                # Use enhanced arrow navigation with smart scrolling
                local old_viewport_start=$_DIR_VIEWPORT_START
                local new_index=$(_dir_handle_arrow_navigation "$key" "$selected_index" "$max_items" "$path")
                
                # Check if viewport changed (scrolling occurred)
                if [[ $_DIR_VIEWPORT_START -ne $old_viewport_start ]]; then
                    # Full re-render needed due to scrolling
                    _dir_render_full "$path" "$new_index"
                else
                    # Just update selection indicator
                    _dir_update_selection "$_DIR_LAST_SELECTED" "$new_index" "$path" "$max_items" "false"
                fi
                
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
                
                # Check if this is the virtual filesystem entry
                if [[ -z "$path" ]] && _dir_is_virtual_filesystem_entry "$selected_index"; then
                    # Enter filesystem mode starting at current working directory
                    _dir_fs_navigate_level "$(_dir_system_to_fs_path "$(pwd)")"
                    local nav_result=$?
                    if [[ $nav_result -eq 0 ]]; then
                        return 0
                    elif [[ $nav_result -eq 99 ]]; then
                        return 99  # Propagate exit signal
                    fi
                    # Re-initialize scrolling state when returning from filesystem
                    _dir_init_scrolling
                    _dir_render_full "$path" "$selected_index"
                    _DIR_LAST_SELECTED=$selected_index
                    max_items=$(_dir_get_item_count "$path")
                    _DIR_LAST_KEY="$key"
                    continue
                fi
                
                # Regular group handling
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
                    # Re-initialize scrolling state when returning from group
                    _dir_init_scrolling
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
                    # Re-initialize scrolling and render after config changes
                    _dir_init_scrolling
                    _dir_render_full "$path" 1
                    max_items=$(_dir_get_item_count "$path")
                    selected_index=1
                    _DIR_LAST_SELECTED=1
                fi
                ;;
            
            'v')
                if [[ "$mode" == "normal" ]]; then
                    _dir_handle_saved_vim_action "$path" "$selected_index"
                    if [[ "$_DIR_EXIT_SCRIPT" == "true" ]]; then
                        return 0
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

# Handle vim action for saved directories
_dir_handle_saved_vim_action() {
    local path="$1"
    local selected_index="$2"
    
    # Check if this is the virtual filesystem entry
    if [[ -z "$path" ]] && _dir_is_virtual_filesystem_entry "$selected_index"; then
        # Open home directory in nvim
        _dir_cleanup
        nvim "$HOME"
        _DIR_EXIT_SCRIPT=true
        return
    fi
    
    # Regular directory handling
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
        fi
    fi
}

# Handle number input for saved directories navigation with clean input
_dir_handle_saved_number_input() {
    local key="$1"
    local path="$2"
    local current_selection="$3"
    local max_items="$4"
    
    case "$key" in
        [0-9])
            if [[ "$_DIR_IN_NUMBER_MODE" == "false" ]]; then
                _DIR_ORIGINAL_SELECTION=$current_selection
                _DIR_IN_NUMBER_MODE=true
            fi
            
            # Just add digit to buffer - no visual changes
            _DIR_NUMBER_BUFFER="${_DIR_NUMBER_BUFFER}${key}"
            return 0  # Stay in number mode, no visual changes
            ;;
            
        "UP"|'k')
            # Handle number + up arrow for directional movement
            if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
                local steps=$(( 10#$_DIR_NUMBER_BUFFER ))
                # Count from ORIGINAL position
                local target=$((_DIR_ORIGINAL_SELECTION - steps))
                if [[ $target -lt 1 ]]; then
                    target=1  # Clamp to beginning, no wrap
                fi
                _dir_reset_number_mode
                
                # Use smart scrolling for number + directional movement
                local final_selection=$(_dir_smart_scroll "$target" "$max_items" "number")
                if [[ -n "$final_selection" ]]; then
                    target=$final_selection
                fi
                
                _DIR_NUMBER_TARGET_INDEX=$target
                return 7  # Signal number + directional movement
            fi
            return 1  # Handle as normal arrow
            ;;
            
        "DOWN"|'j')
            # Handle number + down arrow for directional movement
            if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
                local steps=$(( 10#$_DIR_NUMBER_BUFFER ))
                # Count from ORIGINAL position
                local target=$((_DIR_ORIGINAL_SELECTION + steps))
                if [[ $target -gt $max_items ]]; then
                    target=$max_items  # Clamp to end, no wrap
                fi
                _dir_reset_number_mode
                
                # Use smart scrolling for number + directional movement
                local final_selection=$(_dir_smart_scroll "$target" "$max_items" "number")
                if [[ -n "$final_selection" ]]; then
                    target=$final_selection
                fi
                
                _DIR_NUMBER_TARGET_INDEX=$target
                return 7  # Signal number + directional movement
            fi
            return 1  # Handle as normal arrow
            ;;
            
        'g')
            # Handle number + g for absolute positioning
            if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
                local target_index=$(( 10#$_DIR_NUMBER_BUFFER ))
                _dir_reset_number_mode
                
                if [[ $target_index -gt 0 && $target_index -le $max_items ]]; then
                    # Use smart scrolling for absolute jump
                    _dir_smart_scroll "$target_index" "$max_items" "jump"
                    _DIR_NUMBER_TARGET_INDEX=$target_index
                    return 8  # Signal absolute positioning
                fi
            fi
            return 1  # Handle as normal 'g' (for gg)
            ;;
            
        ""|$'\n'|$'\r')
            if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
                local target_index=$(( 10#$_DIR_NUMBER_BUFFER ))
                _dir_reset_number_mode
                
                if [[ $target_index -gt 0 && $target_index -le $max_items ]]; then
                    # Use smart scrolling for jump navigation
                    _dir_smart_scroll "$target_index" "$max_items" "jump"
                    _dir_handle_navigation_by_index "$path" "$target_index"
                    local nav_result=$?
                    if [[ "$_DIR_EXIT_SCRIPT" == "true" ]]; then
                        return 0
                    elif [[ $nav_result -eq 1 ]]; then
                        _dir_render_full "$path" "$target_index"
                        _DIR_LAST_SELECTED=$target_index
                        return 2
                    else
                        return $nav_result
                    fi
                fi
            else
                _dir_handle_navigation_by_index "$path" "$current_selection"
                local nav_result=$?
                if [[ "$_DIR_EXIT_SCRIPT" == "true" ]]; then
                    return 0
                elif [[ $nav_result -eq 1 ]]; then
                    _dir_render_full "$path" "$current_selection"
                    _DIR_LAST_SELECTED=$current_selection
                    return 2
                else
                    return $nav_result
                fi
            fi
            return 2
            ;;
            
        'd')
            if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
                local target_index=$(( 10#$_DIR_NUMBER_BUFFER ))
                _dir_reset_number_mode
                
                if [[ $target_index -gt 0 && $target_index -le $max_items ]]; then
                    _dir_delete_entry_by_index "$path" "$target_index"
                    return 3
                fi
            else
                _dir_delete_entry_by_index "$path" "$current_selection"
                return 3
            fi
            return 2
            ;;
            
        'v')
            if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
                local target_index=$(( 10#$_DIR_NUMBER_BUFFER ))
                _dir_reset_number_mode
                
                if [[ $target_index -gt 0 && $target_index -le $max_items ]]; then
                    return 4  # Signal to handle 'v' on target
                fi
            else
                return 4  # Signal to handle 'v' on current selection
            fi
            return 2
            ;;
            
        "ESC")
            _dir_reset_number_mode
            return 1  # Handle normally
            ;;
            
        *)
            _dir_reset_number_mode
            return 1  # Handle key normally
            ;;
    esac
}

# Check if the selected index is the virtual filesystem entry
_dir_is_virtual_filesystem_entry() {
    local selected_index="$1"
    
    # Only at root level
    local saved_count=0
    local saved_index=1
    while [[ -n "${_dir_items["/$saved_index"]}" ]]; do
        ((saved_count++))
        ((saved_index++))
    done
    
    # Virtual entry is always after all saved items
    [[ $selected_index -eq $((saved_count + 1)) ]]
}
