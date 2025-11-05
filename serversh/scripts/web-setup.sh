#!/bin/bash

# =============================================================================
# ServerSH Web UI Setup Script
# =============================================================================
# Sets up the Web UI interface for ServerSH management

set -euo pipefail

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Configuration
WEB_UI_PORT="${SERVERSH_WEB_UI_PORT:-8080}"
WEB_UI_HOST="${SERVERSH_WEB_UI_HOST:-0.0.0.0}"
WEB_UI_SSL="${SERVERSH_WEB_UI_SSL:-false}"
WEB_UI_USER="${SERVERSH_WEB_UI_USER:-serversh}"
WEB_UI_SYSTEMD_SERVICE="${SERVERSH_WEB_UI_SYSTEMD_SERVICE:-true}"

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
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

# Install Python dependencies
install_python_dependencies() {
    log_info "Installing Python dependencies..."

    local pkg_manager
    pkg_manager=$(detect_package_manager)

    case "$pkg_manager" in
        "apt")
            apt update
            apt install -y python3 python3-pip python3-venv
            ;;
        "dnf"|"yum")
            "$pkg_manager" install -y python3 python3-pip
            ;;
        "pacman")
            pacman -S --noconfirm python python-pip
            ;;
        "zypper")
            zypper install -y python3 python3-pip
            ;;
        *)
            log_error "Unsupported package manager: $pkg_manager"
            return 1
            ;;
    esac

    # Install Python packages
    pip3 install flask flask-cors werkzeug --break-system-packages
}

# Create web UI user
create_web_user() {
    log_info "Creating web UI user: $WEB_UI_USER"

    if ! id "$WEB_UI_USER" &>/dev/null; then
        useradd -r -s /bin/false -d /opt/serversh "$WEB_UI_USER"
        log_success "Created user: $WEB_UI_USER"
    else
        log_info "User $WEB_UI_USER already exists"
    fi
}

# Setup directories and permissions
setup_directories() {
    log_info "Setting up directories and permissions..."

    # Create necessary directories
    mkdir -p /opt/serversh/serversh/web/{templates,static/{css,js,images}}
    mkdir -p /var/log/serversh
    mkdir -p /etc/serversh

    # Set ownership
    chown -R root:root /opt/serversh
    chown -R "$WEB_UI_USER:$WEB_UI_USER" /var/log/serversh

    # Set permissions
    chmod 755 /opt/serversh
    chmod 755 /opt/serversh/serversh
    chmod 755 /opt/serversh/serversh/web
    chmod 755 /opt/serversh/serversh/web/server.py
    chmod 755 /var/log/serversh

    log_success "Directory structure created"
}

# Create systemd service
create_systemd_service() {
    if [[ "$WEB_UI_SYSTEMD_SERVICE" != "true" ]]; then
        log_info "Skipping systemd service creation"
        return 0
    fi

    log_info "Creating systemd service..."

    cat > /etc/systemd/system/serversh-web.service << EOF
[Unit]
Description=ServerSH Web UI
After=network.target
Wants=network.target

[Service]
Type=simple
User=$WEB_UI_USER
Group=$WEB_UI_USER
WorkingDirectory=/opt/serversh
Environment=PYTHONPATH=/opt/serversh
Environment=FLASK_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
Environment=SERVERSH_ROOT=/opt/serversh
Environment=SERVERSH_CONFIG_DIR=/etc/serversh
Environment=SERVERSH_ENV_FILE=/opt/serversh/.env
ExecStart=/usr/bin/python3 /opt/serversh/serversh/web/server.py
Restart=always
RestartSec=10

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=serversh-web

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/serversh /etc/serversh /opt/serversh

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable serversh-web

    log_success "Systemd service created and enabled"
}

# Create nginx configuration (optional)
create_nginx_config() {
    if command -v nginx >/dev/null 2>&1; then
        log_info "Creating nginx configuration..."

        cat > /etc/nginx/sites-available/serversh-web << EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:$WEB_UI_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Optional: Serve static files directly
    location /static/ {
        alias /opt/serversh/serversh/web/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

        # Enable site if not already enabled
        if [[ ! -L /etc/nginx/sites-enabled/serversh-web ]]; then
            ln -sf /etc/nginx/sites-available/serversh-web /etc/nginx/sites-enabled/
            nginx -t && systemctl reload nginx
            log_success "Nginx configuration created"
        fi
    else
        log_info "Nginx not found, skipping reverse proxy configuration"
    fi
}

# Create SSL configuration (optional)
create_ssl_config() {
    if [[ "$WEB_UI_SSL" == "true" ]]; then
        log_info "Setting up SSL configuration..."

        # Create self-signed certificate if no certificate exists
        if [[ ! -f /etc/ssl/certs/serversh-web.crt ]]; then
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /etc/ssl/private/serversh-web.key \
                -out /etc/ssl/certs/serversh-web.crt \
                -subj "/C=US/ST=State/L=City/O=Organization/CN=$(hostname)"

            log_success "Self-signed SSL certificate created"
        fi

        # Update systemd service for HTTPS
        sed -i 's|ExecStart=/usr/bin/python3 /opt/serversh/serversh/web/server.py|ExecStart=/usr/bin/python3 /opt/serversh/serversh/web/server.py --ssl|' /etc/systemd/system/serversh-web.service
        systemctl daemon-reload

        log_info "SSL configuration completed"
    fi
}

# Create startup script
create_startup_script() {
    log_info "Creating startup script..."

    cat > /usr/local/bin/serversh-web << 'EOF'
#!/bin/bash

# ServerSH Web UI Management Script

SCRIPT_DIR="/opt/serversh/serversh/web"
PYTHON_PATH="/usr/bin/python3"

case "${1:-status}" in
    "start")
        echo "Starting ServerSH Web UI..."
        systemctl start serversh-web
        ;;
    "stop")
        echo "Stopping ServerSH Web UI..."
        systemctl stop serversh-web
        ;;
    "restart")
        echo "Restarting ServerSH Web UI..."
        systemctl restart serversh-web
        ;;
    "status")
        systemctl status serversh-web
        ;;
    "logs")
        journalctl -u serversh-web -f
        ;;
    "config")
        echo "Web UI Configuration:"
        echo "  Port: $WEB_UI_PORT"
        echo "  Host: $WEB_UI_HOST"
        echo "  SSL: $WEB_UI_SSL"
        echo "  User: $WEB_UI_USER"
        ;;
    "help")
        echo "Usage: serversh-web {start|stop|restart|status|logs|config|help}"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use 'serversh-web help' for usage information"
        exit 1
        ;;
esac
EOF

    chmod +x /usr/local/bin/serversh-web
    log_success "Startup script created: /usr/local/bin/serversh-web"
}

# Start the web service
start_web_service() {
    log_info "Starting ServerSH Web UI service..."

    systemctl start serversh-web

    # Wait a moment for service to start
    sleep 3

    if systemctl is-active --quiet serversh-web; then
        log_success "ServerSH Web UI service started successfully"
    else
        log_error "Failed to start ServerSH Web UI service"
        systemctl status serversh-web
        return 1
    fi
}

# Display access information
show_access_info() {
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')

    echo ""
    echo "=============================================================================="
    echo "ServerSH Web UI Setup Completed!"
    echo "=============================================================================="
    echo ""

    if [[ "$WEB_UI_SSL" == "true" ]]; then
        echo "🔒 Secure Web UI: https://$server_ip:$WEB_UI_PORT"
    else
        echo "🌐 Web UI: http://$server_ip:$WEB_UI_PORT"
    fi

    echo "📝 Local access: http://localhost:$WEB_UI_PORT"
    echo "👤 Login: Use your root credentials"
    echo ""

    echo "Management Commands:"
    echo "  serversh-web start    # Start the web service"
    echo "  serversh-web stop     # Stop the web service"
    echo "  serversh-web status   # Check service status"
    echo "  serversh-web logs     # View service logs"
    echo "  serversh-web config   # Show configuration"
    echo ""

    echo "Service Management:"
    echo "  systemctl status serversh-web    # Check systemd status"
    echo "  journalctl -u serversh-web -f    # View real-time logs"
    echo ""

    if command -v nginx >/dev/null 2>&1; then
        echo "🌐 Nginx reverse proxy is configured"
        echo "   Access via: http://$server_ip (port 80)"
        echo ""
    fi

    echo "⚠️  Security Notes:"
    echo "   - Only root login is allowed for security"
    echo "   - Consider setting up a reverse proxy with SSL"
    echo "   - Monitor logs for any suspicious activity"
    echo ""

    echo "📚 Documentation: https://github.com/sunsideofthedark-lgtm/Serversh"
    echo "=============================================================================="
}

# Validate installation
validate_installation() {
    log_info "Validating installation..."

    local errors=()

    # Check if web server file exists
    if [[ ! -f /opt/serversh/serversh/web/server.py ]]; then
        errors+=("Web server file not found")
    fi

    # Check if Python dependencies are installed
    if ! python3 -c "import flask" 2>/dev/null; then
        errors+=("Flask not installed")
    fi

    # Check if service is running
    if ! systemctl is-active --quiet serversh-web; then
        errors+=("Web service not running")
    fi

    # Check if port is accessible
    if ! netstat -tlnp 2>/dev/null | grep -q ":$WEB_UI_PORT "; then
        errors+=("Port $WEB_UI_PORT not accessible")
    fi

    if [[ ${#errors[@]} -eq 0 ]]; then
        log_success "Installation validation passed"
        return 0
    else
        log_error "Installation validation failed:"
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi
}

# Uninstall function
uninstall() {
    log_info "Uninstalling ServerSH Web UI..."

    # Stop and disable service
    systemctl stop serversh-web 2>/dev/null || true
    systemctl disable serversh-web 2>/dev/null || true

    # Remove service file
    rm -f /etc/systemd/system/serversh-web.service
    systemctl daemon-reload

    # Remove nginx configuration
    rm -f /etc/nginx/sites-available/serversh-web
    rm -f /etc/nginx/sites-enabled/serversh-web
    systemctl reload nginx 2>/dev/null || true

    # Remove startup script
    rm -f /usr/local/bin/serversh-web

    # Remove SSL certificates
    rm -f /etc/ssl/certs/serversh-web.crt
    rm -f /etc/ssl/private/serversh-web.key

    # Note: We don't remove the web files or user for safety

    log_success "ServerSH Web UI uninstalled"
}

# Main function
main() {
    echo "=============================================================================="
    echo "ServerSH Web UI Setup Script"
    echo "=============================================================================="
    echo ""

    # Parse command line arguments
    case "${1:-install}" in
        "install")
            check_root
            detect_os
            detect_package_manager

            log_info "Starting ServerSH Web UI installation..."

            install_python_dependencies
            create_web_user
            setup_directories
            create_systemd_service
            create_nginx_config
            create_ssl_config
            create_startup_script
            start_web_service

            if validate_installation; then
                show_access_info
                log_success "ServerSH Web UI installation completed successfully!"
            else
                log_error "Installation validation failed"
                exit 1
            fi
            ;;
        "uninstall")
            check_root
            uninstall
            ;;
        "status")
            if systemctl is-active --quiet serversh-web; then
                log_success "ServerSH Web UI is running"
                show_access_info
            else
                log_warning "ServerSH Web UI is not running"
            fi
            ;;
        "start")
            check_root
            systemctl start serversh-web
            log_success "ServerSH Web UI started"
            ;;
        "stop")
            check_root
            systemctl stop serversh-web
            log_success "ServerSH Web UI stopped"
            ;;
        "restart")
            check_root
            systemctl restart serversh-web
            log_success "ServerSH Web UI restarted"
            ;;
        "logs")
            journalctl -u serversh-web -f
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 {install|uninstall|status|start|stop|restart|logs|help}"
            echo ""
            echo "Commands:"
            echo "  install   Install ServerSH Web UI (default)"
            echo "  uninstall Uninstall ServerSH Web UI"
            echo "  status    Show service status"
            echo "  start     Start the web service"
            echo "  stop      Stop the web service"
            echo "  restart   Restart the web service"
            echo "  logs      Show service logs"
            echo "  help      Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  SERVERSH_WEB_UI_PORT       Web UI port (default: 8080)"
            echo "  SERVERSH_WEB_UI_HOST       Web UI host (default: 0.0.0.0)"
            echo "  SERVERSH_WEB_UI_SSL        Enable SSL (default: false)"
            echo "  SERVERSH_WEB_UI_USER       Service user (default: serversh)"
            echo "  SERVERSH_WEB_UI_SYSTEMD_SERVICE Create systemd service (default: true)"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"