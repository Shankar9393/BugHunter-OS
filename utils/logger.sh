#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

if [[ -n "${BUGHUNTER_LOGGER_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
readonly BUGHUNTER_LOGGER_SH_LOADED="true"

BUGHUNTER_LOGGER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUGHUNTER_ROOT_DIR="$(cd "${BUGHUNTER_LOGGER_DIR}/.." && pwd)"
BUGHUNTER_CONFIG_FILE="${BUGHUNTER_ROOT_DIR}/config/config.conf"
BUGHUNTER_COLORS_FILE="${BUGHUNTER_LOGGER_DIR}/colors.sh"

if [[ -f "${BUGHUNTER_CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${BUGHUNTER_CONFIG_FILE}"
fi

if [[ -n "${BUGHUNTER_LOCAL_CONFIG:-}" && -f "${BUGHUNTER_LOCAL_CONFIG}" ]]; then
    # shellcheck source=/dev/null
    source "${BUGHUNTER_LOCAL_CONFIG}"
fi

if [[ -f "${BUGHUNTER_COLORS_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${BUGHUNTER_COLORS_FILE}"
fi

LOGGER_EXIT_OK=0
LOGGER_EXIT_WRITE_FAILED=1
LOGGER_EXIT_CONFIG_ERROR=2
LOGGER_EXIT_LOCK_FAILED=3

LOGGER_CONSOLE_ENABLED="${LOGGER_CONSOLE_ENABLED:-true}"
LOGGER_FILE_ENABLED="${LOGGER_FILE_ENABLED:-true}"
LOGGER_VERBOSE="${LOGGER_VERBOSE:-false}"
LOGGER_DEBUG="${LOGGER_DEBUG:-false}"
LOGGER_SILENT="${LOGGER_SILENT:-false}"
LOGGER_MAX_SIZE_BYTES="${LOGGER_MAX_SIZE_BYTES:-10485760}"
LOGGER_LOCK_WAIT_SECONDS="${LOGGER_LOCK_WAIT_SECONDS:-30}"
LOGGER_NAME="${LOGGER_NAME:-${BUGHUNTER_NAME:-BugHunter-OS}}"
LOGGER_LOG_DIR="${LOGGER_LOG_DIR:-${LOGS_DIR:-logs}}"
LOGGER_LOG_FILE="${LOGGER_LOG_FILE:-}"
LOGGER_INITIALIZED="false"

_logger_timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

_logger_date() {
    date '+%Y-%m-%d'
}

_logger_resolve_path() {
    local input_path="$1"

    if [[ "${input_path}" = /* ]]; then
        printf '%s\n' "${input_path}"
        return "${LOGGER_EXIT_OK}"
    fi

    printf '%s/%s\n' "${BUGHUNTER_ROOT_DIR}" "${input_path}"
}

_logger_current_file() {
    if [[ -n "${LOGGER_LOG_FILE}" ]]; then
        _logger_resolve_path "${LOGGER_LOG_FILE}"
        return "${LOGGER_EXIT_OK}"
    fi

    printf '%s/%s-%s.log\n' "$(_logger_resolve_path "${LOGGER_LOG_DIR}")" "bughunter" "$(_logger_date)"
}

_logger_lock_file() {
    printf '%s.lock\n' "$(_logger_current_file)"
}

_logger_level_rank() {
    case "${1^^}" in
        DEBUG) printf '10' ;;
        INFO) printf '20' ;;
        SUCCESS) printf '25' ;;
        WARN) printf '30' ;;
        ERROR) printf '40' ;;
        *) printf '20' ;;
    esac
}

_logger_should_emit_level() {
    local level="$1"
    local configured_level="${LOG_LEVEL:-info}"
    local configured_rank
    local message_rank

    if [[ "${LOGGER_DEBUG}" == "true" ]]; then
        configured_level="debug"
    fi

    if [[ "${LOGGER_VERBOSE}" == "true" && "${configured_level}" != "debug" ]]; then
        configured_level="info"
    fi

    configured_rank="$(_logger_level_rank "${configured_level}")"
    message_rank="$(_logger_level_rank "${level}")"
    ((message_rank >= configured_rank))
}

_logger_console_color() {
    case "${1^^}" in
        DEBUG) printf '%s' "${COLOR_DEBUG:-}" ;;
        INFO) printf '%s' "${COLOR_INFO:-}" ;;
        SUCCESS) printf '%s' "${COLOR_SUCCESS:-}" ;;
        WARN) printf '%s' "${COLOR_WARN:-}" ;;
        ERROR) printf '%s' "${COLOR_ERROR:-}" ;;
        *) printf '%s' "${COLOR_INFO:-}" ;;
    esac
}

_logger_console_write() {
    local level="$1"
    local message="$2"
    local color

    if [[ "${LOGGER_CONSOLE_ENABLED}" != "true" || "${LOGGER_SILENT}" == "true" ]]; then
        return "${LOGGER_EXIT_OK}"
    fi

    color="$(_logger_console_color "${level}")"
    if [[ "${level}" == "ERROR" ]]; then
        printf '%s[%s]%s %s\n' "${color}" "${level}" "${COLOR_RESET:-}" "${message}" >&2
        return "${LOGGER_EXIT_OK}"
    fi

    printf '%s[%s]%s %s\n' "${color}" "${level}" "${COLOR_RESET:-}" "${message}"
}

_logger_file_size() {
    local file_path="$1"

    if [[ ! -f "${file_path}" ]]; then
        printf '0'
        return "${LOGGER_EXIT_OK}"
    fi

    stat -c '%s' "${file_path}" 2>/dev/null || printf '0'
}

_logger_rotate_if_needed() {
    local file_path="$1"
    local max_size="${LOGGER_MAX_SIZE_BYTES}"
    local current_size
    local rotated_path

    if [[ ! "${max_size}" =~ ^[0-9]+$ || "${max_size}" == "0" ]]; then
        return "${LOGGER_EXIT_OK}"
    fi

    current_size="$(_logger_file_size "${file_path}")"
    if ((current_size < max_size)); then
        return "${LOGGER_EXIT_OK}"
    fi

    rotated_path="${file_path}.$(date '+%Y%m%d-%H%M%S').$$"
    mv "${file_path}" "${rotated_path}"
}

_logger_write_file_locked() {
    local file_path="$1"
    local line="$2"
    local lock_file="$3"
    local lock_dir="${lock_file}.d"
    local waited=0

    if command -v flock >/dev/null 2>&1; then
        {
            flock -x -w "${LOGGER_LOCK_WAIT_SECONDS}" 200 || return "${LOGGER_EXIT_LOCK_FAILED}"
            _logger_rotate_if_needed "${file_path}" || return "${LOGGER_EXIT_WRITE_FAILED}"
            printf '%s\n' "${line}" >>"${file_path}" || return "${LOGGER_EXIT_WRITE_FAILED}"
        } 200>"${lock_file}"
        return "${LOGGER_EXIT_OK}"
    fi

    while ! mkdir "${lock_dir}" 2>/dev/null; do
        if ((waited >= LOGGER_LOCK_WAIT_SECONDS)); then
            return "${LOGGER_EXIT_LOCK_FAILED}"
        fi
        sleep 1
        waited=$((waited + 1))
    done

    _logger_rotate_if_needed "${file_path}" || {
        rmdir "${lock_dir}" 2>/dev/null || true
        return "${LOGGER_EXIT_WRITE_FAILED}"
    }

    printf '%s\n' "${line}" >>"${file_path}" || {
        rmdir "${lock_dir}" 2>/dev/null || true
        return "${LOGGER_EXIT_WRITE_FAILED}"
    }

    rmdir "${lock_dir}" 2>/dev/null || true
    return "${LOGGER_EXIT_OK}"
}

logger_init() {
    local file_path
    local log_dir

    file_path="$(_logger_current_file)"
    log_dir="$(dirname "${file_path}")"

    mkdir -p "${log_dir}" || return "${LOGGER_EXIT_CONFIG_ERROR}"
    touch "${file_path}" || return "${LOGGER_EXIT_WRITE_FAILED}"
    LOGGER_INITIALIZED="true"
    return "${LOGGER_EXIT_OK}"
}

logger_set_mode() {
    local mode="$1"

    case "${mode}" in
        verbose)
            LOGGER_VERBOSE="true"
            LOGGER_SILENT="false"
            ;;
        debug)
            LOGGER_DEBUG="true"
            LOGGER_VERBOSE="true"
            LOGGER_SILENT="false"
            ;;
        silent)
            LOGGER_SILENT="true"
            ;;
        normal)
            LOGGER_VERBOSE="false"
            LOGGER_DEBUG="false"
            LOGGER_SILENT="false"
            ;;
        *)
            return "${LOGGER_EXIT_CONFIG_ERROR}"
            ;;
    esac

    return "${LOGGER_EXIT_OK}"
}

log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    local file_path
    local lock_file
    local line

    level="${level^^}"
    if ! _logger_should_emit_level "${level}"; then
        return "${LOGGER_EXIT_OK}"
    fi

    if [[ "${LOGGER_INITIALIZED}" != "true" ]]; then
        logger_init || return $?
    fi

    timestamp="$(_logger_timestamp)"
    line="${timestamp} [${level}] [${LOGGER_NAME}] ${message}"

    _logger_console_write "${level}" "${message}" || return $?

    if [[ "${LOGGER_FILE_ENABLED}" != "true" ]]; then
        return "${LOGGER_EXIT_OK}"
    fi

    file_path="$(_logger_current_file)"
    lock_file="$(_logger_lock_file)"
    _logger_write_file_locked "${file_path}" "${line}" "${lock_file}"
}

log_info() {
    log_message "INFO" "$@"
}

log_success() {
    log_message "SUCCESS" "$@"
}

log_warn() {
    log_message "WARN" "$@"
}

log_error() {
    log_message "ERROR" "$@"
}

log_debug() {
    log_message "DEBUG" "$@"
}

info() {
    log_info "$@"
}

success() {
    log_success "$@"
}

warn() {
    log_warn "$@"
}

error() {
    log_error "$@"
}

debug() {
    log_debug "$@"
}

logger_init
