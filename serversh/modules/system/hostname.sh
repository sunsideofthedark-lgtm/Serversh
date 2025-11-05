#!/bin/bash

# =============================================================================
# Module: System Hostname Configuration
# Category: System
# Description: Configures system hostname and updates /etc/hosts
# Version: 1.0.0
# =============================================================================

# Source module interface
source "${SERVERSH_LIB_DIR}/module_interface.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Required Functions
# =============================================================================

module_get_name() {
    echo "system/hostname"
    return $MODULE_SUCCESS
}

module_get_version() {
    echo "1.0.0"
    return $MODULE_SUCCESS
}

module_get_description() {
    echo "Configures system hostname and updates /etc/hosts file accordingly"
    return $MODULE_SUCCESS
}

module_get_category() {
    echo "$MODULE_CATEGORY_SYSTEM"
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

    # Get hostname from configuration
    local hostname
    hostname=$(module_config_get "hostname" "")

    # Validate hostname is provided
    if [[ -z "$hostname" ]]; then
        module_log "ERROR" "Hostname is required but not configured"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate hostname format
    if ! is_valid_hostname "$hostname"; then
        module_log "ERROR" "Invalid hostname format: $hostname"
        module_log "ERROR" "Hostname rules:"
        module_log "ERROR" "  - Only letters (a-z), numbers (0-9), and hyphens (-)"
        module_log "ERROR" "  - Must start and end with letter or number"
        module_log "ERROR" "  - Maximum 63 characters long"
        module_log "ERROR" "  - No consecutive hyphens"
        return $MODULE_CONFIG_ERROR
    fi

    # Check hostname length
    if [[ ${#hostname} -gt 63 ]]; then
        module_log "ERROR" "Hostname too long: ${#hostname} characters (max 63)"
        return $MODULE_CONFIG_ERROR
    fi

    # Check if hostname conflicts with localhost
    local local_hostnames=("localhost" "localhost.localdomain" "ubuntu" "debian")
    for local_hostname in "${local_hostnames[@]}"; do
        if [[ "$hostname" == "$local_hostname" ]]; then
            module_log "WARN" "Hostname '$hostname' conflicts with standard localhost names"
        fi
    done

    # Get additional configuration options
    local update_hosts
    update_hosts=$(module_config_get "update_hosts" "true")
    local fqdn
    fqdn=$(module_config_get "fqdn" "")
    local validate_dns
    validate_dns=$(module_config_get "validate_dns" "false")

    # Validate boolean options
    if [[ "$update_hosts" != "true" && "$update_hosts" != "false" ]]; then
        module_log "ERROR" "Invalid update_hosts value: $update_hosts (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    if [[ "$validate_dns" != "true" && "$validate_dns" != "false" ]]; then
        module_log "ERROR" "Invalid validate_dns value: $validate_dns (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate FQDN if provided
    if [[ -n "$fqdn" ]]; then
        if [[ ! "$fqdn" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
            module_log "ERROR" "Invalid FQDN format: $fqdn"
            return $MODULE_CONFIG_ERROR
        fi
    fi

    module_log "DEBUG" "Configuration validation passed"
    module_log "DEBUG" "  hostname: $hostname"
    module_log "DEBUG" "  fqdn: $fqdn"
    module_log "DEBUG" "  update_hosts: $update_hosts"
    module_log "DEBUG" "  validate_dns: $validate_dns"

    return $MODULE_SUCCESS
}

module_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Installing module: $module_name"

    # Get configuration
    local hostname
    hostname=$(module_config_get "hostname")
    local update_hosts
    update_hosts=$(module_config_get "update_hosts" "true")
    local fqdn
    fqdn=$(module_config_get "fqdn" "")

    # Get current hostname
    local current_hostname
    current_hostname=$(hostname)

    module_log "INFO" "Current hostname: $current_hostname"
    module_log "INFO" "Target hostname: $hostname"

    # Check if hostname needs to be changed
    if [[ "$current_hostname" == "$hostname" ]]; then
        module_log "INFO" "Hostname is already set to: $hostname"

        # Still update hosts file if configured
        if [[ "$update_hosts" == "true" ]]; then
            update_hosts_file "$hostname" "$fqdn"
        fi

        return $MODULE_SUCCESS
    fi

    # Backup current configuration
    backup_hostname_config

    # Set new hostname
    if ! set_hostname "$hostname"; then
        module_log "ERROR" "Failed to set hostname to: $hostname"
        return $MODULE_ERROR
    fi

    # Update hosts file if configured
    if [[ "$update_hosts" == "true" ]]; then
        if ! update_hosts_file "$hostname" "$fqdn"; then
            module_log "ERROR" "Failed to update hosts file"
            return $MODULE_ERROR
        fi
    fi

    # Validate the change
    if ! validate_hostname_change "$hostname"; then
        module_log "ERROR" "Hostname change validation failed"
        return $MODULE_ERROR
    fi

    module_log "SUCCESS" "Hostname successfully changed to: $hostname"
    return $MODULE_SUCCESS
}

module_verify() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Verifying hostname configuration: $module_name"

    # Get expected hostname
    local expected_hostname
    expected_hostname=$(module_config_get "hostname")

    # Get current hostname
    local current_hostname
    current_hostname=$(hostname)

    if [[ "$current_hostname" != "$expected_hostname" ]]; then
        module_log "ERROR" "Hostname verification failed"
        module_log "ERROR" "  Expected: $expected_hostname"
        module_log "ERROR" "  Current: $current_hostname"
        return $MODULE_ERROR
    fi

    # Check hosts file if configured
    local update_hosts
    update_hosts=$(module_config_get "update_hosts" "true")
    if [[ "$update_hosts" == "true" ]]; then
        if ! grep -q "$expected_hostname" /etc/hosts; then
            module_log "ERROR" "Hostname not found in /etc/hosts"
            return $MODULE_ERROR
        fi
    fi

    module_log "DEBUG" "Hostname verification successful"
    return $MODULE_SUCCESS
}

# =============================================================================
# Optional Functions
# =============================================================================

module_pre_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running pre-installation for module: $module_name"

    # Check if hostname command is available
    if ! command_exists hostname; then
        module_log "ERROR" "hostname command not available"
        return $MODULE_ERROR
    fi

    # Check if we have permission to change hostname
    if [[ $EUID -ne 0 ]]; then
        module_log "ERROR" "Root privileges required to change hostname"
        return $MODULE_PERMISSION_DENIED
    fi

    # Check if hostnamectl is available (preferred method)
    if command_exists hostnamectl; then
        module_log "DEBUG" "hostnamectl available, will use for hostname changes"
    else
        module_log "WARN" "hostnamectl not available, using alternative methods"
    fi

    return $MODULE_SUCCESS
}

module_post_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running post-installation for module: $module_name"

    # Display hostname information
    display_hostname_info

    # Check if services need to be restarted
    check_service_dependencies

    return $MODULE_SUCCESS
}

module_rollback() {
    local module_name
    module_name=$(module_get_name)

    module_log "WARN" "Rolling back module: $module_name"

    # Restore backup configuration if available
    local backup_dir="${SERVERSH_STATE_DIR}/backups/${module_name}"
    local hosts_backup="$backup_dir/hosts.backup."
    local hostname_backup="$backup_dir/hostname.backup."

    # Find the most recent backups
    local latest_hosts_backup
    latest_hosts_backup=$(find "$backup_dir" -name "hosts.backup.*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)

    if [[ -n "$latest_hosts_backup" && -f "$latest_hosts_backup" ]]; then
        module_log "INFO" "Restoring /etc/hosts from backup"
        cp "$latest_hosts_backup" /etc/hosts
    fi

    # Try to get original hostname from backup or system
    local original_hostname=""
    if [[ -f "$hostname_backup" ]]; then
        original_hostname=$(cat "$hostname_backup" 2>/dev/null)
    fi

    if [[ -n "$original_hostname" ]]; then
        module_log "INFO" "Restoring hostname to: $original_hostname"
        set_hostname "$original_hostname"
    fi

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

backup_hostname_config() {
    module_log "DEBUG" "Creating backup of hostname configuration"

    local backup_dir="${SERVERSH_STATE_DIR}/backups/${module_name}"
    ensure_dir "$backup_dir"

    # Backup /etc/hosts
    if [[ -f /etc/hosts ]]; then
        local hosts_backup
        hosts_backup=$(backup_file "/etc/hosts")
        module_log "DEBUG" "Backed up /etc/hosts to: $hosts_backup"
    fi

    # Backup current hostname
    local current_hostname
    current_hostname=$(hostname)
    echo "$current_hostname" > "${backup_dir}/hostname.backup.$(date +%Y%m%d_%H%M%S)"
    module_log "DEBUG" "Backed up current hostname: $current_hostname"

    return $MODULE_SUCCESS
}

set_hostname() {
    local new_hostname="$1"

    module_log "INFO" "Setting hostname to: $new_hostname"

    # Method 1: Use hostnamectl (preferred for modern systems)
    if command_exists hostnamectl; then
        module_log "DEBUG" "Using hostnamectl to set hostname"
        if ! hostnamectl set-hostname "$new_hostname"; then
            module_log "ERROR" "hostnamectl failed"
            return $MODULE_ERROR
        fi
    else
        # Method 2: Use hostname command (fallback)
        module_log "DEBUG" "Using hostname command to set hostname"
        if ! hostname "$new_hostname"; then
            module_log "ERROR" "hostname command failed"
            return $MODULE_ERROR
        fi

        # Method 3: Update /etc/hostname directly (fallback)
        echo "$new_hostname" > /etc/hostname
        module_log "DEBUG" "Updated /etc/hostname directly"
    fi

    return $MODULE_SUCCESS
}

update_hosts_file() {
    local hostname="$1"
    local fqdn="${2:-}"

    module_log "DEBUG" "Updating /etc/hosts file for hostname: $hostname"

    # Backup /etc/hosts first
    local hosts_backup
    hosts_backup=$(backup_file "/etc/hosts")

    # Create temporary file for new hosts content
    local temp_hosts
    temp_hosts=$(temp_file "hosts")

    # Copy current hosts file, excluding any existing entries for this hostname
    while IFS= read -r line; do
        # Skip lines that contain the new hostname
        if [[ "$line" =~ $hostname ]]; then
            module_log "DEBUG" "Skipping line with hostname: $line"
            continue
        fi
        echo "$line" >> "$temp_hosts"
    done < /etc/hosts

    # Add new hostname entries
    if [[ -n "$fqdn" ]]; then
        # Add both FQDN and short hostname
        echo "127.0.1.1       $fqdn $hostname" >> "$temp_hosts"
        module_log "DEBUG" "Added FQDN entry: 127.0.1.1       $fqdn $hostname"
    else
        # Add short hostname only
        echo "127.0.1.1       $hostname" >> "$temp_hosts"
        module_log "DEBUG" "Added hostname entry: 127.0.1.1       $hostname"
    fi

    # Ensure localhost entries exist
    if ! grep -q "127.0.0.1.*localhost" "$temp_hosts"; then
        echo "127.0.0.1       localhost localhost.localdomain" >> "$temp_hosts"
    fi

    if ! grep -q "::1.*localhost" "$temp_hosts"; then
        echo "::1             localhost localhost.localdomain" >> "$temp_hosts"
    fi

    # Replace original hosts file
    if ! mv "$temp_hosts" /etc/hosts; then
        module_log "ERROR" "Failed to update /etc/hosts"
        rm -f "$temp_hosts"
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "Successfully updated /etc/hosts"
    return $MODULE_SUCCESS
}

validate_hostname_change() {
    local expected_hostname="$1"

    module_log "DEBUG" "Validating hostname change to: $expected_hostname"

    # Wait a moment for system to update
    sleep 2

    # Check hostname command output
    local current_hostname
    current_hostname=$(hostname)

    if [[ "$current_hostname" != "$expected_hostname" ]]; then
        module_log "ERROR" "Hostname validation failed"
        module_log "ERROR" "  Expected: $expected_hostname"
        module_log "ERROR" "  Current: $current_hostname"
        return $MODULE_ERROR
    fi

    # Check hostnamectl if available
    if command_exists hostnamectl; then
        local hostnamectl_hostname
        hostnamectl_hostname=$(hostnamectl --static)

        if [[ "$hostnamectl_hostname" != "$expected_hostname" ]]; then
            module_log "ERROR" "hostnamectl validation failed"
            module_log "ERROR" "  Expected: $expected_hostname"
            module_log "ERROR" "  hostnamectl: $hostnamectl_hostname"
            return $MODULE_ERROR
        fi
    fi

    module_log "DEBUG" "Hostname change validation successful"
    return $MODULE_SUCCESS
}

display_hostname_info() {
    local hostname
    hostname=$(module_config_get "hostname")
    local fqdn
    fqdn=$(module_config_get "fqdn" "")

    module_log "INFO" "Hostname Configuration Summary:"
    module_log "INFO" "  Hostname: $hostname"

    if [[ -n "$fqdn" ]]; then
        module_log "INFO" "  FQDN: $fqdn"
    fi

    module_log "INFO" "  System hostname: $(hostname)"

    if command_exists hostnamectl; then
        module_log "INFO" "  Static hostname: $(hostnamectl --static)"
        module_log "INFO" "  Pretty hostname: $(hostnamectl --pretty)"
    fi

    # Show network information
    local local_ip
    local_ip=$(get_local_ip)
    if [[ -n "$local_ip" ]]; then
        module_log "INFO" "  Local IP: $local_ip"
    fi
}

check_service_dependencies() {
    module_log "DEBUG" "Checking for services that might need restart"

    # Common services that might need restart after hostname change
    local services=("sshd" "networking" "systemd-networkd" "NetworkManager")

    for service in "${services[@]}"; do
        if is_service_running "$service"; then
            module_log "INFO" "Service '$service' is running and might need restart"

            # Note: We don't automatically restart services as it might
            # disconnect users. This is just informational.
        fi
    done

    module_log "INFO" "Consider restarting network-dependent services"
    module_log "INFO" "A system reboot is recommended to ensure all services use the new hostname"
}

# DNS validation function
validate_dns_resolution() {
    local hostname="$1"
    local fqdn="${2:-}"

    module_log "DEBUG" "Validating DNS resolution for: $hostname"

    # Test local resolution
    if getent hosts "$hostname" >/dev/null 2>&1; then
        module_log "DEBUG" "Local hostname resolution successful"
    else
        module_log "WARN" "Local hostname resolution failed"
    fi

    # Test FQDN resolution if provided
    if [[ -n "$fqdn" ]]; then
        if getent hosts "$fqdn" >/dev/null 2>&1; then
            module_log "DEBUG" "FQDN resolution successful"
        else
            module_log "WARN" "FQDN resolution failed"
        fi
    fi

    return $MODULE_SUCCESS
}

# Check if hostname is already configured correctly
check_hostname_status() {
    local expected_hostname
    expected_hostname=$(module_config_get "hostname")
    local current_hostname
    current_hostname=$(hostname)

    if [[ "$current_hostname" == "$expected_hostname" ]]; then
        module_log "INFO" "Hostname is already correctly set: $expected_hostname"
        return $MODULE_SKIP
    fi

    return $MODULE_SUCCESS
}

# Initialize module (optional - called when module is sourced)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    module_log "DEBUG" "Hostname configuration module loaded"
fi

return $MODULE_SUCCESS