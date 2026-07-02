#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

if [[ -n "${BUGHUNTER_CONFIG_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
readonly BUGHUNTER_CONFIG_SH_LOADED="true"

BUGHUNTER_CONFIG_UTIL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUGHUNTER_ROOT_DIR="$(cd "${BUGHUNTER_CONFIG_UTIL_DIR}/.." && pwd)"
BUGHUNTER_CONFIG_FILE="${BUGHUNTER_ROOT_DIR}/config/config.conf"
BUGHUNTER_LOGGER_FILE="${BUGHUNTER_CONFIG_UTIL_DIR}/logger.sh"

if [[ -f "${BUGHUNTER_LOGGER_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${BUGHUNTER_LOGGER_FILE}"
fi

CONFIG_EXIT_OK=0
CONFIG_EXIT_MISSING_FILE=1
CONFIG_EXIT_INVALID_KEY=2
CONFIG_EXIT_MISSING_KEY=3
CONFIG_EXIT_INVALID_VALUE=4

CONFIG_LOADED="false"
CONFIG_SOURCE_FILE=""
CONFIG_LOCAL_SOURCE_FILE=""

config_key_is_valid() {
    local key="$1"
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

config_file_is_readable() {
    local file_path="$1"
    [[ -f "${file_path}" && -r "${file_path}" ]]
}

config_load() {
    local config_file="${1:-${BUGHUNTER_CONFIG_FILE}}"
    local local_config="${2:-${BUGHUNTER_LOCAL_CONFIG:-}}"

    if ! config_file_is_readable "${config_file}"; then
        log_error "Configuration file is missing or unreadable: ${config_file}"
        return "${CONFIG_EXIT_MISSING_FILE}"
    fi

    # shellcheck source=/dev/null
    source "${config_file}"
    CONFIG_SOURCE_FILE="${config_file}"

    if [[ -n "${local_config}" ]]; then
        if ! config_file_is_readable "${local_config}"; then
            log_error "Local configuration override is missing or unreadable: ${local_config}"
            return "${CONFIG_EXIT_MISSING_FILE}"
        fi

        # shellcheck source=/dev/null
        source "${local_config}"
        CONFIG_LOCAL_SOURCE_FILE="${local_config}"
    fi

    if [[ -z "${PROJECT_ROOT:-}" ]]; then
        PROJECT_ROOT="${BUGHUNTER_ROOT_DIR}"
    elif [[ "${PROJECT_ROOT}" != /* ]]; then
        PROJECT_ROOT="${BUGHUNTER_ROOT_DIR}/${PROJECT_ROOT}"
    fi

    CONFIG_LOADED="true"
    log_debug "Loaded configuration from ${CONFIG_SOURCE_FILE}"
    if [[ -n "${CONFIG_LOCAL_SOURCE_FILE}" ]]; then
        log_debug "Loaded local configuration from ${CONFIG_LOCAL_SOURCE_FILE}"
    fi

    return "${CONFIG_EXIT_OK}"
}

config_reload() {
    CONFIG_LOADED="false"
    CONFIG_SOURCE_FILE=""
    CONFIG_LOCAL_SOURCE_FILE=""
    config_load "$@"
}

config_ensure_loaded() {
    if [[ "${CONFIG_LOADED}" == "true" ]]; then
        return "${CONFIG_EXIT_OK}"
    fi

    config_load
}

config_has() {
    local key="$1"

    if ! config_key_is_valid "${key}"; then
        return "${CONFIG_EXIT_INVALID_KEY}"
    fi

    config_ensure_loaded || return $?
    [[ -v "${key}" ]]
}

config_get() {
    local key="$1"
    local default_value="${2:-}"

    if ! config_key_is_valid "${key}"; then
        log_error "Invalid configuration key: ${key}"
        return "${CONFIG_EXIT_INVALID_KEY}"
    fi

    config_ensure_loaded || return $?

    if [[ -v "${key}" ]]; then
        printf '%s\n' "${!key}"
        return "${CONFIG_EXIT_OK}"
    fi

    if (($# >= 2)); then
        printf '%s\n' "${default_value}"
        return "${CONFIG_EXIT_OK}"
    fi

    log_error "Required configuration key is not set: ${key}"
    return "${CONFIG_EXIT_MISSING_KEY}"
}

config_set() {
    local key="$1"
    local value="$2"

    if ! config_key_is_valid "${key}"; then
        log_error "Invalid configuration key: ${key}"
        return "${CONFIG_EXIT_INVALID_KEY}"
    fi

    printf -v "${key}" '%s' "${value}"
    export "${key}"
    return "${CONFIG_EXIT_OK}"
}

config_require() {
    local key
    local missing=0

    config_ensure_loaded || return $?

    for key in "$@"; do
        if ! config_key_is_valid "${key}"; then
            log_error "Invalid configuration key: ${key}"
            return "${CONFIG_EXIT_INVALID_KEY}"
        fi

        if [[ ! -v "${key}" || -z "${!key}" ]]; then
            log_error "Required configuration key is empty or unset: ${key}"
            missing=1
        fi
    done

    if ((missing > 0)); then
        return "${CONFIG_EXIT_MISSING_KEY}"
    fi

    return "${CONFIG_EXIT_OK}"
}

config_bool() {
    local key="$1"
    local raw_value

    raw_value="$(config_get "${key}" "${2:-false}")" || return $?
    case "${raw_value,,}" in
        true|yes|y|1|on|enabled)
            printf 'true\n'
            ;;
        false|no|n|0|off|disabled)
            printf 'false\n'
            ;;
        *)
            log_error "Configuration key ${key} is not a boolean: ${raw_value}"
            return "${CONFIG_EXIT_INVALID_VALUE}"
            ;;
    esac
}

config_int() {
    local key="$1"
    local raw_value
    local minimum="${3:-}"
    local maximum="${4:-}"

    raw_value="$(config_get "${key}" "${2:-0}")" || return $?
    if [[ ! "${raw_value}" =~ ^[0-9]+$ ]]; then
        log_error "Configuration key ${key} is not an integer: ${raw_value}"
        return "${CONFIG_EXIT_INVALID_VALUE}"
    fi

    if [[ -n "${minimum}" && "${raw_value}" -lt "${minimum}" ]]; then
        log_error "Configuration key ${key} is below minimum ${minimum}: ${raw_value}"
        return "${CONFIG_EXIT_INVALID_VALUE}"
    fi

    if [[ -n "${maximum}" && "${raw_value}" -gt "${maximum}" ]]; then
        log_error "Configuration key ${key} is above maximum ${maximum}: ${raw_value}"
        return "${CONFIG_EXIT_INVALID_VALUE}"
    fi

    printf '%s\n' "${raw_value}"
}

config_path() {
    local key="$1"
    local raw_path
    local root_path

    raw_path="$(config_get "${key}" "${2:-}")" || return $?
    if [[ -z "${raw_path}" ]]; then
        log_error "Configuration path ${key} is empty"
        return "${CONFIG_EXIT_INVALID_VALUE}"
    fi

    if [[ "${raw_path}" = /* ]]; then
        printf '%s\n' "${raw_path}"
        return "${CONFIG_EXIT_OK}"
    fi

    root_path="$(config_get "PROJECT_ROOT" "${BUGHUNTER_ROOT_DIR}")" || return $?
    printf '%s/%s\n' "${root_path}" "${raw_path}"
}

config_csv_contains() {
    local key="$1"
    local needle="$2"
    local csv_value
    local item
    local old_ifs="${IFS}"

    csv_value="$(config_get "${key}" "")" || return $?
    IFS=','
    for item in ${csv_value}; do
        IFS="${old_ifs}"
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        if [[ "${item}" == "${needle}" ]]; then
            return "${CONFIG_EXIT_OK}"
        fi
        IFS=','
    done
    IFS="${old_ifs}"

    return "${CONFIG_EXIT_MISSING_KEY}"
}

config_print_csv_lines() {
    local key="$1"
    local csv_value
    local item
    local old_ifs="${IFS}"

    csv_value="$(config_get "${key}" "")" || return $?
    IFS=','
    for item in ${csv_value}; do
        IFS="${old_ifs}"
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        if [[ -n "${item}" ]]; then
            printf '%s\n' "${item}"
        fi
        IFS=','
    done
    IFS="${old_ifs}"
}

config_profile_modules_key() {
    local profile="$1"

    case "${profile}" in
        safe) printf 'SAFE_MODULES\n' ;;
        balanced) printf 'BALANCED_MODULES\n' ;;
        deep) printf 'DEEP_MODULES\n' ;;
        *)
            log_error "Unknown scan profile: ${profile}"
            return "${CONFIG_EXIT_INVALID_VALUE}"
            ;;
    esac
}

config_profile_modules() {
    local profile="${1:-}"
    local modules_key

    if [[ -z "${profile}" ]]; then
        profile="$(config_get "DEFAULT_PROFILE" "safe")" || return $?
    fi

    modules_key="$(config_profile_modules_key "${profile}")" || return $?
    config_get "${modules_key}"
}

config_init() {
    config_load "$@"
}

config_load
