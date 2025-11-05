# Technical Specifications: Modular Server Setup Framework

## Core Framework Architecture

### 1. Framework Core (`lib/core/framework.sh`)

```bash
#!/bin/bash

# Core framework for modular server setup
# Version: 2.0.0

# Framework configuration
readonly FRAMEWORK_VERSION="2.0.0"
readonly FRAMEWORK_NAME="ServerSH"
readonly DEFAULT_STATE_DIR="/var/lib/serversh"
readonly DEFAULT_CONFIG_DIR="/etc/serversh"
readonly DEFAULT_LOG_DIR="/var/log/serversh"

# Global state variables
declare -A MODULES_REGISTRY
declare -A MODULES_STATUS
declare -A DEPENDENCY_GRAPH
declare -A CONFIG_CACHE
declare -A HOOK_REGISTRY

# Core framework functions
framework_init() {
    local config_dir="${1:-$DEFAULT_CONFIG_DIR}"
    local state_dir="${1:-$DEFAULT_STATE_DIR}"
    local log_dir="${1:-$DEFAULT_LOG_DIR}"

    # Initialize directories
    mkdir -p "$config_dir" "$state_dir" "$log_dir"

    # Load core libraries
    source "${LIB_DIR}/utils/logging.sh"
    source "${LIB_DIR}/utils/package-manager.sh"
    source "${LIB_DIR}/core/state-manager.sh"
    source "${LIB_DIR}/core/module-loader.sh"

    # Initialize logging
    log_init "$log_dir"

    # Load state
    state_load "$state_dir"

    # Discover modules
    module_discover "${MODULE_DIR}"

    log_info "Framework initialized (v${FRAMEWORK_VERSION})"
}

framework_cleanup() {
    # Save state
    state_save

    # Cleanup resources
    module_cleanup_all

    log_info "Framework cleanup completed"
}
```

### 2. Module Interface Standard (`lib/interfaces/module-interface.sh`)

```bash
#!/bin/bash

# Module interface definition
# All modules must implement this interface

# Module metadata (required)
readonly MODULE_NAME=""
readonly MODULE_VERSION=""
readonly MODULE_DESCRIPTION=""
readonly MODULE_AUTHOR=""
readonly MODULE_LICENSE=""

# Module dependencies
readonly MODULE_DEPENDENCIES=()
readonly MODULE_RECOMMENDS=()
readonly MODULE_CONFLICTS=()
readonly MODULE_PROVIDES=()

# Module hooks (optional)
HOOKS_PRE_INSTALL=()
HOOKS_POST_INSTALL=()
HOOKS_PRE_UNINSTALL=()
HOOKS_POST_UNINSTALL=()

# Required interface functions

# Pre-installation checks
module_pre_check() {
    # Check system requirements
    # Validate dependencies
    # Check for conflicts
    # Return 0 if ready to install
    return 0
}

# Installation logic
module_install() {
    # Main installation logic
    # Configure services
    # Setup permissions
    # Return 0 on success
    return 0
}

# Configuration logic
module_configure() {
    # Apply configuration
    # Start services
    # Validate configuration
    # Return 0 on success
    return 0
}

# Post-installation validation
module_post_check() {
    # Verify installation
    # Test functionality
    # Check service status
    # Return 0 if successful
    return 0
}

# Uninstallation logic
module_uninstall() {
    # Stop services
    # Remove packages
    # Clean up configuration
    # Return 0 on success
    return 0
}

# Status reporting
module_status() {
    # Report current status
    # Check service health
    # Show version info
    echo "status: unknown"
}

# Upgrade logic (optional)
module_upgrade() {
    # Handle version upgrades
    # Migrate configurations
    # Update services
    return 0
}

# Rollback logic (optional)
module_rollback() {
    # Rollback to previous version
    # Restore configuration
    # Restart services
    return 0
}

# Configuration validation
module_validate_config() {
    local config_file="$1"

    # Validate YAML/JSON configuration
    # Check required fields
    # Validate values
    # Return 0 if valid
    return 0
}

# Health check
module_health_check() {
    # Check if module is healthy
    # Test critical functionality
    # Return 0 if healthy
    return 0
}
```

### 3. Module Loader (`lib/core/module-loader.sh`)

```bash
#!/bin/bash

# Module loading and management system

# Module registry
declare -A MODULE_REGISTRY
declare -A MODULE_METADATA
declare -A MODULE_DEPENDENCIES
declare -A MODULE_STATUS

# Discover modules in directory
module_discover() {
    local module_dir="$1"
    local found_modules=0

    log_debug "Discovering modules in: $module_dir"

    # Find all module directories
    find "$module_dir" -name "module.sh" -type f | while read -r module_file; do
        local module_path=$(dirname "$module_file")
        local module_name=$(basename "$module_path")

        if module_validate "$module_file"; then
            module_register "$module_name" "$module_path"
            ((found_modules++))
            log_debug "Discovered module: $module_name"
        else
            log_warning "Invalid module: $module_name"
        fi
    done

    log_info "Discovered $found_modules modules"
    return 0
}

# Validate module interface
module_validate() {
    local module_file="$1"

    # Source module temporarily for validation
    (
        source "$module_file" 2>/dev/null || return 1

        # Check required functions exist
        local required_functions=(
            "module_pre_check"
            "module_install"
            "module_configure"
            "module_post_check"
            "module_uninstall"
            "module_status"
        )

        for func in "${required_functions[@]}"; do
            if ! declare -f "$func" >/dev/null; then
                log_error "Missing required function: $func"
                return 1
            fi
        done

        # Check required metadata
        if [[ -z "$MODULE_NAME" || -z "$MODULE_VERSION" ]]; then
            log_error "Missing required metadata (MODULE_NAME, MODULE_VERSION)"
            return 1
        fi

        return 0
    )
}

# Register module in registry
module_register() {
    local module_name="$1"
    local module_path="$2"

    # Load module metadata
    (
        source "$module_path/module.sh"

        MODULE_REGISTRY["$module_name"]="$module_path"
        MODULE_METADATA["$module_name"]="$MODULE_NAME:$MODULE_VERSION:$MODULE_DESCRIPTION"
        MODULE_DEPENDENCIES["$module_name"]=$(printf '%s ' "${MODULE_DEPENDENCIES[@]}")

        log_debug "Registered module: $module_name ($MODULE_VERSION)"
    )
}

# Load module by name
module_load() {
    local module_name="$1"

    if [[ -z "${MODULE_REGISTRY[$module_name]}" ]]; then
        log_error "Module not found: $module_name"
        return 1
    fi

    local module_path="${MODULE_REGISTRY[$module_name]}"

    # Load module into current environment
    source "$module_path/module.sh"

    log_debug "Loaded module: $module_name"
    return 0
}

# Unload module
module_unload() {
    local module_name="$1"

    # Unset module functions and variables
    unset -f module_pre_check module_install module_configure module_post_check
    unset -f module_uninstall module_status module_upgrade module_rollback
    unset -f module_validate_config module_health_check

    log_debug "Unloaded module: $module_name"
    return 0
}

# Execute module function
module_execute() {
    local module_name="$1"
    local function_name="$2"
    shift 2

    if module_load "$module_name"; then
        if declare -f "$function_name" >/dev/null; then
            "$function_name" "$@"
            local exit_code=$?
            module_unload "$module_name"
            return $exit_code
        else
            log_error "Function not found: $function_name in module $module_name"
            module_unload "$module_name"
            return 1
        fi
    else
        log_error "Failed to load module: $module_name"
        return 1
    fi
}

# Get module status
module_get_status() {
    local module_name="$1"

    if [[ -z "${MODULE_REGISTRY[$module_name]}" ]]; then
        echo "not-found"
        return 1
    fi

    if module_execute "$module_name" "module_status"; then
        echo "active"
        return 0
    else
        echo "error"
        return 1
    fi
}

# List all modules
module_list() {
    local format="${1:-table}"

    case "$format" in
        "table")
            printf "%-20s %-10s %-50s\n" "MODULE" "VERSION" "DESCRIPTION"
            printf "%-20s %-10s %-50s\n" "------" "-------" "-----------"
            for module_name in "${!MODULE_REGISTRY[@]}"; do
                local metadata="${MODULE_METADATA[$module_name]}"
                IFS=':' read -r name version description <<< "$metadata"
                printf "%-20s %-10s %-50s\n" "$name" "$version" "$description"
            done
            ;;
        "json")
            echo "{"
            local first=true
            for module_name in "${!MODULE_REGISTRY[@]}"; do
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                local metadata="${MODULE_METADATA[$module_name]}"
                IFS=':' read -r name version description <<< "$metadata"
                echo "  \"$module_name\": {"
                echo "    \"name\": \"$name\","
                echo "    \"version\": \"$version\","
                echo "    \"description\": \"$description\""
                echo -n "  }"
            done
            echo ""
            echo "}"
            ;;
    esac
}
```

### 4. Configuration Management (`lib/interfaces/config-interface.sh`)

```bash
#!/bin/bash

# Configuration management interface

# Configuration sources (in order of precedence)
CONFIG_SOURCES=(
    "/etc/serversh/defaults.yaml"
    "/etc/serversh/environments/${ENVIRONMENT}.yaml"
    "$HOME/.serversh/config.yaml"
    "./config.yaml"
)

# Configuration cache
declare -A CONFIG_CACHE

# Load configuration from all sources
config_load() {
    local config_file="$1"

    log_debug "Loading configuration from: $config_file"

    if [[ ! -f "$config_file" ]]; then
        log_warning "Configuration file not found: $config_file"
        return 1
    fi

    # Parse configuration based on file type
    case "${config_file##*.}" in
        "yaml"|"yml")
            config_parse_yaml "$config_file"
            ;;
        "json")
            config_parse_json "$config_file"
            ;;
        *)
            log_error "Unsupported configuration format: ${config_file##*.}"
            return 1
            ;;
    esac
}

# Parse YAML configuration
config_parse_yaml() {
    local yaml_file="$1"

    # Use yq if available, otherwise basic parsing
    if command -v yq >/dev/null 2>&1; then
        # Parse with yq and convert to bash variables
        yq eval '.' "$yaml_file" -o json | config_parse_json /dev/stdin
    else
        # Basic YAML parsing (limited functionality)
        config_parse_yaml_basic "$yaml_file"
    fi
}

# Basic YAML parser (fallback)
config_parse_yaml_basic() {
    local yaml_file="$1"
    local current_section=""

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Parse sections
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*: ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse key-value pairs
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Remove quotes and trim whitespace
            value=$(echo "$value" | sed 's/^["'\'']//' | sed 's/["'\'']$//' | xargs)

            # Store in cache
            if [[ -n "$current_section" ]]; then
                CONFIG_CACHE["${current_section}_${key}"]="$value"
            else
                CONFIG_CACHE["$key"]="$value"
            fi
        fi
    done < "$yaml_file"
}

# Parse JSON configuration
config_parse_json() {
    local json_file="$1"

    if command -v jq >/dev/null 2>&1; then
        # Parse with jq and convert to bash variables
        local json_content=$(cat "$json_file")

        # Flatten JSON to dot notation
        echo "$json_content" | jq -r 'paths(scalars) as $p | $p | join(".")' | while read -r path; do
            local value=$(echo "$json_content" | jq -r ".$path")
            CONFIG_CACHE["$path"]="$value"
        done
    else
        log_error "jq is required for JSON configuration parsing"
        return 1
    fi
}

# Get configuration value
config_get() {
    local key="$1"
    local default_value="$2"

    if [[ -n "${CONFIG_CACHE[$key]}" ]]; then
        echo "${CONFIG_CACHE[$key]}"
    else
        echo "$default_value"
    fi
}

# Set configuration value
config_set() {
    local key="$1"
    local value="$2"

    CONFIG_CACHE["$key"]="$value"
}

# Validate configuration against schema
config_validate() {
    local config_file="$1"
    local schema_file="$2"

    if command -v ajv >/dev/null 2>&1; then
        ajv validate -s "$schema_file" -d "$config_file"
    else
        log_warning "ajv not available, skipping JSON schema validation"
        return 0
    fi
}

# Merge configurations
config_merge() {
    local base_config="$1"
    local override_config="$2"
    local output_file="$3"

    if command -v yq >/dev/null 2>&1; then
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$base_config" "$override_config" > "$output_file"
    else
        log_error "yq is required for configuration merging"
        return 1
    fi
}
```

### 5. State Management (`lib/core/state-manager.sh`)

```bash
#!/bin/bash

# State management system

# State file locations
STATE_FILE="/var/lib/serversh/state.json"
ROLLBACK_DIR="/var/lib/serversh/rollbacks"
BACKUP_DIR="/var/lib/serversh/backups"

# Current state
declare -A CURRENT_STATE
declare -A ROLLBACK_POINTS

# Load state from file
state_load() {
    local state_file="${1:-$STATE_FILE}"

    if [[ -f "$state_file" ]]; then
        log_debug "Loading state from: $state_file"

        if command -v jq >/dev/null 2>&1; then
            # Parse JSON state
            local state_content=$(cat "$state_file")

            # Load modules state
            echo "$state_content" | jq -r '.modules | to_entries[] | "\(.key)=\(.value.status)"' | while IFS='=' read -r key value; do
                CURRENT_STATE["$key"]="$value"
            done
        else
            log_error "jq is required for state management"
            return 1
        fi
    else
        log_info "State file not found, initializing empty state"
        state_init
    fi

    return 0
}

# Save state to file
state_save() {
    local state_file="${1:-$STATE_FILE}"

    log_debug "Saving state to: $state_file"

    # Create state directory if needed
    mkdir -p "$(dirname "$state_file")"

    # Build JSON state
    local state_json=$(cat << EOF
{
  "version": "2.0.0",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "modules": {
EOF
)

    # Add modules state
    local first=true
    for module_name in "${!CURRENT_STATE[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            state_json+=","
        fi
        state_json+="
    \"$module_name\": {
      \"status\": \"${CURRENT_STATE[$module_name]}\",
      \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    }"
    done

    state_json+="
  },
  \"framework\": {
    \"version\": \"$FRAMEWORK_VERSION\",
    \"last_run\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
  }
}
EOF
)

    echo "$state_json" > "$state_file"
    log_debug "State saved successfully"
}

# Initialize empty state
state_init() {
    CURRENT_STATE=()
    ROLLBACK_POINTS=()

    # Create directories
    mkdir -p "$ROLLBACK_DIR" "$BACKUP_DIR"

    log_info "State initialized"
}

# Set module state
state_set_module_status() {
    local module_name="$1"
    local status="$2"

    CURRENT_STATE["$module_name"]="$status"
    log_debug "Module $module_name status set to: $status"
}

# Get module state
state_get_module_status() {
    local module_name="$1"
    echo "${CURRENT_STATE[$module_name]:-not-installed}"
}

# Create rollback point
state_create_rollback_point() {
    local description="$1"
    local rollback_id="rollback_$(date +%Y%m%d_%H%M%S)"

    log_info "Creating rollback point: $rollback_id ($description)"

    # Create rollback directory
    local rollback_path="$ROLLBACK_DIR/$rollback_id"
    mkdir -p "$rollback_path"

    # Save current state
    state_save "$rollback_path/state.json"

    # Backup critical files
    backup_critical_files "$rollback_path"

    # Save rollback metadata
    cat > "$rollback_path/metadata.json" << EOF
{
  "id": "$rollback_id",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "description": "$description",
  "modules": [$(printf '"%s",' "${!CURRENT_STATE[@]}" | sed 's/,$//')]
}
EOF

    ROLLBACK_POINTS["$rollback_id"]="$description"
    echo "$rollback_id"
}

# Rollback to point
state_rollback() {
    local rollback_id="$1"
    local rollback_path="$ROLLBACK_DIR/$rollback_id"

    if [[ ! -d "$rollback_path" ]]; then
        log_error "Rollback point not found: $rollback_id"
        return 1
    fi

    log_info "Rolling back to: $rollback_id"

    # Restore state
    if [[ -f "$rollback_path/state.json" ]]; then
        state_load "$rollback_path/state.json"
    fi

    # Restore critical files
    restore_critical_files "$rollback_path"

    # Execute module rollbacks
    local modules=($(jq -r '.modules[]' "$rollback_path/metadata.json" 2>/dev/null))
    for module_name in "${modules[@]}"; do
        if module_load "$module_name"; then
            if declare -f module_rollback >/dev/null; then
                log_info "Rolling back module: $module_name"
                module_rollback || log_warning "Module rollback failed: $module_name"
            fi
            module_unload "$module_name"
        fi
    done

    log_info "Rollback completed: $rollback_id"
}

# List rollback points
state_list_rollback_points() {
    local format="${1:-table}"

    case "$format" in
        "table")
            printf "%-20s %-20s %-30s\n" "ROLLBACK ID" "TIMESTAMP" "DESCRIPTION"
            printf "%-20s %-20s %-30s\n" "-----------" "---------" "-----------"

            for rollback_dir in "$ROLLBACK_DIR"/rollback_*; do
                if [[ -d "$rollback_dir" ]]; then
                    local rollback_id=$(basename "$rollback_dir")
                    local metadata_file="$rollback_dir/metadata.json"

                    if [[ -f "$metadata_file" ]]; then
                        local timestamp=$(jq -r '.timestamp' "$metadata_file")
                        local description=$(jq -r '.description' "$metadata_file")
                        printf "%-20s %-20s %-30s\n" "$rollback_id" "$timestamp" "$description"
                    fi
                fi
            done
            ;;
    esac
}

# Backup critical files
backup_critical_files() {
    local backup_path="$1"
    local backup_files=(
        "/etc/passwd"
        "/etc/group"
        "/etc/shadow"
        "/etc/ssh/sshd_config"
        "/etc/fstab"
        "/etc/hosts"
    )

    mkdir -p "$backup_path/files"

    for file in "${backup_files[@]}"; do
        if [[ -f "$file" ]]; then
            cp "$file" "$backup_path/files/"
            log_debug "Backed up: $file"
        fi
    done
}

# Restore critical files
restore_critical_files() {
    local backup_path="$1"
    local files_dir="$backup_path/files"

    if [[ -d "$files_dir" ]]; then
        cp -r "$files_dir"/* /
        log_debug "Restored critical files from: $files_dir"
    fi
}
```

## Docker Module Specification

### Enhanced Docker Module Structure

```
modules/infrastructure/docker/
├── module.sh                    # Main module implementation
├── config/
│   ├── daemon.json.j2           # Docker daemon template
│   ├── docker-compose.yaml.j2   # Compose template
│   └── registry-config.yaml     # Registry configuration
├── scripts/
│   ├── install.sh               # Installation script
│   ├── configure.sh             # Configuration script
│   ├── network-setup.sh         # Network configuration
│   └── security-hardening.sh    # Security hardening
├── templates/
│   ├── stacks/                  # Docker Compose stack templates
│   └── services/                # Service configuration templates
├── tests/
│   ├── unit/                    # Unit tests
│   └── integration/             # Integration tests
└── docs/
    ├── configuration.md         # Configuration documentation
    └── examples/                # Usage examples
```

### Docker Module Implementation

```bash
#!/bin/bash

# Docker Infrastructure Module
# Provides container platform with enhanced networking and security

# Module metadata
readonly MODULE_NAME="docker"
readonly MODULE_VERSION="2.0.0"
readonly MODULE_DESCRIPTION="Docker container platform with enhanced networking and security"
readonly MODULE_AUTHOR="ServerSH Team"
readonly MODULE_LICENSE="MIT"

# Module dependencies
readonly MODULE_DEPENDENCIES=("system-detection" "network" "security")
readonly MODULE_RECOMMENDS=("monitoring" "logging")
readonly MODULE_CONFLICTS=("podman" "containerd")
readonly MODULE_PROVIDES=("container-runtime")

# Module configuration
DOCKER_VERSION=""
DOCKER_INSTALL_METHOD=""
DOCKER_NETWORK_MTU="1450"
DOCKER_ENABLE_IPV6="true"
DOCKER_STORAGE_DRIVER="overlay2"
DOCKER_LOG_DRIVER="json-file"

# Load configuration
module_load_config() {
    DOCKER_VERSION=$(config_get "docker.version" "latest")
    DOCKER_INSTALL_METHOD=$(config_get "docker.install_method" "repository")
    DOCKER_NETWORK_MTU=$(config_get "docker.network.mtu" "1450")
    DOCKER_ENABLE_IPV6=$(config_get "docker.network.ipv6" "true")
    DOCKER_STORAGE_DRIVER=$(config_get "docker.storage.driver" "overlay2")
    DOCKER_LOG_DRIVER=$(config_get "docker.logging.driver" "json-file")
}

# Pre-installation checks
module_pre_check() {
    module_load_config

    log_info "Performing Docker pre-installation checks..."

    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        local installed_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        log_info "Docker already installed: $installed_version"

        if [[ "$DOCKER_VERSION" != "latest" && "$installed_version" != "$DOCKER_VERSION" ]]; then
            log_warning "Docker version mismatch. Installed: $installed_version, Requested: $DOCKER_VERSION"
        fi

        return 0
    fi

    # Check system requirements
    local kernel_version=$(uname -r)
    local major_version=$(echo "$kernel_version" | cut -d. -f1)
    local minor_version=$(echo "$kernel_version" | cut -d. -f2)

    if [[ $major_version -lt 3 || ($major_version -eq 3 && $minor_version -lt 10) ]]; then
        log_error "Docker requires kernel version 3.10 or higher"
        return 1
    fi

    # Check architecture
    local arch=$(uname -m)
    case "$arch" in
        "x86_64"|"aarch64"|"armv7l")
            log_info "Supported architecture: $arch"
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    # Check available disk space (minimum 20GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=$((20 * 1024 * 1024)) # 20GB in KB

    if [[ $available_space -lt $required_space ]]; then
        log_error "Insufficient disk space. Required: 20GB, Available: $((available_space / 1024 / 1024))GB"
        return 1
    fi

    log_info "Docker pre-installation checks passed"
    return 0
}

# Installation logic
module_install() {
    log_info "Installing Docker..."

    # Create Docker user
    if ! getent group docker >/dev/null 2>&1; then
        groupadd docker
        log_info "Created docker group"
    fi

    # Install Docker based on method
    case "$DOCKER_INSTALL_METHOD" in
        "repository")
            docker_install_from_repository
            ;;
        "package")
            docker_install_from_package
            ;;
        "binary")
            docker_install_from_binary
            ;;
        *)
            log_error "Unsupported installation method: $DOCKER_INSTALL_METHOD"
            return 1
            ;;
    esac

    # Verify installation
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker installed successfully: $(docker --version)"
        return 0
    else
        log_error "Docker installation failed"
        return 1
    fi
}

# Install Docker from official repository
docker_install_from_repository() {
    local os_id=$(get_os_id)

    log_info "Installing Docker from official repository..."

    case "$os_id" in
        "ubuntu"|"debian")
            docker_install_ubuntu_debian
            ;;
        "centos"|"rhel"|"rocky"|"almalinux"|"fedora")
            docker_install_rhel_family
            ;;
        *)
            log_error "Unsupported OS for repository installation: $os_id"
            return 1
            ;;
    esac
}

# Install Docker on Ubuntu/Debian
docker_install_ubuntu_debian() {
    local os_id=$(get_os_id)

    log_info "Installing Docker on $os_id..."

    # Install prerequisites
    apt-get update
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/$os_id/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$os_id $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# Install Docker on RHEL family
docker_install_rhel_family() {
    log_info "Installing Docker on RHEL family..."

    # Install prerequisites
    yum install -y yum-utils

    # Add Docker repository
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # Install Docker
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# Configuration logic
module_configure() {
    log_info "Configuring Docker..."

    # Create Docker daemon configuration
    docker_configure_daemon

    # Configure Docker networks
    docker_configure_networks

    # Configure storage
    docker_configure_storage

    # Configure logging
    docker_configure_logging

    # Start and enable Docker service
    systemctl enable docker
    systemctl start docker

    # Wait for Docker to start
    local timeout=30
    while ! docker info >/dev/null 2>&1 && [[ $timeout -gt 0 ]]; do
        sleep 1
        ((timeout--))
    done

    if [[ $timeout -eq 0 ]]; then
        log_error "Docker failed to start within timeout"
        return 1
    fi

    log_info "Docker configured successfully"
    return 0
}

# Configure Docker daemon
docker_configure_daemon() {
    local daemon_config="/etc/docker/daemon.json"

    log_info "Configuring Docker daemon..."

    # Backup existing configuration
    if [[ -f "$daemon_config" ]]; then
        cp "$daemon_config" "$daemon_config.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Create daemon configuration
    cat > "$daemon_config" << EOF
{
  "log-driver": "$DOCKER_LOG_DRIVER",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "$DOCKER_STORAGE_DRIVER",
  "default-address-pools": [
    {
      "base": "172.25.0.0/16",
      "size": 24
    }
  ],
  "mtu": $DOCKER_NETWORK_MTU,
  "ipv6": $DOCKER_ENABLE_IPV6,
EOF

    if [[ "$DOCKER_ENABLE_IPV6" == "true" ]]; then
        cat >> "$daemon_config" << EOF
  "fixed-cidr-v6": "2001:db8:1::/64",
EOF
    fi

    cat >> "$daemon_config" << EOF
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false,
  "metrics-addr": "127.0.0.1:9323",
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF

    log_info "Docker daemon configuration created"
}

# Configure Docker networks
docker_configure_networks() {
    log_info "Configuring Docker networks..."

    # Wait for Docker to be available
    while ! docker info >/dev/null 2>&1; do
        sleep 1
    done

    # Create default networks
    docker network create \
        --driver bridge \
        --opt com.docker.network.driver.mtu="$DOCKER_NETWORK_MTU" \
        --opt com.docker.network.bridge.enable_icc=true \
        --opt com.docker.network.bridge.enable_ip_masquerade=true \
        --subnet="172.25.1.0/24" \
        newt_talk 2>/dev/null || log_info "Network newt_talk already exists"

    if [[ "$DOCKER_ENABLE_IPV6" == "true" ]]; then
        docker network create \
            --driver bridge \
            --opt com.docker.network.driver.mtu="$DOCKER_NETWORK_MTU" \
            --ipv6 \
            --subnet="2001:db8:1:1::/80" \
            newt_talk_ipv6 2>/dev/null || log_info "Network newt_talk_ipv6 already exists"
    fi

    log_info "Docker networks configured"
}

# Post-installation validation
module_post_check() {
    log_info "Performing Docker post-installation validation..."

    # Check if Docker daemon is running
    if ! systemctl is-active --quiet docker; then
        log_error "Docker daemon is not running"
        return 1
    fi

    # Test Docker functionality
    if ! docker run --rm hello-world >/dev/null 2>&1; then
        log_error "Docker test container failed"
        return 1
    fi

    # Check Docker networks
    if ! docker network ls | grep -q "newt_talk"; then
        log_warning "Docker network 'newt_talk' not found"
    fi

    # Verify configuration
    local daemon_config="/etc/docker/daemon.json"
    if [[ ! -f "$daemon_config" ]]; then
        log_error "Docker daemon configuration not found"
        return 1
    fi

    # Test network connectivity
    if docker run --rm --network=newt_talk busybox ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_info "Docker network connectivity test passed"
    else
        log_warning "Docker network connectivity test failed"
    fi

    log_info "Docker post-installation validation completed"
    return 0
}

# Status reporting
module_status() {
    if command -v docker >/dev/null 2>&1; then
        local version=$(docker --version)
        local daemon_status=$(systemctl is-active docker)
        local containers_running=$(docker ps -q | wc -l)
        local images_count=$(docker images -q | wc -l)

        echo "status: installed"
        echo "version: $version"
        echo "daemon_status: $daemon_status"
        echo "containers_running: $containers_running"
        echo "images_count: $images_count"
    else
        echo "status: not_installed"
    fi
}

# Uninstallation logic
module_uninstall() {
    log_info "Uninstalling Docker..."

    # Stop Docker service
    systemctl stop docker 2>/dev/null || true
    systemctl disable docker 2>/dev/null || true

    # Remove Docker packages
    case "$(get_os_id)" in
        "ubuntu"|"debian")
            apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            apt-get autoremove -y
            ;;
        "centos"|"rhel"|"rocky"|"almalinux"|"fedora")
            yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
    esac

    # Remove Docker directories
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd
    rm -f /etc/docker/daemon.json

    # Remove Docker group
    groupdel docker 2>/dev/null || true

    log_info "Docker uninstalled"
}

# Health check
module_health_check() {
    if ! command -v docker >/dev/null 2>&1; then
        return 1
    fi

    # Check daemon status
    if ! systemctl is-active --quiet docker; then
        return 1
    fi

    # Test basic functionality
    if ! docker version >/dev/null 2>&1; then
        return 1
    fi

    return 0
}
```

This comprehensive technical specification provides:

1. **Core Framework Architecture**: Modular, event-driven system with hooks and plugins
2. **Module Interface Standard**: Clear contract for all modules
3. **Module Loading System**: Dynamic discovery, validation, and execution
4. **Configuration Management**: YAML/JSON support with validation and merging
5. **State Management**: Persistent state with rollback capabilities
6. **Enhanced Docker Module**: Complete implementation with networking and security

The design maintains compatibility with the existing script's features while providing a much more maintainable and extensible architecture.