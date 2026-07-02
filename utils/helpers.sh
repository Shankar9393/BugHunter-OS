#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

if [[ -n "${BUGHUNTER_HELPERS_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
readonly BUGHUNTER_HELPERS_SH_LOADED="true"

BUGHUNTER_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUGHUNTER_ROOT_DIR="$(cd "${BUGHUNTER_HELPERS_DIR}/.." && pwd)"
BUGHUNTER_CONFIG_HELPER_FILE="${BUGHUNTER_HELPERS_DIR}/config.sh"

if [[ -f "${BUGHUNTER_CONFIG_HELPER_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${BUGHUNTER_CONFIG_HELPER_FILE}"
fi

HELPERS_EXIT_OK=0
HELPERS_EXIT_INVALID_INPUT=1
HELPERS_EXIT_NOT_FOUND=2
HELPERS_EXIT_IO_ERROR=3
HELPERS_EXIT_COMMAND_FAILED=4

helper_trim() {
    local value="$*"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "${value}"
}

helper_lower() {
    printf '%s\n' "${*,,}"
}

helper_upper() {
    printf '%s\n' "${*^^}"
}

helper_slugify() {
    local value="$*"

    value="$(helper_lower "${value}")"
    value="$(printf '%s' "${value}" | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
    if [[ -z "${value}" ]]; then
        return "${HELPERS_EXIT_INVALID_INPUT}"
    fi

    printf '%s\n' "${value}"
}

helper_timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

helper_run_id() {
    local format

    format="$(config_get "RUN_ID_FORMAT" "%Y%m%d-%H%M%S")" || return $?
    date "+${format}"
}

helper_abspath() {
    local input_path="$1"
    local base_path="${2:-${BUGHUNTER_ROOT_DIR}}"
    local dir_name
    local file_name

    if [[ -z "${input_path}" ]]; then
        return "${HELPERS_EXIT_INVALID_INPUT}"
    fi

    if [[ "${input_path}" != /* ]]; then
        input_path="${base_path}/${input_path}"
    fi

    dir_name="$(dirname "${input_path}")"
    file_name="$(basename "${input_path}")"

    if [[ ! -d "${dir_name}" ]]; then
        return "${HELPERS_EXIT_NOT_FOUND}"
    fi

    printf '%s/%s\n' "$(cd "${dir_name}" && pwd)" "${file_name}"
}

helper_mkdirp() {
    local dir_path="$1"

    if [[ -z "${dir_path}" ]]; then
        log_error "Directory path is empty"
        return "${HELPERS_EXIT_INVALID_INPUT}"
    fi

    if mkdir -p "${dir_path}"; then
        log_debug "Ensured directory exists: ${dir_path}"
        return "${HELPERS_EXIT_OK}"
    fi

    log_error "Failed to create directory: ${dir_path}"
    return "${HELPERS_EXIT_IO_ERROR}"
}

helper_touch_file() {
    local file_path="$1"
    local dir_path

    if [[ -z "${file_path}" ]]; then
        log_error "File path is empty"
        return "${HELPERS_EXIT_INVALID_INPUT}"
    fi

    dir_path="$(dirname "${file_path}")"
    helper_mkdirp "${dir_path}" || return $?

    if touch "${file_path}"; then
        log_debug "Ensured file exists: ${file_path}"
        return "${HELPERS_EXIT_OK}"
    fi

    log_error "Failed to create file: ${file_path}"
    return "${HELPERS_EXIT_IO_ERROR}"
}

helper_file_exists() {
    local file_path="$1"
    [[ -f "${file_path}" ]]
}

helper_file_readable() {
    local file_path="$1"
    [[ -f "${file_path}" && -r "${file_path}" ]]
}

helper_file_nonempty() {
    local file_path="$1"
    [[ -s "${file_path}" ]]
}

helper_dir_exists() {
    local dir_path="$1"
    [[ -d "${dir_path}" ]]
}

helper_require_file() {
    local file_path="$1"

    if helper_file_readable "${file_path}"; then
        return "${HELPERS_EXIT_OK}"
    fi

    log_error "Required file is missing or unreadable: ${file_path}"
    return "${HELPERS_EXIT_NOT_FOUND}"
}

helper_require_dir() {
    local dir_path="$1"

    if helper_dir_exists "${dir_path}"; then
        return "${HELPERS_EXIT_OK}"
    fi

    log_error "Required directory is missing: ${dir_path}"
    return "${HELPERS_EXIT_NOT_FOUND}"
}

helper_command_exists() {
    local command_name="$1"
    command -v "${command_name}" >/dev/null 2>&1
}

helper_command_path() {
    local command_name="$1"

    if ! helper_command_exists "${command_name}"; then
        return "${HELPERS_EXIT_NOT_FOUND}"
    fi

    command -v "${command_name}"
}

helper_require_command() {
    local command_name="$1"

    if helper_command_exists "${command_name}"; then
        return "${HELPERS_EXIT_OK}"
    fi

    log_error "Required command is not available: ${command_name}"
    return "${HELPERS_EXIT_NOT_FOUND}"
}

helper_command_version() {
    local command_name="$1"
    local command_path
    local version_output=""

    command_path="$(helper_command_path "${command_name}")" || return $?

    if version_output="$("${command_path}" --version 2>&1 | head -n 1)"; then
        printf '%s\n' "${version_output}"
        return "${HELPERS_EXIT_OK}"
    fi

    if version_output="$("${command_path}" version 2>&1 | head -n 1)"; then
        printf '%s\n' "${version_output}"
        return "${HELPERS_EXIT_OK}"
    fi

    printf 'version unavailable\n'
}

helper_join_by() {
    local delimiter="$1"
    shift
    local first="true"
    local item

    for item in "$@"; do
        if [[ "${first}" == "true" ]]; then
            printf '%s' "${item}"
            first="false"
        else
            printf '%s%s' "${delimiter}" "${item}"
        fi
    done
    printf '\n'
}

helper_read_lines() {
    local file_path="$1"
    local line

    helper_require_file "${file_path}" || return $?
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" ]] && continue
        printf '%s\n' "${line}"
    done <"${file_path}"
}

helper_sort_unique_file() {
    local file_path="$1"
    local temp_path

    helper_require_file "${file_path}" || return $?
    temp_path="${file_path}.tmp.$$"

    if sort -u "${file_path}" >"${temp_path}" && mv "${temp_path}" "${file_path}"; then
        log_debug "Sorted and deduplicated file: ${file_path}"
        return "${HELPERS_EXIT_OK}"
    fi

    rm -f "${temp_path}" 2>/dev/null || true
    log_error "Failed to sort and deduplicate file: ${file_path}"
    return "${HELPERS_EXIT_IO_ERROR}"
}

helper_count_lines() {
    local file_path="$1"

    helper_require_file "${file_path}" || return $?
    wc -l <"${file_path}" | tr -d '[:space:]'
}

helper_safe_basename() {
    local value="$1"
    local base_value

    base_value="$(basename "${value}")"
    helper_slugify "${base_value}"
}

helper_with_timeout() {
    local seconds="$1"
    shift

    if [[ ! "${seconds}" =~ ^[0-9]+$ || "${seconds}" == "0" ]]; then
        log_error "Invalid timeout value: ${seconds}"
        return "${HELPERS_EXIT_INVALID_INPUT}"
    fi

    if helper_command_exists timeout; then
        timeout "${seconds}" "$@"
        return $?
    fi

    "$@"
}

helper_run_command() {
    local -a command_args=("$@")
    local exit_code

    if ((${#command_args[@]} == 0)); then
        log_error "No command was provided"
        return "${HELPERS_EXIT_INVALID_INPUT}"
    fi

    log_debug "Running command: ${command_args[*]}"
    if "${command_args[@]}"; then
        return "${HELPERS_EXIT_OK}"
    fi

    exit_code=$?
    log_error "Command failed with exit code ${exit_code}: ${command_args[*]}"
    return "${HELPERS_EXIT_COMMAND_FAILED}"
}

helper_is_truthy() {
    local value="${1:-false}"

    case "${value,,}" in
        true|yes|y|1|on|enabled)
            return "${HELPERS_EXIT_OK}"
            ;;
        *)
            return "${HELPERS_EXIT_INVALID_INPUT}"
            ;;
    esac
}

helper_is_falsey() {
    local value="${1:-false}"

    case "${value,,}" in
        false|no|n|0|off|disabled|"")
            return "${HELPERS_EXIT_OK}"
            ;;
        *)
            return "${HELPERS_EXIT_INVALID_INPUT}"
            ;;
    esac
}

helper_assert_workspace_path() {
    local input_path="$1"
    local absolute_path

    absolute_path="$(helper_abspath "${input_path}" "${BUGHUNTER_ROOT_DIR}")" || return $?
    case "${absolute_path}" in
        "${BUGHUNTER_ROOT_DIR}"|"${BUGHUNTER_ROOT_DIR}"/*)
            printf '%s\n' "${absolute_path}"
            return "${HELPERS_EXIT_OK}"
            ;;
        *)
            log_error "Path is outside the workspace: ${absolute_path}"
            return "${HELPERS_EXIT_INVALID_INPUT}"
            ;;
    esac
}
