#!/bin/bash

# =============================================================================
# Module: Docker Container Platform
# Category: Container
# Description: Installs Docker with MTU 1450, IPv6, and newt_talk network (100% compatible with example.sh)
# Version: 1.0.0
# =============================================================================

# Source module interface
source "${SERVERSH_LIB_DIR}/module_interface.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Required Functions
# =============================================================================

module_get_name() {
    echo "container/docker"
    return $MODULE_SUCCESS
}

module_get_version() {
    echo "1.0.0"
    return $MODULE_SUCCESS
}

module_get_description() {
    echo "Installs Docker with MTU 1450, IPv6 support, and creates newt_talk network (preserves all example.sh functionality)"
    return $MODULE_SUCCESS
}

module_get_category() {
    echo "$MODULE_CATEGORY_CONTAINER"
    return $MODULE_SUCCESS
}

module_get_dependencies() {
    echo "system/update"
    return $MODULE_SUCCESS
}

module_validate_config() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Validating configuration for module: $module_name"

    # Get configuration options (with defaults matching example.sh)
    local version
    version=$(module_config_get "version" "latest")
    local install_user
    install_user=$(module_config_get "install_user" "")
    local mtu
    mtu=$(module_config_get "mtu" "1450")
    local ipv6_enabled
    ipv6_enabled=$(module_config_get "ipv6_enabled" "true")
    local ipv6_subnet
    ipv6_subnet=$(module_config_get "ipv6_subnet" "2001:db8:1::/64")
    local default_network
    default_network=$(module_config_get "default_network" "newt_talk")
    local default_subnet
    default_subnet=$(module_config_get "default_subnet" "172.25.0.0/16")
    local custom_subnet
    custom_subnet=$(module_config_get "custom_subnet" "172.25.1.0/24")
    local custom_ipv6_subnet
    custom_ipv6_subnet=$(module_config_get "custom_ipv6_subnet" "2001:db8:1:1::/80")
    local log_driver
    log_driver=$(module_config_get "log_driver" "json-file")
    local log_max_size
    log_max_size=$(module_config_get "log_max_size" "10m")
    local log_max_files
    log_max_files=$(module_config_get "log_max_files" "3")

    # Validate version
    if [[ -z "$version" ]]; then
        module_log "ERROR" "Docker version cannot be empty"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate MTU
    if ! [[ "$mtu" =~ ^[0-9]+$ ]] || [[ "$mtu" -lt 576 || "$mtu" -gt 9000 ]]; then
        module_log "ERROR" "Invalid MTU: $mtu (must be 576-9000)"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate boolean options
    for option in "ipv6_enabled"; do
        local value
        value=$(module_config_get "$option")
        if [[ "$value" != "true" && "$value" != "false" ]]; then
            module_log "ERROR" "Invalid $option value: $value (must be true or false)"
            return $MODULE_CONFIG_ERROR
        fi
    done

    # Validate network name
    if [[ -z "$default_network" ]]; then
        module_log "ERROR" "Docker network name cannot be empty"
        return $MODULE_CONFIG_ERROR
    fi

    if ! [[ "$default_network" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        module_log "ERROR" "Invalid network name: $default_network"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate subnet format
    if ! is_valid_ipv4 "$(echo "$default_subnet" | cut -d'/' -f1)"; then
        module_log "ERROR" "Invalid default subnet: $default_subnet"
        return $MODULE_CONFIG_ERROR
    fi

    if ! is_valid_ipv4 "$(echo "$custom_subnet" | cut -d'/' -f1)"; then
        module_log "ERROR" "Invalid custom subnet: $custom_subnet"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate IPv6 subnet format
    if [[ "$ipv6_enabled" == "true" ]]; then
        if ! is_valid_ipv6 "${ipv6_subnet%/*}"; then
            module_log "ERROR" "Invalid IPv6 subnet: $ipv6_subnet"
            return $MODULE_CONFIG_ERROR
        fi

        if ! is_valid_ipv6 "${custom_ipv6_subnet%/*}"; then
            module_log "ERROR" "Invalid custom IPv6 subnet: $custom_ipv6_subnet"
            return $MODULE_CONFIG_ERROR
        fi
    fi

    # Validate log options
    local valid_log_drivers=("json-file" "journald" "syslog" "none")
    if ! array_contains "$log_driver" "${valid_log_drivers[@]}"; then
        module_log "ERROR" "Invalid log driver: $log_driver"
        return $MODULE_CONFIG_ERROR
    fi

    module_log "DEBUG" "Configuration validation passed"
    module_log "DEBUG" "  version: $version"
    module_log "DEBUG" "  mtu: $mtu (example.sh compatible)"
    module_log "DEBUG" "  ipv6_enabled: $ipv6_enabled"
    module_log "DEBUG" "  ipv6_subnet: $ipv6_subnet (example.sh compatible)"
    module_log "DEBUG" "  default_network: $default_network (example.sh compatible)"
    module_log "DEBUG" "  default_subnet: $default_subnet (example.sh compatible)"
    module_log "DEBUG" "  custom_subnet: $custom_subnet (example.sh compatible)"
    module_log "DEBUG" "  custom_ipv6_subnet: $custom_ipv6_subnet (example.sh compatible)"
    module_log "DEBUG" "  log_driver: $log_driver"
    module_log "DEBUG" "  log_max_size: $log_max_size"
    module_log "DEBUG" "  log_max_files: $log_max_files"

    return $MODULE_SUCCESS
}

module_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Installing module: $module_name"
    module_log "INFO" "Installing Docker Container Platform (example.sh compatible)"

    # Get OS information
    local os_id
    os_id=$(get_system_info "os")
    module_log "DEBUG" "Detected OS: $os_id"

    # Check if Docker is already installed
    if command_exists docker; then
        local current_version
        current_version=$(docker --version | grep -oP 'version \K[^,]+')
        module_log "INFO" "Docker already installed: $current_version"

        # Check if we need to reconfigure
        local configure_existing
        configure_existing=$(module_config_get "configure_existing" "false")
        if [[ "$configure_existing" == "true" ]]; then
            module_log "INFO" "Reconfiguring existing Docker installation"
        else
            module_log "INFO" "Docker already installed, skipping installation"
            return $MODULE_SKIP
        fi
    fi

    # Install Docker based on OS
    case "$os_id" in
        ubuntu|debian)
            install_docker_debian
            ;;
        centos|rhel|rocky|almalinux)
            install_docker_redhat
            ;;
        fedora)
            install_docker_fedora
            ;;
        arch)
            install_docker_arch
            ;;
        *)
            module_log "ERROR" "Unsupported OS for Docker installation: $os_id"
            return $MODULE_ERROR
            ;;
    esac

    local install_result=$?
    if [[ $install_result -ne $MODULE_SUCCESS ]]; then
        module_log "ERROR" "Docker installation failed"
        return $MODULE_ERROR
    fi

    # Configure Docker daemon with example.sh settings
    if ! configure_docker_daemon; then
        module_log "ERROR" "Docker daemon configuration failed"
        return $MODULE_ERROR
    fi

    # Start and enable Docker service
    if ! start_docker_service; then
        module_log "ERROR" "Failed to start Docker service"
        return $MODULE_ERROR
    fi

    # Add user to docker group if specified
    local install_user
    install_user=$(module_config_get "install_user" "")
    if [[ -n "$install_user" ]]; then
        add_user_to_docker_group "$install_user"
    fi

    # Create Docker network (newt_talk from example.sh)
    if ! create_docker_network; then
        module_log "ERROR" "Failed to create Docker network"
        return $MODULE_ERROR
    fi

    # Verify Docker installation
    if ! verify_docker_installation; then
        module_log "ERROR" "Docker installation verification failed"
        return $MODULE_ERROR
    fi

    module_log "SUCCESS" "Docker installation completed with example.sh compatibility"
    return $MODULE_SUCCESS
}

module_verify() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Verifying Docker installation: $module_name"

    # Check if Docker is installed and running
    if ! command_exists docker; then
        module_log "ERROR" "Docker command not found"
        return $MODULE_ERROR
    fi

    if ! is_service_running "docker"; then
        module_log "ERROR" "Docker service is not running"
        return $MODULE_ERROR
    fi

    # Test Docker functionality
    if ! docker run --rm hello-world >/dev/null 2>&1; then
        module_log "ERROR" "Docker test run failed"
        return $MODULE_ERROR
    fi

    # Verify network exists
    local default_network
    default_network=$(module_config_get "default_network" "newt_talk")
    if ! docker network ls | grep -q "$default_network"; then
        module_log "ERROR" "Docker network '$default_network' not found"
        return $MODULE_ERROR
    fi

    # Verify daemon configuration
    verify_docker_daemon_config

    module_log "DEBUG" "Docker installation verification successful"
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
        module_log "ERROR" "Root privileges required for Docker installation"
        return $MODULE_PERMISSION_DENIED
    fi

    # Check system requirements
    if ! check_system_requirements; then
        return $MODULE_ERROR
    fi

    return $MODULE_SUCCESS
}

module_post_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running post-installation for module: $module_name"

    # Display Docker information
    display_docker_info

    # Show network information
    display_network_info

    # Test container connectivity
    test_container_connectivity

    return $MODULE_SUCCESS
}

module_rollback() {
    local module_name
    module_name=$(module_get_name)

    module_log "WARN" "Rolling back Docker installation: $module_name"

    # Stop Docker service
    systemctl stop docker || true

    # Remove Docker packages
    local os_id
    os_id=$(get_system_info "os")

    case "$os_id" in
        ubuntu|debian)
            apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
            ;;
        centos|rhel|rocky|almalinux|fedora)
            if command_exists dnf; then
                dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
            else
                yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
            fi
            ;;
        *)
            module_log "WARN" "Cannot automatically remove Docker on $os_id"
            ;;
    esac

    # Remove Docker group
    if getent group docker >/dev/null; then
        groupdel docker || true
    fi

    # Remove Docker directories
    rm -rf /var/lib/docker /etc/docker /var/run/docker.sock || true

    module_log "INFO" "Docker rollback completed"
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
# OS-Specific Installation Functions
# =============================================================================

install_docker_debian() {
    module_log "INFO" "Installing Docker on Debian/Ubuntu system"

    # Update package index
    module_log "INFO" "Updating package index..."
    apt-get update

    # Install packages to allow apt to use a repository over HTTPS
    module_log "INFO" "Installing prerequisite packages..."
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    module_log "INFO" "Adding Docker GPG key..."
    curl -fsSL https://download.docker.com/linux/$(get_system_info "os")/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Set up the repository
    module_log "INFO" "Setting up Docker repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$(get_system_info "os") \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package index again
    apt-get update

    # Install Docker Engine
    module_log "INFO" "Installing Docker Engine..."
    local docker_version
    docker_version=$(module_config_get "version" "latest")
    if [[ "$docker_version" != "latest" ]]; then
        # Install specific version
        local package_version="${docker_version}-"
        apt-get install -y docker-ce="${package_version}*" docker-ce-cli="${package_version}*" containerd.io docker-buildx-plugin="${package_version}*" docker-compose-plugin="${package_version}*"
    else
        # Install latest version
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    return $MODULE_SUCCESS
}

install_docker_redhat() {
    module_log "INFO" "Installing Docker on RHEL/CentOS system"

    # Install yum-utils
    module_log "INFO" "Installing yum-utils..."
    yum install -y yum-utils

    # Add Docker repository
    module_log "INFO" "Adding Docker repository..."
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # Install Docker Engine
    module_log "INFO" "Installing Docker Engine..."
    local docker_version
    docker_version=$(module_config_get "version" "latest")
    if [[ "$docker_version" != "latest" ]]; then
        # Install specific version
        yum install -y docker-ce-"${docker_version}*" docker-ce-cli-"${docker_version}*" containerd.io docker-buildx-plugin-"${docker_version}*" docker-compose-plugin-"${docker_version}*"
    else
        # Install latest version
        yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    return $MODULE_SUCCESS
}

install_docker_fedora() {
    module_log "INFO" "Installing Docker on Fedora system"

    # Add Docker repository
    module_log "INFO" "Adding Docker repository..."
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

    # Install Docker Engine
    module_log "INFO" "Installing Docker Engine..."
    local docker_version
    docker_version=$(module_config_get "version" "latest")
    if [[ "$docker_version" != "latest" ]]; then
        # Install specific version
        dnf install -y docker-ce-"${docker_version}*" docker-ce-cli-"${docker_version}*" containerd.io docker-buildx-plugin-"${docker_version}*" docker-compose-plugin-"${docker_version}*"
    else
        # Install latest version
        dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    return $MODULE_SUCCESS
}

install_docker_arch() {
    module_log "INFO" "Installing Docker on Arch Linux"

    # Install Docker from official Arch repositories
    module_log "INFO" "Installing Docker from Arch repositories..."
    pacman -Sy --noconfirm docker

    # Start and enable Docker service
    systemctl enable docker
    systemctl start docker

    # Add user to docker group if needed
    local install_user
    install_user=$(module_config_get "install_user" "")
    if [[ -n "$install_user" ]]; then
        usermod -aG docker "$install_user"
    fi

    return $MODULE_SUCCESS
}

# =============================================================================
# Configuration Functions
# =============================================================================

configure_docker_daemon() {
    module_log "INFO" "Configuring Docker daemon (example.sh compatible settings)"

    local daemon_config="/etc/docker/daemon.json"
    local mtu
    mtu=$(module_config_get "mtu" "1450")
    local ipv6_enabled
    ipv6_enabled=$(module_config_get "ipv6_enabled" "true")
    local ipv6_subnet
    ipv6_subnet=$(module_config_get "ipv6_subnet" "2001:db8:1::/64")
    local default_subnet
    default_subnet=$(module_config_get "default_subnet" "172.25.0.0/16")
    local subnet_size
    subnet_size=$(module_config_get "subnet_size" "24")
    local log_driver
    log_driver=$(module_config_get "log_driver" "json-file")
    local log_max_size
    log_max_size=$(module_config_get "log_max_size" "10m")
    local log_max_files
    log_max_files=$(module_config_get "log_max_files" "3")

    # Backup existing config
    if [[ -f "$daemon_config" ]]; then
        backup_file "$daemon_config" >/dev/null
    fi

    # Create Docker daemon configuration (exact match to example.sh)
    cat > "$daemon_config" << EOF
{
  "mtu": $mtu,
  "ipv6": $ipv6_enabled,
  "fixed-cidr-v6": "$ipv6_subnet",
  "log-driver": "$log_driver",
  "log-opts": {
    "max-size": "$log_max_size",
    "max-file": "$log_max_files"
  },
  "default-address-pools": [
    {
      "base": "$default_subnet",
      "size": $subnet_size
    }
  ]
}
EOF

    # Set proper permissions
    chmod 600 "$daemon_config"

    module_log "SUCCESS" "Docker daemon configured with example.sh settings"
    return $MODULE_SUCCESS
}

start_docker_service() {
    module_log "INFO" "Starting Docker service"

    # Enable Docker service
    systemctl enable docker

    # Start Docker service
    systemctl start docker

    # Wait for Docker to start
    local wait_time=0
    local max_wait=10

    while [[ $wait_time -lt $max_wait ]]; do
        if systemctl is-active --quiet docker; then
            module_log "SUCCESS" "Docker service started successfully"
            return $MODULE_SUCCESS
        fi
        sleep 1
        ((wait_time++))
    done

    module_log "ERROR" "Docker service failed to start within $max_wait seconds"
    return $MODULE_ERROR
}

add_user_to_docker_group() {
    local user="$1"

    module_log "INFO" "Adding user $user to docker group"

    # Check if user exists
    if ! id "$user" >/dev/null 2>&1; then
        module_log "ERROR" "User $user does not exist"
        return $MODULE_ERROR
    fi

    # Add user to docker group
    usermod -aG docker "$user"

    module_log "INFO" "User $user added to docker group"
    module_log "INFO" "Note: User must log out and back in for group changes to take effect"
    return $MODULE_SUCCESS
}

create_docker_network() {
    local default_network
    default_network=$(module_config_get "default_network" "newt_talk")
    local mtu
    mtu=$(module_config_get "mtu" "1450")
    local ipv6_enabled
    ipv6_enabled=$(module_config_get "ipv6_enabled" "true")
    local custom_subnet
    custom_subnet=$(module_config_get "custom_subnet" "172.25.1.0/24")
    local custom_ipv6_subnet
    custom_ipv6_subnet=$(module_config_get "custom_ipv6_subnet" "2001:db8:1:1::/80")

    module_log "INFO" "Creating Docker network: $default_network (example.sh compatible)"

    # Check if network already exists
    if docker network ls | grep -q "$default_network"; then
        module_log "INFO" "Docker network '$default_network' already exists"
        return $MODULE_SUCCESS
    fi

    # Create network command (exact match to example.sh)
    local network_cmd="docker network create"
    network_cmd="$network_cmd --opt com.docker.network.driver.mtu=$mtu"

    if [[ "$ipv6_enabled" == "true" ]]; then
        network_cmd="$network_cmd --ipv6"
    fi

    network_cmd="$network_cmd --subnet=\"$custom_subnet\""
    network_cmd="$network_cmd --subnet=\"$custom_ipv6_subnet\""
    network_cmd="$network_cmd $default_network"

    module_log "DEBUG" "Executing: $network_cmd"

    if eval "$network_cmd"; then
        module_log "SUCCESS" "Docker network '$default_network' created successfully"
        return $MODULE_SUCCESS
    else
        module_log "ERROR" "Failed to create Docker network '$default_network'"
        return $MODULE_ERROR
    fi
}

# =============================================================================
# Verification Functions
# =============================================================================

verify_docker_installation() {
    module_log "DEBUG" "Verifying Docker installation"

    # Test Docker command
    if ! docker --version >/dev/null 2>&1; then
        module_log "ERROR" "Docker command not working"
        return $MODULE_ERROR
    fi

    # Test Docker run
    if ! docker run --rm hello-world >/dev/null 2>&1; then
        module_log "ERROR" "Docker test run failed"
        return $MODULE_ERROR
    fi

    # Test Docker info
    if ! docker info >/dev/null 2>&1; then
        module_log "ERROR" "Docker info command failed"
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "Docker installation verification successful"
    return $MODULE_SUCCESS
}

verify_docker_daemon_config() {
    module_log "DEBUG" "Verifying Docker daemon configuration"

    local daemon_config="/etc/docker/daemon.json"
    if [[ ! -f "$daemon_config" ]]; then
        module_log "ERROR" "Docker daemon configuration file not found"
        return $MODULE_ERROR
    fi

    # Validate JSON syntax
    if ! command_exists jq; then
        module_log "WARN" "jq not available, skipping JSON validation"
        return $MODULE_SUCCESS
    fi

    if ! jq empty "$daemon_config" 2>/dev/null; then
        module_log "ERROR" "Docker daemon configuration has invalid JSON"
        return $MODULE_ERROR
    fi

    # Check for example.sh specific settings
    local mtu
    mtu=$(jq -r '.mtu' "$daemon_config" 2>/dev/null)
    local expected_mtu
    expected_mtu=$(module_config_get "mtu" "1450")

    if [[ "$mtu" != "$expected_mtu" ]]; then
        module_log "ERROR" "Docker MTU configuration mismatch: got $mtu, expected $expected_mtu"
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "Docker daemon configuration verification successful"
    return $MODULE_SUCCESS
}

# =============================================================================
# Helper Functions
# =============================================================================

check_system_requirements() {
    module_log "DEBUG" "Checking system requirements"

    # Check for virtualization support
    if command_exists grep; then
        if grep -qE '(vmx|svm)' /proc/cpuinfo 2>/dev/null; then
            module_log "DEBUG" "CPU virtualization support detected"
        else
            module_log "WARN" "CPU virtualization support not detected. Docker may not work properly."
        fi
    fi

    # Check for cgroups
    if [[ ! -d /sys/fs/cgroup ]]; then
        module_log "ERROR" "cgroups not available. Docker requires cgroups."
        return $MODULE_ERROR
    fi

    # Check kernel version
    local kernel_version
    kernel_version=$(uname -r)
    local kernel_major
    kernel_major=$(echo "$kernel_version" | cut -d. -f1)
    local kernel_minor
    kernel_minor=$(echo "$kernel_version" | cut -d. -f2)

    if [[ $kernel_major -lt 3 ]]; then
        module_log "ERROR" "Kernel version too old: $kernel_version (minimum 3.10 required)"
        return $MODULE_ERROR
    fi

    if [[ $kernel_major -eq 3 && $kernel_minor -lt 10 ]]; then
        module_log "ERROR" "Kernel version too old: $kernel_version (minimum 3.10 required)"
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "System requirements check passed"
    return $MODULE_SUCCESS
}

display_docker_info() {
    module_log "INFO" "Docker Installation Summary:"
    module_log "INFO" "==========================="

    if command_exists docker; then
        module_log "INFO" "Docker Version: $(docker --version)"
        module_log "INFO" "Docker Info: $(docker info | grep 'Server Version' | cut -d: -f2- | xargs)"
    fi

    module_log "INFO" "Configuration:"
    module_log "INFO" "  MTU: $(module_config_get "mtu" "1450")"
    module_log "INFO" "  IPv6 Enabled: $(module_config_get "ipv6_enabled" "true")"
    module_log "INFO" "  Network: $(module_config_get "default_network" "newt_talk")"
    module_log "INFO" "  Subnet: $(module_config_get "custom_subnet" "172.25.1.0/24")"
    module_log "INFO" "  IPv6 Subnet: $(module_config_get "custom_ipv6_subnet" "2001:db8:1:1::/80")"
}

display_network_info() {
    local default_network
    default_network=$(module_config_get "default_network" "newt_talk")

    module_log "INFO" "Docker Network Information:"
    module_log "INFO" "========================="

    if docker network ls | grep -q "$default_network"; then
        module_log "INFO" "Network: $default_network"
        docker network inspect "$default_network" | jq -r '.[0] | "Network: \(.Name)\n  Driver: \(.Driver)\n  Subnet: \(.IPAM.Config[0].Subnet)\n  Gateway: \(.IPAM.Config[0].Gateway)"' 2>/dev/null || {
            module_log "INFO" "Network details: Use 'docker network inspect $default_network' for more info"
        }
    fi
}

test_container_connectivity() {
    local default_network
    default_network=$(module_config_get "default_network" "newt_talk")

    module_log "INFO" "Testing container connectivity..."

    # Test basic connectivity
    if docker run --rm --network="$default_network" busybox ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        module_log "SUCCESS" "Container internet connectivity test passed"
    else
        module_log "WARN" "Container internet connectivity test failed"
    fi

    # Test IPv6 connectivity if enabled
    local ipv6_enabled
    ipv6_enabled=$(module_config_get "ipv6_enabled" "true")
    if [[ "$ipv6_enabled" == "true" ]]; then
        if docker run --rm --network="$default_network" busybox ping -c 1 ipv6.google.com >/dev/null 2>&1; then
            module_log "SUCCESS" "Container IPv6 connectivity test passed"
        else
            module_log "WARN" "Container IPv6 connectivity test failed (may be normal)"
        fi
    fi
}

# Initialize module (optional - called when module is sourced)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    module_log "DEBUG" "Docker container module loaded (example.sh compatible)"
fi

return $MODULE_SUCCESS