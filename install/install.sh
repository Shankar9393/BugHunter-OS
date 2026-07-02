#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly CONFIG_FILE="${ROOT_DIR}/config/config.conf"

readonly EXIT_OK=0
readonly EXIT_INSTALL_FAILURES=2
readonly EXIT_UNSUPPORTED_OS=3
readonly EXIT_CONFIG_ERROR=4
readonly EXIT_PRECHECK_ERROR=5

COLOR_RESET=""
COLOR_RED=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_BLUE=""
COLOR_BOLD=""

LOG_FILE=""
OS_ID="unknown"
OS_NAME="unknown"
OS_VERSION_ID="unknown"
OS_LIKE=""
IS_KALI="false"
APT_UPDATED="false"
INSTALL_ENABLED="true"

declare -a INSTALLED_TOOLS=()
declare -a SKIPPED_TOOLS=()
declare -a INSTALLED_PACKAGES=()
declare -a INSTALLED_GO_TOOLS=()
declare -a INSTALLED_PYTHON_TOOLS=()
declare -a INSTALLED_NODE_TOOLS=()
declare -a FAILED_TOOLS=()
declare -a UNAVAILABLE_TOOLS=()
declare -a VERSION_NOTES=()

usage() {
    cat <<'USAGE'
BugHunter-OS installer

Usage:
  ./install/install.sh [options]

Options:
  --verify-only     Detect and verify dependencies without installing missing packages.
  --check-only      Alias for --verify-only.
  --no-color        Disable colored output.
  -h, --help        Show this help message.
USAGE
}

init_colors() {
    if [[ "${ENABLE_COLOR:-true}" == "true" && -t 1 ]]; then
        COLOR_RESET=$'\033[0m'
        COLOR_RED=$'\033[31m'
        COLOR_GREEN=$'\033[32m'
        COLOR_YELLOW=$'\033[33m'
        COLOR_BLUE=$'\033[34m'
        COLOR_BOLD=$'\033[1m'
    fi
}

timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log_line() {
    local level="$1"
    shift
    local message="$*"
    local line

    line="$(timestamp) [${level}] ${message}"
    if [[ -n "${LOG_FILE}" ]]; then
        printf '%s\n' "${line}" >>"${LOG_FILE}"
    fi
}

print_line() {
    local color="$1"
    local level="$2"
    shift 2
    local message="$*"

    printf '%s[%s]%s %s\n' "${color}" "${level}" "${COLOR_RESET}" "${message}"
    log_line "${level}" "${message}"
}

info() {
    print_line "${COLOR_BLUE}" "INFO" "$@"
}

success() {
    print_line "${COLOR_GREEN}" "OK" "$@"
}

warn() {
    print_line "${COLOR_YELLOW}" "WARN" "$@"
}

error() {
    print_line "${COLOR_RED}" "ERROR" "$@"
}

die() {
    local exit_code="$1"
    shift
    error "$@"
    exit "${exit_code}"
}

on_error() {
    local exit_code=$?
    local line_no=$1
    error "Unhandled error at ${SCRIPT_NAME}:${line_no} with exit code ${exit_code}"
    exit "${exit_code}"
}

trap 'on_error ${LINENO}' ERR

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --check-only|--verify-only)
                INSTALL_ENABLED="false"
                ;;
            --no-color)
                ENABLE_COLOR="false"
                ;;
            -h|--help)
                usage
                exit "${EXIT_OK}"
                ;;
            *)
                printf 'Unknown option: %s\n' "$1" >&2
                usage >&2
                exit "${EXIT_PRECHECK_ERROR}"
                ;;
        esac
        shift
    done
}

load_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        printf 'Missing config file: %s\n' "${CONFIG_FILE}" >&2
        exit "${EXIT_CONFIG_ERROR}"
    fi

    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"

    if [[ -n "${BUGHUNTER_LOCAL_CONFIG:-}" ]]; then
        if [[ -f "${BUGHUNTER_LOCAL_CONFIG}" ]]; then
            # shellcheck source=/dev/null
            source "${BUGHUNTER_LOCAL_CONFIG}"
        else
            printf 'Configured local override does not exist: %s\n' "${BUGHUNTER_LOCAL_CONFIG}" >&2
            exit "${EXIT_CONFIG_ERROR}"
        fi
    fi
}

init_logging() {
    local configured_log="${INSTALL_LOG_FILE:-logs/install.log}"
    local logs_dir

    if [[ "${configured_log}" = /* ]]; then
        LOG_FILE="${configured_log}"
    else
        LOG_FILE="${ROOT_DIR}/${configured_log}"
    fi

    logs_dir="$(dirname "${LOG_FILE}")"
    mkdir -p "${logs_dir}"
    : >"${LOG_FILE}"
}

detect_os() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_NAME="${NAME:-unknown}"
        OS_VERSION_ID="${VERSION_ID:-unknown}"
        OS_LIKE="${ID_LIKE:-}"
    else
        OS_NAME="$(uname -s)"
        OS_ID="$(printf '%s' "${OS_NAME}" | tr '[:upper:]' '[:lower:]')"
        OS_VERSION_ID="$(uname -r)"
        OS_LIKE=""
    fi

    if [[ "${OS_ID}" == "kali" ]] || [[ "${OS_NAME,,}" == *"kali"* ]]; then
        IS_KALI="true"
    fi

    info "Operating system: ${OS_NAME} (${OS_ID}) ${OS_VERSION_ID}"
    if [[ "${IS_KALI}" == "true" ]]; then
        success "Kali Linux detected"
    else
        warn "Kali Linux not detected; apt-based Debian-like installation will be used when available"
    fi
}

require_apt() {
    if ! command -v apt-get >/dev/null 2>&1; then
        die "${EXIT_UNSUPPORTED_OS}" "apt-get was not found. This installer currently supports apt-based systems only."
    fi

    if ! command -v apt-cache >/dev/null 2>&1; then
        die "${EXIT_UNSUPPORTED_OS}" "apt-cache was not found. This installer currently supports apt-based systems only."
    fi

    success "apt support detected"
}

run_privileged() {
    local -a command_args=("$@")

    if ((EUID == 0)); then
        "${command_args[@]}"
        return $?
    fi

    if command -v sudo >/dev/null 2>&1; then
        sudo "${command_args[@]}"
        return $?
    fi

    return 127
}

apt_update_once() {
    if [[ "${APT_UPDATED}" == "true" ]]; then
        return 0
    fi

    info "Updating apt package metadata"
    if run_privileged apt-get update; then
        APT_UPDATED="true"
        success "apt package metadata updated"
        return 0
    fi

    warn "apt-get update failed; continuing with existing package metadata"
    APT_UPDATED="true"
    return 1
}

package_candidate_version() {
    local package_name="$1"
    apt-cache policy "${package_name}" 2>/dev/null | awk '/Candidate:/ {print $2; exit}'
}

package_installed_version() {
    local package_name="$1"
    dpkg-query -W -f='${Version}' "${package_name}" 2>/dev/null || true
}

package_available() {
    local package_name="$1"
    local candidate

    candidate="$(package_candidate_version "${package_name}")"
    [[ -n "${candidate}" && "${candidate}" != "(none)" ]]
}

command_version() {
    local command_name="$1"
    local command_path="${2:-}"
    local output=""

    if [[ -z "${command_path}" ]]; then
        command_path="$(command_path_for "${command_name}")"
    fi

    if [[ -z "${command_path}" ]]; then
        printf 'version unavailable'
        return 0
    fi

    if output="$("${command_path}" --version 2>&1 | head -n 1)"; then
        printf '%s' "${output}"
        return 0
    fi

    if output="$("${command_path}" version 2>&1 | head -n 1)"; then
        printf '%s' "${output}"
        return 0
    fi

    printf 'version unavailable'
}

version_note_for_package() {
    local command_name="$1"
    local package_name="$2"
    local installed_version=""
    local candidate_version=""
    local command_version_text=""

    command_version_text="$(command_version "${command_name}")"
    installed_version="$(package_installed_version "${package_name}")"
    candidate_version="$(package_candidate_version "${package_name}")"

    if [[ -n "${installed_version}" && -n "${candidate_version}" && "${candidate_version}" != "(none)" ]]; then
        VERSION_NOTES+=("${command_name}: ${command_version_text}; package ${package_name} installed=${installed_version}, candidate=${candidate_version}")
    else
        VERSION_NOTES+=("${command_name}: ${command_version_text}")
    fi
}

go_bin_dir() {
    local gopath=""

    if command -v go >/dev/null 2>&1; then
        gopath="$(go env GOPATH 2>/dev/null || true)"
    fi

    if [[ -z "${gopath}" ]]; then
        gopath="${HOME}/go"
    fi

    printf '%s/bin' "${gopath}"
}

command_path_for() {
    local command_name="$1"
    local go_path=""

    if command -v "${command_name}" >/dev/null 2>&1; then
        command -v "${command_name}"
        return 0
    fi

    go_path="$(go_bin_dir)/${command_name}"
    if [[ -x "${go_path}" ]]; then
        printf '%s\n' "${go_path}"
        return 0
    fi

    return 1
}

command_exists() {
    local command_name="$1"
    command_path_for "${command_name}" >/dev/null 2>&1
}

record_existing_tool() {
    local command_name="$1"
    local source_name="$2"
    local command_path=""
    local command_version_text=""

    command_path="$(command_path_for "${command_name}")"
    command_version_text="$(command_version "${command_name}" "${command_path}")"
    INSTALLED_TOOLS+=("${command_name}")
    SKIPPED_TOOLS+=("${command_name}")
    VERSION_NOTES+=("${command_name}: ${command_version_text}; source=${source_name}; path=${command_path}")
    success "Found ${command_name} at ${command_path}; skipping installation"
}

install_package() {
    local package_name="$1"

    apt_update_once || true

    info "Installing package: ${package_name}"
    if run_privileged env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${package_name}"; then
        INSTALLED_PACKAGES+=("${package_name}")
        success "Package installed: ${package_name}"
        return 0
    fi

    warn "Package installation failed: ${package_name}"
    return 1
}

check_tool() {
    local command_name="$1"
    local package_name="$2"

    if command_exists "${command_name}"; then
        record_existing_tool "${command_name}" "existing"
        version_note_for_package "${command_name}" "${package_name}"
        return 0
    fi

    warn "Missing command: ${command_name}"

    if [[ "${INSTALL_ENABLED}" != "true" ]]; then
        FAILED_TOOLS+=("${command_name}")
        warn "Verify-only mode enabled; not installing ${command_name}"
        return 1
    fi

    if ! package_available "${package_name}"; then
        UNAVAILABLE_TOOLS+=("${command_name} (${package_name})")
        warn "No apt candidate found for ${package_name}; skipping ${command_name}"
        return 1
    fi

    info "Resolved ${command_name} to apt package ${package_name} candidate $(package_candidate_version "${package_name}")"
    if install_package "${package_name}" && command_exists "${command_name}"; then
        version_note_for_package "${command_name}" "${package_name}"
        INSTALLED_TOOLS+=("${command_name}")
        success "Verified installed command: ${command_name}"
        return 0
    fi

    FAILED_TOOLS+=("${command_name}")
    warn "Verification failed for ${command_name}; continuing"
    return 1
}

install_go_tool() {
    local command_name="$1"
    local module_path="$2"
    local go_binary=""

    if command_exists "${command_name}"; then
        record_existing_tool "${command_name}" "existing"
        return 0
    fi

    warn "Missing Go tool: ${command_name}"

    if [[ "${INSTALL_ENABLED}" != "true" ]]; then
        FAILED_TOOLS+=("${command_name}")
        warn "Verify-only mode enabled; not installing ${command_name}"
        return 1
    fi

    if [[ "${INSTALL_GO_TOOLS:-true}" != "true" ]]; then
        UNAVAILABLE_TOOLS+=("${command_name} (go install disabled)")
        warn "Go tool installation disabled; skipping ${command_name}"
        return 1
    fi

    if ! command_exists "${TOOL_GO:-go}"; then
        FAILED_TOOLS+=("${command_name}")
        warn "Go is unavailable; cannot install ${command_name}"
        return 1
    fi

    info "Installing Go tool ${command_name} from ${module_path}"
    if go install "${module_path}"; then
        go_binary="$(go_bin_dir)/${command_name}"
        if command_exists "${command_name}" || [[ -x "${go_binary}" ]]; then
            INSTALLED_GO_TOOLS+=("${command_name}")
            INSTALLED_TOOLS+=("${command_name}")
            VERSION_NOTES+=("${command_name}: $(command_version "${command_name}") ; source=go install ${module_path}")
            success "Verified Go tool: ${command_name}"
            if ! command -v "${command_name}" >/dev/null 2>&1; then
                warn "${command_name} installed at ${go_binary}, but that directory is not in PATH"
            fi
            return 0
        fi
    fi

    FAILED_TOOLS+=("${command_name}")
    warn "Go installation failed or verification failed for ${command_name}"
    return 1
}

install_python_tool() {
    local command_name="$1"
    local package_name="$2"
    local python_user_base=""
    local python_user_bin=""

    if command_exists "${command_name}"; then
        record_existing_tool "${command_name}" "existing"
        return 0
    fi

    warn "Missing Python tool: ${command_name}"

    if [[ "${INSTALL_ENABLED}" != "true" ]]; then
        FAILED_TOOLS+=("${command_name}")
        warn "Verify-only mode enabled; not installing ${command_name}"
        return 1
    fi

    if [[ "${INSTALL_PYTHON_TOOLS:-true}" != "true" ]]; then
        UNAVAILABLE_TOOLS+=("${command_name} (Python installation disabled)")
        warn "Python tool installation disabled; skipping ${command_name}"
        return 1
    fi

    if command_exists "${TOOL_PIPX:-pipx}"; then
        info "Installing Python tool ${command_name} with pipx package ${package_name}"
        if pipx install "${package_name}"; then
            :
        elif pipx inject "${package_name}" "${package_name}" >/dev/null 2>&1; then
            :
        else
            warn "pipx failed for ${package_name}; trying pip --user when available"
        fi
    fi

    if ! command_exists "${command_name}" && command_exists "${TOOL_PIP:-pip3}"; then
        info "Installing Python tool ${command_name} with pip --user package ${package_name}"
        if ! "${TOOL_PIP:-pip3}" install --user "${package_name}"; then
            warn "pip --user failed for ${package_name}"
        fi
    fi

    python_user_base="$("${TOOL_PYTHON:-python3}" -m site --user-base 2>/dev/null || true)"
    python_user_bin="${python_user_base}/bin/${command_name}"
    if command_exists "${command_name}" || [[ -x "${python_user_bin}" ]]; then
        INSTALLED_PYTHON_TOOLS+=("${command_name}")
        INSTALLED_TOOLS+=("${command_name}")
        VERSION_NOTES+=("${command_name}: $(command_version "${command_name}") ; source=python package ${package_name}")
        success "Verified Python tool: ${command_name}"
        if ! command -v "${command_name}" >/dev/null 2>&1 && [[ -x "${python_user_bin}" ]]; then
            warn "${command_name} installed at ${python_user_bin}, but that directory is not in PATH"
        fi
        return 0
    fi

    FAILED_TOOLS+=("${command_name}")
    warn "Python installation failed or verification failed for ${command_name}"
    return 1
}

install_node_tool() {
    local command_name="$1"
    local package_name="$2"

    if command_exists "${command_name}"; then
        record_existing_tool "${command_name}" "existing"
        return 0
    fi

    warn "Missing Node.js tool: ${command_name}"

    if [[ "${INSTALL_ENABLED}" != "true" ]]; then
        FAILED_TOOLS+=("${command_name}")
        warn "Verify-only mode enabled; not installing ${command_name}"
        return 1
    fi

    if [[ "${INSTALL_NODE_TOOLS:-true}" != "true" ]]; then
        UNAVAILABLE_TOOLS+=("${command_name} (Node.js installation disabled)")
        warn "Node.js tool installation disabled; skipping ${command_name}"
        return 1
    fi

    if ! command_exists "${TOOL_NPM:-npm}"; then
        FAILED_TOOLS+=("${command_name}")
        warn "npm is unavailable; cannot install ${command_name}"
        return 1
    fi

    info "Installing Node.js tool ${command_name} with npm package ${package_name}"
    if run_privileged npm install -g "${package_name}" && command_exists "${command_name}"; then
        INSTALLED_NODE_TOOLS+=("${command_name}")
        INSTALLED_TOOLS+=("${command_name}")
        VERSION_NOTES+=("${command_name}: $(command_version "${command_name}") ; source=npm package ${package_name}")
        success "Verified Node.js tool: ${command_name}"
        return 0
    fi

    FAILED_TOOLS+=("${command_name}")
    warn "Node.js installation failed or verification failed for ${command_name}"
    return 1
}

print_array_summary() {
    local title="$1"
    shift
    local -a items=("$@")
    local item

    printf '%s%s%s\n' "${COLOR_BOLD}" "${title}" "${COLOR_RESET}"
    log_line "SUMMARY" "${title}"
    if ((${#items[@]} == 0)); then
        printf '  none\n'
        log_line "SUMMARY" "  none"
        return
    fi

    for item in "${items[@]}"; do
        printf '  - %s\n' "${item}"
        log_line "SUMMARY" "  - ${item}"
    done
}

print_summary() {
    printf '\n%sInstallation summary%s\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    log_line "SUMMARY" "Installation summary"
    print_array_summary "Detected tools" "${INSTALLED_TOOLS[@]}"
    print_array_summary "Skipped existing tools" "${SKIPPED_TOOLS[@]}"
    print_array_summary "Installed packages" "${INSTALLED_PACKAGES[@]}"
    print_array_summary "Installed Go tools" "${INSTALLED_GO_TOOLS[@]}"
    print_array_summary "Installed Python tools" "${INSTALLED_PYTHON_TOOLS[@]}"
    print_array_summary "Installed Node.js tools" "${INSTALLED_NODE_TOOLS[@]}"
    print_array_summary "Unavailable apt packages" "${UNAVAILABLE_TOOLS[@]}"
    print_array_summary "Failed tools" "${FAILED_TOOLS[@]}"
    print_array_summary "Version notes" "${VERSION_NOTES[@]}"
    printf 'Log file: %s\n' "${LOG_FILE}"
}

main() {
    load_config
    parse_args "$@"
    init_colors
    init_logging

    info "Starting ${BUGHUNTER_NAME:-BugHunter-OS} dependency installation"
    detect_os
    require_apt

    local spec
    local command_name
    local installer_name
    local -a apt_tool_specs=()
    local -a go_tool_specs=()
    local -a python_tool_specs=()
    local -a node_tool_specs=()

    IFS=' ' read -r -a apt_tool_specs <<<"${APT_TOOL_SPECS:-}"
    for spec in "${apt_tool_specs[@]}"; do
        command_name="${spec%%:*}"
        installer_name="${spec#*:}"
        check_tool "${command_name}" "${installer_name}" || true
    done

    IFS=' ' read -r -a go_tool_specs <<<"${GO_TOOL_SPECS:-}"
    for spec in "${go_tool_specs[@]}"; do
        command_name="${spec%%:*}"
        installer_name="${spec#*:}"
        install_go_tool "${command_name}" "${installer_name}" || true
    done

    IFS=' ' read -r -a python_tool_specs <<<"${PYTHON_TOOL_SPECS:-}"
    for spec in "${python_tool_specs[@]}"; do
        command_name="${spec%%:*}"
        installer_name="${spec#*:}"
        install_python_tool "${command_name}" "${installer_name}" || true
    done

    IFS=' ' read -r -a node_tool_specs <<<"${NODE_TOOL_SPECS:-}"
    for spec in "${node_tool_specs[@]}"; do
        command_name="${spec%%:*}"
        installer_name="${spec#*:}"
        install_node_tool "${command_name}" "${installer_name}" || true
    done

    print_summary

    if ((${#FAILED_TOOLS[@]} > 0 || ${#UNAVAILABLE_TOOLS[@]} > 0)); then
        warn "Installer completed with dependency issues"
        exit "${EXIT_INSTALL_FAILURES}"
    fi

    success "All required dependencies are available"
    exit "${EXIT_OK}"
}

main "$@"
