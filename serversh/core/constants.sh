#!/bin/bash

# =============================================================================
# ServerSH Constants
# =============================================================================

# Prevent re-sourcing this file
if [[ -n "${SERVERSH_CONSTANTS_LOADED:-}" ]]; then
    return 0
fi
readonly SERVERSH_CONSTANTS_LOADED=1

# Version Information
readonly SERVERSH_VERSION="1.0.0-alpha"
readonly SERVERSH_BUILD_DATE="$(date +%Y-%m-%d)"
readonly SERVERSH_COPYRIGHT="2024 ServerSH Project"

# Paths
# SERVERSH_ROOT should already be set by the calling script
# Only calculate it if not already set
if [[ -z "${SERVERSH_ROOT:-}" ]]; then
    readonly SERVERSH_ROOT="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
else
    readonly SERVERSH_ROOT="$SERVERSH_ROOT"
fi
readonly SERVERSH_LIB_DIR="${SERVERSH_ROOT}/core"
readonly SERVERSH_MODULES_DIR="${SERVERSH_ROOT}/modules"
readonly SERVERSH_CONFIG_DIR="${SERVERSH_ROOT}/config"
readonly SERVERSH_TEMPLATES_DIR="${SERVERSH_ROOT}/templates"
readonly SERVERSH_STATE_DIR="${SERVERSH_STATE_DIR:-/var/lib/serversh}"
readonly SERVERSH_LOG_DIR="/var/log/serversh"
readonly SERVERSH_RUN_DIR="/run/serversh"

# Files
readonly SERVERSH_CONFIG_FILE="${SERVERSH_CONFIG_FILE:-${SERVERSH_CONFIG_DIR}/default.yaml}"
readonly SERVERSH_STATE_FILE="${SERVERSH_STATE_DIR}/state.json"
readonly SERVERSH_LOCK_FILE="${SERVERSH_RUN_DIR}/serversh.lock"
readonly SERVERSH_LOG_FILE="${SERVERSH_LOG_DIR}/serversh.log"

# Exit Codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_INVALID_ARGS=2
readonly EXIT_MISSING_DEPS=3
readonly EXIT_PERMISSION_DENIED=4
readonly EXIT_CONFIG_ERROR=5
readonly EXIT_MODULE_ERROR=6
readonly EXIT_STATE_ERROR=7
readonly EXIT_LOCK_ERROR=8

# Colors for Output
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[31m'
readonly COLOR_GREEN='\033[32m'
readonly COLOR_YELLOW='\033[33m'
readonly COLOR_BLUE='\033[34m'
readonly COLOR_MAGENTA='\033[35m'
readonly COLOR_CYAN='\033[36m'
readonly COLOR_WHITE='\033[37m'

# Logging Levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_FATAL=4

# Module States
readonly MODULE_STATE_UNKNOWN="unknown"
readonly MODULE_STATE_PENDING="pending"
readonly MODULE_STATE_RUNNING="running"
readonly MODULE_STATE_COMPLETED="completed"
readonly MODULE_STATE_FAILED="failed"
readonly MODULE_STATE_SKIPPED="skipped"
readonly MODULE_STATE_ROLLBACK="rollback"

# Checkpoint Types
readonly CHECKPOINT_TYPE_PRE_INSTALL="pre_install"
readonly CHECKPOINT_TYPE_POST_INSTALL="post_install"
readonly CHECKPOINT_TYPE_PRE_MODULE="pre_module"
readonly CHECKPOINT_TYPE_POST_MODULE="post_module"
readonly CHECKPOINT_TYPE_ERROR="error"

# Validation
readonly VALID_HOSTNAME_REGEX='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
readonly VALID_USERNAME_REGEX='^[a-z_][a-z0-9_-]*$'
readonly VALID_PORT_REGEX='^[0-9]+$'

# Default Configuration
readonly DEFAULT_SSH_PORT=2222
readonly DEFAULT_LOG_LEVEL="${LOG_LEVEL_INFO}"
readonly DEFAULT_PARALLEL_JOBS=4
readonly DEFAULT_TIMEOUT=300

# Security
readonly SERVERSH_USER="${SERVERSH_USER:-root}"
readonly SERVERSH_GROUP="${SERVERSH_GROUP:-root}"
readonly SERVERSH_UMASK=0022

# System Limits
readonly MAX_MODULE_NAME_LENGTH=64
readonly MAX_CONFIG_FILE_SIZE=1048576  # 1MB
readonly MAX_LOG_FILE_SIZE=10485760    # 10MB
readonly MAX_STATE_SIZE=1048576        # 1MB

# OS Detection
readonly OS_ID_FILE="/etc/os-release"
readonly OS_DEBIAN_VERSION_FILE="/etc/debian_version"
readonly OS_REDHAT_RELEASE_FILE="/etc/redhat-release"

# Package Managers
readonly PKG_MANAGER_APT="apt"
readonly PKG_MANAGER_YUM="yum"
readonly PKG_MANAGER_DNF="dnf"
readonly PKG_MANAGER_ZYPPER="zypper"
readonly PKG_MANAGER_PACMAN="pacman"

# Service Managers
readonly SERVICE_MANAGER_SYSTEMD="systemd"
readonly SERVICE_MANAGER_SYSV="sysv"
readonly SERVICE_MANAGER_OPENRC="openrc"

# Firewalls
readonly FIREWALL_UFW="ufw"
readonly FIREWALL_FIREWALLD="firewalld"
readonly FIREWALL_IPTABLES="iptables"

# Docker Constants (from example.sh)
readonly DOCKER_MTU=1450
readonly DOCKER_IPV6_ENABLED=true
readonly DOCKER_IPV6_SUBNET="2001:db8:1::/64"
readonly DOCKER_DEFAULT_NETWORK="newt_talk"
readonly DOCKER_DEFAULT_SUBNET="172.25.0.0/16"
readonly DOCKER_DEFAULT_SUBNET_SIZE=24
readonly DOCKER_CUSTOM_SUBNET="172.25.1.0/24"
readonly DOCKER_CUSTOM_IPV6_SUBNET="2001:db8:1:1::/80"

# Required Commands
readonly REQUIRED_COMMANDS=(
    "bash"
    "cat"
    "chmod"
    "chown"
    "cp"
    "grep"
    "mkdir"
    "mktemp"
    "mv"
    "rm"
    "sed"
    "sort"
    "tail"
    "touch"
    "tr"
    "which"
)

# Optional Commands
readonly OPTIONAL_COMMANDS=(
    "curl"
    "wget"
    "jq"
    "yq"
    "shellcheck"
    "bats"
)

# Module Categories
readonly MODULE_CATEGORY_SYSTEM="system"
readonly MODULE_CATEGORY_SECURITY="security"
readonly MODULE_CATEGORY_CONTAINER="container"
readonly MODULE_CATEGORY_MONITORING="monitoring"
readonly MODULE_CATEGORY_APPLICATION="application"
readonly MODULE_CATEGORY_NETWORK="network"
readonly MODULE_CATEGORY_CUSTOM="custom"

# Dependencies
readonly MIN_BASH_VERSION=4
readonly MIN_KERNEL_VERSION=3.10

# Network
readonly IPV4_LOCALHOST="127.0.0.1"
readonly IPV6_LOCALHOST="::1"
readonly DNS_SERVERS=("8.8.8.8" "8.8.4.4" "1.1.1.1")

# Timeouts (seconds)
readonly TIMEOUT_MODULE_INSTALL=1800    # 30 minutes
readonly TIMEOUT_CONFIG_VALIDATION=60   # 1 minute
readonly TIMEOUT_STATE_OPERATION=30     # 30 seconds
readonly TIMEOUT_NETWORK_CHECK=10       # 10 seconds

# Performance
readonly MEMORY_LIMIT_MB=512
readonly CPU_LIMIT_PERCENT=80

# Security Settings
readonly UMASK_SETTING=0022
readonly FILE_PERMISSION_CONFIG=644
readonly FILE_PERMISSION_EXEC=755
readonly FILE_PERMISSION_SECRET=600
readonly DIR_PERMISSION=755

# =============================================================================
# Validation Functions
# =============================================================================

# Validate required commands are available
validate_required_commands() {
    local missing_commands=()

    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -gt 0 ]; then
        printf "ERROR: Missing required commands: %s\n" "${missing_commands[*]}" >&2
        return $EXIT_MISSING_DEPS
    fi

    return $EXIT_SUCCESS
}

# Validate bash version
validate_bash_version() {
    if [ "${BASH_VERSION%%.*}" -lt "$MIN_BASH_VERSION" ]; then
        printf "ERROR: Bash version %s is too old. Minimum required: %s\n" "$BASH_VERSION" "$MIN_BASH_VERSION" >&2
        return $EXIT_GENERAL_ERROR
    fi

    return $EXIT_SUCCESS
}

# Validate system environment
validate_system_environment() {
    local errors=0

    # Check if running as root (for most operations)
    if [ "$(id -u)" -ne 0 ]; then
        printf "WARNING: Not running as root. Some operations may fail.\n" >&2
    fi

    # Check basic system directories
    for dir in "/etc" "/var" "/tmp"; do
        if [ ! -d "$dir" ]; then
            printf "ERROR: Required system directory not found: %s\n" "$dir" >&2
            ((errors++))
        fi
    done

    return $errors
}