#!/bin/bash

# #############################################################################
#
# SCRIPT 12.2 (CORE 0 FIX)
#
# A modular command-line utility to view and manage CPU core status.
# - Fixes a bug where `all` did not include core 0 when setting policies.
#
# #############################################################################

# --- xterm-256color Custom Theme Definitions ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET='\e[0m'; C_BOLD='\e[1m'
  C_TITLE='\e[1;38;5;228m'; C_HEADER='\e[1;38;5;39m'; C_CORE='\e[38;5;228m'
  C_STATUS_ON='\e[38;5;154m'; C_STATUS_OFF='\e[38;5;196m'; C_GOV='\e[38;5;141m'
  C_EPP='\e[38;5;161m'; C_INFO='\e[38;5;244m'; C_SUCCESS='\e[38;5;46m'; C_ERROR='\e[1;38;5;196m]'
  C_PLUS='\e[38;5;47m'; C_PIPE='\e[38;5;41m'; C_DASH='\e[38;5;28m'; C_EQUAL='\e[38;5;22m'
else
  for v in C_RESET C_BOLD C_TITLE C_HEADER C_CORE C_STATUS_ON C_STATUS_OFF C_GOV C_EPP C_INFO C_SUCCESS C_ERROR C_PLUS C_PIPE C_DASH C_EQUAL; do eval "$v=''"; done
fi

# =============================================================================
# --- HELPER FUNCTIONS ---
# =============================================================================

function show_help() {
    echo -e "${C_TITLE}CPU Core Control Utility v12.2${C_RESET}"
    echo -e "  View and manage the status and power policies of CPU cores."
    echo; echo -e "${C_BOLD}USAGE:${C_RESET}"; echo -e "  $0 [action_flags]"
    echo; echo -e "${C_BOLD}ACTIONS (can be combined):${C_RESET}"
    echo -e "  ${C_SUCCESS}(no flags)${C_RESET}       Displays the current status of all cores (default)."
    echo -e "  ${C_SUCCESS}--on [<cores>]${C_RESET}   Enables cores. Defaults to 'all' if no list is given."
    echo -e "  ${C_SUCCESS}--off [<cores>]${C_RESET}  Disables cores. Defaults to all except core 0."
    echo -e "  ${C_SUCCESS}-g, --governor <name>${C_RESET}  Sets the scaling governor."
    echo -e "  ${C_SUCCESS}-b, --bias <name>${C_RESET}      Sets the energy performance bias."
    echo -e "  ${C_SUCCESS}--cores <cores>${C_RESET}   Specifies target cores for -g and -b flags."
    echo -e "  ${C_SUCCESS}-h, --help${C_RESET}        Shows this help message."
    echo; echo -e "${C_BOLD}CORE SPECIFICATION <cores>:${C_RESET}"; echo -e "  A list in the format: ${C_YELLOW}1-3,7${C_RESET} or ${C_YELLOW}all${C_RESET}"
}

function parse_core_list() {
    local input_str=$1; local expanded_list=""
    if [[ "$input_str" == "all" ]]; then
        # CORRECTED: Get ALL cores, including 0. Let the calling function decide what to do.
        expanded_list=$(ls -d /sys/devices/system/cpu/cpu[0-9]* | sed 's|.*/cpu||' | tr '\n' ' ')
    else
        for part in ${input_str//,/ }; do
            if [[ $part == *-* ]]; then
                local start=${part%-*}; local end=${part#*-}; for ((i=start; i<=end; i++)); do expanded_list="$expanded_list $i"; done
            else
                expanded_list="$expanded_list $part";
            fi
        done
    fi
    echo "${expanded_list# }";
}

function get_enumerated_online_cpus() { parse_core_list "$(cat /sys/devices/system/cpu/online)"; }

function set_core_state() {
    local state=$1; local core_list=$2; local action_str="ONLINE"; if [ "$state" -eq 0 ]; then action_str="OFFLINE"; fi
    echo -e "${C_HEADER}Executing Core State Change: Setting cores to ${action_str}${C_RESET}"
    for i in $core_list; do
        # This safety check correctly protects core 0
        if [ "$state" -eq 0 ] && [ "$i" -eq 0 ]; then echo -e "  ${C_INFO}↳ Skipping Core 0: Cannot be taken offline.${C_RESET}"; continue; fi
        local ONLINE_PATH="/sys/devices/system/cpu/cpu${i}/online"
        if [ -f "$ONLINE_PATH" ]; then
            # For --on, attempting to set core 0 online is a harmless, idempotent action.
            echo -e "  ${C_INFO}↳ Setting Core ${i} to ${action_str}...${C_RESET}"; echo "$state" > "$ONLINE_PATH";
        else
            echo -e "  ${C_INFO}↳ Warning: Cannot control Core ${i} (sysfs path not found).${C_RESET}";
        fi
    done
    echo -e "${C_SUCCESS}>> Action complete.${C_RESET}\n"
}

function apply_default_policies() {
    local core_list=$1
    echo -e "${C_HEADER}Applying Default Bias Policies...${C_RESET}"
    for i in $core_list; do
        local bias_to_set=""; if [ "$i" -le 3 ]; then bias_to_set="balance_performance"; else bias_to_set="performance"; fi
        local BIAS_PATH="/sys/devices/system/cpu/cpu${i}/cpufreq/energy_performance_preference"
        if [ -w "$BIAS_PATH" ]; then
            echo -e "  ${C_INFO}↳ Core ${i}: Setting default bias to ${C_EPP}${bias_to_set}${C_RESET}"
            echo "$bias_to_set" > "$BIAS_PATH"
        fi
    done
    echo -e "${C_SUCCESS}>> Default policies applied.${C_RESET}\n"
}

function apply_power_policies() {
    local governor=$1; local bias=$2; local core_list=$3
    echo -e "${C_HEADER}Deploying Custom Power Management Policies...${C_RESET}"
    for i in $core_list; do
        if [[ -n "$governor" ]]; then local GOV_PATH="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"; if [ -w "$GOV_PATH" ]; then echo -e "  ${C_INFO}↳ Core ${i}: Setting governor to ${C_GOV}${governor}${C_RESET}"; echo "$governor" > "$GOV_PATH"; fi; fi
        if [[ -n "$bias" ]]; then local BIAS_PATH="/sys/devices/system/cpu/cpu${i}/cpufreq/energy_performance_preference"; if [ -w "$BIAS_PATH" ]; then echo -e "  ${C_INFO}↳ Core ${i}: Setting bias to ${C_EPP}${bias}${C_RESET}"; echo "$bias" > "$BIAS_PATH"; fi; fi
    done
    echo -e "${C_SUCCESS}>> Custom policies deployed.${C_RESET}\n"
}

function show_online_cores() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        echo -e "${C_INFO}System Core Status Grid:${C_RESET}"; local all_cores=($(ls -d /sys/devices/system/cpu/cpu[0-9]* | sed 's|.*/cpu||' | sort -n)); local online_cores=" $(get_enumerated_online_cpus) "; local counter=0; local wrap_at=16
        for i in "${all_cores[@]}"; do if [[ $online_cores == *" $i "* ]]; then printf "${C_STATUS_ON}■ %-3s${C_RESET}" "$i"; else printf "${C_STATUS_OFF}■ %-3s${C_RESET}" "$i"; fi; ((counter++)); if (( counter % wrap_at == 0 )); then printf "\n"; fi; done; printf "\n\n"
    else local online_cores_text; online_cores_text=$(get_enumerated_online_cpus); echo "Verified online cores:"; echo "${online_cores_text}"; echo ""; fi
}

function show_status_table() {
    local COL1_W=12 COL2_W=12 COL3_W=15 COL4_W=25; local TABLE_WIDTH=$((COL1_W + COL2_W + COL3_W + COL4_W + 13)); local TITLE="SYSTEM STATUS: ALL CORES"
    function _draw_line() { printf "${C_PLUS}+"; for ((i=1; i<TABLE_WIDTH-1; i++)); do printf "${1}%s" "$2"; done; printf "${C_PLUS}+\n${C_RESET}"; }
    function _print_centered() { local width=$1 text=$2 color=$3; local pad_len=$(( (width - ${#text}) / 2 )); printf "${color}%*s%s%*s${C_RESET}" "$pad_len" "" "$text" "$((width - ${#text} - pad_len))" ""; }
    _draw_line "$C_EQUAL" "="; local PAD_LEN=$(( (TABLE_WIDTH - 2 - ${#TITLE}) / 2 )); printf "${C_PIPE}|%*s${C_TITLE}%s${C_PIPE}%*s|\n" "$PAD_LEN" "" "$TITLE" "$((TABLE_WIDTH - 2 - ${#TITLE} - PAD_LEN))"; _draw_line "$C_EQUAL" "="
    printf "${C_PIPE}| ${C_RESET}"; _print_centered "$COL1_W" "NODE" "$C_HEADER"; printf "${C_PIPE} | ${C_RESET}"; _print_centered "$COL2_W" "STATUS" "$C_HEADER"; printf "${C_PIPE} | ${C_RESET}"; _print_centered "$COL3_W" "GOVERNOR" "$C_HEADER"; printf "${C_PIPE} | ${C_RESET}"; _print_centered "$COL4_W" "BIAS" "$C_HEADER"; printf "${C_PIPE} |\n"; _draw_line "$C_DASH" "-"
    local all_cores=($(ls -d /sys/devices/system/cpu/cpu[0-9]* | sed 's|.*/cpu||' | sort -n))
    for i in "${all_cores[@]}"; do
        local ONLINE_STATUS="OFFLINE" GOV="<no_signal>" EPP_VAL="<no_signal>" STATUS_COLOR="${C_STATUS_OFF}"; local GOV_COLOR="${C_GOV}" EPP_COLOR="${C_EPP}"
        local ONLINE_FILE="/sys/devices/system/cpu/cpu${i}/online"
        if [ "$i" -eq 0 ] || ( [ -f "$ONLINE_FILE" ] && [ "$(cat "$ONLINE_FILE")" -eq 1 ] ); then
            ONLINE_STATUS="ONLINE"; STATUS_COLOR="${C_STATUS_ON}"; local GOV_FILE="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"; local EPP_FILE="/sys/devices/system/cpu/cpu${i}/cpufreq/energy_performance_preference"
            if [ -f "$GOV_FILE" ]; then GOV=$(cat "$GOV_FILE"); fi; if [ -f "$EPP_FILE" ]; then EPP_VAL=$(cat "$EPP_FILE"); fi
        fi
        if [[ "$GOV" == "<no_signal>" ]]; then GOV_COLOR="${C_STATUS_OFF}"; fi; if [[ "$EPP_VAL" == "<no_signal>" ]]; then EPP_COLOR="${C_STATUS_OFF}"; fi
        printf "${C_PIPE}| ${C_CORE}%-*s ${C_PIPE}| ${STATUS_COLOR}%-*s ${C_PIPE}| ${GOV_COLOR}%-*s ${C_PIPE}| ${EPP_COLOR}%-*s ${C_PIPE}|\n" "$COL1_W" "Core $i" "$COL2_W" "$ONLINE_STATUS" "$COL3_W" "$GOV" "$COL4_W" "$EPP_VAL"
    done
    _draw_line "$C_EQUAL" "="; echo
}

# =============================================================================
# --- MAIN LOGIC ---
# =============================================================================

if [ -z "$1" ]; then show_online_cores; show_status_table; exit 0; fi
ON_CORES_STR=""; OFF_CORES_STR=""; GOVERNOR_TO_SET=""; BIAS_TO_SET=""; CORES_FOR_POLICY_STR=""; ACTION_TAKEN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --on)
            ACTION_TAKEN=1; if [[ -n "$2" && "$2" != -* ]]; then ON_CORES_STR="$2"; shift 2; else ON_CORES_STR="all"; shift 1; fi ;;
        --off)
            ACTION_TAKEN=1; if [[ -n "$2" && "$2" != -* ]]; then OFF_CORES_STR="$2"; shift 2;
            else OFF_CORES_STR=$(ls -d /sys/devices/system/cpu/cpu[0-9]* | sed 's|.*/cpu||' | grep -v '^0$' | tr '\n' ','); shift 1; fi ;;
        -g|--governor) GOVERNOR_TO_SET="$2"; ACTION_TAKEN=1; shift 2 ;;
        -b|--bias) BIAS_TO_SET="$2"; ACTION_TAKEN=1; shift 2 ;;
        --cores) CORES_FOR_POLICY_STR="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo -e "${C_ERROR}Error: Unknown option '$1'${C_RESET}"; show_help; exit 1 ;;
    esac
done

if [[ -n "$ON_CORES_STR" ]]; then
    cores_to_enable=$(parse_core_list "$ON_CORES_STR")
    set_core_state 1 "$cores_to_enable"
    if [[ -z "$GOVERNOR_TO_SET" && -z "$BIAS_TO_SET" ]]; then
        apply_default_policies "$cores_to_enable"
    fi
fi
if [[ -n "$OFF_CORES_STR" ]]; then
    set_core_state 0 "$(parse_core_list "$OFF_CORES_STR")"
fi
if [[ -n "$GOVERNOR_TO_SET" || -n "$BIAS_TO_SET" ]]; then
    TARGET_LIST=""; if [[ -n "$CORES_FOR_POLICY_STR" ]]; then TARGET_LIST=$(parse_core_list "$CORES_FOR_POLICY_STR"); else TARGET_LIST=$(get_enumerated_online_cpus); fi
    apply_power_policies "$GOVERNOR_TO_SET" "$BIAS_TO_SET" "$TARGET_LIST"
fi

if [ "$ACTION_TAKEN" -eq 1 ]; then show_online_cores; fi
show_status_table
