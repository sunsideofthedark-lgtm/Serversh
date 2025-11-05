#!/bin/bash

# =============================================================================
# ServerSH All-in-One Deployment Script
# =============================================================================
# Complete server management with a single script and configuration file

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
    echo -e "${PURPLE}Version $SCRIPT_VERSION • One-Click Server Deployment${NC}"
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
ServerSH All-in-One Deployment Script

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    install           Install ServerSH with Web UI (interactive)
    install-web       Install only Web UI
    install-cli       Install only CLI components
    deploy            Deploy with existing configuration
    update            Update existing installation
    status            Show system status
    uninstall         Uninstall ServerSH
    web               Manage Web UI service
    config            Configuration management

OPTIONS:
    --env FILE         Use custom environment file (default: .env)
    --mode MODE        Deployment mode: interactive|auto|web|cli (default: interactive)
    --profile PROFILE  Configuration profile: minimal|standard|full (default: standard)
    --web-port PORT    Web UI port (default: 8080)
    --dry-run          Show what would be done without executing
    --verbose          Enable verbose output
    --help             Show this help message

EXAMPLES:
    # Interactive installation with Web UI
    $0 install

    # Automated installation with custom config
    $0 install --mode=auto --env=my-config.env

    # Web UI only installation
    $0 install-web --web-port=9000

    # CLI only installation
    $0 install-cli

    # Deploy with existing configuration
    $0 deploy --env=production.env

    # Check system status
    $0 status

CONFIGURATION PROFILES:
    minimal   - Basic system setup + SSH + Docker
    standard  - Full production setup with monitoring
    full      - Complete setup with all features enabled

ENVIRONMENT FILE:
    Copy .env.example to .env and customize settings.
    All configuration is done through environment variables.

WEB UI:
    After installation, access the Web UI at:
    http://your-server-ip:8080
    Login with your root credentials

For more information, see the documentation at:
https://github.com/sunsideofthedark-lgtm/Serversh
EOF
}

# Parse command line arguments
parse_arguments() {
    MODE="interactive"
    ENV_FILE=".env"
    PROFILE="standard"
    WEB_PORT="8080"
    DRY_RUN=false
    VERBOSE=false
    COMMAND="install"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                MODE="$2"
                shift 2
                ;;
            --env)
                ENV_FILE="$2"
                shift 2
                ;;
            --profile)
                PROFILE="$2"
                shift 2
                ;;
            --web-port)
                WEB_PORT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            install|install-web|install-cli|deploy|update|status|uninstall|web|config)
                COMMAND="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    export SERVERSH_DEPLOY_MODE="$MODE"
    export SERVERSH_DEPLOY_PROFILE="$PROFILE"
    export SERVERSH_WEB_UI_PORT="$WEB_PORT"
    export SERVERSH_ENV_FILE="$ENV_FILE"
    export SERVERSH_DRY_RUN="$DRY_RUN"
    export SERVERSH_VERBOSE="$VERBOSE"
}

# Check system requirements
check_requirements() {
    log_step "Checking system requirements..."

    local errors=()

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        errors+=("This script must be run as root")
    fi

    # Check operating system
    if [[ ! -f /etc/os-release ]]; then
        errors+=("Unsupported operating system (no /etc/os-release found)")
    fi

    # Check package manager
    local pkg_manager
    if command -v apt >/dev/null 2>&1; then
        pkg_manager="apt"
    elif command -v dnf >/dev/null 2>&1; then
        pkg_manager="dnf"
    elif command -v yum >/dev/null 2>&1; then
        pkg_manager="yum"
    elif command -v pacman >/dev/null 2>&1; then
        pkg_manager="pacman"
    elif command -v zypper >/dev/null 2>&1; then
        pkg_manager="zypper"
    else
        errors+=("No supported package manager found")
    fi

    # Check internet connectivity
    if ! ping -c 1 google.com >/dev/null 2>&1; then
        errors+=("Internet connectivity required")
    fi

    # Check disk space
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ "$available_space" -lt 2097152 ]]; then  # 2GB in KB
        errors+=("Insufficient disk space (need at least 2GB available)")
    fi

    # Check memory
    local available_memory
    available_memory=$(free | awk 'NR==2{printf "%.0f", $7}')
    if [[ "$available_memory" -lt 1048576 ]]; then  # 1GB in KB
        errors+=("Insufficient memory (need at least 1GB available)")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "System requirements check failed:"
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi

    log_success "System requirements check passed"
    return 0
}

# Create configuration profile
create_profile_config() {
    local profile="$1"
    local env_file="$2"

    log_step "Creating $profile configuration profile..."

    case "$profile" in
        "minimal")
            cat > "$env_file" << 'EOF'
# ServerSH Minimal Configuration
SERVERSH_HOSTNAME=minimal-server
SERVERSH_USERNAME=admin
SERVERSH_USER_PASSWORD=MinimalPass123!
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_DOCKER_ENABLE=true
SERVERSH_PROMETHEUS_ENABLE=false
SERVERSH_BACKUP_ENABLE=false
SERVERSH_WEB_UI_ENABLE=true
SERVERSH_INSTALL_TAILSCALE=false
EOF
            ;;
        "standard")
            cat > "$env_file" << 'EOF'
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
            cat > "$env_file" << 'EOF'
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
            return 1
            ;;
    esac

    # Add deployment-specific settings
    cat >> "$env_file" << EOF

# Deployment Settings (auto-generated)
SERVERSH_DEPLOY_MODE=$MODE
SERVERSH_DEPLOY_PROFILE=$PROFILE
SERVERSH_WEB_UI_PORT=$WEB_PORT
SERVERSH_ENV_FILE=$ENV_FILE
SERVERSH_INSTALLATION_DATE=$(date -Iseconds)
SERVERSH_VERSION=$SCRIPT_VERSION
EOF

    log_success "Configuration profile created: $env_file"
    return 0
}

# Interactive configuration setup
interactive_setup() {
    log_step "Interactive configuration setup..."

    # Ask for configuration method
    echo ""
    echo "Choose configuration method:"
    echo "1) Use standard profile (recommended)"
    echo "2) Use minimal profile"
    echo "3) Use full profile"
    echo "4) Custom configuration"
    echo ""

    while true; do
        read -p "Enter choice [1-4]: " choice
        case $choice in
            1)
                PROFILE="standard"
                break
                ;;
            2)
                PROFILE="minimal"
                break
                ;;
            3)
                PROFILE="full"
                break
                ;;
            4)
                log_info "Custom configuration selected. Please edit .env file after installation."
                PROFILE="standard"
                break
                ;;
            *)
                echo "Invalid choice. Please enter 1, 2, 3, or 4."
                ;;
        esac
    done

    # Ask for basic settings
    echo ""
    read -p "Server hostname [$PROFILE-server]: " hostname
    SERVERSH_HOSTNAME="${hostname:-$PROFILE-server}"

    echo ""
    read -p "Admin username [admin]: " username
    SERVERSH_USERNAME="${username:-admin}"

    echo ""
    read -s -p "Admin password: " password
    echo ""
    if [[ -z "$password" ]]; then
        password="SecurePassword123!"
        log_warning "Using default password: $password"
    fi
    SERVERSH_USER_PASSWORD="$password"

    # Create configuration file
    if ! create_profile_config "$PROFILE" "$ENV_FILE"; then
        return 1
    fi

    # Update hostname and password
    sed -i "s/SERVERSH_HOSTNAME=.*/SERVERSH_HOSTNAME=$SERVERSH_HOSTNAME/" "$ENV_FILE"
    sed -i "s/SERVERSH_USERNAME=.*/SERVERSH_USERNAME=$SERVERSH_USERNAME/" "$ENV_FILE"
    sed -i "s/SERVERSH_USER_PASSWORD=.*/SERVERSH_USER_PASSWORD=$SERVERSH_USER_PASSWORD/" "$ENV_FILE"

    # Ask about Web UI
    echo ""
    read -p "Enable Web UI? [Y/n]: " enable_web
    if [[ "$enable_web" =~ ^[Nn]$ ]]; then
        sed -i 's/SERVERSH_WEB_UI_ENABLE=.*/SERVERSH_WEB_UI_ENABLE=false/' "$ENV_FILE"
    fi

    echo ""
    read -p "Web UI port [$WEB_PORT]: " web_port
    if [[ -n "$web_port" ]]; then
        WEB_PORT="$web_port"
        sed -i "s/SERVERSH_WEB_UI_PORT=.*/SERVERSH_WEB_UI_PORT=$WEB_PORT/" "$ENV_FILE"
    fi

    log_success "Interactive configuration completed"
    return 0
}

# Execute ServerSH installation
execute_installation() {
    log_step "Executing ServerSH installation..."

    local install_script="${PROJECT_DIR}/serversh/scripts/install-from-env.sh"

    if [[ ! -f "$install_script" ]]; then
        log_error "Installation script not found: $install_script"
        return 1
    fi

    # Set environment variables
    export SERVERSH_ENV_FILE="$ENV_FILE"
    export SERVERSH_WEB_UI_PORT="$WEB_PORT"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would execute: $install_script"
        log_info "Configuration file: $ENV_FILE"
        return 0
    fi

    # Execute installation
    if "$install_script"; then
        log_success "ServerSH installation completed successfully"
        return 0
    else
        log_error "ServerSH installation failed"
        return 1
    fi
}

# Install Web UI only
install_web_ui_only() {
    log_step "Installing Web UI only..."

    local web_setup_script="${PROJECT_DIR}/serversh/scripts/web-setup.sh"

    if [[ ! -f "$web_setup_script" ]]; then
        log_error "Web setup script not found: $web_setup_script"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would execute: $web_setup_script install"
        return 0
    fi

    # Execute Web UI installation
    if "$web_setup_script" install; then
        log_success "Web UI installation completed successfully"
        return 0
    else
        log_error "Web UI installation failed"
        return 1
    fi
}

# Show system status
show_status() {
    log_step "Checking system status..."

    echo ""
    echo "ServerSH System Status"
    echo "======================="
    echo ""

    # Check if ServerSH is installed
    if [[ -f "${PROJECT_DIR}/serversh/scripts/status.sh" ]]; then
        if "${PROJECT_DIR}/serversh/scripts/status.sh"; then
            log_success "ServerSH is properly installed"
        else
            log_warning "ServerSH installation may have issues"
        fi
    else
        log_error "ServerSH is not installed"
    fi

    echo ""

    # Check Web UI
    if systemctl is-active --quiet serversh-web 2>/dev/null; then
        local server_ip
        server_ip=$(hostname -I | awk '{print $1}')
        log_success "Web UI is running"
        echo "  Access URL: http://$server_ip:$WEB_PORT"
        echo "  Local access: http://localhost:$WEB_PORT"
    else
        log_warning "Web UI is not running"
    fi

    echo ""

    # Check services
    local services=("ssh" "docker" "prometheus-node-exporter")
    echo "Service Status:"
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "  ✅ $service: running"
        else
            echo "  ❌ $service: not running"
        fi
    done

    echo ""
}

# Main deployment function
deploy() {
    show_banner

    case "$COMMAND" in
        "install")
            log_step "Starting ServerSH installation..."

            if ! check_requirements; then
                exit 1
            fi

            if [[ "$MODE" == "interactive" ]]; then
                if ! interactive_setup; then
                    exit 1
                fi
            else
                if [[ ! -f "$ENV_FILE" ]]; then
                    if ! create_profile_config "$PROFILE" "$ENV_FILE"; then
                        exit 1
                    fi
                fi
            fi

            if ! execute_installation; then
                exit 1
            fi

            # Show access information
            show_status
            show_completion_message
            ;;
        "install-web")
            show_banner
            log_step "Installing Web UI only..."

            if ! check_requirements; then
                exit 1
            fi

            if ! install_web_ui_only; then
                exit 1
            fi

            show_web_completion_message
            ;;
        "install-cli")
            show_banner
            log_step "Installing CLI components only..."

            export SERVERSH_WEB_UI_ENABLE=false

            if ! check_requirements; then
                exit 1
            fi

            if [[ ! -f "$ENV_FILE" ]]; then
                if ! create_profile_config "$PROFILE" "$ENV_FILE"; then
                    exit 1
                fi
            fi

            sed -i 's/SERVERSH_WEB_UI_ENABLE=.*/SERVERSH_WEB_UI_ENABLE=false/' "$ENV_FILE"

            if ! execute_installation; then
                exit 1
            fi

            show_cli_completion_message
            ;;
        "deploy")
            show_banner
            log_step "Deploying with existing configuration..."

            if [[ ! -f "$ENV_FILE" ]]; then
                log_error "Configuration file not found: $ENV_FILE"
                exit 1
            fi

            if ! execute_installation; then
                exit 1
            fi

            show_status
            ;;
        "update")
            show_banner
            log_step "Updating ServerSH installation..."

            if [[ ! -f "$ENV_FILE" ]]; then
                log_error "Configuration file not found: $ENV_FILE"
                exit 1
            fi

            if ! execute_installation; then
                exit 1
            fi

            log_success "Update completed successfully"
            ;;
        "status")
            show_status
            ;;
        "uninstall")
            show_banner
            log_step "Uninstalling ServerSH..."

            read -p "Are you sure you want to uninstall ServerSH? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                "${PROJECT_DIR}/serversh/scripts/web-setup.sh" uninstall 2>/dev/null || true
                log_warning "Manual cleanup may be required"
                log_success "Uninstallation completed"
            else
                log_info "Uninstallation cancelled"
            fi
            ;;
        "web")
            show_banner
            log_step "Managing Web UI service..."

            if [[ $# -gt 1 ]]; then
                case "$2" in
                    "start"|"stop"|"restart"|"status"|"logs")
                        "${PROJECT_DIR}/serversh/scripts/web-setup.sh" "$2"
                        ;;
                    *)
                        log_error "Unknown web command: $2"
                        echo "Available commands: start, stop, restart, status, logs"
                        exit 1
                        ;;
                esac
            else
                show_status
            fi
            ;;
        "config")
            show_banner
            log_step "Configuration management..."

            if [[ -f "$ENV_FILE" ]]; then
                echo "Configuration file: $ENV_FILE"
                echo "Configuration size: $(wc -l < "$ENV_FILE") lines"
                echo ""
                echo "Quick edit commands:"
                echo "  nano $ENV_FILE"
                echo "  vim $ENV_FILE"
                echo ""
            else
                log_error "Configuration file not found: $ENV_FILE"
                echo "Create one with: $0 install"
            fi
            ;;
        *)
            log_error "Unknown command: $COMMAND"
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

    if [[ "$SERVERSH_WEB_UI_ENABLE" == "true" ]]; then
        local server_ip
        server_ip=$(hostname -I | awk '{print $1}')
        echo "🌐 Web UI Access:"
        echo "   http://$server_ip:$WEB_PORT"
        echo "   http://localhost:$WEB_PORT"
        echo "   Login with your root credentials"
        echo ""
    fi

    echo "📋 Next Steps:"
    echo "1. Configure your system through the Web UI or CLI"
    echo "2. Install your applications using Docker"
    echo "3. Set up backups and monitoring"
    echo "4. Configure firewall and security settings"
    echo ""

    echo "🔧 Management Commands:"
    echo "   $0 status              # Check system status"
    echo "   $0 web status          # Web UI status"
    echo "   $0 config              # Configuration management"
    echo ""

    echo "📚 Documentation: https://github.com/sunsideofthedark-lgtm/Serversh"
    echo "=============================================================================="
}

# Show Web UI completion message
show_web_completion_message() {
    echo ""
    echo "=============================================================================="
    echo "🌐 Web UI Installation Completed!"
    echo "=============================================================================="
    echo ""

    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')

    echo "🌐 Access Web UI at:"
    echo "   http://$server_ip:$WEB_PORT"
    echo "   http://localhost:$WEB_PORT"
    echo ""

    echo "👤 Login with your root credentials"
    echo ""

    echo "🔧 Management Commands:"
    echo "   $0 web status          # Check Web UI status"
    echo "   $0 web logs            # View Web UI logs"
    echo "   $0 web restart         # Restart Web UI service"
    echo ""

    echo "📚 Complete ServerSH setup: $0 install"
    echo "=============================================================================="
}

# Show CLI completion message
show_cli_completion_message() {
    echo ""
    echo "=============================================================================="
    echo "💻 CLI Components Installation Completed!"
    echo "=============================================================================="
    echo ""

    echo "📋 Next Steps:"
    echo "1. Configure your system using environment variables"
    echo "2. Install additional modules as needed"
    echo "3. Set up monitoring and backups"
    echo ""

    echo "🔧 Management Commands:"
    echo "   $0 status              # Check system status"
    echo "   $0 config              # Configuration management"
    echo ""

    echo "🌐 Add Web UI: $0 install-web"
    echo "📚 Documentation: https://github.com/sunsideofthedark-lgtm/Serversh"
    echo "=============================================================================="
}

# Main execution
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Execute deployment
    deploy
}

# Execute main function with all arguments
main "$@"