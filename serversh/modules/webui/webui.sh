#!/bin/bash

# =============================================================================
# ServerSH Web UI Module
# =============================================================================
# Web-based management interface for ServerSH

set -euo pipefail

# Source required utilities
source "${SERVERSH_ROOT}/core/utils.sh"
source "${SERVERSH_ROOT}/core/logger.sh"
source "${SERVERSH_ROOT}/core/state.sh"

# Module metadata
MODULE_NAME="webui/webui"
MODULE_VERSION="1.0.0"
MODULE_DESCRIPTION="Web-based management interface for ServerSH"
MODULE_DEPENDENCIES=("system/update")

# Configuration
WEB_UI_PORT="${SERVERSH_WEB_UI_PORT:-8080}"
WEB_UI_HOST="${SERVERSH_WEB_UI_HOST:-0.0.0.0}"
WEB_UI_SSL="${SERVERSH_WEB_UI_SSL:-false}"
WEB_UI_USER="${SERVERSH_WEB_UI_USER:-serversh}"
WEB_UI_SYSTEMD_SERVICE="${SERVERSH_WEB_UI_SYSTEMD_SERVICE:-true}"

validate() {
    log_info "Validating Web UI configuration"

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "Web UI installation requires root privileges"
        return 1
    fi

    # Validate port
    if ! [[ "$WEB_UI_PORT" =~ ^[0-9]+$ ]] || [[ "$WEB_UI_PORT" -lt 1 ]] || [[ "$WEB_UI_PORT" -gt 65535 ]]; then
        log_error "Invalid Web UI port: $WEB_UI_PORT (must be 1-65535)"
        return 1
    fi

    # Check if port is available
    if check_port "$WEB_UI_PORT"; then
        log_error "Port $WEB_UI_PORT is already in use"
        return 1
    fi

    # Check Python dependencies
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python 3 is required for Web UI"
        return 1
    fi

    # Check Flask
    if ! python3 -c "import flask" 2>/dev/null; then
        log_error "Flask is required for Web UI. Install with: pip3 install flask flask-cors werkzeug"
        return 1
    fi

    log_success "Web UI configuration validation completed"
    return 0
}

install() {
    log_info "Installing ServerSH Web UI"

    # Run web setup script
    local web_setup_script="${SERVERSH_ROOT}/serversh/scripts/web-setup.sh"

    if [[ -f "$web_setup_script" ]]; then
        log_info "Running Web UI setup script..."
        if "$web_setup_script" install; then
            log_success "Web UI setup completed"
        else
            log_error "Web UI setup failed"
            return 1
        fi
    else
        log_error "Web setup script not found: $web_setup_script"
        return 1
    fi

    # Save state
    save_state "${MODULE_NAME}" "installed" "port=$WEB_UI_PORT"

    log_success "Web UI installation completed"
    return 0
}

uninstall() {
    log_info "Uninstalling ServerSH Web UI"

    # Run web setup script with uninstall
    local web_setup_script="${SERVERSH_ROOT}/serversh/scripts/web-setup.sh"

    if [[ -f "$web_setup_script" ]]; then
        log_info "Running Web UI uninstall script..."
        if "$web_setup_script" uninstall; then
            log_success "Web UI uninstall completed"
        else
            log_error "Web UI uninstall failed"
            return 1
        fi
    else
        log_warning "Web setup script not found, manual cleanup may be required"
    fi

    # Save state
    save_state "${MODULE_NAME}" "uninstalled"

    log_success "Web UI uninstallation completed"
    return 0
}

status() {
    log_info "Checking Web UI status"

    if systemctl is-active --quiet serversh-web; then
        log_success "Web UI service is running"

        # Show access information
        local server_ip
        server_ip=$(hostname -I | awk '{print $1}')

        if [[ "$WEB_UI_SSL" == "true" ]]; then
            log_info "Access Web UI at: https://$server_ip:$WEB_UI_PORT"
        else
            log_info "Access Web UI at: http://$server_ip:$WEB_UI_PORT"
        fi

        return 0
    else
        log_warning "Web UI service is not running"
        return 1
    fi
}

# Module interface
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