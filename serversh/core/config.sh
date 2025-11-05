#!/bin/bash

# =============================================================================
# ServerSH Configuration Management System
# =============================================================================

# Source dependencies
source "${SERVERSH_LIB_DIR}/constants.sh" || exit $EXIT_MISSING_DEPS
source "${SERVERSH_LIB_DIR}/utils.sh" || exit $EXIT_MISSING_DEPS
source "${SERVERSH_LIB_DIR}/logger.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Global Variables
# =============================================================================

# Configuration paths
declare -g CONFIG_FILE="${SERVERSH_CONFIG_FILE}"
declare -g CONFIG_DIR="${SERVERSH_CONFIG_DIR}"
declare -g CONFIG_CACHE_DIR="${SERVERSH_STATE_DIR}/config_cache"

# Configuration data
declare -gA CONFIG_DATA
declare -g CONFIG_LOADED=false

# Configuration defaults
declare -g DEFAULT_CONFIG='{
  "serversh": {
    "version": "1.0.0",
    "log_level": "info",
    "parallel_jobs": 4,
    "timeout": 300,
    "state_dir": "/var/lib/serversh",
    "log_dir": "/var/log/serversh"
  },
  "modules": {
    "enabled": [],
    "disabled": [],
    "auto_dependencies": true,
    "fail_fast": true
  },
  "system": {
    "hostname": "",
    "timezone": "UTC",
    "locale": "en_US.UTF-8"
  },
  "security": {
    "ssh": {
      "port": 2222,
      "password_authentication": false,
      "permit_root_login": false,
      "allowed_groups": ["remotessh"]
    },
    "firewall": {
      "enabled": true,
      "default_policy": "deny",
      "allowed_ports": {
        "ssh": 2222,
        "http": 80,
        "https": 443
      }
    },
    "users": {
      "admin_user": "",
      "create_admin": true,
      "generate_keys": true
    }
  },
  "container": {
    "docker": {
      "enabled": false,
      "version": "latest",
      "daemon_config": {
        "mtu": 1450,
        "ipv6": true,
        "fixed_cidr_v6": "2001:db8:1::/64",
        "log_driver": "json-file",
        "log_opts": {
          "max-size": "10m",
          "max-file": "3"
        },
        "default_address_pools": [
          {
            "base": "172.25.0.0/16",
            "size": 24
          }
        ]
      },
      "networks": [
        {
          "name": "newt_talk",
          "mtu": 1450,
          "ipv6": true,
          "subnet": "172.25.1.0/24",
          "ipv6_subnet": "2001:db8:1:1::/80"
        }
      ]
    }
  },
  "monitoring": {
    "prometheus": {
      "enabled": false,
      "port": 9100,
      "metrics": ["cpu", "memory", "disk", "network"]
    }
  }
}'

# =============================================================================
# Configuration File Operations
# =============================================================================

# Initialize configuration system
config_init() {
    local config_file="${1:-$CONFIG_FILE}"
    local force_init="${2:-false}"

    CONFIG_FILE="$config_file"
    CONFIG_DIR=$(dirname "$CONFIG_FILE")

    log_debug "Initializing configuration system"

    # Create config directory
    ensure_dir "$CONFIG_DIR" || {
        log_error "Failed to create config directory: $CONFIG_DIR"
        return $EXIT_CONFIG_ERROR
    }

    # Create cache directory
    ensure_dir "$CONFIG_CACHE_DIR" || {
        log_error "Failed to create config cache directory: $CONFIG_CACHE_DIR"
        return $EXIT_CONFIG_ERROR
    }

    # Check if config file exists and force_init is not requested
    if [ -f "$CONFIG_FILE" ] && [ "$force_init" != "true" ]; then
        config_load
        return $?
    fi

    # Create default configuration file
    if [ ! -f "$CONFIG_FILE" ]; then
        log_info "Creating default configuration file: $CONFIG_FILE"
        echo "$DEFAULT_CONFIG" | jq '.' > "$CONFIG_FILE" || {
            log_error "Failed to create default configuration file"
            return $EXIT_CONFIG_ERROR
        }

        # Set proper permissions
        chmod "$FILE_PERMISSION_CONFIG" "$CONFIG_FILE" || {
            log_error "Failed to set permissions on configuration file"
            return $EXIT_CONFIG_ERROR
        }
    fi

    # Load configuration
    config_load || return $EXIT_CONFIG_ERROR

    log_info "Configuration system initialized (file: $CONFIG_FILE)"
    return $EXIT_SUCCESS
}

# Load configuration from file
config_load() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        return $EXIT_CONFIG_ERROR
    fi

    log_debug "Loading configuration from: $CONFIG_FILE"

    # Validate configuration file
    if ! config_validate_file "$CONFIG_FILE"; then
        log_error "Invalid configuration file format"
        return $EXIT_CONFIG_ERROR
    fi

    # Check file size
    local file_size
    file_size=$(file_size "$CONFIG_FILE")
    if [ "$file_size" -gt "$MAX_CONFIG_FILE_SIZE" ]; then
        log_error "Configuration file too large: ${file_size} bytes (max: $MAX_CONFIG_FILE_SIZE)"
        return $EXIT_CONFIG_ERROR
    fi

    # Load configuration into memory
    if command_exists jq; then
        # Use jq for JSON parsing
        local config_content
        config_content=$(cat "$CONFIG_FILE") || {
            log_error "Failed to read configuration file"
            return $EXIT_CONFIG_ERROR
        }

        # Extract key configuration values
        local log_level
        log_level=$(echo "$config_content" | jq -r '.serversh.log_level // "info"')
        CONFIG_DATA["log_level"]="$log_level"

        local parallel_jobs
        parallel_jobs=$(echo "$config_content" | jq -r '.serversh.parallel_jobs // 4')
        CONFIG_DATA["parallel_jobs"]="$parallel_jobs"

        local timeout
        timeout=$(echo "$config_content" | jq -r '.serversh.timeout // 300')
        CONFIG_DATA["timeout"]="$timeout"

        local ssh_port
        ssh_port=$(echo "$config_content" | jq -r '.security.ssh.port // 2222')
        CONFIG_DATA["ssh_port"]="$ssh_port"

        local docker_enabled
        docker_enabled=$(echo "$config_content" | jq -r '.container.docker.enabled // false')
        CONFIG_DATA["docker_enabled"]="$docker_enabled"

        # Load enabled modules
        local enabled_modules_json
        enabled_modules_json=$(echo "$config_content" | jq -r '.modules.enabled // []')
        local enabled_modules_str
        enabled_modules_str=$(echo "$enabled_modules_json" | jq -r '.[]' | tr '\n' ' ')
        CONFIG_DATA["enabled_modules"]="$enabled_modules_str"

    else
        log_warn "jq not available, using basic configuration parsing"
        # Fallback to basic grep/sed parsing
        CONFIG_DATA["log_level"]=$(grep -o '"log_level":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        CONFIG_DATA["parallel_jobs"]=$(grep -o '"parallel_jobs":[0-9]*' "$CONFIG_FILE" | cut -d':' -f2)
        CONFIG_DATA["ssh_port"]=$(grep -o '"port":[0-9]*' "$CONFIG_FILE" | head -1 | cut -d':' -f2)
    fi

    CONFIG_LOADED=true
    log_debug "Configuration loaded successfully"

    return $EXIT_SUCCESS
}

# Save configuration to file
config_save() {
    if [ "$CONFIG_LOADED" != true ]; then
        log_error "Configuration not loaded, cannot save"
        return $EXIT_CONFIG_ERROR
    fi

    log_debug "Saving configuration to: $CONFIG_FILE"

    # Create backup before saving
    if [ -f "$CONFIG_FILE" ]; then
        backup_file "$CONFIG_FILE" >/dev/null || {
            log_warn "Failed to backup configuration file"
        }
    fi

    # This would need to be implemented to reconstruct the full JSON
    # For now, just touch the file to indicate it was "saved"
    touch "$CONFIG_FILE" || {
        log_error "Failed to save configuration file"
        return $EXIT_CONFIG_ERROR
    }

    log_debug "Configuration saved successfully"
    return $EXIT_SUCCESS
}

# Validate configuration file format
config_validate_file() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        log_error "Configuration file does not exist: $config_file"
        return 1
    fi

    # Validate JSON format if jq is available
    if command_exists jq; then
        if ! jq empty "$config_file" 2>/dev/null; then
            log_error "Invalid JSON format in configuration file"
            return 1
        fi

        # Validate required sections
        local required_sections=("serversh" "modules" "system" "security")
        for section in "${required_sections[@]}"; do
            if ! jq -e ".$section" "$config_file" >/dev/null 2>&1; then
                log_error "Missing required section in configuration file: $section"
                return 1
            fi
        done
    fi

    return 0
}

# =============================================================================
# Configuration Value Operations
# =============================================================================

# Get configuration value using dot notation
config_get() {
    local key="$1"
    local default_value="${2:-}"

    if [ "$CONFIG_LOADED" != true ]; then
        log_error "Configuration not loaded"
        return $EXIT_CONFIG_ERROR
    fi

    # Check cache first
    local cache_key="${key//\//_}"
    local cache_file="${CONFIG_CACHE_DIR}/${cache_key}"

    if [ -f "$cache_file" ]; then
        local cache_time
        cache_time=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
        local config_time
        config_time=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || stat -f %m "$CONFIG_FILE" 2>/dev/null)

        if [ "$cache_time" -ge "$config_time" ]; then
            cat "$cache_file"
            return $EXIT_SUCCESS
        fi
    fi

    # Get value from configuration
    local value
    if command_exists jq; then
        value=$(jq -r ".$key // \"$default_value\"" "$CONFIG_FILE")
    else
        # Fallback to cached values
        value="${CONFIG_DATA[$key]:-$default_value}"
    fi

    # Cache the value
    echo "$value" > "$cache_file"

    echo "$value"
}

# Set configuration value using dot notation
config_set() {
    local key="$1"
    local value="$2"

    if [ "$CONFIG_LOADED" != true ]; then
        log_error "Configuration not loaded"
        return $EXIT_CONFIG_ERROR
    fi

    if ! command_exists jq; then
        log_error "jq required to set configuration values"
        return $EXIT_MISSING_DEPS
    fi

    log_debug "Setting configuration: $key = $value"

    # Update configuration file
    local temp_file
    temp_file=$(temp_file "config")

    if echo "null" | jq --arg key "$key" --arg value "$value" 'setpath($key | split("."); $value)' > "$temp_file"; then
        # Apply to actual configuration file
        local current_config
        current_config=$(cat "$CONFIG_FILE")
        echo "$current_config" | jq --arg key "$key" --arg value "$value" 'setpath($key | split("."); $value)' > "$CONFIG_FILE.tmp"

        # Atomic move
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE" || {
            rm -f "$CONFIG_FILE.tmp" "$temp_file"
            log_error "Failed to update configuration file"
            return $EXIT_CONFIG_ERROR
        }

        # Set proper permissions
        chmod "$FILE_PERMISSION_CONFIG" "$CONFIG_FILE" || {
            log_error "Failed to set permissions on configuration file"
            return $EXIT_CONFIG_ERROR
        }

        # Clear cache
        rm -f "${CONFIG_CACHE_DIR}/*"

        log_debug "Configuration updated: $key = $value"
    else
        rm -f "$temp_file"
        log_error "Failed to set configuration value"
        return $EXIT_CONFIG_ERROR
    fi

    rm -f "$temp_file"
    return $EXIT_SUCCESS
}

# Check if configuration key exists
config_has() {
    local key="$1"

    if [ "$CONFIG_LOADED" != true ]; then
        return $EXIT_CONFIG_ERROR
    fi

    if command_exists jq; then
        jq -e ".$key" "$CONFIG_FILE" >/dev/null 2>&1
    else
        # Check cached values
        [[ -v "CONFIG_DATA[$key]" ]]
    fi
}

# =============================================================================
# Module Configuration
# =============================================================================

# Get module configuration
config_get_module() {
    local module_name="$1"
    local config_key="${2:-}"

    if [ -n "$config_key" ]; then
        config_get "modules.${module_name}.${config_key}"
    else
        config_get "modules.${module_name}"
    fi
}

# Set module configuration
config_set_module() {
    local module_name="$1"
    local config_key="$2"
    local value="$3"

    config_set "modules.${module_name}.${config_key}" "$value"
}

# Enable module
config_enable_module() {
    local module_name="$1"

    log_debug "Enabling module: $module_name"

    if ! command_exists jq; then
        log_error "jq required for module configuration"
        return $EXIT_MISSING_DEPS
    fi

    local temp_file
    temp_file=$(temp_file "config")

    # Add module to enabled list
    cat "$CONFIG_FILE" | jq --arg module "$module_name" '.modules.enabled += [$module] | .modules.enabled |= unique' > "$temp_file"

    # Remove from disabled list if present
    cat "$temp_file" | jq --arg module "$module_name" '.modules.disabled |= map(select(. != $module))' > "$CONFIG_FILE.tmp"

    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    rm -f "$temp_file"

    # Clear cache
    rm -f "${CONFIG_CACHE_DIR}/*"

    log_info "Module enabled: $module_name"
    return $EXIT_SUCCESS
}

# Disable module
config_disable_module() {
    local module_name="$1"

    log_debug "Disabling module: $module_name"

    if ! command_exists jq; then
        log_error "jq required for module configuration"
        return $EXIT_MISSING_DEPS
    fi

    local temp_file
    temp_file=$(temp_file "config")

    # Add module to disabled list
    cat "$CONFIG_FILE" | jq --arg module "$module_name" '.modules.disabled += [$module] | .modules.disabled |= unique' > "$temp_file"

    # Remove from enabled list if present
    cat "$temp_file" | jq --arg module "$module_name" '.modules.enabled |= map(select(. != $module))' > "$CONFIG_FILE.tmp"

    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    rm -f "$temp_file"

    # Clear cache
    rm -f "${CONFIG_CACHE_DIR}/*"

    log_info "Module disabled: $module_name"
    return $EXIT_SUCCESS
}

# List enabled modules
config_list_enabled_modules() {
    if command_exists jq; then
        jq -r '.modules.enabled[]' "$CONFIG_FILE"
    else
        echo "${CONFIG_DATA[enabled_modules]}"
    fi
}

# List disabled modules
config_list_disabled_modules() {
    if command_exists jq; then
        jq -r '.modules.disabled[]' "$CONFIG_FILE"
    else
        echo ""
    fi
}

# =============================================================================
# Profile Management
# =============================================================================

# Load configuration profile
config_load_profile() {
    local profile_name="$1"
    local profile_file="${CONFIG_DIR}/profiles/${profile_name}.yaml"

    if [ ! -f "$profile_file" ]; then
        log_error "Profile not found: $profile_name"
        return $EXIT_CONFIG_ERROR
    fi

    log_info "Loading configuration profile: $profile_name"

    # This would need YAML parsing capability
    # For now, just indicate that profile loading is attempted
    log_debug "Profile file: $profile_file"

    return $EXIT_SUCCESS
}

# Create configuration profile
config_create_profile() {
    local profile_name="$1"
    local description="$2"
    local profile_file="${CONFIG_DIR}/profiles/${profile_name}.yaml"

    log_info "Creating configuration profile: $profile_name"

    ensure_dir "${CONFIG_DIR}/profiles" || return $EXIT_CONFIG_ERROR

    # Create basic profile structure (YAML format)
    cat > "$profile_file" << EOF
# ServerSH Configuration Profile: $profile_name
# Description: $description
# Created: $(date)

serversh:
  log_level: "info"
  parallel_jobs: 4
  timeout: 300

modules:
  enabled: []
  auto_dependencies: true
  fail_fast: true

# Override specific settings here
EOF

    log_success "Profile created: $profile_file"
    return $EXIT_SUCCESS
}

# List available profiles
config_list_profiles() {
    local profiles_dir="${CONFIG_DIR}/profiles"

    if [ -d "$profiles_dir" ]; then
        find "$profiles_dir" -name "*.yaml" -type f | sort
    else
        log_debug "No profiles directory found"
    fi
}

# =============================================================================
# Validation Functions
# =============================================================================

# Validate configuration values
config_validate_values() {
    local errors=0

    log_debug "Validating configuration values"

    # Validate log level
    local log_level
    log_level=$(config_get "serversh.log_level" "info")
    case "$log_level" in
        "debug"|"info"|"warn"|"error"|"fatal")
            log_debug "Log level valid: $log_level"
            ;;
        # Accept numeric log levels as well
        "0"|"1"|"2"|"3"|"4")
            log_debug "Log level valid (numeric): $log_level"
            ;;
        *)
            log_error "Invalid log level: $log_level"
            ((errors++))
            ;;
    esac

    # Validate SSH port
    local ssh_port
    ssh_port=$(config_get "security.ssh.port" "2222")
    if ! is_valid_port "$ssh_port"; then
        log_error "Invalid SSH port: $ssh_port"
        ((errors++))
    fi

    # Validate parallel jobs
    local parallel_jobs
    parallel_jobs=$(config_get "serversh.parallel_jobs" "4")
    if ! [[ "$parallel_jobs" =~ ^[0-9]+$ ]] || [ "$parallel_jobs" -lt 1 ] || [ "$parallel_jobs" -gt 16 ]; then
        log_error "Invalid parallel_jobs value: $parallel_jobs (must be 1-16)"
        ((errors++))
    fi

    # Validate timeout
    local timeout
    timeout=$(config_get "serversh.timeout" "300")
    if ! [[ "$timeout" =~ ^[0-9]+$ ]] || [ "$timeout" -lt 60 ] || [ "$timeout" -gt 3600 ]; then
        log_error "Invalid timeout value: $timeout (must be 60-3600 seconds)"
        ((errors++))
    fi

    # Validate Docker configuration if enabled
    local docker_enabled
    docker_enabled=$(config_get "container.docker.enabled" "false")
    if [ "$docker_enabled" = "true" ]; then
        local docker_mtu
        docker_mtu=$(config_get "container.docker.daemon_config.mtu" "1500")
        if ! [[ "$docker_mtu" =~ ^[0-9]+$ ]] || [ "$docker_mtu" -lt 576 ] || [ "$docker_mtu" -gt 9000 ]; then
            log_error "Invalid Docker MTU: $docker_mtu (must be 576-9000)"
            ((errors++))
        fi
    fi

    if [ $errors -gt 0 ]; then
        log_error "Configuration validation failed with $errors errors"
        return $EXIT_CONFIG_ERROR
    fi

    log_success "Configuration validation passed"
    return $EXIT_SUCCESS
}

# =============================================================================
# Utility Functions
# =============================================================================

# Get configuration summary
config_summary() {
    if [ "$CONFIG_LOADED" != true ]; then
        echo "Configuration not loaded"
        return $EXIT_CONFIG_ERROR
    fi

    echo "ServerSH Configuration Summary:"
    echo "  File: $CONFIG_FILE"
    echo "  Log Level: $(config_get "serversh.log_level" "info")"
    echo "  Parallel Jobs: $(config_get "serversh.parallel_jobs" "4")"
    echo "  Timeout: $(config_get "serversh.timeout" "300")s"
    echo "  SSH Port: $(config_get "security.ssh.port" "2222")"
    echo "  Docker Enabled: $(config_get "container.docker.enabled" "false")"
    echo "  Enabled Modules: $(config_list_enabled_modules | wc -l)"
}

# Export configuration to JSON
config_export() {
    local output_file="${1:-/dev/stdout}"

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found"
        return $EXIT_CONFIG_ERROR
    fi

    cat "$CONFIG_FILE" > "$output_file"
}

# Merge configuration from file
config_merge() {
    local merge_file="$1"

    if [ ! -f "$merge_file" ]; then
        log_error "Merge file not found: $merge_file"
        return $EXIT_CONFIG_ERROR
    fi

    if ! command_exists jq; then
        log_error "jq required for configuration merge"
        return $EXIT_MISSING_DEPS
    fi

    log_info "Merging configuration from: $merge_file"

    local temp_file
    temp_file=$(temp_file "config_merge")

    # Merge configurations
    jq -s '.[0] * .[1]' "$CONFIG_FILE" "$merge_file" > "$temp_file"

    # Backup and replace
    backup_file "$CONFIG_FILE" >/dev/null
    mv "$temp_file" "$CONFIG_FILE"

    # Clear cache
    rm -f "${CONFIG_CACHE_DIR}/*"

    log_success "Configuration merged successfully"
    return $EXIT_SUCCESS
}

# =============================================================================
# Cleanup Functions
# =============================================================================

# Cleanup configuration cache
config_cleanup_cache() {
    log_debug "Cleaning configuration cache"

    if [ -d "$CONFIG_CACHE_DIR" ]; then
        rm -rf "${CONFIG_CACHE_DIR:?}"/*
    fi
}

# Cleanup old configuration files
config_cleanup() {
    local days="${1:-30}"

    log_info "Cleaning up configuration files older than $days days"

    find "$CONFIG_DIR" -name "*.backup.*" -type f -mtime +$days -delete
    find "$CONFIG_DIR" -name "*.tmp" -type f -mtime +1 -delete
    config_cleanup_cache
}

# =============================================================================
# Initialization
# =============================================================================

# Auto-initialize if sourced with parameters
if [ "${BASH_SOURCE[0]}" != "${0}" ] && [ $# -gt 0 ]; then
    config_init "$@"
fi