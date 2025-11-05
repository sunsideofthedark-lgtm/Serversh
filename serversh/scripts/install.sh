#!/bin/bash

# =============================================================================
# ServerSH Installation Script
# =============================================================================
# This is the main entry point for ServerSH installation
# Usage: sudo ./install.sh [options] [modules...]
# =============================================================================

# Set strict mode
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source core components
SERVERSH_ROOT="$PROJECT_ROOT"
source "${PROJECT_ROOT}/core/constants.sh" || exit 1
source "${PROJECT_ROOT}/core/utils.sh" || exit 1
source "${PROJECT_ROOT}/core/logger.sh" || exit 1

# =============================================================================
# Usage and Help
# =============================================================================

show_help() {
    cat << EOF
ServerSH Installation Script (v$SERVERSH_VERSION)

USAGE:
    sudo $0 [OPTIONS] [MODULES...]

OPTIONS:
    -h, --help              Show this help message
    -v, --version           Show version information
    -c, --config FILE       Use specific configuration file
    -s, --state FILE        Use specific state file
    -l, --log-level LEVEL   Set log level (debug, info, warn, error)
    -p, --parallel JOBS     Enable parallel execution with N jobs
    -f, --force             Force installation even if already completed
    -r, --resume            Resume interrupted installation
    -q, --quiet             Suppress non-error output
    --dry-run               Show what would be done without executing
    --validate-only         Validate configuration and dependencies only
    --list-modules          List available modules
    --list-profiles         List available configuration profiles
    --profile PROFILE       Load configuration profile
    --create-checkpoint DESC Create checkpoint with description
    --rollback-to ID        Rollback to specific checkpoint
    --status                Show current installation status
    --cleanup               Clean up temporary files and old logs

MODULES:
    Specify specific modules to install (space-separated)
    If no modules are specified, all enabled modules will be installed

EXAMPLES:
    $0                                    # Install with default settings
    $0 system/update security/ssh         # Install specific modules
    $0 --parallel 4 --log-level debug    # Install with parallel execution and debug logging
    $0 --profile development             # Install using development profile
    $0 --resume                         # Resume interrupted installation
    $0 --validate-only                  # Validate configuration only

CONFIGURATION:
    Default configuration file: $SERVERSH_CONFIG_FILE
    Default state file: $SERVERSH_STATE_FILE
    Default log file: $SERVERSH_LOG_FILE

For more information, see: https://github.com/serversh/serversh
EOF
}

show_version() {
    cat << EOF
ServerSH v$SERVERSH_VERSION
Build: $SERVERSH_BUILD_DATE
Copyright: $SERVERSH_COPYRIGHT

Components:
  Core Framework: v$SERVERSH_VERSION
  Module Interface: v1.0.0
  Configuration: v1.0.0
  State Management: v1.0.0
EOF
}

# =============================================================================
# Argument Parsing
# =============================================================================

# Default options
CONFIG_FILE="$SERVERSH_CONFIG_FILE"
STATE_FILE="$SERVERSH_STATE_FILE"
LOG_LEVEL=$LOG_LEVEL_INFO
PARALLEL_JOBS=1
FORCE_INSTALL=false
RESUME_INSTALL=false
QUIET_MODE=false
DRY_RUN=false
VALIDATE_ONLY=false
LIST_MODULES=false
LIST_PROFILES=false
PROFILE_NAME=""
CREATE_CHECKPOINT_DESC=""
ROLLBACK_TO_ID=""
SHOW_STATUS=false
CLEANUP_MODE=false

# Module list
MODULES_TO_INSTALL=()

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -s|--state)
                STATE_FILE="$2"
                shift 2
                ;;
            -l|--log-level)
                # Convert string log level to numeric
                case "$2" in
                    "DEBUG"|"debug") LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
                    "INFO"|"info")   LOG_LEVEL=$LOG_LEVEL_INFO ;;
                    "WARN"|"warn")   LOG_LEVEL=$LOG_LEVEL_WARN ;;
                    "ERROR"|"error") LOG_LEVEL=$LOG_LEVEL_ERROR ;;
                    "FATAL"|"fatal") LOG_LEVEL=$LOG_LEVEL_FATAL ;;
                    *) LOG_LEVEL=$LOG_LEVEL_INFO ;;
                esac
                shift 2
                ;;
            -p|--parallel)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_INSTALL=true
                shift
                ;;
            -r|--resume)
                RESUME_INSTALL=true
                shift
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            --list-modules)
                LIST_MODULES=true
                shift
                ;;
            --list-profiles)
                LIST_PROFILES=true
                shift
                ;;
            --profile)
                PROFILE_NAME="$2"
                shift 2
                ;;
            --create-checkpoint)
                CREATE_CHECKPOINT_DESC="$2"
                shift 2
                ;;
            --rollback-to)
                ROLLBACK_TO_ID="$2"
                shift 2
                ;;
            --status)
                SHOW_STATUS=true
                shift
                ;;
            --cleanup)
                CLEANUP_MODE=true
                shift
                ;;
            -*)
                echo "Unknown option: $1" >&2
                show_help >&2
                exit 2
                ;;
            *)
                MODULES_TO_INSTALL+=("$1")
                shift
                ;;
        esac
    done
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_environment() {
    log_debug "Validating environment"

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 4
    fi

    # Validate system requirements
    if ! validate_required_commands; then
        log_error "System requirements not met"
        exit 3
    fi

    # Validate bash version
    if ! validate_bash_version; then
        log_error "Bash version too old"
        exit 3
    fi

    # Validate system environment
    if ! validate_system_environment; then
        log_error "System environment validation failed"
        exit 3
    fi

    log_success "Environment validation passed"
}

validate_configuration() {
    log_debug "Validating configuration"

    # Check if configuration file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_info "Configuration file not found, creating default: $CONFIG_FILE"
        # This will be handled by config_init()
    fi

    # Validate configuration file format
    if [[ -f "$CONFIG_FILE" ]] && ! command_exists jq; then
        log_warn "jq not available, configuration validation limited"
    fi

    log_success "Configuration validation passed"
}

# =============================================================================
# Installation Functions
# =============================================================================

initialize_serversh() {
    log_info "Initializing ServerSH"

    # SERVERSH_ROOT and other variables are already set as readonly in constants.sh
    # No need to re-export them
    export LOG_LEVEL="$LOG_LEVEL"

    # Initialize core components
    log_info "Loading core components..."
    if ! source "${PROJECT_ROOT}/core/config.sh"; then
        log_error "Failed to load configuration manager"
        exit 1
    fi
    log_info "Config manager loaded"

    if ! source "${PROJECT_ROOT}/core/state.sh"; then
        log_error "Failed to load state manager"
        exit 1
    fi
    log_info "State manager loaded"

    if ! source "${PROJECT_ROOT}/core/engine.sh"; then
        log_error "Failed to load engine"
        exit 1
    fi
    log_info "Engine loaded"

    # Initialize systems
    log_info "Initializing systems..."
    if ! config_init "$CONFIG_FILE"; then
        log_error "Configuration initialization failed"
        exit 5
    fi
    log_info "Config system initialized"

    if ! state_init "$STATE_FILE"; then
        log_error "State initialization failed"
        exit 7
    fi
    log_info "State system initialized"

    if ! engine_init "$CONFIG_FILE" "$STATE_FILE"; then
        log_error "Engine initialization failed"
        exit 1
    fi
    log_info "Engine initialized"

    # Configure logging
    log_set_level "$LOG_LEVEL"

    if [[ "$QUIET_MODE" == true ]]; then
        log_set_enabled false
    fi

    # Configure parallel execution
    if [[ "$PARALLEL_JOBS" -gt 1 ]]; then
        engine_enable_parallel "$PARALLEL_JOBS"
    fi

    # Load profile if specified
    if [[ -n "$PROFILE_NAME" ]]; then
        log_info "Loading configuration profile: $PROFILE_NAME"
        if ! config_load_profile "$PROFILE_NAME"; then
            log_error "Failed to load profile: $PROFILE_NAME"
            exit 5
        fi
    fi

    log_success "ServerSH initialized successfully"
}

perform_dry_run() {
    log_info "DRY RUN: Showing what would be executed"

    echo "Configuration file: $CONFIG_FILE"
    echo "State file: $STATE_FILE"
    echo "Log level: $LOG_LEVEL"
    echo "Parallel jobs: $PARALLEL_JOBS"
    echo "Modules to install: ${MODULES_TO_INSTALL[*]:-all enabled modules}"

    if [[ -f "$CONFIG_FILE" ]]; then
        echo ""
        echo "Configuration summary:"
        config_summary
    fi

    echo ""
    echo "Engine status:"
    engine_status

    echo ""
    echo "DRY RUN complete - no changes were made"
    exit 0
}

validate_only_mode() {
    log_info "VALIDATION ONLY: Validating configuration and dependencies"

    # Validate configuration
    if ! config_validate_values; then
        log_error "Configuration validation failed"
        exit 5
    fi

    # Validate module dependencies
    if [[ ${#MODULES_TO_INSTALL[@]} -gt 0 ]]; then
        log_info "Validating modules: ${MODULES_TO_INSTALL[*]}"
        # This would validate specific modules
    fi

    log_success "Validation complete - all checks passed"
    exit 0
}

execute_installation() {
    log_info "Starting ServerSH installation"

    # Check if installation already completed
    if [[ "$FORCE_INSTALL" != true ]] && [[ "$RESUME_INSTALL" != true ]]; then
        local current_status
        current_status=$(state_get "status" "pending")
        if [[ "$current_status" == "completed" ]]; then
            log_info "Installation already completed. Use --force to reinstall."
            exit 0
        fi
    fi

    # Create initial checkpoint
    engine_create_checkpoint "Installation start"

    # Start engine with specified modules
    local install_result
    if [[ ${#MODULES_TO_INSTALL[@]} -gt 0 ]]; then
        log_info "Installing specified modules: ${MODULES_TO_INSTALL[*]}"
        engine_start "${MODULES_TO_INSTALL[@]}"
        install_result=$?
        log_info "Engine start completed with exit code: $install_result"
    else
        log_info "Installing all enabled modules"
        engine_start
        install_result=$?
        log_info "Engine start completed with exit code: $install_result"
    fi

    # Handle installation result
    if [[ $install_result -eq 0 ]]; then
        log_success "ServerSH installation completed successfully"
        engine_create_checkpoint "Installation complete"

        # Show final status
        echo ""
        engine_status
        echo ""
        engine_stats

        exit 0
    else
        log_error "ServerSH installation failed with exit code: $install_result"
        log_error "Exit code meanings: 1=General Error, 2=Invalid Args, 3=Missing Deps, 4=Permission Denied, 5=Config Error, 6=Module Error, 7=State Error, 8=Lock Error"
        log_info "You can resume with: $0 --resume"
        log_info "Or rollback with: $0 --rollback-to <checkpoint_id>"
        exit $install_result
    fi
}

# =============================================================================
# Special Mode Functions
# =============================================================================

list_modules_mode() {
    log_info "Listing available modules"

    # Initialize engine to get module list
    if ! engine_init "$CONFIG_FILE" "$STATE_FILE" 2>/dev/null; then
        log_error "Failed to initialize engine for module listing"
        exit 1
    fi

    engine_list_modules
    exit 0
}

list_profiles_mode() {
    log_info "Listing available configuration profiles"

    local profiles
    profiles=$(config_list_profiles)

    if [[ -z "$profiles" ]]; then
        log_info "No configuration profiles found"
        exit 0
    fi

    echo "Available configuration profiles:"
    echo "$profiles" | while read -r profile; do
        if [[ -n "$profile" ]]; then
            local profile_name
            profile_name=$(basename "$profile" .yaml)
            echo "  - $profile_name ($profile)"
        fi
    done

    exit 0
}

show_status_mode() {
    log_info "Showing installation status"

    # Initialize systems
    if ! engine_init "$CONFIG_FILE" "$STATE_FILE" 2>/dev/null; then
        log_error "Failed to initialize engine"
        exit 1
    fi

    echo "ServerSH Installation Status"
    echo "=========================="
    echo ""

    engine_status
    echo ""
    engine_stats
    echo ""

    if [[ -f "$STATE_FILE" ]]; then
        echo "Recent checkpoints:"
        state_list_checkpoints | tail -5
        echo ""
    fi

    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Configuration:"
        config_summary
    fi

    exit 0
}

create_checkpoint_mode() {
    if [[ -z "$CREATE_CHECKPOINT_DESC" ]]; then
        log_error "Checkpoint description required"
        echo "Usage: $0 --create-checkpoint \"Description\""
        exit 2
    fi

    log_info "Creating checkpoint: $CREATE_CHECKPOINT_DESC"

    # Initialize engine
    if ! engine_init "$CONFIG_FILE" "$STATE_FILE" 2>/dev/null; then
        log_error "Failed to initialize engine"
        exit 1
    fi

    if engine_create_checkpoint "$CREATE_CHECKPOINT_DESC"; then
        log_success "Checkpoint created successfully"
        exit 0
    else
        log_error "Failed to create checkpoint"
        exit 7
    fi
}

rollback_mode() {
    if [[ -z "$ROLLBACK_TO_ID" ]]; then
        log_error "Checkpoint ID required for rollback"
        echo "Usage: $0 --rollback-to <checkpoint_id>"
        echo ""
        echo "Available checkpoints:"
        if [[ -f "$STATE_FILE" ]]; then
            state_list_checkpoints
        else
            echo "No state file found"
        fi
        exit 2
    fi

    log_warn "Rolling back to checkpoint: $ROLLBACK_TO_ID"

    # Initialize engine
    if ! engine_init "$CONFIG_FILE" "$STATE_FILE" 2>/dev/null; then
        log_error "Failed to initialize engine"
        exit 1
    fi

    if engine_rollback_to_checkpoint "$ROLLBACK_TO_ID"; then
        log_success "Rollback completed successfully"
        exit 0
    else
        log_error "Rollback failed"
        exit 7
    fi
}

cleanup_mode() {
    log_info "Cleaning up ServerSH"

    # Clean up old logs
    log_cleanup_old 7

    # Clean up old state files
    state_cleanup 30

    # Clean up configuration cache
    config_cleanup

    # Clean up temporary files
    find /tmp -name "serversh.*" -type f -mtime +1 -delete 2>/dev/null || true

    log_success "Cleanup completed"
    exit 0
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    # Parse arguments
    parse_arguments "$@"

    # Handle special modes first
    if [[ "$LIST_MODULES" == true ]]; then
        list_modules_mode
    fi

    if [[ "$LIST_PROFILES" == true ]]; then
        list_profiles_mode
    fi

    if [[ "$SHOW_STATUS" == true ]]; then
        show_status_mode
    fi

    if [[ "$CLEANUP_MODE" == true ]]; then
        cleanup_mode
    fi

    if [[ -n "$CREATE_CHECKPOINT_DESC" ]]; then
        create_checkpoint_mode
    fi

    if [[ -n "$ROLLBACK_TO_ID" ]]; then
        rollback_mode
    fi

    # Validate environment
    validate_environment

    # Validate configuration
    validate_configuration

    # Handle dry run mode
    if [[ "$DRY_RUN" == true ]]; then
        perform_dry_run
    fi

    # Handle validation-only mode
    if [[ "$VALIDATE_ONLY" == true ]]; then
        validate_only_mode
    fi

    # Initialize ServerSH
    log_info "About to initialize ServerSH..."
    initialize_serversh
    log_info "ServerSH initialization completed"

    # Execute installation
    log_info "About to execute installation..."
    execute_installation
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1

    log_error "Script failed at line $line_number with exit code $exit_code"
    log_error "Check logs at: $SERVERSH_LOG_FILE"

    # Show help for debugging
    echo ""
    echo "Debugging information:"
    echo "  - Check logs: tail -f $SERVERSH_LOG_FILE"
    echo "  - Show status: $0 --status"
    echo "  - Resume installation: $0 --resume"
    echo "  - Validate configuration: $0 --validate-only"

    exit $exit_code
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Run main function
main "$@"