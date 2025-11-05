# ServerSH API Reference

This document provides comprehensive API reference for ServerSH modules, scripts, and configuration options.

## Table of Contents

- [Core API](#core-api)
- [Module API](#module-api)
- [Script API](#script-api)
- [Configuration API](#configuration-api)
- [REST API](#rest-api)
- [Examples](#examples)

## Core API

### Constants API

```bash
# System Constants
SERVERSH_VERSION="2.0.0"
SERVERSH_ROOT="/opt/serversh"
SERVERSH_CONFIG_DIR="/etc/serversh"
SERVERSH_LOG_DIR="/var/log/serversh"
SERVERSH_STATE_DIR="/var/lib/serversh"

# Docker Constants
SERVERSH_DOCKER_NETWORK_NAME="newt_talk"
SERVERSH_DOCKER_NETWORK_MTU="1450"
SERVERSH_DOCKER_IPV6_SUBNET="2001:db8:1::/64"

# Ports
SERVERSH_DEFAULT_SSH_PORT="22"
SERVERSH_DEFAULT_PROMETHEUS_PORT="9090"
SERVERSH_DEFAULT_NODE_EXPORTER_PORT="9100"
```

### Logger API

```bash
# Logging Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [[ "${SERVERSH_DEBUG:-false}" == "true" ]]; then
        echo -e "${GRAY}[DEBUG]${NC} $1"
    fi
}
```

### State Management API

```bash
# State Functions
save_state() {
    local module="$1"
    local status="$2"
    local value="${3:-}"

    local state_file="${SERVERSH_STATE_DIR}/${module}.state"
    echo "${status}=$(date -Iseconds)" > "$state_file"

    if [[ -n "$value" ]]; then
        echo "value=${value}" >> "$state_file"
    fi
}

load_state() {
    local module="$1"
    local state_file="${SERVERSH_STATE_DIR}/${module}.state"

    if [[ -f "$state_file" ]]; then
        source "$state_file"
        echo "$status"
    fi
}

check_state() {
    local module="$1"
    local expected_status="$2"

    local current_status
    current_status=$(load_state "$module")

    [[ "$current_status" == "$expected_status" ]]
}
```

### Utility Functions API

```bash
# System Detection
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

detect_version() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$VERSION_ID"
    else
        echo "unknown"
    fi
}

# Package Manager Detection
detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# Service Management
start_service() {
    local service="$1"
    systemctl start "$service" && systemctl enable "$service"
}

stop_service() {
    local service="$1"
    systemctl stop "$service" && systemctl disable "$service"
}

restart_service() {
    local service="$1"
    systemctl restart "$service"
}

# File Operations
backup_file() {
    local file="$1"
    local backup_dir="${2:-${SERVERSH_STATE_DIR}/backups}"

    if [[ -f "$file" ]]; then
        mkdir -p "$backup_dir"
        cp "$file" "${backup_dir}/$(basename "$file").$(date +%Y%m%d_%H%M%S).bak"
    fi
}

# Port Operations
check_port() {
    local port="$1"
    local protocol="${2:-tcp}"

    if command -v ss >/dev/null 2>&1; then
        ss -"$protocol"ln | grep -q ":$port "
    else
        netstat -"$protocol"ln 2>/dev/null | grep -q ":$port "
    fi
}

find_available_port() {
    local start_port="$1"
    local end_port="$2"

    for ((port=start_port; port<=end_port; port++)); do
        if ! check_port "$port"; then
            echo "$port"
            return 0
        fi
    done

    return 1
}
```

## Module API

### Standard Module Interface

All ServerSH modules must implement the following interface:

```bash
#!/bin/bash
set -euo pipefail

# Module Metadata
MODULE_NAME="category/module_name"
MODULE_VERSION="1.0.0"
MODULE_DESCRIPTION="Module description"
MODULE_DEPENDENCIES=()

# Required Functions
validate() {
    # Validate configuration
    # Return: 0 on success, 1 on error
}

install() {
    # Install module
    # Return: 0 on success, 1 on error
}

uninstall() {
    # Uninstall module
    # Return: 0 on success, 1 on error
}

# Optional Functions
pre_install() {
    # Pre-installation hooks
}

post_install() {
    # Post-installation hooks
}

status() {
    # Check module status
    # Return: 0 if installed, 1 if not installed
}

# Module Execution
case "${1:-}" in
    "validate") validate ;;
    "install")
        pre_install
        install
        post_install
        ;;
    "uninstall") uninstall ;;
    "status") status ;;
    *)
        echo "Usage: $0 {validate|install|uninstall|status}"
        exit 1
        ;;
esac
```

### Module Configuration API

```bash
# Configuration Loading
load_module_config() {
    local module="$1"
    local config_file="${2:-${SERVERSH_CONFIG_DIR}/${module##*/}.yaml}"

    if [[ -f "$config_file" ]]; then
        # Parse YAML configuration
        parse_yaml "$config_file"
    fi
}

# Configuration Validation
validate_config_value() {
    local key="$1"
    local value="$2"
    local type="${3:-string}"

    case "$type" in
        "boolean")
            [[ "$value" =~ ^(true|false)$ ]]
            ;;
        "integer")
            [[ "$value" =~ ^[0-9]+$ ]]
            ;;
        "port")
            [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -ge 1 ]] && [[ "$value" -le 65535 ]]
            ;;
        "email")
            [[ "$value" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
            ;;
        *)
            true  # string type, always valid
            ;;
    esac
}
```

## Script API

### Installation Script API

```bash
# Main Installation Script
# Usage: ./install.sh [OPTIONS]

# Options
--config FILE           # Configuration file path
--modules MODULES       # Comma-separated list of modules
--dry-run              # Simulate installation without changes
--verbose              # Enable verbose output
--debug                # Enable debug output
--force                # Force reinstallation
--uninstall            # Uninstall modules
--status               # Show installation status

# Examples
./install.sh                                    # Interactive installation
./install.sh --config=config.yaml              # Installation with config
./install.sh --modules=security/ssh,docker     # Install specific modules
./install.sh --dry-run --verbose               # Simulation with verbose output
```

### Backup Control Script API

```bash
# Backup Control Script
# Usage: ./backupctl.sh [COMMAND] [OPTIONS]

# Commands
create [TYPE] [SOURCE]     # Create backup
restore <PATH> <TARGET>     # Restore backup
list [TYPE]                # List backups
status                     # Show backup status
schedule                   # Setup backup schedule
unschedule                 # Remove backup schedule
verify <PATH>              # Verify backup integrity
cleanup [TYPE]             # Cleanup old backups
disaster-recovery          # Create disaster recovery package
config                     # Show configuration
test                       # Test configuration

# Backup Types
full                       # Complete backup
incremental               # Incremental backup
differential              # Differential backup
snapshot                  # Filesystem snapshot

# Examples
./backupctl.sh create full                    # Create full backup
./backupctl.sh create incremental /home      # Incremental backup of /home
./backupctl.sh restore /backup/full/date /    # Restore to root
./backupctl.sh list full                      # List full backups
./backupctl.sh verify /backup/full/date      # Verify backup
./backupctl.sh cleanup --older-than=30d      # Cleanup old backups
```

### Cluster Control Script API

```bash
# Cluster Control Script
# Usage: ./clusterctl.sh [COMMAND] [OPTIONS]

# Commands
init --mode=MODE         # Initialize cluster
join --token=TOKEN       # Join cluster
status                   # Show cluster status
node SUBCOMMAND          # Node management
service SUBCOMMAND       # Service management
backend SUBCOMMAND       # Load balancer management
token SUBCOMMAND         # Token management

# Cluster Modes
single_node              # Single node cluster
multi_master             # Multi-master cluster
worker                   # Worker node

# Node Subcommands
list                     # List cluster nodes
status [NAME]            # Show node status
pause NAME               # Pause node
resume NAME              # Resume node
remove NAME              # Remove node
test NAME                # Test node connectivity

# Service Subcommands
list                     # List services
register --name=NAME    # Register service
unregister NAME          # Unregister service
health NAME              # Check service health

# Examples
./clusterctl.sh init --mode=single_node           # Initialize single node
./clusterctl.sh join --token=abc123 --master=1.2.3.4  # Join cluster
./clusterctl.sh node list                         # List nodes
./clusterctl.sh service register --name=web --port=80  # Register service
```

## Configuration API

### Environment Variable API

```bash
# Environment Variable Loading
load_env_file() {
    local env_file="${1:-.env}"

    if [[ -f "$env_file" ]]; then
        set -a
        source "$env_file"
        set +a
    fi
}

# Environment Variable Validation
validate_env_variable() {
    local var_name="$1"
    local required="${2:-false}"
    local default="${3:-}"

    local value="${!var_name:-$default}"

    if [[ "$required" == "true" && -z "$value" ]]; then
        log_error "Required environment variable $var_name is not set"
        return 1
    fi

    export "$var_name"="$value"
}

# Environment Variable Expansion
expand_env_vars() {
    local text="$1"

    while [[ "$text" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name:-}"
        text="${text/\$\{$var_name\}/$var_value}"
    done

    echo "$text"
}
```

### YAML Configuration API

```bash
# YAML Parser (simplified)
parse_yaml() {
    local file="$1"
    local prefix="${2:-}"

    while IFS='=' read -r key value; do
        if [[ "$key" =~ ^# ]] || [[ -z "$key" ]]; then
            continue
        fi

        # Convert YAML key to bash variable
        local bash_key="${key//[\/:]/_}"
        bash_key="${bash_key// /_}"
        bash_key="${prefix}${bash_key^^}"

        # Export variable
        export "$bash_key"="$value"
    done < <(grep -v '^[[:space:]]*#' "$file" | grep -v '^[[:space:]]*$' | sed 's/^[[:space:]]*//' | sed 's/: /=/' | sed 's/ #.*//')
}

# YAML Validation
validate_yaml() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "YAML file not found: $file"
        return 1
    fi

    # Basic syntax validation
    if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        return 0
    else
        log_error "Invalid YAML syntax in: $file"
        return 1
    fi
}

# Configuration Merging
merge_configs() {
    local base_config="$1"
    local override_config="$2"
    local output_file="$3"

    if command -v yq >/dev/null 2>&1; then
        yq merge "$base_config" "$override_config" > "$output_file"
    else
        # Fallback: simple concatenation
        cat "$base_config" "$override_config" > "$output_file"
    fi
}
```

## REST API

### Authentication

```bash
# API Authentication
API_TOKEN="${SERVERSH_API_TOKEN:-}"
API_BASE_URL="http://localhost:8080/api/v1"

# Make authenticated request
api_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local curl_args=(
        -X "$method"
        -H "Authorization: Bearer $API_TOKEN"
        -H "Content-Type: application/json"
        "$API_BASE_URL$endpoint"
    )

    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    curl "${curl_args[@]}"
}
```

### Endpoints

#### System Endpoints

```bash
# Get system information
GET /api/v1/system/info

Response:
{
    "version": "2.0.0",
    "hostname": "myserver",
    "os": "ubuntu",
    "architecture": "x86_64",
    "uptime": 86400,
    "load_average": [0.1, 0.2, 0.3]
}

# Get system status
GET /api/v1/system/status

Response:
{
    "status": "healthy",
    "services": {
        "ssh": "running",
        "docker": "running",
        "prometheus": "running"
    },
    "last_update": "2024-01-01T12:00:00Z"
}
```

#### Module Endpoints

```bash
# List modules
GET /api/v1/modules

Response:
{
    "modules": [
        {
            "name": "system/update",
            "version": "1.0.0",
            "status": "installed",
            "description": "System update management"
        },
        {
            "name": "container/docker",
            "version": "1.0.0",
            "status": "installed",
            "description": "Docker container management"
        }
    ]
}

# Get module details
GET /api/v1/modules/{module_name}

Response:
{
    "name": "container/docker",
    "version": "1.0.0",
    "status": "installed",
    "description": "Docker container management",
    "dependencies": ["system/update"],
    "configuration": {
        "version": "latest",
        "install_compose": true
    },
    "installed_at": "2024-01-01T12:00:00Z"
}

# Install module
POST /api/v1/modules/{module_name}/install

Request:
{
    "configuration": {
        "version": "latest",
        "install_compose": true
    }
}

Response:
{
    "status": "success",
    "message": "Module installation started",
    "task_id": "abc123"
}
```

#### Backup Endpoints

```bash
# List backups
GET /api/v1/backups

Response:
{
    "backups": [
        {
            "id": "full_20240101_020000",
            "type": "full",
            "path": "/backup/full/2024-01-01_02-00-00",
            "size": 1073741824,
            "created_at": "2024-01-01T02:00:00Z",
            "status": "completed"
        }
    ]
}

# Create backup
POST /api/v1/backups

Request:
{
    "type": "full",
    "sources": "/etc,/home,/var/www",
    "compression": "gzip",
    "encryption": false
}

Response:
{
    "status": "success",
    "backup_id": "full_20240101_030000",
    "task_id": "def456"
}

# Get backup status
GET /api/v1/backups/{backup_id}

Response:
{
    "id": "full_20240101_020000",
    "type": "full",
    "status": "completed",
    "progress": 100,
    "size": 1073741824,
    "created_at": "2024-01-01T02:00:00Z",
    "completed_at": "2024-01-01T02:15:00Z"
}
```

#### Cluster Endpoints

```bash
# Get cluster status
GET /api/v1/cluster

Response:
{
    "mode": "single_node_cluster",
    "status": "healthy",
    "nodes": [
        {
            "name": "node1",
            "role": "master",
            "status": "ready",
            "ip": "192.168.1.10"
        }
    ],
    "services": [
        {
            "name": "etcd",
            "status": "running"
        }
    ]
}

# Join cluster
POST /api/v1/cluster/join

Request:
{
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "master_ip": "192.168.1.10",
    "role": "worker"
}

Response:
{
    "status": "success",
    "message": "Node joining cluster",
    "task_id": "ghi789"
}
```

## Examples

### Module Development Example

```bash
#!/bin/bash
# serversh/modules/custom/nginx.sh

set -euo pipefail

source "${SERVERSH_ROOT}/core/utils.sh"
source "${SERVERSH_ROOT}/core/logger.sh"
source "${SERVERSH_ROOT}/core/state.sh"

MODULE_NAME="custom/nginx"
MODULE_VERSION="1.0.0"
MODULE_DESCRIPTION="Nginx web server"
MODULE_DEPENDENCIES=("system/update")

# Configuration defaults
NGINX_VERSION="${NGINX_VERSION:-latest}"
NGINX_PORT="${NGINX_PORT:-80}"
NGINX_SSL_PORT="${NGINX_SSL_PORT:-443}"
NGINX_SITES_ENABLED="${NGINX_SITES_ENABLED:-true}"

validate() {
    log_info "Validating nginx configuration"

    # Validate port numbers
    if ! [[ "$NGINX_PORT" =~ ^[0-9]+$ ]] || [[ "$NGINX_PORT" -lt 1 ]] || [[ "$NGINX_PORT" -gt 65535 ]]; then
        log_error "Invalid nginx port: $NGINX_PORT"
        return 1
    fi

    if ! [[ "$NGINX_SSL_PORT" =~ ^[0-9]+$ ]] || [[ "$NGINX_SSL_PORT" -lt 1 ]] || [[ "$NGINX_SSL_PORT" -gt 65535 ]]; then
        log_error "Invalid nginx SSL port: $NGINX_SSL_PORT"
        return 1
    fi

    # Check port availability
    if check_port "$NGINX_PORT"; then
        log_error "Port $NGINX_PORT is already in use"
        return 1
    fi

    if check_port "$NGINX_SSL_PORT"; then
        log_error "Port $NGINX_SSL_PORT is already in use"
        return 1
    fi

    log_success "Nginx configuration validation completed"
    return 0
}

install() {
    log_info "Installing nginx $NGINX_VERSION"

    local pkg_manager
    pkg_manager=$(detect_package_manager)

    case "$pkg_manager" in
        "apt")
            apt update
            apt install -y nginx
            ;;
        "dnf"|"yum")
            "$pkg_manager" install -y nginx
            ;;
        "pacman")
            pacman -S --noconfirm nginx
            ;;
        *)
            log_error "Unsupported package manager: $pkg_manager"
            return 1
            ;;
    esac

    # Configure nginx
    configure_nginx

    # Start and enable service
    start_service "nginx"

    # Save state
    save_state "${MODULE_NAME}" "installed" "version=$NGINX_VERSION"

    log_success "Nginx installation completed"
    return 0
}

configure_nginx() {
    local nginx_conf="/etc/nginx/nginx.conf"

    # Backup original configuration
    backup_file "$nginx_conf"

    # Create nginx configuration
    cat > "$nginx_conf" << EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss;

    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

    # Create default site
    create_default_site
}

create_default_site() {
    local site_conf="/etc/nginx/sites-available/default"

    cat > "$site_conf" << EOF
server {
    listen $NGINX_PORT default_server;
    listen [::]:$NGINX_PORT default_server;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    server_name _;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}

server {
    listen $NGINX_SSL_PORT ssl default_server;
    listen [::]:$NGINX_SSL_PORT ssl default_server;

    root /var/www/html;
    index index.html index.htm;

    server_name _;

    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

    # Enable site
    if [[ "$NGINX_SITES_ENABLED" == "true" ]]; then
        ln -sf "$site_conf" "/etc/nginx/sites-enabled/"
    fi
}

uninstall() {
    log_info "Uninstalling nginx"

    # Stop and disable service
    stop_service "nginx"

    local pkg_manager
    pkg_manager=$(detect_package_manager)

    # Remove nginx package
    case "$pkg_manager" in
        "apt")
            apt remove --purge -y nginx nginx-common nginx-core
            ;;
        "dnf"|"yum")
            "$pkg_manager" remove -y nginx
            ;;
        "pacman")
            pacman -R --noconfirm nginx
            ;;
    esac

    # Remove configuration (optional - keep for safety)
    # rm -rf /etc/nginx

    # Save state
    save_state "${MODULE_NAME}" "uninstalled"

    log_success "Nginx uninstallation completed"
}

status() {
    if systemctl is-active --quiet nginx; then
        echo "installed"
        return 0
    else
        echo "not_installed"
        return 1
    fi
}

# Execute module operations
case "${1:-}" in
    "validate")
        validate
        ;;
    "install")
        if validate; then
            install
        else
            exit 1
        fi
        ;;
    "uninstall")
        uninstall
        ;;
    "status")
        status
        ;;
    *)
        echo "Usage: $0 {validate|install|uninstall|status}"
        exit 1
        ;;
esac
```

### REST API Client Example

```bash
#!/bin/bash
# ServerSH API Client Example

set -euo pipefail

# Configuration
API_BASE_URL="http://localhost:8080/api/v1"
API_TOKEN="${SERVERSH_API_TOKEN:-}"

# API Functions
api_get() {
    local endpoint="$1"
    curl -s -H "Authorization: Bearer $API_TOKEN" "$API_BASE_URL$endpoint"
}

api_post() {
    local endpoint="$1"
    local data="$2"
    curl -s -X POST -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json" -d "$data" "$API_BASE_URL$endpoint"
}

# Usage Examples
get_system_info() {
    echo "=== System Information ==="
    api_get "/system/info" | jq '.'
}

list_modules() {
    echo "=== Installed Modules ==="
    api_get "/modules" | jq '.modules[] | {name: .name, status: .status}'
}

create_backup() {
    local backup_type="${1:-full}"
    echo "=== Creating $backup_type backup ==="

    local response
    response=$(api_post "/backups" "{\"type\": \"$backup_type\"}")

    echo "$response" | jq '.'

    local task_id
    task_id=$(echo "$response" | jq -r '.task_id')

    if [[ "$task_id" != "null" ]]; then
        echo "Backup task started with ID: $task_id"
        monitor_task "$task_id"
    fi
}

monitor_task() {
    local task_id="$1"

    echo "Monitoring task $task_id..."

    while true; do
        local status
        status=$(api_get "/tasks/$task_id" | jq -r '.status')

        echo "Task status: $status"

        if [[ "$status" == "completed" || "$status" == "failed" ]]; then
            break
        fi

        sleep 5
    done
}

# Main execution
case "${1:-}" in
    "info")
        get_system_info
        ;;
    "modules")
        list_modules
        ;;
    "backup")
        create_backup "${2:-full}"
        ;;
    *)
        echo "Usage: $0 {info|modules|backup [type]}"
        exit 1
        ;;
esac
```

This API reference provides comprehensive documentation for all ServerSH interfaces and can be used as a guide for module development, automation scripting, and integration with external systems.