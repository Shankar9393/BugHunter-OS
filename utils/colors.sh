#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

if [[ -n "${BUGHUNTER_COLORS_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
readonly BUGHUNTER_COLORS_SH_LOADED="true"

BUGHUNTER_COLORS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUGHUNTER_ROOT_DIR="$(cd "${BUGHUNTER_COLORS_DIR}/.." && pwd)"
BUGHUNTER_CONFIG_FILE="${BUGHUNTER_ROOT_DIR}/config/config.conf"

if [[ -f "${BUGHUNTER_CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${BUGHUNTER_CONFIG_FILE}"
fi

if [[ -n "${BUGHUNTER_LOCAL_CONFIG:-}" && -f "${BUGHUNTER_LOCAL_CONFIG}" ]]; then
    # shellcheck source=/dev/null
    source "${BUGHUNTER_LOCAL_CONFIG}"
fi

COLOR_RESET=""
COLOR_BOLD=""
COLOR_DIM=""
COLOR_INFO=""
COLOR_WARN=""
COLOR_ERROR=""
COLOR_SUCCESS=""
COLOR_DEBUG=""
COLOR_BANNER=""
COLOR_SECTION=""

_bughunter_colors_enabled="false"

_colors_support_256() {
    [[ "${TERM:-}" == *"256color"* || "${COLORTERM:-}" == "truecolor" || "${COLORTERM:-}" == "24bit" ]]
}

_colors_should_enable() {
    if [[ -n "${NO_COLOR:-}" ]]; then
        return 1
    fi

    if [[ "${ENABLE_COLOR:-true}" != "true" ]]; then
        return 1
    fi

    if [[ ! -t 1 ]]; then
        return 1
    fi

    case "${TERM:-}" in
        ""|dumb)
            return 1
            ;;
    esac

    return 0
}

reset_colors() {
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_DIM=""
    COLOR_INFO=""
    COLOR_WARN=""
    COLOR_ERROR=""
    COLOR_SUCCESS=""
    COLOR_DEBUG=""
    COLOR_BANNER=""
    COLOR_SECTION=""
    _bughunter_colors_enabled="false"
}

init_colors() {
    reset_colors

    if ! _colors_should_enable; then
        return 0
    fi

    COLOR_RESET=$'\033[0m'
    COLOR_BOLD=$'\033[1m'
    COLOR_DIM=$'\033[2m'

    if _colors_support_256; then
        COLOR_INFO=$'\033[38;5;39m'
        COLOR_WARN=$'\033[38;5;214m'
        COLOR_ERROR=$'\033[38;5;196m'
        COLOR_SUCCESS=$'\033[38;5;40m'
        COLOR_DEBUG=$'\033[38;5;245m'
        COLOR_BANNER=$'\033[38;5;45m'
        COLOR_SECTION=$'\033[38;5;81m'
    else
        COLOR_INFO=$'\033[34m'
        COLOR_WARN=$'\033[33m'
        COLOR_ERROR=$'\033[31m'
        COLOR_SUCCESS=$'\033[32m'
        COLOR_DEBUG=$'\033[2m'
        COLOR_BANNER=$'\033[36m'
        COLOR_SECTION=$'\033[36m'
    fi

    _bughunter_colors_enabled="true"
}

_color_timestamp() {
    if [[ "${ENABLE_TIMESTAMPS:-true}" == "true" ]]; then
        date '+%Y-%m-%dT%H:%M:%S%z'
    fi
}

_log_level_rank() {
    case "$1" in
        debug) printf '10' ;;
        info) printf '20' ;;
        warn) printf '30' ;;
        error) printf '40' ;;
        *) printf '20' ;;
    esac
}

_should_print_debug() {
    local configured_rank
    local debug_rank

    configured_rank="$(_log_level_rank "${LOG_LEVEL:-info}")"
    debug_rank="$(_log_level_rank "debug")"
    ((configured_rank <= debug_rank))
}

_print_status() {
    local label="$1"
    local color="$2"
    shift 2
    local message="$*"
    local ts=""

    ts="$(_color_timestamp)"
    if [[ -n "${ts}" ]]; then
        printf '%s %s[%s]%s %s\n' "${ts}" "${color}" "${label}" "${COLOR_RESET}" "${message}"
        return 0
    fi

    printf '%s[%s]%s %s\n' "${color}" "${label}" "${COLOR_RESET}" "${message}"
}

info() {
    _print_status "INFO" "${COLOR_INFO}" "$@"
}

warn() {
    _print_status "WARN" "${COLOR_WARN}" "$@"
}

error() {
    _print_status "ERROR" "${COLOR_ERROR}" "$@" >&2
}

success() {
    _print_status "OK" "${COLOR_SUCCESS}" "$@"
}

debug() {
    if _should_print_debug; then
        _print_status "DEBUG" "${COLOR_DEBUG}" "$@"
    fi
}

banner() {
    local title="$*"
    local border

    border="$(printf '%*s' "${#title}" '' | tr ' ' '=')"
    printf '%s%s%s\n' "${COLOR_BANNER}${COLOR_BOLD}" "${border}" "${COLOR_RESET}"
    printf '%s%s%s\n' "${COLOR_BANNER}${COLOR_BOLD}" "${title}" "${COLOR_RESET}"
    printf '%s%s%s\n' "${COLOR_BANNER}${COLOR_BOLD}" "${border}" "${COLOR_RESET}"
}

section() {
    local title="$*"
    printf '%s%s%s\n' "${COLOR_SECTION}${COLOR_BOLD}" "${title}" "${COLOR_RESET}"
}

init_colors
