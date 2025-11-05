#!/bin/bash

# =============================================================================
# ServerSH State Management System
# =============================================================================

# Source dependencies
source "${SERVERSH_LIB_DIR}/constants.sh" || exit $EXIT_MISSING_DEPS
source "${SERVERSH_LIB_DIR}/utils.sh" || exit $EXIT_MISSING_DEPS
source "${SERVERSH_LIB_DIR}/logger.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Global Variables
# =============================================================================

# State file paths
declare -g STATE_FILE="${SERVERSH_STATE_FILE}"
declare -g STATE_DIR="${SERVERSH_STATE_DIR}"
declare -g STATE_LOCK_FILE="${SERVERSH_STATE_DIR}/.state.lock"

# State file permissions
declare -g FILE_PERMISSION_STATE=644

# State data structure
declare -gA STATE_DATA
declare -g STATE_LOADED=false

# Checkpoint data
declare -gA CHECKPOINTS
declare -g CURRENT_CHECKPOINT=""

# =============================================================================
# State Structure
# =============================================================================

# Default state structure
state_get_default() {
    cat << 'EOF'
{
  "version": "1.0.0",
  "created": "2024-01-01T00:00:00Z",
  "updated": "2024-01-01T00:00:00Z",
  "serversh_version": "1.0.0-alpha",
  "system": {
    "os": "unknown",
    "version": "unknown",
    "arch": "unknown",
    "hostname": "unknown",
    "kernel": "unknown"
  },
  "modules": {},
  "checkpoints": [],
  "current_step": 0,
  "total_steps": 0,
  "status": "pending",
  "errors": [],
  "metadata": {
    "install_id": "",
    "started_by": "",
    "environment": "production"
  }
}
EOF
}

# =============================================================================
# State File Operations
# =============================================================================

# Initialize state system
state_init() {
    local state_file="${1:-$STATE_FILE}"
    local force_init="${2:-false}"

    STATE_FILE="$state_file"
    STATE_DIR=$(dirname "$STATE_FILE")

    # Create state directory
    ensure_dir "$STATE_DIR" || {
        log_error "Failed to create state directory: $STATE_DIR"
        return $EXIT_STATE_ERROR
    }

    # Set proper permissions
    chmod "$DIR_PERMISSION" "$STATE_DIR" || {
        log_error "Failed to set permissions on state directory"
        return $EXIT_STATE_ERROR
    }

    # Check if state file exists and force_init is not requested
    if [ -f "$STATE_FILE" ] && [ "$force_init" != "true" ]; then
        state_load
        return $?
    fi

    # Create initial state
    log_debug "Initializing state system"

    local default_state
    default_state=$(state_get_default) || return $EXIT_STATE_ERROR

    # Update default state with current system information
    default_state=$(state_update_system_info "$default_state")

    # Generate unique install ID
    local install_id
    install_id=$(random_string 16)
    default_state=$(echo "$default_state" | jq --arg id "$install_id" '.metadata.install_id = $id')

    # Write initial state to file
    echo "$default_state" > "$STATE_FILE" || {
        log_error "Failed to create initial state file: $STATE_FILE"
        return $EXIT_STATE_ERROR
    }

    # Set proper permissions
    chmod "$FILE_PERMISSION_STATE" "$STATE_FILE" || {
        log_error "Failed to set permissions on state file"
        return $EXIT_STATE_ERROR
    }

    # Load state into memory
    state_load || return $EXIT_STATE_ERROR

    log_info "State system initialized (file: $STATE_FILE)"
    return $EXIT_SUCCESS
}

# Load state from file
state_load() {
    if [ ! -f "$STATE_FILE" ]; then
        log_error "State file not found: $STATE_FILE"
        return $EXIT_STATE_ERROR
    fi

    log_debug "Loading state from: $STATE_FILE"

    # Validate state file
    if ! state_validate_file "$STATE_FILE"; then
        log_error "Invalid state file format"
        return $EXIT_STATE_ERROR
    fi

    # Load state into global variables
    local state_content
    state_content=$(cat "$STATE_FILE") || {
        log_error "Failed to read state file"
        return $EXIT_STATE_ERROR
    }

    # Parse JSON and populate arrays (simplified approach)
    if command_exists jq; then
        # Use jq for JSON parsing
        local version
        version=$(echo "$state_content" | jq -r '.version // "unknown"')
        STATE_DATA["version"]="$version"

        local status
        status=$(echo "$state_content" | jq -r '.status // "unknown"')
        STATE_DATA["status"]="$status"

        local current_step
        current_step=$(echo "$state_content" | jq -r '.current_step // 0')
        STATE_DATA["current_step"]="$current_step"

        local total_steps
        total_steps=$(echo "$state_content" | jq -r '.total_steps // 0')
        STATE_DATA["total_steps"]="$total_steps"

        # Load checkpoints
        local checkpoints_json
        checkpoints_json=$(echo "$state_content" | jq -r '.checkpoints // []')
        CHECKPOINTS=()
        while IFS= read -r checkpoint; do
            if [ -n "$checkpoint" ] && [ "$checkpoint" != "null" ]; then
                CHECKPOINTS+=("$checkpoint")
            fi
        done <<< "$(echo "$checkpoints_json" | jq -r '.[] | @base64')"
    else
        log_warn "jq not available, using basic JSON parsing"
        # Fallback to basic grep/sed parsing
        STATE_DATA["version"]=$(grep -o '"version":"[^"]*"' "$STATE_FILE" | cut -d'"' -f4)
        STATE_DATA["status"]=$(grep -o '"status":"[^"]*"' "$STATE_FILE" | cut -d'"' -f4)
    fi

    STATE_LOADED=true
    log_debug "State loaded successfully (version: ${STATE_DATA[version]}, status: ${STATE_DATA[status]})"

    return $EXIT_SUCCESS
}

# Save state to file
state_save() {
    if [ "$STATE_LOADED" != true ]; then
        log_error "State not loaded, cannot save"
        return $EXIT_STATE_ERROR
    fi

    log_debug "Saving state to: $STATE_FILE"

    # Create backup before saving
    if [ -f "$STATE_FILE" ]; then
        backup_file "$STATE_FILE" >/dev/null || {
            log_warn "Failed to backup state file"
        }
    fi

    # Acquire lock
    state_lock || return $EXIT_LOCK_ERROR

    # Read current state
    local current_state
    current_state=$(cat "$STATE_FILE" 2>/dev/null || state_get_default)

    # Update state with current values
    current_state=$(echo "$current_state" | jq --arg version "${STATE_DATA[version]}" '.version = $version')
    current_state=$(echo "$current_state" | jq --arg status "${STATE_DATA[status]}" '.status = $status')
    current_state=$(echo "$current_state" | jq --argjson step "${STATE_DATA[current_step]}" '.current_step = $step')
    current_state=$(echo "$current_state" | jq --argjson total "${STATE_DATA[total_steps]}" '.total_steps = $total')

    # Update timestamp
    local timestamp
    timestamp=$(date -Iseconds)
    current_state=$(echo "$current_state" | jq --arg ts "$timestamp" '.updated = $ts')

    # Write state to file
    echo "$current_state" > "$STATE_FILE.tmp" || {
        state_unlock
        log_error "Failed to write state file"
        return $EXIT_STATE_ERROR
    }

    # Atomic move
    mv "$STATE_FILE.tmp" "$STATE_FILE" || {
        state_unlock
        log_error "Failed to move temporary state file"
        return $EXIT_STATE_ERROR
    }

    # Set permissions
    chmod "$FILE_PERMISSION_STATE" "$STATE_FILE" || {
        state_unlock
        log_error "Failed to set permissions on state file"
        return $EXIT_STATE_ERROR
    }

    state_unlock
    log_debug "State saved successfully"

    return $EXIT_SUCCESS
}

# Validate state file format
state_validate_file() {
    local state_file="$1"

    if [ ! -f "$state_file" ]; then
        log_error "State file does not exist: $state_file"
        return 1
    fi

    # Check file size
    local file_size
    file_size=$(file_size "$state_file")
    if [ "$file_size" -gt "$MAX_STATE_SIZE" ]; then
        log_error "State file too large: ${file_size} bytes (max: $MAX_STATE_SIZE)"
        return 1
    fi

    # Validate JSON format if jq is available
    if command_exists jq; then
        if ! jq empty "$state_file" 2>/dev/null; then
            log_error "Invalid JSON format in state file"
            return 1
        fi

        # Validate required fields
        local required_fields=("version" "status" "current_step" "total_steps")
        for field in "${required_fields[@]}"; do
            if ! jq -e ".$field" "$state_file" >/dev/null 2>&1; then
                log_error "Missing required field in state file: $field"
                return 1
            fi
        done
    fi

    return 0
}

# =============================================================================
# State Operations
# =============================================================================

# Get state value
state_get() {
    local key="$1"
    local default_value="${2:-}"

    if [ "$STATE_LOADED" != true ]; then
        log_error "State not loaded"
        return $EXIT_STATE_ERROR
    fi

    local value="${STATE_DATA[$key]}"
    if [ -z "$value" ]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

# Set state value
state_set() {
    local key="$1"
    local value="$2"

    if [ "$STATE_LOADED" != true ]; then
        log_error "State not loaded"
        return $EXIT_STATE_ERROR
    fi

    log_debug "Setting state: $key = $value"
    STATE_DATA["$key"]="$value"

    # Auto-save
    state_save || return $EXIT_STATE_ERROR

    return $EXIT_SUCCESS
}

# Update system information in state
state_update_system_info() {
    local state_json="$1"

    local os
    os=$(get_system_info "os")
    local version
    version=$(get_system_info "version")
    local arch
    arch=$(get_system_info "arch")
    local hostname
    hostname=$(get_system_info "hostname")
    local kernel
    kernel=$(get_system_info "kernel")

    state_json=$(echo "$state_json" | jq --arg os "$os" '.system.os = $os')
    state_json=$(echo "$state_json" | jq --arg ver "$version" '.system.version = $ver')
    state_json=$(echo "$state_json" | jq --arg arch "$arch" '.system.arch = $arch')
    state_json=$(echo "$state_json" | jq --arg hostname "$hostname" '.system.hostname = $hostname')
    state_json=$(echo "$state_json" | jq --arg kernel "$kernel" '.system.kernel = $kernel')

    echo "$state_json"
}

# =============================================================================
# Module State Management
# =============================================================================

# Set module state
state_set_module_state() {
    local module_name="$1"
    local module_state="$2"
    local additional_data="${3:-}"

    log_debug "Setting module state: $module_name = $module_state"

    if ! command_exists jq; then
        log_error "jq required for module state management"
        return $EXIT_MISSING_DEPS
    fi

    state_lock || return $EXIT_LOCK_ERROR

    # Read current state
    local current_state
    current_state=$(cat "$STATE_FILE")

    # Update module state
    local timestamp
    timestamp=$(date -Iseconds)

    if [ -n "$additional_data" ]; then
        current_state=$(echo "$current_state" | jq --arg name "$module_name" --arg state "$module_state" --arg ts "$timestamp" --argjson data "$additional_data" '
            .modules[$name] = {
                state: $state,
                updated: $ts,
                data: $data
            }
        ')
    else
        current_state=$(echo "$current_state" | jq --arg name "$module_name" --arg state "$module_state" --arg ts "$timestamp" '
            .modules[$name] = {
                state: $state,
                updated: $ts
            }
        ')
    fi

    # Write updated state
    echo "$current_state" > "$STATE_FILE"
    state_unlock

    log_debug "Module state updated: $module_name -> $module_state"
    return $EXIT_SUCCESS
}

# Get module state
state_get_module_state() {
    local module_name="$1"

    if ! command_exists jq; then
        log_error "jq required for module state management"
        return $EXIT_MISSING_DEPS
    fi

    local state
    state=$(jq -r ".modules[\"$module_name\"].state // \"unknown\"" "$STATE_FILE")
    echo "$state"
}

# List all module states
state_list_modules() {
    if ! command_exists jq; then
        log_error "jq required for module state management"
        return $EXIT_MISSING_DEPS
    fi

    jq -r '.modules | to_entries[] | "\(.key): \(.value.state)"' "$STATE_FILE"
}

# =============================================================================
# Checkpoint Management
# =============================================================================

# Create checkpoint
state_create_checkpoint() {
    local description="$1"
    local checkpoint_type="${2:-manual}"
    echo "DEBUG: state_create_checkpoint called with: $description, $checkpoint_type" >&2

    if ! command_exists jq; then
        echo "DEBUG: jq command not found, returning error" >&2
        log_error "jq required for checkpoint management"
        return $EXIT_MISSING_DEPS
    fi
    echo "DEBUG: jq command found, proceeding" >&2

    local checkpoint_id
    checkpoint_id="checkpoint_$(date +%Y%m%d_%H%M%S)_$(random_string 8)"

    log_info "Creating checkpoint: $checkpoint_id - $description"

    state_lock || return $EXIT_LOCK_ERROR

    # Read current state
    local current_state
    current_state=$(cat "$STATE_FILE")

    # Create checkpoint data
    local timestamp
    timestamp=$(date -Iseconds)
    local modules_snapshot
    modules_snapshot=$(echo "$current_state" | jq '.modules')

    local checkpoint_data
    checkpoint_data=$(cat << EOF
{
  "id": "$checkpoint_id",
  "type": "$checkpoint_type",
  "description": "$description",
  "timestamp": "$timestamp",
  "modules_snapshot": $modules_snapshot,
  "state_snapshot": $current_state
}
EOF
)

    # Add checkpoint to state
    current_state=$(echo "$current_state" | jq --argjson checkpoint "$checkpoint_data" '.checkpoints += [$checkpoint]')

    # Set as current checkpoint
    CURRENT_CHECKPOINT="$checkpoint_id"
    current_state=$(echo "$current_state" | jq --arg id "$checkpoint_id" '.current_checkpoint = $id')

    # Write updated state
    echo "$current_state" > "$STATE_FILE"
    state_unlock

    log_success "Checkpoint created: $checkpoint_id"
    return $EXIT_SUCCESS
}

# List checkpoints
state_list_checkpoints() {
    if ! command_exists jq; then
        log_error "jq required for checkpoint management"
        return $EXIT_MISSING_DEPS
    fi

    jq -r '.checkpoints[] | "\(.id): \(.description) (\(.timestamp))"' "$STATE_FILE"
}

# Restore checkpoint
state_restore_checkpoint() {
    local checkpoint_id="$1"

    if ! command_exists jq; then
        log_error "jq required for checkpoint management"
        return $EXIT_MISSING_DEPS
    fi

    log_info "Restoring checkpoint: $checkpoint_id"

    # Get checkpoint data
    local checkpoint_data
    checkpoint_data=$(jq -r ".checkpoints[] | select(.id == \"$checkpoint_id\")" "$STATE_FILE")

    if [ -z "$checkpoint_data" ] || [ "$checkpoint_data" = "null" ]; then
        log_error "Checkpoint not found: $checkpoint_id"
        return $EXIT_STATE_ERROR
    fi

    state_lock || return $EXIT_LOCK_ERROR

    # Extract state snapshot
    local state_snapshot
    state_snapshot=$(echo "$checkpoint_data" | jq '.state_snapshot')

    # Write restored state
    echo "$state_snapshot" > "$STATE_FILE"

    state_unlock

    # Reload state
    state_load || return $EXIT_STATE_ERROR

    log_success "Checkpoint restored: $checkpoint_id"
    return $EXIT_SUCCESS
}

# =============================================================================
# Lock Management
# =============================================================================

# Acquire state lock
state_lock() {
    local timeout="${1:-30}"
    local count=0

    while [ $count -lt "$timeout" ]; do
        if (set -C; echo $$ > "$STATE_LOCK_FILE") 2>/dev/null; then
            return 0
        fi

        # Check if lock process is still running
        if [ -f "$STATE_LOCK_FILE" ]; then
            local lock_pid
            lock_pid=$(cat "$STATE_LOCK_FILE" 2>/dev/null)
            if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
                # Lock process is dead, remove stale lock
                rm -f "$STATE_LOCK_FILE"
                continue
            fi
        fi

        sleep 1
        ((count++))
    done

    log_error "Failed to acquire state lock after ${timeout} seconds"
    return $EXIT_LOCK_ERROR
}

# Release state lock
state_unlock() {
    if [ -f "$STATE_LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$STATE_LOCK_FILE" 2>/dev/null)
        if [ "$lock_pid" = "$$" ]; then
            rm -f "$STATE_LOCK_FILE"
            return 0
        fi
    fi

    return 0
}

# =============================================================================
# Utility Functions
# =============================================================================

# Get state summary
state_summary() {
    if [ "$STATE_LOADED" != true ]; then
        echo "State not loaded"
        return $EXIT_STATE_ERROR
    fi

    echo "ServerSH State Summary:"
    echo "  File: $STATE_FILE"
    echo "  Version: ${STATE_DATA[version]}"
    echo "  Status: ${STATE_DATA[status]}"
    echo "  Progress: ${STATE_DATA[current_step]}/${STATE_DATA[total_steps]}"
    echo "  Modules: $(state_list_modules | wc -l)"
    echo "  Checkpoints: $(state_list_checkpoints | wc -l)"
}

# Reset state
state_reset() {
    log_warn "Resetting state system"

    if [ -f "$STATE_FILE" ]; then
        backup_file "$STATE_FILE" >/dev/null
        rm -f "$STATE_FILE"
    fi

    # Clear in-memory state
    STATE_DATA=()
    CHECKPOINTS=()
    STATE_LOADED=false
    CURRENT_CHECKPOINT=""

    # Reinitialize
    state_init
}

# Export state to JSON
state_export() {
    local output_file="${1:-/dev/stdout}"

    if [ ! -f "$STATE_FILE" ]; then
        log_error "State file not found"
        return $EXIT_STATE_ERROR
    fi

    cat "$STATE_FILE" > "$output_file"
}

# =============================================================================
# Cleanup Functions
# =============================================================================

# Cleanup old state files
state_cleanup() {
    local days="${1:-7}"

    log_info "Cleaning up state files older than $days days"

    find "$STATE_DIR" -name "*.backup.*" -type f -mtime +$days -delete
    find "$STATE_DIR" -name "*.tmp" -type f -mtime +1 -delete
}

# =============================================================================
# Initialization
# =============================================================================

# Auto-initialize if sourced with parameters
if [ "${BASH_SOURCE[0]}" != "${0}" ] && [ $# -gt 0 ]; then
    state_init "$@"
fi