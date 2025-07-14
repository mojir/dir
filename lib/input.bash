#!/bin/bash

# Input handling functions for dir navigator

# Read key input with proper escape sequence handling including arrow keys
_dir_read_key() {
   local key
   stty -echo -icanon 2>/dev/null
   
   # Read first character
   read -n1 -s key
   
   # Check if it's an escape character (start of escape sequence)
   if [[ $(printf '%d' "'$key" 2>/dev/null) -eq 27 ]] 2>/dev/null; then
       # Read the next character to see if it's an escape sequence
       read -n1 -s -t 0.1 next_char 2>/dev/null
       if [[ "$next_char" == "[" ]]; then
           # It's likely an arrow key or other escape sequence
           read -n1 -s -t 0.1 arrow_char 2>/dev/null
           case "$arrow_char" in
               "A") echo "UP"; stty echo icanon 2>/dev/null; return 0 ;;
               "B") echo "DOWN"; stty echo icanon 2>/dev/null; return 0 ;;
               "C") echo "RIGHT"; stty echo icanon 2>/dev/null; return 0 ;;
               "D") echo "LEFT"; stty echo icanon 2>/dev/null; return 0 ;;
               *) 
                   # Other escape sequence, ignore
                   stty echo icanon 2>/dev/null
                   return 1
                   ;;
           esac
       elif [[ -n "$next_char" ]]; then
           # Other escape sequence, ignore
           stty echo icanon 2>/dev/null
           return 1
       else
           # Plain ESC key
           echo "ESC"
           stty echo icanon 2>/dev/null
           return 0
       fi
   fi
   
   stty echo icanon 2>/dev/null
   echo "$key"
   return 0
}

# Reset number mode state
_dir_reset_number_mode() {
   _DIR_NUMBER_BUFFER=""
   _DIR_IN_NUMBER_MODE=false
}

# Handle number input and commands
_dir_handle_number_input() {
   local key="$1"
   local path="$2"
   local current_selection="$3"
   local max_items="$4"
   
   case "$key" in
       [0-9])
           # Store original selection on first digit
           if [[ "$_DIR_IN_NUMBER_MODE" == "false" ]]; then
               _DIR_ORIGINAL_SELECTION=$current_selection
           fi
           
           # Add digit to buffer
           _DIR_NUMBER_BUFFER="${_DIR_NUMBER_BUFFER}${key}"
           _DIR_IN_NUMBER_MODE=true
           
           # Move indicator to the row matching the current number (if valid)
           local target_row=$(( 10#$_DIR_NUMBER_BUFFER ))  # Force decimal interpretation
           if [[ $target_row -gt 0 && $target_row -le $max_items ]]; then
               # Valid row - move indicator there
               _dir_update_selection "$current_selection" "$target_row" "$path" "$max_items" "true"
               # Store the new target for the main loop
               _DIR_NUMBER_TARGET_INDEX=$target_row
               return 5  # Signal that selection changed
           else
               # Invalid row - remove indicator (set to 0)
               _dir_update_selection "$current_selection" "0" "$path" "$max_items" "true"
               _DIR_NUMBER_TARGET_INDEX=0
               return 0  # Stay in current mode
           fi
           ;;
           
       ""|$'\n'|$'\r')  # Enter - navigate to buffered number
           if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
               local target_index="$_DIR_NUMBER_BUFFER"
               _dir_reset_number_mode
               
               # Validate target index
               if [[ $target_index -gt 0 && $target_index -le $max_items ]]; then
                   _dir_handle_navigation_by_index "$path" "$target_index"
                   local nav_result=$?
                   # Check global flag for exit
                   if [[ "$_DIR_EXIT_SCRIPT" == "true" ]]; then
                       return 0
                   elif [[ $nav_result -eq 1 ]]; then
                       # Came back from group - handle redraw here
                       _dir_render_full "$path" "$target_index"
                       _DIR_LAST_SELECTED=$target_index
                       return 2   # Continue in current level
                   else
                       return $nav_result  # Pass through other results
                   fi
               fi
           else
               # No number buffer, use current selection
               _dir_handle_navigation_by_index "$path" "$current_selection"
               local nav_result=$?
               # Check global flag for exit
               if [[ "$_DIR_EXIT_SCRIPT" == "true" ]]; then
                   return 0
               elif [[ $nav_result -eq 1 ]]; then
                   # Came back from group - handle redraw here
                   _dir_render_full "$path" "$current_selection"
                   _DIR_LAST_SELECTED=$current_selection
                   return 2   # Continue in current level
               else
                   return $nav_result  # Pass through other results
               fi
           fi
           return 2
           ;;
           
       'd')  # Delete command
           if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
               local target_index="$_DIR_NUMBER_BUFFER"
               _dir_reset_number_mode
               
               # Validate and delete
               if [[ $target_index -gt 0 && $target_index -le $max_items ]]; then
                   _dir_delete_entry_by_index "$path" "$target_index"
                   return 3  # Signal for full redraw
               fi
           else
               # No number buffer, delete current selection
               _dir_delete_entry_by_index "$path" "$current_selection"
               return 3  # Signal for full redraw
           fi
           return 2
           ;;
           
       'v')  # Nvim command
           if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
               local target_index="$_DIR_NUMBER_BUFFER"
               _dir_reset_number_mode
               
               # Validate target index
               if [[ $target_index -gt 0 && $target_index -le $max_items ]]; then
                   local item_path
                   if [[ -z "$path" ]]; then
                       item_path="/$target_index"
                   else
                       item_path="$path/$target_index"
                   fi
                   
                   # Only works on directory entries
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
           else
               # No number buffer, use current selection - handle in main loop
               return 4  # Signal to handle 'v' on current selection
           fi
           return 2
           ;;
           
       "ESC")  # Escape - cancel number mode
           _dir_reset_number_mode
           # Restore to original selection before number input started
           _DIR_NUMBER_TARGET_INDEX=$_DIR_ORIGINAL_SELECTION
           return 6  # Signal to restore original selection
           ;;
           
       *)  # Any other key - cancel number mode and handle normally
           _dir_reset_number_mode
           _dir_update_selection "$current_selection" "$current_selection" "$path" "$max_items" "false"
           return 1  # Signal to handle key normally
           ;;
   esac
}
