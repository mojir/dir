#!/bin/bash

# Rendering and display functions for dir navigator with virtual filesystem support

# Update only the selection indicators without full redraw
_dir_update_selection() {
   local old_index="$1"
   local new_index="$2"
   local path="$3"
   local max_items="$4"
   local number_mode="${5:-false}"
   
   # Handle filesystem paths
   if _dir_is_filesystem_path "$path"; then
       _dir_fs_update_selection "$old_index" "$new_index" "$path" "$max_items" "$number_mode"
       return
   fi
   
   # Hide cursor during updates
   printf '\e[?25l'
   
   # Get visible range
   local range=($(_dir_get_visible_range "$max_items"))
   local visible_start=${range[0]}
   local visible_end=${range[1]}
   
   # Calculate line positions within viewport
   local viewport_offset=0
   if [[ $visible_start -gt 1 ]]; then
       viewport_offset=1  # Account for "... (X more above)" line
   fi
   
   # Clear old selection (if valid and visible)
   if [[ $old_index -gt 0 && $old_index -le $max_items ]]; then
       if [[ $old_index -ge $visible_start && $old_index -le $visible_end ]]; then
           local old_line=$((_DIR_ITEM_START_LINE + viewport_offset + old_index - visible_start))
           printf '\e[%d;1H' "$old_line"
           printf '  '
       fi
   fi
   
   # Draw new selection (only if valid and visible)
   if [[ $new_index -gt 0 && $new_index -le $max_items ]]; then
       if [[ $new_index -ge $visible_start && $new_index -le $visible_end ]]; then
           local new_line=$((_DIR_ITEM_START_LINE + viewport_offset + new_index - visible_start))
           printf '\e[%d;1H' "$new_line"
           
           # Always use normal selection indicator - no special number mode styling
           printf "${_DIR_ICON_SELECTED}"
       fi
   fi
   
   # Position cursor right after the footer text line
   printf '\e[%d;1H\e[?25h' "$((_DIR_FOOTER_START_LINE + 1))"
}

# Initial full render - called once, then use selective updates
_dir_render_full() {
   local path="$1"
   local selected_index="${2:-0}"
   
   # Handle filesystem paths
   if _dir_is_filesystem_path "$path"; then
       _dir_fs_render_full "$path" "$selected_index"
       return
   fi
   
   # Clear screen and hide cursor
   printf '\e[H\e[J\e[?25l'
   
   # Get current working directory for display
   local cwd_display=$(pwd | sed "s|^$HOME|~|")
   
   # Render header with cwd
   printf "${_DIR_COLOR_HEADER}Directory Navigator${_DIR_COLOR_RESET} ${_DIR_COLOR_BREADCRUMB}(cwd: %s)${_DIR_COLOR_RESET}\n" "$cwd_display"
   printf "${_DIR_COLOR_HEADER}===================${_DIR_COLOR_RESET}\n"
   echo
   _DIR_HEADER_LINES=3
   
   # Render breadcrumb if not at root
   if [[ -n "$path" ]]; then
       printf "${_DIR_COLOR_BREADCRUMB}${_DIR_ICON_ARROW} %s${_DIR_COLOR_RESET}\n" "$(_dir_get_breadcrumb_path "$path")"
       echo
       _DIR_HEADER_LINES=$(((_DIR_HEADER_LINES + 2)))
   fi
   
   # Track where items start
   _DIR_ITEM_START_LINE=$((_DIR_HEADER_LINES + 1))
   
   # Get total item count and ensure viewport is properly positioned
   local max_items=$(_dir_get_item_count "$path")
   
   # Adjust viewport if selection is out of bounds
   if [[ $selected_index -gt 0 ]]; then
       if ! _dir_is_in_viewport "$selected_index"; then
           _dir_center_viewport_on "$selected_index" "$max_items"
       fi
   fi
   
   # Render all items with viewport
   _dir_render_items_with_viewport "$path" "$selected_index" "$max_items"
   
   # Calculate footer position based on what was actually rendered
   local range=($(_dir_get_visible_range "$max_items"))
   local visible_start=${range[0]}
   local visible_end=${range[1]}
   local visible_count=$((visible_end - visible_start + 1))
   
   # Add space for scroll indicators
   local scroll_indicator_lines=0
   if [[ $visible_start -gt 1 ]]; then
       ((scroll_indicator_lines++))
   fi
   if [[ $visible_end -lt $max_items ]]; then
       ((scroll_indicator_lines++))
   fi
   
   _DIR_FOOTER_START_LINE=$((_DIR_ITEM_START_LINE + visible_count + scroll_indicator_lines + 1))
   
   # Render footer with context-appropriate commands
   echo
   printf "${_DIR_COLOR_SHORTCUT}?=Help, q=Quit${_DIR_COLOR_RESET}\n"
   
   # Show cursor
   printf '\e[?25h'
}

# Render items with viewport support - NEW FUNCTION
_dir_render_items_with_viewport() {
   local path="$1"
   local selected_index="${2:-0}"
   local max_items="$3"
   
   # Handle filesystem paths
   if _dir_is_filesystem_path "$path"; then
       _dir_fs_render_items_with_viewport "$path" "$selected_index" "$max_items"
       return
   fi
   
   # Get visible range
   local range=($(_dir_get_visible_range "$max_items"))
   local visible_start=${range[0]}
   local visible_end=${range[1]}
   
   # Show scroll indicator for items above
   if [[ $visible_start -gt 1 ]]; then
       printf "  ${_DIR_COLOR_BREADCRUMB}... (%d more above)${_DIR_COLOR_RESET}\n" $((visible_start - 1))
   fi
   
   # Render visible items
   local index=$visible_start
   local has_groups=$(_dir_has_groups "$path"; echo $?)
   
   while [[ $index -le $visible_end ]]; do
       # Handle saved items and virtual filesystem entry
       local item_path
       if [[ -z "$path" ]]; then
           item_path="/$index"
       else
           item_path="$path/$index"
       fi
       
       # Check if this item exists (might be virtual filesystem entry)
       local item_exists=false
       if [[ -n "${_dir_items["$item_path"]}" ]]; then
           item_exists=true
       elif [[ -z "$path" ]] && [[ $index -eq $max_items ]]; then
           # This is the virtual filesystem entry at root
           item_exists=true
       fi
       
       if [[ "$item_exists" == "true" ]]; then
           # Render selection indicator
           if [[ $index -eq $selected_index ]]; then
               # Always use normal selection indicator - no number mode styling
               printf "${_DIR_ICON_SELECTED} "
           else
               printf "  "
           fi
           
           # Render item content
           if [[ -n "${_dir_items["$item_path"]}" ]]; then
               # Regular saved item
               if [[ "${_dir_types["$item_path"]}" == "group" ]]; then
                   local indicator=""
                   if [[ "$_DIR_USE_ICONS" == true ]]; then
                       indicator="$_DIR_ICON_GROUP"
                   else
                       indicator="$_DIR_TEXT_GROUP"
                   fi
                   printf "${_DIR_COLOR_SHORTCUT}%d${_DIR_COLOR_RESET}  %s ${_DIR_COLOR_GROUP}%s${_DIR_COLOR_RESET} ${_DIR_COLOR_GROUP}(%d)${_DIR_COLOR_RESET}\n" \
                       "$index" "$indicator" "${_dir_names["$item_path"]}" "${_dir_counts["$item_path"]}"
               else
                   local display_path=$(echo "${_dir_items["$item_path"]}" | sed "s|^$HOME|~|")
                   if [[ $has_groups -eq 0 ]]; then
                       # Has groups, show indicator
                       local indicator=""
                       if [[ "$_DIR_USE_ICONS" == true ]]; then
                           indicator="$_DIR_ICON_DIR"
                       else
                           indicator="$_DIR_TEXT_DIR"
                       fi
                       printf "${_DIR_COLOR_SHORTCUT}%d${_DIR_COLOR_RESET}  %s ${_DIR_COLOR_DIR}%s${_DIR_COLOR_RESET}\n" \
                           "$index" "$indicator" "$display_path"
                   else
                       # No groups, compact display
                       printf "${_DIR_COLOR_SHORTCUT}%d${_DIR_COLOR_RESET}  ${_DIR_COLOR_DIR}%s${_DIR_COLOR_RESET}\n" \
                           "$index" "$display_path"
                   fi
               fi
           else
               # Virtual filesystem entry
               local indicator=""
               if [[ "$_DIR_USE_ICONS" == true ]]; then
                   indicator="🗂️"  # Different icon for filesystem browser
               else
                   indicator="[FS]"
               fi
               
               # Get current working directory for display
               local cwd_display=$(pwd | sed "s|^$HOME|~|")
               printf "${_DIR_COLOR_SHORTCUT}%d${_DIR_COLOR_RESET}  %s ${_DIR_COLOR_BREADCRUMB}%s (browse filesystem)${_DIR_COLOR_RESET}\n" \
                   "$index" "$indicator" "$cwd_display"
           fi
       fi
       
       ((index++))
   done
   
   # Show scroll indicator for items below
   if [[ $visible_end -lt $max_items ]]; then
       printf "  ${_DIR_COLOR_BREADCRUMB}... (%d more below)${_DIR_COLOR_RESET}\n" $((max_items - visible_end))
   fi
}

# LEGACY FUNCTIONS - Keep for compatibility but mark as deprecated

# Render items without selection highlighting WITHOUT viewport support (LEGACY)
_dir_render_items() {
   local path="$1"
   local selected_index="${2:-0}"
   
   # Redirect to viewport version for consistency
   local max_items=$(_dir_get_item_count "$path")
   _dir_render_items_with_viewport "$path" "$selected_index" "$max_items"
}

# Show current directory level with optional selection highlighting (LEGACY)
_dir_show_level() {
   local path="$1"
   local selected_index="${2:-0}"  # 0 means no selection
   
   printf "${_DIR_COLOR_HEADER}Directory Navigator${_DIR_COLOR_RESET}\n"
   printf "${_DIR_COLOR_HEADER}===================${_DIR_COLOR_RESET}\n"
   echo
   
   if [[ -z "$path" ]]; then
       # Show root level
       _dir_show_root_level "$selected_index"
   else
       # Show expanded level with parent context
       _dir_show_expanded_level "$path" "$selected_index"
   fi
   
   echo
   if [[ -z "$path" ]]; then
       echo "Navigation: ↑/↓=Select, Enter/→=Open, 1-9/a-z=Select, A=Add, C=Clean, D=Delete, E=Edit, G=Group, Q/Esc=Quit"
   else
       echo "Navigation: ↑/↓=Select, Enter/→=Open, ←/0=Back, 1-9/a-z=Select, A=Add, C=Clean, D=Delete, E=Edit, G=Group, V=Nvim, Q/Esc=Quit"
   fi
}

# Show root level directories with selection highlighting (LEGACY)
_dir_show_root_level() {
   local selected_index="${1:-0}"
   local index=1
   local shortcut
   local has_groups=$(_dir_has_groups ""; echo $?)
   
   # Iterate through root level items
   while [[ -n "${_dir_items["/$index"]}" ]]; do
       shortcut=$(_dir_get_shortcut $index)
       
       if [[ $index -eq $selected_index ]]; then
           # Selected item - show with selection indicator (no color inversion)
           if [[ "${_dir_types["/$index"]}" == "group" ]]; then
               local indicator=""
               if [[ "$_DIR_USE_ICONS" == true ]]; then
                   indicator="$_DIR_ICON_GROUP"
               else
                   indicator="$_DIR_TEXT_GROUP"
               fi
               
               printf "${_DIR_ICON_SELECTED} ${_DIR_COLOR_SHORTCUT}%s${_DIR_COLOR_RESET}  %s ${_DIR_COLOR_GROUP}%s${_DIR_COLOR_RESET} ${_DIR_COLOR_GROUP}(%d)${_DIR_COLOR_RESET}\n" \
                   "$shortcut" "$indicator" "${_dir_names["/$index"]}" "${_dir_counts["/$index"]}"
           else
               local display_path=$(echo "${_dir_items["/$index"]}" | sed "s|^$HOME|~|")
               if [[ $has_groups -eq 0 ]]; then
                   # Has groups, show indicator
                   local indicator=""
                   if [[ "$_DIR_USE_ICONS" == true ]]; then
                       indicator="$_DIR_ICON_DIR"
                   else
                       indicator="$_DIR_TEXT_DIR"
                   fi
                   printf "${_DIR_ICON_SELECTED} ${_DIR_COLOR_SHORTCUT}%s${_DIR_COLOR_RESET}  %s ${_DIR_COLOR_DIR}%s${_DIR_COLOR_RESET}\n" \
                       "$shortcut" "$indicator" "$display_path"
               else
                   # No groups, compact display
                   printf "${_DIR_ICON_SELECTED} ${_DIR_COLOR_SHORTCUT}%s${_DIR_COLOR_RESET}  ${_DIR_COLOR_DIR}%s${_DIR_COLOR_RESET}\n" \
                       "$shortcut" "$display_path"
               fi
           fi
       else
           # Unselected item - normal display with two spaces padding
           if [[ "${_dir_types["/$index"]}" == "group" ]]; then
               local indicator=""
               if [[ "$_DIR_USE_ICONS" == true ]]; then
                   indicator="$_DIR_ICON_GROUP"
               else
                   indicator="$_DIR_TEXT_GROUP"
               fi
               
               printf "  ${_DIR_COLOR_SHORTCUT}%s${_DIR_COLOR_RESET}  %s ${_DIR_COLOR_GROUP}%s${_DIR_COLOR_RESET} ${_DIR_COLOR_GROUP}(%d)${_DIR_COLOR_RESET}\n" \
                   "$shortcut" "$indicator" "${_dir_names["/$index"]}" "${_dir_counts["/$index"]}"
           else
               local display_path=$(echo "${_dir_items["/$index"]}" | sed "s|^$HOME|~|")
               if [[ $has_groups -eq 0 ]]; then
                   # Has groups, show indicator
                   local indicator=""
                   if [[ "$_DIR_USE_ICONS" == true ]]; then
                       indicator="$_DIR_ICON_DIR"
                   else
                       indicator="$_DIR_TEXT_DIR"
                   fi
                   printf "  ${_DIR_COLOR_SHORTCUT}%s${_DIR_COLOR_RESET}  %s ${_DIR_COLOR_DIR}%s${_DIR_COLOR_RESET}\n" \
                       "$shortcut" "$indicator" "$display_path"
               else
                   # No groups, compact display
                   printf "  ${_DIR_COLOR_SHORTCUT}%s${_DIR_COLOR_RESET}  ${_DIR_COLOR_DIR}%s${_DIR_COLOR_RESET}\n" \
                       "$shortcut" "$display_path"
               fi
           fi
       fi
       
       ((index++))
   done
}

# Show expanded level with parent context and selection highlighting (LEGACY)
_dir_show_expanded_level() {
   local path="$1"
   local selected_index="${2:-0}"
   local has_groups=$(_dir_has_groups "$path"; echo $?)
   
   # Show breadcrumb path
   printf "${_DIR_COLOR_BREADCRUMB}${_DIR_ICON_ARROW} %s${_DIR_COLOR_RESET}\n" "$(_dir_get_breadcrumb_path "$path")"
   echo
   
   # Show current level items with shortcuts and selection
   local index=1
   local shortcut
   
   # Iterate through items in this group
   while [[ -n "${_dir_items["$path/$index"]}" ]]; do
       shortcut=$(_dir_get_shortcut $index)
       
       if [[ $index -eq $selected_index ]]; then
           # Selected item - show with selection indicator (no color inversion)
           if [[ "${_dir_types["$path/$index"]}" == "group" ]]; then
               local indicator=""
               if [[ "$_DIR_USE_ICONS" == true ]]; then
                   indicator="$_DIR_ICON_GROUP"
               else
                   indicator="$_DIR_TEXT_GROUP"
               fi
               
               printf "${_DIR_ICON_SELECTED} ${_DIR_COLOR_SHORTCUT}%s${_DIR_COLOR_RESET}  %s ${_DIR_COLOR_GROUP}%s${_DIR_COLOR_RESET} ${_DIR_COLOR_GROUP}(%d)${_DIR_COLOR_RESET}\n" \
                   "$shortcut" "$indicator" "${_dir_names["$path/$index"]}" "${_dir_counts["$path/$index"]}"
           else
               local display_path=$(echo "${_dir_items["$path/$index"]}" | sed "s|^$HOME|~|")
               if [[ $has_groups -eq 0 ]]; then
                   # Has groups, show indicator
                   local indicator=""
                   if [[ "$_DIR_USE_ICONS" == true ]]; then
                       indicator="$_DIR_ICON_DIR"
                   else
                       indicator="$_DIR_TEXT_DIR"
                   fi
                   printf "${_DIR_ICON_SELECTED} ${_DIR_COLOR_SHORTCUT}%s${_DIR_COLOR_RESET}  %s ${_DIR_COLOR_DIR}%s${_DIR_COLOR_RESET}\n" \
                       "$shortcut" "$indicator" "$display_path"
               else
                   # No groups, compact display
                   printf "${_DIR_ICON_SELECTED} ${_DIR_COLOR_SHORTCUT}%s${_DIR_COLOR_RESET}  ${_DIR_COLOR_DIR}%s${_DIR_COLOR_RESET}\n" \
                       "$shortcut" "$display_path"
               fi
           fi
       else
           # Unselected item - normal display with two spaces padding
           if [[ "${_dir_types["$path/$index"]}" == "group" ]]; then
               local indicator=""
               if [[ "$_DIR_USE_ICONS" == true ]]; then
                   indicator="$_DIR_ICON_GROUP"
               else
                   indicator="$_DIR_TEXT_GROUP"
               fi
               
               printf "  ${_DIR_COLOR_SHORTCUT}%s${_DIR_COLOR_RESET}  %s ${_DIR_COLOR_GROUP}%s${_DIR_COLOR_RESET} ${_DIR_COLOR_GROUP}(%d)${_DIR_COLOR_RESET}\n" \
                   "$shortcut" "$indicator" "${_dir_names["$path/$index"]}" "${_dir_counts["$path/$index"]}"
           else
               local display_path=$(echo "${_dir_items["$path/$index"]}" | sed "s|^$HOME|~|")
               if [[ $has_groups -eq 0 ]]; then
                   # Has groups, show indicator
                   local indicator=""
                   if [[ "$_DIR_USE_ICONS" == true ]]; then
                       indicator="$_DIR_ICON_DIR"
                   else
                       indicator="$_DIR_TEXT_DIR"
                   fi
                   printf "  ${_DIR_COLOR_SHORTCUT}%s${_DIR_COLOR_RESET}  %s ${_DIR_COLOR_DIR}%s${_DIR_COLOR_RESET}\n" \
                       "$shortcut" "$indicator" "$display_path"
               else
                   # No groups, compact display
                   printf "  ${_DIR_COLOR_SHORTCUT}%s${_DIR_COLOR_RESET}  ${_DIR_COLOR_DIR}%s${_DIR_COLOR_RESET}\n" \
                       "$shortcut" "$display_path"
               fi
           fi
       fi
       
       ((index++))
   done
}
