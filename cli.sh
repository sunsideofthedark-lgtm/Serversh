#!/bin/bash

# =============================================================================
# ServerSH CLI - Simple Server Management
# =============================================================================
# One script, one config, complete server management

set -euo pipefail

# Script information
SCRIPT_VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ASCII Art Banner
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
 ____                       ____  _
|  _ \ __ _ _ __   ___ _ __/ ___|| | ___
| |_) / _` | '_ \ / _ \ '__\___ \| |/ _ \
|  _ < (_| | |_) |  __/ |   ___) | |  __/
|_| \_\__,_| .__/ \___|_|  |____/|_|\___|
           |_|
            S E R V E R   M A N A G E M E N T
EOF
    echo -e "${NC}"
    echo -e "${PURPLE}Version $SCRIPT_VERSION • Simple Server Management${NC}"
    echo ""
}

# Logging functions
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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# Help information
show_help() {
    cat << EOF
ServerSH CLI - Simple Server Management

USAGE:
    $0 [COMMAND] [OPTIONS]

INSTALLATION COMMANDS:
    install              Install ServerSH (interactive)
    install --auto       Auto-install with defaults
    install --web        Install Web UI only
    install --with-web  Install CLI + Web UI
    install --profile P  Install with profile (minimal|standard|full)

PROFILE COMMANDS:
    create-profile P      Create profile config file
    list-profiles         List available profiles
    show-profile P        Show profile configuration

WEB UI COMMANDS:
    web start             Start Web UI service
    web stop              Stop Web UI service
    web restart           Restart Web UI service
    web status            Check Web UI status
    web logs              Show Web UI logs

SYSTEM COMMANDS:
    status                Show system status
    update                Update ServerSH installation
    config                Show/edit configuration
    diagnose              Run system diagnosis

BACKUP COMMANDS:
    backup create TYPE    Create backup (full|incremental|differential)
    backup restore PATH   Restore from backup
    backup list           List backups
    backup schedule       Setup backup schedule

SSH COMMANDS:
    ssh keys generate     Generate SSH keys
    ssh keys list         List SSH keys
    ssh keys download F   Download SSH key (openssh|json)
    ssh config            Show SSH configuration

MODULE COMMANDS:
    module list           List available modules
    module install M      Install module
    module uninstall M    Uninstall module
    module status M       Check module status
    module update M       Update module

CONFIG COMMANDS:
    config show           Show current configuration
    config edit           Edit configuration file
    config validate       Validate configuration
    config reset          Reset configuration

UTILITIES:
    logs                  Show system logs
    clean                 Clean temporary files
    version               Show version information
    help                  Show this help message

EXAMPLES:
    # Interactive installation
    $0 install

    # Auto-install with standard profile
    $0 install --auto --profile=standard

    # Web UI management
    $0 web start
    $0 web status

    # System management
    $0 status
    $0 backup create full
    $0 ssh keys generate

    # Module management
    $0 module install docker
    $0 module status prometheus

CONFIGURATION:
    All configuration is done through the .env file.
    Copy .env.example to .env and customize settings.

WEB UI:
    After installation, access: http://your-server-ip:8080
    Login with root credentials

For help and examples, run: ./cli.sh help
EOF
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This command requires root privileges"
        echo "Use: sudo $0 $*"
        exit 1
    fi
}

# Detect operating system
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# Detect package manager
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

# Load environment configuration
load_env() {
    local env_file="${1:-.env}"

    if [[ -f "$env_file" ]]; then
        log_info "Loading configuration from: $env_file"
        set -a
        source "$env_file"
        set +a
    else
        log_warning "Environment file not found: $env_file"
        if [[ "$1" != ".env" ]]; then
            log_info "You can create one by copying .env.example"
        fi
    fi
}

# Validate configuration
validate_config() {
    log_step "Validating configuration..."

    local errors=()

    # Check required variables
    local required_vars=("SERVERSH_HOSTNAME" "SERVERSH_USERNAME" "SERVERSH_USER_PASSWORD")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            errors+=("$var is not set")
        fi
    done

    # Check password strength
    if [[ -n "${SERVERSH_USER_PASSWORD:-}" ]] && [[ ${#SERVERSH_USER_PASSWORD} -lt 8 ]]; then
        errors+=("SERVERSH_USER_PASSWORD must be at least 8 characters")
    fi

    # Check port numbers
    local port_vars=("SERVERSH_WEB_UI_PORT" "SERVERSH_SSH_PREFERRED_PORT" "SERVERSH_PROMETHEUS_PORT")
    for var in "${port_vars[@]}"; do
        if [[ -n "${!var:-}" ]] && ! [[ "${!var}" =~ ^[0-9]+$ ]]; then
            errors+=("$var must be a valid port number")
        fi
    done

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Configuration validation failed:"
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi

    log_success "Configuration validation passed"
    return 0
}

# Create configuration profile
create_profile() {
    local profile="$1"

    if [[ -z "$profile" ]]; then
        log_error "Profile name required"
        echo "Available profiles: minimal, standard, full"
        return 1
    fi

    log_step "Creating $profile profile..."

    case "$profile" in
        "minimal")
            cat > .env << 'EOF'
# ServerSH Minimal Configuration
SERVERSH_HOSTNAME=minimal-server
SERVERSH_USERNAME=admin
SERVERSH_USER_PASSWORD=MinimalPass123!
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_DOCKER_ENABLE=true
SERVERSH_PROMETHEUS_ENABLE=false
SERVERSH_BACKUP_ENABLE=false
SERVERSH_WEB_UI_ENABLE=false
SERVERSH_INSTALL_TAILSCALE=false
EOF
            ;;
        "standard")
            cat > .env << 'EOF'
# ServerSH Standard Configuration
SERVERSH_HOSTNAME=production-server
SERVERSH_USERNAME=admin
SERVERSH_USER_PASSWORD=SecurePassword123!
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_FIREWALL_ENABLE=true
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DOCKER_INSTALL_COMPOSE=true
SERVERSH_PROMETHEUS_ENABLE=true
SERVERSH_BACKUP_ENABLE=true
SERVERSH_WEB_UI_ENABLE=true
SERVERSH_INSTALL_TAILSCALE=true
SERVERSH_TAILSCALE_SSH=true
SERVERSH_TAILSCALE_MAGICDNS=true
SERVERSH_INSTALL_UTILITIES=true
EOF
            ;;
        "full")
            cat > .env << 'EOF'
# ServerSH Full Configuration
SERVERSH_HOSTNAME=full-stack-server
SERVERSH_USERNAME=admin
SERVERSH_USER_PASSWORD=SuperSecurePassword123!
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_FIREWALL_ENABLE=true
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DOCKER_INSTALL_COMPOSE=true
SERVERSH_PROMETHEUS_ENABLE=true
SERVERSH_BACKUP_ENABLE=true
SERVERSH_BACKUP_ENCRYPTION=true
SERVERSH_WEB_UI_ENABLE=true
SERVERSH_INSTALL_TAILSCALE=true
SERVERSH_TAILSCALE_SSH=true
SERVERSH_TAILSCALE_MAGICDNS=true
SERVERSH_INSTALL_UTILITIES=true
SERVERSH_INSTALL_DEV_TOOLS=true
SERVERSH_INSTALL_MONITORING_TOOLS=true
SERVERSH_INSTALL_DOCKER_EXTRAS=true
SERVERSH_MULTI_SERVER_MODE=cluster
SERVERSH_BACKUP_REMOTE_ENABLE=true
EOF
            ;;
        *)
            log_error "Unknown profile: $profile"
            echo "Available profiles: minimal, standard, full"
            return 1
            ;;
    esac

    # Add deployment info
    cat >> .env << EOF

# Deployment Info
SERVERSH_VERSION=$SCRIPT_VERSION
SERVERSH_INSTALLATION_DATE=$(date -Iseconds)
SERVERSH_PROFILE=$profile
EOF

    log_success "Profile '$profile' created in .env"
    log_info "You can now edit .env to customize settings"
    return 0
}

# List available profiles
list_profiles() {
    echo "Available profiles:"
    echo "  minimal    - Basic system + SSH + Docker"
    echo "  standard   - Full production setup with monitoring"
    echo "  full       - Complete setup with all features"
    echo "  development- Dev tools and utilities"
    echo ""
    echo "Usage:"
    echo "  $0 create-profile <profile>"
    echo "  $0 install --profile <profile>"
}

# Show profile configuration
show_profile() {
    local profile="$1"

    if [[ -z "$profile" ]]; then
        if [[ -f .env ]]; then
            echo "Current profile: $(grep 'SERVERSH_PROFILE=' .env 2>/dev/null | cut -d'=' -f2 || 'custom')"
            echo ""
            echo "Configuration:"
            cat .env
        else
            log_error "No .env file found"
        fi
        return 0
    fi

    echo "Profile: $profile"
    echo ""

    case "$profile" in
        "minimal")
            echo "Includes: System updates, SSH hardening, Docker"
            echo "Perfect for: Development servers, basic setups"
            ;;
        "standard")
            echo "Includes: All minimal + Monitoring + Firewall + Web UI + Tailscale"
            echo "Perfect for: Production servers, full management"
            ;;
        "full")
            echo "Includes: All standard + Advanced monitoring + Cluster + Remote backup"
            echo "Perfect for: Enterprise deployments, multi-server setups"
            ;;
        *)
            log_error "Unknown profile: $profile"
            return 1
            ;;
    esac
}

# Installation functions
install_server() {
    log_step "Installing ServerSH..."

    # Check dependencies
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python 3 is required"
        return 1
    fi

    # Validate configuration
    if ! validate_config; then
        return 1
    fi

    # Install ServerSH core
    local install_script="${PROJECT_DIR}/serversh/scripts/install-from-env.sh"
    if [[ -f "$install_script" ]]; then
        log_info "Ensuring script permissions..."
        chmod +x "$install_script"
        log_info "Executing ServerSH installation..."
        if "$install_script"; then
            log_success "ServerSH installation completed"
            return 0
        else
            log_error "ServerSH installation failed"
            return 1
        fi
    else
        log_error "Installation script not found: $install_script"
        return 1
    fi
}

install_web() {
    log_step "Installing Web UI..."

    local web_setup_script="${PROJECT_DIR}/serversh/scripts/web-setup.sh"
    if [[ -f "$web_setup_script" ]]; then
        chmod +x "$web_setup_script"
        log_info "Executing Web UI installation..."
        if "$web_setup_script" install; then
            log_success "Web UI installation completed"
            show_web_info
            return 0
        else
            log_error "Web UI installation failed"
            return 1
        fi
    else
        log_error "Web setup script not found: $web_setup_script"
        return 1
    fi
}

# Show Web UI information
show_web_info() {
    if [[ "${SERVERSH_WEB_UI_ENABLE:-false}" == "true" ]]; then
        local server_ip
        server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
        local port="${SERVERSH_WEB_UI_PORT:-8080}"

        echo ""
        echo "🌐 Web UI Information:"
        echo "   Access URL: http://$server_ip:$port"
        echo "   Local URL: http://localhost:$port"
        echo "   Login with your root credentials"
        echo ""
        echo "🔧 Management Commands:"
        echo "   $0 web status     # Check Web UI status"
        echo "   $0 web logs       # View Web UI logs"
        echo "   $0 web restart    # Restart Web UI service"
        echo ""
    fi
}

# System status
show_status() {
    log_step "Checking system status..."

    echo ""
    echo "ServerSH System Status"
    echo "======================="
    echo ""

    # Load configuration
    load_env

    # Check if ServerSH is installed
    if [[ -f "${PROJECT_DIR}/serversh/scripts/status.sh" ]]; then
        chmod +x "${PROJECT_DIR}/serversh/scripts/status.sh"
        if "${PROJECT_DIR}/serversh/scripts/status.sh" 2>/dev/null; then
            log_success "ServerSH is properly installed"
        else
            log_warning "ServerSH installation may have issues"
        fi
    else
        log_error "ServerSH is not installed"
        echo "Run: $0 install"
        return 1
    fi

    echo ""

    # Check Web UI
    if [[ "${SERVERSH_WEB_UI_ENABLE:-false}" == "true" ]]; then
        if systemctl is-active --quiet serversh-web 2>/dev/null; then
            local server_ip
            server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
            local port="${SERVERSH_WEB_UI_PORT:-8080}"
            log_success "Web UI is running"
            echo "  Access URL: http://$server_ip:$port"
            echo "  Local URL: http://localhost:$port"
        else
            log_warning "Web UI is not running"
            echo "Run: $0 web start"
        fi
    else
        echo "Web UI: Disabled in configuration"
    fi

    echo ""

    # Check services
    local services=("ssh" "docker" "prometheus-node-exporter" "nginx" "fail2ban")
    echo "Service Status:"
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "  ✅ $service: running"
        elif systemctl list-unit-files | grep -q "^$service.service"; then
            echo "  ❌ $service: stopped"
        else
            echo "  ⚪ $service: not installed"
        fi
    done

    echo ""

    # Show configuration summary
    echo "Configuration Summary:"
    echo "  Hostname: ${SERVERSH_HOSTNAME:-not set}"
    echo "  User: ${SERVERSH_USERNAME:-not set}"
    echo "  SSH Port: ${SERVERSH_SSH_PREFERRED_PORT:-auto}"
    echo "  Web UI: ${SERVERSH_WEB_UI_ENABLE:-false}"
    echo "  Docker: ${SERVERSH_DOCKER_ENABLE:-false}"
    echo "  Monitoring: ${SERVERSH_PROMETHEUS_ENABLE:-false}"
    echo "  Backup: ${SERVERSH_BACKUP_ENABLE:-false}"
    echo ""

    return 0
}

# Module management
list_modules() {
    log_step "Listing available modules..."

    local modules_dir="${PROJECT_DIR}/serversh/modules"
    if [[ ! -d "$modules_dir" ]]; then
        log_error "Modules directory not found: $modules_dir"
        return 1
    fi

    echo "Available Modules:"
    echo ""

    for category in "$modules_dir"/*; do
        if [[ -d "$category" ]]; then
            local category_name=$(basename "$category")
            echo "  $category_name:"
            for module in "$category"/*.sh; do
                if [[ -f "$module" ]]; then
                    local module_name=$(basename "$module" .sh)
                    echo "    - $module_name"
                fi
            done
            echo ""
        fi
    done

    return 0
}

manage_module() {
    local action="$1"
    local module="$2"

    if [[ -z "$module" ]]; then
        log_error "Module name required"
        return 1
    fi

    local module_file="${PROJECT_DIR}/serversh/modules/*/$module.sh"
    module_file=$(find "${PROJECT_DIR}/serversh/modules" -name "$module.sh" -type f | head -n1)

    if [[ ! -f "$module_file" ]]; then
        log_error "Module not found: $module"
        return 1
    fi

    log_step "$action module: $module"

    chmod +x "$module_file"
    if bash "$module_file" "$action"; then
        log_success "Module $action completed: $module"
    else
        log_error "Module $action failed: $module"
        return 1
    fi
}

# SSH management
manage_ssh_keys() {
    local action="$1"

    case "$action" in
        "generate")
            log_step "Generating SSH keys..."

            local username="${SERVERSH_USERNAME:-admin}"
            local ssh_dir="/home/$username/.ssh"

            if [[ ! -d "$ssh_dir" ]]; then
                mkdir -p "$ssh_dir"
                chown "$username:$username" "$ssh_dir"
                chmod 700 "$ssh_dir"
            fi

            # Generate key
            ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N "" -C "serversh-key-$(date +%Y%m%d)"

            # Add to authorized_keys
            cat "$ssh_dir/id_ed25519.pub" >> "$ssh_dir/authorized_keys"
            chmod 600 "$ssh_dir/authorized_keys"

            # Set permissions
            chmod 600 "$ssh_dir/id_ed25519"
            chmod 644 "$ssh_dir/id_ed25519.pub"

            chown -R "$username:$username" "$ssh_dir"

            log_success "SSH keys generated for user: $username"
            log_info "Private key: $ssh_dir/id_ed25519"
            log_info "Public key: $ssh_dir/id_ed25519.pub"
            ;;
        "list")
            local username="${SERVERSH_USERNAME:-admin}"
            local ssh_dir="/home/$username/.ssh"

            echo "SSH Keys for user: $username"
            echo "======================="

            if [[ -f "$ssh_dir/id_ed25519.pub" ]]; then
                echo "Public Key:"
                cat "$ssh_dir/id_ed25519.pub"
                echo ""
            fi

            if [[ -f "$ssh_dir/authorized_keys" ]]; then
                echo "Authorized Keys:"
                cat "$ssh_dir/authorized_keys"
                echo ""
            fi

            if [[ -f "$ssh_dir/id_ed25519" ]]; then
                echo "Private Key exists: $ssh_dir/id_ed25519"
            else
                echo "No private key found"
            fi
            ;;
        "download")
            local format="${2:-openssh}"
            local username="${SERVERSH_USERNAME:-admin}"
            local ssh_dir="/home/$username/.ssh"

            case "$format" in
                "openssh")
                    if [[ -f "$ssh_dir/id_ed25519" ]]; then
                        echo "OpenSSH Private Key:"
                        cat "$ssh_dir/id_ed25519"
                    else
                        log_error "Private key not found"
                        return 1
                    fi
                    ;;
                "json")
                    if [[ -f "$ssh_dir/id_ed25519" ]] && [[ -f "$ssh_dir/id_ed25519.pub" ]]; then
                        local private_key=$(cat "$ssh_dir/id_ed25519")
                        local public_key=$(cat "$ssh_dir/id_ed25519.pub")

                        echo "{"
                        echo "  \"private_key\": \"$private_key\","
                        echo "  \"public_key\": \"$public_key\","
                        echo "  \"format\": \"openssh\","
                        echo "  \"type\": \"ed25519\","
                        echo "  \"comment\": \"serversh-key-$(date +%Y%m%d)\","
                        echo "  \"generated_at\": \"$(date -Iseconds)\","
                        echo "  \"username\": \"$username\""
                        echo "}"
                    else
                        log_error "SSH keys not found"
                        return 1
                    fi
                    ;;
                *)
                    log_error "Unsupported format: $format"
                    echo "Available formats: openssh, json"
                    return 1
                    ;;
            esac
            ;;
        *)
            log_error "Unknown SSH action: $action"
            echo "Available actions: generate, list, download"
            return 1
            ;;
    esac
}

# Backup management
manage_backup() {
    local action="$1"
    local arg="${2:-}"

    load_env

    case "$action" in
        "create")
            local backup_type="${arg:-full}"
            log_step "Creating $backup_type backup..."

            local backup_script="${PROJECT_DIR}/serversh/scripts/backupctl.sh"
            if [[ -f "$backup_script" ]]; then
                chmod +x "$backup_script"
                if "$backup_script" "create" "$backup_type"; then
                    log_success "Backup created successfully"
                else
                    log_error "Backup creation failed"
                    return 1
                fi
            else
                log_error "Backup script not found"
                return 1
            fi
            ;;
        "list")
            log_step "Listing backups..."

            local backup_script="${PROJECT_DIR}/serversh/scripts/backupctl.sh"
            if [[ -f "$backup_script" ]]; then
                chmod +x "$backup_script"
                "$backup_script" "list"
            else
                log_error "Backup script not found"
                return 1
            fi
            ;;
        "schedule")
            log_step "Setting up backup schedule..."

            local backup_script="${PROJECT_DIR}/serversh/scripts/backupctl.sh"
            if [[ -f "$backup_script" ]]; then
                chmod +x "$backup_script"
                if "$backup_script" "schedule"; then
                    log_success "Backup schedule configured"
                else
                    log_error "Backup schedule setup failed"
                    return 1
                fi
            else
                log_error "Backup script not found"
                return 1
            fi
            ;;
        *)
            log_error "Unknown backup action: $action"
            echo "Available actions: create, list, schedule"
            return 1
            ;;
    esac
}

# Web UI management
manage_web() {
    local action="${1:-status}"

    case "$action" in
        "start")
            log_step "Starting Web UI service..."
            systemctl start serversh-web
            ;;
        "stop")
            log_step "Stopping Web UI service..."
            systemctl stop serversh-web
            ;;
        "restart")
            log_step "Restarting Web UI service..."
            systemctl restart serversh-web
            ;;
        "status")
            if systemctl is-active --quiet serversh-web; then
                log_success "Web UI service is running"
                show_web_info
            else
                log_warning "Web UI service is not running"
            fi
            ;;
        "logs")
            log_info "Web UI logs (Ctrl+C to exit):"
            journalctl -u serversh-web -f
            ;;
        *)
            log_error "Unknown web action: $action"
            echo "Available actions: start, stop, restart, status, logs"
            return 1
            ;;
    esac
}

# Configuration management
manage_config() {
    local action="${1:-show}"

    case "$action" in
        "show")
            if [[ -f .env ]]; then
                echo "Current Configuration:"
                echo "=================="
                cat .env
            else
                log_error "Configuration file not found: .env"
                echo "Create one with: $0 create-profile standard"
            fi
            ;;
        "edit")
            if [[ -f .env ]]; then
                log_info "Opening configuration file in editor..."
                ${EDITOR:-nano} .env
            else
                log_error "Configuration file not found: .env"
                echo "Create one with: $0 create-profile standard"
            fi
            ;;
        "validate")
            load_env
            validate_config
            ;;
        "reset")
            if [[ -f .env ]]; then
                log_warning "This will reset your configuration. Continue? [y/N]"
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    cp .env ".env.backup.$(date +%Y%m%d_%H%M%S)"
                    rm .env
                    log_success "Configuration reset. Backup saved as .env.backup.$(date +%Y%m%d_%H%M%S)"
                fi
            else
                log_error "Configuration file not found: .env"
            fi
            ;;
        *)
            log_error "Unknown config action: $action"
            echo "Available actions: show, edit, validate, reset"
            return 1
            ;;
    esac
}

# System diagnosis
run_diagnosis() {
    log_step "Running system diagnosis..."

    echo ""
    echo "System Diagnosis Report"
    echo "===================="
    echo ""

    # System info
    echo "System Information:"
    echo "  OS: $(detect_os)"
    echo "  Kernel: $(uname -r)"
    echo "  Architecture: $(uname -m)"
    echo "  Uptime: $(uptime -p)"
    echo ""

    # ServerSH installation
    echo "ServerSH Installation:"
    if [[ -f "${PROJECT_DIR}/serversh/scripts/status.sh" ]]; then
        echo "  ✅ Core installation found"
    else
        echo "  ❌ Core installation not found"
    fi

    if [[ -f "${PROJECT_DIR}/serversh/scripts/web-setup.sh" ]]; then
        echo "  ✅ Web UI installation found"
    else
        echo "  ❌ Web UI installation not found"
    fi

    echo ""

    # Services
    echo "Service Status:"
    local services=("serversh-web" "ssh" "docker" "prometheus-node-exporter")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "  ✅ $service: running"
        elif systemctl list-unit-files | grep -q "^$service.service"; then
            echo "  ❌ $service: stopped"
        else
            echo "  ⚪ $service: not installed"
        fi
    done

    echo ""

    # Ports
    echo "Port Status:"
    local ports=("22" "${SERVERSH_WEB_UI_PORT:-8080}" "${SERVERSH_PROMETHEUS_PORT:-9090}")
    for port in "${ports[@]}"; do
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            echo "  ✅ Port $port: in use"
        else
            echo "  ❌ Port $port: not in use"
        fi
    done

    echo ""

    # Configuration
    echo "Configuration Check:"
    if [[ -f .env ]]; then
        echo "  ✅ .env file exists"
        local required_vars=("SERVERSH_HOSTNAME" "SERVERSH_USERNAME" "SERVERSH_USER_PASSWORD")
        local missing_vars=()
        for var in "${required_vars[@]}"; do
            if ! grep -q "^${var}=" .env; then
                missing_vars+=("$var")
            fi
        done

        if [[ ${#missing_vars[@]} -eq 0 ]]; then
            echo "  ✅ All required variables set"
        else
            echo "  ❌ Missing variables: ${missing_vars[*]}"
        fi
    else
        echo "  ❌ .env file not found"
    fi

    echo ""
    echo "Diagnosis completed."
}

# Clean temporary files
clean_temp() {
    log_step "Cleaning temporary files..."

    # Clean ServerSH temp files
    local temp_dirs=(
        "/tmp/serversh*"
        "/var/tmp/serversh*"
        "${PROJECT_DIR}/serversh/tmp"
    )

    for temp_dir in "${temp_dirs[@]}"; do
        if [[ -d "$temp_dir" ]]; then
            log_info "Cleaning: $temp_dir"
            rm -rf "$temp_dir"
        fi
    done

    # Clean logs older than 7 days
    find /var/log -name "serversh*" -mtime +7 -delete 2>/dev/null || true

    log_success "Temporary files cleaned"
}

# Show version
show_version() {
    echo "ServerSH CLI"
    echo "Version: $SCRIPT_VERSION"
    echo "Project: $PROJECT_DIR"
    echo ""
    echo "Configuration: ${SERVERSH_VERSION:-2.0.0}"
    echo "Profile: ${SERVERSH_PROFILE:-custom}"
    echo ""
}

# Main function
main() {
    local command="${1:-help}"

    case "$command" in
        "install")
            check_root
            show_banner

            case "${2:-}" in
                "--auto")
                    log_info "Auto-installation mode"
                    if [[ ! -f .env ]]; then
                        create_profile "standard"
                    fi
                    load_env
                    install_server
                    ;;
                "--web")
                    install_web
                    ;;
                "--with-web")
                    log_info "CLI + Web UI installation"
                    if [[ ! -f .env ]]; then
                        create_profile "standard"
                    fi
                    load_env
                    install_server
                    install_web
                    ;;
                "--profile")
                    local profile="${3:-standard}"
                    if [[ ! -f .env ]]; then
                        create_profile "$profile"
                    fi
                    load_env
                    install_server
                    if [[ "${SERVERSH_WEB_UI_ENABLE:-false}" == "true" ]]; then
                        install_web
                    fi
                    ;;
                "")
                    log_info "Interactive installation"
                    echo ""
                    echo "Choose installation type:"
                    echo "1) Standard installation (recommended)"
                    echo "2) Web UI only"
                    echo "3) CLI + Web UI"
                    echo ""
                    read -p "Enter choice [1-3]: " choice

                    case "$choice" in
                        1)
                            if [[ ! -f .env ]]; then
                                create_profile "standard"
                            fi
                            load_env
                            install_server
                            if [[ "${SERVERSH_WEB_UI_ENABLE:-false}" == "true" ]]; then
                                install_web
                            fi
                            ;;
                        2)
                            install_web
                            ;;
                        3)
                            if [[ ! -f .env ]]; then
                                create_profile "standard"
                            fi
                            load_env
                            install_server
                            install_web
                            ;;
                        *)
                            log_error "Invalid choice"
                            exit 1
                            ;;
                    esac
                    ;;
                *)
                    log_error "Unknown option: $2"
                    show_help
                    exit 1
                    ;;
            esac

            show_status
            show_completion_message
            ;;
        "create-profile")
            create_profile "$2"
            ;;
        "list-profiles")
            list_profiles
            ;;
        "show-profile")
            show_profile "$2"
            ;;
        "web")
            manage_web "${2:-status}"
            ;;
        "status")
            show_status
            ;;
        "update")
            check_root
            log_step "Updating ServerSH..."
            if [[ -f .env ]]; then
                install_server
            else
                log_error "Configuration file not found: .env"
            fi
            ;;
        "config")
            manage_config "$2"
            ;;
        "diagnose")
            run_diagnosis
            ;;
        "module")
            case "${2:-}" in
                "list")
                    list_modules
                    ;;
                *)
                    manage_module "${2:-}" "${3:-}"
                    ;;
            esac
            ;;
        "ssh")
            case "${2:-}" in
                "keys")
                    manage_ssh_keys "${3:-generate}"
                    ;;
                "config")
                    manage_ssh_keys "config"
                    ;;
                *)
                    log_error "Unknown SSH command: $2"
                    echo "Available: keys, config"
                    exit 1
                    ;;
            esac
            ;;
        "backup")
            manage_backup "${2:-create}" "${3:-}"
            ;;
        "logs")
            log_info "ServerSH logs (Ctrl+C to exit):"
            if [[ -d /var/log/serversh ]]; then
                tail -f /var/log/serversh/*.log
            else
                journalctl -u serversh -f
            fi
            ;;
        "clean")
            check_root
            clean_temp
            ;;
        "version")
            show_version
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Show completion message
show_completion_message() {
    echo ""
    echo "=============================================================================="
    echo "🎉 ServerSH Installation Completed Successfully!"
    echo "=============================================================================="
    echo ""

    if [[ "${SERVERSH_WEB_UI_ENABLE:-false}" == "true" ]]; then
        show_web_info
    fi

    echo "📋 Next Steps:"
    echo "1. Configure your system through Web UI or CLI"
    echo "2. Install your applications using Docker"
    echo "3. Set up backups and monitoring"
    echo "4. Configure firewall and security settings"
    echo ""

    echo "🔧 Management Commands:"
    echo "  $0 status              # Check system status"
    echo "  $0 config              # Configuration management"
    echo "  $0 module list         # List available modules"
    echo "  $0 web status          # Web UI status"
    echo "  $0 backup create       # Create backup"
    echo "  $0 ssh keys generate    # Generate SSH keys"
    echo ""

    echo "📚 Documentation: https://github.com/sunsideofthedark-lgtm/Serversh"
    echo "=============================================================================="
}

# Execute main function with all arguments
main "$@"