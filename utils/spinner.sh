#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

if [[ -n "${BUGHUNTER_SPINNER_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
readonly BUGHUNTER_SPINNER_SH_LOADED="true"

BUGHUNTER_SPINNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUGHUNTER_HELPERS_FILE="${BUGHUNTER_SPINNER_DIR}/helpers.sh"

if [[ -f "${BUGHUNTER_HELPERS_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${BUGHUNTER_HELPERS_FILE}"
fi

SPINNER_EXIT_OK=0
SPINNER_EXIT_INVALID_INPUT=1
SPINNER_EXIT_NOT_RUNNING=2

SPINNER_ENABLED="${SPINNER_ENABLED:-true}"
SPINNER_INTERVAL="${SPINNER_INTERVAL:-0.1}"
SPINNER_MESSAGE=""
SPINNER_PID=""
SPINNER_LAST_MESSAGE=""
SPINNER_FRAME_INDEX=0
SPINNER_FRAMES='| / - \'

spinner_validate_message() {
    local message="${1:-}"

    if [[ -n "${message}" ]]; then
        return "${SPINNER_EXIT_OK}"
    fi

    log_error "Spinner message cannot be empty"
    return "${SPINNER_EXIT_INVALID_INPUT}"
}

spinner_validate_interval() {
    local interval="${1:-}"

    if [[ "${interval}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        return "${SPINNER_EXIT_OK}"
    fi

    log_error "Spinner interval must be numeric: ${interval}"
    return "${SPINNER_EXIT_INVALID_INPUT}"
}

spinner_is_terminal() {
    [[ -t 1 ]]
}

spinner_is_enabled() {
    if [[ "${SPINNER_ENABLED}" != "true" || "${LOGGER_SILENT:-false}" == "true" ]]; then
        return 1
    fi

    spinner_is_terminal
}

spinner_frame() {
    local index="$1"
    local frame

    case "${index}" in
        0) frame='|' ;;
        1) frame='/' ;;
        2) frame='-' ;;
        *) frame='\' ;;
    esac

    printf '%s\n' "${frame}"
}

spinner_render_once() {
    local message="${1:-${SPINNER_MESSAGE}}"
    local frame
    local color

    frame="$(spinner_frame "${SPINNER_FRAME_INDEX}")"
    color="${COLOR_INFO:-}"

    if spinner_is_enabled; then
        printf '\r\033[K%s%s%s %s' "${color}" "${frame}" "${COLOR_RESET:-}" "${message}"
        return "${SPINNER_EXIT_OK}"
    fi

    log_info "${message}"
    return "${SPINNER_EXIT_OK}"
}

spinner_loop() {
    local message="$1"
    local interval="$2"
    local frame_count=4

    while :; do
        spinner_render_once "${message}" || return $?
        SPINNER_FRAME_INDEX=$(((SPINNER_FRAME_INDEX + 1) % frame_count))
        sleep "${interval}"
    done
}

spinner_start() {
    local message="$1"
    local interval="${2:-${SPINNER_INTERVAL}}"
    local spinner_output

    spinner_validate_message "${message}" || return $?
    spinner_validate_interval "${interval}" || return $?

    if [[ -n "${SPINNER_PID}" ]]; then
        spinner_stop "${SPINNER_LAST_MESSAGE:-${SPINNER_MESSAGE}}" >/dev/null 2>&1 || true
    fi

    SPINNER_MESSAGE="${message}"
    SPINNER_LAST_MESSAGE="${message}"
    SPINNER_FRAME_INDEX=0

    if ! spinner_is_enabled; then
        log_info "${message}"
        return "${SPINNER_EXIT_OK}"
    fi

    spinner_loop "${message}" "${interval}" >/dev/null 2>&1 &
    SPINNER_PID="$!"
    disown "${SPINNER_PID}" 2>/dev/null || true
    spinner_output="${SPINNER_PID}"
    log_debug "Spinner started pid=${spinner_output} message=${message}"
    return "${SPINNER_EXIT_OK}"
}

spinner_update() {
    local message="$1"

    spinner_validate_message "${message}" || return $?
    SPINNER_MESSAGE="${message}"
    SPINNER_LAST_MESSAGE="${message}"

    if [[ -z "${SPINNER_PID}" ]]; then
        spinner_render_once "${message}"
        return $?
    fi

    log_debug "Spinner updated pid=${SPINNER_PID} message=${message}"
    return "${SPINNER_EXIT_OK}"
}

spinner_stop() {
    local message="${1:-${SPINNER_MESSAGE}}"
    local pid="${SPINNER_PID}"

    if [[ -z "${pid}" ]]; then
        if [[ -n "${message}" ]]; then
            log_info "${message}"
        fi
        return "${SPINNER_EXIT_NOT_RUNNING}"
    fi

    if kill "${pid}" >/dev/null 2>&1; then
        wait "${pid}" 2>/dev/null || true
    fi

    SPINNER_PID=""
    SPINNER_MESSAGE=""
    SPINNER_FRAME_INDEX=0

    if spinner_is_enabled; then
        printf '\r\033[K%s\n' "${message}"
    else
        log_info "${message}"
    fi

    log_debug "Spinner stopped message=${message}"
    return "${SPINNER_EXIT_OK}"
}

spinner_success() {
    local message="$1"
    spinner_stop "${message}" || return $?
    log_success "${message}"
}

spinner_warn() {
    local message="$1"
    spinner_stop "${message}" || return $?
    log_warn "${message}"
}

spinner_error() {
    local message="$1"
    spinner_stop "${message}" || return $?
    log_error "${message}"
}

spinner_reset() {
    if [[ -n "${SPINNER_PID}" ]]; then
        spinner_stop "${SPINNER_MESSAGE}" >/dev/null 2>&1 || true
    fi

    SPINNER_MESSAGE=""
    SPINNER_PID=""
    SPINNER_LAST_MESSAGE=""
    SPINNER_FRAME_INDEX=0
    return "${SPINNER_EXIT_OK}"
}
