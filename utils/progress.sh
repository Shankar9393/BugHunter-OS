#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

if [[ -n "${BUGHUNTER_PROGRESS_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
readonly BUGHUNTER_PROGRESS_SH_LOADED="true"

BUGHUNTER_PROGRESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUGHUNTER_HELPERS_FILE="${BUGHUNTER_PROGRESS_DIR}/helpers.sh"

if [[ -f "${BUGHUNTER_HELPERS_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${BUGHUNTER_HELPERS_FILE}"
fi

PROGRESS_EXIT_OK=0
PROGRESS_EXIT_INVALID_INPUT=1
PROGRESS_EXIT_NOT_STARTED=2

PROGRESS_TOTAL=0
PROGRESS_CURRENT=0
PROGRESS_LABEL=""
PROGRESS_STARTED_AT=0
PROGRESS_LAST_RENDER=""
PROGRESS_BAR_WIDTH="${PROGRESS_BAR_WIDTH:-30}"
PROGRESS_RENDER_MODE="${PROGRESS_RENDER_MODE:-auto}"
PROGRESS_ENABLED="${PROGRESS_ENABLED:-true}"

progress_terminal_enabled() {
    if [[ "${PROGRESS_ENABLED}" != "true" || "${LOGGER_SILENT:-false}" == "true" ]]; then
        return 1
    fi

    case "${PROGRESS_RENDER_MODE}" in
        always)
            return 0
            ;;
        never)
            return 1
            ;;
        auto)
            [[ -t 1 ]]
            ;;
        *)
            [[ -t 1 ]]
            ;;
    esac
}

progress_validate_count() {
    local value="$1"

    if [[ "${value}" =~ ^[0-9]+$ ]]; then
        return "${PROGRESS_EXIT_OK}"
    fi

    log_error "Progress value must be a non-negative integer: ${value}"
    return "${PROGRESS_EXIT_INVALID_INPUT}"
}

progress_percent() {
    local current="$1"
    local total="$2"

    progress_validate_count "${current}" || return $?
    progress_validate_count "${total}" || return $?

    if ((total == 0)); then
        printf '0\n'
        return "${PROGRESS_EXIT_OK}"
    fi

    if ((current > total)); then
        current="${total}"
    fi

    printf '%s\n' "$(((current * 100) / total))"
}

progress_elapsed_seconds() {
    local now

    if ((PROGRESS_STARTED_AT == 0)); then
        printf '0\n'
        return "${PROGRESS_EXIT_OK}"
    fi

    now="$(date '+%s')"
    printf '%s\n' "$((now - PROGRESS_STARTED_AT))"
}

progress_format_duration() {
    local seconds="$1"
    local hours
    local minutes

    progress_validate_count "${seconds}" || return $?

    hours="$((seconds / 3600))"
    minutes="$(((seconds % 3600) / 60))"
    seconds="$((seconds % 60))"

    if ((hours > 0)); then
        printf '%02d:%02d:%02d\n' "${hours}" "${minutes}" "${seconds}"
        return "${PROGRESS_EXIT_OK}"
    fi

    printf '%02d:%02d\n' "${minutes}" "${seconds}"
}

progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-${PROGRESS_BAR_WIDTH}}"
    local percent
    local filled
    local empty
    local bar=""

    progress_validate_count "${width}" || return $?
    if ((width == 0)); then
        log_error "Progress bar width must be greater than zero"
        return "${PROGRESS_EXIT_INVALID_INPUT}"
    fi

    percent="$(progress_percent "${current}" "${total}")" || return $?
    filled="$(((percent * width) / 100))"
    empty="$((width - filled))"

    if ((filled > 0)); then
        bar="$(printf '%*s' "${filled}" '' | tr ' ' '#')"
    fi

    if ((empty > 0)); then
        bar="${bar}$(printf '%*s' "${empty}" '' | tr ' ' '-')"
    fi

    printf '[%s] %3d%%\n' "${bar}" "${percent}"
}

progress_line() {
    local current="$1"
    local total="$2"
    local label="${3:-${PROGRESS_LABEL}}"
    local percent
    local bar
    local elapsed
    local elapsed_text

    percent="$(progress_percent "${current}" "${total}")" || return $?
    bar="$(progress_bar "${current}" "${total}" "${PROGRESS_BAR_WIDTH}")" || return $?
    elapsed="$(progress_elapsed_seconds)" || return $?
    elapsed_text="$(progress_format_duration "${elapsed}")" || return $?

    if [[ -n "${label}" ]]; then
        printf '%s %s (%s/%s, elapsed %s)\n' "${label}" "${bar}" "${current}" "${total}" "${elapsed_text}"
    else
        printf '%s (%s/%s, elapsed %s)\n' "${bar}" "${current}" "${total}" "${elapsed_text}"
    fi

    log_debug "Progress ${label}: ${current}/${total} ${percent}% elapsed=${elapsed_text}"
}

progress_start() {
    local total="$1"
    local label="${2:-}"

    progress_validate_count "${total}" || return $?

    PROGRESS_TOTAL="${total}"
    PROGRESS_CURRENT=0
    PROGRESS_LABEL="${label}"
    PROGRESS_STARTED_AT="$(date '+%s')"
    PROGRESS_LAST_RENDER=""

    log_info "Progress started: ${label:-task} total=${total}"
    progress_render
}

progress_set() {
    local current="$1"
    local label="${2:-${PROGRESS_LABEL}}"

    if ((PROGRESS_STARTED_AT == 0)); then
        log_error "Progress has not been started"
        return "${PROGRESS_EXIT_NOT_STARTED}"
    fi

    progress_validate_count "${current}" || return $?

    if ((current > PROGRESS_TOTAL)); then
        current="${PROGRESS_TOTAL}"
    fi

    PROGRESS_CURRENT="${current}"
    PROGRESS_LABEL="${label}"
    progress_render
}

progress_advance() {
    local increment="${1:-1}"
    local label="${2:-${PROGRESS_LABEL}}"

    progress_validate_count "${increment}" || return $?
    progress_set "$((PROGRESS_CURRENT + increment))" "${label}"
}

progress_render() {
    local line

    if ((PROGRESS_STARTED_AT == 0)); then
        return "${PROGRESS_EXIT_NOT_STARTED}"
    fi

    line="$(progress_line "${PROGRESS_CURRENT}" "${PROGRESS_TOTAL}" "${PROGRESS_LABEL}")" || return $?
    PROGRESS_LAST_RENDER="${line}"

    if progress_terminal_enabled; then
        printf '\r\033[K%s' "${line}"
        return "${PROGRESS_EXIT_OK}"
    fi

    log_info "${line}"
}

progress_finish() {
    local label="${1:-${PROGRESS_LABEL}}"

    if ((PROGRESS_STARTED_AT == 0)); then
        log_error "Progress has not been started"
        return "${PROGRESS_EXIT_NOT_STARTED}"
    fi

    PROGRESS_CURRENT="${PROGRESS_TOTAL}"
    PROGRESS_LABEL="${label}"
    progress_render || return $?

    if progress_terminal_enabled; then
        printf '\n'
    fi

    log_success "Progress finished: ${label:-task} total=${PROGRESS_TOTAL}"
    PROGRESS_STARTED_AT=0
    return "${PROGRESS_EXIT_OK}"
}

progress_fail() {
    local label="${1:-${PROGRESS_LABEL}}"

    if ((PROGRESS_STARTED_AT == 0)); then
        log_error "Progress failed before it was started: ${label:-task}"
        return "${PROGRESS_EXIT_NOT_STARTED}"
    fi

    if progress_terminal_enabled; then
        printf '\n'
    fi

    log_error "Progress failed: ${label:-task} current=${PROGRESS_CURRENT} total=${PROGRESS_TOTAL}"
    PROGRESS_STARTED_AT=0
    return "${PROGRESS_EXIT_OK}"
}

progress_reset() {
    PROGRESS_TOTAL=0
    PROGRESS_CURRENT=0
    PROGRESS_LABEL=""
    PROGRESS_STARTED_AT=0
    PROGRESS_LAST_RENDER=""
    return "${PROGRESS_EXIT_OK}"
}
