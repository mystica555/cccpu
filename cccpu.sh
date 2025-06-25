#!/bin/bash

# #############################################################################
#
# SCRIPT 9.0 (CPU CONTROL UTILITY)
#
# A modular command-line utility to view and manage CPU core status.
# - Default (no args): Display status only.
# - --on <cores>: Enable specified cores.
# - --off <cores>: Disable specified cores.
# - --help: Show usage information.
#
# #############################################################################

# --- xterm-256color Custom Theme Definitions ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET='\e[0m'; C_BOLD='\e[1m'
  C_TITLE='\e[1;38;5;228m'; C_HEADER='\e[1;38;5;39m'; C_CORE='\e[38;5;228m'
  C_STATUS_ON='\e[38;5;154m'; C_STATUS_OFF='\e[38;5;196m'; C_GOV='\e[38;5;141m'
  C_EPP='\e[38;5;161m'; C_INFO='\e[38;5;244m'; C_SUCCESS='\e[38;5;46m'
  C_PLUS='\e[38;5;25m'; C_PIPE='\e[38;5;32m'; C_DASH='\e[38;5;28m'; C_EQUAL='\e[38;5;22m'
else
  for v in C_RESET C_BOLD C_TITLE C_HEADER C_CORE C_STATUS_ON C_STATUS_OFF C_GOV C_EPP C_INFO C_SUCCESS C_PLUS C_PIPE C_DASH C_EQUAL; do eval "$v=''"; done
fi

# =============================================================================
# --- HELPER FUNCTIONS ---
# =============================================================================

# --- Function to display help/usage information ---
function show_help() {
    echo -e "${C_TITLE}CPU Core Control Utility${C_RESET}"
    echo -e "  A script to view and manage the online status of CPU cores."
    echo
    echo -e "${C_BOLD}USAGE:${C_RESET}"
    echo -e "  $0 [command]"
    echo
    echo -e "${C_BOLD}COMMANDS:${C_RESET}"
    echo -e "  ${C_SUCCESS}(no command)${C_RESET}    Displays the current status of all cores (default action)."
    echo -e "  ${C_SUCCESS}--on <cores>${C_RESET}    Enables the specified cores."
    echo -e "  ${C_SUCCESS}--off <cores>${C_RESET}   Disables the specified cores (cannot disable core 0)."
    echo -e "  ${C_SUCCESS}--help, -h${C_RESET}     Shows this help message."
    echo
    echo -e "${C_BOLD}CORE SPECIFICATION:${C_RESET}"
    echo -e "  The <cores> argument accepts a list in the following formats:"
    echo -e "  - A single core:       ${C_YELLOW}5${C_RESET}"
    echo -e "  - A range of cores:    ${C_YELLOW}1-3${C_RESET}"
    echo -e "  - A list of cores:     ${C_YELLOW}1,5,7${C_RESET}"
    echo -e "  - A combination:       ${C_YELLOW}1-3,5,9-11${C_RESET}"
    echo -e "  - All possible cores:  ${C_YELLOW}all${C_RESET}"
}

# --- Function to parse a user-provided core string (e.g., "1-3,7") ---
function parse_core_list() {
    local input_str=$1
    local expanded_list=""

    if [[ "$input_str" == "all" ]]; then
        # Get all cores except 0
        expanded_list=$(ls -d /sys/devices/system/cpu/cpu[0-9]* | sed 's|.*/cpu||' | grep -v '^0$' | tr '\n' ' ')
    else
        # Replace comma with space to iterate
        for part in ${input_str//,/ }; do
            if [[ $part == *-* ]]; then
                # It's a range. Use a C-style loop for a single line.
                local start=${part%-*}; local end=${part#*-}
                for ((i=start; i<=end; i++)); do expanded_list="$expanded_list $i"; done
            else
                # It's a single number
                expanded_list="$expanded_list $part"
            fi
        done
    fi
    echo "${expanded_list# }" # Trim leading space
}

# --- Function to set the online state of specified cores ---
function set_core_state() {
    local state=$1 # 1 for on, 0 for off
    local core_list=$2
    local action_str="ONLINE"
    if [ "$state" -eq 0 ]; then action_str="OFFLINE"; fi

    echo -e "${C_HEADER}Executing Core State Change: Setting cores to ${action_str}${C_RESET}"
    for i in $core_list; do
        if [ "$state" -eq 0 ] && [ "$i" -eq 0 ]; then
            echo -e "  ${C_INFO}↳ Skipping Core 0: Cannot be taken offline.${C_RESET}"
            continue
        fi

        local ONLINE_PATH="/sys/devices/system/cpu/cpu${i}/online"
        if [ -f "$ONLINE_PATH" ]; then
            echo -e "  ${C_INFO}↳ Setting Core ${i} to ${action_str}...${C_RESET}"
            echo "$state" > "$ONLINE_PATH"
        else
            echo -e "  ${C_INFO}↳ Warning: Cannot control Core ${i} (sysfs path not found).${C_RESET}"
        fi
    done
    echo -e "${C_SUCCESS}>> Action complete.${C_RESET}\n"
}

# --- Function to display the list of currently online cores ---
function show_online_cores() {
    local online_cores
    online_cores=$(cat /sys/devices/system/cpu/online)
    echo -e "${C_INFO}Verified online core string: ${C_YELLOW}${online_cores}${C_RESET}\n"
}

# --- Function to draw the detailed status table ---
function show_status_table() {
    # Define column widths
    local COL1_W=12 COL2_W=12 COL3_W=15 COL4_W=25
    local TABLE_WIDTH=$((COL1_W + COL2_W + COL3_W + COL4_W + 13))
    local TITLE="SYSTEM STATUS: ALL CORES"

    # Helper to draw a multi-colored line
    function _draw_line() {
        printf "${C_PLUS}+"; for ((i=1; i<TABLE_WIDTH-1; i++)); do printf "${1}%s" "$2"; done; printf "${C_PLUS}+\n"
    }
    # Helper to print a centered string
    function _print_centered() {
        local width=$1 text=$2 color=$3; local pad_len=$(( (width - ${#text}) / 2 ))
        printf "${color}%*s%s%*s${C_RESET}" "$pad_len" "" "$text" "$((width - ${#text} - pad_len))" ""
    }

    # Draw the table
    _draw_line "$C_EQUAL" "="
    local PAD_LEN=$(( (TABLE_WIDTH - 2 - ${#TITLE}) / 2 ))
    printf "${C_PIPE}|%*s${C_TITLE}%s${C_PIPE}%*s|\n" "$PAD_LEN" "" "$TITLE" "$((TABLE_WIDTH - 2 - ${#TITLE} - PAD_LEN))" ""
    _draw_line "$C_EQUAL" "="
    printf "${C_PIPE}| ${C_RESET}"; _print_centered "$COL1_W" "NODE" "$C_HEADER"
    printf "${C_PIPE} | ${C_RESET}"; _print_centered "$COL2_W" "STATUS" "$C_HEADER"
    printf "${C_PIPE} | ${C_RESET}"; _print_centered "$COL3_W" "GOVERNOR" "$C_HEADER"
    printf "${C_PIPE} | ${C_RESET}"; _print_centered "$COL4_W" "BIAS" "$C_HEADER"
    printf "${C_PIPE} |\n"
    _draw_line "$C_DASH" "-"

    local all_cores
    all_cores=($(ls -d /sys/devices/system/cpu/cpu[0-9]* | sed 's|.*/cpu||' | sort -n))
    for i in "${all_cores[@]}"; do
        local ONLINE_STATUS="OFFLINE" GOV="<no_signal>" EPP_VAL="<no_signal>" STATUS_COLOR="${C_STATUS_OFF}"
        local ONLINE_FILE="/sys/devices/system/cpu/cpu${i}/online"
        if [ "$i" -eq 0 ] || ( [ -f "$ONLINE_FILE" ] && [ "$(cat "$ONLINE_FILE")" -eq 1 ] ); then
            ONLINE_STATUS="ONLINE"; STATUS_COLOR="${C_STATUS_ON}"
            local GOV_FILE="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"; local EPP_FILE="/sys/devices/system/cpu/cpu${i}/cpufreq/energy_performance_preference"
            if [ -f "$GOV_FILE" ]; then GOV=$(cat "$GOV_FILE"); fi
            if [ -f "$EPP_FILE" ]; then EPP_VAL=$(cat "$EPP_FILE"); fi
        fi
        printf "${C_PIPE}| ${C_CORE}%-*s ${C_PIPE}| ${STATUS_COLOR}%-*s ${C_PIPE}| ${C_GOV}%-*s ${C_PIPE}| ${C_EPP}%-*s ${C_PIPE}|\n" "$COL1_W" "Core $i" "$COL2_W" "$ONLINE_STATUS" "$COL3_W" "$GOV" "$COL4_W" "$EPP_VAL"
    done
    _draw_line "$C_EQUAL" "="
    echo
}


# =============================================================================
# --- MAIN LOGIC ---
# =============================================================================

# Default action: If no arguments are given, just show status.
if [ -z "$1" ]; then
    show_online_cores
    show_status_table
    exit 0
fi

# Parse command-line arguments
case "$1" in
    --on|-on)
        if [ -z "$2" ]; then echo -e "${C_STATUS_OFF}Error: --on requires a core specification.${C_RESET}"; show_help; exit 1; fi
        CORE_LIST=$(parse_core_list "$2")
        set_core_state 1 "$CORE_LIST"
        show_status_table
        ;;
    --off|-off)
        if [ -z "$2" ]; then echo -e "${C_STATUS_OFF}Error: --off requires a core specification.${C_RESET}"; show_help; exit 1; fi
        CORE_LIST=$(parse_core_list "$2")
        set_core_state 0 "$CORE_LIST"
        show_status_table
        ;;
    --help|-h)
        show_help
        ;;
    *)
        echo -e "${C_STATUS_OFF}Error: Unknown option '$1'${C_RESET}"
        show_help
        exit 1
        ;;
esac
