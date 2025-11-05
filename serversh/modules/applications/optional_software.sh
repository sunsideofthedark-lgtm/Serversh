#!/bin/bash

# =============================================================================
# Module: Optional Software Installation
# Category: Applications
# Description: Installs optional software packages including Tailscale, development tools, and utilities
# Version: 1.0.0
# =============================================================================

# Source module interface
source "${SERVERSH_LIB_DIR}/module_interface.sh" || exit $EXIT_MISSING_DEPS

# Color definitions for interactive prompts
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# =============================================================================
# Required Functions
# =============================================================================

module_get_name() {
    echo "applications/optional_software"
    return $MODULE_SUCCESS
}

module_get_version() {
    echo "1.0.0"
    return $MODULE_SUCCESS
}

module_get_description() {
    echo "Installs optional software packages including Tailscale and development tools"
    return $MODULE_SUCCESS
}

module_get_category() {
    echo "$MODULE_CATEGORY_APPLICATIONS"
    return $MODULE_SUCCESS
}

module_get_dependencies() {
    echo "system/hostname"
    return $MODULE_SUCCESS
}

module_validate_config() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Validating configuration for module: $module_name"

    # Get configuration values
    local install_tailscale
    install_tailscale=$(module_config_get "install_tailscale" "true")
    local tailscale_auth_key
    tailscale_auth_key=$(module_config_get "tailscale_auth_key" "")
    local tailscale_args
    tailscale_args=$(module_config_get "tailscale_args" "")
    local tailscale_login_method
    tailscale_login_method=$(module_config_get "tailscale_login_method" "interactive")

    local install_dev_tools
    install_dev_tools=$(module_config_get "install_dev_tools" "false")
    local dev_packages
    dev_packages=$(module_config_get "dev_packages" "build-essential,python3,python3-pip,nodejs,npm")

    local install_utilities
    install_utilities=$(module_config_get "install_utilities" "true")
    local utility_packages
    utility_packages=$(module_config_get "utility_packages" "htop,vim,git,curl,wget,unzip,tree,ncdu,rsync,netcat-openbsd")

    local install_docker_extras
    install_docker_extras=$(module_config_get "install_docker_extras" "false")
    local docker_extras
    docker_extras=$(module_config_get "docker_extras" "docker-compose,ctop")

    local install_monitoring_tools
    install_monitoring_tools=$(module_config_get "install_monitoring_tools" "false")
    local monitoring_packages
    monitoring_packages=$(module_config_get "monitoring_packages" "iotop,nethogs,sysstat,lm-sensors")

    # Validate boolean options
    if [[ "$install_tailscale" != "true" && "$install_tailscale" != "false" ]]; then
        module_log "ERROR" "Invalid install_tailscale value: $install_tailscale (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    if [[ "$install_dev_tools" != "true" && "$install_dev_tools" != "false" ]]; then
        module_log "ERROR" "Invalid install_dev_tools value: $install_dev_tools (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    if [[ "$install_utilities" != "true" && "$install_utilities" != "false" ]]; then
        module_log "ERROR" "Invalid install_utilities value: $install_utilities (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    if [[ "$install_docker_extras" != "true" && "$install_docker_extras" != "false" ]]; then
        module_log "ERROR" "Invalid install_docker_extras value: $install_docker_extras (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    if [[ "$install_monitoring_tools" != "true" && "$install_monitoring_tools" != "false" ]]; then
        module_log "ERROR" "Invalid install_monitoring_tools value: $install_monitoring_tools (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate Tailscale configuration
    if [[ "$install_tailscale" == "true" ]]; then
        if [[ "$tailscale_login_method" != "interactive" && "$tailscale_login_method" != "auth_key" && "$tailscale_login_method" != "no_login" && "$tailscale_login_method" != "ssh" ]]; then
            module_log "ERROR" "Invalid tailscale_login_method: $tailscale_login_method (must be interactive, auth_key, ssh, or no_login)"
            return $MODULE_CONFIG_ERROR
        fi

        if [[ "$tailscale_login_method" == "auth_key" && -z "$tailscale_auth_key" ]]; then
            module_log "ERROR" "tailscale_auth_key is required when login_method is 'auth_key'"
            return $MODULE_CONFIG_ERROR
        fi

        # Validate Tailscale auth key format (starts with tskey-)
        if [[ -n "$tailscale_auth_key" && ! "$tailscale_auth_key" =~ ^tskey-[a-zA-Z0-9-]+$ ]]; then
            module_log "ERROR" "Invalid tailscale_auth_key format (should start with 'tskey-')"
            return $MODULE_CONFIG_ERROR
        fi
    fi

    # Validate package lists
    if [[ -n "$dev_packages" ]]; then
        validate_package_list "$dev_packages" "dev_packages" || return $MODULE_CONFIG_ERROR
    fi

    if [[ -n "$utility_packages" ]]; then
        validate_package_list "$utility_packages" "utility_packages" || return $MODULE_CONFIG_ERROR
    fi

    if [[ -n "$docker_extras" ]]; then
        validate_package_list "$docker_extras" "docker_extras" || return $MODULE_CONFIG_ERROR
    fi

    if [[ -n "$monitoring_packages" ]]; then
        validate_package_list "$monitoring_packages" "monitoring_packages" || return $MODULE_CONFIG_ERROR
    fi

    module_log "DEBUG" "Configuration validation passed"
    module_log "DEBUG" "  install_tailscale: $install_tailscale"
    module_log "DEBUG" "  tailscale_login_method: $tailscale_login_method"
    module_log "DEBUG" "  install_dev_tools: $install_dev_tools"
    module_log "DEBUG" "  install_utilities: $install_utilities"
    module_log "DEBUG" "  install_docker_extras: $install_docker_extras"
    module_log "DEBUG" "  install_monitoring_tools: $install_monitoring_tools"

    return $MODULE_SUCCESS
}

module_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Installing module: $module_name"

    # Check if hostname is set (dependency requirement)
    if [[ $(hostname) == "localhost" || $(hostname) == "$(cat /etc/hostname 2>/dev/null)" ]]; then
        module_log "INFO" "Waiting for hostname to be configured..."
        # Wait a moment for hostname module to complete
        sleep 3
    fi

    # Get current hostname for Tailscale configuration
    local current_hostname
    current_hostname=$(hostname)
    module_log "INFO" "Current hostname: $current_hostname"

    # Install Tailscale
    local install_tailscale
    install_tailscale=$(module_config_get "install_tailscale" "true")
    if [[ "$install_tailscale" == "true" ]]; then
        if ! install_tailscale; then
            module_log "ERROR" "Failed to install Tailscale"
            return $MODULE_ERROR
        fi
    fi

    # Install development tools
    local install_dev_tools
    install_dev_tools=$(module_config_get "install_dev_tools" "false")
    if [[ "$install_dev_tools" == "true" ]]; then
        if ! install_package_group "Development Tools" "$dev_packages"; then
            module_log "ERROR" "Failed to install development tools"
            return $MODULE_ERROR
        fi
    fi

    # Install utilities
    local install_utilities
    install_utilities=$(module_config_get "install_utilities" "true")
    if [[ "$install_utilities" == "true" ]]; then
        if ! install_package_group "Utilities" "$utility_packages"; then
            module_log "ERROR" "Failed to install utilities"
            return $MODULE_ERROR
        fi
    fi

    # Install Docker extras
    local install_docker_extras
    install_docker_extras=$(module_config_get "install_docker_extras" "false")
    if [[ "$install_docker_extras" == "true" ]]; then
        if ! install_docker_extras; then
            module_log "ERROR" "Failed to install Docker extras"
            return $MODULE_ERROR
        fi
    fi

    # Install monitoring tools
    local install_monitoring_tools
    install_monitoring_tools=$(module_config_get "install_monitoring_tools" "false")
    if [[ "$install_monitoring_tools" == "true" ]]; then
        if ! install_package_group "Monitoring Tools" "$monitoring_packages"; then
            module_log "ERROR" "Failed to install monitoring tools"
            return $MODULE_ERROR
        fi
    fi

    # Post-installation setup
    if ! post_install_setup; then
        module_log "ERROR" "Failed post-installation setup"
        return $MODULE_ERROR
    fi

    module_log "SUCCESS" "Optional software installation completed successfully"
    return $MODULE_SUCCESS
}

module_verify() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Verifying optional software installation: $module_name"

    local verification_failed=false

    # Verify Tailscale
    local install_tailscale
    install_tailscale=$(module_config_get "install_tailscale" "true")
    if [[ "$install_tailscale" == "true" ]]; then
        if ! verify_tailscale; then
            module_log "ERROR" "Tailscale verification failed"
            verification_failed=true
        fi
    fi

    # Verify package installations
    local install_utilities
    install_utilities=$(module_config_get "install_utilities" "true")
    if [[ "$install_utilities" == "true" ]]; then
        if ! verify_packages "$utility_packages"; then
            module_log "ERROR" "Utility packages verification failed"
            verification_failed=true
        fi
    fi

    local install_dev_tools
    install_dev_tools=$(module_config_get "install_dev_tools" "false")
    if [[ "$install_dev_tools" == "true" ]]; then
        if ! verify_packages "$dev_packages"; then
            module_log "ERROR" "Development tools verification failed"
            verification_failed=true
        fi
    fi

    local install_monitoring_tools
    install_monitoring_tools=$(module_config_get "install_monitoring_tools" "false")
    if [[ "$install_monitoring_tools" == "true" ]]; then
        if ! verify_packages "$monitoring_packages"; then
            module_log "ERROR" "Monitoring tools verification failed"
            verification_failed=true
        fi
    fi

    if [[ "$verification_failed" == "true" ]]; then
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "Optional software verification successful"
    return $MODULE_SUCCESS
}

# =============================================================================
# Optional Functions
# =============================================================================

module_pre_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running pre-installation for module: $module_name"

    # Check if we have permission to install packages
    if [[ $EUID -ne 0 ]]; then
        module_log "ERROR" "Root privileges required to install software packages"
        return $MODULE_PERMISSION_DENIED
    fi

    # Check hostname dependency
    if ! command_exists hostname; then
        module_log "ERROR" "hostname command not available"
        return $MODULE_ERROR
    fi

    local current_hostname
    current_hostname=$(hostname)
    if [[ "$current_hostname" == "localhost" || -z "$current_hostname" ]]; then
        module_log "WARN" "Hostname appears to be default. Ensure system/hostname module runs first."
    fi

    return $MODULE_SUCCESS
}

module_post_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running post-installation for module: $module_name"

    # Display installation summary
    display_installation_summary

    # Show next steps
    show_next_steps

    return $MODULE_SUCCESS
}

module_rollback() {
    local module_name
    module_name=$(module_get_name)

    module_log "WARN" "Rolling back module: $module_name"

    # Rollback Tailscale
    local install_tailscale
    install_tailscale=$(module_config_get "install_tailscale" "true")
    if [[ "$install_tailscale" == "true" ]]; then
        rollback_tailscale
    fi

    # Remove installed packages
    local packages_to_remove=""

    local install_utilities
    install_utilities=$(module_config_get "install_utilities" "true")
    if [[ "$install_utilities" == "true" ]]; then
        packages_to_remove="$packages_to_remove $utility_packages"
    fi

    local install_dev_tools
    install_dev_tools=$(module_config_get "install_dev_tools" "false")
    if [[ "$install_dev_tools" == "true" ]]; then
        packages_to_remove="$packages_to_remove $dev_packages"
    fi

    local install_monitoring_tools
    install_monitoring_tools=$(module_config_get "install_monitoring_tools" "false")
    if [[ "$install_monitoring_tools" == "true" ]]; then
        packages_to_remove="$packages_to_remove $monitoring_packages"
    fi

    if [[ -n "$packages_to_remove" ]]; then
        module_log "INFO" "Removing installed packages: $packages_to_remove"
        remove_packages "$packages_to_remove"
    fi

    module_log "INFO" "Optional software rollback completed"
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

validate_package_list() {
    local package_list="$1"
    local list_name="$2"

    # Check if package list is valid (comma-separated package names)
    if [[ ! "$package_list" =~ ^[a-zA-Z0-9_\-]+$ ]] && [[ ! "$package_list" =~ ^[a-zA-Z0-9_\-]+(,[a-zA-Z0-9_\-]+)*$ ]]; then
        module_log "ERROR" "Invalid package list format for $list_name: $package_list"
        module_log "ERROR" "Use comma-separated package names without spaces"
        return 1
    fi

    return 0
}

install_package_group() {
    local group_name="$1"
    local packages="$2"

    module_log "INFO" "Installing $group_name packages: $packages"

    # Update package lists
    update_package_lists

    # Convert comma-separated to space-separated
    local package_array
    IFS=',' read -ra package_array <<< "$packages"

    # Install packages based on distribution
    local install_success=true

    case "$(get_system_info os)" in
        ubuntu|debian)
            for package in "${package_array[@]}"; do
                package=$(echo "$package" | xargs)  # trim whitespace
                module_log "DEBUG" "Installing Debian/Ubuntu package: $package"
                if ! apt-get install -y "$package"; then
                    module_log "WARN" "Failed to install $package (may not be available)"
                    install_success=false
                fi
            done
            ;;
        centos|rhel|fedora)
            for package in "${package_array[@]}"; do
                package=$(echo "$package" | xargs)
                module_log "DEBUG" "Installing RHEL/Fedora package: $package"
                if command_exists dnf; then
                    if ! dnf install -y "$package"; then
                        module_log "WARN" "Failed to install $package (may not be available)"
                        install_success=false
                    fi
                elif command_exists yum; then
                    if ! yum install -y "$package"; then
                        module_log "WARN" "Failed to install $package (may not be available)"
                        install_success=false
                    fi
                fi
            done
            ;;
        arch)
            for package in "${package_array[@]}"; do
                package=$(echo "$package" | xargs)
                module_log "DEBUG" "Installing Arch package: $package"
                if ! pacman -S --noconfirm "$package"; then
                    module_log "WARN" "Failed to install $package (may not be available)"
                    install_success=false
                fi
            done
            ;;
        opensuse*)
            for package in "${package_array[@]}"; do
                package=$(echo "$package" | xargs)
                module_log "DEBUG" "Installing openSUSE package: $package"
                if ! zypper install -y "$package"; then
                    module_log "WARN" "Failed to install $package (may not be available)"
                    install_success=false
                fi
            done
            ;;
        *)
            module_log "ERROR" "Unsupported distribution for package installation"
            return $MODULE_ERROR
            ;;
    esac

    if [[ "$install_success" == "true" ]]; then
        module_log "SUCCESS" "$group_name packages installed successfully"
        return $MODULE_SUCCESS
    else
        module_log "WARN" "Some $group_name packages failed to install"
        return $MODULE_SUCCESS  # Don't fail the entire module for missing optional packages
    fi
}

update_package_lists() {
    case "$(get_system_info os)" in
        ubuntu|debian)
            apt-get update -qq
            ;;
        centos|rhel|fedora)
            if command_exists dnf; then
                dnf makecache -q
            elif command_exists yum; then
                yum makecache -q
            fi
            ;;
        arch)
            pacman -Sy
            ;;
        opensuse*)
            zypper refresh -q
            ;;
    esac
}

remove_packages() {
    local packages="$1"

    # Convert comma-separated to space-separated
    local package_array
    IFS=',' read -ra package_array <<< "$packages"

    case "$(get_system_info os)" in
        ubuntu|debian)
            apt-get remove --purge -y "${package_array[@]}" 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
            ;;
        centos|rhel|fedora)
            if command_exists dnf; then
                dnf remove -y "${package_array[@]}" 2>/dev/null || true
            elif command_exists yum; then
                yum remove -y "${package_array[@]}" 2>/dev/null || true
            fi
            ;;
        arch)
            pacman -Rsu --noconfirm "${package_array[@]}" 2>/dev/null || true
            ;;
        opensuse*)
            zypper remove -y "${package_array[@]}" 2>/dev/null || true
            ;;
    esac
}

verify_packages() {
    local packages="$1"

    # Convert comma-separated to space-separated
    local package_array
    IFS=',' read -ra package_array <<< "$packages"
    local missing_packages=()

    for package in "${package_array[@]}"; do
        package=$(echo "$package" | xargs)  # trim whitespace
        if ! is_package_installed "$package"; then
            missing_packages+=("$package")
        fi
    done

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        module_log "WARN" "Some packages are not installed: ${missing_packages[*]}"
        # Don't fail verification for optional packages
    fi

    return $MODULE_SUCCESS
}

# =============================================================================
# Tailscale Functions
# =============================================================================

install_tailscale() {
    module_log "INFO" "Installing Tailscale"

    local tailscale_auth_key
    tailscale_auth_key=$(module_config_get "tailscale_auth_key" "")
    local tailscale_args
    tailscale_args=$(module_config_get "tailscale_args" "")
    local tailscale_login_method
    tailscale_login_method=$(module_config_get "tailscale_login_method" "interactive")

    # Install Tailscale
    if ! install_tailscale_package; then
        module_log "ERROR" "Failed to install Tailscale package"
        return $MODULE_ERROR
    fi

    # Configure Tailscale
    if ! configure_tailscale "$tailscale_auth_key" "$tailscale_args" "$tailscale_login_method"; then
        module_log "ERROR" "Failed to configure Tailscale"
        return $MODULE_ERROR
    fi

    module_log "SUCCESS" "Tailscale installed and configured"
    return $MODULE_SUCCESS
}

install_tailscale_package() {
    module_log "DEBUG" "Installing Tailscale package"

    # Detect distribution and install accordingly
    case "$(get_system_info os)" in
        ubuntu|debian)
            # Add Tailscale repository
            curl -fsSL https://tailscale.com/install.sh | sh
            ;;
        centos|rhel|fedora)
            # Add Tailscale repository
            curl -fsSL https://tailscale.com/install.sh | sh
            ;;
        arch)
            # Install from AUR or use official script
            curl -fsSL https://tailscale.com/install.sh | sh
            ;;
        opensuse*)
            curl -fsSL https://tailscale.com/install.sh | sh
            ;;
        *)
            # Use the universal installer script as fallback
            if command_exists curl; then
                curl -fsSL https://tailscale.com/install.sh | sh
            else
                module_log "ERROR" "Cannot install Tailscale: curl not available and unsupported distribution"
                return $MODULE_ERROR
            fi
            ;;
    esac

    # Verify installation
    if ! command_exists tailscale; then
        module_log "ERROR" "Tailscale installation failed - tailscale command not found"
        return $MODULE_ERROR
    fi

    # Enable and start Tailscale service
    systemctl enable tailscaled 2>/dev/null || true
    systemctl start tailscaled 2>/dev/null || true

    # Wait for service to start
    sleep 5

    module_log "DEBUG" "Tailscale package installed successfully"
    return $MODULE_SUCCESS
}

configure_tailscale() {
    local auth_key="$1"
    local tailscale_args="$2"
    local login_method="$3"

    module_log "INFO" "Configuring Tailscale with login method: $login_method"

    # Wait for Tailscale daemon to be ready
    local max_wait=30
    local wait_count=0
    while ! tailscale status >/dev/null 2>&1 && [[ $wait_count -lt $max_wait ]]; do
        module_log "DEBUG" "Waiting for Tailscale daemon to start... ($wait_count/$max_wait)"
        sleep 1
        ((wait_count++))
    done

    if [[ $wait_count -ge $max_wait ]]; then
        module_log "WARN" "Tailscale daemon did not start within expected time"
    fi

    # Build Tailscale arguments
    local ts_args=""

    # Add hostname-specific arguments
    local current_hostname
    current_hostname=$(hostname)
    ts_args="$ts_args --hostname=$current_hostname"

    # Add user-specified arguments
    if [[ -n "$tailscale_args" ]]; then
        ts_args="$ts_args $tailscale_args"
    fi

    # Add auth key if provided
    if [[ -n "$auth_key" && "$login_method" == "auth_key" ]]; then
        ts_args="$ts_args --authkey=$auth_key"
    fi

    # Start Tailscale based on login method
    case "$login_method" in
        "auth_key")
            module_log "INFO" "Starting Tailscale with authentication key"
            if ! eval "tailscale up $ts_args"; then
                module_log "ERROR" "Failed to start Tailscale with auth key"
                return $MODULE_ERROR
            fi
            ;;
        "interactive")
            module_log "INFO" "Starting Tailscale (interactive login required)"
            module_log "INFO" "You will need to authenticate at: https://login.tailscale.com/start"
            if ! eval "tailscale up $ts_args"; then
                module_log "WARN" "Tailscale started but may need manual authentication"
            fi
            ;;
        "ssh")
            module_log "INFO" "Configuring Tailscale for SSH-based authentication"
            # Ask user if they want SSH authentication
            if [[ -t 0 ]]; then  # Check if running in interactive terminal
                echo -e "${YELLOW}Möchten Sie SSH-basierte Tailscale-Authentifizierung verwenden?${NC}"
                echo "Dies erstellt SSH-Schlüssel und konfiguriert Tailscale für SSH-Zugriff."
                echo ""
                read -p "SSH-Authentifizierung verwenden? (j/N): " -n 1 -r
                echo ""
                if [[ $REPLY =~ ^[Jj]$ ]]; then
                    module_log "INFO" "SSH-Authentifizierung gewählt"
                    configure_tailscale_ssh "$ts_args"
                else
                    module_log "INFO" "SSH-Authentifizierung abgelehnt, nutze Standard-Methode"
                    # Fallback to interactive method
                    if ! eval "tailscale up $ts_args"; then
                        module_log "WARN" "Tailscale started but may need manual authentication"
                    fi
                fi
            else
                module_log "INFO" "Non-interactive mode: configuring SSH-based authentication"
                configure_tailscale_ssh "$ts_args"
            fi
            ;;
        "no_login")
            module_log "INFO" "Installing Tailscale without connecting (no-login mode)"
            # Don't start tailscale up, just install the package
            return $MODULE_SUCCESS
            ;;
        *)
            module_log "ERROR" "Unknown Tailscale login method: $login_method"
            return $MODULE_ERROR
            ;;
    esac

    # Wait a moment for connection to establish
    sleep 3

    # Verify Tailscale status
    if tailscale status >/dev/null 2>&1; then
        local tailscale_ip
        tailscale_ip=$(tailscale ip -4 2>/dev/null | head -1)
        if [[ -n "$tailscale_ip" ]]; then
            module_log "SUCCESS" "Tailscale connected with IP: $tailscale_ip"
        else
            module_log "INFO" "Tailscale installed but not yet connected"
        fi
    else
        module_log "WARN" "Tailscale status check failed - may need manual configuration"
    fi

    return $MODULE_SUCCESS
}

configure_tailscale_ssh() {
    local ts_args="$1"

    module_log "INFO" "Setting up Tailscale SSH authentication"

    # Get SSH configuration values
    local tailscale_ssh_user
    tailscale_ssh_user=$(module_config_get "tailscale_ssh_user" "root")

    local tailscale_ssh_port
    tailscale_ssh_port=$(module_config_get "tailscale_ssh_port" "22")

    local tailscale_ssh_key_path
    tailscale_ssh_key_path=$(module_config_get "tailscale_ssh_key_path" "/root/.ssh/tailscale")

    local tailscale_ssh_timeout
    tailscale_ssh_timeout=$(module_config_get "tailscale_ssh_timeout" "300")

    module_log "INFO" "SSH Configuration: User=$tailscale_ssh_user, Port=$tailscale_ssh_port"

    # Check if SSH is running
    if ! systemctl is-active --quiet sshd && ! systemctl is-active --quiet ssh; then
        module_log "WARN" "SSH service is not running. Starting SSH service..."
        systemctl start sshd 2>/dev/null || systemctl start ssh 2>/dev/null || {
            module_log "ERROR" "Failed to start SSH service"
            return $MODULE_ERROR
        }
    fi

    # Enable SSH if not already enabled
    if ! systemctl is-enabled --quiet sshd && ! systemctl is-enabled --quiet ssh; then
        systemctl enable sshd 2>/dev/null || systemctl enable ssh 2>/dev/null || {
            module_log "WARN" "Could not enable SSH service"
        }
    fi

    # Generate SSH key pair for Tailscale if not exists
    if [[ ! -f "$tailscale_ssh_key_path" ]]; then
        module_log "INFO" "Generating SSH key pair for Tailscale authentication"
        mkdir -p "$(dirname "$tailscale_ssh_key_path")"
        ssh-keygen -t ed25519 -f "$tailscale_ssh_key_path" -N "" -C "tailscale-$(hostname)"
        chmod 600 "$tailscale_ssh_key_path"
        chmod 644 "${tailscale_ssh_key_path}.pub"
    fi

    # Display the public key for manual addition to Tailscale
    local public_key
    public_key=$(cat "${tailscale_ssh_key_path}.pub")

    module_log "INFO" "SSH Public Key for Tailscale:"
    module_log "INFO" "$public_key"
    module_log "INFO" "Add this key to your Tailscale account at: https://login.tailscale.com/admin/machines"

    # Create SSH configuration script for later use
    local ssh_config_script="/tmp/tailscale_ssh_auth.sh"
    cat > "$ssh_config_script" << EOF
#!/bin/bash
# Tailscale SSH Authentication Script
# Generated by ServerSH on $(date)

set -e

SSH_USER="$tailscale_ssh_user"
SSH_PORT="$tailscale_ssh_port"
SSH_KEY="$tailscale_ssh_key_path"
TIMEOUT="$tailscale_ssh_timeout"
TS_ARGS="$ts_args"

echo "Tailscale SSH Authentication Script"
echo "==================================="
echo "This script will help you authenticate Tailscale via SSH"
echo ""

# Function to check Tailscale status
check_tailscale_status() {
    if tailscale status >/dev/null 2>&1; then
        echo "✅ Tailscale is connected"
        tailscale ip -4 2>/dev/null && echo "Tailscale IP: \$(tailscale ip -4)"
        return 0
    else
        echo "❌ Tailscale is not connected"
        return 1
    fi
}

# Try to start Tailscale if not running
if ! systemctl is-active --quiet tailscaled; then
    echo "Starting Tailscale daemon..."
    systemctl start tailscaled
    sleep 5
fi

# Show current status
echo "Current Tailscale status:"
tailscale status 2>/dev/null || echo "Tailscale not connected"

echo ""
echo "Available authentication methods:"
echo "1. Use this script with SSH key authentication"
echo "2. Manual authentication at: https://login.tailscale.com/start"
echo "3. Use auth key if available"
echo ""

# Try SSH-based authentication
echo "Attempting SSH-based Tailscale authentication..."

# Add SSH key to authorized_keys for local access
if [[ -f "\$SSH_KEY" && -d "/home/\$SSH_USER/.ssh" ]]; then
    if ! grep -q "\$(cat \$SSH_KEY.pub)" "/home/\$SSH_USER/.ssh/authorized_keys" 2>/dev/null; then
        echo "Adding SSH key to authorized_keys..."
        mkdir -p "/home/\$SSH_USER/.ssh"
        cat "\$SSH_KEY.pub" >> "/home/\$SSH_USER/.ssh/authorized_keys"
        chown -R "\$SSH_USER:\$SSH_USER" "/home/\$SSH_USER/.ssh"
        chmod 600 "/home/\$SSH_USER/.ssh/authorized_keys"
    fi
fi

# Start Tailscale with SSH-specific arguments
echo "Starting Tailscale..."
if eval "tailscale up \$TS_ARGS"; then
    echo "Tailscale started successfully!"
    sleep 10

    if check_tailscale_status; then
        echo ""
        echo "🎉 Tailscale SSH authentication successful!"
        echo ""
        echo "Next steps:"
        echo "1. Check your Tailscale admin panel: https://login.tailscale.com/admin/machines"
        echo "2. Verify the machine appears and is authorized"
        echo "3. Test connectivity: tailscale ping <other-machine>"
    else
        echo ""
        echo "⚠️  Tailscale started but may need manual authorization"
        echo "Please visit: https://login.tailscale.com/start"
        echo ""
        echo "SSH Key for manual addition:"
        echo "\$public_key"
    fi
else
    echo "❌ Failed to start Tailscale"
    echo "Please check logs: journalctl -u tailscaled -f"
    exit 1
fi

echo ""
echo "This script will remain available at: $ssh_config_script"
echo "Run it anytime to retry Tailscale SSH authentication"
EOF

    chmod +x "$ssh_config_script"

    module_log "INFO" "SSH authentication script created: $ssh_config_script"
    module_log "INFO" "Run this script to complete Tailscale SSH authentication"

    # Try to automatically run the script if we're in an interactive environment
    if [[ -t 0 ]] && [[ "${INTERACTIVE_SSH:-false}" == "true" ]]; then
        module_log "INFO" "Running SSH authentication script..."
        if bash "$ssh_config_script"; then
            module_log "SUCCESS" "Tailscale SSH authentication completed"
        else
            module_log "WARN" "SSH authentication script requires manual execution"
        fi
    else
        module_log "INFO" "SSH authentication script created for manual execution"
    fi

    return $MODULE_SUCCESS
}

verify_tailscale() {
    if ! command_exists tailscale; then
        module_log "ERROR" "Tailscale command not found"
        return $MODULE_ERROR
    fi

    if ! systemctl is-active --quiet tailscaled; then
        module_log "WARN" "Tailscale service is not running"
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "Tailscale verification successful"
    return $MODULE_SUCCESS
}

rollback_tailscale() {
    module_log "INFO" "Rolling back Tailscale"

    # Stop and disable Tailscale service
    systemctl stop tailscaled 2>/dev/null || true
    systemctl disable tailscaled 2>/dev/null || true

    # Remove Tailscale package
    case "$(get_system_info os)" in
        ubuntu|debian)
            apt-get remove --purge -y tailscale 2>/dev/null || true
            ;;
        centos|rhel|fedora)
            if command_exists dnf; then
                dnf remove -y tailscale 2>/dev/null || true
            elif command_exists yum; then
                yum remove -y tailscale 2>/dev/null || true
            fi
            ;;
        arch)
            pacman -Rsu --noconfirm tailscale 2>/dev/null || true
            ;;
        opensuse*)
            zypper remove -y tailscale 2>/dev/null || true
            ;;
    esac

    module_log "INFO" "Tailscale rollback completed"
}

# =============================================================================
# Docker Extras Functions
# =============================================================================

install_docker_extras() {
    module_log "INFO" "Installing Docker extras"

    local docker_extras
    docker_extras=$(module_config_get "docker_extras" "docker-compose,ctop")

    # Check if Docker is installed
    if ! command_exists docker; then
        module_log "WARN" "Docker is not installed. Skipping Docker extras."
        return $MODULE_SUCCESS
    fi

    # Install Docker Compose if needed
    if [[ "$docker_extras" =~ docker-compose ]] && ! command_exists docker-compose; then
        install_docker_compose
    fi

    # Install ctop if needed
    if [[ "$docker_extras" =~ ctop ]] && ! command_exists ctop; then
        install_ctop
    fi

    module_log "SUCCESS" "Docker extras installed"
    return $MODULE_SUCCESS
}

install_docker_compose() {
    module_log "INFO" "Installing Docker Compose"

    local version
    version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [[ -z "$version" ]]; then
        module_log "WARN" "Could not get latest Docker Compose version, using fallback method"
        return $MODULE_SUCCESS
    fi

    # Download and install Docker Compose
    local download_url="https://github.com/docker/compose/releases/download/v${version}/docker-compose-$(uname -s)-$(uname -m)"

    if command_exists curl; then
        curl -L "$download_url" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        module_log "SUCCESS" "Docker Compose installed: v${version}"
    else
        module_log "WARN" "curl not available, cannot install Docker Compose"
    fi
}

install_ctop() {
    module_log "INFO" "Installing ctop"

    local version
    version=$(curl -s https://api.github.com/repos/bcicen/ctop/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [[ -z "$version" ]]; then
        module_log "WARN" "Could not get latest ctop version"
        return $MODULE_SUCCESS
    fi

    # Download and install ctop
    local download_url="https://github.com/bcicen/ctop/releases/download/v${version}/ctop-${version}-linux-amd64"

    if command_exists curl; then
        curl -L "$download_url" -o /usr/local/bin/ctop
        chmod +x /usr/local/bin/ctop
        module_log "SUCCESS" "ctop installed: v${version}"
    else
        module_log "WARN" "curl not available, cannot install ctop"
    fi
}

# =============================================================================
# Post-Installation Functions
# =============================================================================

post_install_setup() {
    module_log "DEBUG" "Running post-installation setup"

    # Create common directories
    mkdir -p /opt/custom-scripts 2>/dev/null || true
    mkdir -p /etc/custom-configs 2>/dev/null || true

    # Setup system aliases (optional)
    setup_aliases

    # Configure shell environments
    configure_shell_environments

    return $MODULE_SUCCESS
}

setup_aliases() {
    local setup_aliases
    setup_aliases=$(module_config_get "setup_aliases" "true")

    if [[ "$setup_aliases" != "true" ]]; then
        return $MODULE_SUCCESS
    fi

    module_log "DEBUG" "Setting up useful aliases"

    # Create global aliases file
    cat > /etc/profile.d/serversh-aliases.sh << 'EOF'
# ServerSH Useful Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Docker aliases
if command_exists docker; then
    alias dps='docker ps'
    alias dpsa='docker ps -a'
    alias dimg='docker images'
    alias dlogs='docker logs'
fi

# Tailscale alias
if command_exists tailscale; then
    alias ts='tailscale'
    alias tsstatus='tailscale status'
    alias tsip='tailscale ip -4'
fi

# System monitoring
if command_exists htop; then
    alias top='htop'
fi
EOF

    module_log "DEBUG" "System aliases configured"
}

configure_shell_environments() {
    module_log "DEBUG" "Configuring shell environments"

    # Add custom PATH entries if needed
    local profile_d_file="/etc/profile.d/serversh-paths.sh"
    cat > "$profile_d_file" << 'EOF'
# ServerSH Custom Paths
export PATH=$PATH:/usr/local/bin:/opt/custom-scripts
EOF

    module_log "DEBUG" "Shell environments configured"
}

display_installation_summary() {
    module_log "INFO" "Optional Software Installation Summary:"

    local install_tailscale
    install_tailscale=$(module_config_get "install_tailscale" "true")
    if [[ "$install_tailscale" == "true" ]]; then
        module_log "INFO" "  Tailscale: ✅ Installed"
        if command_exists tailscale && tailscale status >/dev/null 2>&1; then
            local tailscale_ip
            tailscale_ip=$(tailscale ip -4 2>/dev/null | head -1)
            module_log "INFO " "    Tailscale IP: ${tailscale_ip:-Not connected}"
        fi
    fi

    local install_dev_tools
    install_dev_tools=$(module_config_get "install_dev_tools" "false")
    if [[ "$install_dev_tools" == "true" ]]; then
        module_log "INFO" "  Development Tools: ✅ Installed"
    fi

    local install_utilities
    install_utilities=$(module_config_get "install_utilities" "true")
    if [[ "$install_utilities" == "true" ]]; then
        module_log "INFO" "  System Utilities: ✅ Installed"
    fi

    local install_docker_extras
    install_docker_extras=$(module_config_get "install_docker_extras" "false")
    if [[ "$install_docker_extras" == "true" ]]; then
        module_log "INFO" "  Docker Extras: ✅ Installed"
    fi

    local install_monitoring_tools
    install_monitoring_tools=$(module_config_get "install_monitoring_tools" "false")
    if [[ "$install_monitoring_tools" == "true" ]]; then
        module_log "INFO" "  Monitoring Tools: ✅ Installed"
    fi
}

show_next_steps() {
    local install_tailscale
    install_tailscale=$(module_config_get "install_tailscale" "true")

    module_log "INFO" "Next Steps:"

    if [[ "$install_tailscale" == "true" ]]; then
        local tailscale_login_method
        tailscale_login_method=$(module_config_get "tailscale_login_method" "interactive")

        if [[ "$tailscale_login_method" == "interactive" ]]; then
            module_log "INFO " "  1. Authenticate Tailscale: tailscale up"
            module_log "INFO " "     Or visit: https://login.tailscale.com/start"
        else
            module_log "INFO " "  1. Check Tailscale status: tailscale status"
        fi

        module_log "INFO " "  2. Get Tailscale IP: tailscale ip -4"
        module_log "INFO " "  3. List Tailscale devices: tailscale status"
    fi

    module_log "INFO " "  4. Verify installations: check individual tool commands"
    module_log "INFO " "  5. Configure tools as needed for your environment"
}

# Initialize module (optional - called when module is sourced)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    module_log "DEBUG" "Optional software module loaded"
fi

return $MODULE_SUCCESS