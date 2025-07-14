#!/bin/bash

# Virtual filesystem browsing for dir navigator

# Check if a path is a filesystem path (starts with ~fs:)
_dir_is_filesystem_path() {
   local path="$1"
   [[ "$path" == ~fs:* ]]
}

# Convert filesystem path to actual system path
_dir_fs_to_system_path() {
   local fs_path="$1"
   echo "${fs_path#~fs:}"
}

# Convert system path to filesystem path
_dir_system_to_fs_path() {
   local system_path="$1"
   echo "~fs:$system_path"
}

# Get filesystem item count for a directory
_dir_fs_get_item_count() {
   local fs_path="$1"
   local system_path=$(_dir_fs_to_system_path "$fs_path")
   
   # Expand ~ if present
   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
   
   # Check if directory exists and is readable
   if [[ ! -d "$system_path" || ! -r "$system_path" ]]; then
       echo "0"
       return
   fi
   
   # Count non-hidden directories only
   local count=0
   while IFS= read -r -d '' dir; do
       ((count++))
   done < <(find "$system_path" -maxdepth 1 -type d ! -name ".*" ! -path "$system_path" -print0 2>/dev/null)
   
   echo "$count"
}

# Check if filesystem directory has subdirectories
_dir_fs_has_subdirs() {
   local fs_path="$1"
   local system_path=$(_dir_fs_to_system_path "$fs_path")
   
   # Expand ~ if present
   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
   
   # Check if directory exists and is readable
   if [[ ! -d "$system_path" || ! -r "$system_path" ]]; then
       return 1
   fi
   
   # Check for any subdirectories
   local subdir
   while IFS= read -r -d '' subdir; do
       return 0  # Found at least one subdirectory
   done < <(find "$system_path" -maxdepth 1 -type d ! -name ".*" ! -path "$system_path" -print0 2>/dev/null)
   
   return 1  # No subdirectories found
}

# Get filesystem breadcrumb path
_dir_fs_get_breadcrumb_path() {
   local fs_path="$1"
   local system_path=$(_dir_fs_to_system_path "$fs_path")
   
   # Convert to display path with ~
   local display_path=$(echo "$system_path" | sed "s|^$HOME|~|")
   
   echo "Filesystem → $display_path"
}

# Render filesystem items
_dir_fs_render_items() {
   local fs_path="$1"
   local selected_index="${2:-0}"
   local system_path=$(_dir_fs_to_system_path "$fs_path")
   
   # Expand ~ if present
   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
   
   # Check if directory exists and is readable
   if [[ ! -d "$system_path" || ! -r "$system_path" ]]; then
       printf "${_DIR_COLOR_RESET}  Error: Cannot read directory${_DIR_COLOR_RESET}\n"
       return
   fi
   
   # Get sorted list of subdirectories
   local dirs=()
   while IFS= read -r -d '' dir; do
       dirs+=("$(basename "$dir")")
   done < <(find "$system_path" -maxdepth 1 -type d ! -name ".*" ! -path "$system_path" -print0 2>/dev/null | sort -z)
   
   # Render each directory
   local index=1
   for dir_name in "${dirs[@]}"; do
       # Check for selection
       if [[ $index -eq $selected_index ]]; then
           if [[ "$_DIR_IN_NUMBER_MODE" == "true" ]]; then
               printf "${_DIR_COLOR_NUMBER_MODE}${_DIR_ICON_SELECTED}${_DIR_COLOR_RESET} "
           else
               printf "${_DIR_ICON_SELECTED} "
           fi
       else
           printf "  "
       fi
       
       # Show directory with number and check if it has subdirs
       local full_path="$system_path/$dir_name"
       
       # Check if this directory has subdirectories (for visual indication)
       if find "$full_path" -maxdepth 1 -type d ! -name ".*" ! -path "$full_path" -print -quit 2>/dev/null | grep -q .; then
           # Has subdirectories - show with (+) indicator
           printf "${_DIR_COLOR_SHORTCUT}%d${_DIR_COLOR_RESET}  ${_DIR_COLOR_DIR}%s${_DIR_COLOR_RESET} ${_DIR_COLOR_GROUP}(+)${_DIR_COLOR_RESET}\n" \
               "$index" "$dir_name"
       else
           # No subdirectories - show without indicator
           printf "${_DIR_COLOR_SHORTCUT}%d${_DIR_COLOR_RESET}  ${_DIR_COLOR_DIR}%s${_DIR_COLOR_RESET}\n" \
               "$index" "$dir_name"
       fi
       
       ((index++))
   done
}

# Navigate filesystem by index - FIXED VERSION
_dir_fs_handle_navigation_by_index() {
   local fs_path="$1"
   local index="$2"
   local system_path=$(_dir_fs_to_system_path "$fs_path")
   
   # Expand ~ if present
   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
   
   # Check if directory exists and is readable
   if [[ ! -d "$system_path" || ! -r "$system_path" ]]; then
       return 2
   fi
   
   # Get sorted list of subdirectories
   local dirs=()
   while IFS= read -r -d '' dir; do
       dirs+=("$(basename "$dir")")
   done < <(find "$system_path" -maxdepth 1 -type d ! -name ".*" ! -path "$system_path" -print0 2>/dev/null | sort -z)
   
   # Check if index is valid
   if [[ $index -lt 1 || $index -gt ${#dirs[@]} ]]; then
       return 2
   fi
   
   # Get the selected directory
   local selected_dir="${dirs[$((index - 1))]}"
   local target_path="$system_path/$selected_dir"
   
   # FIXED: Always navigate deeper in filesystem mode, don't exit to cd
   # Only cd and exit when explicitly requested (Enter key in a leaf directory)
   if _dir_fs_has_subdirs "$(_dir_system_to_fs_path "$target_path")"; then
       # Has subdirectories, navigate into it
       _dir_fs_navigate_level "$(_dir_system_to_fs_path "$target_path")"
       return $?
   else
       # No subdirectories - show empty directory in filesystem mode
       # Don't cd automatically, let user decide with Enter or 'v'
       _dir_fs_navigate_level "$(_dir_system_to_fs_path "$target_path")"
       return $?
   fi
}

# Main filesystem navigation function
_dir_fs_navigate_level() {
   local fs_path="$1"
   local mode="normal"
   local selected_index=1
   local max_items=$(_dir_fs_get_item_count "$fs_path")
   
   # Reset number mode and key tracking
   _dir_reset_number_mode
   _DIR_LAST_KEY=""
   
   # Initial full render
   _dir_fs_render_full "$fs_path" "$selected_index"
   _DIR_LAST_SELECTED=$selected_index
   
   # If no items, handle empty level
   if [[ $max_items -eq 0 ]]; then
       while true; do
           printf '\e[%d;1H' "$_DIR_FOOTER_START_LINE"
           echo
           printf "${_DIR_COLOR_SHORTCUT}No subdirectories. ?=Help, q=Quit${_DIR_COLOR_RESET}\n"
           
           key=$(_dir_read_key)
           if [[ $? -ne 0 ]]; then
               continue
           fi
           
           case "$key" in
               "ESC"|'q') return 0 ;;
               "LEFT"|'h') return 1 ;;  # Go back
               $'') # Enter key - cd to current directory and exit
                   local system_path=$(_dir_fs_to_system_path "$fs_path")
                   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
                   if cd "$system_path" 2>/dev/null; then
                       local display_path=$(echo "$system_path" | sed "s|^$HOME|~|")
                       printf "${_DIR_COLOR_DIR}Changed to: %s${_DIR_COLOR_RESET}\n" "$display_path"
                       _DIR_EXIT_SCRIPT=true
                       return 0
                   else
                       printf "${_DIR_COLOR_RESET}Error: Cannot access directory${_DIR_COLOR_RESET}\n"
                       echo "Press any key to continue..."
                       read -n1 -s
                   fi
                   ;;
               '?') 
                   _dir_show_help "$fs_path"
                   _dir_fs_render_full "$fs_path" 1
                   max_items=$(_dir_fs_get_item_count "$fs_path")
                   selected_index=1
                   _DIR_LAST_SELECTED=1
                   ;;
               'b') 
                   # Bookmark current filesystem directory to saved locations
                   local system_path=$(_dir_fs_to_system_path "$fs_path")
                   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
                   _dir_add_filesystem_dir_to_saved "$system_path"
                   ;;
               'v')
                   # Open current directory in nvim
                   local system_path=$(_dir_fs_to_system_path "$fs_path")
                   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
                   if [[ -d "$system_path" ]]; then
                       _dir_cleanup
                       nvim "$system_path"
                       _DIR_EXIT_SCRIPT=true
                       return 0
                   fi
                   ;;
           esac
       done
   fi
   
   while true; do
       # Check global exit flag first
       if [[ "$_DIR_EXIT_SCRIPT" == "true" ]]; then
           return 0
       fi
       
       # Read key input
       key=$(_dir_read_key)
       if [[ $? -ne 0 ]]; then
           continue
       fi
       
       # Handle number input for filesystem navigation
       if [[ "$_DIR_IN_NUMBER_MODE" == "true" || "$key" =~ [0-9] ]]; then
           _dir_fs_handle_number_input "$key" "$fs_path" "$selected_index" "$max_items"
           local result=$?
           
           case $result in
               0) _DIR_LAST_KEY="$key"; continue ;;
               1) ;;  # Handle key normally
               2) _DIR_LAST_KEY="$key"; continue ;;
               3) # Full redraw needed
                   max_items=$(_dir_fs_get_item_count "$fs_path")
                   if [[ $selected_index -gt $max_items && $max_items -gt 0 ]]; then
                       selected_index=$max_items
                   elif [[ $max_items -eq 0 ]]; then
                       selected_index=1
                   fi
                   _dir_fs_render_full "$fs_path" "$selected_index"
                   _DIR_LAST_SELECTED=$selected_index
                   _DIR_LAST_KEY="$key"
                   continue
                   ;;
               4) # Handle 'v' on current selection
                   local system_path=$(_dir_fs_to_system_path "$fs_path")
                   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
                   
                   # Get sorted list of subdirectories
                   local dirs=()
                   while IFS= read -r -d '' dir; do
                       dirs+=("$(basename "$dir")")
                   done < <(find "$system_path" -maxdepth 1 -type d ! -name ".*" ! -path "$system_path" -print0 2>/dev/null | sort -z)
                   
                   if [[ $selected_index -gt 0 && $selected_index -le ${#dirs[@]} ]]; then
                       local selected_dir="${dirs[$((selected_index - 1))]}"
                       local target_path="$system_path/$selected_dir"
                       
                       if [[ -d "$target_path" ]]; then
                           _dir_cleanup
                           nvim "$target_path"
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
               6) # Escape - restore selection
                   selected_index="$_DIR_NUMBER_TARGET_INDEX"
                   _dir_fs_update_selection "$_DIR_LAST_SELECTED" "$selected_index" "$fs_path" "$max_items" "false"
                   _DIR_LAST_SELECTED=$selected_index
                   _DIR_LAST_KEY="$key"
                   continue
                   ;;
               99) return 99 ;;
               *) _DIR_LAST_KEY="$key"; return $result ;;
           esac
       fi
       
       case "$key" in
           "ESC")
               if [[ "$_DIR_IN_NUMBER_MODE" == "true" ]]; then
                   _dir_reset_number_mode
                   _dir_fs_update_selection "$selected_index" "$_DIR_ORIGINAL_SELECTION" "$fs_path" "$max_items" "false"
                   selected_index="$_DIR_ORIGINAL_SELECTION"
                   _DIR_LAST_SELECTED=$selected_index
               else
                   return 1  # Go back
               fi
               ;;
           
           'q') return 0 ;;
           
           'g')
               if [[ "$_DIR_LAST_KEY" == "g" ]]; then
                   # gg - go to first item
                   if [[ $max_items -gt 0 ]]; then
                       local new_index=1
                       _dir_fs_update_selection "$_DIR_LAST_SELECTED" "$new_index" "$fs_path" "$max_items" "false"
                       selected_index=$new_index
                       _DIR_LAST_SELECTED=$selected_index
                   fi
               fi
               ;;
           
           'G')
               # G - go to last item
               if [[ $max_items -gt 0 ]]; then
                   local new_index=$max_items
                   _dir_fs_update_selection "$_DIR_LAST_SELECTED" "$new_index" "$fs_path" "$max_items" "false"
                   selected_index=$new_index
                   _DIR_LAST_SELECTED=$selected_index
               fi
               ;;
           
           '?')
               _dir_show_help "$fs_path"
               _dir_fs_render_full "$fs_path" "$selected_index"
               _DIR_LAST_SELECTED=$selected_index
               ;;
           
           "") # Enter key - cd to selected directory and exit
               if [[ $max_items -gt 0 && $selected_index -gt 0 && $selected_index -le $max_items ]]; then
                   local system_path=$(_dir_fs_to_system_path "$fs_path")
                   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
                   
                   # Get sorted list of subdirectories
                   local dirs=()
                   while IFS= read -r -d '' dir; do
                       dirs+=("$(basename "$dir")")
                   done < <(find "$system_path" -maxdepth 1 -type d ! -name ".*" ! -path "$system_path" -print0 2>/dev/null | sort -z)
                   
                   local selected_dir="${dirs[$((selected_index - 1))]}"
                   local target_path="$system_path/$selected_dir"
                   
                   # cd to selected directory and exit
                   if cd "$target_path" 2>/dev/null; then
                       local display_path=$(echo "$target_path" | sed "s|^$HOME|~|")
                       printf "${_DIR_COLOR_DIR}Changed to: %s${_DIR_COLOR_RESET}\n" "$display_path"
                       _DIR_EXIT_SCRIPT=true
                       return 0
                   else
                       printf "${_DIR_COLOR_RESET}Error: Cannot access directory %s${_DIR_COLOR_RESET}\n" "$target_path"
                       echo "Press any key to continue..."
                       read -n1 -s
                   fi
               else
                   # No selection or empty directory - cd to current directory
                   local system_path=$(_dir_fs_to_system_path "$fs_path")
                   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
                   if cd "$system_path" 2>/dev/null; then
                       local display_path=$(echo "$system_path" | sed "s|^$HOME|~|")
                       printf "${_DIR_COLOR_DIR}Changed to: %s${_DIR_COLOR_RESET}\n" "$display_path"
                       _DIR_EXIT_SCRIPT=true
                       return 0
                   fi
               fi
               ;;

           "UP"|'k')
               local new_index=$((selected_index - 1))
               if [[ $new_index -lt 1 ]]; then
                   new_index=$max_items
               fi
               _dir_fs_update_selection "$_DIR_LAST_SELECTED" "$new_index" "$fs_path" "$max_items" "false"
               selected_index=$new_index
               _DIR_LAST_SELECTED=$selected_index
               ;;
           
           "DOWN"|'j')
               local new_index=$((selected_index + 1))
               if [[ $new_index -gt $max_items ]]; then
                   new_index=1
               fi
               _dir_fs_update_selection "$_DIR_LAST_SELECTED" "$new_index" "$fs_path" "$max_items" "false"
               selected_index=$new_index
               _DIR_LAST_SELECTED=$selected_index
               ;;
           
           "RIGHT"|'l')
               # Only navigate if selected directory has subdirectories
               if [[ $max_items -gt 0 && $selected_index -gt 0 && $selected_index -le $max_items ]]; then
                   local system_path=$(_dir_fs_to_system_path "$fs_path")
                   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
                   
                   # Get sorted list of subdirectories
                   local dirs=()
                   while IFS= read -r -d '' dir; do
                       dirs+=("$(basename "$dir")")
                   done < <(find "$system_path" -maxdepth 1 -type d ! -name ".*" ! -path "$system_path" -print0 2>/dev/null | sort -z)
                   
                   local selected_dir="${dirs[$((selected_index - 1))]}"
                   local target_path="$system_path/$selected_dir"
                   
                   # Only navigate if target has subdirectories
                   if _dir_fs_has_subdirs "$(_dir_system_to_fs_path "$target_path")"; then
                       _dir_fs_handle_navigation_by_index "$fs_path" "$selected_index"
                       local nav_result=$?
                       if [[ $nav_result -eq 0 ]]; then
                           return 99  # Exit script completely (only if cd was executed)
                       elif [[ $nav_result -eq 1 ]]; then
                           # Came back from subdirectory
                           _dir_fs_render_full "$fs_path" "$selected_index"
                           _DIR_LAST_SELECTED=$selected_index
                           max_items=$(_dir_fs_get_item_count "$fs_path")
                       else
                           _dir_fs_render_full "$fs_path" "$selected_index"
                           _DIR_LAST_SELECTED=$selected_index
                           max_items=$(_dir_fs_get_item_count "$fs_path")
                       fi
                   fi
                   # If no subdirectories, do nothing (right arrow is ignored)
               fi
               ;;

           "LEFT"|'h')
               return 1  # Go back
               ;;
           
           'b')
               # Bookmark current filesystem directory to saved locations
               if [[ $max_items -gt 0 && $selected_index -gt 0 && $selected_index -le $max_items ]]; then
                   # Bookmark the selected subdirectory
                   local system_path=$(_dir_fs_to_system_path "$fs_path")
                   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
                   
                   # Get sorted list of subdirectories
                   local dirs=()
                   while IFS= read -r -d '' dir; do
                       dirs+=("$(basename "$dir")")
                   done < <(find "$system_path" -maxdepth 1 -type d ! -name ".*" ! -path "$system_path" -print0 2>/dev/null | sort -z)
                   
                   local selected_dir="${dirs[$((selected_index - 1))]}"
                   local target_path="$system_path/$selected_dir"
                   _dir_add_filesystem_dir_to_saved "$target_path"
               else
                   # Bookmark current directory if no selection or empty directory
                   local system_path=$(_dir_fs_to_system_path "$fs_path")
                   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
                   _dir_add_filesystem_dir_to_saved "$system_path"
               fi
               # Redraw after bookmarking
               _dir_fs_render_full "$fs_path" "$selected_index"
               _DIR_LAST_SELECTED=$selected_index
               ;;
           
           'v')
               # Open current directory in nvim
               if [[ $max_items -gt 0 && $selected_index -gt 0 && $selected_index -le $max_items ]]; then
                   local system_path=$(_dir_fs_to_system_path "$fs_path")
                   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
                   
                   # Get sorted list of subdirectories
                   local dirs=()
                   while IFS= read -r -d '' dir; do
                       dirs+=("$(basename "$dir")")
                   done < <(find "$system_path" -maxdepth 1 -type d ! -name ".*" ! -path "$system_path" -print0 2>/dev/null | sort -z)
                   
                   local selected_dir="${dirs[$((selected_index - 1))]}"
                   local target_path="$system_path/$selected_dir"
                   
                   if [[ -d "$target_path" ]]; then
                       _dir_cleanup
                       nvim "$target_path"
                       _DIR_EXIT_SCRIPT=true
                       return 0
                   fi
               else
                   # Open current directory if no selection
                   local system_path=$(_dir_fs_to_system_path "$fs_path")
                   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
                   if [[ -d "$system_path" ]]; then
                       _dir_cleanup
                       nvim "$system_path"
                       _DIR_EXIT_SCRIPT=true
                       return 0
                   fi
               fi
               ;;
       esac
       
       _DIR_LAST_KEY="$key"
   done
}

# Render full filesystem view
_dir_fs_render_full() {
   local fs_path="$1"
   local selected_index="${2:-0}"
   
   # Clear screen and hide cursor
   printf '\e[H\e[J\e[?25l'
   
   # Get current working directory for display
   local cwd_display=$(pwd | sed "s|^$HOME|~|")
   
   # Render header with cwd (same as saved directories)
   printf "${_DIR_COLOR_HEADER}Directory Navigator${_DIR_COLOR_RESET} ${_DIR_COLOR_BREADCRUMB}(cwd: %s)${_DIR_COLOR_RESET}\n" "$cwd_display"
   printf "${_DIR_COLOR_HEADER}===================${_DIR_COLOR_RESET}\n"
   echo
   _DIR_HEADER_LINES=3
   
   # Render breadcrumb
   printf "${_DIR_COLOR_BREADCRUMB}${_DIR_ICON_ARROW} %s${_DIR_COLOR_RESET}\n" "$(_dir_fs_get_breadcrumb_path "$fs_path")"
   echo
   _DIR_HEADER_LINES=$(((_DIR_HEADER_LINES + 2)))
   
   # Track where items start
   _DIR_ITEM_START_LINE=$((_DIR_HEADER_LINES + 1))
   
   # Render filesystem items
   _dir_fs_render_items "$fs_path" "$selected_index"
   
   # Calculate footer position
   local max_items=$(_dir_fs_get_item_count "$fs_path")
   _DIR_FOOTER_START_LINE=$((_DIR_ITEM_START_LINE + max_items + 1))
   
   # Render footer
   echo
   printf "${_DIR_COLOR_SHORTCUT}?=Help, q=Quit${_DIR_COLOR_RESET}\n"
   
   # Show cursor
   printf '\e[?25h'
}

# Update filesystem selection
_dir_fs_update_selection() {
   local old_index="$1"
   local new_index="$2"
   local fs_path="$3"
   local max_items="$4"
   local number_mode="${5:-false}"
   
   # Hide cursor during updates
   printf '\e[?25l'
   
   # Clear old selection (if valid)
   if [[ $old_index -gt 0 && $old_index -le $max_items ]]; then
       local old_line=$((_DIR_ITEM_START_LINE + old_index - 1))
       printf '\e[%d;1H' "$old_line"
       printf '  '
   fi
   
   # Draw new selection (only if valid)
   if [[ $new_index -gt 0 && $new_index -le $max_items ]]; then
       local new_line=$((_DIR_ITEM_START_LINE + new_index - 1))
       printf '\e[%d;1H' "$new_line"
       
       if [[ "$number_mode" == "true" ]]; then
           printf "${_DIR_COLOR_NUMBER_MODE}${_DIR_ICON_SELECTED}${_DIR_COLOR_RESET}"
       else
           printf "${_DIR_ICON_SELECTED}"
       fi
   fi
   
   # Position cursor after footer
   printf '\e[%d;1H\e[?25h' "$((_DIR_FOOTER_START_LINE + 1))"
}

# Handle number input for filesystem navigation
_dir_fs_handle_number_input() {
   local key="$1"
   local fs_path="$2"
   local current_selection="$3"
   local max_items="$4"
   
   case "$key" in
       [0-9])
           if [[ "$_DIR_IN_NUMBER_MODE" == "false" ]]; then
               _DIR_ORIGINAL_SELECTION=$current_selection
           fi
           
           _DIR_NUMBER_BUFFER="${_DIR_NUMBER_BUFFER}${key}"
           _DIR_IN_NUMBER_MODE=true
           
           local target_row=$(( 10#$_DIR_NUMBER_BUFFER ))
           if [[ $target_row -gt 0 && $target_row -le $max_items ]]; then
               _dir_fs_update_selection "$current_selection" "$target_row" "$fs_path" "$max_items" "true"
               _DIR_NUMBER_TARGET_INDEX=$target_row
               return 5  # Selection changed
           else
               _dir_fs_update_selection "$current_selection" "0" "$fs_path" "$max_items" "true"
               _DIR_NUMBER_TARGET_INDEX=0
               return 0  # Stay in number mode
           fi
           ;;
           
       ""|\n'|\r')
           if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
               local target_index="$_DIR_NUMBER_BUFFER"
               _dir_reset_number_mode
               
               if [[ $target_index -gt 0 && $target_index -le $max_items ]]; then
                   # For Enter key, cd to directory and exit
                   local system_path=$(_dir_fs_to_system_path "$fs_path")
                   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
                   
                   # Get sorted list of subdirectories
                   local dirs=()
                   while IFS= read -r -d '' dir; do
                       dirs+=("$(basename "$dir")")
                   done < <(find "$system_path" -maxdepth 1 -type d ! -name ".*" ! -path "$system_path" -print0 2>/dev/null | sort -z)
                   
                   local selected_dir="${dirs[$((target_index - 1))]}"
                   local target_path="$system_path/$selected_dir"
                   
                   if cd "$target_path" 2>/dev/null; then
                       local display_path=$(echo "$target_path" | sed "s|^$HOME|~|")
                       printf "${_DIR_COLOR_DIR}Changed to: %s${_DIR_COLOR_RESET}\n" "$display_path"
                       _DIR_EXIT_SCRIPT=true
                       return 99  # Exit completely
                   else
                       printf "${_DIR_COLOR_RESET}Error: Cannot access directory %s${_DIR_COLOR_RESET}\n" "$target_path"
                       echo "Press any key to continue..."
                       read -n1 -s
                       return 2
                   fi
               fi
           else
               # No number buffer, cd to current directory
               local system_path=$(_dir_fs_to_system_path "$fs_path")
               system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
               if cd "$system_path" 2>/dev/null; then
                   local display_path=$(echo "$system_path" | sed "s|^$HOME|~|")
                   printf "${_DIR_COLOR_DIR}Changed to: %s${_DIR_COLOR_RESET}\n" "$display_path"
                   _DIR_EXIT_SCRIPT=true
                   return 99  # Exit completely
               fi
           fi
           return 2
           ;;
           
       'v')
           if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
               local target_index="$_DIR_NUMBER_BUFFER"
               _dir_reset_number_mode
               
               if [[ $target_index -gt 0 && $target_index -le $max_items ]]; then
                   return 4  # Signal to handle 'v' on target
               fi
           else
               return 4  # Signal to handle 'v' on current selection
           fi
           return 2
           ;;
           
       'b')
           if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
               local target_index="$_DIR_NUMBER_BUFFER"
               _dir_reset_number_mode
               
               if [[ $target_index -gt 0 && $target_index -le $max_items ]]; then
                   # Bookmark the target directory
                   local system_path=$(_dir_fs_to_system_path "$fs_path")
                   system_path=$(echo "$system_path" | sed "s|^~|$HOME|")
                   
                   # Get sorted list of subdirectories
                   local dirs=()
                   while IFS= read -r -d '' dir; do
                       dirs+=("$(basename "$dir")")
                   done < <(find "$system_path" -maxdepth 1 -type d ! -name ".*" ! -path "$system_path" -print0 2>/dev/null | sort -z)
                   
                   local selected_dir="${dirs[$((target_index - 1))]}"
                   local target_path="$system_path/$selected_dir"
                   _dir_add_filesystem_dir_to_saved "$target_path"
                   return 3  # Signal for full redraw
               fi
           else
               # This should not happen during number input, but handle gracefully
               return 2
           fi
           return 2
           ;;
           
       "ESC")
           _dir_reset_number_mode
           _DIR_NUMBER_TARGET_INDEX=$_DIR_ORIGINAL_SELECTION
           return 6  # Signal to restore original selection
           ;;
           
       *)
           _dir_reset_number_mode
           _dir_fs_update_selection "$current_selection" "$current_selection" "$fs_path" "$max_items" "false"
           return 1  # Signal to handle key normally
           ;;
   esac
}

# Add filesystem directory to saved locations (always to root level)
_dir_add_filesystem_dir_to_saved() {
   local system_path="$1"
   local config_file="$HOME/.config/dir/dir.json"
   
   # Always add to root level (empty path = root)
   local root_path=""
   
   # Check if directory already exists in root level
   if _dir_check_duplicate "$root_path" "$system_path"; then
       # Clear the area and show message
       printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 1))"
       printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 2))"
       printf '\e[%d;1H' "$((_DIR_FOOTER_START_LINE + 1))"
       printf "${_DIR_COLOR_GROUP}Directory already exists in saved locations!${_DIR_COLOR_RESET}\n"
       printf "Press any key to continue..."
       read -n1 -s
       # Clear the message area
       printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 1))"
       printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 2))"
       return
   fi
   
   # Add directory to JSON root level and refresh
   if _dir_add_to_json "$root_path" "$system_path" "$config_file"; then
       # Re-parse JSON to update in-memory arrays
       _dir_parse_json "$config_file"
       # Clear the area and show success message
       printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 1))"
       printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 2))"
       printf '\e[%d;1H' "$((_DIR_FOOTER_START_LINE + 1))"
       printf "${_DIR_COLOR_DIR}Added to saved locations: %s${_DIR_COLOR_RESET}\n" "$(echo "$system_path" | sed "s|^$HOME|~|")"
       printf "Press any key to continue..."
       read -n1 -s
       # Clear the message area
       printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 1))"
       printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 2))"
   else
       # Clear the area and show error message
       printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 1))"
       printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 2))"
       printf '\e[%d;1H' "$((_DIR_FOOTER_START_LINE + 1))"
       printf "${_DIR_COLOR_RESET}Error: Failed to add directory${_DIR_COLOR_RESET}\n"
       printf "Press any key to continue..."
       read -n1 -s
       # Clear the message area
       printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 1))"
       printf '\e[%d;1H\e[K' "$((_DIR_FOOTER_START_LINE + 2))"
   fi
}
