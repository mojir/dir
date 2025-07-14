#!/bin/bash

# Rendering and display functions for dir navigator

# Update only the selection indicators without full redraw
_dir_update_selection() {
   local old_index="$1"
   local new_index="$2"
   local path="$3"
   local max_items="$4"
   local number_mode="${5:-false}"
   
   # Hide cursor during updates
   printf '\e[?25l'
   
   # Clear old selection (if valid)
   if [[ $old_index -gt 0 && $old_index -le $max_items ]]; then
       local old_line=$((_DIR_ITEM_START_LINE + old_index - 1))
       printf '\e[%d;1H' "$old_line"  # Move to start of old line
       printf '  '  # Replace indicator with spaces
   fi
   
   # Draw new selection with appropriate color (only if valid)
   if [[ $new_index -gt 0 && $new_index -le $max_items ]]; then
       local new_line=$((_DIR_ITEM_START_LINE + new_index - 1))
       printf '\e[%d;1H' "$new_line"  # Move to start of new line
       
       if [[ "$number_mode" == "true" ]]; then
           printf "${_DIR_COLOR_NUMBER_MODE}${_DIR_ICON_SELECTED}${_DIR_COLOR_RESET}"
       else
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
   
   # Clear screen and hide cursor
   printf '\e[H\e[J\e[?25l'
   
   # Render header
   printf "${_DIR_COLOR_HEADER}Directory Navigator${_DIR_COLOR_RESET}\n"
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
   
   # Render all items
   _dir_render_items "$path" "$selected_index"
   
   # Calculate footer position
   local max_items=$(_dir_get_item_count "$path")
   _DIR_FOOTER_START_LINE=$((_DIR_ITEM_START_LINE + max_items + 1))
   
   # Render minimal footer
   echo
   printf "${_DIR_COLOR_SHORTCUT}Press ? for help, q to quit${_DIR_COLOR_RESET}\n"
   
   # Show cursor
   printf '\e[?25h'
}

# Render items without selection highlighting
_dir_render_items() {
   local path="$1"
   local selected_index="${2:-0}"
   local index=1
   local has_groups=$(_dir_has_groups "$path"; echo $?)
   
   # Iterate through items
   while [[ -n "${_dir_items["$path/$index"]}" || ( -z "$path" && -n "${_dir_items["/$index"]}" ) ]]; do
       local item_path
       if [[ -z "$path" ]]; then
           item_path="/$index"
       else
           item_path="$path/$index"
       fi
       
       # Render with or without selection
       if [[ $index -eq $selected_index ]]; then
           if [[ "$_DIR_IN_NUMBER_MODE" == "true" ]]; then
               printf "${_DIR_COLOR_NUMBER_MODE}${_DIR_ICON_SELECTED}${_DIR_COLOR_RESET} "
           else
               printf "${_DIR_ICON_SELECTED} "
           fi
       else
           printf "  "
       fi
       
       # Render the item content with natural numbering
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
       
       ((index++))
   done
}

# Show current directory level with optional selection highlighting
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

# Show root level directories with selection highlighting
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

# Show expanded level with parent context and selection highlighting
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
