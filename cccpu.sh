#!/bin/bash

# #############################################################################
#
# SCRIPT 19.1 (PARSER FIX)
#
# A modular command-line utility to view and manage CPU core status.
# - Fixes a critical bug where the script would hang if -g or -b were
#   provided without a value.
# - The argument parser is now more robust and integrated.
#
# #############################################################################

# --- xterm-256color Custom Theme Definitions ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET='\e[0m'; C_BOLD='\e[1m'
  C_TITLE='\e[1;38;5;228m'; C_HEADER='\e[1;38;5;39m'; C_CORE='\e[38;5;228m'
  C_STATUS_ON='\e[38;5;154m'; C_STATUS_OFF='\e[38;5;196m'; C_GOV='\e[38;5;141m'
  C_EPP='\e[38;5;161m'; C_INFO='\e[38;5;244m'; C_SUCCESS='\e[38;5;46m'; C_ERROR='\e[1;38;5;196m'
  C_PLUS='\e[38;5;47m'; C_PIPE='\e[38;5;41m'; C_DASH='\e[38;5;28m'; C_EQUAL='\e[38;5;22m'
else
  for v in C_RESET C_BOLD C_TITLE C_HEADER C_CORE C_STATUS_ON C_STATUS_OFF C_GOV C_EPP C_INFO C_SUCCESS C_ERROR C_PLUS C_PIPE C_DASH C_EQUAL; do eval "$v=''"; done
fi

# =============================================================================
# --- GLOBAL HELPERS & DEFINITIONS ---
# =============================================================================

# Define EXACT table width from final mock-up
TABLE_WIDTH=69

# Helper function to draw a multi-colored line
function draw_line() {
    printf "${C_PLUS}+"; for ((i=1; i<TABLE_WIDTH-1; i++)); do printf "${1}%s" "$2"; done; printf "${C_PLUS}+\n${C_RESET}";
}

# =============================================================================
# --- HELPER FUNCTIONS ---
# =============================================================================

function show_help() {
    echo; echo -e "${C_TITLE}CPU Core Control Utility v19.1${C_RESET}"
    echo -e "  View and manage the status and power policies of CPU cores."
    echo; echo -e "${C_BOLD}USAGE:${C_RESET}"; echo -e "  $0 [action_flags]"
    echo; echo -e "${C_BOLD}ACTIONS (can be combined):${C_RESET}"
    echo -e "  ${C_SUCCESS}(no flags)${C_RESET}        Displays the current status of all cores (default)."
    echo -e "  ${C_SUCCESS}--on [<cores>]${C_RESET}    Enables cores. Defaults to 'all' if no list is given."
    echo -e "  ${C_SUCCESS}--off [<cores>]${C_RESET}   Disables cores. Defaults to all except core 0."
    echo -e "  ${C_SUCCESS}-g, --governor <name|list>${C_RESET} Sets governor or lists available governors."
    echo -e "  ${C_SUCCESS}-b, --bias <name|list>${C_RESET}      Sets bias or lists available biases."
    echo -e "  ${C_SUCCESS}-c, --cores <cores>${C_RESET}   Specifies target cores for -g and -b flags."
    echo -e "  ${C_SUCCESS}-h, --help${C_RESET}         Shows this help message."
    echo; echo -e "${C_BOLD}CORE SPECIFICATION <cores>:${C_RESET}"; echo -e "  A list in the format: ${C_YELLOW}1-3,7${C_RESET} or ${C_YELLOW}all${C_RESET}"; echo
}

function parse_core_list() {
    local input_str=$1; local expanded_list=""
    if [[ "$input_str" == "all" ]]; then expanded_list=$(ls -d /sys/devices/system/cpu/cpu[0-9]* | sed 's|.*/cpu||' | tr '\n' ' ');
    else for part in ${input_str//,/ }; do if [[ $part == *-* ]]; then local start=${part%-*}; local end=${part#*-}; for ((i=start; i<=end; i++)); do expanded_list="$expanded_list $i"; done; else expanded_list="$expanded_list $part"; fi; done; fi
    local sorted_list; sorted_list=$(echo "${expanded_list# }" | tr ' ' '\n' | sort -n | tr '\n' ' '); echo "${sorted_list% }";
}

function get_enumerated_online_cpus() { parse_core_list "$(cat /sys/devices/system/cpu/online)"; }

function set_core_state() {
    local state=$1; local core_list=$2; local action_str="ONLINE"; if [ "$state" -eq 0 ]; then action_str="OFFLINE"; fi
    echo -e "${C_HEADER}Executing Core State Change: Setting cores to ${action_str}${C_RESET}"
    for i in $core_list; do
        if [ "$i" -eq 0 ]; then if [ "$state" -eq 1 ]; then echo -e "  ${C_INFO}↳ Verifying Core 0: Already online.${C_RESET}"; else echo -e "  ${C_INFO}↳ Skipping Core 0: Cannot be taken offline.${C_RESET}"; fi; continue; fi
        local ONLINE_PATH="/sys/devices/system/cpu/cpu${i}/online"
        if [ -f "$ONLINE_PATH" ]; then if [ "$state" -eq 1 ]; then if [ "$(cat "$ONLINE_PATH")" -eq 1 ]; then echo -e "  ${C_INFO}↳ Verifying Core ${i}: Already online.${C_RESET}"; else echo -e "  ${C_INFO}↳ Setting Core ${i} to ONLINE...${C_RESET}"; echo 1 > "$ONLINE_PATH"; fi; else echo -e "  ${C_INFO}↳ Setting Core ${i} to OFFLINE...${C_RESET}"; echo 0 > "$ONLINE_PATH"; fi;
        else echo -e "  ${C_INFO}↳ Warning: Cannot control Core ${i} (sysfs path not found).${C_RESET}"; fi
    done
    echo -e "${C_SUCCESS}>> Action complete.${C_RESET}\n"
}

function list_available_policies() {
    local policy_type=$1; local file_path=""; local title=""
    if [[ "$policy_type" == "governor" ]]; then file_path="/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"; title="Available Governors";
    elif [[ "$policy_type" == "bias" ]]; then file_path="/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_available_preferences"; title="Available Bias Profiles"; else return; fi
    echo -e "${C_HEADER}${title}:${C_RESET}"
    if [ -f "$file_path" ]; then echo -e "${C_YELLOW}$(cat "$file_path")${C_RESET}"; else echo -e "${C_ERROR}  Information not available on this system.${C_RESET}"; fi; echo
}

function check_policy_availability() {
    local core_num=$1; local policy_type=$2; local policy_value=$3
    local available_path=""; local valid=0
    if [[ "$policy_type" == "governor" ]]; then available_path="/sys/devices/system/cpu/cpu${core_num}/cpufreq/scaling_available_governors";
    elif [[ "$policy_type" == "bias" ]]; then available_path="/sys/devices/system/cpu/cpu${core_num}/cpufreq/energy_performance_available_preferences"; fi
    if [ -f "$available_path" ]; then if grep -q "\<$policy_value\>" "$available_path"; then valid=1; fi; fi
    if [ "$valid" -eq 0 ]; then echo -e "  ${C_ERROR}Error: Policy '${policy_type}' value '${policy_value}' is not available for Core ${core_num}.${C_RESET}"; return 1; fi
    return 0
}

function apply_default_policies() {
    local core_list=$1
    echo -e "${C_HEADER}Applying Default Policies...${C_RESET}"
    for i in $core_list; do
        local bias_to_set=""; if [ "$i" -le 3 ]; then bias_to_set="balance_performance"; else bias_to_set="performance"; fi
        if check_policy_availability "$i" "governor" "powersave"; then
            local GOV_PATH="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
            if [ -w "$GOV_PATH" ]; then echo -e "  ${C_INFO}↳ Core ${i}: Setting default governor to ${C_GOV}powersave${C_RESET}"; echo "powersave" > "$GOV_PATH"; fi
        fi
        if check_policy_availability "$i" "bias" "$bias_to_set"; then
            local BIAS_PATH="/sys/devices/system/cpu/cpu${i}/cpufreq/energy_performance_preference"
            if [ -w "$BIAS_PATH" ]; then echo -e "  ${C_INFO}↳ Core ${i}: Setting default bias to ${C_EPP}${bias_to_set}${C_RESET}"; echo "$bias_to_set" > "$BIAS_PATH"; fi
        fi
    done
    echo -e "${C_SUCCESS}>> Default policies applied.${C_RESET}\n"
}

function apply_power_policies() {
    local governor=$1; local bias=$2; local core_list=$3
    echo -e "${C_HEADER}Deploying Custom Power Management Policies...${C_RESET}"
    for i in $core_list; do
        local GOV_PATH="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        if [[ -n "$bias" && "$bias" != "performance" ]]; then
            if [ -f "$GOV_PATH" ] && [ "$(cat "$GOV_PATH")" == "performance" ]; then
                if check_policy_availability "$i" "governor" "powersave"; then echo -e "  ${C_INFO}↳ Core ${i}: Switching governor to 'powersave' to allow custom bias.${C_RESET}"; echo "powersave" > "$GOV_PATH"; fi
            fi
        fi
        if [[ -n "$governor" ]]; then if check_policy_availability "$i" "governor" "$governor"; then if [ -w "$GOV_PATH" ]; then echo -e "  ${C_INFO}↳ Core ${i}: Setting governor to ${C_GOV}${governor}${C_RESET}"; echo "$governor" > "$GOV_PATH"; fi; fi; fi
        if [[ -n "$bias" ]]; then if check_policy_availability "$i" "bias" "$bias"; then local BIAS_PATH="/sys/devices/system/cpu/cpu${i}/cpufreq/energy_performance_preference"; if [ -w "$BIAS_PATH" ]; then echo -e "  ${C_INFO}↳ Core ${i}: Setting bias to ${C_EPP}${bias}${C_RESET}"; echo "$bias" > "$BIAS_PATH"; fi; fi; fi
    done
    echo -e "${C_SUCCESS}>> Custom policies deployed.${C_RESET}\n"
}

function show_online_cores() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        local TITLE="CPU Core Status"
        draw_line "$C_EQUAL" "="
        local PAD_LEN=$(( (TABLE_WIDTH - ${#TITLE}) / 2 ))
        printf "${C_PIPE}|%*s${C_TITLE}%s${C_RESET}%*s${C_PIPE}|\n" "$PAD_LEN" "" "$TITLE" "$((TABLE_WIDTH - 2 - ${#TITLE} - PAD_LEN))" ""
        draw_line "$C_DASH" "-"
        local all_cores=($(ls -d /sys/devices/system/cpu/cpu[0-9]* | sed 's|.*/cpu||' | sort -n))
        local online_cores=" $(get_enumerated_online_cpus) "
        local item_width=5; local grid_width=$(( ${#all_cores[@]} * item_width ))
        local grid_pad=$(( (TABLE_WIDTH - grid_width) / 2 ))
        printf "${C_PIPE}|%*s" "$grid_pad" ""
        local grid_content=""; for i in "${all_cores[@]}"; do if [[ $online_cores == *" $i "* ]]; then grid_content+=$(printf "${C_STATUS_ON}■ %-3s${C_RESET}" "$i"); else grid_content+=$(printf "${C_STATUS_OFF}■ %-3s${C_RESET}" "$i"); fi; done
        printf "%b" "$grid_content"
        printf "%*s${C_PIPE}|\n" "$((TABLE_WIDTH - 2 - grid_width - grid_pad))" ""
        draw_line "$C_EQUAL" "="; echo ""
    else
        local online_cores_text; online_cores_text=$(get_enumerated_online_cpus)
        echo "Verified online cores:"; echo "${online_cores_text}"; echo ""
    fi
}

function show_status_table() {
    local W_NODE=10; local W_STATUS=10; local W_GOV=13; local W_BIAS=27
    function _get_centered() { local width=$1 text=$2; local pad_l=$(( (width - ${#text}) / 2 )); local pad_r=$((width - ${#text} - pad_l)); printf "%*s%s%*s" "$pad_l" "" "$text" "$pad_r"; }
    function _get_node() { local width=$1 text=$2; local num=${text##* }; local str; str=$(printf "Core %s" "$num"); local pad_l=2; local pad_r=$((width - ${#str} - pad_l)); printf "%*s%s%*s" "$pad_l" "" "$str" "$pad_r"; }
    function _get_centered_bias() { local width=$1 text=$2; local pad_l=$(( (width - ${#text}) / 2 - 2)); local pad_r=$((width - ${#text} - pad_l - 4)); printf "%*s%s%*s" "$pad_l" "" "$text" "$pad_r"; }
    local TITLE="Detailed Core Status"
    local PAD_LEN=$(( (TABLE_WIDTH - 2 - ${#TITLE}) / 2 ))
    draw_line "$C_EQUAL" "="; printf "${C_PIPE}|%*s${C_TITLE}%s${C_RESET}%*s${C_PIPE}|\n" "$PAD_LEN" "" "$TITLE" "$((TABLE_WIDTH - 2 - ${#TITLE} - PAD_LEN))" ""
    draw_line "$C_EQUAL" "="
    local h_node;   h_node=$(_get_centered "$W_NODE" "NODE"); local h_status; h_status=$(_get_centered "$W_STATUS" "STATUS"); local h_gov;    h_gov=$(_get_centered "$W_GOV" "GOVERNOR"); local h_bias;   h_bias=$(_get_centered_bias "$W_BIAS" "BIAS")
    printf "${C_PIPE}|"; printf " ${C_HEADER}%s${C_RESET} " "$h_node"; printf "${C_PIPE}|"; printf " ${C_HEADER}%s${C_RESET} " "$h_status"; printf "${C_PIPE}|"; printf " ${C_HEADER}%s${C_RESET} " "$h_gov"; printf "${C_PIPE}|"; printf " ${C_HEADER}%s${C_RESET} " "$h_bias"; printf "${C_PIPE}|\n"
    draw_line "$C_DASH" "-"
    local all_cores=($(ls -d /sys/devices/system/cpu/cpu[0-9]* | sed 's|.*/cpu||' | sort -n))
    for i in "${all_cores[@]}"; do
        local ONLINE_STATUS="OFFLINE" GOV="<no_signal>" EPP_VAL="<no_signal>" STATUS_COLOR="${C_STATUS_OFF}"; local GOV_COLOR="${C_GOV}" EPP_COLOR="${C_EPP}"
        local ONLINE_FILE="/sys/devices/system/cpu/cpu${i}/online"
        if [ "$i" -eq 0 ] || ( [ -f "$ONLINE_FILE" ] && [ "$(cat "$ONLINE_FILE")" -eq 1 ] ); then
            ONLINE_STATUS="ONLINE"; STATUS_COLOR="${C_STATUS_ON}"; local GOV_FILE="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"; local EPP_FILE="/sys/devices/system/cpu/cpu${i}/cpufreq/energy_performance_preference"
            if [ -f "$GOV_FILE" ]; then GOV=$(cat "$GOV_FILE"); fi; if [ -f "$EPP_FILE" ]; then EPP_VAL=$(cat "$EPP_FILE"); fi
        fi
        if [[ "$GOV" == "<no_signal>" ]]; then GOV_COLOR="${C_STATUS_OFF}"; fi; if [[ "$EPP_VAL" == "<no_signal>" ]]; then EPP_COLOR="${C_STATUS_OFF}"; fi
        local d_node;   d_node=$(_get_node "$W_NODE" "Core $i"); local d_status; d_status=$(_get_centered "$W_STATUS" "$ONLINE_STATUS"); local d_gov;    d_gov=$(_get_centered "$W_GOV" "$GOV"); local d_bias;   d_bias=$(_get_centered_bias "$W_BIAS" "$EPP_VAL")
        printf "${C_PIPE}|"; printf " ${C_CORE}%s${C_RESET} " "$d_node"; printf "${C_PIPE}|"; printf " ${STATUS_COLOR}%s${C_RESET} " "$d_status"; printf "${C_PIPE}|"; printf " ${GOV_COLOR}%s${C_RESET} " "$d_gov"; printf "${C_PIPE}|"; printf " ${EPP_COLOR}%s${C_RESET} " "$d_bias"; printf "${C_PIPE}|\n"
    done
    draw_line "$C_EQUAL" "=";
}

# =============================================================================
# --- MAIN LOGIC (REFACTORED PARSER) ---
# =============================================================================

echo # Start with a blank line for separation

# If no arguments are given, just show status and exit.
if [ -z "$1" ]; then
    show_online_cores
    show_status_table
    exit 0
fi

ON_CORES_STR=""; OFF_CORES_STR=""; GOVERNOR_TO_SET=""; BIAS_TO_SET=""; CORES_FOR_POLICY_STR=""; ACTION_TAKEN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --on) ACTION_TAKEN=1; if [[ -n "$2" && "$2" != -* ]]; then ON_CORES_STR="$2"; shift 2; else ON_CORES_STR="all"; shift 1; fi ;;
        --off) ACTION_TAKEN=1; if [[ -n "$2" && "$2" != -* ]]; then OFF_CORES_STR="$2"; shift 2; else OFF_CORES_STR=$(ls -d /sys/devices/system/cpu/cpu[0-9]* | sed 's|.*/cpu||' | grep -v '^0$' | tr '\n' ','); shift 1; fi ;;
        -g|--governor)
            ACTION_TAKEN=1
            if [[ -z "$2" || "$2" == -* ]]; then echo -e "${C_ERROR}Error: $1 requires an argument (e.g., 'performance' or 'list').${C_RESET}"; show_help; exit 1; fi
            if [[ "$2" == "list" ]]; then list_available_policies "governor"; exit 0; fi
            GOVERNOR_TO_SET="$2"; shift 2
            ;;
        -b|--bias)
            ACTION_TAKEN=1
            if [[ -z "$2" || "$2" == -* ]]; then echo -e "${C_ERROR}Error: $1 requires an argument (e.g., 'powersave' or 'list').${C_RESET}"; show_help; exit 1; fi
            if [[ "$2" == "list" ]]; then list_available_policies "bias"; exit 0; fi
            BIAS_TO_SET="$2"; shift 2
            ;;
        -c|--cores)
            if [[ -z "$2" || "$2" == -* ]]; then echo -e "${C_ERROR}Error: $1 requires a core specification.${C_RESET}"; show_help; exit 1; fi
            CORES_FOR_POLICY_STR="$2"; shift 2
            ;;
        -h|--help) show_help; exit 0 ;;
        *) echo -e "${C_ERROR}Error: Unknown option '$1'${C_RESET}"; show_help; exit 1 ;;
    esac
done

if [[ -n "$ON_CORES_STR" ]]; then
    cores_to_enable=$(parse_core_list "$ON_CORES_STR"); set_core_state 1 "$cores_to_enable"
    if [[ -z "$GOVERNOR_TO_SET" && -z "$BIAS_TO_SET" ]]; then apply_default_policies "$cores_to_enable"; fi
fi
if [[ -n "$OFF_CORES_STR" ]]; then set_core_state 0 "$(parse_core_list "$OFF_CORES_STR")"; fi
if [[ -n "$GOVERNOR_TO_SET" || -n "$BIAS_TO_SET" ]]; then
    TARGET_LIST=""; if [[ -n "$CORES_FOR_POLICY_STR" ]]; then TARGET_LIST=$(parse_core_list "$CORES_FOR_POLICY_STR"); else TARGET_LIST=$(get_enumerated_online_cpus); fi
    apply_power_policies "$GOVERNOR_TO_SET" "$BIAS_TO_SET" "$TARGET_LIST"
fi

if [ "$ACTION_TAKEN" -eq 1 ]; then show_online_cores; fi
show_status_table
