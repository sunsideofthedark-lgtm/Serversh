#!/bin/bash

# =============================================================================
# Module: User Management and Security
# Category: Security
# Description: Creates administrative users with SSH access and proper security settings
# Version: 1.0.0
# =============================================================================

# Source module interface
source "${SERVERSH_LIB_DIR}/module_interface.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Required Functions
# =============================================================================

module_get_name() {
    echo "security/users"
    return $MODULE_SUCCESS
}

module_get_version() {
    echo "1.0.0"
    return $MODULE_SUCCESS
}

module_get_description() {
    echo "Creates administrative users with SSH access and configures security groups"
    return $MODULE_SUCCESS
}

module_get_category() {
    echo "$MODULE_CATEGORY_SECURITY"
    return $MODULE_SUCCESS
}

module_get_dependencies() {
    echo ""
    return $MODULE_SUCCESS
}

module_validate_config() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Validating configuration for module: $module_name"

    # Get configuration options
    local admin_user
    admin_user=$(module_config_get "admin_user" "")
    local create_admin
    create_admin=$(module_config_get "create_admin" "true")
    local generate_ssh_keys
    generate_ssh_keys=$(module_config_get "generate_ssh_keys" "true")
    local ssh_key_password
    ssh_key_password=$(module_config_get "ssh_key_password" "false")
    local disable_root
    disable_root=$(module_config_get "disable_root" "true")
    local ssh_access_group
    ssh_access_group=$(module_config_get "ssh_access_group" "remotessh")

    # Validate boolean options
    for option in "create_admin" "generate_ssh_keys" "ssh_key_password" "disable_root"; do
        local value
        value=$(module_config_get "$option")
        if [[ "$value" != "true" && "$value" != "false" ]]; then
            module_log "ERROR" "Invalid $option value: $value (must be true or false)"
            return $MODULE_CONFIG_ERROR
        fi
    done

    # Validate admin_user if create_admin is true
    if [[ "$create_admin" == "true" ]]; then
        if [[ -z "$admin_user" ]]; then
            module_log "ERROR" "admin_user is required when create_admin is true"
            return $MODULE_CONFIG_ERROR
        fi

        # Validate username format
        if ! is_valid_username "$admin_user"; then
            module_log "ERROR" "Invalid admin_user format: $admin_user"
            module_log "ERROR" "Username rules:"
            module_log "ERROR" "  - Only lowercase letters (a-z), numbers (0-9), underscores (_) and hyphens (-)"
            module_log "ERROR" "  - Must start with letter or underscore"
            module_log "ERROR" "  - Maximum 32 characters long"
            return $MODULE_CONFIG_ERROR
        fi

        # Check for reserved usernames
        local reserved_names="root daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc gnats nobody systemd-network systemd-resolve messagebus systemd-timesync syslog"
        for reserved in $reserved_names; do
            if [[ "$admin_user" == "$reserved" ]]; then
                module_log "ERROR" "Username '$admin_user' is reserved"
                return $MODULE_CONFIG_ERROR
            fi
        done

        # Check username length
        if [[ ${#admin_user} -gt 32 ]]; then
            module_log "ERROR" "Username too long: ${#admin_user} characters (max 32)"
            return $MODULE_CONFIG_ERROR
        fi
    fi

    # Validate SSH access group name
    if ! is_valid_username "$ssh_access_group"; then
        module_log "ERROR" "Invalid ssh_access_group format: $ssh_access_group"
        return $MODULE_CONFIG_ERROR
    fi

    module_log "DEBUG" "Configuration validation passed"
    module_log "DEBUG" "  create_admin: $create_admin"
    module_log "DEBUG" "  admin_user: $admin_user"
    module_log "DEBUG" "  generate_ssh_keys: $generate_ssh_keys"
    module_log "DEBUG" "  ssh_key_password: $ssh_key_password"
    module_log "DEBUG" "  disable_root: $disable_root"
    module_log "DEBUG" "  ssh_access_group: $ssh_access_group"

    return $MODULE_SUCCESS
}

module_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Installing module: $module_name"

    # Get configuration
    local create_admin
    create_admin=$(module_config_get "create_admin" "true")
    local admin_user
    admin_user=$(module_config_get "admin_user" "")

    # Create SSH access group
    if ! create_ssh_access_group; then
        module_log "ERROR" "Failed to create SSH access group"
        return $MODULE_ERROR
    fi

    # Create admin user if configured
    if [[ "$create_admin" == "true" ]]; then
        if ! create_admin_user "$admin_user"; then
            module_log "ERROR" "Failed to create admin user"
            return $MODULE_ERROR
        fi
    fi

    # Configure SSH access group permissions
    if ! configure_ssh_group_permissions; then
        module_log "ERROR" "Failed to configure SSH group permissions"
        return $MODULE_ERROR
    fi

    # Create secure working directories
    if ! create_working_directories "$admin_user"; then
        module_log "ERROR" "Failed to create working directories"
        return $MODULE_ERROR
    fi

    module_log "SUCCESS" "User management and security configuration completed"
    return $MODULE_SUCCESS
}

module_verify() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Verifying user management: $module_name"

    # Get configuration
    local create_admin
    create_admin=$(module_config_get "create_admin" "true")
    local admin_user
    admin_user=$(module_config_get "admin_user" "")
    local ssh_access_group
    ssh_access_group=$(module_config_get "ssh_access_group" "remotessh")

    # Verify SSH access group exists
    if ! getent group "$ssh_access_group" >/dev/null; then
        module_log "ERROR" "SSH access group not found: $ssh_access_group"
        return $MODULE_ERROR
    fi

    # Verify admin user if created
    if [[ "$create_admin" == "true" ]]; then
        if ! id "$admin_user" >/dev/null 2>&1; then
            module_log "ERROR" "Admin user not found: $admin_user"
            return $MODULE_ERROR
        fi

        # Verify user is in SSH access group
        if ! groups "$admin_user" | grep -q "$ssh_access_group"; then
            module_log "ERROR" "Admin user not in SSH access group: $ssh_access_group"
            return $MODULE_ERROR
        fi

        # Verify user has admin privileges
        if ! verify_admin_privileges "$admin_user"; then
            module_log "ERROR" "Admin user lacks required privileges"
            return $MODULE_ERROR
        fi

        # Verify SSH keys if generated
        local generate_ssh_keys
        generate_ssh_keys=$(module_config_get "generate_ssh_keys" "true")
        if [[ "$generate_ssh_keys" == "true" ]]; then
            verify_ssh_keys "$admin_user"
        fi
    fi

    module_log "DEBUG" "User management verification successful"
    return $MODULE_SUCCESS
}

# =============================================================================
# Optional Functions
# =============================================================================

module_pre_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running pre-installation for module: $module_name"

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        module_log "ERROR" "Root privileges required for user management"
        return $MODULE_PERMISSION_DENIED
    fi

    # Check if required commands are available
    local required_commands=("useradd" "usermod" "groupadd" "passwd" "ssh-keygen")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            module_log "ERROR" "Required command not available: $cmd"
            return $EXIT_MISSING_DEPS
        fi
    done

    return $MODULE_SUCCESS
}

module_post_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running post-installation for module: $module_name"

    # Display user information
    display_user_info

    # Display SSH key information if generated
    local generate_ssh_keys
    generate_ssh_keys=$(module_config_get "generate_ssh_keys" "true")
    if [[ "$generate_ssh_keys" == "true" ]]; then
        display_ssh_key_info
    fi

    # Show security recommendations
    show_security_recommendations

    return $MODULE_SUCCESS
}

module_rollback() {
    local module_name
    module_name=$(module_get_name)

    module_log "WARN" "Rolling back module: $module_name"

    # Get configuration
    local create_admin
    create_admin=$(module_config_get "create_admin" "true")
    local admin_user
    admin_user=$(module_config_get "admin_user" "")
    local ssh_access_group
    ssh_access_group=$(module_config_get "ssh_access_group" "remotessh")

    # Remove admin user if created by this module
    if [[ "$create_admin" == "true" && -n "$admin_user" ]]; then
        if id "$admin_user" >/dev/null 2>&1; then
            module_log "INFO" "Removing admin user: $admin_user"

            # Kill any processes for this user
            pkill -u "$admin_user" 2>/dev/null || true
            sleep 1

            # Remove user and home directory
            userdel -r "$admin_user" 2>/dev/null || {
                module_log "WARN" "Failed to completely remove user, cleaning up manually"
                rm -rf "/home/$admin_user" 2>/dev/null || true
            }
        fi
    fi

    # Note: We don't remove the SSH access group as other users might depend on it

    module_log "INFO" "Rollback completed"
    return $MODULE_SUCCESS
}

module_cleanup() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running cleanup for module: $module_name"

    # Remove temporary files
    rm -f "${SERVERSH_STATE_DIR}/${module_name}_*.tmp" 2>/dev/null || true

    return $MODULE_SUCCESS
}

# =============================================================================
# Helper Functions
# =============================================================================

create_ssh_access_group() {
    local ssh_access_group
    ssh_access_group=$(module_config_get "ssh_access_group" "remotessh")

    module_log "INFO" "Creating SSH access group: $ssh_access_group"

    # Check if group already exists
    if getent group "$ssh_access_group" >/dev/null; then
        module_log "INFO" "SSH access group already exists: $ssh_access_group"
        return $MODULE_SUCCESS
    fi

    # Create group
    if ! groupadd "$ssh_access_group"; then
        module_log "ERROR" "Failed to create SSH access group: $ssh_access_group"
        return $MODULE_ERROR
    fi

    module_log "SUCCESS" "SSH access group created: $ssh_access_group"
    return $MODULE_SUCCESS
}

create_admin_user() {
    local admin_user="$1"

    module_log "INFO" "Creating admin user: $admin_user"

    # Check if user already exists
    if id "$admin_user" >/dev/null 2>&1; then
        module_log "INFO" "Admin user already exists: $admin_user"

        # Add user to SSH access group if not already a member
        if ! groups "$admin_user" | grep -q "$(module_config_get "ssh_access_group" "remotessh")"; then
            add_user_to_ssh_group "$admin_user"
        fi

        return $MODULE_SUCCESS
    fi

    # Create user with home directory and bash shell
    if ! useradd -m -s /bin/bash "$admin_user"; then
        module_log "ERROR" "Failed to create admin user: $admin_user"
        return $MODULE_ERROR
    fi

    # Add user to admin group (sudo/wheel)
    local admin_group
    admin_group=$(get_admin_group)
    if ! usermod -aG "$admin_group" "$admin_user"; then
        module_log "ERROR" "Failed to add user to admin group: $admin_group"
        return $MODULE_ERROR
    fi

    # Add user to SSH access group
    add_user_to_ssh_group "$admin_user"

    # Generate SSH keys if configured
    local generate_ssh_keys
    generate_ssh_keys=$(module_config_get "generate_ssh_keys" "true")
    if [[ "$generate_ssh_keys" == "true" ]]; then
        generate_user_ssh_keys "$admin_user"
    fi

    module_log "SUCCESS" "Admin user created: $admin_user"
    return $MODULE_SUCCESS
}

get_admin_group() {
    local os_id
    os_id=$(get_system_info "os")

    case "$os_id" in
        ubuntu|debian)
            echo "sudo"
            ;;
        centos|rhel|rocky|almalinux|fedora|opensuse*)
            echo "wheel"
            ;;
        arch)
            echo "wheel"
            ;;
        *)
            echo "sudo"
            ;;
    esac
}

add_user_to_ssh_group() {
    local user="$1"
    local ssh_access_group
    ssh_access_group=$(module_config_get "ssh_access_group" "remotessh")

    module_log "INFO" "Adding user $user to SSH access group: $ssh_access_group"

    if ! usermod -aG "$ssh_access_group" "$user"; then
        module_log "ERROR" "Failed to add user to SSH access group"
        return $MODULE_ERROR
    fi

    return $MODULE_SUCCESS
}

generate_user_ssh_keys() {
    local user="$1"
    local ssh_key_password
    ssh_key_password=$(module_config_get "ssh_key_password" "false")

    module_log "INFO" "Generating SSH keys for user: $user"

    # Get user home directory
    local user_home
    user_home=$(eval echo ~"$user")

    # Create .ssh directory
    local ssh_dir="$user_home/.ssh"
    ensure_dir "$ssh_dir"
    chown "$user:$user" "$ssh_dir"
    chmod 700 "$ssh_dir"

    # Generate SSH key pair
    local key_options=()
    key_options+=("-t" "ed25519")
    key_options+=("-f" "$ssh_dir/id_ed25519")
    key_options+=("-C" "$user@$(hostname)")

    if [[ "$ssh_key_password" == "true" ]]; then
        # Interactive password input
        module_log "INFO" "SSH key will be protected with a password"
        sudo -u "$user" ssh-keygen "${key_options[@]}"
    else
        # No password
        key_options+=("-N" "")
        sudo -u "$user" ssh-keygen "${key_options[@]}"
    fi

    # Set proper permissions
    chown "$user:$user" "$ssh_dir/id_ed25519"
    chmod 600 "$ssh_dir/id_ed25519"
    chown "$user:$user" "$ssh_dir/id_ed25519.pub"
    chmod 644 "$ssh_dir/id_ed25519.pub"

    # Create authorized_keys
    sudo -u "$user" cp "$ssh_dir/id_ed25519.pub" "$ssh_dir/authorized_keys"
    chown "$user:$user" "$ssh_dir/authorized_keys"
    chmod 600 "$ssh_dir/authorized_keys"

    module_log "SUCCESS" "SSH keys generated for user: $user"
    return $MODULE_SUCCESS
}

configure_ssh_group_permissions() {
    local ssh_access_group
    ssh_access_group=$(module_config_get "ssh_access_group" "remotessh")

    module_log "INFO" "Configuring SSH access group permissions for: $ssh_access_group"

    # Create sudoers configuration for secure directory access
    local sudoers_dir="/etc/sudoers.d"
    if [[ -d "$sudoers_dir" ]]; then
        local admin_user
        admin_user=$(module_config_get "admin_user" "")

        if [[ -n "$admin_user" ]]; then
            local sudoers_file="${sudoers_dir}/91-${admin_user}-srv-access"
            cat > "$sudoers_file" << EOF
# Sudo access for $admin_user to manage /srv directory
$admin_user ALL=(root) NOPASSWD: /bin/mkdir -p /srv/*, /bin/chown $admin_user\\:$admin_user /srv/*, /bin/chmod 755 /srv/*
EOF
            chmod 440 "$sudoers_file"
            module_log "DEBUG" "Created sudoers configuration: $sudoers_file"
        fi
    fi

    return $MODULE_SUCCESS
}

create_working_directories() {
    local user="$1"

    module_log "INFO" "Creating working directories for user: $user"

    # Get user home directory
    local user_home
    user_home=$(eval echo ~"$user")

    # Create standard directories
    local work_dirs=("projects" "scripts" "backups" "downloads")

    for dir in "${work_dirs[@]}"; do
        local full_path="$user_home/$dir"
        ensure_dir "$full_path"
        chown "$user:$user" "$full_path"
        chmod 755 "$full_path"
        module_log "DEBUG" "Created directory: $full_path"
    done

    # Create .ssh directory if it doesn't exist
    local ssh_dir="$user_home/.ssh"
    ensure_dir "$ssh_dir"
    chown "$user:$user" "$ssh_dir"
    chmod 700 "$ssh_dir"

    module_log "SUCCESS" "Working directories created for user: $user"
    return $MODULE_SUCCESS
}

verify_admin_privileges() {
    local user="$1"
    local admin_group
    admin_group=$(get_admin_group)

    module_log "DEBUG" "Verifying admin privileges for user: $user"

    # Check if user is in admin group
    if ! groups "$user" | grep -q "$admin_group"; then
        module_log "ERROR" "User $user is not in admin group: $admin_group"
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "User $user has admin privileges via group: $admin_group"
    return $MODULE_SUCCESS
}

verify_ssh_keys() {
    local user="$1"
    local user_home
    user_home=$(eval echo ~"$user")
    local ssh_dir="$user_home/.ssh"

    module_log "DEBUG" "Verifying SSH keys for user: $user"

    # Check if SSH directory exists
    if [[ ! -d "$ssh_dir" ]]; then
        module_log "ERROR" "SSH directory not found: $ssh_dir"
        return $MODULE_ERROR
    fi

    # Check if private key exists
    if [[ ! -f "$ssh_dir/id_ed25519" ]]; then
        module_log "ERROR" "SSH private key not found: $ssh_dir/id_ed25519"
        return $MODULE_ERROR
    fi

    # Check if public key exists
    if [[ ! -f "$ssh_dir/id_ed25519.pub" ]]; then
        module_log "ERROR" "SSH public key not found: $ssh_dir/id_ed25519.pub"
        return $MODULE_ERROR
    fi

    # Check if authorized_keys exists
    if [[ ! -f "$ssh_dir/authorized_keys" ]]; then
        module_log "ERROR" "authorized_keys not found: $ssh_dir/authorized_keys"
        return $MODULE_ERROR
    fi

    # Check permissions
    local ssh_dir_perms
    ssh_dir_perms=$(stat -c %a "$ssh_dir" 2>/dev/null)
    if [[ "$ssh_dir_perms" != "700" ]]; then
        module_log "WARN" "SSH directory permissions are not 700: $ssh_dir_perms"
    fi

    local private_key_perms
    private_key_perms=$(stat -c %a "$ssh_dir/id_ed25519" 2>/dev/null)
    if [[ "$private_key_perms" != "600" ]]; then
        module_log "WARN" "SSH private key permissions are not 600: $private_key_perms"
    fi

    module_log "DEBUG" "SSH keys verification successful"
    return $MODULE_SUCCESS
}

display_user_info() {
    local create_admin
    create_admin=$(module_config_get "create_admin" "true")
    local admin_user
    admin_user=$(module_config_get "admin_user" "")
    local ssh_access_group
    ssh_access_group=$(module_config_get "ssh_access_group" "remotessh")

    module_log "INFO" "User Management Summary:"

    if [[ "$create_admin" == "true" ]]; then
        module_log "INFO" "  Admin User: $admin_user"
        module_log "INFO" "  Home Directory: $(eval echo ~"$admin_user")"
        module_log "INFO" "  Admin Group: $(get_admin_group)"
        module_log "INFO" "  SSH Access Group: $ssh_access_group"
    else
        module_log "INFO" "  Admin User: Not created (create_admin=false)"
    fi

    module_log "INFO" "  SSH Access Group: $ssh_access_group"
}

display_ssh_key_info() {
    local admin_user
    admin_user=$(module_config_get "admin_user" "")
    local user_home
    user_home=$(eval echo ~"$admin_user")
    local public_key_file="$user_home/.ssh/id_ed25519.pub"

    if [[ -f "$public_key_file" ]]; then
        module_log "INFO" "SSH Public Key:"
        module_log "INFO" "================================"
        cat "$public_key_file" | while read -r line; do
            module_log "INFO" "$line"
        done
        module_log "INFO" "================================"
        module_log "INFO" "Save this key for SSH access to the server"
        module_log "INFO" "Private key location: $user_home/.ssh/id_ed25519"
    fi
}

show_security_recommendations() {
    local disable_root
    disable_root=$(module_config_get "disable_root" "true")

    module_log "INFO" "Security Recommendations:"
    module_log "INFO" "  1. Use SSH key authentication (passwords are disabled)"
    module_log "INFO" "  2. Only allow users in the '$(module_config_get "ssh_access_group" "remotessh")' group to SSH"
    module_log "INFO" "  3. Consider setting up fail2ban for brute force protection"
    module_log "INFO" "  4. Regular security updates are recommended"

    if [[ "$disable_root" == "true" ]]; then
        module_log "INFO" "  5. Root access will be disabled after SSH configuration"
    fi

    module_log "INFO" "  6. Monitor logs for suspicious activity"
}

# Initialize module (optional - called when module is sourced)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    module_log "DEBUG" "User management module loaded"
fi

return $MODULE_SUCCESS