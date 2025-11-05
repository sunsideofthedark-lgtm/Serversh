#!/bin/bash

# =============================================================================
# ServerSH Module Interface Specification
# =============================================================================

# Source dependencies
source "${SERVERSH_LIB_DIR}/constants.sh" || exit $EXIT_MISSING_DEPS
source "${SERVERSH_LIB_DIR}/utils.sh" || exit $EXIT_MISSING_DEPS
source "${SERVERSH_LIB_DIR}/logger.sh" || exit $EXIT_MISSING_DEPS
source "${SERVERSH_LIB_DIR}/config.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Module Interface Constants
# =============================================================================

# Module categories
readonly MODULE_CATEGORY_SYSTEM="system"
readonly MODULE_CATEGORY_SECURITY="security"
readonly MODULE_CATEGORY_CONTAINER="container"
readonly MODULE_CATEGORY_MONITORING="monitoring"
readonly MODULE_CATEGORY_APPLICATION="application"
readonly MODULE_CATEGORY_NETWORK="network"
readonly MODULE_CATEGORY_CUSTOM="custom"

# Module states
readonly MODULE_STATE_PENDING="pending"
readonly MODULE_STATE_CONFIG_VALIDATING="config_validating"
readonly MODULE_STATE_PRE_INSTALLING="pre_installing"
readonly MODULE_STATE_INSTALLING="installing"
readonly MODULE_STATE_POST_INSTALLING="post_installing"
readonly MODULE_STATE_VERIFYING="verifying"
readonly MODULE_STATE_COMPLETED="completed"
readonly MODULE_STATE_FAILED="failed"
readonly MODULE_STATE_ROLLING_BACK="rolling_back"
readonly MODULE_STATE_ROLLBACK_COMPLETE="rollback_complete"

# Return codes
readonly MODULE_SUCCESS=0
readonly MODULE_ERROR=1
readonly MODULE_SKIP=2
readonly MODULE_RETRY=3
readonly MODULE_CONFIG_ERROR=4
readonly MODULE_DEPENDENCY_ERROR=5

# =============================================================================
# Module Interface Functions (Must be implemented by each module)
# =============================================================================

# Required Functions - Every module MUST implement these:

# Get module name
# Returns: module name (string)
# Example: echo "system/update"
module_get_name() {
    echo "module_interface_example"
    return $MODULE_ERROR
}

# Get module version
# Returns: version string (semantic versioning)
# Example: echo "1.0.0"
module_get_version() {
    echo "1.0.0"
    return $MODULE_ERROR
}

# Get module description
# Returns: human-readable description
# Example: echo "Updates system packages to latest versions"
module_get_description() {
    echo "Example module for interface demonstration"
    return $MODULE_ERROR
}

# Get module category
# Returns: one of the MODULE_CATEGORY_* constants
# Example: echo "$MODULE_CATEGORY_SYSTEM"
module_get_category() {
    echo "$MODULE_CATEGORY_CUSTOM"
    return $MODULE_ERROR
}

# Get module dependencies
# Returns: space-separated list of module names
# Example: echo "system/update security/users"
module_get_dependencies() {
    echo ""
    return $MODULE_SUCCESS
}

# Validate module configuration
# Returns: MODULE_SUCCESS if valid, MODULE_CONFIG_ERROR if invalid
# This function should check that all required configuration values are present and valid
module_validate_config() {
    local module_name
    module_name=$(module_get_name)

    log_debug "Validating configuration for module: $module_name"

    # Example validation checks:
    local required_configs=()
    local config_errors=0

    # Check if required configurations are present
    for config_key in "${required_configs[@]}"; do
        local config_value
        config_value=$(config_get "modules.${module_name}.${config_key}" "")

        if [ -z "$config_value" ]; then
            log_error "Required configuration missing: $config_key"
            ((config_errors++))
        fi
    done

    if [ $config_errors -gt 0 ]; then
        return $MODULE_CONFIG_ERROR
    fi

    return $MODULE_SUCCESS
}

# Main installation function
# Returns: MODULE_SUCCESS on success, error code on failure
# This is the core function that performs the module's main work
module_install() {
    local module_name
    module_name=$(module_get_name)

    log_info "Installing module: $module_name"

    # Example installation logic:
    # 1. Pre-installation checks
    # 2. Install packages/configure services
    # 3. Post-installation setup

    return $MODULE_SUCCESS
}

# Verify installation success
# Returns: MODULE_SUCCESS if installation is verified, error code otherwise
# This function should check that the installation was successful
module_verify() {
    local module_name
    module_name=$(module_get_name)

    log_debug "Verifying installation of module: $module_name"

    # Example verification logic:
    # - Check if required services are running
    # - Check if required files exist
    # - Check if configuration is applied correctly

    return $MODULE_SUCCESS
}

# =============================================================================
# Optional Functions - Modules MAY implement these:

# Pre-installation hook
# Returns: MODULE_SUCCESS on success, error code on failure
# Called before main installation, useful for preparation tasks
module_pre_install() {
    local module_name
    module_name=$(module_get_name)

    log_debug "Running pre-installation for module: $module_name"

    return $MODULE_SUCCESS
}

# Post-installation hook
# Returns: MODULE_SUCCESS on success, error code on failure
# Called after main installation, useful for cleanup and finalization
module_post_install() {
    local module_name
    module_name=$(module_get_name)

    log_debug "Running post-installation for module: $module_name"

    return $MODULE_SUCCESS
}

# Rollback function
# Returns: MODULE_SUCCESS on success, error code on failure
# Called to undo changes made by the module
module_rollback() {
    local module_name
    module_name=$(module_get_name)

    log_warn "Rolling back module: $module_name"

    # Example rollback logic:
    # - Remove installed packages
    # - Restore configuration files
    # - Stop/disable services

    return $MODULE_SUCCESS
}

# Cleanup function
# Returns: MODULE_SUCCESS on success, error code on failure
# Called on failure to clean up partial changes
module_cleanup() {
    local module_name
    module_name=$(module_get_name)

    log_debug "Running cleanup for module: $module_name"

    return $MODULE_SUCCESS
}

# Get module status
# Returns: status string
# Returns current status of the module
module_get_status() {
    local module_name
    module_name=$(module_get_name)

    # Query state system for module status
    state_get_module_state "$module_name"
}

# Get module logs
# Returns: log content
# Returns logs specific to this module
module_get_logs() {
    local module_name
    module_name=$(module_get_name)

    # Return logs related to this module
    log_search "$module_name" "$SERVERSH_LOG_FILE"
}

# =============================================================================
# Module Helper Functions (Provided by framework)

# Get module configuration value
# Usage: module_config_get "config_key" "default_value"
module_config_get() {
    local config_key="$1"
    local default_value="${2:-}"
    local module_name
    module_name=$(module_get_name)

    config_get "modules.${module_name}.${config_key}" "$default_value"
}

# Set module configuration value
# Usage: module_config_set "config_key" "value"
module_config_set() {
    local config_key="$1"
    local value="$2"
    local module_name
    module_name=$(module_get_name)

    config_set "modules.${module_name}.${config_key}" "$value"
}

# Check if module configuration exists
# Usage: module_config_has "config_key"
module_config_has() {
    local config_key="$1"
    local module_name
    module_name=$(module_get_name)

    config_has "modules.${module_name}.${config_key}"
}

# Log module-specific message
# Usage: module_log "INFO" "Message content"
module_log() {
    local level="$1"
    shift
    local message="$*"
    local module_name
    module_name=$(module_get_name)

    log_${,,level} "[$module_name] $message"
}

# Create backup of file before modification
# Usage: module_backup_file "/path/to/file"
module_backup_file() {
    local file="$1"
    local module_name
    module_name=$(module_get_name)

    if [ -f "$file" ]; then
        local backup_dir="${SERVERSH_STATE_DIR}/backups/${module_name}"
        ensure_dir "$backup_dir"

        local backup_file="${backup_dir}/$(basename "$file").backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup_file" || return $EXIT_GENERAL_ERROR

        log_debug "Created backup: $backup_file"
        echo "$backup_file"
        return $EXIT_SUCCESS
    fi

    return $EXIT_CONFIG_ERROR
}

# Validate OS compatibility
# Usage: module_validate_os "ubuntu" "debian" "centos"
module_validate_os() {
    local supported_os=("$@")
    local current_os
    current_os=$(get_system_info "os")

    if array_contains "$current_os" "${supported_os[@]}"; then
        log_debug "OS compatibility verified: $current_os"
        return $EXIT_SUCCESS
    else
        log_error "OS not supported: $current_os (supported: ${supported_os[*]})"
        return $EXIT_CONFIG_ERROR
    fi
}

# Check if package is installed
# Usage: module_check_package "package_name"
module_check_package() {
    local package="$1"
    is_package_installed "$package"
}

# Install package with OS-specific handling
# Usage: module_install_package "package_name" ["alternative_package"]
module_install_package() {
    local package="$1"
    local alt_package="${2:-}"

    if module_check_package "$package"; then
        log_debug "Package already installed: $package"
        return $EXIT_SUCCESS
    fi

    log_info "Installing package: $package"

    # This would integrate with the system's package manager
    # Implementation depends on the specific system
    local os_id
    os_id=$(get_system_info "os")

    case "$os_id" in
        ubuntu|debian)
            apt-get update && apt-get install -y "$package"
            ;;
        centos|rhel|fedora)
            if command_exists dnf; then
                dnf install -y "${alt_package:-$package}"
            else
                yum install -y "${alt_package:-$package}"
            fi
            ;;
        *)
            log_error "Unsupported OS for package installation: $os_id"
            return $EXIT_GENERAL_ERROR
            ;;
    esac
}

# Enable and start service
# Usage: module_enable_service "service_name"
module_enable_service() {
    local service="$1"

    log_info "Enabling service: $service"

    if command_exists systemctl; then
        systemctl enable "$service" && systemctl start "$service"
    elif command_exists service; then
        service "$service" start
        # Add to startup (implementation depends on system)
    else
        log_error "No service manager available"
        return $EXIT_GENERAL_ERROR
    fi
}

# Check if service is running
# Usage: module_check_service "service_name"
module_check_service() {
    local service="$1"
    is_service_running "$service"
}

# Create user with specific configuration
# Usage: module_create_user "username" "group" "shell" "home"
module_create_user() {
    local username="$1"
    local group="${2:-}"
    local shell="${3:-/bin/bash}"
    local home="${4:-}"

    if id "$username" &>/dev/null; then
        log_debug "User already exists: $username"
        return $EXIT_SUCCESS
    fi

    log_info "Creating user: $username"

    local useradd_cmd="useradd -m -s $shell"
    if [ -n "$group" ]; then
        useradd_cmd="$useradd_cmd -g $group"
    fi
    if [ -n "$home" ]; then
        useradd_cmd="$useradd_cmd -d $home"
    fi

    if ! $useradd_cmd "$username"; then
        log_error "Failed to create user: $username"
        return $EXIT_GENERAL_ERROR
    fi

    return $EXIT_SUCCESS
}

# Add user to group
# Usage: module_add_user_to_group "username" "group"
module_add_user_to_group() {
    local username="$1"
    local group="$2"

    if ! id "$username" &>/dev/null; then
        log_error "User does not exist: $username"
        return $EXIT_CONFIG_ERROR
    fi

    if ! getent group "$group" &>/dev/null; then
        log_error "Group does not exist: $group"
        return $EXIT_CONFIG_ERROR
    fi

    log_info "Adding user $username to group $group"
    usermod -aG "$group" "$username"
}

# Create directory with specific permissions
# Usage: module_create_dir "/path/to/dir" "permissions" "owner:group"
module_create_dir() {
    local dir="$1"
    local permissions="${2:-755}"
    local owner="${3:-}"

    ensure_dir "$dir" || return $EXIT_GENERAL_ERROR
    chmod "$permissions" "$dir" || return $EXIT_GENERAL_ERROR

    if [ -n "$owner" ]; then
        chown "$owner" "$dir" || return $EXIT_GENERAL_ERROR
    fi

    log_debug "Created directory: $dir (permissions: $permissions, owner: $owner)"
    return $EXIT_SUCCESS
}

# Install configuration file from template
# Usage: module_install_config "template_file" "target_file" "variables"
module_install_config() {
    local template_file="$1"
    local target_file="$2"
    shift 2
    local variables=("$@")

    if [ ! -f "$template_file" ]; then
        log_error "Template file not found: $template_file"
        return $EXIT_CONFIG_ERROR
    fi

    # Create backup of existing config
    if [ -f "$target_file" ]; then
        module_backup_file "$target_file" >/dev/null
    fi

    # Ensure target directory exists
    ensure_dir "$(dirname "$target_file")" || return $EXIT_GENERAL_ERROR

    # Copy template to target
    cp "$template_file" "$target_file" || return $EXIT_GENERAL_ERROR

    # Replace variables in template
    for var_pair in "${variables[@]}"; do
        local var_name="${var_pair%%=*}"
        local var_value="${var_pair#*=}"
        sed -i "s|{{$var_name}}|$var_value|g" "$target_file"
    done

    log_debug "Installed config: $target_file"
    return $EXIT_SUCCESS
}

# Add line to file if not present
# Usage: module_add_to_file "/path/to/file" "line to add"
module_add_to_file() {
    local file="$1"
    local line="$2"

    if [ ! -f "$file" ]; then
        touch "$file" || return $EXIT_GENERAL_ERROR
    fi

    if ! grep -qF "$line" "$file"; then
        echo "$line" >> "$file" || return $EXIT_GENERAL_ERROR
        log_debug "Added line to $file: $line"
    fi

    return $EXIT_SUCCESS
}

# Remove line from file
# Usage: module_remove_from_file "/path/to/file" "line to remove"
module_remove_from_file() {
    local file="$1"
    local line="$2"

    if [ ! -f "$file" ]; then
        return $EXIT_SUCCESS
    fi

    if grep -qF "$line" "$file"; then
        grep -vF "$line" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file" || return $EXIT_GENERAL_ERROR
        log_debug "Removed line from $file: $line"
    fi

    return $EXIT_SUCCESS
}

# =============================================================================
# Module Validation and Testing Functions

# Validate module implementation
# Checks that all required functions are implemented
module_validate_implementation() {
    local module_file="$1"
    local module_name
    module_name=$(basename "$module_file" .sh)

    log_debug "Validating module implementation: $module_name"

    # Source module temporarily
    if ! source "$module_file" 2>/dev/null; then
        log_error "Failed to source module: $module_name"
        return $EXIT_MODULE_ERROR
    fi

    # Check required functions
    local required_functions=(
        "module_get_name"
        "module_get_version"
        "module_get_description"
        "module_get_category"
        "module_get_dependencies"
        "module_validate_config"
        "module_install"
        "module_verify"
    )

    local missing_functions=()
    for func in "${required_functions[@]}"; do
        if ! declare -f "$func" >/dev/null; then
            missing_functions+=("$func")
        fi
    done

    if [ ${#missing_functions[@]} -gt 0 ]; then
        log_error "Module $module_name missing required functions: ${missing_functions[*]}"
        return $EXIT_MODULE_ERROR
    fi

    # Validate function return values
    local name
    name=$(module_get_name 2>/dev/null)
    if [ -z "$name" ]; then
        log_error "Module $module_name: module_get_name() returned empty value"
        return $EXIT_MODULE_ERROR
    fi

    local version
    version=$(module_get_version 2>/dev/null)
    if [ -z "$version" ]; then
        log_error "Module $module_name: module_get_version() returned empty value"
        return $EXIT_MODULE_ERROR
    fi

    local category
    category=$(module_get_category 2>/dev/null)
    if [ -z "$category" ]; then
        log_error "Module $module_name: module_get_category() returned empty value"
        return $EXIT_MODULE_ERROR
    fi

    log_success "Module implementation validated: $module_name"
    return $EXIT_SUCCESS
}

# =============================================================================
# Module Creation Template Generator

# Generate module template
# Usage: module_create_template "module_name" "category" "description"
module_create_template() {
    local module_name="$1"
    local category="${2:-custom}"
    local description="${3:-Generated module}"

    local module_dir="${SERVERSH_MODULES_DIR}/${category}"
    local module_file="${module_dir}/${module_name}.sh"

    ensure_dir "$module_dir" || return $EXIT_GENERAL_ERROR

    cat > "$module_file" << EOF
#!/bin/bash

# =============================================================================
# Module: $module_name
# Category: $category
# Description: $description
# Version: 1.0.0
# =============================================================================

# Source module interface
source "\${SERVERSH_LIB_DIR}/module_interface.sh" || exit \$EXIT_MISSING_DEPS

# =============================================================================
# Required Functions
# =============================================================================

module_get_name() {
    echo "$category/$module_name"
    return \$MODULE_SUCCESS
}

module_get_version() {
    echo "1.0.0"
    return \$MODULE_SUCCESS
}

module_get_description() {
    echo "$description"
    return \$MODULE_SUCCESS
}

module_get_category() {
    echo "\$$MODULE_CATEGORY_$(to_upper "$category")"
    return \$MODULE_SUCCESS
}

module_get_dependencies() {
    echo ""
    return \$MODULE_SUCCESS
}

module_validate_config() {
    local module_name
    module_name=\$(module_get_name)

    log_debug "Validating configuration for module: \$module_name"

    # Add your configuration validation logic here

    return \$MODULE_SUCCESS
}

module_install() {
    local module_name
    module_name=\$(module_get_name)

    log_info "Installing module: \$module_name"

    # Add your installation logic here

    return \$MODULE_SUCCESS
}

module_verify() {
    local module_name
    module_name=\$(module_get_name)

    log_debug "Verifying installation of module: \$module_name"

    # Add your verification logic here

    return \$MODULE_SUCCESS
}

# =============================================================================
# Optional Functions
# =============================================================================

module_pre_install() {
    local module_name
    module_name=\$(module_get_name)

    log_debug "Running pre-installation for module: \$module_name"

    return \$MODULE_SUCCESS
}

module_post_install() {
    local module_name
    module_name=\$(module_get_name)

    log_debug "Running post-installation for module: \$module_name"

    return \$MODULE_SUCCESS
}

module_rollback() {
    local module_name
    module_name=\$(module_get_name)

    log_warn "Rolling back module: \$module_name"

    return \$MODULE_SUCCESS
}

module_cleanup() {
    local module_name
    module_name=\$(module_get_name)

    log_debug "Running cleanup for module: \$module_name"

    return \$MODULE_SUCCESS
}
EOF

    chmod "$FILE_PERMISSION_EXEC" "$module_file" || return $EXIT_GENERAL_ERROR

    log_success "Module template created: $module_file"
    return $EXIT_SUCCESS
}

echo "Module interface loaded successfully"
return $EXIT_SUCCESS