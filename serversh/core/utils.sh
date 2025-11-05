#!/bin/bash

# =============================================================================
# ServerSH Utility Functions
# =============================================================================

# Source constants
source "${SERVERSH_LIB_DIR}/constants.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# String Utilities
# =============================================================================

# Trim whitespace from string
trim() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

# Convert string to lowercase
to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Convert string to uppercase
to_upper() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

# Check if string contains substring
contains() {
    local string="$1"
    local substring="$2"
    [[ "$string" == *"$substring"* ]]
}

# Check if string starts with prefix
starts_with() {
    local string="$1"
    local prefix="$2"
    [[ "$string" == "$prefix"* ]]
}

# Check if string ends with suffix
ends_with() {
    local string="$1"
    local suffix="$2"
    [[ "$string" == *"$suffix" ]]
}

# Generate random string
random_string() {
    local length="${1:-16}"
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

# Escape string for regex
regex_escape() {
    printf '%s' "$1" | sed 's/[][\.|$(){}?+*^]/\\&/g'
}

# =============================================================================
# Array Utilities
# =============================================================================

# Check if array contains element
array_contains() {
    local element="$1"
    shift
    local array=("$@")

    for item in "${array[@]}"; do
        [[ "$item" == "$element" ]] && return 0
    done
    return 1
}

# Remove duplicates from array
array_unique() {
    local array=("$@")
    local unique_array=()
    local seen=()

    for item in "${array[@]}"; do
        if ! array_contains "$item" "${seen[@]}"; then
            unique_array+=("$item")
            seen+=("$item")
        fi
    done

    printf '%s\n' "${unique_array[@]}"
}

# Join array elements with delimiter
array_join() {
    local delimiter="$1"
    shift
    local array=("$@")

    if [ ${#array[@]} -eq 0 ]; then
        return 0
    fi

    printf '%s' "${array[0]}"
    printf '%s%s' "$delimiter" "${array[@]:1}"
}

# Sort array
array_sort() {
    local array=("$@")
    printf '%s\n' "${array[@]}" | sort
}

# =============================================================================
# File Utilities
# =============================================================================

# Create directory with parents if needed
ensure_dir() {
    local dir="$1"
    local mode="${2:-755}"

    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || return $EXIT_GENERAL_ERROR
        chmod "$mode" "$dir" || return $EXIT_GENERAL_ERROR
    fi

    return $EXIT_SUCCESS
}

# Create backup of file
backup_file() {
    local file="$1"
    local backup_dir="${2:-${SERVERSH_STATE_DIR}/backups}"
    local timestamp

    if [ ! -f "$file" ]; then
        return $EXIT_CONFIG_ERROR
    fi

    ensure_dir "$backup_dir" || return $EXIT_GENERAL_ERROR
    timestamp=$(date +%Y%m%d_%H%M%S)

    cp "$file" "${backup_dir}/$(basename "$file").backup.${timestamp}" || return $EXIT_GENERAL_ERROR
    printf '%s' "${backup_dir}/$(basename "$file").backup.${timestamp}"
}

# Check if file is empty
is_file_empty() {
    local file="$1"
    [ ! -s "$file" ]
}

# Get file size in bytes
file_size() {
    local file="$1"
    stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || printf '0'
}

# Check file permissions
file_has_permissions() {
    local file="$1"
    local expected_perms="$2"
    local actual_perms

    actual_perms=$(stat -c%a "$file" 2>/dev/null || stat -f%Lp "$file" 2>/dev/null)
    [ "$actual_perms" = "$expected_perms" ]
}

# Create temporary file or directory
temp_file() {
    local prefix="${1:-serversh}"
    local suffix="${2:-tmp}"
    mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX.${suffix}"
}

temp_dir() {
    local prefix="${1:-serversh}"
    mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}

# =============================================================================
# Validation Utilities
# =============================================================================

# Validate hostname
is_valid_hostname() {
    local hostname="$1"
    [[ "$hostname" =~ $VALID_HOSTNAME_REGEX ]]
}

# Validate username
is_valid_username() {
    local username="$1"
    [[ "$username" =~ $VALID_USERNAME_REGEX ]]
}

# Validate port number
is_valid_port() {
    local port="$1"
    [[ "$port" =~ $VALID_PORT_REGEX ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ]
}

# Validate IPv4 address
is_valid_ipv4() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ ! "$ip" =~ $regex ]]; then
        return 1
    fi

    # Check each octet
    IFS='.' read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
            return 1
        fi
    done

    return 0
}

# Validate IPv6 address
is_valid_ipv6() {
    local ip="$1"
    # Simple IPv6 validation
    [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]
}

# Validate email address
is_valid_email() {
    local email="$1"
    local regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    [[ "$email" =~ $regex ]]
}

# Validate URL
is_valid_url() {
    local url="$1"
    local regex='^(https?|ftp)://[^\s/$.?#].[^\s]*$'
    [[ "$url" =~ $regex ]]
}

# =============================================================================
# Network Utilities
# =============================================================================

# Check if port is open
is_port_open() {
    local port="$1"
    local host="${2:-localhost}"

    if command -v nc >/dev/null 2>&1; then
        nc -z "$host" "$port" 2>/dev/null
    elif command -v telnet >/dev/null 2>&1; then
        timeout 2 telnet "$host" "$port" </dev/null >/dev/null 2>&1
    else
        return 1
    fi
}

# Check network connectivity
check_network_connectivity() {
    local host="${1:-8.8.8.8}"
    local timeout="${2:-5}"

    if command -v ping >/dev/null 2>&1; then
        ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1
    else
        return 1
    fi
}

# Get local IP address
get_local_ip() {
    local interface="${1:-}"

    if command -v ip >/dev/null 2>&1; then
        if [ -n "$interface" ]; then
            ip -4 addr show "$interface" | awk '/inet/ {print $2}' | cut -d/ -f1 | head -1
        else
            ip route get 8.8.8.8 | awk '/src/ {print $7}' | head -1
        fi
    elif command -v ifconfig >/dev/null 2>&1; then
        if [ -n "$interface" ]; then
            ifconfig "$interface" | awk '/inet / {print $2}' | head -1
        else
            ifconfig | awk '/inet / && !/127.0.0.1/ {print $2}' | head -1
        fi
    else
        return 1
    fi
}

# Get public IP address
get_public_ip() {
    if command -v curl >/dev/null 2>&1; then
        curl -s --max-time 10 "https://api.ipify.org" 2>/dev/null ||
        curl -s --max-time 10 "https://ipinfo.io/ip" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=10 "https://api.ipify.org" 2>/dev/null ||
        wget -qO- --timeout=10 "https://ipinfo.io/ip" 2>/dev/null
    fi
}

# =============================================================================
# System Utilities
# =============================================================================

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get system information
get_system_info() {
    local info_type="$1"

    case "$info_type" in
        "os")
            if [ -f "$OS_ID_FILE" ]; then
                . "$OS_ID_FILE"
                printf '%s' "$ID"
            fi
            ;;
        "version")
            if [ -f "$OS_ID_FILE" ]; then
                . "$OS_ID_FILE"
                printf '%s' "$VERSION_ID"
            fi
            ;;
        "arch")
            uname -m
            ;;
        "kernel")
            uname -r
            ;;
        "hostname")
            hostname
            ;;
        "memory")
            if command_exists free; then
                free -h | awk '/^Mem:/ {print $2}'
            fi
            ;;
        "disk")
            if command_exists df; then
                df -h / | awk 'NR==2 {print $2}'
            fi
            ;;
        "cpu")
            if command_exists nproc; then
                nproc
            elif [ -f /proc/cpuinfo ]; then
                grep -c "^processor" /proc/cpuinfo
            fi
            ;;
    esac
}

# Check if service is running
is_service_running() {
    local service="$1"

    if command_exists systemctl; then
        systemctl is-active --quiet "$service"
    elif command_exists service; then
        service "$service" status >/dev/null 2>&1
    else
        return 1
    fi
}

# Check if package is installed
is_package_installed() {
    local package="$1"

    case "$(get_system_info os)" in
        ubuntu|debian)
            dpkg -l | grep -q "^ii.*$package "
            ;;
        centos|rhel|fedora)
            if command_exists dnf; then
                dnf list installed "$package" >/dev/null 2>&1
            elif command_exists yum; then
                yum list installed "$package" >/dev/null 2>&1
            fi
            ;;
        opensuse*)
            zypper search -i "$package" | grep -q "^i "
            ;;
        arch)
            pacman -Q "$package" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# Process Utilities
# =============================================================================

# Check if process is running
is_process_running() {
    local process="$1"
    pgrep -f "$process" >/dev/null 2>&1
}

# Kill process gracefully
kill_process() {
    local process="$1"
    local timeout="${2:-10}"

    if is_process_running "$process"; then
        pkill -TERM "$process"
        local count=0
        while is_process_running "$process" && [ $count -lt "$timeout" ]; do
            sleep 1
            ((count++))
        done

        if is_process_running "$process"; then
            pkill -KILL "$process"
        fi
    fi
}

# Wait for process to complete
wait_for_process() {
    local pid="$1"
    local timeout="${2:-30}"
    local count=0

    while kill -0 "$pid" 2>/dev/null && [ $count -lt "$timeout" ]; do
        sleep 1
        ((count++))
    done

    ! kill -0 "$pid" 2>/dev/null
}

# =============================================================================
# Math Utilities
# =============================================================================

# Convert string to integer
to_int() {
    local value="$1"
    printf '%d' "$value" 2>/dev/null || printf '0'
}

# Check if number is even
is_even() {
    local num="$1"
    [ $((num % 2)) -eq 0 ]
}

# Check if number is odd
is_odd() {
    local num="$1"
    [ $((num % 2)) -eq 1 ]
}

# Generate random number in range
random_number() {
    local min="${1:-0}"
    local max="${2:-100}"

    # Check if /dev/urandom is available
    if [ -r /dev/urandom ]; then
        od -N 4 -t u4 -An /dev/urandom | tr -d ' '
    else
        # Fallback to $RANDOM
        echo $RANDOM
    fi
}

# Calculate percentage
percentage() {
    local value="$1"
    local total="$2"
    local scale="${3:-2}"

    if [ "$total" -eq 0 ]; then
        printf '0'
    else
        awk "BEGIN { printf \"%.${scale}f\", ($value * 100) / $total }"
    fi
}

# =============================================================================
# Time Utilities
# =============================================================================

# Get current timestamp
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Get current unix timestamp
unix_timestamp() {
    date '+%s'
}

# Format duration in seconds to human readable
format_duration() {
    local seconds="$1"
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [ $hours -gt 0 ]; then
        printf '%dh %dm %ds' $hours $minutes $secs
    elif [ $minutes -gt 0 ]; then
        printf '%dm %ds' $minutes $secs
    else
        printf '%ds' $secs
    fi
}

# Check if timeout has expired
is_timeout_expired() {
    local start_time="$1"
    local timeout="$2"
    local current_time
    current_time=$(unix_timestamp)

    [ $((current_time - start_time)) -gt "$timeout" ]
}

# =============================================================================
# Color Utilities
# =============================================================================

# Colorize text
colorize() {
    local color="$1"
    local text="$2"
    printf '%b%s%b' "$color" "$text" "$COLOR_RESET"
}

# Print colored text (if terminal supports colors)
print_color() {
    local color="$1"
    local text="$2"
    local file="${3:-/dev/stdout}"

    if [ -t 1 ] || [ "$file" != "/dev/stdout" ]; then
        printf '%b%s%b\n' "$color" "$text" "$COLOR_RESET" >> "$file"
    else
        printf '%s\n' "$text" >> "$file"
    fi
}

# =============================================================================
# Progress Utilities
# =============================================================================

# Simple progress bar
progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-50}"
    local char="${4:-█}"

    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf '\r['
    printf '%*s' "$filled" | tr ' ' "$char"
    printf '%*s' "$empty"
    printf '] %d%%' "$percentage"
}

# Spinner animation
spinner() {
    local chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local delay="${1:-0.1}"

    while true; do
        for char in "${chars[@]}"; do
            printf '\r%s' "$char"
            sleep "$delay"
        done
    done
}