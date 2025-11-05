#!/bin/bash

# =============================================================================
# Module: Firewall Configuration
# Category: Security
# Description: Configures system firewall (UFW or firewalld) with security rules
# Version: 1.0.0
# =============================================================================

# Source module interface
source "${SERVERSH_LIB_DIR}/module_interface.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Required Functions
# =============================================================================

module_get_name() {
    echo "security/firewall"
    return $MODULE_SUCCESS
}

module_get_version() {
    echo "1.0.0"
    return $MODULE_SUCCESS
}

module_get_description() {
    echo "Configures system firewall (UFW/firewalld) with security rules"
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

    # Get configuration values
    local firewall_type
    firewall_type=$(module_config_get "firewall_type" "auto")
    local enable_firewall
    enable_firewall=$(module_config_get "enable_firewall" "true")
    local default_policy
    default_policy=$(module_config_get "default_policy" "deny")
    local allow_ssh
    allow_ssh=$(module_config_get "allow_ssh" "true")
    local ssh_port
    ssh_port=$(module_config_get "ssh_port" "22")
    local allowed_ports
    allowed_ports=$(module_config_get "allowed_ports" "")
    local log_rules
    log_rules=$(module_config_get "log_rules" "true")

    # Validate firewall type
    if [[ "$firewall_type" != "auto" && "$firewall_type" != "ufw" && "$firewall_type" != "firewalld" ]]; then
        module_log "ERROR" "Invalid firewall type: $firewall_type (must be auto, ufw, or firewalld)"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate boolean options
    if [[ "$enable_firewall" != "true" && "$enable_firewall" != "false" ]]; then
        module_log "ERROR" "Invalid enable_firewall value: $enable_firewall (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    if [[ "$default_policy" != "deny" && "$default_policy" != "allow" ]]; then
        module_log "ERROR" "Invalid default_policy value: $default_policy (must be deny or allow)"
        return $MODULE_CONFIG_ERROR
    fi

    if [[ "$allow_ssh" != "true" && "$allow_ssh" != "false" ]]; then
        module_log "ERROR" "Invalid allow_ssh value: $allow_ssh (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    if [[ "$log_rules" != "true" && "$log_rules" != "false" ]]; then
        module_log "ERROR" "Invalid log_rules value: $log_rules (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate SSH port
    if ! is_port_number "$ssh_port"; then
        module_log "ERROR" "Invalid SSH port: $ssh_port (must be between 1-65535)"
        return $MODULE_CONFIG_ERROR
    fi

    # Parse and validate allowed ports
    if [[ -n "$allowed_ports" ]]; then
        IFS=',' read -ra ports <<< "$allowed_ports"
        for port_config in "${ports[@]}"; do
            port_config=$(echo "$port_config" | xargs)  # trim whitespace

            if [[ "$port_config" =~ ^([0-9]+)/([a-z]+)$ ]]; then
                local port_num="${BASH_REMATCH[1]}"
                local protocol="${BASH_REMATCH[2]}"

                if ! is_port_number "$port_num"; then
                    module_log "ERROR" "Invalid port number in allowed_ports: $port_num"
                    return $MODULE_CONFIG_ERROR
                fi

                if [[ "$protocol" != "tcp" && "$protocol" != "udp" ]]; then
                    module_log "ERROR" "Invalid protocol in allowed_ports: $protocol (must be tcp or udp)"
                    return $MODULE_CONFIG_ERROR
                fi
            else
                module_log "ERROR" "Invalid port format in allowed_ports: $port_config (use format: 80/tcp or 53/udp)"
                return $MODULE_CONFIG_ERROR
            fi
        done
    fi

    module_log "DEBUG" "Configuration validation passed"
    module_log "DEBUG" "  firewall_type: $firewall_type"
    module_log "DEBUG" "  enable_firewall: $enable_firewall"
    module_log "DEBUG" "  default_policy: $default_policy"
    module_log "DEBUG" "  allow_ssh: $allow_ssh"
    module_log "DEBUG" "  ssh_port: $ssh_port"
    module_log "DEBUG" "  allowed_ports: $allowed_ports"
    module_log "DEBUG" "  log_rules: $log_rules"

    return $MODULE_SUCCESS
}

module_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Installing module: $module_name"

    # Get configuration
    local firewall_type
    firewall_type=$(module_config_get "firewall_type" "auto")
    local enable_firewall
    enable_firewall=$(module_config_get "enable_firewall" "true")

    # Skip if firewall is not enabled
    if [[ "$enable_firewall" != "true" ]]; then
        module_log "INFO" "Firewall is disabled in configuration, skipping installation"
        return $MODULE_SUCCESS
    fi

    # Detect and install firewall
    if ! detect_and_install_firewall "$firewall_type"; then
        module_log "ERROR" "Failed to install firewall"
        return $MODULE_ERROR
    fi

    # Configure firewall
    if ! configure_firewall; then
        module_log "ERROR" "Failed to configure firewall"
        return $MODULE_ERROR
    fi

    module_log "SUCCESS" "Firewall configuration completed successfully"
    return $MODULE_SUCCESS
}

module_verify() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Verifying firewall configuration: $module_name"

    local enable_firewall
    enable_firewall=$(module_config_get "enable_firewall" "true")

    # Skip verification if firewall is disabled
    if [[ "$enable_firewall" != "true" ]]; then
        module_log "DEBUG" "Firewall is disabled, skipping verification"
        return $MODULE_SUCCESS
    fi

    # Get firewall type
    local firewall_type
    firewall_type=$(get_active_firewall_type)

    if [[ -z "$firewall_type" ]]; then
        module_log "ERROR" "No active firewall found"
        return $MODULE_ERROR
    fi

    # Verify firewall is running
    if ! verify_firewall_status "$firewall_type"; then
        module_log "ERROR" "Firewall is not running properly"
        return $MODULE_ERROR
    fi

    # Verify firewall rules
    if ! verify_firewall_rules "$firewall_type"; then
        module_log "ERROR" "Firewall rules are not configured correctly"
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "Firewall verification successful"
    return $MODULE_SUCCESS
}

# =============================================================================
# Optional Functions
# =============================================================================

module_pre_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running pre-installation for module: $module_name"

    # Check if we have permission to configure firewall
    if [[ $EUID -ne 0 ]]; then
        module_log "ERROR" "Root privileges required to configure firewall"
        return $MODULE_PERMISSION_DENIED
    fi

    # Check for existing firewall configurations
    check_existing_firewall

    return $MODULE_SUCCESS
}

module_post_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running post-installation for module: $module_name"

    # Display firewall status
    display_firewall_status

    # Show security recommendations
    show_security_recommendations

    return $MODULE_SUCCESS
}

module_rollback() {
    local module_name
    module_name=$(module_get_name)

    module_log "WARN" "Rolling back module: $module_name"

    # Get firewall type
    local firewall_type
    firewall_type=$(get_active_firewall_type)

    if [[ -z "$firewall_type" ]]; then
        module_log "INFO" "No firewall to rollback"
        return $MODULE_SUCCESS
    fi

    # Disable firewall
    module_log "INFO" "Disabling firewall"
    case "$firewall_type" in
        "ufw")
            ufw --force disable 2>/dev/null || true
            ;;
        "firewalld")
            systemctl stop firewalld 2>/dev/null || true
            systemctl disable firewalld 2>/dev/null || true
            ;;
    esac

    module_log "INFO" "Firewall rollback completed"
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

detect_and_install_firewall() {
    local preferred_type="$1"

    module_log "INFO" "Detecting and installing firewall"

    local detected_type
    detected_type=$(detect_available_firewall "$preferred_type")

    if [[ -z "$detected_type" ]]; then
        module_log "ERROR" "No suitable firewall found"
        return $MODULE_ERROR
    fi

    module_log "INFO" "Using firewall: $detected_type"

    # Install firewall if needed
    case "$detected_type" in
        "ufw")
            install_ufw
            ;;
        "firewalld")
            install_firewalld
            ;;
    esac

    return $MODULE_SUCCESS
}

detect_available_firewall() {
    local preferred_type="$1"

    # Check if preferred type is available
    case "$preferred_type" in
        "ufw")
            if can_use_ufw; then
                echo "ufw"
                return
            fi
            ;;
        "firewalld")
            if can_use_firewalld; then
                echo "firewalld"
                return
            fi
            ;;
        "auto")
            # Auto-detect based on system
            if can_use_ufw; then
                echo "ufw"
                return
            elif can_use_firewalld; then
                echo "firewalld"
                return
            fi
            ;;
    esac

    # Fallback detection
    if can_use_ufw; then
        echo "ufw"
    elif can_use_firewalld; then
        echo "firewalld"
    fi
}

can_use_ufw() {
    command_exists ufw || \
        (is_debian_family && package_available ufw) || \
        (is_fedora_family && package_available ufw)
}

can_use_firewalld() {
    command_exists firewall-cmd || \
        (is_rhel_family && package_available firewalld) || \
        (is_fedora_family && package_available firewalld)
}

install_ufw() {
    module_log "INFO" "Installing UFW firewall"

    if ! command_exists ufw; then
        if is_debian_family; then
            apt-get update -qq
            apt-get install -y ufw
        elif is_fedora_family; then
            dnf install -y ufw
        else
            module_log "ERROR" "UFW not supported on this system"
            return $MODULE_ERROR
        fi
    fi

    return $MODULE_SUCCESS
}

install_firewalld() {
    module_log "INFO" "Installing firewalld"

    if ! command_exists firewall-cmd; then
        if is_debian_family; then
            apt-get update -qq
            apt-get install -y firewalld
        elif is_rhel_family || is_fedora_family; then
            dnf install -y firewalld
        else
            module_log "ERROR" "firewalld not supported on this system"
            return $MODULE_ERROR
        fi
    fi

    # Enable and start firewalld
    systemctl enable firewalld
    systemctl start firewalld

    return $MODULE_SUCCESS
}

configure_firewall() {
    local firewall_type
    firewall_type=$(get_active_firewall_type)

    module_log "INFO" "Configuring firewall: $firewall_type"

    # Backup current configuration
    backup_firewall_config "$firewall_type"

    case "$firewall_type" in
        "ufw")
            configure_ufw
            ;;
        "firewalld")
            configure_firewalld
            ;;
    esac

    return $MODULE_SUCCESS
}

configure_ufw() {
    module_log "INFO" "Configuring UFW"

    # Get configuration
    local default_policy
    default_policy=$(module_config_get "default_policy" "deny")
    local allow_ssh
    allow_ssh=$(module_config_get "allow_ssh" "true")
    local ssh_port
    ssh_port=$(module_config_get "ssh_port" "22")
    local allowed_ports
    allowed_ports=$(module_config_get "allowed_ports" "")
    local log_rules
    log_rules=$(module_config_get "log_rules" "true")

    # Reset UFW
    ufw --force reset

    # Set default policy
    local ufw_policy="deny"
    if [[ "$default_policy" == "allow" ]]; then
        ufw_policy="allow"
    fi
    ufw default "$ufw_policy" incoming
    ufw default allow outgoing

    # Configure logging
    if [[ "$log_rules" == "true" ]]; then
        ufw logging on
    else
        ufw logging off
    fi

    # Allow SSH if configured
    if [[ "$allow_ssh" == "true" ]]; then
        module_log "INFO" "Allowing SSH on port $ssh_port"
        ufw allow "$ssh_port/tcp" comment "SSH"
    fi

    # Allow additional ports
    if [[ -n "$allowed_ports" ]]; then
        IFS=',' read -ra ports <<< "$allowed_ports"
        for port_config in "${ports[@]}"; do
            port_config=$(echo "$port_config" | xargs)  # trim whitespace

            if [[ "$port_config" =~ ^([0-9]+)/([a-z]+)$ ]]; then
                local port_num="${BASH_REMATCH[1]}"
                local protocol="${BASH_REMATCH[2]}"

                module_log "INFO" "Allowing port $port_num/$protocol"
                ufw allow "$port_num/$protocol"
            fi
        done
    fi

    # Enable UFW
    module_log "INFO" "Enabling UFW"
    ufw --force enable

    return $MODULE_SUCCESS
}

configure_firewalld() {
    module_log "INFO" "Configuring firewalld"

    # Get configuration
    local default_policy
    default_policy=$(module_config_get "default_policy" "deny")
    local allow_ssh
    allow_ssh=$(module_config_get "allow_ssh" "true")
    local ssh_port
    ssh_port=$(module_config_get "ssh_port" "22")
    local allowed_ports
    allowed_ports=$(module_config_get "allowed_ports" "")
    local log_rules
    log_rules=$(module_config_get "log_rules" "true")

    # Ensure firewalld is running
    if ! systemctl is-active --quiet firewalld; then
        systemctl start firewalld
    fi

    # Set default zone
    local default_zone="public"
    firewall-cmd --set-default-zone="$default_zone"

    # Configure default policy
    local target="DROP"
    if [[ "$default_policy" == "allow" ]]; then
        target="ACCEPT"
    fi

    # Note: firewalld doesn't easily support changing default policy to DROP
    # We'll use rich rules or specific zones instead
    if [[ "$default_policy" == "deny" ]]; then
        module_log "INFO" "Setting restrictive default policy for firewalld"
        # Create a restrictive zone
        firewall-cmd --permanent --new-zone=restricted || true
        firewall-cmd --permanent --zone=restricted --set-target=DROP
        firewall-cmd --permanent --zone=restricted --add-interface=$(get_default_interface)
    fi

    # Configure logging
    if [[ "$log_rules" == "true" ]]; then
        firewall-cmd --set-log-denied=all
    fi

    # Allow SSH if configured
    if [[ "$allow_ssh" == "true" ]]; then
        module_log "INFO" "Allowing SSH on port $ssh_port"
        firewall-cmd --permanent --add-service=ssh
        if [[ "$ssh_port" != "22" ]]; then
            firewall-cmd --permanent --add-port="$ssh_port/tcp"
        fi
    fi

    # Allow additional ports
    if [[ -n "$allowed_ports" ]]; then
        IFS=',' read -ra ports <<< "$allowed_ports"
        for port_config in "${ports[@]}"; do
            port_config=$(echo "$port_config" | xargs)  # trim whitespace

            if [[ "$port_config" =~ ^([0-9]+)/([a-z]+)$ ]]; then
                local port_num="${BASH_REMATCH[1]}"
                local protocol="${BASH_REMATCH[2]}"

                module_log "INFO" "Allowing port $port_num/$protocol"
                firewall-cmd --permanent --add-port="$port_num/$protocol"
            fi
        done
    fi

    # Reload firewalld
    module_log "INFO" "Reloading firewalld configuration"
    firewall-cmd --reload

    return $MODULE_SUCCESS
}

get_active_firewall_type() {
    if command_exists ufw && ufw status | grep -q "Status: active"; then
        echo "ufw"
    elif command_exists firewall-cmd && systemctl is-active --quiet firewalld; then
        echo "firewalld"
    fi
}

verify_firewall_status() {
    local firewall_type="$1"

    case "$firewall_type" in
        "ufw")
            ufw status | grep -q "Status: active"
            ;;
        "firewalld")
            systemctl is-active --quiet firewalld
            ;;
    esac
}

verify_firewall_rules() {
    local firewall_type="$1"

    # Get configuration
    local allow_ssh
    allow_ssh=$(module_config_get "allow_ssh" "true")
    local ssh_port
    ssh_port=$(module_config_get "ssh_port" "22")
    local allowed_ports
    allowed_ports=$(module_config_get "allowed_ports" "")

    case "$firewall_type" in
        "ufw")
            # Verify SSH rule
            if [[ "$allow_ssh" == "true" ]]; then
                if ! ufw status | grep -q "$ssh_port/tcp.*ALLOW"; then
                    module_log "ERROR" "SSH rule not found in UFW"
                    return $MODULE_ERROR
                fi
            fi

            # Verify additional ports
            if [[ -n "$allowed_ports" ]]; then
                IFS=',' read -ra ports <<< "$allowed_ports"
                for port_config in "${ports[@]}"; do
                    port_config=$(echo "$port_config" | xargs)
                    if [[ "$port_config" =~ ^([0-9]+)/([a-z]+)$ ]]; then
                        local port_num="${BASH_REMATCH[1]}"
                        local protocol="${BASH_REMATCH[2]}"

                        if ! ufw status | grep -q "$port_num/$protocol.*ALLOW"; then
                            module_log "ERROR" "Port rule not found in UFW: $port_num/$protocol"
                            return $MODULE_ERROR
                        fi
                    fi
                done
            fi
            ;;

        "firewalld")
            # Verify SSH rule
            if [[ "$allow_ssh" == "true" ]]; then
                if ! firewall-cmd --list-services | grep -q "ssh"; then
                    module_log "ERROR" "SSH service not found in firewalld"
                    return $MODULE_ERROR
                fi
            fi

            # Verify additional ports
            if [[ -n "$allowed_ports" ]]; then
                IFS=',' read -ra ports <<< "$allowed_ports"
                for port_config in "${ports[@]}"; do
                    port_config=$(echo "$port_config" | xargs)
                    if [[ "$port_config" =~ ^([0-9]+)/([a-z]+)$ ]]; then
                        local port_num="${BASH_REMATCH[1]}"
                        local protocol="${BASH_REMATCH[2]}"

                        if ! firewall-cmd --list-ports | grep -q "$port_num/$protocol"; then
                            module_log "ERROR" "Port rule not found in firewalld: $port_num/$protocol"
                            return $MODULE_ERROR
                        fi
                    fi
                done
            fi
            ;;
    esac

    return $MODULE_SUCCESS
}

check_existing_firewall() {
    module_log "INFO" "Checking for existing firewall configurations"

    # Check UFW
    if command_exists ufw; then
        if ufw status | grep -q "Status: active"; then
            module_log "WARN" "UFW is currently active"
            module_log "WARN" "Existing rules will be backed up and replaced"
        fi
    fi

    # Check firewalld
    if command_exists firewall-cmd && systemctl is-active --quiet firewalld; then
        module_log "WARN" "firewalld is currently active"
        module_log "WARN" "Existing rules will be backed up and replaced"
    fi

    # Check iptables directly
    if command_exists iptables && iptables -L | grep -q "ACCEPT\|DROP"; then
        module_log "WARN" "iptables rules detected"
        module_log "WARN" "These may conflict with UFW/firewalld"
    fi
}

backup_firewall_config() {
    local firewall_type="$1"
    local backup_dir="${SERVERSH_STATE_DIR}/backups/${module_name}"

    ensure_dir "$backup_dir"

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    case "$firewall_type" in
        "ufw")
            if [[ -f /etc/ufw/user.rules ]]; then
                cp /etc/ufw/user.rules "$backup_dir/ufw_user.rules.$timestamp"
                module_log "DEBUG" "Backed up UFW user rules"
            fi
            if [[ -f /etc/ufw/before.rules ]]; then
                cp /etc/ufw/before.rules "$backup_dir/ufw_before.rules.$timestamp"
                module_log "DEBUG" "Backed up UFW before rules"
            fi
            ;;
        "firewalld")
            if [[ -d /etc/firewalld ]]; then
                tar -czf "$backup_dir/firewalld_config.$timestamp.tar.gz" -C /etc firewalld 2>/dev/null || true
                module_log "DEBUG" "Backed up firewalld configuration"
            fi
            ;;
    esac
}

display_firewall_status() {
    local firewall_type
    firewall_type=$(get_active_firewall_type)

    if [[ -z "$firewall_type" ]]; then
        module_log "INFO" "No firewall is currently active"
        return
    fi

    module_log "INFO" "Firewall Status Summary:"
    module_log "INFO" "  Firewall Type: $firewall_type"
    module_log "INFO" "  Status: Active"

    case "$firewall_type" in
        "ufw")
            module_log "INFO" "  Default Policy: $(ufw status verbose | grep "Default:" | head -1)"
            module_log "INFO" "  Logging: $(ufw status | grep "Logging:" | awk '{print $2}')"
            ;;
        "firewalld")
            module_log "INFO" "  Default Zone: $(firewall-cmd --get-default-zone)"
            module_log "INFO" "  Log Denied: $(firewall-cmd --get-log-denied)"
            ;;
    esac
}

show_security_recommendations() {
    module_log "INFO" "Security Recommendations:"
    module_log "INFO" "  • Regularly review firewall rules"
    module_log "INFO" "  • Monitor firewall logs for suspicious activity"
    module_log "INFO" "  • Consider using fail2ban for additional protection"
    module_log "INFO" "  • Keep firewall software updated"
    module_log "INFO" "  • Test firewall rules after configuration changes"
}

get_default_interface() {
    # Get the default network interface
    ip route | grep default | head -1 | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}'
}

# Initialize module (optional - called when module is sourced)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    module_log "DEBUG" "Firewall configuration module loaded"
fi

return $MODULE_SUCCESS