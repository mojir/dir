#!/bin/bash

# Utility functions and constants for dir navigator

# Initialize all constants and global variables
_dir_init_constants() {
   # Color definitions
   _DIR_COLOR_RESET='\033[0m'
   _DIR_COLOR_GROUP='\033[1;34m'        # Bold blue for groups
   _DIR_COLOR_DIR='\033[0;32m'          # Green for directories  
   _DIR_COLOR_SHORTCUT='\033[1;33m'     # Bold yellow for shortcuts
   _DIR_COLOR_BREADCRUMB='\033[1;36m'   # Bold cyan for headers
   _DIR_COLOR_HEADER='\033[1;36m'       # Bold cyan for headers
   _DIR_COLOR_SELECTED='\033[1;47;30m'  # Bold white background, black text for selection
   _DIR_COLOR_SELECTED_GROUP='\033[1;44;37m'  # Bold blue background, white text for selected groups

   # Icons/indicators
   _DIR_ICON_GROUP='📁'    # Clipboard icon for groups (collections)
   _DIR_ICON_DIR='  '      # Space for directories (or could use 📁)
   _DIR_ICON_ARROW='→'     # Arrow for breadcrumbs
   _DIR_ICON_SELECTED='►' # Selection indicator

   # Alternative text-based indicators (if Unicode not preferred)
   _DIR_TEXT_GROUP='[GRP]'
   _DIR_TEXT_DIR='[DIR]'
   _DIR_TEXT_SELECTED='>'

   # Configuration for display style
   _DIR_USE_ICONS=true  # Set to false to use text indicators instead
   
   # Performance tracking
   _DIR_HEADER_LINES=0
   _DIR_ITEM_START_LINE=0
   _DIR_FOOTER_START_LINE=0
   _DIR_LAST_SELECTED=0
   
   # Number input mode
   _DIR_NUMBER_BUFFER=""
   _DIR_IN_NUMBER_MODE=false
   _DIR_NUMBER_TARGET_INDEX=0
   _DIR_ORIGINAL_SELECTION=0
   _DIR_EXIT_SCRIPT=false  # Reset on each run
   
   # Key tracking for multi-key commands
   _DIR_LAST_KEY=""
   
   # Initialize scrolling state
   _dir_init_scrolling
}

# Initialize scrolling state variables
_dir_init_scrolling() {
    _DIR_VIEWPORT_START=1      # First visible item (1-based)
    _DIR_VIEWPORT_SIZE=10      # Will be calculated based on terminal height
    _DIR_SCROLL_OFFSET=0       # For fine positioning
    
    # Calculate actual viewport size based on terminal height
    local terminal_height=$(tput lines 2>/dev/null || echo 24)
    local header_lines=5       # Title + separator + breadcrumb + spacing
    local footer_lines=3       # Spacing + help text + input area
    local available_height=$((terminal_height - header_lines - footer_lines))
    
    # Minimum viewport size
    if [[ $available_height -lt 5 ]]; then
        _DIR_VIEWPORT_SIZE=5
    else
        _DIR_VIEWPORT_SIZE=$available_height
    fi
}

# Calculate center position for viewport (with even/odd logic)
_dir_get_center_position() {
    local viewport_size="$1"
    echo $(((viewport_size / 2) + 1))
}

# Check if item index is within current viewport
_dir_is_in_viewport() {
    local item_index="$1"
    local viewport_end=$((_DIR_VIEWPORT_START + _DIR_VIEWPORT_SIZE - 1))
    
    [[ $item_index -ge $_DIR_VIEWPORT_START && $item_index -le $viewport_end ]]
}

# Center viewport on target item
_dir_center_viewport_on() {
    local target_index="$1"
    local max_items="$2"
    
    local center_pos=$(_dir_get_center_position "$_DIR_VIEWPORT_SIZE")
    local new_start=$((target_index - center_pos + 1))
    
    # Clamp to valid range
    if [[ $new_start -lt 1 ]]; then
        new_start=1
    elif [[ $((new_start + _DIR_VIEWPORT_SIZE - 1)) -gt $max_items ]]; then
        new_start=$((max_items - _DIR_VIEWPORT_SIZE + 1))
        if [[ $new_start -lt 1 ]]; then
            new_start=1
        fi
    fi
    
    _DIR_VIEWPORT_START=$new_start
}

# Scroll viewport by half-screen in given direction
_dir_scroll_half_screen() {
    local direction="$1"  # "up" or "down"
    local max_items="$2"
    local current_selection="$3"
    
    local half_screen=$((_DIR_VIEWPORT_SIZE / 2))
    if [[ $half_screen -lt 1 ]]; then
        half_screen=1
    fi
    
    if [[ "$direction" == "down" ]]; then
        local new_start=$((_DIR_VIEWPORT_START + half_screen))
        local max_start=$((max_items - _DIR_VIEWPORT_SIZE + 1))
        if [[ $max_start -lt 1 ]]; then
            max_start=1
        fi
        if [[ $new_start -gt $max_start ]]; then
            new_start=$max_start
        fi
        _DIR_VIEWPORT_START=$new_start
        
        # Adjust selection to stay in center of new viewport
        local center_pos=$(_dir_get_center_position "$_DIR_VIEWPORT_SIZE")
        local new_selection=$((_DIR_VIEWPORT_START + center_pos - 1))
        if [[ $new_selection -gt $max_items ]]; then
            new_selection=$max_items
        fi
        echo "$new_selection"
        
    elif [[ "$direction" == "up" ]]; then
        local new_start=$((_DIR_VIEWPORT_START - half_screen))
        if [[ $new_start -lt 1 ]]; then
            new_start=1
        fi
        _DIR_VIEWPORT_START=$new_start
        
        # Adjust selection to stay in center of new viewport
        local center_pos=$(_dir_get_center_position "$_DIR_VIEWPORT_SIZE")
        local new_selection=$((_DIR_VIEWPORT_START + center_pos - 1))
        if [[ $new_selection -lt 1 ]]; then
            new_selection=1
        fi
        echo "$new_selection"
    fi
}

# Smart scroll management - decides whether to scroll and how
_dir_smart_scroll() {
    local target_index="$1"
    local max_items="$2"
    local scroll_reason="$3"  # "jump", "arrow", "number"
    
    case "$scroll_reason" in
        "jump"|"number")
            # For jumps (gg, G, number+enter), always center if out of view
            if ! _dir_is_in_viewport "$target_index"; then
                _dir_center_viewport_on "$target_index" "$max_items"
            fi
            ;;
        "arrow")
            # For arrow movement, only scroll if moving outside viewport
            if ! _dir_is_in_viewport "$target_index"; then
                # Determine direction and scroll half-screen
                local viewport_end=$((_DIR_VIEWPORT_START + _DIR_VIEWPORT_SIZE - 1))
                if [[ $target_index -gt $viewport_end ]]; then
                    # Moving down beyond viewport
                    local new_selection=$(_dir_scroll_half_screen "down" "$max_items" "$target_index")
                    echo "$new_selection"
                    return
                elif [[ $target_index -lt $_DIR_VIEWPORT_START ]]; then
                    # Moving up beyond viewport  
                    local new_selection=$(_dir_scroll_half_screen "up" "$max_items" "$target_index")
                    echo "$new_selection"
                    return
                fi
            fi
            # If within viewport or no scroll needed, return original target
            echo "$target_index"
            ;;
    esac
}

# Get visible item indices for current viewport
_dir_get_visible_range() {
    local max_items="$1"
    local viewport_end=$((_DIR_VIEWPORT_START + _DIR_VIEWPORT_SIZE - 1))
    
    if [[ $viewport_end -gt $max_items ]]; then
        viewport_end=$max_items
    fi
    
    echo "$_DIR_VIEWPORT_START $viewport_end"
}

# Cleanup function to restore terminal state
_dir_cleanup() {
   # Restore cursor visibility
   printf '\e[?25h'
   # Restore terminal settings
   stty echo icanon 2>/dev/null
   # Exit alternate screen buffer or restore cursor
   printf '\e[?1049l' || printf '\e[u'
   # Reset colors
   printf "${_DIR_COLOR_RESET}"
}

# Get shortcut character for index (1-9, then a-z)
_dir_get_shortcut() {
   local index=$1
   
   if [[ $index -le 9 ]]; then
       echo "$index"
   else
       # Convert to letter (a=10, b=11, etc.)
       local letter_index=$((index - 10))
       printf "\\$(printf '%03o' $((97 + letter_index)))"
   fi
}

# Get breadcrumb path showing full navigation trail
_dir_get_breadcrumb_path() {
   local path="$1"
   local breadcrumb=""
   
   if [[ -z "$path" ]]; then
       echo "Root"
       return
   fi
   
   # Split path into parts and build breadcrumb
   IFS='/' read -ra path_parts <<< "$path"
   local current_path=""
   
   for part in "${path_parts[@]}"; do
       if [[ -n "$part" ]]; then
           current_path="${current_path}/${part}"
           local name="${_dir_names["$current_path"]}"
           
           if [[ -n "$breadcrumb" ]]; then
               breadcrumb="${breadcrumb} > ${name}"
           else
               breadcrumb="$name"
           fi
       fi
   done
   
   echo "$breadcrumb"
}

# Get the count of items in current level WITH virtual filesystem support
_dir_get_item_count() {
   local path="$1"
   
   # Handle filesystem paths
   if _dir_is_filesystem_path "$path"; then
       _dir_fs_get_item_count "$path"
       return
   fi
   
   local count=0
   local index=1
   
   while [[ -n "${_dir_items["$path/$index"]}" || ( -z "$path" && -n "${_dir_items["/$index"]}" ) ]]; do
       ((count++))
       ((index++))
   done
   
   # Add virtual filesystem entry only at root level
   if [[ -z "$path" ]]; then
       ((count++))
   fi
   
   echo "$count"
}

# Check if current level has any groups
_dir_has_groups() {
   local path="$1"
   local index=1
   
   while [[ -n "${_dir_items["$path/$index"]}" || ( -z "$path" && -n "${_dir_items["/$index"]}" ) ]]; do
       local item_path
       if [[ -z "$path" ]]; then
           item_path="/$index"
       else
           item_path="$path/$index"
       fi
       
       if [[ "${_dir_types["$item_path"]}" == "group" ]]; then
           return 0  # Has groups
       fi
       
       ((index++))
   done
   
   return 1  # No groups
}

# Check if the selected index is the virtual filesystem entry
_dir_is_virtual_filesystem_entry() {
   local selected_index="$1"
   
   # Only at root level - count saved items
   local saved_count=0
   local saved_index=1
   while [[ -n "${_dir_items["/$saved_index"]}" ]]; do
       ((saved_count++))
       ((saved_index++))
   done
   
   # Virtual entry is always after all saved items
   [[ $selected_index -eq $((saved_count + 1)) ]]
}

# Drain any pending input to avoid double-processing
_dir_drain_input() {
   while read -t 0.01 -n 1 2>/dev/null; do
       :  # Consume and discard
   done
}

# Show comprehensive help screen with virtual filesystem info
_dir_show_help() {
   local path="$1"
   
   # Clear screen and show help
   printf '\e[H\e[J\e[?25l'
   
   printf "${_DIR_COLOR_HEADER}Directory Navigator - Help${_DIR_COLOR_RESET}\n"
   printf "${_DIR_COLOR_HEADER}============================${_DIR_COLOR_RESET}\n"
   echo
   
   printf "${_DIR_COLOR_GROUP}Navigation (Both Modes):${_DIR_COLOR_RESET}\n"
   printf "  ↑/k           Move selection up\n"
   printf "  ↓/j           Move selection down\n"
   printf "  Enter or →/l  Open selected item\n"
   printf "  ←/h           Go back (if not at root)\n"
   printf "  gg            Go to first item\n"
   printf "  G             Go to last item\n"
   printf "  1-9           Quick select by number\n"
   printf "  ESC           Cancel number mode / Go back\n"
   printf "  v             Open directory in nvim\n"
   printf "  q             Quit\n"
   printf "  ?             Show this help\n"
   echo
   
   printf "${_DIR_COLOR_GROUP}Number Commands (Vim-like):${_DIR_COLOR_RESET}\n"
   printf "  5↓/5j         Move down 5 items (no wrap)\n"
   printf "  3↑/3k         Move up 3 items (no wrap)\n"
   printf "  15g           Jump to item 15 (absolute)\n"
   printf "  50Enter       Jump to item 50 and navigate/CD\n"
   printf "  12d           Delete item 12 (saved dirs only)\n"
   printf "  8v            Open item 8 in nvim\n"
   printf "  7b            Bookmark item 7 (filesystem only)\n"
   echo
   
   printf "${_DIR_COLOR_GROUP}Saved Directories Commands:${_DIR_COLOR_RESET}\n"
   printf "  a             Add current working directory\n"
   printf "  c             Clean invalid/duplicate entries\n"
   printf "  d             Delete selected item\n"
   printf "  e             Edit config file\n"
   printf "  g             Create new group\n"
   echo
   
   printf "${_DIR_COLOR_GROUP}Filesystem Browser Commands:${_DIR_COLOR_RESET}\n"
   printf "  b             Bookmark directory to saved locations\n"
   printf "  Enter         CD to directory and exit browser\n"
   printf "  →/l           Navigate only if directory has subdirs\n"
   echo
   
   # Show virtual filesystem help only at root level of saved directories
   if [[ -z "$path" ]] && ! _dir_is_filesystem_path "$path"; then
       printf "${_DIR_COLOR_GROUP}Virtual Filesystem:${_DIR_COLOR_RESET}\n"
       printf "  🗂️            Virtual filesystem browser (last entry at root)\n"
       printf "  →/l on 🗂️     Enter filesystem mode starting at current directory\n"
       echo
   fi
   
   printf "${_DIR_COLOR_GROUP}Number Mode (Both Modes):${_DIR_COLOR_RESET}\n"
   printf "  Type digits to select item by number\n"
   printf "  Enter         Navigate to/CD to selected number\n"
   printf "  d             Delete item by number (saved dirs only)\n"
   printf "  v             Open item by number in nvim\n"
   printf "  b             Bookmark item by number (filesystem only)\n"
   printf "  ESC           Cancel and restore selection\n"
   echo
   
   printf "${_DIR_COLOR_GROUP}Display Indicators:${_DIR_COLOR_RESET}\n"
   printf "  📁            Group (collection of items)\n"
   printf "  Directory     Individual directory path\n"
   if [[ -z "$path" ]] && ! _dir_is_filesystem_path "$path"; then
       printf "  🗂️            Virtual filesystem browser\n"
   fi
   printf "  (+)           Directory has subdirectories (filesystem)\n"
   printf "  ►             Current selection indicator\n"
   printf "  (n)           Number of items in group (saved dirs)\n"
   printf "  ...           More items above/below current view\n"
   echo
   
   printf "${_DIR_COLOR_SHORTCUT}Press any key to return...${_DIR_COLOR_RESET}"
   
   # Wait for any key
   read -n1 -s
   
   # Show cursor
   printf '\e[?25h'
}
