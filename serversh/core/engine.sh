#!/bin/bash

# =============================================================================
# ServerSH Core Engine
# =============================================================================

# Source dependencies
source "${SERVERSH_LIB_DIR}/constants.sh" || exit $EXIT_MISSING_DEPS
source "${SERVERSH_LIB_DIR}/utils.sh" || exit $EXIT_MISSING_DEPS
source "${SERVERSH_LIB_DIR}/logger.sh" || exit $EXIT_MISSING_DEPS
source "${SERVERSH_LIB_DIR}/state.sh" || exit $EXIT_MISSING_DEPS
source "${SERVERSH_LIB_DIR}/config.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Global Variables
# =============================================================================

# Engine state
declare -g ENGINE_INITIALIZED=false
declare -g ENGINE_RUNNING=false
declare -g ENGINE_PAUSED=false

# Module registry
declare -ga REGISTERED_MODULES=()
declare -gA MODULE_METADATA
declare -gA MODULE_DEPENDENCIES
declare -gA MODULE_EXECUTION_ORDER

# Execution tracking
declare -g CURRENT_MODULE=""
declare -g MODULE_START_TIME=0
declare -gA MODULE_TIMERS

# Parallel execution
declare -g PARALLEL_ENABLED=false
declare -g PARALLEL_MAX_JOBS=1
declare -ga ACTIVE_JOBS=()

# =============================================================================
# Module Interface Specification
# =============================================================================

# Every module must implement these required functions:
# module_get_name()          - Returns module name
# module_get_version()       - Returns module version
# module_get_description()   - Returns module description
# module_get_category()      - Returns module category
# module_get_dependencies()  - Returns list of dependencies
# module_validate_config()   - Validates module configuration
# module_install()          - Main installation function
# module_verify()           - Verifies installation success
# module_rollback()         - Rolls back module changes

# Optional functions:
# module_pre_install()       - Pre-installation checks
# module_post_install()      - Post-installation tasks
# module_cleanup()           - Cleanup on failure
# module_get_status()        - Returns module status
# module_get_logs()          - Returns module logs

# =============================================================================
# Module Registration System
# =============================================================================

# Register a module with the engine
engine_register_module() {
    local module_path="$1"
    local module_name
    module_name=$(basename "$module_path" .sh)

    log_info "Registering module: $module_name (path: $module_path)"

    # Validate module file
    if [ ! -f "$module_path" ]; then
        log_error "Module file not found: $module_path"
        return $EXIT_MODULE_ERROR
    fi

    # Validate module file structure without sourcing (to avoid dependency issues)
    log_info "Validating module file structure: $module_name"

    # Check if module has basic structure by looking for required function declarations
    if ! grep -q "module_get_name" "$module_path" 2>/dev/null; then
        log_error "Module $module_name missing required function: module_get_name"
        return $EXIT_MODULE_ERROR
    fi

    if ! grep -q "module_get_version" "$module_path" 2>/dev/null; then
        log_error "Module $module_name missing required function: module_get_version"
        return $EXIT_MODULE_ERROR
    fi

    if ! grep -q "module_get_description" "$module_path" 2>/dev/null; then
        log_error "Module $module_name missing required function: module_get_description"
        return $EXIT_MODULE_ERROR
    fi

    if ! grep -q "module_install" "$module_path" 2>/dev/null; then
        log_error "Module $module_name missing required function: module_install"
        return $EXIT_MODULE_ERROR
    fi

    if ! grep -q "module_verify" "$module_path" 2>/dev/null; then
        log_error "Module $module_name missing required function: module_verify"
        return $EXIT_MODULE_ERROR
    fi

    log_info "Module file structure validation passed: $module_name"

    # Extract module metadata from file header comments
    local module_version
    module_version=$(grep "^# Version:" "$module_path" | cut -d' ' -f3- | head -1)
    module_version=${module_version:-"unknown"}

    local module_description
    module_description=$(grep "^# Description:" "$module_path" | cut -d' ' -f3- | head -1)
    module_description=${module_description:-"No description"}

    local module_category
    module_category=$(grep "^# Category:" "$module_path" | cut -d' ' -f3- | head -1)
    module_category=${module_category:-"custom"}

    # Extract dependencies from function
    local module_dependencies=""
    if grep -q "module_get_dependencies" "$module_path"; then
        # For now, we'll get dependencies when the module is actually sourced during execution
        module_dependencies=""
    fi

    # Store module metadata
    MODULE_METADATA["$module_name"]="version:$module_version|description:$module_description|category:$module_category|path:$module_path"
    MODULE_DEPENDENCIES["$module_name"]="$module_dependencies"

    # Add to registered modules
    REGISTERED_MODULES+=("$module_name")

    log_success "Module registered: $module_name (v$module_version)"
    return $EXIT_SUCCESS
}

# Auto-register modules from directory
engine_register_modules_from_dir() {
    local modules_dir="$1"

    if [ ! -d "$modules_dir" ]; then
        log_error "Modules directory not found: $modules_dir"
        return $EXIT_CONFIG_ERROR
    fi

    log_info "Registering modules from: $modules_dir"

    local modules_found=0
    local modules_registered=0

    # Find all .sh files in subdirectories
    log_info "Searching for module files in: $modules_dir"
    while IFS= read -r -d '' module_file; do
        ((modules_found++))
        log_info "Found module file: $(basename "$module_file")"

        if engine_register_module "$module_file"; then
            ((modules_registered++))
            log_info "Successfully registered: $(basename "$module_file")"
        else
            log_warn "Failed to register module: $(basename "$module_file")"
        fi
    done < <(find "$modules_dir" -name "*.sh" -type f -print0)

    log_info "Modules registration complete: $modules_registered/$modules_found registered"
    return $EXIT_SUCCESS
}

# List registered modules
engine_list_modules() {
    log_info "Registered modules (${#REGISTERED_MODULES[@]}):"

    for module_name in "${REGISTERED_MODULES[@]}"; do
        local metadata="${MODULE_METADATA[$module_name]}"
        local version="${metadata#*version:}"
        version="${version%%|*}"
        local description="${metadata#*description:}"
        description="${description%%|*}"
        local category="${metadata#*category:}"
        category="${category%%|*}"

        printf "  %-20s v%-10s %s (%s)\n" "$module_name" "$version" "$description" "$category"
    done
}

# =============================================================================
# Dependency Resolution
# =============================================================================

# Resolve module dependencies and create execution order
engine_resolve_dependencies() {
    local module_list=("$@")
    local resolved_modules=()
    local visited_modules=()

    if [ ${#module_list[@]} -eq 0 ]; then
        module_list=("${REGISTERED_MODULES[@]}")
    fi

    log_debug "Resolving dependencies for modules: ${module_list[*]}"

    # Clear execution order
    MODULE_EXECUTION_ORDER=()

    # Recursive dependency resolution
    resolve_dependencies_recursive() {
        local module_name="$1"
        local dependencies

        # Skip if already visited
        if array_contains "$module_name" "${visited_modules[@]}"; then
            log_debug "Module already visited: $module_name"
            return $EXIT_SUCCESS
        fi

        # Mark as visited
        visited_modules+=("$module_name")

        # Get module dependencies
        dependencies="${MODULE_DEPENDENCIES[$module_name]}"

        if [ -n "$dependencies" ]; then
            log_debug "Module $module_name depends on: $dependencies"

            # Resolve dependencies first
            local dependency_list
            readarray -t dependency_list <<< "$dependencies"

            for dependency in "${dependency_list[@]}"; do
                dependency=$(trim "$dependency")

                # Check if dependency is registered
                if ! array_contains "$dependency" "${REGISTERED_MODULES[@]}"; then
                    log_error "Dependency not found: $dependency (required by $module_name)"
                    return $EXIT_MODULE_ERROR
                fi

                # Recursively resolve dependency
                resolve_dependencies_recursive "$dependency" || return $EXIT_MODULE_ERROR
            done
        fi

        # Add module to execution order if not already added
        if ! array_contains "$module_name" "${resolved_modules[@]}"; then
            resolved_modules+=("$module_name")
            MODULE_EXECUTION_ORDER+=("$module_name")
            log_debug "Added to execution order: $module_name"
        fi

        return $EXIT_SUCCESS
    }

    # Resolve dependencies for all modules
    for module_name in "${module_list[@]}"; do
        if ! array_contains "$module_name" "${REGISTERED_MODULES[@]}"; then
            log_error "Module not registered: $module_name"
            return $EXIT_MODULE_ERROR
        fi

        resolve_dependencies_recursive "$module_name" || return $EXIT_MODULE_ERROR
    done

    log_success "Dependency resolution complete (${#MODULE_EXECUTION_ORDER[@]} modules)"
    log_debug "Execution order: ${MODULE_EXECUTION_ORDER[*]}"

    return $EXIT_SUCCESS
}

# =============================================================================
# Module Execution
# =============================================================================

# Execute a single module
engine_execute_module() {
    local module_name="$1"
    local module_start_time
    module_start_time=$(unix_timestamp)

    log_info "Executing module: $module_name"
    log_module_start "$module_name"

    # Update state
    state_set_module_state "$module_name" "running"
    CURRENT_MODULE="$module_name"
    MODULE_START_TIME="$module_start_time"

    # Source module file
    local module_path
    module_path="${MODULE_METADATA[$module_name]#*path:}"
    module_path="${module_path%%|*}"

    if ! source "$module_path"; then
        log_module_error "$module_name" "$EXIT_MODULE_ERROR" "Failed to source module file"
        state_set_module_state "$module_name" "failed"
        return $EXIT_MODULE_ERROR
    fi

    # Validate configuration
    log_debug "Validating module configuration: $module_name"
    if ! module_validate_config 2>/dev/null; then
        log_module_error "$module_name" "$EXIT_CONFIG_ERROR" "Module configuration validation failed"
        state_set_module_state "$module_name" "failed"
        return $EXIT_CONFIG_ERROR
    fi

    # Pre-installation hook
    log_debug "Running pre-installation hook: $module_name"
    if declare -f module_pre_install >/dev/null; then
        if ! module_pre_install 2>/dev/null; then
            log_module_error "$module_name" "$EXIT_MODULE_ERROR" "Pre-installation hook failed"
            state_set_module_state "$module_name" "failed"
            return $EXIT_MODULE_ERROR
        fi
    fi

    # Main installation
    log_debug "Running main installation: $module_name"
    if ! module_install 2>/dev/null; then
        log_module_error "$module_name" "$EXIT_MODULE_ERROR" "Module installation failed"
        state_set_module_state "$module_name" "failed"

        # Cleanup on failure
        if declare -f module_cleanup >/dev/null; then
            log_debug "Running cleanup hook: $module_name"
            module_cleanup 2>/dev/null || true
        fi

        return $EXIT_MODULE_ERROR
    fi

    # Post-installation hook
    log_debug "Running post-installation hook: $module_name"
    if declare -f module_post_install >/dev/null; then
        if ! module_post_install 2>/dev/null; then
            log_module_error "$module_name" "$EXIT_MODULE_ERROR" "Post-installation hook failed"
            state_set_module_state "$module_name" "failed"
            return $EXIT_MODULE_ERROR
        fi
    fi

    # Verify installation
    log_debug "Verifying installation: $module_name"
    if ! module_verify 2>/dev/null; then
        log_module_error "$module_name" "$EXIT_MODULE_ERROR" "Module verification failed"
        state_set_module_state "$module_name" "failed"
        return $EXIT_MODULE_ERROR
    fi

    # Calculate execution time
    local module_end_time
    module_end_time=$(unix_timestamp)
    local module_duration=$((module_end_time - module_start_time))
    MODULE_TIMERS["$module_name"]=$module_duration

    # Update state
    state_set_module_state "$module_name" "completed"
    log_module_complete "$module_name" "$module_duration"
    log_success "Module completed: $module_name (${module_duration}s)"

    CURRENT_MODULE=""
    return $EXIT_SUCCESS
}

# Execute modules in order
engine_execute_modules() {
    local module_list=("$@")
    local total_modules
    total_modules=${#module_list[@]}

    if [ $total_modules -eq 0 ]; then
        module_list=("${MODULE_EXECUTION_ORDER[@]}")
        total_modules=${#MODULE_EXECUTION_ORDER[@]}
    fi

    if [ $total_modules -eq 0 ]; then
        log_warn "No modules to execute"
        return $EXIT_SUCCESS
    fi

    log_info "Starting module execution ($total_modules modules)"

    # Update state
    state_set "current_step" 0
    state_set "total_steps" "$total_modules"

    local completed_modules=0
    local failed_modules=0

    for i in "${!module_list[@]}"; do
        local module_name="${module_list[i]}"
        local step=$((i + 1))

        log_step "$step" "$total_modules" "Executing module: $module_name"

        if engine_execute_module "$module_name"; then
            ((completed_modules++))
        else
            ((failed_modules++))

            # Check fail_fast setting
            local fail_fast
            fail_fast=$(config_get "modules.fail_fast" "true")
            if [ "$fail_fast" = "true" ]; then
                log_error "Module execution failed, stopping due to fail_fast=true"
                break
            fi
        fi

        # Update progress
        state_set "current_step" "$step"
    done

    log_info "Module execution complete: $completed_modules succeeded, $failed_modules failed"

    if [ $failed_modules -gt 0 ]; then
        return $EXIT_MODULE_ERROR
    fi

    return $EXIT_SUCCESS
}

# =============================================================================
# Parallel Execution
# =============================================================================

# Enable parallel execution
engine_enable_parallel() {
    local max_jobs="${1:-4}"

    if ! command_exists "xargs"; then
        log_warn "xargs not available, parallel execution disabled"
        return $EXIT_MISSING_DEPS
    fi

    PARALLEL_ENABLED=true
    PARALLEL_MAX_JOBS="$max_jobs"

    log_info "Parallel execution enabled (max jobs: $max_jobs)"
}

# Execute modules in parallel (basic implementation)
engine_execute_parallel() {
    local module_list=("$@")

    if [ "$PARALLEL_ENABLED" != "true" ]; then
        log_debug "Parallel execution disabled, using sequential execution"
        engine_execute_modules "${module_list[@]}"
        return $?
    fi

    log_info "Starting parallel module execution (${#module_list[@]} modules)"

    # This is a simplified parallel execution
    # In a full implementation, you would use proper job control
    for module_name in "${module_list[@]}"; do
        (
            engine_execute_module "$module_name"
        ) &

        # Limit concurrent jobs
        while [ "$(jobs -r -p | wc -l)" -ge "$PARALLEL_MAX_JOBS" ]; do
            sleep 1
        done
    done

    # Wait for all jobs to complete
    wait

    log_info "Parallel execution complete"
    return $EXIT_SUCCESS
}

# =============================================================================
# Checkpoint Management
# =============================================================================

# Create execution checkpoint
engine_create_checkpoint() {
    local description="$1"

    if [ "$STATE_LOADED" != true ]; then
        log_error "State system not initialized"
        return $EXIT_STATE_ERROR
    fi

    state_create_checkpoint "$description" "execution"
    return $EXIT_SUCCESS
}

# Rollback to checkpoint
engine_rollback_to_checkpoint() {
    local checkpoint_id="$1"

    if [ "$STATE_LOADED" != true ]; then
        log_error "State system not initialized"
        return $EXIT_STATE_ERROR
    fi

    log_warn "Rolling back to checkpoint: $checkpoint_id"
    state_restore_checkpoint "$checkpoint_id"
    return $EXIT_SUCCESS
}

# =============================================================================
# Engine Lifecycle
# =============================================================================

# Initialize the engine
engine_init() {
    local config_file="${1:-$SERVERSH_CONFIG_FILE}"
    local state_file="${2:-$SERVERSH_STATE_FILE}"

    if [ "$ENGINE_INITIALIZED" = true ]; then
        log_warn "Engine already initialized"
        return $EXIT_SUCCESS
    fi

    log_info "Initializing ServerSH Engine (v$SERVERSH_VERSION)"

    # Validate system requirements
    if ! validate_required_commands; then
        log_error "System requirements not met"
        return $EXIT_MISSING_DEPS
    fi

    # Initialize logging
    log_init || return $EXIT_GENERAL_ERROR

    # Initialize configuration
    config_init "$config_file" || return $EXIT_CONFIG_ERROR

    # Initialize state
    state_init "$state_file" || return $EXIT_STATE_ERROR

    # Configure logging from config
    local log_level
    log_level=$(config_get "serversh.log_level" "info")
    log_set_level "$log_level"

    # Configure parallel execution
    local parallel_jobs
    parallel_jobs=$(config_get "serversh.parallel_jobs" "4")
    if [ "$parallel_jobs" -gt 1 ]; then
        engine_enable_parallel "$parallel_jobs"
    fi

    # Auto-register modules if modules directory exists
    if [ -d "$SERVERSH_MODULES_DIR" ]; then
        log_info "Found modules directory, registering modules..."
        if ! engine_register_modules_from_dir "$SERVERSH_MODULES_DIR"; then
            log_error "Failed to register modules from: $SERVERSH_MODULES_DIR"
            return $EXIT_MODULE_ERROR
        fi
        log_info "Module registration completed"
    else
        log_warn "Modules directory not found: $SERVERSH_MODULES_DIR"
    fi

    ENGINE_INITIALIZED=true
    log_success "ServerSH Engine initialized successfully"

    return $EXIT_SUCCESS
}

# Start the engine with specified modules
engine_start() {
    echo "DEBUG: engine_start function called with args: $*" >&2
    local module_list=("$@")

    if [ "$ENGINE_INITIALIZED" != true ]; then
        log_error "Engine not initialized"
        return $EXIT_GENERAL_ERROR
    fi

    if [ "$ENGINE_RUNNING" = true ]; then
        log_warn "Engine already running"
        return $EXIT_SUCCESS
    fi

    log_info "Starting ServerSH Engine"

    # Update state
    state_set "status" "running"
    ENGINE_RUNNING=true

    # Create initial checkpoint
    engine_create_checkpoint "Engine start"

    # Validate configuration
    log_info "Validating configuration..."
    if ! config_validate_values; then
        log_error "Configuration validation failed"
        state_set "status" "failed"
        ENGINE_RUNNING=false
        return $EXIT_CONFIG_ERROR
    fi
    log_info "Configuration validation passed"

    # Resolve dependencies
    if [ ${#module_list[@]} -gt 0 ]; then
        # Filter to only registered modules
        local filtered_modules=()
        for module_name in "${module_list[@]}"; do
            if array_contains "$module_name" "${REGISTERED_MODULES[@]}"; then
                filtered_modules+=("$module_name")
            else
                log_warn "Module not registered, skipping: $module_name"
            fi
        done
        module_list=("${filtered_modules[@]}")
    fi

    # Resolve execution order
    log_info "Resolving dependencies for modules: ${module_list[*]}"
    if ! engine_resolve_dependencies "${module_list[@]}"; then
        log_error "Dependency resolution failed"
        state_set "status" "failed"
        ENGINE_RUNNING=false
        return $EXIT_MODULE_ERROR
    fi
    log_info "Dependency resolution passed"

    # Execute modules
    local execution_result=$EXIT_SUCCESS
    log_info "Starting module execution (parallel: $PARALLEL_ENABLED)..."
    if [ "$PARALLEL_ENABLED" = true ]; then
        log_info "Executing modules in parallel: ${MODULE_EXECUTION_ORDER[*]}"
        engine_execute_parallel "${MODULE_EXECUTION_ORDER[@]}"
        execution_result=$?
    else
        log_info "Executing modules sequentially: ${MODULE_EXECUTION_ORDER[*]}"
        engine_execute_modules "${MODULE_EXECUTION_ORDER[@]}"
        execution_result=$?
    fi
    log_info "Module execution completed with result: $execution_result"

    # Update final state
    if [ $execution_result -eq $EXIT_SUCCESS ]; then
        state_set "status" "completed"
        log_success "ServerSH Engine completed successfully"
    else
        state_set "status" "failed"
        log_error "ServerSH Engine failed with exit code: $execution_result"
    fi

    # Create final checkpoint
    engine_create_checkpoint "Engine end"

    ENGINE_RUNNING=false
    return $execution_result
}

# Stop the engine
engine_stop() {
    if [ "$ENGINE_RUNNING" != true ]; then
        log_warn "Engine not running"
        return $EXIT_SUCCESS
    fi

    log_info "Stopping ServerSH Engine"

    # Kill any active jobs
    if [ "${#ACTIVE_JOBS[@]}" -gt 0 ]; then
        log_info "Terminating active jobs: ${#ACTIVE_JOBS[@]}"
        for job_pid in "${ACTIVE_JOBS[@]}"; do
            kill_process "$job_pid" 5
        done
        ACTIVE_JOBS=()
    fi

    state_set "status" "stopped"
    ENGINE_RUNNING=false
    ENGINE_PAUSED=false

    log_info "ServerSH Engine stopped"
    return $EXIT_SUCCESS
}

# Pause the engine
engine_pause() {
    if [ "$ENGINE_RUNNING" != true ]; then
        log_warn "Engine not running"
        return $EXIT_SUCCESS
    fi

    if [ "$ENGINE_PAUSED" = true ]; then
        log_warn "Engine already paused"
        return $EXIT_SUCCESS
    fi

    log_info "Pausing ServerSH Engine"

    # Create checkpoint before pause
    engine_create_checkpoint "Engine paused"

    state_set "status" "paused"
    ENGINE_PAUSED=true

    log_info "ServerSH Engine paused"
    return $EXIT_SUCCESS
}

# Resume the engine
engine_resume() {
    if [ "$ENGINE_RUNNING" != true ]; then
        log_error "Engine not running, cannot resume"
        return $EXIT_GENERAL_ERROR
    fi

    if [ "$ENGINE_PAUSED" != true ]; then
        log_warn "Engine not paused"
        return $EXIT_SUCCESS
    fi

    log_info "Resuming ServerSH Engine"

    state_set "status" "running"
    ENGINE_PAUSED=false

    log_info "ServerSH Engine resumed"
    return $EXIT_SUCCESS
}

# =============================================================================
# Engine Status and Information
# =============================================================================

# Get engine status
engine_status() {
    echo "ServerSH Engine Status:"
    echo "  Version: $SERVERSH_VERSION"
    echo "  Initialized: $ENGINE_INITIALIZED"
    echo "  Running: $ENGINE_RUNNING"
    echo "  Paused: $ENGINE_PAUSED"
    echo "  Parallel: $PARALLEL_ENABLED"
    echo "  Max Jobs: $PARALLEL_MAX_JOBS"
    echo "  Registered Modules: ${#REGISTERED_MODULES[@]}"
    echo "  Execution Order: ${#MODULE_EXECUTION_ORDER[@]}"

    if [ "$ENGINE_RUNNING" = true ]; then
        echo "  Current Module: $CURRENT_MODULE"
    fi

    if [ "$STATE_LOADED" = true ]; then
        echo ""
        state_summary
    fi

    if [ "$CONFIG_LOADED" = true ]; then
        echo ""
        config_summary
    fi
}

# Get execution statistics
engine_stats() {
    echo "ServerSH Engine Statistics:"
    echo "  Total Modules: ${#REGISTERED_MODULES[@]}"
    echo "  Execution Order: ${#MODULE_EXECUTION_ORDER[@]}"

    if [ ${#MODULE_TIMERS[@]} -gt 0 ]; then
        echo ""
        echo "Module Execution Times:"
        for module_name in "${!MODULE_TIMERS[@]}"; do
            local duration="${MODULE_TIMERS[$module_name]}"
            printf "  %-20s: %ds\n" "$module_name" "$duration"
        done
    fi
}

# =============================================================================
# Cleanup
# =============================================================================

# Cleanup engine resources
engine_cleanup() {
    log_info "Cleaning up ServerSH Engine"

    # Stop engine if running
    if [ "$ENGINE_RUNNING" = true ]; then
        engine_stop
    fi

    # Clear module data
    REGISTERED_MODULES=()
    MODULE_METADATA=()
    MODULE_DEPENDENCIES=()
    MODULE_EXECUTION_ORDER=()
    MODULE_TIMERS=()

    # Reset state
    ENGINE_INITIALIZED=false
    ENGINE_RUNNING=false
    ENGINE_PAUSED=false
    CURRENT_MODULE=""

    log_info "ServerSH Engine cleanup complete"
    return $EXIT_SUCCESS
}

# =============================================================================
# Signal Handlers
# =============================================================================

# Handle interrupt signals
engine_signal_handler() {
    local signal="$1"

    log_warn "Received signal: $signal"

    if [ "$ENGINE_RUNNING" = true ]; then
        log_info "Gracefully stopping engine..."
        engine_stop
    fi

    exit $EXIT_GENERAL_ERROR
}

# Set up signal handlers
trap 'engine_signal_handler SIGINT' INT
trap 'engine_signal_handler SIGTERM' TERM
trap 'engine_signal_handler SIGHUP' HUP

# =============================================================================
# Auto-initialization
# =============================================================================

# Initialize engine if sourced with parameters
if [ "${BASH_SOURCE[0]}" != "${0}" ] && [ $# -gt 0 ]; then
    engine_init "$@"
fi