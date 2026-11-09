#!/bin/bash

# #############################################################################
#
# Copyright (c) 2025, Mike Hodson, Mystica Online Technologies, Lakewood Colorado 
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# #############################################################################
#
# CCCPU - CPU Core Control & Power Utility v
#
# A modular command-line utility to view and manage CPU core status.
#
# #############################################################################

# --- xterm-256color Custom Theme Definitions ---
COLOR_VARS='C_RESET C_BOLD C_TITLE C_HEADER C_CORE C_STATUS_ON C_STATUS_OFF C_GOV C_EPP C_INFO C_SUCCESS C_ERROR C_YELLOW C_FRAME'
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  # Real ESC bytes (ANSI-C quoting) so the colors print correctly through %s.
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'
  C_TITLE=$'\e[1;38;5;228m'; C_HEADER=$'\e[1;38;5;39m'; C_CORE=$'\e[38;5;228m'
  C_STATUS_ON=$'\e[38;5;154m'; C_STATUS_OFF=$'\e[38;5;196m'; C_GOV=$'\e[38;5;141m'
  C_EPP=$'\e[38;5;161m'; C_INFO=$'\e[38;5;244m'; C_SUCCESS=$'\e[38;5;46m'; C_ERROR=$'\e[1;38;5;196m'
  C_YELLOW=$'\e[1;38;5;228m'; C_FRAME=$'\e[38;5;45m'
else
  for v in $COLOR_VARS; do eval "$v=''"; done
fi

# =============================================================================
# --- GLOBAL HELPERS & DEFINITIONS ---
# =============================================================================

# Column content widths. Every cell gets one space of padding on each side.
COL_NODE=10; COL_STATUS=9; COL_GOV=14; COL_BIAS=23

# Derived geometry: four cells + three inner dividers + the two outer walls.
# Rules, titles and rows all use these values, so they can never drift apart.
TABLE_WIDTH=$(( (COL_NODE+2) + (COL_STATUS+2) + (COL_GOV+2) + (COL_BIAS+2) + 3 + 2 ))
TABLE_INNER=$(( TABLE_WIDTH - 2 ))

# Frame glyphs. ASCII is the default because every box-drawing character is
# East-Asian "Ambiguous" width: a terminal whose font fallback supplies it may
# draw it two columns wide, which doubles the rules and breaks the frame.
# --unicode selects the single-line box set for terminals that draw it at one
# column; single-line is much more widely covered than the double-line set.
G_TL='+'; G_TR='+'; G_BL='+'; G_BR='+'
G_H='=';  G_V='|';  G_VL='|'
G_LT='+'; G_RT='+'; G_TT='+'; G_BT='+'; G_CT='+'
G_ON='#'; G_OFF='.'

# Swap the frame and status markers to their single-line Unicode equivalents.
function set_box_style() {
    [[ ${1:-} == "unicode" ]] || return 0
    G_TL='┌'; G_TR='┐'; G_BL='└'; G_BR='┘'
    G_H='─';  G_V='│';  G_VL='│'
    G_LT='├'; G_RT='┤'; G_TT='┬'; G_BT='┴'; G_CT='┼'
    G_ON='■'; G_OFF='□'
}

# Echo glyph $1 repeated $2 times as plain text.
function _rep() { local out; printf -v out '%*s' "$2" ''; printf '%s' "${out// /$1}"; }

# Echo text centered in exactly $1 columns (truncated when it is too long).
function _center() {
    local w=$1 text=${2:0:$1} pad_l
    pad_l=$(( (w - ${#text}) / 2 )); (( pad_l < 0 )) && pad_l=0
    printf '%*s%s%*s' "$pad_l" '' "$text" "$(( w - ${#text} - pad_l ))" ''
}

# Horizontal rule: left cap, run glyph, junction glyph, right cap, segment widths.
function draw_rule() {
    local left=$1 run=$2 join=$3 right=$4 out first=1 width; shift 4
    (( $# )) || set -- "$TABLE_INNER"
    out="${C_FRAME}${left}${C_RESET}"
    for width in "$@"; do
        (( first )) || out+="${C_FRAME}${join}${C_RESET}"
        out+="${C_FRAME}$(_rep "$run" "$width")${C_RESET}"
        first=0
    done
    printf '%s%s%s%s\n' "$out" "$C_FRAME" "$right" "$C_RESET"
}

# Title row: the title centered between the two outer walls.
function draw_title() {
    local title=$1 pad_l pad_r
    pad_l=$(( (TABLE_INNER - ${#title}) / 2 )); pad_r=$(( TABLE_INNER - ${#title} - pad_l ))
    printf '%s%s%s%*s%s%s%s%*s%s%s%s\n' \
        "$C_FRAME" "$G_V" "$C_RESET" "$pad_l" '' "$C_TITLE" "$title" "$C_RESET" "$pad_r" '' "$C_FRAME" "$G_V" "$C_RESET"
}

# Content row built from (color, text) pairs; text must already fill its column.
function draw_row() {
    local color text first=1
    printf '%s%s%s' "$C_FRAME" "$G_V" "$C_RESET"
    while (( $# >= 2 )); do
        color=$1 text=$2; shift 2
        (( first )) || printf '%s%s%s' "$C_FRAME" "$G_VL" "$C_RESET"
        printf ' %s%s%s ' "$color" "$text" "$C_RESET"
        first=0
    done
    printf '%s%s%s\n' "$C_FRAME" "$G_V" "$C_RESET"
}

# =============================================================================
# --- HELPER FUNCTIONS ---
# =============================================================================

function show_help() {
    echo; echo -e "${C_TITLE}CPU Core Control Power Utility${C_RESET}"
    echo -e "  View and manage the status and power policies of CPU cores."
    echo; echo -e "${C_BOLD}USAGE:${C_RESET}"; echo -e "  $0 [action_flags] [display_flags]"
    
    local -A options
    options["No Flags:"]="Displays the current status of all cores (default)."
    options["--on [<cores>]"]="Enables cores. Defaults to 'all' if no list is given."
    options["--off [<cores>]"]="Disables cores. Defaults to all except core 0."
    options["-g, --governor <name|list>"]="Sets governor or lists available governors."
    options["-b, --bias <name|list>"]="Sets bias or lists available biases."
    options["-c, --cores <cores>"]="Target for -g/-b flags. Defaults to all online cores."
    options["-h, --help"]="Shows this help message."
    
    local max_len=0
    for key in "${!options[@]}"; do if (( ${#key} > max_len )); then max_len=${#key}; fi; done
    echo;
    printf "  ${C_SUCCESS}%-*s${C_RESET}  %s\n" "$max_len" "No Flags:" "${options['No Flags:']}"
    echo; echo -e "${C_BOLD}ACTION FLAGS (can be combined):${C_RESET}"
    printf "  ${C_SUCCESS}%-*s${C_RESET}  %s\n" "$max_len" "--on           [<cores>]  " "${options['--on [<cores>]']}"
    printf "  ${C_SUCCESS}%-*s${C_RESET}  %s\n" "$max_len" "--off          [<cores>]  " "${options['--off [<cores>]']}"
    printf "  ${C_SUCCESS}%-*s${C_RESET}  %s\n" "$max_len" "-g, --governor <name|list>" "${options['-g, --governor <name|list>']}"
    printf "  ${C_SUCCESS}%-*s${C_RESET}  %s\n" "$max_len" "-b, --bias     <name|list>" "${options['-b, --bias <name|list>']}"
    printf "  ${C_SUCCESS}%-*s${C_RESET}  %s\n" "$max_len" "-c, --cores    <cores>    " "${options['-c, --cores <cores>']}"
    printf "  ${C_SUCCESS}%-*s${C_RESET}  %s\n" "$max_len" "-h, --help                " "${options['-h, --help']}"
    
    echo; echo -e "${C_BOLD}DISPLAY FLAGS:${C_RESET}"
    printf "  ${C_SUCCESS}%-*s${C_RESET}  %s\n" "$max_len" "-G, --grid" "Only displays the CPU Core Status grid."
    printf "  ${C_SUCCESS}%-*s${C_RESET}  %s\n" "$max_len" "-T, --table" "Only displays the Detailed Core Status table."
    printf "  ${C_SUCCESS}%-*s${C_RESET}  %s\n" "$max_len" "--unicode" "Uses single-line Unicode box drawing instead of ASCII."

    echo; echo -e "${C_BOLD}CORE SPECIFICATION <cores>:${C_RESET}"; echo -e "  A list in the format: ${C_YELLOW}1-3,7${C_RESET} or ${C_YELLOW}all${C_RESET}"; echo
}

# --- NEW Function to check for root privileges ---
function check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "\n${C_ERROR}Error: This action requires root privileges. Please run with sudo.${C_RESET}\n" >&2
        exit 1
    fi
}

function parse_core_list() {
    local input_str=$1; local expanded_list=""
    if [[ "$input_str" == "all" ]]; then expanded_list=$(ls -d /sys/devices/system/cpu/cpu[0-9]* | sed 's|.*/cpu||' | tr '\n' ' ');
    else for part in ${input_str//,/ }; do if [[ $part == *-* ]]; then local start=${part%-*}; local end=${part#*-}; for ((i=start; i<=end; i++)); do expanded_list="$expanded_list $i"; done; else expanded_list="$expanded_list $part"; fi; done; fi
    local sorted_list; sorted_list=$(echo "${expanded_list# }" | tr ' ' '\n' | sort -n | tr '\n' ' '); echo "${sorted_list% }";
}

function get_enumerated_online_cpus() { parse_core_list "$(cat /sys/devices/system/cpu/online)"; }

function set_core_state() {
    check_root # Security Check
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
    check_root # Security Check
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
    check_root # Security Check
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
    if ! { [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; }; then
        local online_cores_text; online_cores_text=$(get_enumerated_online_cpus)
        echo "Verified online cores:"; echo "${online_cores_text}"; echo ""
        return 0
    fi

    local TITLE="CPU Core Status"
    local -a all_cores; mapfile -t all_cores < <(ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null | sed 's|.*/cpu||' | sort -n)
    local online_cores=" $(get_enumerated_online_cpus) "
    local total=${#all_cores[@]} digits=1 core unit cell

    for core in "${all_cores[@]}"; do (( ${#core} > digits )) && digits=${#core}; done
    unit=$(( 3 + digits ))                       # "■ " + number + trailing space
    local per_line=$(( TABLE_INNER / unit )); (( per_line < 1 )) && per_line=1

    draw_rule "$G_TL" "$G_H" '' "$G_TR"
    draw_title "$TITLE"
    draw_rule "$G_LT" "$G_H" '' "$G_RT"

    local start end i line_width pad_l pad_r
    local -a cells
    for (( start = 0; start < total; start += per_line )); do
        end=$(( start + per_line )); (( end > total )) && end=$total
        cells=()
        for (( i = start; i < end; i++ )); do
            core=${all_cores[i]}
            if [[ $online_cores == *" $core "* ]]; then
                printf -v cell '%s %*s ' "$G_ON" "$digits" "$core"; cells+=("${C_STATUS_ON}${cell}${C_RESET}")
            else
                printf -v cell '%s %*s ' "$G_OFF" "$digits" "$core"; cells+=("${C_STATUS_OFF}${cell}${C_RESET}")
            fi
        done
        line_width=$(( ${#cells[@]} * unit ))
        pad_l=$(( (TABLE_INNER - line_width) / 2 )); (( pad_l < 0 )) && pad_l=0
        pad_r=$(( TABLE_INNER - line_width - pad_l ))
        printf '%s%s%s%*s' "$C_FRAME" "$G_V" "$C_RESET" "$pad_l" ''
        printf '%s' "${cells[@]}"
        printf '%*s%s%s%s\n' "$pad_r" '' "$C_FRAME" "$G_V" "$C_RESET"
    done

    # Legend: what the square colors mean plus an online/total count, centered.
    local key_on=' online' key_off=' offline' legend online_count=0
    for core in "${all_cores[@]}"; do [[ $online_cores == *" $core "* ]] && online_count=$(( online_count + 1 )); done
    local count_text="${online_count}/${total} online"
    local legend_width=$(( 1 + ${#key_on} + 3 + 1 + ${#key_off} + 3 + ${#count_text} ))   # each square is one column
    printf -v legend '%s%s%s%s   %s%s%s%s   %s' "$C_STATUS_ON" "$G_ON" "$C_RESET" "$key_on" "$C_STATUS_OFF" "$G_OFF" "$C_RESET" "$key_off" "$count_text"
    draw_rule "$G_LT" "$G_H" '' "$G_RT"
    pad_l=$(( (TABLE_INNER - legend_width) / 2 )); (( pad_l < 0 )) && pad_l=0
    pad_r=$(( TABLE_INNER - legend_width - pad_l ))
    printf '%s%s%s%*s%s%*s%s%s%s\n' "$C_FRAME" "$G_V" "$C_RESET" "$pad_l" '' "$legend" "$pad_r" '' "$C_FRAME" "$G_V" "$C_RESET"

    draw_rule "$G_BL" "$G_H" '' "$G_BR"
    echo ""
}

function show_status_table() {
    local TITLE="Detailed Core Status"
    local c_node=$(( COL_NODE + 2 )) c_status=$(( COL_STATUS + 2 )) c_gov=$(( COL_GOV + 2 )) c_bias=$(( COL_BIAS + 2 ))
    local -a all_cores; mapfile -t all_cores < <(ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null | sed 's|.*/cpu||' | sort -n)

    draw_rule "$G_TL" "$G_H" '' "$G_TR"
    draw_title "$TITLE"
    draw_rule "$G_LT" "$G_H" "$G_TT" "$G_RT" "$c_node" "$c_status" "$c_gov" "$c_bias"
    draw_row "$C_HEADER" "$(_center "$COL_NODE" "NODE")" \
             "$C_HEADER" "$(_center "$COL_STATUS" "STATUS")" \
             "$C_HEADER" "$(_center "$COL_GOV" "GOVERNOR")" \
             "$C_HEADER" "$(_center "$COL_BIAS" "BIAS")"
    draw_rule "$G_LT" "$G_H" "$G_CT" "$G_RT" "$c_node" "$c_status" "$c_gov" "$c_bias"

    local i ONLINE_STATUS GOV EPP_VAL STATUS_COLOR GOV_COLOR EPP_COLOR ONLINE_FILE GOV_FILE EPP_FILE
    for i in "${all_cores[@]}"; do
        ONLINE_STATUS="OFFLINE"; GOV="<no_signal>"; EPP_VAL="<no_signal>"
        STATUS_COLOR="${C_STATUS_OFF}"; GOV_COLOR="${C_GOV}"; EPP_COLOR="${C_EPP}"
        ONLINE_FILE="/sys/devices/system/cpu/cpu${i}/online"
        if [ "$i" -eq 0 ] || { [ -f "$ONLINE_FILE" ] && [ "$(cat "$ONLINE_FILE")" -eq 1 ]; }; then
            ONLINE_STATUS="ONLINE"; STATUS_COLOR="${C_STATUS_ON}"
            GOV_FILE="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
            EPP_FILE="/sys/devices/system/cpu/cpu${i}/cpufreq/energy_performance_preference"
            if [ -f "$GOV_FILE" ]; then GOV=$(cat "$GOV_FILE"); fi
            if [ -f "$EPP_FILE" ]; then EPP_VAL=$(cat "$EPP_FILE"); fi
        fi
        if [[ "$GOV" == "<no_signal>" ]]; then GOV_COLOR="${C_STATUS_OFF}"; fi
        if [[ "$EPP_VAL" == "<no_signal>" ]]; then EPP_COLOR="${C_STATUS_OFF}"; fi
        draw_row "$C_CORE" "$(_center "$COL_NODE" "Core $i")" \
                 "$STATUS_COLOR" "$(_center "$COL_STATUS" "$ONLINE_STATUS")" \
                 "$GOV_COLOR" "$(_center "$COL_GOV" "$GOV")" \
                 "$EPP_COLOR" "$(_center "$COL_BIAS" "$EPP_VAL")"
    done
    draw_rule "$G_BL" "$G_H" "$G_BT" "$G_BR" "$c_node" "$c_status" "$c_gov" "$c_bias"
    echo ""
}

# =============================================================================
# --- MAIN LOGIC (REFACTORED PARSER) ---
# =============================================================================

echo # Start with a blank line for separation

if [ -z "$1" ]; then show_online_cores; show_status_table; exit 0; fi
ON_CORES_STR=""; OFF_CORES_STR=""; GOVERNOR_TO_SET=""; BIAS_TO_SET=""; CORES_FOR_POLICY_STR=""
ACTION_TAKEN=0; SHOW_GRID_FLAG=0; SHOW_TABLE_FLAG=0; STYLE_ONLY=0

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
        -G|--grid) SHOW_GRID_FLAG=1; shift 1 ;;
        -T|--table) SHOW_TABLE_FLAG=1; shift 1 ;;
        --unicode) set_box_style unicode; STYLE_ONLY=1; shift 1 ;;
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

# Determine what to show
if (( SHOW_GRID_FLAG == 1 || SHOW_TABLE_FLAG == 1 )); then
    if (( SHOW_GRID_FLAG == 1 )); then show_online_cores; fi
    if (( SHOW_TABLE_FLAG == 1 )); then show_status_table; fi
elif [ "$ACTION_TAKEN" -eq 1 ] || [ "$STYLE_ONLY" -eq 1 ]; then
    show_online_cores
    show_status_table
fi
