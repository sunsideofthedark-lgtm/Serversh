#!/bin/bash

# =============================================================================
# Module: SSH Security Configuration (Interactive)
# Category: Security
# Description: Hardens SSH with interactive port selection and security options
# Version: 1.0.0
# =============================================================================

# Source module interface
source "${SERVERSH_LIB_DIR}/module_interface.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Required Functions
# =============================================================================

module_get_name() {
    echo "security/ssh_interactive"
    return $MODULE_SUCCESS
}

module_get_version() {
    echo "1.0.0"
    return $MODULE_SUCCESS
}

module_get_description() {
    echo "Interactive SSH security configuration with port scanning and user selection"
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
    local scan_ports
    scan_ports=$(module_config_get "scan_ports" "true")
    auto_select_port
    auto_select_port=$(module_config_get "auto_select_port" "false")
    local preferred_port
    preferred_port=$(module_config_get "preferred_port" "2222")

    # Validate boolean options
    for option in "password_auth" "root_login" "scan_ports" "auto_select_port"; do
        local value
        value=$(module_config_get "$option")
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

    # Validate preferred port if provided
    if [[ -n "$preferred_port" ]]; then
        if ! is_valid_port "$preferred_port"; then
            module_log "ERROR" "Invalid preferred_port: $preferred_port"
            return $MODULE_CONFIG_ERROR
        fi
    fi

    # Validate allowed groups
    if [[ -z "$allowed_groups" ]]; then
        module_log "ERROR" "allowed_groups cannot be empty"
        return $MODULE_CONFIG_ERROR
    fi

    module_log "DEBUG" "Configuration validation passed"
    module_log "DEBUG" "  scan_ports: $scan_ports"
    module_log "DEBUG" "  auto_select_port: $auto_select_port"
    module_log "DEBUG" "  preferred_port: $preferred_port"
    module_log "DEBUG" "  password_auth: $password_auth"
    module_log "DEBUG"   root_login: $root_login"
    module_log "DEBUG"   allowed_groups: $allowed_groups"
    module_log "DEBUG" "  max_auth_tries: $max_auth_tries"
    module_log "DEBUG"   client_alive_interval: $client_alive_interval"

    return $MODULE_SUCCESS
}

module_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Installing module: $module_name"
    module_log "INFO" "Interactive SSH security configuration"

    # Get configuration
    local ssh_config_file="/etc/ssh/sshd_config"
    local scan_ports
    scan_ports=$(module_config_get "scan_ports" "true")
    local auto_select_port
    auto_select_port=$(module_config_get "auto_select_port" "false")
    local preferred_port
    preferred_port=$(module_config_get "preferred_port" "2222")

    # Interactive port selection
    local ssh_port
    if [[ "$scan_ports" == "true" ]]; then
        ssh_port=$(select_ssh_port_interactive "$preferred_port" "$auto_select_port")
    else
        ssh_port="$preferred_port"
    fi

    if [[ -z "$ssh_port" ]]; then
        module_log "ERROR" "No SSH port selected"
        return $MODULE_ERROR
    fi

    module_log "INFO" "Selected SSH port: $ssh_port"

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

    # Verify port availability
    if ! verify_port_availability "$ssh_port"; then
        module_log "ERROR" "Port $ssh_port is not available for use"
        return $MODULE_ERROR
    fi

    # Apply SSH hardening configuration
    if ! apply_ssh_hardening_interactive "$ssh_port"; then
        module_log "ERROR" "Failed to apply SSH hardening"
        return $MODULE_ERROR
    fi

    # Validate SSH configuration
    if ! validate_ssh_config; then
        module_log "ERROR" "SSH configuration validation failed"
        return $MODULE_ERROR
    fi

    # Show configuration summary before restart
    show_ssh_configuration_summary "$ssh_port"

    # Ask for confirmation before restart
    if ! confirm_ssh_restart; then
        module_log "INFO" "SSH configuration cancelled by user"
        return $MODULE_SKIP
    fi

    # Restart SSH service
    if ! restart_ssh_service; then
        module_log "ERROR" "Failed to restart SSH service"
        return $MODULE_ERROR
    fi

    # Wait for service to start
    sleep 3

    # Verify SSH service is running on new port
    if ! verify_ssh_service "$ssh_port"; then
        module_log "ERROR" "SSH service verification failed"
        return $MODULE_ERROR
    fi

    module_log "SUCCESS" "Interactive SSH security configuration completed"
    module_log "INFO" "SSH is now running on port $ssh_port with enhanced security"

    # Show connection instructions
    show_final_connection_instructions "$ssh_port"

    return $MODULE_SUCCESS
}

module_verify() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Verifying SSH interactive configuration: $module_name"

    # Get the actual port being used (from state or config)
    local ssh_port
    ssh_port=$(state_get "ssh_port" "$(module_config_get "preferred_port" "2222")")

    # Check if SSH is running on configured port
    if ! is_port_open "$ssh_port"; then
        module_log "ERROR" "SSH is not accessible on port $ssh_port"
        return $MODULE_ERROR
    fi

    # Verify SSH configuration values
    local ssh_config_file="/etc/ssh/sshd_config"
    if ! grep -q "^Port $ssh_port$" "$ssh_config_file"; then
        module_log "ERROR" "SSH port not properly configured"
        return $MODULE_ERROR
    fi

    # Verify other security settings
    local password_auth
    password_auth=$(module_config_get "password_authentication" "false")
    local root_login
    root_login=$(module_config_get "permit_root_login" "false")

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

    module_log "DEBUG" "SSH interactive configuration verification successful"
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
    end

    # Check if required tools are available
    local required_tools=("ss" "netstat" "timeout")
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            module_log "WARN" "Tool $tool not available, some features may be limited"
        fi
    done

    # Get configuration
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

    # Store selected port in state
    local ssh_port
    ssh_port=$(state_get "ssh_port" "$(module_config_get "preferred_port" "2222")")
    state_set "ssh_port" "$ssh_port"

    # Show final summary
    show_final_summary

    return $MODULE_SUCCESS
}

module_rollback() {
    local module_name
    module_name=$(module_get_name)

    module_log "WARN" "Rolling back SSH interactive configuration: $module_name"

    # Restore backup SSH configuration
    local backup_dir="${SERVERSH_STATE_DIR}/backups/${module_name}"
    local latest_backup
    latest_backup=$(find "$backup_dir" -name "sshd_config.backup.*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)

    if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
        module_log "INFO" "Restoring SSH configuration from backup"
        cp "$latest_backup" /etc/ssh/sshd_config

        # Restart SSH service
        restart_ssh_service

        # Clear port from state
        state_set "ssh_port" "22"

        module_log "INFO" "SSH configuration restored from backup (port 22)"
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
    rm -f "${SERVERSH_STATE_DIR}/port_scan_*.tmp" 2>/dev/null || true

    return $MODULE_SUCCESS
}

# =============================================================================
# Interactive Port Selection Functions
# =============================================================================

select_ssh_port_interactive() {
    local preferred_port="$1"
    local auto_select="$2"

    module_log "INFO" "Starting interactive SSH port selection"
    module_log "INFO" "Preferred port: $preferred_port"

    # First, check if preferred port is available
    if check_port_quickly "$preferred_port"; then
        if [[ "$auto_select" == "true" ]]; then
            module_log "INFO" "Auto-selecting preferred port: $preferred_port"
            echo "$preferred_port"
            return $MODULE_SUCCESS
        else
            echo "✅ Preferred port $preferred_port is available!"
            if confirm_ssh_port_choice "$preferred_port" "Use preferred port $preferred_port?"; then
                echo "$preferred_port"
                return $MODULE_SUCCESS
            fi
        fi
    else
        module_log "INFO" "Preferred port $preferred_port is not available"
    fi

    # Scan for available ports
    echo ""
    echo "🔍 Scanning for available SSH ports..."
    echo ""

    local available_ports
    available_ports=($(scan_available_ports))

    if [[ ${#available_ports[@]} -eq 0 ]]; then
        module_log "ERROR" "No available SSH ports found"
        return $MODULE_ERROR
    fi

    echo "✅ Found ${#available_ports[@]} available SSH ports:"
    echo ""
    printf "%-8s %s\n" "Port" "Status"
    echo "-------- ------"

    for port in "${available_ports[@]}; do
        local status="Available"
        if [[ "$port" == "2222" ]]; then
            status="Recommended ⭐"
        elif [[ "$port" == "22" ]]; then
            status="Standard (Not Recommended)"
        elif [[ "$port" -ge 8000 && "$port" -le 8999 ]]; then
            status="High Range (Good)"
        elif [[ "$port" -ge 9000 && "$port" -le 9999 ]]; then
            status="Very High (Avoid)"
        else
            status="Available"
        fi
        printf "%-8d %s\n" "$port" "$status"
    done

    echo ""
    echo "Port Selection Options:"
    echo "1.  Use recommended port (2222)"
    echo "2.  Choose from available ports"
    echo "3.  Enter custom port"
    echo "4.  Scan again"
    echo "5.  Cancel"

    while true; do
        echo ""
        echo -n "Enter your choice (1-5): "
        read -r choice

        case "$choice" in
            1)
                if array_contains "2222" "${available_ports[@]}"; then
                    echo "2222"
                    return $MODULE_SUCCESS
                else
                    echo "❌ Port 2222 is not available"
                fi
                ;;
            2)
                select_from_available_ports "${available_ports[@]}"
                ;;
            3)
                select_custom_port
                ;;
            4)
                echo "🔄 Rescanning ports..."
                available_ports=($(scan_available_ports))
                if [[ ${#available_ports[@]} -eq 0 ]]; then
                    echo "❌ No available ports found"
                    return $MODULE_ERROR
                fi
                echo "✅ Found ${#available_ports[@]} available ports:"
                for port in "${available_ports[@]}"; do
                    echo "  - $port"
                done
                ;;
            5)
                echo "❌ Port selection cancelled"
                return $MODULE_ERROR
                ;;
            *)
                echo "❌ Invalid choice. Please enter 1-5."
                ;;
        esac
    done
}

scan_available_ports() {
    local port_ranges=("2000-2999" "4000-4999" "5000-5999" "7000-7999" "8000-8999" "9000-9999" "10000-10999" "12000-12999" "14000-14999" "15000-15999" "22000-22999" "23000-23999" "24000-24999" "25000-25999")
    local available_ports=()
    local scan_results="${SERVERSH_STATE_DIR}/port_scan_results.tmp"

    # Create temporary scan results file
    > "$scan_results"

    echo "Scanning port ranges..."
    local total_checked=0

    for range in "${port_ranges[@]}"; do
        local start_port
        local end_port
        start_port="${range%-*}"
        end_port="${range#*-}"

        echo "  Scanning ports $start_port-$end_port..."

        for ((port = start_port; port <= end_port; port++)); do
            total_checked=$((total_checked + 1))

            # Progress indicator every 50 ports
            if ((total_checked % 50 == 0)); then
                echo -ne "\r  Scanned $total_checked ports..." >&2
            fi

            if check_port_quickly "$port"; then
                available_ports+=("$port")
                echo "$port" >> "$scan_results"
            fi
        done
    done

    echo -e "\r✅ Scanned $total_checked ports" >&2
    echo "Found ${#available_ports[@]} available ports"

    # Clean up scan results
    rm -f "$scan_results"

    # Sort ports numerically
    IFS=$'\n' read -d '' sorted_ports < <(printf '%s\n' "${available_ports[@]}" | sort -n)
    available_ports=("${sorted_ports[@]}")

    # Remove duplicates
    local unique_ports=()
    local seen_ports=()
    for port in "${available_ports[@]}"; do
        if ! array_contains "$port" "${seen_ports[@]}"; then
            unique_ports+=("$port")
            seen_ports+=("$port")
        fi
    done

    echo "${unique_ports[@]}"
}

check_port_quickly() {
    local port="$1"

    # Quick check with timeout
    if timeout 1 bash -c "</dev/tcp/localhost/$port" 2>/dev/null; then
        return 1  # Port is in use
    else
        return 0  # Port is available
    fi
}

select_from_available_ports() {
    local ports=("$@")

    echo ""
    echo "Available SSH Ports:"
    echo "=================="

    # Display ports with numbers
    local counter=1
    local port_map=()

    for port in "${ports[@]}"; do
        port_map+=("$counter:$port")
        echo "  $counter. Port $port"
        ((counter++))
    done

    echo ""
    echo "Enter the number of your choice (or 0 to cancel): "
    read -r selection

    if [[ "$selection" == "0" ]]; then
        return $MODULE_ERROR
    fi

    # Validate selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 && $selection -lt ${#ports[@]} ]]; then
        local selected_port="${ports[$((selection - 1))]}"
        echo "✅ Selected port: $selected_port"
        echo "$selected_port"
        return $MODULE_SUCCESS
    else
        echo "❌ Invalid selection: $selection"
        return $MODULE_ERROR
    fi
}

select_custom_port() {
    while true; do
        echo ""
        echo "Enter custom SSH port (1024-65535): "
        read -r custom_port

        if [[ "$custom_port" =~ ^[qQ] ]]; then
            return $MODULE_ERROR
        fi

        if [[ "$custom_port" =~ ^[0-9]+$ ]]; then
            if is_valid_port "$custom_port"; then
                if check_port_quickly "$custom_port"; then
                    echo "✅ Port $custom_port is available"
                    echo "$custom_port"
                    return $MODULE_SUCCESS
                else
                    echo "❌ Port $custom_port is already in use"
                fi
            else
                echo "❌ Invalid port number. Please enter a number between 1024 and 65535."
            fi
        else
            echo "❌ Invalid input. Please enter a number between 1024 and 65535."
        fi
    done
}

confirm_ssh_port_choice() {
    local port="$1"
    local message="$2"

    echo ""
    echo "$message"
    echo "Port $port will be configured for SSH access."
    echo ""
    echo "⚠️  IMPORTANT: Make sure you can access this port!"
    echo "   - Check firewall rules"
    echo "   - Verify network connectivity"
    echo   - Ensure port is open in your security groups"
    echo ""
    if confirm "Are you sure you want to use port $port for SSH?"; then
        return 0
    else
        return 1
    fi
}

confirm_ssh_restart() {
    echo ""
    echo "⚠️  SSH service will be restarted on the new port."
    echo "   This will disconnect any current SSH sessions."
    echo "   Make sure you have another way to access the server!"
    echo ""
    if confirm "Do you want to restart SSH service now?"; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Enhanced Configuration Functions
# =============================================================================

verify_port_availability() {
    local port="$1"

    module_log "DEBUG" "Verifying port availability: $port"

    # Check if port is already in use
    if ! check_port_quickly "$port"; then
        module_log "ERROR" "Port $port is already in use"
        return $MODULE_ERROR
    fi

    # Additional check with netstat/ss if available
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

    # Check if it's a common service port
    local common_ports=(80 443 8080 8443 3306 5432 6379)
    for common_port in "${common_ports[@]}"; do
        if [[ "$port" == "$common_port" ]]; then
            module_log "WARN" "Port $port is commonly used by other services"
            break
        fi
    done

    module_log "DEBUG" "Port $port is available for use"
    return $MODULE_SUCCESS
}

apply_ssh_hardening_interactive() {
    local ssh_port="$1"
    local ssh_config_file="/etc/ssh/sshd_config"

    module_log "INFO" "Applying SSH hardening configuration for port $ssh_port"

    # Get other configuration options
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

    # Create new SSH configuration
    local temp_config
    temp_config=$(temp_file "sshd_config_interactive")

    cat > "$temp_config" << EOF
# SSH Configuration - Interactive Setup by ServerSH
# Generated at: $(timestamp)
# SSH Port: $ssh_port

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

show_ssh_configuration_summary() {
    local ssh_port="$1"
    local password_auth
    password_auth=$(module_config_get "password_authentication" "false")
    local root_login
    root_login=$(module_config_get "permit_root_login" "false")
    local admin_user
    admin_user=$(module_config_get "admin_user" "")
    local allowed_groups
    allowed_groups=$(module_config_get "allowed_groups" "remotessh")

    echo ""
    echo "🔒 SSH Configuration Summary"
    echo "=========================="
    echo "SSH Port: $ssh_port"
    echo ""
    echo "Security Settings:"
    echo "  Password Authentication: $password_auth"
    echo "  Root Login: $root_login"
    echo "  Allowed Groups: $allowed_groups"
    echo "  Max Auth Tries: $max_auth_tries"
    echo "  Session Timeout: ${client_alive_interval}s"
    echo ""
    echo "Access Information:"
    echo "  SSH Access User: $admin_user"
    echo "  SSH Access Group: $allowed_groups"
    echo ""
    echo "📋 This configuration will be applied to /etc/ssh/sshd_config"
}

show_final_connection_instructions() {
    local ssh_port="$1"
    local admin_user
    admin_user=$(module_config_get "admin_user" "")
    local current_ip
    current_ip=$(get_public_ip 2>/dev/null || echo "<SERVER_IP>")

    echo ""
    echo "🚀 SSH Connection Instructions"
    echo "=========================="
    echo ""
    echo "✅ SSH successfully configured on port $ssh_port!"
    echo ""
    echo "To connect to this server, use:"
    echo ""
    echo "ssh -i /path/to/private/key -p $ssh_port $admin_user@$current_ip"
    echo ""
    echo "Replace:"
    echo "  - /path/to/private/key with your SSH private key path"
    echo "  - <SERVER_IP> with the server's actual IP address"
    echo ""
    echo "⚠️  IMPORTANT Connection Notes:"
    echo "  - Old SSH connections on port 22 will no longer work"
    echo "  - Only users in the '$allowed_groups' group can SSH"
    echo "  - Password authentication is disabled"
    echo "  - Root login is disabled"
    echo "  - Test your connection BEFORE disconnecting!"
    echo ""
    echo "🔍 Testing Connectivity:"
    echo "  - From another terminal: ssh -i key -p $ssh_port $admin_user@localhost"
    echo "  - Or test with: nc -zv $ssh_port localhost"
    echo ""
}

show_final_summary() {
    local ssh_port
    ssh_port=$(state_get "ssh_port" "unknown")

    echo ""
    echo "🎉 SSH Security Configuration Complete!"
    echo "================================"
    echo "✅ SSH port: $ssh_port"
    echo "✅ Password authentication: Disabled"
    echo "✅ Root login: Disabled"
    echo "✅ Group-based access control: Enabled"
    echo "✅ Enhanced security options: Applied"
    echo ""
    echo "📋 Next Steps:"
    echo "  1. Test your SSH connection with the new port"
    echo "  2. Verify all security features are working"
    echo "  3. Consider setting up additional security tools"
    echo ""
}

# =============================================================================
# Additional Interactive Features
# =============================================================================

create_ssh_banner() {
    local banner_file="/etc/ssh/banner.txt"

    module_log "INFO" "Creating SSH login banner"

    cat > "$banner_file" << EOF
***************************************************************************
                  SECURE SSH SERVER ACCESS ONLY
***************************************************************************

This system is for authorized users only.

⚠️  SECURITY NOTICE:
- All connections are logged and monitored
- Unauthorized access attempts will be reported
- System security policies are strictly enforced

🔐  SSH Configuration:
- Port: $(state_get "ssh_port" "unknown")
- Key Authentication Only
- Root Access Disabled
- Session Monitoring Enabled

✅  ACCESS LOGGED
- Connection timestamps
- Source IP addresses
- Authentication attempts
- Command execution logs

For technical support, contact your system administrator.
***************************************************************************
EOF

    chmod 644 "$banner_file"

    # Add banner to SSH config
    local ssh_config_file="/etc/ssh/sshd_config"
    echo "Banner $banner_file" >> "$ssh_config_file"

    module_log "INFO" "SSH login banner created"
}

configure_fail2ban_ssh() {
    module_log "INFO" "Configuring Fail2Ban for SSH protection"

    local fail2ban_jail="/etc/fail2ban/jail.d/sshd.conf"

    if [[ ! -d "/etc/fail2ban/jail.d" ]]; then
        module_log "WARN" "Fail2Ban not installed. Consider installing for additional protection."
        return $MODULE_SUCCESS
    fi

    local ssh_port
    ssh_port=$(state_get "ssh_port" "2222")

    cat > "$fail2ban_jail" << EOF
[sshd]
enabled = true
port = $ssh_port
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

    # Restart fail2ban if running
    if is_service_running "fail2ban"; then
        systemctl restart fail2ban
        module_log "INFO" "Fail2Ban service restarted for SSH protection"
    fi

    module_log "INFO" "Fail2Ban configured for SSH protection"
}

# Initialize module (optional - called when module is sourced)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    module_log "DEBUG" "Interactive SSH security module loaded"
fi

return $MODULE_SUCCESS