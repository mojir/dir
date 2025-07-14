#!/bin/bash

# JSON parsing and manipulation functions for dir navigator

# Recursively parse a level of the JSON structure
_dir_parse_level() {
   local path_prefix="$1"
   local dirs_json="$2"
   local index=1
   
   while IFS= read -r item; do
       if [[ -z "$item" ]]; then continue; fi
       
       local current_path="${path_prefix}/${index}"
       
       if [[ "$item" == "{"* ]]; then
           # It's a nested object
           local name=$(echo "$item" | jq -r '.name')
           local count=$(echo "$item" | jq -r '.dirs | length')
           local sub_dirs=$(echo "$item" | jq -c '.dirs')
           
           _dir_items["$current_path"]="$item"
           _dir_names["$current_path"]="$name"
           _dir_types["$current_path"]="group"
           _dir_counts["$current_path"]="$count"
           
           # Recursively parse nested items
           _dir_parse_level "$current_path" "$sub_dirs"
       else
           # It's a direct directory
           local clean_path=$(echo "$item" | sed 's/^"//;s/"$//')
           _dir_items["$current_path"]="$clean_path"
           _dir_types["$current_path"]="dir"
       fi
       ((index++))
   done <<< "$(echo "$dirs_json" | jq -c '.[]')"
}

# Parse JSON into bash arrays for fast access
_dir_parse_json() {
   local config_file="$1"
   
   # Clear existing arrays
   unset _dir_items _dir_names _dir_types _dir_counts
   declare -gA _dir_items _dir_names _dir_types _dir_counts
   
   # Parse recursively starting from root
   _dir_parse_level "" "$(jq -c '.dirs' "$config_file")"
}

# Add directory to JSON file
_dir_add_to_json() {
   local path="$1"
   local new_dir="$2"
   local config_file="$3"
   local temp_file="${config_file}.tmp.$$"  # Use PID for unique temp file
   
   # Convert absolute path to use ~ if it's in home directory
   local display_path=$(echo "$new_dir" | sed "s|^$HOME|~|")
   
   # Create backup
   cp "$config_file" "$config_file.bak" 2>/dev/null || return 1
   
   if [[ -z "$path" ]]; then
       # Add to root level
       if jq --arg dir "$display_path" '.dirs += [$dir]' "$config_file" > "$temp_file"; then
           cat "$temp_file" > "$config_file" && rm -f "$temp_file"
       else
           rm -f "$temp_file"
           return 1
       fi
   else
       # Add to nested group - build jq path
       local jq_path=".dirs"
       IFS='/' read -ra path_parts <<< "$path"
       for part in "${path_parts[@]}"; do
           if [[ -n "$part" ]]; then
               local zero_based=$((part - 1))
               jq_path="${jq_path}[$zero_based].dirs"
           fi
       done
       
       # Add to the nested array
       if jq --arg dir "$display_path" "${jq_path} += [\$dir]" "$config_file" > "$temp_file"; then
           cat "$temp_file" > "$config_file" && rm -f "$temp_file"
       else
           rm -f "$temp_file"
           return 1
       fi
   fi
}

# Add group to JSON file
_dir_add_group_to_json() {
   local path="$1"
   local group_name="$2"
   local config_file="$3"
   local temp_file="${config_file}.tmp.$$"
   
   # Create backup
   cp "$config_file" "$config_file.bak" 2>/dev/null || return 1
   
   # Create the new group object
   local new_group="{\"name\": \"$group_name\", \"dirs\": []}"
   
   if [[ -z "$path" ]]; then
       # Add to root level
       if jq --argjson group "$new_group" '.dirs += [$group]' "$config_file" > "$temp_file"; then
           cat "$temp_file" > "$config_file" && rm -f "$temp_file"
       else
           rm -f "$temp_file"
           return 1
       fi
   else
       # Add to nested group - build jq path
       local jq_path=".dirs"
       IFS='/' read -ra path_parts <<< "$path"
       for part in "${path_parts[@]}"; do
           if [[ -n "$part" ]]; then
               local zero_based=$((part - 1))
               jq_path="${jq_path}[$zero_based].dirs"
           fi
       done
       
       # Add to the nested array
       if jq --argjson group "$new_group" "${jq_path} += [\$group]" "$config_file" > "$temp_file"; then
           cat "$temp_file" > "$config_file" && rm -f "$temp_file"
       else
           rm -f "$temp_file"
           return 1
       fi
   fi
}

# Delete entry from JSON file
_dir_delete_from_json() {
   local path="$1"
   local index="$2"
   local config_file="$3"
   local temp_file="${config_file}.tmp.$$"
   
   # Create backup
   cp "$config_file" "$config_file.bak" 2>/dev/null || return 1
   
   # Convert 1-based index to 0-based for jq
   local zero_based=$((index - 1))
   
   if [[ -z "$path" ]]; then
       # Delete from root level
       if jq "del(.dirs[$zero_based])" "$config_file" > "$temp_file"; then
           cat "$temp_file" > "$config_file" && rm -f "$temp_file"
       else
           rm -f "$temp_file"
           return 1
       fi
   else
       # Delete from nested group - build jq path
       local jq_path=".dirs"
       IFS='/' read -ra path_parts <<< "$path"
       for part in "${path_parts[@]}"; do
           if [[ -n "$part" ]]; then
               local part_zero_based=$((part - 1))
               jq_path="${jq_path}[$part_zero_based].dirs"
           fi
       done
       
       # Delete from the nested array
       if jq "del(${jq_path}[$zero_based])" "$config_file" > "$temp_file"; then
           cat "$temp_file" > "$config_file" && rm -f "$temp_file"
       else
           rm -f "$temp_file"
           return 1
       fi
   fi
}
