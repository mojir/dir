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
   _DIR_COLOR_NUMBER_MODE='\033[1;31m'  # Bold red for number input mode

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

# Get the count of items in current level
_dir_get_item_count() {
   local path="$1"
   local count=0
   local index=1
   
   while [[ -n "${_dir_items["$path/$index"]}" || ( -z "$path" && -n "${_dir_items["/$index"]}" ) ]]; do
       ((count++))
       ((index++))
   done
   
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

# Drain any pending input to avoid double-processing
_dir_drain_input() {
   while read -t 0.01 -n 1 2>/dev/null; do
       :  # Consume and discard
   done
}

# Show comprehensive help screen
_dir_show_help() {
   local path="$1"
   
   # Clear screen and show help
   printf '\e[H\e[J\e[?25l'
   
   printf "${_DIR_COLOR_HEADER}Directory Navigator - Help${_DIR_COLOR_RESET}\n"
   printf "${_DIR_COLOR_HEADER}============================${_DIR_COLOR_RESET}\n"
   echo
   
   printf "${_DIR_COLOR_GROUP}Navigation:${_DIR_COLOR_RESET}\n"
   printf "  ↑/k           Move selection up\n"
   printf "  ↓/j           Move selection down\n"
   printf "  Enter or →/l  Open selected item\n"
   printf "  ←/h           Go back (if not at root)\n"
   printf "  gg            Go to first item\n"
   printf "  G             Go to last item\n"
   printf "  1-9           Quick select by number\n"
   printf "  ESC           Cancel number mode / Go back\n"
   echo
   
   printf "${_DIR_COLOR_GROUP}Commands:${_DIR_COLOR_RESET}\n"
   printf "  a             Add current directory\n"
   printf "  c             Clean invalid/duplicate entries\n"
   printf "  d             Delete selected item\n"
   printf "  e             Edit config file\n"
   printf "  g             Create new group\n"
   printf "  v             Open directory in nvim\n"
   printf "  q             Quit\n"
   printf "  ?             Show this help\n"
   echo
   
   printf "${_DIR_COLOR_GROUP}Number Mode:${_DIR_COLOR_RESET}\n"
   printf "  Type digits to select item by number\n"
   printf "  Enter         Navigate to selected number\n"
   printf "  d             Delete item by number\n"
   printf "  v             Open item by number in nvim\n"
   printf "  ESC           Cancel and restore selection\n"
   echo
   
   printf "${_DIR_COLOR_GROUP}Display:${_DIR_COLOR_RESET}\n"
   printf "  📁            Group (collection of items)\n"
   printf "  Directory     Individual directory path\n"
   printf "  ►             Current selection indicator\n"
   printf "  (n)           Number of items in group\n"
   echo
   
   printf "${_DIR_COLOR_SHORTCUT}Press any key to return...${_DIR_COLOR_RESET}"
   
   # Wait for any key
   read -n1 -s
   
   # Show cursor
   printf '\e[?25h'
}
