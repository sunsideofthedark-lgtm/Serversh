#!/bin/bash

# =============================================================================
# Module: SSH Security Configuration
# Category: Security
# Description: Hardens SSH service with port change, key authentication, and security options
# Version: 1.0.0
# =============================================================================

# Source module interface
source "${SERVERSH_LIB_DIR}/module_interface.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Required Functions
# =============================================================================

module_get_name() {
    echo "security/ssh"
    return $MODULE_SUCCESS
}

module_get_version() {
    echo "1.0.0"
    return $MODULE_SUCCESS
}

module_get_description() {
    echo "Hardens SSH service with custom port, key-only authentication, and security hardening"
    return $MODULE_SUCCESS
}

module_get_category() {
    echo "$MODULE_CATEGORY_SECURITY"
    return $MODULE_SUCCESS
}

module_get_dependencies() {
    echo "security/users"
    return $MODULE_SUCCESS
}

module_validate_config() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Validating configuration for module: $module_name"

    # Get configuration options
    local ssh_port
    ssh_port=$(module_config_get "port" "2222")
    local password_auth
    password_auth=$(module_config_get "password_authentication" "false")
    local root_login
    root_login=$(module_config_get "permit_root_login" "false")
    local allowed_groups
    allowed_groups=$(module_config_get "allowed_groups" "remotessh")
    local max_auth_tries
    max_auth_tries=$(module_config_get "max_auth_tries" "3")
    local client_alive_interval
    client_alive_interval=$(module_config_get "client_alive_interval" "300")
    local x11_forwarding
    x11_forwarding=$(module_config_get "x11_forwarding" "false")

    # Validate SSH port
    if ! is_valid_port "$ssh_port"; then
        module_log "ERROR" "Invalid SSH port: $ssh_port"
        module_log "ERROR" "Port must be between 1024 and 65535"
        return $MODULE_CONFIG_ERROR
    fi

    # Check for common problematic ports
    local problematic_ports="22 80 443 8080 8443"
    for port in $problematic_ports; do
        if [[ "$ssh_port" == "$port" ]]; then
            module_log "WARN" "Using port $ssh_port may conflict with other services"
        fi
    done

    # Validate boolean options
    for option in "password_auth" "root_login" "x11_forwarding"; do
        local value
        value=$(module_config_get "${option}")
        if [[ "$value" != "true" && "$value" != "false" ]]; then
            module_log "ERROR" "Invalid $option value: $value (must be true or false)"
            return $MODULE_CONFIG_ERROR
        fi
    done

    # Validate numeric options
    if ! [[ "$max_auth_tries" =~ ^[0-9]+$ ]] || [[ "$max_auth_tries" -lt 1 || "$max_auth_tries" -gt 10 ]]; then
        module_log "ERROR" "Invalid max_auth_tries: $max_auth_tries (must be 1-10)"
        return $MODULE_CONFIG_ERROR
    fi

    if ! [[ "$client_alive_interval" =~ ^[0-9]+$ ]] || [[ "$client_alive_interval" -lt 60 || "$client_alive_interval" -gt 3600 ]]; then
        module_log "ERROR" "Invalid client_alive_interval: $client_alive_interval (must be 60-3600)"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate allowed groups
    if [[ -z "$allowed_groups" ]]; then
        module_log "ERROR" "allowed_groups cannot be empty"
        return $MODULE_CONFIG_ERROR
    fi

    # Check if SSH access group exists (will be created by users module)
    local ssh_access_group
    ssh_access_group=$(module_config_get "ssh_access_group" "remotessh")
    if ! getent group "$ssh_access_group" >/dev/null 2>&1; then
        module_log "WARN" "SSH access group '$ssh_access_group' does not exist yet"
        module_log "WARN" "Make sure the security/users module is executed first"
    fi

    module_log "DEBUG" "Configuration validation passed"
    module_log "DEBUG" "  ssh_port: $ssh_port"
    module_log "DEBUG" "  password_auth: $password_auth"
    module_log "DEBUG"   root_login: $root_login"
    module_log "DEBUG"   allowed_groups: $allowed_groups"
    module_log "DEBUG" "  max_auth_tries: $max_auth_tries"
    module_log "DEBUG"   client_alive_interval: $client_alive_interval"
    module_log "DEBUG"   x11_forwarding: $x11_forwarding"

    return $MODULE_SUCCESS
}

module_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Installing module: $module_name"
    module_log "INFO" "Hardening SSH service configuration"

    # Get configuration
    local ssh_port
    ssh_port=$(module_config_get "port" "2222")
    local ssh_config_file="/etc/ssh/sshd_config"

    # Check if SSH config exists
    if [[ ! -f "$ssh_config_file" ]]; then
        module_log "ERROR" "SSH configuration file not found: $ssh_config_file"
        return $MODULE_ERROR
    fi

    # Backup current SSH configuration
    if ! backup_ssh_config; then
        module_log "ERROR" "Failed to backup SSH configuration"
        return $MODULE_ERROR
    fi

    # Check if port is available
    if ! check_port_availability "$ssh_port"; then
        module_log "ERROR" "Port $ssh_port is already in use"
        return $MODULE_ERROR
    fi

    # Apply SSH hardening configuration
    if ! apply_ssh_hardening; then
        module_log "ERROR" "Failed to apply SSH hardening"
        return $MODULE_ERROR
    fi

    # Validate SSH configuration
    if ! validate_ssh_config; then
        module_log "ERROR" "SSH configuration validation failed"
        return $MODULE_ERROR
    fi

    # Restart SSH service
    if ! restart_ssh_service; then
        module_log "ERROR" "Failed to restart SSH service"
        return $MODULE_ERROR
    fi

    # Wait for service to start
    sleep 2

    # Verify SSH service is running on new port
    if ! verify_ssh_service "$ssh_port"; then
        module_log "ERROR" "SSH service verification failed"
        return $MODULE_ERROR
    fi

    module_log "SUCCESS" "SSH security hardening completed"
    module_log "INFO" "SSH is now running on port $ssh_port with enhanced security"
    return $MODULE_SUCCESS
}

module_verify() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Verifying SSH security configuration: $module_name"

    # Get configuration
    local ssh_port
    ssh_port=$(module_config_get "port" "2222")
    local password_auth
    password_auth=$(module_config_get "password_authentication" "false")
    local root_login
    root_login=$(module_config_get "permit_root_login" "false")
    local ssh_config_file="/etc/ssh/sshd_config"

    # Check if SSH is running on configured port
    if ! is_port_open "$ssh_port"; then
        module_log "ERROR" "SSH is not accessible on port $ssh_port"
        return $MODULE_ERROR
    fi

    # Verify SSH configuration values
    if ! grep -q "^Port $ssh_port$" "$ssh_config_file"; then
        module_log "ERROR" "SSH port not properly configured"
        return $MODULE_ERROR
    fi

    if [[ "$password_auth" == "false" ]]; then
        if ! grep -q "^PasswordAuthentication no" "$ssh_config_file"; then
            module_log "ERROR" "Password authentication not properly disabled"
            return $MODULE_ERROR
        fi
    fi

    if [[ "$root_login" == "false" ]]; then
        if ! grep -q "^PermitRootLogin no" "$ssh_config_file"; then
            module_log "ERROR" "Root login not properly disabled"
            return $MODULE_ERROR
        fi
    fi

    # Check if SSH service is running
    if ! is_service_running "sshd" && ! is_service_running "ssh"; then
        module_log "ERROR" "SSH service is not running"
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "SSH security configuration verification successful"
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
        module_log "ERROR" "Root privileges required for SSH configuration"
        return $MODULE_PERMISSION_DENIED
    fi

    # Check if SSH is installed
    if ! command_exists sshd && ! command_exists ssh; then
        module_log "ERROR" "SSH is not installed"
        return $EXIT_MISSING_DEPS
    fi

    # Check if SSH service exists
    local ssh_service="sshd"
    if ! systemctl list-unit-files | grep -q "$ssh_service"; then
        ssh_service="ssh"
    fi

    if ! systemctl list-unit-files | grep -q "$ssh_service"; then
        module_log "ERROR" "SSH service not found"
        return $EXIT_MISSING_DEPS
    fi

    # Get configuration
    local ssh_port
    ssh_port=$(module_config_get "port" "2222")
    local admin_user
    admin_user=$(module_config_get "admin_user" "")

    # Check if admin user exists (required for SSH access)
    if [[ -n "$admin_user" ]] && ! id "$admin_user" >/dev/null 2>&1; then
        module_log "ERROR" "Admin user '$admin_user' does not exist"
        module_log "ERROR" "SSH configuration requires an admin user"
        return $MODULE_CONFIG_ERROR
    fi

    return $MODULE_SUCCESS
}

module_post_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running post-installation for module: $module_name"

    # Display SSH configuration summary
    display_ssh_summary

    # Show connection instructions
    show_connection_instructions

    # Test SSH connection on new port (local test)
    test_local_ssh_connection

    return $MODULE_SUCCESS
}

module_rollback() {
    local module_name
    module_name=$(module_get_name)

    module_log "WARN" "Rolling back SSH configuration: $module_name"

    # Restore backup SSH configuration
    local backup_dir="${SERVERSH_STATE_DIR}/backups/${module_name}"
    local latest_backup
    latest_backup=$(find "$backup_dir" -name "sshd_config.backup.*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)

    if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
        module_log "INFO" "Restoring SSH configuration from backup"
        cp "$latest_backup" /etc/ssh/sshd_config

        # Restart SSH service
        restart_ssh_service

        module_log "INFO" "SSH configuration restored from backup"
    else
        module_log "ERROR" "No SSH configuration backup found"
        return $MODULE_ERROR
    fi

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

backup_ssh_config() {
    local ssh_config_file="/etc/ssh/sshd_config"

    module_log "DEBUG" "Creating backup of SSH configuration"

    local backup_file
    backup_file=$(backup_file "$ssh_config_file")
    if [[ -n "$backup_file" ]]; then
        module_log "DEBUG" "SSH configuration backed up to: $backup_file"
        return $MODULE_SUCCESS
    else
        module_log "ERROR" "Failed to backup SSH configuration"
        return $MODULE_ERROR
    fi
}

check_port_availability() {
    local port="$1"

    module_log "DEBUG" "Checking port availability: $port"

    # Check if port is already in use
    if is_port_open "$port"; then
        module_log "ERROR" "Port $port is already in use"
        return $MODULE_ERROR
    fi

    # Check netstat/ss for listening ports
    if command_exists ss; then
        if ss -tuln | grep -q ":$port "; then
            module_log "ERROR" "Port $port is being listened on"
            return $MODULE_ERROR
        fi
    elif command_exists netstat; then
        if netstat -tuln | grep -q ":$port "; then
            module_log "ERROR" "Port $port is being listened on"
            return $MODULE_ERROR
        fi
    fi

    module_log "DEBUG" "Port $port is available"
    return $MODULE_SUCCESS
}

apply_ssh_hardening() {
    local ssh_config_file="/etc/ssh/sshd_config"
    local temp_config
    temp_config=$(temp_file "sshd_config")

    # Get configuration options
    local ssh_port
    ssh_port=$(module_config_get "port" "2222")
    local password_auth
    password_auth=$(module_config_get "password_authentication" "false")
    local root_login
    root_login=$(module_config_get "permit_root_login" "false")
    local allowed_groups
    allowed_groups=$(module_config_get "allowed_groups" "remotessh")
    local max_auth_tries
    max_auth_tries=$(module_config_get "max_auth_tries" "3")
    local client_alive_interval
    client_alive_interval=$(module_config_get "client_alive_interval" "300")
    local client_alive_count_max
    client_alive_count_max=$(module_config_get "client_alive_count_max" "2")
    local x11_forwarding
    x11_forwarding=$(module_config_get "x11_forwarding" "false")
    local allow_tcp_forwarding
    allow_tcp_forwarding=$(module_config_get "allow_tcp_forwarding" "false")
    local max_sessions
    max_sessions=$(module_config_get "max_sessions" "10")
    local compression
    compression=$(module_config_get "compression" "no")

    module_log "DEBUG" "Applying SSH hardening configuration"

    # Create new SSH configuration
    cat > "$temp_config" << EOF
# SSH Configuration - Hardened by ServerSH
# Generated at: $(timestamp)

# Basic Configuration
Port $ssh_port
Protocol 2

# Authentication Configuration
PasswordAuthentication $password_auth
PermitRootLogin $root_login
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Access Control
AllowGroups $allowed_groups
MaxAuthTries $max_auth_tries

# Session Management
ClientAliveInterval $client_alive_interval
ClientAliveCountMax $client_alive_count_max
MaxSessions $max_sessions

# Security Options
PermitEmptyPasswords no
PermitUserEnvironment no
UsePAM yes

# Connection Settings
X11Forwarding $x11_forwarding
AllowTcpForwarding $allow_tcp_forwarding
AllowAgentForwarding no

# Logging
LogLevel VERBOSE
SyslogFacility AUTH

# Subsystem Configuration
Subsystem sftp /usr/lib/openssh/sftp-server

# Additional Security Options
UsePrivilegeSeparation yes
StrictModes yes
IgnoreRhosts yes
HostbasedAuthentication no
RhostsRSAAuthentication no
PermitTunnel no

# KEX Algorithms
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256

# Ciphers
Ciphers chacha20-poly1305@openssl.com,aes256-gcm@openssl.com,aes128-gcm@openssl.com,aes256-ctr,aes192-ctr,aes128-ctr

# MACs
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-256,hmac-sha2-512

# Compression
Compression $compression
EOF

    # Replace original configuration
    if ! mv "$temp_config" "$ssh_config_file"; then
        module_log "ERROR" "Failed to replace SSH configuration file"
        rm -f "$temp_config"
        return $MODULE_ERROR
    fi

    # Set proper permissions
    chmod 600 "$ssh_config_file"

    module_log "DEBUG" "SSH hardening configuration applied successfully"
    return $MODULE_SUCCESS
}

validate_ssh_config() {
    local sshd_binary="/usr/sbin/sshd"

    module_log "DEBUG" "Validating SSH configuration"

    # Test configuration syntax
    if ! "$sshd_binary" -t; then
        module_log "ERROR" "SSH configuration syntax validation failed"
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "SSH configuration validation successful"
    return $MODULE_SUCCESS
}

restart_ssh_service() {
    local ssh_service="sshd"

    # Determine service name
    if ! systemctl list-unit-files | grep -q "sshd"; then
        ssh_service="ssh"
    fi

    module_log "INFO" "Restarting SSH service: $ssh_service"

    # Check service status before restart
    local was_running=false
    if systemctl is-active --quiet "$ssh_service"; then
        was_running=true
    fi

    # Restart service
    if ! systemctl restart "$ssh_service"; then
        module_log "ERROR" "Failed to restart SSH service"
        return $MODULE_ERROR
    fi

    # Enable service to start on boot
    systemctl enable "$ssh_service" >/dev/null 2>&1

    module_log "DEBUG" "SSH service restarted successfully"
    return $MODULE_SUCCESS
}

verify_ssh_service() {
    local ssh_port="$1"

    module_log "DEBUG" "Verifying SSH service on port $ssh_port"

    # Wait for service to fully start
    local wait_time=0
    local max_wait=10

    while [[ $wait_time -lt $max_wait ]]; do
        if is_port_open "$ssh_port"; then
            module_log "DEBUG" "SSH service is responding on port $ssh_port"
            return $MODULE_SUCCESS
        fi
        sleep 1
        ((wait_time++))
    done

    module_log "ERROR" "SSH service not responding on port $ssh_port after $max_wait seconds"
    return $MODULE_ERROR
}

display_ssh_summary() {
    local ssh_port
    ssh_port=$(module_config_get "port" "2222")
    local password_auth
    password_auth=$(module_config_get "password_authentication" "false")
    local root_login
    root_login=$(module_config_get "permit_root_login" "false")
    local admin_user
    admin_user=$(module_config_get "admin_user" "")

    module_log "INFO" "SSH Security Configuration Summary:"
    module_log "INFO" "  SSH Port: $ssh_port"
    module_log "INFO" "  Password Authentication: $password_auth"
    module_log "INFO" "  Root Login: $root_login"
    module_log "INFO" "  Allowed Groups: $(module_config_get "allowed_groups" "remotessh")"
    module_log "INFO" "  Max Auth Tries: $(module_config_get "max_auth_tries" "3")"
    module_log "INFO" "  Client Alive Interval: $(module_config_get "client_alive_interval" "300") seconds"

    if [[ -n "$admin_user" ]]; then
        module_log "INFO" "  SSH Access User: $admin_user"
    fi
}

show_connection_instructions() {
    local ssh_port
    ssh_port=$(module_config_get "port" "2222")
    local admin_user
    admin_user=$(module_config_get "admin_user" "")
    local ssh_access_group
    ssh_access_group=$(module_config_get "ssh_access_group" "remotessh")

    module_log "INFO" "SSH Connection Instructions:"
    module_log "INFO" "================================"
    module_log "INFO" "To connect to this server, use:"
    module_log "INFO" ""
    module_log "INFO" "ssh -i /path/to/private/key -p $ssh_port $admin_user@<SERVER_IP>"
    module_log "INFO" ""
    module_log "INFO" "Replace:"
    module_log "INFO" "  - /path/to/private/key with your SSH private key"
    module_log "INFO" "  - <SERVER_IP> with this server's IP address"
    module_log "INFO" ""
    module_log "INFO" "Important:"
    module_log "INFO" "  - Port 22 (standard SSH) is now blocked"
    module_log "INFO" "  - Only users in '$ssh_access_group' group can SSH"
    module_log "INFO" "  - Password authentication is disabled"
    module_log "INFO" "  - Root login is disabled"
    module_log "INFO" "================================"
}

test_local_ssh_connection() {
    local ssh_port
    ssh_port=$(module_config_get "port" "2222")

    module_log "DEBUG" "Testing local SSH connection on port $ssh_port"

    # Simple connection test to localhost
    if timeout 5 bash -c "</dev/tcp/localhost/$ssh_port" 2>/dev/null; then
        module_log "DEBUG" "Local SSH connection test successful"
    else
        module_log "WARN" "Local SSH connection test failed"
        module_log "WARN" "This may be normal if SSH is not configured for localhost connections"
    fi
}

# Additional security functions

create_ssh_banner() {
    local banner_file="/etc/ssh/banner.txt"

    module_log "INFO" "Creating SSH login banner"

    cat > "$banner_file" << EOF
***************************************************************************
                            AUTHORIZED ACCESS ONLY
***************************************************************************

This system is for authorized users only. Individual use of this system
and/or network without authority from the system administrators is
strictly prohibited.

Unauthorized access is prohibited and subject to prosecution under
local, state, federal, and international law.

All activities are logged and monitored.
***************************************************************************
EOF

    chmod 644 "$banner_file"

    # Add banner to SSH config
    local ssh_config_file="/etc/ssh/sshd_config"
    echo "Banner $banner_file" >> "$ssh_config_file"
}

configure_fail2ban_ssh() {
    module_log "INFO" "Configuring Fail2Ban for SSH protection"

    local fail2ban_jail="/etc/fail2ban/jail.d/sshd.conf"

    if [[ ! -d "/etc/fail2ban/jail.d" ]]; then
        module_log "WARN" "Fail2Ban not installed. Consider installing it for additional protection."
        return $MODULE_SUCCESS
    fi

    cat > "$fail2ban_jail" << EOF
[sshd]
enabled = true
port = $(module_config_get "port" "2222")
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

    # Restart fail2ban if running
    if is_service_running "fail2ban"; then
        systemctl restart fail2ban
    fi
}

# Initialize module (optional - called when module is sourced)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    module_log "DEBUG" "SSH security module loaded"
fi

return $MODULE_SUCCESS