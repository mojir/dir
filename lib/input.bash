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

# Clean number input handling - no visual feedback until command
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
               
               # Use smart scrolling and return target
               _dir_smart_scroll "$target" "$max_items" "number"
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
               
               # Use smart scrolling and return target
               _dir_smart_scroll "$target" "$max_items" "number"
               _DIR_NUMBER_TARGET_INDEX=$target
               return 7  # Signal number + directional movement
           fi
           return 1  # Handle as normal arrow
           ;;
           
       'g')
           # Handle number + g for absolute positioning (like vim)
           if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
               local target_index=$(( 10#$_DIR_NUMBER_BUFFER ))
               _dir_reset_number_mode
               
               # Validate target index
               if [[ $target_index -gt 0 && $target_index -le $max_items ]]; then
                   # Use smart scrolling for absolute jump
                   _dir_smart_scroll "$target_index" "$max_items" "jump"
                   _DIR_NUMBER_TARGET_INDEX=$target_index
                   return 8  # Signal absolute positioning
               fi
           fi
           return 1  # Handle as normal 'g' (for gg)
           ;;
           
       ""|$'\n'|$'\r')  # Enter - navigate to buffered number
           if [[ -n "$_DIR_NUMBER_BUFFER" ]]; then
               local target_index=$(( 10#$_DIR_NUMBER_BUFFER ))
               _dir_reset_number_mode
               
               # Validate target index
               if [[ $target_index -gt 0 && $target_index -le $max_items ]]; then
                   # Use smart scrolling for jump navigation
                   _dir_smart_scroll "$target_index" "$max_items" "jump"
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
               local target_index=$(( 10#$_DIR_NUMBER_BUFFER ))
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
               local target_index=$(( 10#$_DIR_NUMBER_BUFFER ))
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
           return 1  # Handle normally (will go back or do nothing)
           ;;
           
       *)  # Any other key - cancel number mode and handle normally
           _dir_reset_number_mode
           return 1  # Signal to handle key normally
           ;;
   esac
}

# Handle arrow key navigation with smart scrolling
_dir_handle_arrow_navigation() {
   local key="$1"
   local current_selection="$2"
   local max_items="$3"
   local path="$4"
   
   case "$key" in
       "UP"|'k')
           local new_index=$((current_selection - 1))
           if [[ $new_index -lt 1 ]]; then
               new_index=$max_items  # Wrap around to end
               # For wrap-around, use jump scrolling to center
               _dir_smart_scroll "$new_index" "$max_items" "jump"
           else
               # Regular movement - use arrow scrolling logic
               local final_selection=$(_dir_smart_scroll "$new_index" "$max_items" "arrow")
               if [[ -n "$final_selection" && "$final_selection" != "$new_index" ]]; then
                   # Scrolling occurred and adjusted selection
                   new_index=$final_selection
               fi
           fi
           echo "$new_index"
           ;;
           
       "DOWN"|'j')
           local new_index=$((current_selection + 1))
           if [[ $new_index -gt $max_items ]]; then
               new_index=1  # Wrap around to beginning
               # For wrap-around, use jump scrolling to center
               _dir_smart_scroll "$new_index" "$max_items" "jump"
           else
               # Regular movement - use arrow scrolling logic
               local final_selection=$(_dir_smart_scroll "$new_index" "$max_items" "arrow")
               if [[ -n "$final_selection" && "$final_selection" != "$new_index" ]]; then
                   # Scrolling occurred and adjusted selection
                   new_index=$final_selection
               fi
           fi
           echo "$new_index"
           ;;
   esac
}

# Handle gg and G navigation with smart scrolling
_dir_handle_jump_navigation() {
   local jump_type="$1"  # "first" or "last"
   local max_items="$2"
   
   case "$jump_type" in
       "first")
           local target=1
           _dir_smart_scroll "$target" "$max_items" "jump"
           echo "$target"
           ;;
           
       "last")
           local target=$max_items
           _dir_smart_scroll "$target" "$max_items" "jump"
           echo "$target"
           ;;
   esac
}

# Check if we should handle number + directional input
_dir_should_handle_number_directional() {
   local key="$1"
   
   case "$key" in
       "UP"|"DOWN")
           [[ "$_DIR_IN_NUMBER_MODE" == "true" && -n "$_DIR_NUMBER_BUFFER" ]]
           ;;
       *)
           return 1
           ;;
   esac
}
