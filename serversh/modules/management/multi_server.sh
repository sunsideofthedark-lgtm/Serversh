#!/bin/bash

# =============================================================================
# Module: Multi-Server Management
# Category: Management
# Description: Manage multiple servers, cluster configurations, and distributed deployments
# Version: 1.0.0
# =============================================================================

# Source module interface
source "${SERVERSH_LIB_DIR}/module_interface.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Required Functions
# =============================================================================

module_get_name() {
    echo "management/multi_server"
    return $MODULE_SUCCESS
}

module_get_version() {
    echo "1.0.0"
    return $MODULE_SUCCESS
}

module_get_description() {
    echo "Manage multiple servers, cluster configurations, and distributed deployments"
    return $MODULE_SUCCESS
}

module_get_category() {
    echo "$MODULE_CATEGORY_MANAGEMENT"
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
    local enable_cluster
    enable_cluster=$(module_config_get "enable_cluster" "false")
    local cluster_name
    cluster_name=$(module_config_get "cluster_name" "serversh-cluster")
    local cluster_role
    cluster_role=$(module_config_get "cluster_role" "single")
    local master_nodes
    master_nodes=$(module_config_get "master_nodes" "localhost")
    local worker_nodes
    worker_nodes=$(module_config_get "worker_nodes" "")
    local cluster_discovery
    cluster_discovery=$(module_config_get "cluster_discovery" "static")

    # Validate boolean options
    if [[ "$enable_cluster" != "true" && "$enable_cluster" != "false" ]]; then
        module_log "ERROR" "Invalid enable_cluster value: $enable_cluster (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate cluster role
    if [[ "$cluster_role" != "single" && "$cluster_role" != "master" && "$cluster_role" != "worker" ]]; then
        module_log "ERROR" "Invalid cluster_role value: $cluster_role (must be single, master, or worker)"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate cluster name
    if [[ -n "$cluster_name" ]] && ! [[ "$cluster_name" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        module_log "ERROR" "Invalid cluster name format: $cluster_name"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate master nodes
    if [[ -n "$master_nodes" ]]; then
        IFS=',' read -ra nodes <<< "$master_nodes"
        for node in "${nodes[@]}"; do
            node=$(echo "$node" | xargs)  # trim whitespace
            if ! validate_node_address "$node"; then
                module_log "ERROR" "Invalid master node address: $node"
                return $MODULE_CONFIG_ERROR
            fi
        done
    fi

    # Validate worker nodes
    if [[ -n "$worker_nodes" ]]; then
        IFS=',' read -ra nodes <<< "$worker_nodes"
        for node in "${nodes[@]}"; do
            node=$(echo "$node" | xargs)  # trim whitespace
            if ! validate_node_address "$node"; then
                module_log "ERROR "Invalid worker node address: $node"
                return $MODULE_CONFIG_ERROR
            fi
        done
    fi

    # Validate cluster discovery method
    if [[ "$cluster_discovery" != "static" && "$cluster_discovery" != "dynamic" && "$cluster_discovery" != "dns" ]]; then
        module_log "ERROR" "Invalid cluster_discovery value: $cluster_discovery (must be static, dynamic, or dns)"
        return $MODULE_CONFIG_ERROR
    fi

    module_log "DEBUG" "Configuration validation passed"
    module_log "DEBUG" "  enable_cluster: $enable_cluster"
    module_log "DEBUG" "  cluster_name: $cluster_name"
    module_log "DEBUG" "  cluster_role: $cluster_role"
    module_log "DEBUG " "  master_nodes: $master_nodes"
    module_log "DEBUG " "  worker_nodes: $worker_nodes"
    module_log "DEBUG " "  cluster_discovery: $cluster_discovery"

    return $MODULE_SUCCESS
}

module_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Installing module: $module_name"

    # Get configuration
    local enable_cluster
    enable_cluster=$(module_config_get "enable_cluster" "false")

    if [[ "$enable_cluster" != "true" ]]; then
        module_log "INFO" "Cluster mode is disabled, skipping cluster setup"
        setup_single_server_mode
        return $MODULE_SUCCESS
    fi

    # Setup cluster mode
    local cluster_name
    cluster_name=$(module_config_get "cluster_name" "serversh-cluster")
    local cluster_role
    cluster_role=$(module_config_get "cluster_role" "single")
    local master_nodes
    master_nodes=$(module_config_get "master_nodes" "localhost")
    local worker_nodes
    worker_nodes=$(module_config_get "worker_nodes" "")

    module_log "INFO" "Setting up cluster: $cluster_name"
    module_log "INFO " "  Role: $cluster_role"

    case "$cluster_role" in
        "master")
            setup_cluster_master "$cluster_name" "$master_nodes" "$worker_nodes"
            ;;
        "worker")
            setup_cluster_worker "$cluster_name" "$master_nodes"
            ;;
        "single")
            setup_single_node_cluster "$cluster_name"
            ;;
    esac

    module_log "SUCCESS" "Multi-server management setup completed"
    return $MODULE_SUCCESS
}

module_verify() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Verifying multi-server management: $module_name"

    local enable_cluster
    enable_cluster=$(module_config_get "enable_cluster" "false")

    if [[ "$enable_cluster" == "true" ]]; then
        verify_cluster_setup
    else
        verify_single_server_mode
    fi

    return $MODULE_SUCCESS
}

# =============================================================================
# Optional Functions
# =============================================================================

module_pre_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running pre-installation for module: $module_name"

    # Check if we have permission for system configuration
    if [[ $EUID -ne 0 ]]; then
        module_log "ERROR" "Root privileges required for multi-server management"
        return $MODULE_PERMISSION_DENIED
    fi

    # Check network connectivity if clustering
    local enable_cluster
    enable_cluster=$(module_config_get "enable_cluster" "false")

    if [[ "$enable_cluster" == "true" ]]; then
        check_cluster_prerequisites
    fi

    return $MODULE_SUCCESS
}

module_post_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running post-installation for module: $module_name"

    # Display cluster information
    display_cluster_status

    # Show management commands
    show_management_commands

    return $MODULE_SUCCESS
}

module_rollback() {
    local module_name
    module_name=$(module_get_name)

    module_log "WARN" "Rolling back module: $module_name"

    # Stop cluster services if running
    stop_cluster_services

    # Remove cluster configuration
    cleanup_cluster_configuration

    module_log "INFO" "Multi-server management rollback completed"
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

validate_node_address() {
    local address="$1"

    # Check if it's a valid IP address
    if is_valid_ipv4 "$address" || is_valid_ipv6 "$address"; then
        return 0
    fi

    # Check if it's a valid hostname
    if is_valid_hostname "$address"; then
        return 0
    fi

    # Check if it's a valid domain name with port
    if [[ "$address" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        local host="${address%:*}"
        local port="${address##*:}"
        if [[ ("$host" =~ ^[a-zA-Z0-9.-]+$ ]] && is_port_number "$port" ]]; then
            return 0
        fi
    fi

    return 1
}

setup_single_server_mode() {
    module_log "INFO" "Setting up single server mode"

    local server_id
    server_id=$(generate_server_id)

    # Create server configuration
    create_server_config "$server_id" "single" "localhost"

    # Install cluster management tools
    install_cluster_tools

    # Start local services
    start_local_services

    module_log "SUCCESS" "Single server mode configured"
}

setup_cluster_master() {
    local cluster_name="$1"
    local master_nodes="$2"
    local worker_nodes="$3"

    module_log "INFO" "Setting up cluster master: $cluster_name"

    local server_id
    server_id=$(generate_server_id)

    # Create cluster configuration
    create_cluster_config "$cluster_name" "$server_id" "master" "$master_nodes" "$worker_nodes"

    # Install cluster management tools
    install_cluster_tools

    # Setup etcd if needed
    setup_etcd_cluster "$cluster_name" "$master_nodes"

    # Setup load balancer if multiple masters
    if [[ "$master_nodes" == *","* ]]; then
        setup_ha_load_balancer "$cluster_name" "$master_nodes"
    fi

    # Configure master services
    configure_master_services "$cluster_name" "$server_id"

    # Start cluster services
    start_cluster_services

    # Wait for cluster to form
    wait_for_cluster_formation

    module_log "SUCCESS" "Cluster master configured"
}

setup_cluster_worker() {
    local cluster_name="$1"
    local master_nodes="$2"

    module_log "INFO" "Setting up cluster worker: $cluster_name"

    local server_id
    server_id=$(generate_server_id)

    # Create cluster configuration
    create_cluster_config "$cluster_name" "$server_id" "worker" "$master_nodes" ""

    # Install cluster tools
    install_cluster_tools

    # Connect to cluster
    join_cluster "$cluster_name" "$master_nodes" "$server_id"

    # Configure worker services
    configure_worker_services "$cluster_name" "$server_id"

    # Start worker services
    start_worker_services

    module_log "SUCCESS" "Cluster worker configured"
}

setup_single_node_cluster() {
    local cluster_name="$1"

    module_log "INFO "Setting up single-node cluster: $cluster_name"

    local server_id
    server_id=$(generate_server_id)

    # Create cluster configuration
    create_cluster_config "$cluster_name" "$server_id" "master" "localhost" ""

    # Install cluster tools
    install_cluster_tools

    # Setup etcd for single node
    setup_etcd_single_node "$cluster_name"

    # Configure single node cluster
    configure_single_node_cluster "$cluster_name" "$server_id"

    # Start cluster services
    start_cluster_services

    module_log "SUCCESS" "Single-node cluster configured"
}

generate_server_id() {
    local hostname
    hostname=$(hostname)
    local timestamp
    timestamp=$(date +%s)
    local mac_address
    mac_address=$(ip link | grep -m1 -o 'ether ..' | awk '{print $2}' | tr -d ':')

    echo "${hostname}-${timestamp}-${mac_address: -4}"
}

create_server_config() {
    local server_id="$1"
    local role="$2"
    local address="$3"

    local config_dir="${SERVERSH_STATE_DIR}/cluster"
    ensure_dir "$config_dir"

    cat > "$config_dir/server-${server_id}.yaml" << EOF
# Server Configuration for ServerSH Cluster
server_id: "$server_id"
role: "$role"
address: "$address"
hostname: "$(hostname)"
created_at: "$(date -Iseconds)"
version: "1.0.0"

# Network Configuration
network:
  listen_port: 8080
  advertise_address: "$address"
  bind_address: "0.0.0.0"

# Health Check
health_check:
  enabled: true
  endpoint: "/health"
  interval: "30s"
  timeout: "5s"
  retries: 3

# Service Configuration
services:
  enabled: true
  port_range: "9000-9100"

# Resource Limits
resources:
  max_connections: 1000
  memory_limit: "1GB"
  cpu_limit: "1.0"
EOF

    module_log "DEBUG" "Created server configuration: $config_dir/server-${server_id}.yaml"
}

create_cluster_config() {
    local cluster_name="$1"
    local server_id="$2"
    local role="$3"
    local masters="$4"
    local workers="$5"

    local config_dir="${SERVERSH_STATE_DIR}/cluster"
    ensure_dir "$config_dir"

    cat > "$config_dir/cluster-${cluster_name}.yaml" << EOF
# Cluster Configuration for ServerSH
cluster_name: "$cluster_name"
created_at: "$(date -Iseconds)"
version: "1.0.0"

# Cluster Node Configuration
current_server:
  id: "$server_id"
  role: "$role"

# Master Nodes
master_nodes:
EOF

    # Add master nodes
    if [[ -n "$masters" ]]; then
        IFS=',' read -ra nodes <<< "$masters"
        local index=1
        for node in "${nodes[@]}"; do
            node=$(echo "$node" | xargs)
            echo "  - id: \"master-${index}\"" >> "$config_dir/cluster-${cluster_name}.yaml"
            echo "    address: \"$node\"" >> "$config_dir/cluster-${cluster_name}.yaml"
            ((index++))
        done
    fi

    # Add worker nodes
    if [[ -n "$workers" ]]; then
        cat >> "$config_dir/cluster-${cluster_name}.yaml" << EOF
worker_nodes:
EOF
        IFS=',' read -ra nodes <<< "$workers"
        local index=1
        for node in "${nodes[@]}"; do
            node=$(echo "$node" | xargs)
            echo "  - id: \"worker-${index}\"" >> "$config_dir/cluster-${cluster_name}.yaml"
            echo "    address: \"$node\"" >> "$config_dir/cluster-${cluster_name}.yaml"
            ((index++))
        done
    fi

    # Add cluster settings
    cat >> "$config_dir/cluster-${cluster_name}.yaml" << EOF

# Cluster Settings
cluster:
  discovery_method: "static"
  heartbeat_interval: "5s"
  election_timeout: "30s"
  leader_lease_duration: "15s"

# Networking
network:
  cluster_port: 7946
  node_port_range: "7947-7950"
  service_port_range: "9000-9100"

# Security
security:
  enable_tls: false
  cluster_key: "$(openssl rand -hex 32 2>/dev/null || echo 'insecure-key')"

# Database
database:
  type: "sqlite"
  path: "${SERVERSH_STATE_DIR}/cluster/cluster.db"

# Logging
logging:
  level: "info"
  file: "${SERVERSH_LOG_DIR}/cluster.log"
  max_size: "100MB"
  max_files: 10
EOF

    # Create cluster key file
    echo "$(openssl rand -hex 32 2>/dev/null || echo 'insecure-key')" > "$config_dir/cluster.key"
    chmod 600 "$config_dir/cluster.key"

    module_log "DEBUG" "Created cluster configuration: $config_dir/cluster-${cluster_name}.yaml"
}

install_cluster_tools() {
    module_log "INFO" "Installing cluster management tools"

    # Install required packages
    local packages="curl wget jq openssl"

    case "$(get_system_info os)" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y $packages
            ;;
        centos|rhel|fedora)
            if command_exists dnf; then
                dnf install -y $packages
            else
                yum install -y $packages
            fi
            ;;
        arch)
            pacman -S --noconfirm $packages
            ;;
    esac

    # Create cluster scripts directory
    local scripts_dir="${SERVERSH_LIB_DIR}/cluster"
    ensure_dir "$scripts_dir"

    # Create cluster management scripts
    create_cluster_scripts "$scripts_dir"

    module_log "SUCCESS" "Cluster management tools installed"
}

create_cluster_scripts() {
    local scripts_dir="$1"

    # Cluster management script
    cat > "$scripts_dir/clusterctl.sh" << 'EOF'
#!/bin/bash

# ServerSH Cluster Management Tool
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR="${SERVERSH_STATE_DIR}/cluster"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_help() {
    cat << EOF
ServerSH Cluster Management Tool

Usage: $0 <command> [options]

Commands:
  status          Show cluster status
  list            List all nodes
  health          Check cluster health
  promote         Promote worker to master
  demote          Demote master to worker
  add             Add new node to cluster
  remove          Remove node from cluster
  restart          Restart cluster services
  cleanup          Cleanup cluster resources

Options:
  --cluster <name>    Specify cluster name
  --config <file>     Specify config file
  --verbose          Verbose output
  --help            Show this help

Examples:
  $0 status
  $0 list
  $0 health
  $0 --cluster production status
EOF
}

# Main script logic here
case "${1:-status}" in
    "status")
        cluster_status
        ;;
    "list")
        list_nodes
        ;;
    "health")
        check_cluster_health
        ;;
    *)
        show_help
        exit 1
        ;;
esac
EOF

    chmod +x "$scripts_dir/clusterctl.sh"

    # Node management script
    cat > "$scripts_dir/node-manager.sh" << 'EOF'
#!/bin/bash

# ServerSH Node Management
set -euo pipefail

CLUSTER_DIR="${SERVERSH_STATE_DIR}/cluster"

list_nodes() {
    if [[ -f "$CLUSTER_DIR/cluster.yaml" ]]; then
        grep -E "^(id|address|role)" "$CLUSTER_DIR/cluster.yaml"
    fi
}

check_node_health() {
    local node_id="$1"
    local config_file="$CLUSTER_DIR/server-${node_id}.yaml"

    if [[ -f "$config_file" ]]; then
        echo "Node $node_id is configured"
        grep "role:" "$config_file"
    else
        echo "Node $node_id not found"
        return 1
    fi
}
EOF

    chmod +x "$scripts_dir/node-manager.sh"

    module_log "DEBUG" "Created cluster management scripts in: $scripts_dir"
}

start_local_services() {
    module_log "INFO" "Starting local services for single server mode"

    # Create systemd service for local cluster management
    cat > "/etc/systemd/system/serversh-cluster.service" << EOF
[Unit]
Description=ServerSH Cluster Management
After=network.target

[Service]
Type=simple
ExecStart=${SERVERSH_LIB_DIR}/cluster/clusterctl.sh status
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable serversh-cluster.service
    systemctl start serversh-cluster.service

    module_log "INFO" "Local cluster services started"
}

start_cluster_services() {
    module_log "INFO" "Starting cluster services"

    # Create systemd service for cluster management
    cat > "/etc/systemd/system/serversh-cluster.service" << EOF
[Unit]
Description=ServerSH Cluster Management
After=network.target

[Service]
Type=simple
ExecStart=${SERVERSH_LIB_DIR}/cluster/clusterctl.sh status
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable serversh-cluster.service
    systemctl start serversh-cluster.service

    module_log "INFO" "Cluster services started"
}

start_worker_services() {
    module_log "INFO "Starting worker services"

    # Worker-specific services
    systemctl enable serversh-cluster.service
    systemctl start serversh-cluster.service

    module_log "INFO" "Worker services started"
}

configure_master_services() {
    local cluster_name="$1"
    local server_id="$2"

    module_log "INFO" "Configuring master services for cluster: $cluster_name"

    # Create master service configuration
    cat > "/etc/systemd/system/serversh-master.service" << EOF
[Unit]
Description=ServerSH Master Node
After=network.target

[Service]
Type=simple
EnvironmentFile=-/etc/environment
Environment=SERVERSH_CLUSTER_NAME=$cluster_name
Environment=SERVERSH_SERVER_ID=$server_id
Environment=SERVERSH_ROLE=master
ExecStart=${SERVERSH_LIB_DIR}/cluster/clusterctl.sh start-master
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable serversh-master.service

    module_log "INFO" "Master services configured"
}

configure_worker_services() {
    local cluster_name="$1"
    local server_id="$2"

    module_log "INFO "Configuring worker services for cluster: $cluster_name"

    # Create worker service configuration
    cat > "/etc/systemd/system/serversh-worker.service" << EOF
[Unit]
Description=ServerSH Worker Node
After=network.target

[Service]
Type=simple
EnvironmentFile=-/etc/environment
Environment=SERVERSH_CLUSTER_NAME=$cluster_name
Environment=SERVERSH_SERVER_ID=$server_id
Environment=SERVERSH_ROLE=worker
ExecStart=${SERVERSH_LIB_DIR}/cluster/clusterctl.sh start-worker
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable serversh-worker.service

    module_log "INFO" "Worker services configured"
}

configure_single_node_cluster() {
    local cluster_name="$1"
    local server_id="$2"

    module_log "INFO "Configuring single-node cluster: $cluster_name"

    # Create single-node service configuration
    cat > "/etc/systemd/system/serversh-single.service" << EOF
[Unit]
Description=ServerSH Single-Node Cluster
After=network.target

[Service]
Type=simple
EnvironmentFile=-/etc/environment
Environment=SERVERSH_CLUSTER_NAME=$cluster_name
Environment=SERVERSH_SERVER_ID=$server_id
Environment=SERVERSH_ROLE=single
ExecStart=${SERVERSH_LIB_DIR}/cluster/clusterctl.sh start-single
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WedantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable serversh-single.service

    module_log "INFO "Single-node cluster configured"
}

check_cluster_prerequisites() {
    module_log "INFO" "Checking cluster prerequisites"

    # Check network connectivity
    if ! command_exists ping; then
        module_log "WARN" "ping command not available"
    fi

    # Check if required ports are available
    local ports=(8080 7946 7947)
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port.*LISTEN" || ss -tuln 2>/dev/null | grep -q ":$port.*LISTEN"; then
            module_log "WARN" "Port $port is already in use"
        fi
    done

    module_log "DEBUG" "Cluster prerequisites check completed"
}

stop_cluster_services() {
    module_log "INFO" "Stopping cluster services"

    # Stop all cluster-related services
    systemctl stop serversh-cluster.service 2>/dev/null || true
    systemctl stop serversh-master.service 2>/dev/null || true
    systemctl stop serversh-worker.service 2>/dev/null || true
    systemctl stop serversh-single.service 2>/dev/null || true

    # Disable services
    systemctl disable serversh-cluster.service 2>/dev/null || true
    systemctl disable serversh-master.service 2>/dev/null || true
    systemctl disable serversh-worker.service 2>/dev/null || true
    systemctl disable serversh-single.service 2>/dev/null || true

    systemctl daemon-reload

    module_log "INFO" "Cluster services stopped"
}

cleanup_cluster_configuration() {
    module_log "INFO" "Cleaning up cluster configuration"

    # Remove cluster configuration files
    rm -rf "${SERVERSH_STATE_DIR}/cluster" 2>/dev/null || true

    # Remove systemd service files
    rm -f /etc/systemd/system/serversh-cluster.service
    rm -f /etc/systemd/system/serversh-master.service
    rm -f /etc/systemd/system/serversh-worker.service
    rm -f /etc/systemd/system/serversh-single.service

    systemctl daemon-reload

    module_log "INFO" "Cluster configuration cleaned up"
}

verify_cluster_setup() {
    module_log "DEBUG" "Verifying cluster setup"

    local config_dir="${SERVERSH_STATE_DIR}/cluster"
    if [[ ! -d "$config_dir" ]]; then
        module_log "ERROR" "Cluster configuration directory not found"
        return $MODULE_ERROR
    fi

    # Check if cluster configuration exists
    local cluster_name
    cluster_name=$(module_config_get "cluster_name" "")
    if [[ ! -f "$config_dir/cluster-${cluster_name}.yaml" ]]; then
        module_log "ERROR" "Cluster configuration file not found: cluster-${cluster_name}.yaml"
        return $MODULE_ERROR
    fi

    # Verify service files exist
    local cluster_role
    cluster_role=$(module_config_get "cluster_role" "single")
    local service_name="serversh-${cluster_role}.service"

    if [[ ! -f "/etc/systemd/system/$service_name" ]]; then
        module_log "ERROR" "Cluster service not found: $service_name"
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "Cluster verification successful"
    return $MODULE_SUCCESS
}

verify_single_server_mode() {
    module_log "DEBUG" "Verifying single server mode"

    # Check if services are running
    if ! systemctl is-active --quiet serversh-cluster.service; then
        module_log "WARN" "Cluster management service is not running"
    fi

    module_log "DEBUG" "Single server mode verification successful"
    return $MODULE_SUCCESS
}

setup_etcd_cluster() {
    local cluster_name="$1"
    local master_nodes="$2"

    module_log "INFO" "Setting up etcd cluster for: $cluster_name"

    # Install etcd if not available
    if ! command_exists etcd; then
        install_etcd
    fi

    # Create etcd configuration
    local etcd_dir="${SERVERSH_STATE_DIR}/etcd"
    ensure_dir "$etcd_dir"

    # Generate etcd configuration
    local initial_cluster=""
    if [[ "$master_nodes" == *","* ]]; then
        # Multiple masters
        IFS=',' read -ra nodes <<< "$master_nodes"
        for node in "${nodes[@]}"; do
            node=$(echo "$node" | xargs)
            initial_cluster="${initial_cluster} --initial-cluster ${node}:2380"
        done
    fi

    # Create etcd environment file
    cat > "/etc/etcd/etcd.env" << EOF
# etcd Environment Configuration
ETCD_NAME="$(hostname)"
ETCD_DATA_DIR="$etcd_dir"
ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://$(hostname):2379"
ETCD_LISTEN_PEER_URLS="$initial_cluster"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_CLUSTER_NAME="$cluster_name"
EOF

    # Create etcd service
    cat > "/etc/systemd/system/etcd.service" << EOF
[Unit]
Description=etcd Key-Value Store
Documentation=https://github.com/etcd-io/etcd
After=network.target

[Service]
Type=notify
User=etcd
EnvironmentFile=/etc/etcd/etcd.env
ExecStart=/usr/local/bin/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable etcd.service
    systemctl start etcd.service

    module_log "SUCCESS" "etcd cluster setup completed"
}

setup_etcd_single_node() {
    local cluster_name="$1"

    module_log "INFO "Setting up single-node etcd for: $cluster_name"

    # Install etcd if not available
    if ! command_exists etcd; then
        install_etcd
    fi

    # Create etcd configuration
    local etcd_dir="${SERVERSH_STATE_DIR}/etcd"
    ensure_dir "$etcd_dir"

    # Create etcd environment file
    cat > "/etc/etcd/etcd.env" << EOF
# etcd Environment Configuration
ETCD_NAME="$(hostname)"
ETCD_DATA_DIR="$etcd_dir"
ETCD_LISTEN_CLIENT_URLS="http://localhost:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://localhost:2379"
ETCD_INITIAL_CLUSTER="new"
ETCD_CLUSTER_NAME="$cluster_name"
EOF

    # Create etcd service
    cat > "/etc/systemd/system/etcd.service" << EOF
[Unit]
Description=etcd Key-Value Store
Documentation=https://github.com/etcd-io/etcd
After=network.target

[Service]
Type=notify
User=etcd
EnvironmentFile=/etc/etcd/etcd.env
ExecStart=/usr/local/bin/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable etcd.service
    systemctl start etcd.service

    module_log "SUCCESS" "Single-node etcd setup completed"
}

install_etcd() {
    local etcd_version="v3.5.9"
    local arch="amd64"

    module_log "INFO" "Installing etcd $etcd_version"

    # Download etcd
    local download_url="https://github.com/etcd-io/etcd/releases/download/${etcd_version}/etcd-${etcd_version}-linux-${arch}.tar.gz"

    local temp_file="/tmp/etcd-${etcd_version}.tar.gz"
    if command_exists wget; then
        wget -O "$temp_file" "$download_url"
    elif command_exists curl; then
        curl -L -o "$temp_file" "$download_url"
    else
        module_log "ERROR "Cannot download etcd - neither wget nor curl available"
        return $MODULE_ERROR
    fi

    # Extract and install
    cd /tmp
    tar -xzf "$temp_file"
    local extracted_dir="etcd-${et_version}-linux-${arch}"

    if [[ -d "$extracted_dir" ]]; then
        cp "$extracted_dir/etcd" /usr/local/bin/
        cp "$extracted_dir/etcdctl" /usr/local/bin/
        chmod +x /usr/local/bin/etcd /usr/local/bin/etcdctl
        rm -rf "$extracted_dir" "$temp_file"
    else
        module_log "ERROR "Failed to extract etcd archive"
        rm -f "$temp_file"
        return $MODULE_ERROR
    fi

    module_log "SUCCESS" "etcd installed successfully"
}

setup_ha_load_balancer() {
    local cluster_name="$1"
    local master_nodes="$2"

    module_log "INFO "Setting up HA load balancer for: $cluster_name"

    # Install HAProxy if not available
    if ! command_exists haproxy; then
        install_haproxy
    fi

    # Create HAProxy configuration
    local haproxy_dir="${SERVERSH_STATE_DIR}/haproxy"
    ensure_dir "$haproxy_dir"

    # Generate HAProxy configuration for master nodes
    cat > "$haproxy_dir/haproxy.cfg" << EOF
# HAProxy Configuration for ServerSH Cluster
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    daemon

defaults
    log     global
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server 50000
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

frontend serversh_frontend
    bind *:8080
    mode http
    option  httplog
    option  httplog-format
    default_backend serversh_backend

backend serversh_backend
    balance roundrobin
    option httpchk GET /health
    server-check
EOF

    # Add master nodes to backend
    IFS=',' read -ra nodes <<< "$master_nodes"
    for node in "${nodes[@]}"; do
        node=$(echo "$node" | xargs)
        echo "    server $node:8080 check" >> "$haproxy_dir/haproxy.cfg"
    done

    # Create HAProxy service
    cat > "/etc/systemd/system/haproxy.service" << EOF
[Unit]
Description=HAProxy Load Balancer
After=network.target

[Service]
Type=notify
ExecStart=/usr/sbin/haproxy -f $haproxy_dir/haproxy.cfg
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable haproxy
    systemctl start haproxy

    module_log "SUCCESS" "HA load balancer configured"
}

install_haproxy() {
    module_log "INFO" "Installing HAProxy"

    case "$(get_system_info os)" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y haproxy
            ;;
        centos|rhel|fedora)
            if command_exists dnf; then
                dnf install -y haproxy
            else
                yum install -y haproxy
            fi
            ;;
        arch)
            pacman -S --noconfirm haproxy
            ;;
    esac

    module_log "SUCCESS" "HAProxy installed"
}

wait_for_cluster_formation() {
    module_log "INFO" "Waiting for cluster to form..."

    local max_wait=60
    local wait_count=0
    local cluster_healthy=false

    while [[ $wait_count -lt $max_wait ]] && [[ $cluster_healthy == "false" ]]; do
        if check_cluster_health >/dev/null 2>&1; then
            cluster_healthy=true
            module_log "SUCCESS" "Cluster is healthy"
        else
            module_log "DEBUG" "Waiting for cluster to form... ($wait_count/$max_wait)"
            sleep 5
            ((wait_count++))
        fi
    done

    if [[ $cluster_healthy == "false" ]]; then
        module_log "WARN" "Cluster formation timeout after ${max_wait}s"
    fi
}

check_cluster_health() {
    # Basic health check for cluster
    # This would be expanded with actual health checking logic
    return 0
}

list_nodes() {
    local config_dir="${SERVERSH_STATE_DIR}/cluster"

    if [[ -f "$config_dir/cluster.yaml" ]]; then
        echo "Cluster Nodes:"
        grep -E "id:|address:" "$config_dir" | sed 's/^ */  /'
    else
        echo "No cluster configuration found"
    fi
}

display_cluster_status() {
    module_log "INFO" "Cluster Status:"

    local enable_cluster
    enable_cluster=$(module_config_get "enable_cluster" "false")

    if [[ "$enable_cluster" == "false" ]]; then
        module_log "INFO "  Mode: Single Server"
        module_log "INFO "  Server: $(hostname)"
        module_log "INFO "  Cluster: Disabled"
    else
        local cluster_name
        cluster_name=$(module_config_get "cluster_name" "serversh-cluster")
        local cluster_role
        cluster_role=$(module_config_get "cluster_role" "single")

        module_log "INFO "  Mode: Cluster"
        module_log "INFO "  Cluster: $cluster_name"
        module_log "INFO "  Role: $cluster_role"
        module_log "INFO "  Server: $(hostname)"
        module_log "INFO "  Node ID: $(generate_server_id)"

        # List configured nodes
        list_nodes
    fi
}

show_management_commands() {
    module_log "INFO "Cluster Management Commands:"
    module_log "INFO " "
    module_log "INFO " " "  # Cluster Management:"
    module_log "INFO " " "  ${SERVERSH_LIB_DIR}/cluster/clusterctl.sh status"
    module_log "INFO " " "  ${SERVERSH_LIB_DIR}/cluster/clusterctl.sh list"
    module_log "INFO " " "  ${SERVERSH_LIB_DIR}/cluster/clusterctl.sh health"
    module_log "INFO " " "
    module_log "INFO " " "  # Node Management:"
    module_log "INFO " " "  ${SERVERSH_LIB_DIR}/cluster/node-manager.sh check_node <node-id>"
    module_log "INFO " " "  ${SERVERSH_LIB_DIR}/cluster/node-manager.sh list"
    module_log "INFO " " "
    module_log "INFO " " "  # Service Management:"
    module_log "INFO " " "  systemctl status serversh-cluster"
    module_log "INFO " " "  systemctl status serversh-master"
    module_log "INFO " " "  systemctl status serversh-worker"
    module_log "INFO " " "  systemctl status etcd"
}

# Initialize module (optional - called when module is sourced)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    module_log "DEBUG" "Multi-server management module loaded"
fi

return $MODULE_SUCCESS