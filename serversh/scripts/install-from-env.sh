#!/bin/bash

# =============================================================================
# ServerSH Environment-Based Installation Script
# =============================================================================
# Liest Konfiguration aus .env Datei und führt vollautomatische Installation durch

set -euo pipefail

# Script-Verzeichnis ermitteln
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Farben für Ausgaben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging-Funktionen
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

# Hilfsfunktionen
check_dependencies() {
    log_info "Prüfe Abhängigkeiten..."

    local missing_deps=()

    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi

    if ! command -v yq >/dev/null 2>&1; then
        missing_deps+=("yq")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Fehlende Abhängigkeiten: ${missing_deps[*]}"
        log_info "Installieren Sie die fehlenden Pakete:"
        log_info "Ubuntu/Debian: sudo apt-get install jq yq"
        log_info "CentOS/RHEL: sudo yum install jq yq"
        exit 1
    fi
}

load_env_file() {
    local env_file="${1:-.env}"

    if [[ ! -f "$env_file" ]]; then
        log_error "Umgebungsdatei nicht gefunden: $env_file"
        log_info "Kopieren Sie .env.example nach .env und passen Sie die Konfiguration an"
        exit 1
    fi

    log_info "Lade Umgebungsvariablen aus: $env_file"

    # Lade die .env Datei
    set -a
    source "$env_file"
    set +a

    log_success "Umgebungsvariablen geladen"
}

validate_config() {
    log_info "Validiere Konfiguration..."

    local errors=()

    # Prüfe erforderliche Variablen
    local required_vars=(
        "SERVERSH_HOSTNAME"
        "SERVERSH_USERNAME"
        "SERVERSH_USER_PASSWORD"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            errors+=("$var ist nicht gesetzt")
        fi
    fi

    # Prüfe Port-Nummern
    local port_vars=(
        "SERVERSH_SSH_PORT"
        "SERVERSH_PROMETHEUS_PORT"
        "SERVERSH_NODE_EXPORTER_PORT"
    )

    for var in "${port_vars[@]}"; do
        if [[ -n "${!var:-}" ]] && ! [[ "${!var}" =~ ^[0-9]+$ ]]; then
            errors+=("$var muss eine gültige Port-Nummer sein")
        fi
    done

    # Prüfe Passwort-Stärke
    if [[ -n "${SERVERSH_USER_PASSWORD:-}" ]] && [[ ${#SERVERSH_USER_PASSWORD} -lt 8 ]]; then
        errors+=("SERVERSH_USER_PASSWORD muss mindestens 8 Zeichen lang sein")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Konfigurationsfehler gefunden:"
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        exit 1
    fi

    log_success "Konfiguration validiert"
}

create_module_configs() {
    log_info "Erstelle Modul-Konfigurationen..."

    local config_dir="${PROJECT_DIR}/configs/generated"
    mkdir -p "$config_dir"

    # System Update Konfiguration
    if [[ "${SERVERSH_UPDATE_AUTO:-true}" == "true" ]]; then
        cat > "$config_dir/system_update.yaml" << EOF
system/update:
  auto_update: ${SERVERSH_UPDATE_AUTO:-true}
  security_only: ${SERVERSH_UPDATE_SECURITY_ONLY:-false}
  cleanup: ${SERVERSH_UPDATE_CLEANUP:-true}
  reboot: false
EOF
    fi

    # Hostname Konfiguration
    cat > "$config_dir/hostname.yaml" << EOF
system/hostname:
  hostname: "${SERVERSH_HOSTNAME}"
  fqdn: "${SERVERSH_FQDN:-}"
  update_hosts: ${SERVERSH_HOSTNAME_UPDATE_HOSTS:-true}
  validate_dns: ${SERVERSH_HOSTNAME_VALIDATE_DNS:-false}
EOF

    # Benutzer Konfiguration
    if [[ "${SERVERSH_CREATE_USER:-true}" == "true" ]]; then
        cat > "$config_dir/users.yaml" << EOF
security/users:
  create_user: true
  username: "${SERVERSH_USERNAME}"
  password: "${SERVERSH_USER_PASSWORD}"
  ssh_key: ${SERVERSH_USER_SSH_KEY:-true}
  sudo: ${SERVERSH_USER_SUDO:-true}
  shell: "${SERVERSH_USER_SHELL:-/bin/bash}"
  additional_ssh_keys:
EOF

        # Füge zusätzliche SSH Keys hinzu
        if [[ -n "${SERVERSH_ADDITIONAL_SSH_KEYS:-}" ]]; then
            IFS=',' read -ra keys <<< "$SERVERSH_ADDITIONAL_SSH_KEYS"
            for key in "${keys[@]}"; do
                echo "    - \"$(echo "$key" | xargs)\"" >> "$config_dir/users.yaml"
            done
        fi
    fi

    # SSH Konfiguration
    if [[ "${SERVERSH_SSH_ENABLE:-true}" == "true" ]]; then
        cat > "$config_dir/ssh.yaml" << EOF
security/ssh_interactive:
  interactive_port: ${SERVERSH_SSH_INTERACTIVE_PORT:-true}
  preferred_port: ${SERVERSH_SSH_PREFERRED_PORT:-2222}
  auto_select_port: ${SERVERSH_SSH_AUTO_SELECT_PORT:-true}
  scan_ranges: "${SERVERSH_SSH_SCAN_RANGES:-2000-2999,4000-4999,5000-5999}"
  backup_config: ${SERVERSH_SSH_BACKUP_CONFIG:-true}
  security_settings:
    permit_root_login: "${SERVERSH_SSH_PERMIT_ROOT_LOGIN:-no}"
    password_authentication: "${SERVERSH_SSH_PASSWORD_AUTHENTICATION:-no}"
    permit_empty_passwords: "${SERVERSH_SSH_PERMIT_EMPTY_PASSWORDS:-no}"
    x11_forwarding: "${SERVERSH_SSH_X11_FORWARDING:-no}"
    client_alive_interval: ${SERVERSH_SSH_CLIENT_ALIVE_INTERVAL:-300}
    client_alive_count_max: ${SERVERSH_SSH_CLIENT_ALIVE_COUNT_MAX:-2}
    max_auth_tries: ${SERVERSH_SSH_MAX_AUTH_TRIES:-3}
    max_sessions: ${SERVERSH_SSH_MAX_SESSIONS:-10}
EOF

        # Wenn nicht interaktiv, setze Port direkt
        if [[ "${SERVERSH_SSH_INTERACTIVE_PORT:-true}" != "true" ]]; then
            cat >> "$config_dir/ssh.yaml" << EOF
  port: ${SERVERSH_SSH_PORT:-22}
EOF
        fi
    fi

    # Firewall Konfiguration
    if [[ "${SERVERSH_FIREWALL_ENABLE:-true}" == "true" ]]; then
        cat > "$config_dir/firewall.yaml" << EOF
security/firewall:
  firewall_type: "${SERVERSH_FIREWALL_TYPE:-auto}"
  enable_firewall: true
  default_policy: "${SERVERSH_FIREWALL_DEFAULT_POLICY:-deny}"
  allow_ssh: true
  ssh_port: \${SERVERSH_FINAL_SSH_PORT:-22}
  allowed_ports: "${SERVERSH_FIREWALL_ALLOWED_PORTS:-80/tcp,443/tcp}"
  log_rules: ${SERVERSH_FIREWALL_LOG_RULES:-true}
EOF
    fi

    # Docker Konfiguration
    if [[ "${SERVERSH_DOCKER_ENABLE:-true}" == "true" ]]; then
        cat > "$config_dir/docker.yaml" << EOF
container/docker:
  version: "${SERVERSH_DOCKER_VERSION:-latest}"
  install_compose: ${SERVERSH_DOCKER_INSTALL_COMPOSE:-true}
  compose_version: "${SERVERSH_DOCKER_COMPOSE_VERSION:-latest}"
  docker_user: "${SERVERSH_DOCKER_USER:-${SERVERSH_USERNAME}}"
  network_config:
    mtu: ${SERVERSH_DOCKER_NETWORK_MTU:-1450}
    ipv6: ${SERVERSH_DOCKER_NETWORK_IPV6:-true}
    name: "${SERVERSH_DOCKER_NETWORK_NAME:-newt_talk}"
    ipv6_subnet: "${SERVERSH_DOCKER_IPV6_SUBNET:-2001:db8:1::/64}"
    address_pools:
      - base: "${SERVERSH_DOCKER_IP_POOL:-172.25.0.0/16}"
        size: ${SERVERSH_DOCKER_IP_POOL_SIZE:-24}
  daemon_config:
    log-level: "${SERVERSH_DOCKER_LOG_LEVEL:-info}"
    storage-driver: "${SERVERSH_DOCKER_STORAGE_DRIVER:-overlay2}"
    experimental: ${SERVERSH_DOCKER_EXPERIMENTAL:-false}
EOF
    fi

    # Prometheus Konfiguration
    if [[ "${SERVERSH_PROMETHEUS_ENABLE:-true}" == "true" ]]; then
        cat > "$config_dir/prometheus.yaml" << EOF
monitoring/prometheus:
  prometheus_version: "${SERVERSH_PROMETHEUS_VERSION:-latest}"
  install_node_exporter: ${SERVERSH_NODE_EXPORTER_ENABLE:-true}
  node_exporter_version: "${SERVERSH_NODE_EXPORTER_VERSION:-latest}"
  prometheus_port: ${SERVERSH_PROMETHEUS_PORT:-9090}
  node_exporter_port: ${SERVERSH_NODE_EXPORTER_PORT:-9100}
  enable_service: ${SERVERSH_PROMETHEUS_ENABLE_SERVICE:-true}
  config_retention: "${SERVERSH_PROMETHEUS_RETENTION:-15d}"
  config_storage_path: "${SERVERSH_PROMETHEUS_STORAGE_PATH:-/var/lib/prometheus}"
EOF
    fi

    # Optionale Software Konfiguration
    cat > "$config_dir/optional_software.yaml" << EOF
applications/optional_software:
  install_tailscale: ${SERVERSH_INSTALL_TAILSCALE:-true}
  tailscale_login_method: "${SERVERSH_TAILSCALE_LOGIN_METHOD:-interactive}"
  tailscale_auth_key: "${SERVERSH_TAILSCALE_AUTH_KEY:-}"
  tailscale_args: "${SERVERSH_TAILSCALE_ARGS:-}"
  tailscale_ssh_user: "${SERVERSH_TAILSCALE_SSH_USER:-root}"
  tailscale_ssh_port: ${SERVERSH_TAILSCALE_SSH_PORT:-22}
  tailscale_ssh_key_path: "${SERVERSH_TAILSCALE_SSH_KEY_PATH:-/root/.ssh/tailscale}"
  tailscale_ssh_timeout: ${SERVERSH_TAILSCALE_SSH_TIMEOUT:-300}
  tailscale_ssh_interactive: ${SERVERSH_TAILSCALE_SSH_INTERACTIVE:-false}
  install_dev_tools: ${SERVERSH_INSTALL_DEV_TOOLS:-false}
  dev_packages: "${SERVERSH_DEV_PACKAGES:-build-essential,python3,python3-pip,nodejs,npm}"
  install_utilities: ${SERVERSH_INSTALL_UTILITIES:-true}
  utility_packages: "${SERVERSH_UTILITY_PACKAGES:-htop,vim,git,curl,wget,unzip,tree,ncdu,rsync,netcat-openbsd,zip,jq}"
  install_docker_extras: ${SERVERSH_INSTALL_DOCKER_EXTRAS:-false}
  docker_extras: "${SERVERSH_DOCKER_EXTRAS:-docker-compose,ctop}"
  install_monitoring_tools: ${SERVERSH_INSTALL_MONITORING_TOOLS:-false}
  monitoring_packages: "${SERVERSH_MONITORING_PACKAGES:-iotop,nethogs,sysstat,lm-sensors,atop}"
  setup_aliases: ${SERVERSH_SETUP_ALIASES:-true}
EOF

    log_success "Modul-Konfigurationen erstellt in: $config_dir"
}

run_installation() {
    log_info "Starte Installation..."

    local modules="${SERVERSH_MODULE_ORDER:-system/update,system/hostname,security/users,security/ssh,security/firewall,container/docker,monitoring/prometheus,applications/optional_software}"
    local config_dir="${PROJECT_DIR}/configs/generated"

    # Erstelle temporäre Config-Datei für den Installer
    local temp_config="${PROJECT_DIR}/temp_config.yaml"

    # Kombiniere alle Konfigurationen
    cat > "$temp_config" << EOF
# Automatisch generierte Konfiguration aus .env
# Erstellt am: $(date)

EOF

    # Füge Modul-Konfigurationen hinzu
    IFS=',' read -ra module_list <<< "$modules"
    for module in "${module_list[@]}"; do
        module=$(echo "$module" | xargs)  # trim whitespace
        local config_file="$config_dir/${module##*/}.yaml"

        if [[ -f "$config_file" ]]; then
            echo "# Konfiguration für $module" >> "$temp_config"
            cat "$config_file" >> "$temp_config"
            echo "" >> "$temp_config"
        fi
    done

    # Führe Installation aus
    local install_script="${PROJECT_DIR}/serversh/scripts/install.sh"

    if [[ ! -f "$install_script" ]]; then
        log_error "Installationsskript nicht gefunden: $install_script"
        exit 1
    fi

    log_info "Führe Installation mit folgenden Modulen aus: $modules"

    # Bereite Argumente vor
    local args=(
        "--config" "$temp_config"
        "--log-level" "${SERVERSH_LOG_LEVEL:-INFO}"
    )

    if [[ "${SERVERSH_DRY_RUN:-false}" == "true" ]]; then
        args+=("--dry-run")
    fi

    if [[ "${SERVERSH_VERBOSE_OUTPUT:-false}" == "true" ]]; then
        args+=("--verbose")
    fi

    if [[ "${SERVERSH_PARALLEL_INSTALL:-false}" == "true" ]]; then
        args+=("--parallel")
    fi

    # Setze SSH Port für Firewall (wird vom SSH-Modul gesetzt)
    export SERVERSH_FINAL_SSH_PORT="${SERVERSH_FINAL_SSH_PORT:-22}"

    # Führe Installation aus
    log_info "Ausführung: $install_script ${args[*]}"

    if [[ "${SERVERSH_DEBUG:-false}" == "true" ]]; then
        "$install_script" "${args[@]}"
    else
        "$install_script" "${args[@]}" 2>&1 | while IFS= read -r line; do
            if [[ "$line" =~ \[SUCCESS\] ]]; then
                echo -e "${GREEN}$line${NC}"
            elif [[ "$line" =~ \[WARNING\] ]]; then
                echo -e "${YELLOW}$line${NC}"
            elif [[ "$line" =~ \[ERROR\] ]]; then
                echo -e "${RED}$line${NC}"
            else
                echo "$line"
            fi
        done
    fi

    local exit_code=$?

    # Aufräumen
    rm -f "$temp_config"

    if [[ $exit_code -eq 0 ]]; then
        log_success "Installation erfolgreich abgeschlossen!"
    else
        log_error "Installation fehlgeschlagen mit Exit-Code: $exit_code"
        exit $exit_code
    fi
}

install_additional_packages() {
    if [[ -n "${SERVERSH_ADDITIONAL_PACKAGES:-}" ]]; then
        log_info "Installiere zusätzliche Pakete: ${SERVERSH_ADDITIONAL_PACKAGES}"

        IFS=',' read -ra packages <<< "$SERVERSH_ADDITIONAL_PACKAGES"

        if command_exists apt-get; then
            apt-get update -qq
            apt-get install -y "${packages[@]}"
        elif command_exists dnf; then
            dnf install -y "${packages[@]}"
        elif command_exists yum; then
            yum install -y "${packages[@]}"
        elif command_exists pacman; then
            pacman -S --noconfirm "${packages[@]}"
        else
            log_warning "Konnte Paketmanager nicht erkennen, überspringe zusätzliche Pakete"
        fi

        log_success "Zusätzliche Pakete installiert"
    fi
}

show_summary() {
    log_info "Installationszusammenfassung:"
    log_info "  Hostname: ${SERVERSH_HOSTNAME}"
    log_info "  Hauptbenutzer: ${SERVERSH_USERNAME}"
    log_info "  SSH Port: ${SERVERSH_FINAL_SSH_PORT:-22} (automatisch ermittelt)"
    log_info "  Firewall: ${SERVERSH_FIREWALL_ENABLE:-true}"
    log_info "  Docker: ${SERVERSH_DOCKER_ENABLE:-true}"
    log_info "  Prometheus: ${SERVERSH_PROMETHEUS_ENABLE:-true}"
    log_info "  Monitoring Port: ${SERVERSH_PROMETHEUS_PORT:-9090}"

    echo ""
    log_info "Nächste Schritte:"
    log_info "  1. Testen Sie die SSH-Verbindung: ssh ${SERVERSH_USERNAME}@${SERVERSH_HOSTNAME} -p ${SERVERSH_FINAL_SSH_PORT:-22}"
    log_info "  2. Öffnen Sie Prometheus: http://${SERVERSH_HOSTNAME}:${SERVERSH_PROMETHEUS_PORT:-9090}"
    log_info "  3. Prüfen Sie den Docker-Status: docker ps"
    log_info "  4. Überprüfen Sie die Firewall-Konfiguration"
}

# Hauptfunktion
main() {
    echo "=============================================================================="
    echo "ServerSH Environment-Based Installation"
    echo "=============================================================================="
    echo ""

    # Prüfe ob als root ausgeführt
    if [[ $EUID -ne 0 ]]; then
        log_error "Dieses Skript muss als root ausgeführt werden"
        exit 1
    fi

    # Prüfe Abhängigkeiten
    check_dependencies

    # Lade Konfiguration
    load_env_file "${1:-.env}"

    # Validiere Konfiguration
    validate_config

    # Erstelle Modul-Konfigurationen
    create_module_configs

    # Installiere zusätzliche Pakete
    install_additional_packages

    # Führe Installation durch
    run_installation

    # Zeige Zusammenfassung
    show_summary

    echo ""
    log_success "ServerSH Installation abgeschlossen!"
}

# Hilfsfunktion
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ausführung mit Parameterübergabe
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi