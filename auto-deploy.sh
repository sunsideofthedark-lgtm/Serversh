#!/bin/bash

# =============================================================================
# ServerSH Auto-Deploy Script
# =============================================================================
# Vollautomatisierte Deployment für verschiedene Szenarien

set -euo pipefail

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script-Verzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() { echo -e "${PURPLE}[HEADER]${NC} $1"; }
log_command() { echo -e "${CYAN}[COMMAND]${NC} $1"; }

# Hilfe anzeigen
show_help() {
    cat << EOF
ServerSH Auto-Deploy Script

Verwendung:
  $0 [MODUS] [OPTIONEN]

MODI:
  local          Lokale Installation direkt auf dem System
  docker         Docker-basierte Installation
  compose        Docker Compose Installation
  remote         Remote-Installation über SSH
  generate       Nur Konfigurationen generieren
  validate       Konfiguration validieren

OPTIONEN:
  --env FILE     Umgebungsdatei (Standard: .env)
  --config FILE  Konfigurationsdatei (Standard: .env)
  --dry-run      Testlauf ohne Änderungen
  --verbose      Detaillierte Ausgabe
  --debug        Debug-Modus
  --help         Diese Hilfe anzeigen

BEISPIELE:
  # Lokale Installation
  $0 local

  # Docker Installation
  $0 docker --env production.env

  # Mit Monitoring Services
  $0 compose --env production.env --profiles monitoring,grafana

  # Remote Installation
  $0 remote --host 192.168.1.100 --user root --env production.env

  # Nur Konfiguration generieren
  $0 generate --env production.env

  # Konfiguration validieren
  $0 validate --env production.env

EOF
}

# Konfiguration laden
load_config() {
    local env_file="${1:-.env}"

    if [[ ! -f "$env_file" ]]; then
        log_error "Umgebungsdatei nicht gefunden: $env_file"
        log_info "Erstelle Beispielkonfiguration aus .env.example..."
        if [[ -f ".env.example" ]]; then
            cp .env.example "$env_file"
            log_success "Beispielkonfiguration erstellt als: $env_file"
            log_info "Bitte bearbeiten Sie die Datei und versuchen Sie es erneut."
        else
            log_error "Keine Beispielkonfiguration gefunden!"
        fi
        exit 1
    fi

    log_info "Lade Konfiguration aus: $env_file"
    set -a
    source "$env_file"
    set +a
}

# Konfiguration validieren
validate_config() {
    log_info "Validiere Konfiguration..."

    local errors=()

    # Erforderliche Variablen prüfen
    local required_vars=(
        "SERVERSH_HOSTNAME"
        "SERVERSH_USERNAME"
        "SERVERSH_USER_PASSWORD"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            errors+=("$var ist nicht gesetzt")
        fi
    done

    # Passwort-Stärke prüfen
    if [[ -n "${SERVERSH_USER_PASSWORD:-}" ]]; then
        if [[ ${#SERVERSH_USER_PASSWORD} -lt 8 ]]; then
            errors+=("Passwort muss mindestens 8 Zeichen lang sein")
        fi
        if [[ "$SERVERSH_USER_PASSWORD" =~ ^[a-zA-Z]+$ ]] || [[ "$SERVERSH_USER_PASSWORD" =~ ^[0-9]+$ ]]; then
            errors+=("Passwort sollte Buchstaben und Zahlen enthalten")
        fi
    fi

    # Port-Nummern prüfen
    local port_vars=(
        "SERVERSH_SSH_PORT"
        "SERVERSH_PROMETHEUS_PORT"
        "SERVERSH_NODE_EXPORTER_PORT"
    )

    for var in "${port_vars[@]}"; do
        if [[ -n "${!var:-}" ]] && ! [[ "${!var}" =~ ^[0-9]+$ ]] && [[ "${!var}" -ge 1 ]] && [[ "${!var}" -le 65535 ]]; then
            errors+=("$var muss eine gültige Port-Nummer (1-65535) sein")
        fi
    done

    # Hostname-Format prüfen
    if [[ -n "${SERVERSH_HOSTNAME:-}" ]] && ! [[ "$SERVERSH_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        errors+=("SERVERSH_HOSTNAME hat ungültiges Format")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Konfigurationsfehler:"
        for error in "${errors[@]}"; do
            log_error "  ❌ $error"
        done
        return 1
    fi

    log_success "Konfiguration validiert"
    return 0
}

# Lokale Installation
deploy_local() {
    log_header "Lokale ServerSH Installation"

    # Prüfe ob als root
    if [[ $EUID -ne 0 ]]; then
        log_error "Lokale Installation erfordert root-Rechte"
        log_info "Verwenden Sie: sudo $0 local"
        exit 1
    fi

    # Konfiguration laden und validieren
    load_config "$ENV_FILE"
    validate_config

    # Installations-Skript ausführen
    local install_script="${SCRIPT_DIR}/serversh/scripts/install-from-env.sh"

    if [[ ! -f "$install_script" ]]; then
        log_error "Installationsskript nicht gefunden: $install_script"
        exit 1
    fi

    local args=(
        "$ENV_FILE"
    )

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        args+=("--dry-run")
    fi

    if [[ "${VERBOSE:-false}" == "true" ]]; then
        args+=("--verbose")
    fi

    log_command "Ausführung: $install_script ${args[*]}"
    "$install_script" "${args[@]}"
}

# Docker Installation
deploy_docker() {
    log_header "Docker-basierte ServerSH Installation"

    # Prüfe ob Docker verfügbar
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker ist nicht installiert oder nicht im PATH"
        exit 1
    fi

    # Konfiguration laden und validieren
    load_config "$ENV_FILE"
    validate_config

    # Docker-Image bauen
    log_info "Bauce ServerSH Setup Docker-Image..."
    if ! docker build -f Dockerfile.setup -t serversh-setup:latest .; then
        log_error "Docker-Image Build fehlgeschlagen"
        exit 1
    fi

    # Setup-Container ausführen
    log_info "Starte ServerSH Setup Container..."

    local docker_args=(
        "--rm"
        "--privileged"
        "-v" "$(pwd):/serversh:ro"
        "-v" "/var/run/docker.sock:/var/run/docker.sock"
        "-v" "/:/host"
        "--env-file" "$ENV_FILE"
    )

    if [[ "${KEEP_RUNNING:-false}" == "true" ]]; then
        docker_args+=("-e" "KEEP_RUNNING=true")
    fi

    if [[ "${INTERACTIVE:-false}" == "true" ]]; then
        docker_args+=("-it")
    fi

    log_command "Ausführung: docker run ${docker_args[*]} serversh-setup:latest"
    docker run "${docker_args[@]}" serversh-setup:latest
}

# Docker Compose Installation
deploy_compose() {
    log_header "Docker Compose ServerSH Installation"

    # Prüfe ob docker-compose verfügbar
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose ist nicht installiert"
        exit 1
    fi

    # Konfiguration laden und validieren
    load_config "$ENV_FILE"
    validate_config

    # Compose-Datei
    local compose_file="docker-compose.server-setup.yml"

    if [[ ! -f "$compose_file" ]]; then
        log_error "Docker Compose Datei nicht gefunden: $compose_file"
        exit 1
    fi

    # Verzeichnisse erstellen
    mkdir -p configs/{prometheus,grafana,traefik,dynamic} logs state

    # Docker Compose ausführen
    log_info "Starte Docker Compose..."

    local compose_args=(
        "-f" "$compose_file"
        "--env-file" "$ENV_FILE"
        "up"
        "-d"
    )

    # Profile hinzufügen
    if [[ -n "${COMPOSE_PROFILES:-}" ]]; then
        IFS=',' read -ra profiles <<< "$COMPOSE_PROFILES"
        for profile in "${profiles[@]}"; do
            compose_args+=("--profile" "$(echo "$profile" | xargs)")
        done
    fi

    # Wähle Services
    local services=("serversh-setup")
    if [[ -n "${COMPOSE_SERVICES:-}" ]]; then
        IFS=',' read -ra svc_list <<< "$COMPOSE_SERVICES"
        services=("${svc_list[@]}")
    fi

    compose_args+=("${services[@]}")

    log_command "Ausführung: docker compose ${compose_args[*]}"

    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose "${compose_args[@]}"
    else
        docker compose "${compose_args[@]}"
    fi

    # Status anzeigen
    log_info "Container-Status:"
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose -f "$compose_file" ps
    else
        docker compose -f "$compose_file" ps
    fi
}

# Remote Installation
deploy_remote() {
    log_header "Remote ServerSH Installation"

    # Erforderliche Parameter prüfen
    if [[ -z "${REMOTE_HOST:-}" ]]; then
        log_error "REMOTE_HOST ist erforderlich für Remote-Installation"
        exit 1
    fi

    if [[ -z "${REMOTE_USER:-}" ]]; then
        log_error "REMOTE_USER ist erforderlich für Remote-Installation"
        exit 1
    fi

    # Konfiguration laden und validieren
    load_config "$ENV_FILE"
    validate_config

    # SSH-Verbindung prüfen
    log_info "Teste SSH-Verbindung zu ${REMOTE_USER}@${REMOTE_HOST}..."
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "${REMOTE_USER}@${REMOTE_HOST}" "echo 'SSH-Verbindung erfolgreich'"; then
        log_error "SSH-Verbindung fehlgeschlagen"
        log_info "Stellen Sie sicher dass:"
        log_info "  - SSH-Schlüssel konfiguriert sind"
        log_info "  - Der Server erreichbar ist"
        log_info "  - Der Benutzer SSH-Zugriff hat"
        exit 1
    fi

    # Projekt kopieren
    log_info "Kopiere Projekt zum Remote-Server..."
    local remote_dir="/tmp/serversh-deploy-$(date +%s)"

    ssh "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p '$remote_dir'"
    scp -r . "${REMOTE_USER}@${REMOTE_HOST}:$remote_dir/"

    # Umgebungsdatei kopieren
    scp "$ENV_FILE" "${REMOTE_USER}@${REMOTE_HOST}:$remote_dir/.env"

    # Installation ausführen
    log_info "Führe Remote-Installation durch..."
    local remote_cmd="
        cd '$remote_dir' && \
        sudo bash serversh/scripts/install-from-env.sh .env
    "

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        remote_cmd="$remote_cmd --dry-run"
    fi

    if [[ "${VERBOSE:-false}" == "true" ]]; then
        remote_cmd="$remote_cmd --verbose"
    fi

    log_command "Remote-Ausführung: $remote_cmd"
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "$remote_cmd"

    # Aufräumen
    if [[ "${CLEANUP_REMOTE:-true}" == "true" ]]; then
        log_info "Räume Remote-Verzeichnis auf..."
        ssh "${REMOTE_USER}@${REMOTE_HOST}" "rm -rf '$remote_dir'"
    fi
}

# Konfigurationen generieren
generate_configs() {
    log_header "ServerSH Konfigurationen generieren"

    # Konfiguration laden und validieren
    load_config "$ENV_FILE"
    validate_config

    # Installations-Skript mit --dry-run --config-only aufrufen
    local install_script="${SCRIPT_DIR}/serversh/scripts/install-from-env.sh"

    if [[ ! -f "$install_script" ]]; then
        log_error "Installationsskript nicht gefunden: $install_script"
        exit 1
    fi

    log_info "Generiere Konfigurationen..."

    # Temporäres Verzeichnis für generierte Konfigs
    local output_dir="${OUTPUT_DIR:-./generated-configs}"
    mkdir -p "$output_dir"

    # Hier müsste der Installations-Skript erweitert werden
    # Für jetzt erstellen wir manuell die Konfigurationen
    create_manual_configs "$output_dir"

    log_success "Konfigurationen generiert in: $output_dir"
}

# Manuelles Erstellen von Konfigurationen (Fallback)
create_manual_configs() {
    local output_dir="$1"

    # System Update
    cat > "$output_dir/system_update.yaml" << EOF
system/update:
  auto_update: ${SERVERSH_UPDATE_AUTO:-true}
  security_only: ${SERVERSH_UPDATE_SECURITY_ONLY:-false}
  cleanup: ${SERVERSH_UPDATE_CLEANUP:-true}
EOF

    # Hostname
    cat > "$output_dir/hostname.yaml" << EOF
system/hostname:
  hostname: "${SERVERSH_HOSTNAME}"
  fqdn: "${SERVERSH_FQDN:-}"
  update_hosts: ${SERVERSH_HOSTNAME_UPDATE_HOSTS:-true}
  validate_dns: ${SERVERSH_HOSTNAME_VALIDATE_DNS:-false}
EOF

    # Benutzer
    cat > "$output_dir/users.yaml" << EOF
security/users:
  create_user: ${SERVERSH_CREATE_USER:-true}
  username: "${SERVERSH_USERNAME}"
  password: "${SERVERSH_USER_PASSWORD}"
  ssh_key: ${SERVERSH_USER_SSH_KEY:-true}
  sudo: ${SERVERSH_USER_SUDO:-true}
  shell: "${SERVERSH_USER_SHELL:-/bin/bash}"
EOF

    # SSH
    cat > "$output_dir/ssh.yaml" << EOF
security/ssh_interactive:
  interactive_port: ${SERVERSH_SSH_INTERACTIVE_PORT:-true}
  preferred_port: ${SERVERSH_SSH_PREFERRED_PORT:-2222}
  auto_select_port: ${SERVERSH_SSH_AUTO_SELECT_PORT:-true}
  scan_ranges: "${SERVERSH_SSH_SCAN_RANGES:-2000-2999,4000-4999,5000-5999}"
EOF

    # Firewall
    cat > "$output_dir/firewall.yaml" << EOF
security/firewall:
  firewall_type: "${SERVERSH_FIREWALL_TYPE:-auto}"
  enable_firewall: ${SERVERSH_FIREWALL_ENABLE:-true}
  default_policy: "${SERVERSH_FIREWALL_DEFAULT_POLICY:-deny}"
  allow_ssh: ${SERVERSH_FIREWALL_ALLOW_SSH:-true}
  allowed_ports: "${SERVERSH_FIREWALL_ALLOWED_PORTS:-80/tcp,443/tcp}"
  log_rules: ${SERVERSH_FIREWALL_LOG_RULES:-true}
EOF

    # Docker
    cat > "$output_dir/docker.yaml" << EOF
container/docker:
  version: "${SERVERSH_DOCKER_VERSION:-latest}"
  install_compose: ${SERVERSH_DOCKER_INSTALL_COMPOSE:-true}
  docker_user: "${SERVERSH_DOCKER_USER:-${SERVERSH_USERNAME}}"
  network_config:
    mtu: ${SERVERSH_DOCKER_NETWORK_MTU:-1450}
    ipv6: ${SERVERSH_DOCKER_NETWORK_IPV6:-true}
    name: "${SERVERSH_DOCKER_NETWORK_NAME:-newt_talk}"
EOF

    # Prometheus
    cat > "$output_dir/prometheus.yaml" << EOF
monitoring/prometheus:
  prometheus_version: "${SERVERSH_PROMETHEUS_VERSION:-latest}"
  install_node_exporter: ${SERVERSH_NODE_EXPORTER_ENABLE:-true}
  prometheus_port: ${SERVERSH_PROMETHEUS_PORT:-9090}
  node_exporter_port: ${SERVERSH_NODE_EXPORTER_PORT:-9100}
  enable_service: ${SERVERSH_PROMETHEUS_ENABLE_SERVICE:-true}
EOF

    log_info "Konfigurationsdateien erstellt:"
    ls -la "$output_dir/"
}

# Parameter parsen
parse_args() {
    MODE=""
    ENV_FILE=".env"
    DRY_RUN=false
    VERBOSE=false
    DEBUG=false
    INTERACTIVE=false
    KEEP_RUNNING=false
    CLEANUP_REMOTE=true
    OUTPUT_DIR="./generated-configs"
    COMPOSE_PROFILES=""
    COMPOSE_SERVICES=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --env)
                ENV_FILE="$2"
                shift 2
                ;;
            --config)
                ENV_FILE="$2"
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
            --debug)
                DEBUG=true
                VERBOSE=true
                shift
                ;;
            --interactive)
                INTERACTIVE=true
                shift
                ;;
            --keep-running)
                KEEP_RUNNING=true
                shift
                ;;
            --cleanup-remote)
                CLEANUP_REMOTE="${2:-true}"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --profiles)
                COMPOSE_PROFILES="$2"
                shift 2
                ;;
            --services)
                COMPOSE_SERVICES="$2"
                shift 2
                ;;
            --host)
                export REMOTE_HOST="$2"
                shift 2
                ;;
            --user)
                export REMOTE_USER="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            local|docker|compose|remote|generate|validate)
                MODE="$1"
                shift
                ;;
            *)
                log_error "Unbekannter Parameter: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [[ -z "$MODE" ]]; then
        log_error "Kein Modus angegeben"
        show_help
        exit 1
    fi

    export DRY_RUN VERBOSE DEBUG INTERACTIVE KEEP_RUNNING CLEANUP_REMOTE OUTPUT_DIR COMPOSE_PROFILES COMPOSE_SERVICES
}

# Hauptfunktion
main() {
    echo "=============================================================================="
    echo "ServerSH Auto-Deploy Script"
    echo "=============================================================================="
    echo ""

    parse_args "$@"

    # Debug-Modus
    if [[ "$DEBUG" == "true" ]]; then
        set -x
        log_info "Debug-Modus aktiviert"
    fi

    # Modus ausführen
    case "$MODE" in
        local)
            deploy_local
            ;;
        docker)
            deploy_docker
            ;;
        compose)
            deploy_compose
            ;;
        remote)
            deploy_remote
            ;;
        generate)
            generate_configs
            ;;
        validate)
            load_config "$ENV_FILE"
            validate_config
            log_success "Konfiguration ist gültig!"
            ;;
        *)
            log_error "Unbekannter Modus: $MODE"
            show_help
            exit 1
            ;;
    esac

    echo ""
    log_success "Auto-Deploy abgeschlossen!"
}

# Ausführung
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi