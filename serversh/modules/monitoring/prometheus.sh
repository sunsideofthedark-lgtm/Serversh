#!/bin/bash

# =============================================================================
# Module: Prometheus Monitoring
# Category: Monitoring
# Description: Installs and configures Prometheus monitoring system
# Version: 1.0.0
# =============================================================================

# Source module interface
source "${SERVERSH_LIB_DIR}/module_interface.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Required Functions
# =============================================================================

module_get_name() {
    echo "monitoring/prometheus"
    return $MODULE_SUCCESS
}

module_get_version() {
    echo "1.0.0"
    return $MODULE_SUCCESS
}

module_get_description() {
    echo "Installs and configures Prometheus monitoring system"
    return $MODULE_SUCCESS
}

module_get_category() {
    echo "$MODULE_CATEGORY_MONITORING"
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
    local prometheus_version
    prometheus_version=$(module_config_get "prometheus_version" "latest")
    local install_node_exporter
    install_node_exporter=$(module_config_get "install_node_exporter" "true")
    local node_exporter_version
    node_exporter_version=$(module_config_get "node_exporter_version" "latest")
    local prometheus_port
    prometheus_port=$(module_config_get "prometheus_port" "9090")
    local node_exporter_port
    node_exporter_port=$(module_config_get "node_exporter_port" "9100")
    local enable_service
    enable_service=$(module_config_get "enable_service" "true")
    local config_retention
    config_retention=$(module_config_get "config_retention" "15d")
    local config_storage_path
    config_storage_path=$(module_config_get "config_storage_path" "/var/lib/prometheus")

    # Validate Prometheus version
    if [[ "$prometheus_version" != "latest" && ! "$prometheus_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        module_log "ERROR" "Invalid Prometheus version format: $prometheus_version (use 'latest' or format like '2.45.0')"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate Node Exporter version
    if [[ "$node_exporter_version" != "latest" && ! "$node_exporter_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        module_log "ERROR" "Invalid Node Exporter version format: $node_exporter_version (use 'latest' or format like '1.6.0')"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate boolean options
    if [[ "$install_node_exporter" != "true" && "$install_node_exporter" != "false" ]]; then
        module_log "ERROR" "Invalid install_node_exporter value: $install_node_exporter (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    if [[ "$enable_service" != "true" && "$enable_service" != "false" ]]; then
        module_log "ERROR" "Invalid enable_service value: $enable_service (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate port numbers
    if ! is_port_number "$prometheus_port"; then
        module_log "ERROR" "Invalid Prometheus port: $prometheus_port (must be between 1-65535)"
        return $MODULE_CONFIG_ERROR
    fi

    if ! is_port_number "$node_exporter_port"; then
        module_log "ERROR" "Invalid Node Exporter port: $node_exporter_port (must be between 1-65535)"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate storage path
    if [[ ! "$config_storage_path" =~ ^/ ]]; then
        module_log "ERROR" "Storage path must be absolute: $config_storage_path"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate retention time format
    if [[ ! "$config_retention" =~ ^[0-9]+[dhms]$ ]]; then
        module_log "ERROR" "Invalid retention time format: $config_retention (use format like '15d', '24h', '60m', '3600s')"
        return $MODULE_CONFIG_ERROR
    fi

    module_log "DEBUG" "Configuration validation passed"
    module_log "DEBUG" "  prometheus_version: $prometheus_version"
    module_log "DEBUG" "  install_node_exporter: $install_node_exporter"
    module_log "DEBUG" "  node_exporter_version: $node_exporter_version"
    module_log "DEBUG" "  prometheus_port: $prometheus_port"
    module_log "DEBUG" "  node_exporter_port: $node_exporter_port"
    module_log "DEBUG" "  enable_service: $enable_service"
    module_log "DEBUG" "  config_retention: $config_retention"
    module_log "DEBUG" "  config_storage_path: $config_storage_path"

    return $MODULE_SUCCESS
}

module_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Installing module: $module_name"

    # Create prometheus user
    if ! create_prometheus_user; then
        module_log "ERROR" "Failed to create prometheus user"
        return $MODULE_ERROR
    fi

    # Download and install Prometheus
    if ! install_prometheus; then
        module_log "ERROR" "Failed to install Prometheus"
        return $MODULE_ERROR
    fi

    # Install Node Exporter if configured
    local install_node_exporter
    install_node_exporter=$(module_config_get "install_node_exporter" "true")
    if [[ "$install_node_exporter" == "true" ]]; then
        if ! install_node_exporter; then
            module_log "ERROR" "Failed to install Node Exporter"
            return $MODULE_ERROR
        fi
    fi

    # Configure Prometheus
    if ! configure_prometheus; then
        module_log "ERROR" "Failed to configure Prometheus"
        return $MODULE_ERROR
    fi

    # Setup and enable services
    local enable_service
    enable_service=$(module_config_get "enable_service" "true")
    if [[ "$enable_service" == "true" ]]; then
        if ! setup_prometheus_service; then
            module_log "ERROR" "Failed to setup Prometheus service"
            return $MODULE_ERROR
        fi

        if [[ "$install_node_exporter" == "true" ]]; then
            if ! setup_node_exporter_service; then
                module_log "ERROR" "Failed to setup Node Exporter service"
                return $MODULE_ERROR
            fi
        fi
    fi

    module_log "SUCCESS" "Prometheus monitoring system installed successfully"
    return $MODULE_SUCCESS
}

module_verify() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Verifying Prometheus installation: $module_name"

    # Check Prometheus binary
    local prometheus_bin="/usr/local/bin/prometheus"
    if [[ ! -x "$prometheus_bin" ]]; then
        module_log "ERROR" "Prometheus binary not found or not executable: $prometheus_bin"
        return $MODULE_ERROR
    fi

    # Check Prometheus configuration
    local prometheus_config="/etc/prometheus/prometheus.yml"
    if [[ ! -f "$prometheus_config" ]]; then
        module_log "ERROR" "Prometheus configuration file not found: $prometheus_config"
        return $MODULE_ERROR
    fi

    # Validate configuration syntax
    if ! "$prometheus_bin" --config.file="$prometheus_config" --dry-run >/dev/null 2>&1; then
        module_log "ERROR" "Prometheus configuration validation failed"
        return $MODULE_ERROR
    fi

    # Check Node Exporter if installed
    local install_node_exporter
    install_node_exporter=$(module_config_get "install_node_exporter" "true")
    if [[ "$install_node_exporter" == "true" ]]; then
        local node_exporter_bin="/usr/local/bin/node_exporter"
        if [[ ! -x "$node_exporter_bin" ]]; then
            module_log "ERROR" "Node Exporter binary not found or not executable: $node_exporter_bin"
            return $MODULE_ERROR
        fi
    fi

    # Check services if enabled
    local enable_service
    enable_service=$(module_config_get "enable_service" "true")
    if [[ "$enable_service" == "true" ]]; then
        if ! is_service_running prometheus; then
            module_log "ERROR" "Prometheus service is not running"
            return $MODULE_ERROR
        fi

        if [[ "$install_node_exporter" == "true" ]]; then
            if ! is_service_running node_exporter; then
                module_log "ERROR" "Node Exporter service is not running"
                return $MODULE_ERROR
            fi
        fi
    fi

    # Test web interface
    local prometheus_port
    prometheus_port=$(module_config_get "prometheus_port" "9090")
    if curl -s "http://localhost:$prometheus_port/-/healthy" >/dev/null 2>&1; then
        module_log "DEBUG" "Prometheus web interface is accessible"
    else
        module_log "WARN" "Prometheus web interface is not accessible (service may be starting)"
    fi

    module_log "DEBUG" "Prometheus verification successful"
    return $MODULE_SUCCESS
}

# =============================================================================
# Optional Functions
# =============================================================================

module_pre_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running pre-installation for module: $module_name"

    # Check if we have permission to install system packages
    if [[ $EUID -ne 0 ]]; then
        module_log "ERROR" "Root privileges required to install Prometheus"
        return $MODULE_PERMISSION_DENIED
    fi

    # Check for existing installations
    check_existing_installations

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

    # Stop services
    systemctl stop prometheus 2>/dev/null || true
    systemctl stop node_exporter 2>/dev/null || true

    # Disable services
    systemctl disable prometheus 2>/dev/null || true
    systemctl disable node_exporter 2>/dev/null || true

    # Remove service files
    rm -f /etc/systemd/system/prometheus.service
    rm -f /etc/systemd/system/node_exporter.service

    # Reload systemd
    systemctl daemon-reload

    # Remove binaries
    rm -f /usr/local/bin/prometheus
    rm -f /usr/local/bin/promtool
    rm -f /usr/local/bin/node_exporter

    # Remove configuration and data directories
    rm -rf /etc/prometheus
    rm -rf /var/lib/prometheus

    # Remove user
    userdel prometheus 2>/dev/null || true

    module_log "INFO" "Prometheus rollback completed"
    return $MODULE_SUCCESS
}

module_cleanup() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running cleanup for module: $module_name"

    # Remove temporary files
    rm -f "${SERVERSH_STATE_DIR}/${module_name}_*.tmp" 2>/dev/null || true
    rm -f /tmp/prometheus*.tar.gz 2>/dev/null || true

    return $MODULE_SUCCESS
}

# =============================================================================
# Helper Functions
# =============================================================================

create_prometheus_user() {
    module_log "INFO" "Creating prometheus user"

    if ! id prometheus >/dev/null 2>&1; then
        useradd --no-create-home --shell /bin/false prometheus
        module_log "DEBUG" "Created prometheus user"
    else
        module_log "DEBUG" "prometheus user already exists"
    fi

    return $MODULE_SUCCESS
}

install_prometheus() {
    module_log "INFO" "Installing Prometheus"

    local prometheus_version
    prometheus_version=$(module_config_get "prometheus_version" "latest")

    # Get latest version if not specified
    if [[ "$prometheus_version" == "latest" ]]; then
        prometheus_version=$(get_latest_prometheus_version)
        if [[ -z "$prometheus_version" ]]; then
            module_log "ERROR" "Failed to get latest Prometheus version"
            return $MODULE_ERROR
        fi
    fi

    module_log "INFO" "Installing Prometheus version: $prometheus_version"

    # Download and extract Prometheus
    local archive_name="prometheus-${prometheus_version}.linux-amd64"
    local download_url="https://github.com/prometheus/prometheus/releases/download/v${prometheus_version}/${archive_name}.tar.gz"
    local temp_file="/tmp/${archive_name}.tar.gz"

    if ! download_prometheus_archive "$download_url" "$temp_file"; then
        module_log "ERROR" "Failed to download Prometheus"
        return $MODULE_ERROR
    fi

    # Extract and install
    cd /tmp || return $MODULE_ERROR
    tar -xzf "$temp_file"

    # Create directories
    mkdir -p /etc/prometheus
    mkdir -p /var/lib/prometheus

    # Copy binaries
    cp "${archive_name}/prometheus" /usr/local/bin/
    cp "${archive_name}/promtool" /usr/local/bin/

    # Copy configuration files
    cp "${archive_name}/prometheus.yml" /etc/prometheus/
    cp -r "${archive_name}/consoles" /etc/prometheus/
    cp -r "${archive_name}/console_libraries" /etc/prometheus/

    # Set ownership
    chown prometheus:prometheus /etc/prometheus
    chown prometheus:prometheus /var/lib/prometheus
    chown -R prometheus:prometheus /etc/prometheus/consoles
    chown -R prometheus:prometheus /etc/prometheus/console_libraries

    # Set permissions
    chmod +x /usr/local/bin/prometheus
    chmod +x /usr/local/bin/promtool

    # Cleanup
    rm -rf "$temp_file" "$archive_name"

    module_log "INFO" "Prometheus installed successfully"
    return $MODULE_SUCCESS
}

install_node_exporter() {
    module_log "INFO" "Installing Node Exporter"

    local node_exporter_version
    node_exporter_version=$(module_config_get "node_exporter_version" "latest")

    # Get latest version if not specified
    if [[ "$node_exporter_version" == "latest" ]]; then
        node_exporter_version=$(get_latest_node_exporter_version)
        if [[ -z "$node_exporter_version" ]]; then
            module_log "ERROR" "Failed to get latest Node Exporter version"
            return $MODULE_ERROR
        fi
    fi

    module_log "INFO" "Installing Node Exporter version: $node_exporter_version"

    # Download and extract Node Exporter
    local archive_name="node_exporter-${node_exporter_version}.linux-amd64"
    local download_url="https://github.com/prometheus/node_exporter/releases/download/v${node_exporter_version}/${archive_name}.tar.gz"
    local temp_file="/tmp/${archive_name}.tar.gz"

    if ! download_prometheus_archive "$download_url" "$temp_file"; then
        module_log "ERROR" "Failed to download Node Exporter"
        return $MODULE_ERROR
    fi

    # Extract and install
    cd /tmp || return $MODULE_ERROR
    tar -xzf "$temp_file"

    # Copy binary
    cp "${archive_name}/node_exporter" /usr/local/bin/

    # Set permissions
    chmod +x /usr/local/bin/node_exporter

    # Cleanup
    rm -rf "$temp_file" "$archive_name"

    module_log "INFO" "Node Exporter installed successfully"
    return $MODULE_SUCCESS
}

download_prometheus_archive() {
    local url="$1"
    local output_file="$2"

    module_log "DEBUG" "Downloading: $url"

    if command_exists wget; then
        wget -O "$output_file" "$url"
    elif command_exists curl; then
        curl -L -o "$output_file" "$url"
    else
        module_log "ERROR" "Neither wget nor curl is available"
        return $MODULE_ERROR
    fi
}

get_latest_prometheus_version() {
    if command_exists curl; then
        curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/'
    elif command_exists wget; then
        wget -q -O - https://api.github.com/repos/prometheus/prometheus/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/'
    fi
}

get_latest_node_exporter_version() {
    if command_exists curl; then
        curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/'
    elif command_exists wget; then
        wget -q -O - https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/'
    fi
}

configure_prometheus() {
    module_log "INFO" "Configuring Prometheus"

    local prometheus_port
    prometheus_port=$(module_config_get "prometheus_port" "9090")
    local node_exporter_port
    node_exporter_port=$(module_config_get "node_exporter_port" "9100")
    local config_retention
    config_retention=$(module_config_get "config_retention" "15d")
    local config_storage_path
    config_storage_path=$(module_config_get "config_storage_path" "/var/lib/prometheus")

    # Create prometheus.yml configuration
    cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:${prometheus_port}']

  - job_name: 'node'
    static_configs:
      - targets: ['localhost:${node_exporter_port}']
EOF

    # Create advanced configuration with additional rules
    create_prometheus_rules

    # Set ownership
    chown prometheus:prometheus /etc/prometheus/prometheus.yml
    chmod 644 /etc/prometheus/prometheus.yml

    module_log "DEBUG" "Prometheus configuration updated"
    return $MODULE_SUCCESS
}

create_prometheus_rules() {
    local rules_dir="/etc/prometheus/rules"
    mkdir -p "$rules_dir"

    # Create basic alerting rules
    cat > "${rules_dir}/alerts.yml" << 'EOF'
groups:
  - name: node_alerts
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% for more than 5 minutes"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 80% for more than 5 minutes"

      - alert: DiskSpaceLow
        expr: (1 - (node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes{fstype!="tmpfs"})) * 100 > 85
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Low disk space"
          description: "Disk usage is above 85%"

      - alert: NodeDown
        expr: up{job="node"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Node is down"
          description: "Node {{ $labels.instance }} has been down for more than 1 minute"
EOF

    chown -R prometheus:prometheus "$rules_dir"
    chmod 644 "${rules_dir}/alerts.yml"

    # Update prometheus.yml to include rules
    if ! grep -q "rule_files:" /etc/prometheus/prometheus.yml; then
        sed -i '/^scrape_configs:/i rule_files:\n  - "rules/*.yml"' /etc/prometheus/prometheus.yml
    fi
}

setup_prometheus_service() {
    module_log "INFO" "Setting up Prometheus service"

    local prometheus_port
    prometheus_port=$(module_config_get "prometheus_port" "9090")
    local config_retention
    config_retention=$(module_config_get "config_retention" "15d")
    local config_storage_path
    config_storage_path=$(module_config_get "config_storage_path" "/var/lib/prometheus")

    # Create systemd service file
    cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file=/etc/prometheus/prometheus.yml \\
    --storage.tsdb.path=${config_storage_path} \\
    --web.console.libraries=/etc/prometheus/console_libraries \\
    --web.console.templates=/etc/prometheus/consoles \\
    --storage.tsdb.retention.time=${config_retention} \\
    --web.listen-address=0.0.0.0:${prometheus_port} \\
    --web.enable-lifecycle

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus

    module_log "INFO" "Prometheus service started"
    return $MODULE_SUCCESS
}

setup_node_exporter_service() {
    module_log "INFO" "Setting up Node Exporter service"

    local node_exporter_port
    node_exporter_port=$(module_config_get "node_exporter_port" "9100")

    # Create systemd service file
    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/node_exporter \\
    --web.listen-address=0.0.0.0:${node_exporter_port}

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter

    module_log "INFO" "Node Exporter service started"
    return $MODULE_SUCCESS
}

check_existing_installations() {
    module_log "INFO" "Checking for existing Prometheus installations"

    # Check for existing binaries
    if [[ -x /usr/local/bin/prometheus ]]; then
        local existing_version
        existing_version=$(/usr/local/bin/prometheus --version 2>&1 | head -1 | grep -oP 'version \K[0-9]+\.[0-9]+\.[0-9]+')
        module_log "WARN" "Existing Prometheus installation found (version: $existing_version)"
        module_log "WARN" "Existing installation will be replaced"
    fi

    # Check for existing services
    if systemctl is-enabled prometheus >/dev/null 2>&1; then
        module_log "WARN" "Prometheus service is already enabled"
        module_log "WARN" "Service configuration will be updated"
    fi

    # Check for existing user
    if id prometheus >/dev/null 2>&1; then
        module_log "DEBUG" "Prometheus user already exists"
    fi
}

display_installation_summary() {
    local prometheus_port
    prometheus_port=$(module_config_get "prometheus_port" "9090")
    local node_exporter_port
    node_exporter_port=$(module_config_get "node_exporter_port" "9100")
    local install_node_exporter
    install_node_exporter=$(module_config_get "install_node_exporter" "true")

    module_log "INFO" "Prometheus Installation Summary:"
    module_log "INFO" "  Prometheus Web Interface: http://localhost:$prometheus_port"
    module_log "INFO" "  Prometheus Configuration: /etc/prometheus/prometheus.yml"
    module_log "INFO" "  Prometheus Storage: $(module_config_get "config_storage_path" "/var/lib/prometheus")"

    if [[ "$install_node_exporter" == "true" ]]; then
        module_log "INFO" "  Node Exporter Metrics: http://localhost:$node_exporter_port/metrics"
    fi

    module_log "INFO" "  Service Status: $(systemctl is-active prometheus 2>/dev/null || echo "unknown")"
    if [[ "$install_node_exporter" == "true" ]]; then
        module_log "INFO" "  Node Exporter Status: $(systemctl is-active node_exporter 2>/dev/null || echo "unknown")"
    fi
}

show_next_steps() {
    module_log "INFO" "Next Steps:"
    module_log "INFO" "  1. Access Prometheus web interface to verify metrics collection"
    module_log "INFO" "  2. Configure additional targets in /etc/prometheus/prometheus.yml"
    module_log "INFO" "  3. Set up Grafana for visualization (optional)"
    module_log "INFO" "  4. Configure alerting rules and notification channels"
    module_log "INFO" "  5. Consider setting up Prometheus for high availability"
}

# Initialize module (optional - called when module is sourced)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    module_log "DEBUG" "Prometheus monitoring module loaded"
fi

return $MODULE_SUCCESS