#!/bin/bash

# =============================================================================
# ServerSH Logging System
# =============================================================================

# Source dependencies
source "${SERVERSH_LIB_DIR}/constants.sh" || exit $EXIT_MISSING_DEPS
source "${SERVERSH_LIB_DIR}/utils.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Global Variables
# =============================================================================

# Logging configuration
declare -g LOG_LEVEL="${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}"
declare -g LOG_FILE="${SERVERSH_LOG_FILE}"
declare -g LOG_ENABLED=true
declare -g LOG_COLORS=true
declare -g LOG_FORMAT="detailed"  # simple, detailed, json

# File descriptors for different log levels
declare -g LOG_FD_DEBUG=3
declare -g LOG_FD_INFO=4
declare -g LOG_FD_WARN=5
declare -g LOG_FD_ERROR=6
declare -g LOG_FD_FATAL=7

# Log rotation settings
declare -g LOG_MAX_SIZE="${LOG_MAX_SIZE:-$MAX_LOG_FILE_SIZE}"
declare -g LOG_MAX_FILES="${LOG_MAX_FILES:-5}"

# =============================================================================
# Logging Functions
# =============================================================================

# Initialize logging system
log_init() {
    local log_file="${1:-$LOG_FILE}"
    local log_level="${2:-$LOG_LEVEL}"

    # Ensure log directory exists
    local log_dir
    log_dir="$(dirname "$log_file")"
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" || {
            echo "ERROR: Cannot create log directory: $log_dir" >&2
            return 1
        }
    fi

    # Set global variables
    LOG_FILE="$log_file"
    LOG_LEVEL="$log_level"

    # Check if colors should be disabled
    if [ ! -t 1 ] || [ "$NO_COLOR" = "1" ]; then
        LOG_COLORS=false
    fi

    # Create log file if it doesn't exist
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE" || return $EXIT_GENERAL_ERROR
        chmod "$FILE_PERMISSION_LOG" "$LOG_FILE" || return $EXIT_GENERAL_ERROR
    fi

    # Setup file descriptors for different log levels
    exec 3>&1  # DEBUG
    exec 4>&1  # INFO
    exec 5>&2  # WARN
    exec 6>&2  # ERROR
    exec 7>&2  # FATAL

    # Initialize log file with header
    log_write "INFO" "ServerSH Logging initialized (Version: $SERVERSH_VERSION)"
    log_write "INFO" "Log file: $LOG_FILE"
    log_write "INFO" "Log level: $LOG_LEVEL"
    log_write "INFO" "Log format: $LOG_FORMAT"

    return $EXIT_SUCCESS
}

# Write message to log file
log_write() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(timestamp)

    # Rotate log if needed
    log_rotate_if_needed

    # Write to log file based on format
    case "$LOG_FORMAT" in
        "json")
            printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
                "$timestamp" "$level" "$message" >> "$LOG_FILE"
            ;;
        "simple")
            printf '[%s] %s: %s\n' "$timestamp" "$level" "$message" >> "$LOG_FILE"
            ;;
        "detailed"|*)
            printf '[%s] [%s] [PID:%s] %s: %s\n' \
                "$timestamp" "$level" $$ "$0" "$message" >> "$LOG_FILE"
            ;;
    esac
}

# Log rotation
log_rotate_if_needed() {
    if [ ! -f "$LOG_FILE" ]; then
        return $EXIT_SUCCESS
    fi

    local file_size
    file_size=$(file_size "$LOG_FILE")

    if [ "$file_size" -ge "$LOG_MAX_SIZE" ]; then
        # Rotate logs
        for ((i = LOG_MAX_FILES - 1; i >= 1; i--)); do
            if [ -f "${LOG_FILE}.${i}" ]; then
                mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
            fi
        done

        if [ -f "$LOG_FILE" ]; then
            mv "$LOG_FILE" "${LOG_FILE}.1"
        fi

        # Create new log file
        touch "$LOG_FILE" || return $EXIT_GENERAL_ERROR
        chmod "$FILE_PERMISSION_LOG" "$LOG_FILE" || return $EXIT_GENERAL_ERROR

        log_write "INFO" "Log rotated (size: ${file_size} bytes)"
    fi
}

# Check if log level should be displayed
log_should_log() {
    local level="$1"
    local level_value

    case "$level" in
        "DEBUG") level_value=$LOG_LEVEL_DEBUG ;;
        "INFO")  level_value=$LOG_LEVEL_INFO ;;
        "WARN")  level_value=$LOG_LEVEL_WARN ;;
        "ERROR") level_value=$LOG_LEVEL_ERROR ;;
        "FATAL") level_value=$LOG_LEVEL_FATAL ;;
        *) return 1 ;;
    esac

    [ "$level_value" -ge "$LOG_LEVEL" ]
}

# Format message with color
log_format_message() {
    local level="$1"
    shift
    local message="$*"

    if [ "$LOG_COLORS" = true ]; then
        case "$level" in
            "DEBUG") colorize "$COLOR_MAGENTA" "$message" ;;
            "INFO")  colorize "$COLOR_BLUE" "$message" ;;
            "WARN")  colorize "$COLOR_YELLOW" "$message" ;;
            "ERROR") colorize "$COLOR_RED" "$message" ;;
            "FATAL") colorize "$COLOR_RED" "$message" ;;
            *) printf '%s' "$message" ;;
        esac
    else
        printf '%s' "$message"
    fi
}

# =============================================================================
# Log Level Functions
# =============================================================================

# Debug logging
log_debug() {
    if ! log_should_log "DEBUG"; then
        return $EXIT_SUCCESS
    fi

    local message="$*"
    local formatted_message
    formatted_message=$(log_format_message "DEBUG" "[DEBUG] $message")

    # Write to log file
    log_write "DEBUG" "$message"

    # Output to console if enabled
    if [ "$LOG_ENABLED" = true ]; then
        printf '%s\n' "$formatted_message" >&"$LOG_FD_DEBUG"
    fi
}

# Info logging
log_info() {
    if ! log_should_log "INFO"; then
        return $EXIT_SUCCESS
    fi

    local message="$*"
    local formatted_message
    formatted_message=$(log_format_message "INFO" "[INFO] $message")

    # Write to log file
    log_write "INFO" "$message"

    # Output to console if enabled
    if [ "$LOG_ENABLED" = true ]; then
        printf '%s\n' "$formatted_message" >&"$LOG_FD_INFO"
    fi
}

# Warning logging
log_warn() {
    if ! log_should_log "WARN"; then
        return $EXIT_SUCCESS
    fi

    local message="$*"
    local formatted_message
    formatted_message=$(log_format_message "WARN" "[WARNING] $message")

    # Write to log file
    log_write "WARN" "$message"

    # Output to console if enabled
    if [ "$LOG_ENABLED" = true ]; then
        printf '%s\n' "$formatted_message" >&"$LOG_FD_WARN"
    fi
}

# Error logging
log_error() {
    if ! log_should_log "ERROR"; then
        return $EXIT_SUCCESS
    fi

    local message="$*"
    local formatted_message
    formatted_message=$(log_format_message "ERROR" "[ERROR] $message")

    # Write to log file
    log_write "ERROR" "$message"

    # Output to console if enabled
    if [ "$LOG_ENABLED" = true ]; then
        printf '%s\n' "$formatted_message" >&"$LOG_FD_ERROR"
    fi
}

# Fatal logging
log_fatal() {
    local message="$*"
    local formatted_message
    formatted_message=$(log_format_message "FATAL" "[FATAL] $message")

    # Write to log file
    log_write "FATAL" "$message"

    # Output to console if enabled
    if [ "$LOG_ENABLED" = true ]; then
        printf '%s\n' "$formatted_message" >&"$LOG_FD_FATAL"
    fi
}

# =============================================================================
# Special Logging Functions
# =============================================================================

# Success logging
log_success() {
    local message="$*"
    local formatted_message
    formatted_message=$(log_format_message "SUCCESS" "✅ $message")

    log_write "INFO" "SUCCESS: $message"

    if [ "$LOG_ENABLED" = true ]; then
        printf '%s\n' "$formatted_message" >&"$LOG_FD_INFO"
    fi
}

# Progress logging
log_progress() {
    local current="$1"
    local total="$2"
    local description="$3"

    local percentage
    percentage=$(percentage "$current" "$total")

    local message
    message=$(printf '%s (%d/%d - %s%%)' "$description" "$current" "$total" "$percentage")

    log_debug "PROGRESS: $message"

    if [ "$LOG_ENABLED" = true ]; then
        progress_bar "$current" "$total"
        printf ' %s\r' "$description"
    fi
}

# Step logging
log_step() {
    local step="$1"
    local total="$2"
    local description="$3"

    local message
    message=$(printf '[%d/%d] %s' "$step" "$total" "$description")

    log_info "STEP: $message"

    if [ "$LOG_ENABLED" = true ]; then
        printf '\n%s %s\n' "$(colorize "$COLOR_CYAN" "📋")" "$(log_format_message "INFO" "$message")"
    fi
}

# Module logging
log_module_start() {
    local module_name="$1"
    log_info "MODULE_START: Starting module '$module_name'"
}

log_module_complete() {
    local module_name="$1"
    local duration="$2"
    log_info "MODULE_COMPLETE: Module '$module_name' completed in ${duration}s"
}

log_module_error() {
    local module_name="$1"
    local error_code="$2"
    local error_message="$3"
    log_error "MODULE_ERROR: Module '$module_name' failed with code $error_code: $error_message"
}

# =============================================================================
# Configuration Functions
# =============================================================================

# Set log level
log_set_level() {
    local level="$1"

    case "$level" in
        "debug"|"DEBUG") LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
        "info"|"INFO")   LOG_LEVEL=$LOG_LEVEL_INFO ;;
        "warn"|"WARN")   LOG_LEVEL=$LOG_LEVEL_WARN ;;
        "error"|"ERROR") LOG_LEVEL=$LOG_LEVEL_ERROR ;;
        "fatal"|"FATAL") LOG_LEVEL=$LOG_LEVEL_FATAL ;;
        *)
            log_error "Invalid log level: $level"
            return $EXIT_INVALID_ARGS
            ;;
    esac

    log_info "Log level set to: $level"
}

# Set log format
log_set_format() {
    local format="$1"

    case "$format" in
        "simple"|"detailed"|"json")
            LOG_FORMAT="$format"
            log_info "Log format set to: $format"
            ;;
        *)
            log_error "Invalid log format: $format"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

# Enable/disable logging
log_set_enabled() {
    local enabled="$1"

    case "$enabled" in
        "true"|"1"|"yes")
            LOG_ENABLED=true
            ;;
        "false"|"0"|"no")
            LOG_ENABLED=false
            ;;
        *)
            log_error "Invalid value for log enabled: $enabled"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

# Enable/disable colors
log_set_colors() {
    local colors="$1"

    case "$colors" in
        "true"|"1"|"yes")
            LOG_COLORS=true
            ;;
        "false"|"0"|"no")
            LOG_COLORS=false
            ;;
        *)
            log_error "Invalid value for log colors: $colors"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

# =============================================================================
# Log Analysis Functions
# =============================================================================

# Get log statistics
log_stats() {
    local log_file="${1:-$LOG_FILE}"
    local stats_file

    if [ ! -f "$log_file" ]; then
        log_error "Log file not found: $log_file"
        return $EXIT_CONFIG_ERROR
    fi

    stats_file=$(temp_file "log_stats")

    # Count log levels
    awk '
        BEGIN { debug=0; info=0; warn=0; error=0; fatal=0 }
        /\[DEBUG\]/ { debug++ }
        /\[INFO\]/  { info++ }
        /\[WARN\]/  { warn++ }
        /\[ERROR\]/ { error++ }
        /\[FATAL\]/ { fatal++ }
        END {
            print "DEBUG:", debug
            print "INFO:", info
            print "WARN:", warn
            print "ERROR:", error
            print "FATAL:", fatal
            print "TOTAL:", debug+info+warn+error+fatal
        }
    ' "$log_file" > "$stats_file"

    cat "$stats_file"
    rm -f "$stats_file"
}

# Search log for pattern
log_search() {
    local pattern="$1"
    local log_file="${2:-$LOG_FILE}"
    local context="${3:-0}"

    if [ ! -f "$log_file" ]; then
        log_error "Log file not found: $log_file"
        return $EXIT_CONFIG_ERROR
    fi

    if [ "$context" -gt 0 ]; then
        grep -C "$context" "$pattern" "$log_file"
    else
        grep "$pattern" "$log_file"
    fi
}

# Tail log file
log_tail() {
    local lines="${1:-50}"
    local log_file="${2:-$LOG_FILE}"

    if [ ! -f "$log_file" ]; then
        log_error "Log file not found: $log_file"
        return $EXIT_CONFIG_ERROR
    fi

    tail -n "$lines" "$log_file"
}

# =============================================================================
# Cleanup Functions
# =============================================================================

# Cleanup logging system
log_cleanup() {
    log_info "ServerSH Logging shutting down"

    # Close file descriptors
    exec 3>&-
    exec 4>&-
    exec 5>&-
    exec 6>&-
    exec 7>&-

    return $EXIT_SUCCESS
}

# Cleanup old log files
log_cleanup_old() {
    local days="${1:-30}"
    local log_dir
    log_dir=$(dirname "$LOG_FILE")

    if [ ! -d "$log_dir" ]; then
        return $EXIT_SUCCESS
    fi

    find "$log_dir" -name "*.log.*" -type f -mtime +$days -delete
    log_info "Cleaned up log files older than $days days"
}

# =============================================================================
# Legacy Functions (Backward Compatibility)
# =============================================================================

# Legacy functions for backward compatibility
debug() { log_debug "$@"; }
info() { log_info "$@"; }
warn() { log_warn "$@"; }
error() { log_error "$@"; }
fatal() { log_fatal "$@"; }
success() { log_success "$@"; }

# =============================================================================
# Signal Handlers
# =============================================================================

# Handle cleanup on exit
log_cleanup_on_exit() {
    log_cleanup
}

# Set up signal handlers
trap log_cleanup_on_exit EXIT
trap 'log_fatal "ServerSH interrupted by signal"' INT TERM

# =============================================================================
# Initialization
# =============================================================================

# Auto-initialize if sourced with parameters
if [ "${BASH_SOURCE[0]}" != "${0}" ] && [ $# -gt 0 ]; then
    log_init "$@"
fi