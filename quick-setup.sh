#!/bin/bash

# =============================================================================
# ServerSH Quick Setup Script
# =============================================================================
# Schnelle Einrichtung für verschiedene Anwendungsfälle

set -euo pipefail

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Header
show_header() {
    echo -e "${PURPLE}==============================================================================${NC}"
    echo -e "${PURPLE}ServerSH Quick Setup${NC}"
    echo -e "${PURPLE}Vollautomatische Server-Konfiguration${NC}"
    echo -e "${PURPLE}==============================================================================${NC}"
    echo ""
}

# Hauptmenü
show_menu() {
    echo -e "${CYAN}Wählen Sie eine Setup-Variante:${NC}"
    echo ""
    echo "1) 🖥️  Webserver Setup (Nginx + SSL + Firewall)"
    echo "2) 🐳 Docker Development Setup"
    echo "3) 📊 Monitoring Setup (Prometheus + Grafana)"
    echo "4) 🔒 Security Hardening Setup"
    echo "5) 🏢 Production Server Setup"
    echo "6) 🧪 Test Environment Setup"
    echo "7) 🔧 Benutzerdefiniertes Setup"
    echo "8) 📋 Nur Konfiguration erstellen"
    echo ""
    echo "0) Beenden"
    echo ""
}

# Benutzereingabe
read_choice() {
    local prompt="$1"
    local default="${2:-}"
    local result

    while true; do
        if [[ -n "$default" ]]; then
            read -p "$prompt [$default]: " result
            result="${result:-$default}"
        else
            read -p "$prompt: " result
        fi

        if [[ -n "$result" ]]; then
            echo "$result"
            break
        fi
    done
}

# Passwort eingabe
read_password() {
    local prompt="$1"
    local password

    while true; do
        read -s -p "$prompt: " password
        echo ""
        if [[ ${#password} -ge 8 ]]; then
            echo "$password"
            break
        else
            echo -e "${RED}Passwort muss mindestens 8 Zeichen lang sein${NC}"
        fi
    done
}

# E-Mail eingabe mit Validierung
read_email() {
    local prompt="$1"
    local email

    while true; do
        email=$(read_choice "$prompt")
        if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            echo "$email"
            break
        else
            echo -e "${RED}Ungültige E-Mail-Adresse${NC}"
        fi
    done
}

# Webserver Setup
setup_webserver() {
    echo -e "${BLUE}🖥️  Webserver Setup konfigurieren...${NC}"
    echo ""

    local hostname
    hostname=$(read_choice "Server-Hostname" "webserver")

    local domain
    domain=$(read_choice "Domain (optional)")

    local admin_email
    admin_email=$(read_email "Admin E-Mail")

    local ssh_port
    ssh_port=$(read_choice "SSH Port" "2222")

    local admin_user
    admin_user=$(read_choice "Admin-Benutzername" "admin")

    local admin_password
    admin_password=$(read_password "Admin-Passwort")

    # .env Datei erstellen
    cat > .env << EOF
# =============================================================================
# ServerSH Webserver Configuration
# =============================================================================

# System-Konfiguration
SERVERSH_HOSTNAME=$hostname
SERVERSH_FQDN=${domain}
SERVERSH_UPDATE_AUTO=true
SERVERSH_UPDATE_SECURITY_ONLY=false

# Benutzer-Konfiguration
SERVERSH_CREATE_USER=true
SERVERSH_USERNAME=$admin_user
SERVERSH_USER_PASSWORD=$admin_password
SERVERSH_USER_SSH_KEY=true
SERVERSH_USER_SUDO=true
SERVERSH_USER_SHELL=/bin/bash
SERVERSH_ADDITIONAL_SSH_KEYS=""

# SSH-Konfiguration
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_SSH_PREFERRED_PORT=$ssh_port
SERVERSH_SSH_AUTO_SELECT_PORT=true
SERVERSH_SSH_PERMIT_ROOT_LOGIN=no
SERVERSH_SSH_PASSWORD_AUTHENTICATION=no

# Firewall-Konfiguration
SERVERSH_FIREWALL_ENABLE=true
SERVERSH_FIREWALL_TYPE=auto
SERVERSH_FIREWALL_DEFAULT_POLICY=deny
SERVERSH_FIREWALL_ALLOWED_PORTS="80/tcp,443/tcp"
SERVERSH_FIREWALL_LOG_RULES=true

# Docker-Konfiguration
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DOCKER_VERSION=latest
SERVERSH_DOCKER_INSTALL_COMPOSE=true
SERVERSH_DOCKER_USER=$admin_user

# Prometheus-Konfiguration
SERVERSH_PROMETHEUS_ENABLE=true
SERVERSH_PROMETHEUS_PORT=9090
SERVERSH_NODE_EXPORTER_ENABLE=true

# Zusätzliche Pakete
SERVERSH_ADDITIONAL_PACKAGES="htop,vim,git,curl,wget,unzip,tree,ncdu,nginx,certbot,python3-certbot-nginx"

# Tailscale Konfiguration
SERVERSH_INSTALL_TAILSCALE=true
SERVERSH_TAILSCALE_LOGIN_METHOD=interactive
SERVERSH_TAILSCALE_ARGS="--accept-dns=false"

# Sicherheits-Konfiguration
SERVERSH_INSTALL_FAIL2BAN=true
SERVERSH_AUTO_SECURITY_UPDATES=true
SERVERSH_AUTO_UPDATE_MAIL=$admin_email

# Installations-Optionen
SERVERSH_LOG_LEVEL=INFO
SERVERSH_AUTO_BACKUP=true
SERVERSH_ROLLBACK_ON_ERROR=true
SERVERSH_MODULE_ORDER="system/update,system/hostname,security/users,security/ssh,security/firewall,container/docker,monitoring/prometheus,applications/optional_software"
EOF

    echo ""
    echo -e "${GREEN}✅ Webserver-Konfiguration erstellt!${NC}"
    echo -e "${YELLOW}Starte Installation mit:${NC} ./auto-deploy.sh local"
}

# Docker Development Setup
setup_docker_dev() {
    echo -e "${BLUE}🐳 Docker Development Setup konfigurieren...${NC}"
    echo ""

    local hostname
    hostname=$(read_choice "Entwicklungs-Hostname" "devbox")

    local admin_user
    admin_user=$(read_choice "Entwickler-Benutzername" "developer")

    local admin_password
    admin_password=$(read_password "Entwickler-Passwort")

    local ssh_port
    ssh_port=$(read_choice "SSH Port" "2222")

    # .env Datei erstellen
    cat > .env << EOF
# =============================================================================
# ServerSH Docker Development Configuration
# =============================================================================

# System-Konfiguration
SERVERSH_HOSTNAME=$hostname
SERVERSH_UPDATE_AUTO=true
SERVERSH_UPDATE_CLEANUP=true

# Benutzer-Konfiguration
SERVERSH_CREATE_USER=true
SERVERSH_USERNAME=$admin_user
SERVERSH_USER_PASSWORD=$admin_password
SERVERSH_USER_SSH_KEY=true
SERVERSH_USER_SUDO=true
SERVERSH_USER_SHELL=/bin/bash

# SSH-Konfiguration
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_SSH_PREFERRED_PORT=$ssh_port
SERVERSH_SSH_AUTO_SELECT_PORT=true
SERVERSH_SSH_PERMIT_ROOT_LOGIN=no
SERVERSH_SSH_PASSWORD_AUTHENTICATION=no

# Firewall-Konfiguration
SERVERSH_FIREWALL_ENABLE=true
SERVERSH_FIREWALL_DEFAULT_POLICY=allow
SERVERSH_FIREWALL_ALLOWED_PORTS="80/tcp,443/tcp,3000/tcp,8000/tcp,8080/tcp,3001/tcp,5000/tcp"

# Docker-Konfiguration
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DOCKER_VERSION=latest
SERVERSH_DOCKER_INSTALL_COMPOSE=true
SERVERSH_DOCKER_USER=$admin_user
SERVERSH_DOCKER_NETWORK_MTU=1450
SERVERSH_DOCKER_NETWORK_IPV6=true

# Zusätzliche Pakete
SERVERSH_ADDITIONAL_PACKAGES="htop,vim,git,curl,wget,unzip,tree,ncdu,build-essential,python3,python3-pip,nodejs,npm,yarn,docker-compose"

# Entwicklungstools
SERVERSH_DEV_TOOLS=true
SERVERSH_DEV_PACKAGES="build-essential,python3,python3-pip,nodejs,npm"

# Installations-Optionen
SERVERSH_LOG_LEVEL=INFO
SERVERSH_AUTO_BACKUP=true
SERVERSH_MODULE_ORDER="system/update,system/hostname,security/users,security/ssh,container/docker"
EOF

    echo ""
    echo -e "${GREEN}✅ Docker Development Konfiguration erstellt!${NC}"
    echo -e "${YELLOW}Starte Installation mit:${NC} ./auto-deploy.sh local"
}

# Monitoring Setup
setup_monitoring() {
    echo -e "${BLUE}📊 Monitoring Setup konfigurieren...${NC}"
    echo ""

    local hostname
    hostname=$(read_choice "Monitoring-Hostname" "monitoring")

    local admin_user
    admin_user=$(read_choice "Admin-Benutzername" "monitoring")

    local admin_password
    admin_password=$(read_password "Admin-Passwort")

    local prometheus_port
    prometheus_port=$(read_choice "Prometheus Port" "9090")

    local grafana_port
    grafana_port=$(read_choice "Grafana Port" "3000")

    # .env Datei erstellen
    cat > .env << EOF
# =============================================================================
# ServerSH Monitoring Configuration
# =============================================================================

# System-Konfiguration
SERVERSH_HOSTNAME=$hostname
SERVERSH_UPDATE_AUTO=true
SERVERSH_UPDATE_SECURITY_ONLY=true

# Benutzer-Konfiguration
SERVERSH_CREATE_USER=true
SERVERSH_USERNAME=$admin_user
SERVERSH_USER_PASSWORD=$admin_password
SERVERSH_USER_SSH_KEY=true
SERVERSH_USER_SUDO=true
SERVERSH_USER_SHELL=/bin/bash

# SSH-Konfiguration
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_SSH_PREFERRED_PORT=2222
SERVERSH_SSH_AUTO_SELECT_PORT=true

# Firewall-Konfiguration
SERVERSH_FIREWALL_ENABLE=true
SERVERSH_FIREWALL_DEFAULT_POLICY=deny
SERVERSH_FIREWALL_ALLOWED_PORTS="9090/tcp,3000/tcp,9100/tcp"

# Docker-Konfiguration
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DOCKER_INSTALL_COMPOSE=true
SERVERSH_DOCKER_USER=$admin_user

# Prometheus-Konfiguration
SERVERSH_PROMETHEUS_ENABLE=true
SERVERSH_PROMETHEUS_PORT=$prometheus_port
SERVERSH_PROMETHEUS_RETENTION=30d
SERVERSH_PROMETHEUS_STORAGE_PATH=/var/lib/prometheus
SERVERSH_NODE_EXPORTER_ENABLE=true
SERVERSH_NODE_EXPORTER_PORT=9100

# Grafana-Konfiguration
SERVERSH_GRAFANA_ENABLE=true
SERVERSH_GRAFANA_PORT=$grafana_port

# Zusätzliche Pakete
SERVERSH_ADDITIONAL_PACKAGES="htop,vim,git,curl,wget"

# Installations-Optionen
SERVERSH_LOG_LEVEL=INFO
SERVERSH_AUTO_BACKUP=true
SERVERSH_MODULE_ORDER="system/update,system/hostname,security/users,security/ssh,security/firewall,container/docker,monitoring/prometheus,applications/optional_software"
EOF

    echo ""
    echo -e "${GREEN}✅ Monitoring Konfiguration erstellt!${NC}"
    echo -e "${YELLOW}Starte Installation mit:${NC} ./auto-deploy.sh local"
}

# Security Hardening Setup
setup_security() {
    echo -e "${BLUE}🔒 Security Hardening Setup konfigurieren...${NC}"
    echo ""

    local hostname
    hostname=$(read_choice "Server-Hostname" "secured-server")

    local admin_user
    admin_user=$(read_choice "Admin-Benutzername" "admin")

    local admin_password
    admin_password=$(read_password "Admin-Passwort (min. 12 Zeichen)")

    while [[ ${#admin_password} -lt 12 ]]; do
        echo -e "${RED}Für Security Setup wird ein langes Passwort empfohlen (min. 12 Zeichen)${NC}"
        admin_password=$(read_password "Admin-Passwort (min. 12 Zeichen)")
    done

    local ssh_port
    ssh_port=$(read_choice "SSH Port (empfohlen: >2000)" "3333")

    # .env Datei erstellen
    cat > .env << EOF
# =============================================================================
# ServerSH Security Hardening Configuration
# =============================================================================

# System-Konfiguration
SERVERSH_HOSTNAME=$hostname
SERVERSH_UPDATE_AUTO=true
SERVERSH_UPDATE_SECURITY_ONLY=true
SERVERSH_UPDATE_CLEANUP=true

# Benutzer-Konfiguration
SERVERSH_CREATE_USER=true
SERVERSH_USERNAME=$admin_user
SERVERSH_USER_PASSWORD=$admin_password
SERVERSH_USER_SSH_KEY=true
SERVERSH_USER_SUDO=true
SERVERSH_USER_SHELL=/bin/bash

# SSH-Konfiguration (maximale Sicherheit)
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_SSH_PREFERRED_PORT=$ssh_port
SERVERSH_SSH_AUTO_SELECT_PORT=true
SERVERSH_SSH_PERMIT_ROOT_LOGIN=no
SERVERSH_SSH_PASSWORD_AUTHENTICATION=no
SERVERSH_SSH_PERMIT_EMPTY_PASSWORDS=no
SERVERSH_SSH_X11_FORWARDING=no
SERVERSH_SSH_CLIENT_ALIVE_INTERVAL=300
SERVERSH_SSH_CLIENT_ALIVE_COUNT_MAX=2
SERVERSH_SSH_MAX_AUTH_TRIES=3
SERVERSH_SSH_MAX_SESSIONS=2

# Firewall-Konfiguration (restriktiv)
SERVERSH_FIREWALL_ENABLE=true
SERVERSH_FIREWALL_TYPE=auto
SERVERSH_FIREWALL_DEFAULT_POLICY=deny
SERVERSH_FIREWALL_ALLOW_SSH=true
SERVERSH_FIREWALL_ALLOWED_PORTS=""
SERVERSH_FIREWALL_LOG_RULES=true

# Docker-Konfiguration
SERVERSH_DOCKER_ENABLE=false

# Prometheus-Konfiguration (lokal nur)
SERVERSH_PROMETHEUS_ENABLE=false

# Sicherheits-Konfiguration
SERVERSH_INSTALL_FAIL2BAN=true
SERVERSH_FAIL2BAN_MAXRETRY=3
SERVERSH_FAIL2BAN_FINDTIME=600
SERVERSH_FAIL2BAN_BANTIME=3600
SERVERSH_AUTO_SECURITY_UPDATES=true

# Zusätzliche Sicherheitspakete
SERVERSH_ADDITIONAL_PACKAGES="htop,vim,git,curl,wget,auditd,rkhunter,chkrootkit,lynis"

# Installations-Optionen
SERVERSH_LOG_LEVEL=INFO
SERVERSH_AUTO_BACKUP=true
SERVERSH_ROLLBACK_ON_ERROR=true
SERVERSH_MODULE_ORDER="system/update,system/hostname,security/users,security/ssh,security/firewall"
EOF

    echo ""
    echo -e "${GREEN}✅ Security Hardening Konfiguration erstellt!${NC}"
    echo -e "${YELLOW}Starte Installation mit:${NC} ./auto-deploy.sh local"
}

# Production Server Setup
setup_production() {
    echo -e "${BLUE}🏢 Production Server Setup konfigurieren...${NC}"
    echo ""

    local hostname
    hostname=$(read_choice "Produktions-Hostname")

    local domain
    domain=$(read_choice "Produktions-Domain")

    local admin_email
    admin_email=$(read_email "Admin E-Mail")

    local admin_user
    admin_user=$(read_choice "Admin-Benutzername" "admin")

    local admin_password
    admin_password=$(read_password "Admin-Passwort (min. 16 Zeichen)")

    while [[ ${#admin_password} -lt 16 ]]; do
        echo -e "${RED}Für Production wird ein sehr langes Passwort empfohlen (min. 16 Zeichen)${NC}"
        admin_password=$(read_password "Admin-Passwort (min. 16 Zeichen)")
    done

    local ssh_port
    ssh_port=$(read_choice "SSH Port (empfohlen: >4000)" "4444")

    local backup_enable
    backup_enable=$(read_choice "Backup aktivieren? (ja/nein)" "ja")

    # .env Datei erstellen
    cat > .env << EOF
# =============================================================================
# ServerSH Production Configuration
# =============================================================================

# System-Konfiguration
SERVERSH_HOSTNAME=$hostname
SERVERSH_FQDN=$domain
SERVERSH_UPDATE_AUTO=true
SERVERSH_UPDATE_SECURITY_ONLY=true
SERVERSH_UPDATE_CLEANUP=true

# Benutzer-Konfiguration
SERVERSH_CREATE_USER=true
SERVERSH_USERNAME=$admin_user
SERVERSH_USER_PASSWORD=$admin_password
SERVERSH_USER_SSH_KEY=true
SERVERSH_USER_SUDO=true
SERVERSH_USER_SHELL=/bin/bash

# SSH-Konfiguration
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_SSH_PREFERRED_PORT=$ssh_port
SERVERSH_SSH_AUTO_SELECT_PORT=true
SERVERSH_SSH_PERMIT_ROOT_LOGIN=no
SERVERSH_SSH_PASSWORD_AUTHENTICATION=no
SERVERSH_SSH_MAX_AUTH_TRIES=3
SERVERSH_SSH_MAX_SESSIONS=3

# Firewall-Konfiguration
SERVERSH_FIREWALL_ENABLE=true
SERVERSH_FIREWALL_TYPE=auto
SERVERSH_FIREWALL_DEFAULT_POLICY=deny
SERVERSH_FIREWALL_ALLOWED_PORTS="80/tcp,443/tcp"
SERVERSH_FIREWALL_LOG_RULES=true

# Docker-Konfiguration
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DOCKER_VERSION=latest
SERVERSH_DOCKER_INSTALL_COMPOSE=true
SERVERSH_DOCKER_USER=$admin_user

# Prometheus-Konfiguration
SERVERSH_PROMETHEUS_ENABLE=true
SERVERSH_PROMETHEUS_PORT=9090
SERVERSH_PROMETHEUS_RETENTION=30d
SERVERSH_NODE_EXPORTER_ENABLE=true

# Tailscale Konfiguration
SERVERSH_INSTALL_TAILSCALE=true
SERVERSH_TAILSCALE_LOGIN_METHOD=interactive
SERVERSH_TAILSCALE_ARGS="--accept-dns=false --accept-routes=true"

# Sicherheits-Konfiguration
SERVERSH_INSTALL_FAIL2BAN=true
SERVERSH_FAIL2BAN_MAXRETRY=2
SERVERSH_FAIL2BAN_FINDTIME=300
SERVERSH_FAIL2BAN_BANTIME=7200
SERVERSH_AUTO_SECURITY_UPDATES=true
SERVERSH_AUTO_UPDATE_MAIL=$admin_email

# Backup-Konfiguration
SERVERSH_BACKUP_ENABLE=$backup_enable
SERVERSH_BACKUP_SCHEDULE="0 2 * * *"
SERVERSH_BACKUP_RETENTION_DAYS=30
SERVERSH_BACKUP_PATH=/backup

# Zusätzliche Pakete
SERVERSH_ADDITIONAL_PACKAGES="htop,vim,git,curl,wget,unzip,tree,ncdu,rsync,logrotate,certbot,python3-certbot-nginx,auditd,rkhunter"

# Installations-Optionen
SERVERSH_LOG_LEVEL=INFO
SERVERSH_AUTO_BACKUP=true
SERVERSH_ROLLBACK_ON_ERROR=true
SERVERSH_MODULE_ORDER="system/update,system/hostname,security/users,security/ssh,security/firewall,container/docker,monitoring/prometheus,applications/optional_software"
EOF

    echo ""
    echo -e "${GREEN}✅ Production Konfiguration erstellt!${NC}"
    echo -e "${YELLOW}Starte Installation mit:${NC} ./auto-deploy.sh local"
}

# Test Environment Setup
setup_test() {
    echo -e "${BLUE}🧪 Test Environment Setup konfigurieren...${NC}"
    echo ""

    local hostname
    hostname=$(read_choice "Test-Hostname" "testbox")

    local test_user
    test_user=$(read_choice "Test-Benutzername" "testuser")

    local test_password
    test_password=$(read_password "Test-Passwort")

    # .env Datei erstellen
    cat > .env << EOF
# =============================================================================
# ServerSH Test Environment Configuration
# =============================================================================

# System-Konfiguration
SERVERSH_HOSTNAME=$hostname
SERVERSH_UPDATE_AUTO=false
SERVERSH_TEST_MODE=true

# Benutzer-Konfiguration
SERVERSH_CREATE_USER=true
SERVERSH_USERNAME=$test_user
SERVERSH_USER_PASSWORD=$test_password
SERVERSH_USER_SSH_KEY=true
SERVERSH_USER_SUDO=true
SERVERSH_USER_SHELL=/bin/bash

# SSH-Konfiguration
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=false
SERVERSH_SSH_PORT=22
SERVERSH_SSH_PERMIT_ROOT_LOGIN=yes
SERVERSH_SSH_PASSWORD_AUTHENTICATION=yes

# Firewall-Konfiguration
SERVERSH_FIREWALL_ENABLE=false

# Docker-Konfiguration
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DOCKER_VERSION=latest
SERVERSH_DOCKER_INSTALL_COMPOSE=true
SERVERSH_DOCKER_USER=$test_user

# Prometheus-Konfiguration
SERVERSH_PROMETHEUS_ENABLE=true
SERVERSH_PROMETHEUS_PORT=9090
SERVERSH_NODE_EXPORTER_ENABLE=true

# Zusätzliche Pakete
SERVERSH_ADDITIONAL_PACKAGES="htop,vim,git,curl,wget,unzip,tree,build-essential,python3,python3-pip"

# Installations-Optionen
SERVERSH_LOG_LEVEL=DEBUG
SERVERSH_TEST_MODE=true
SERVERSH_TEST_KEEP_CHANGES=false
SERVERSH_AUTO_BACKUP=true
SERVERSH_ROLLBACK_ON_ERROR=true
SERVERSH_MODULE_ORDER="system/update,system/hostname,security/users,security/ssh,container/docker,monitoring/prometheus"
EOF

    echo ""
    echo -e "${GREEN}✅ Test Environment Konfiguration erstellt!${NC}"
    echo -e "${YELLOW}Starte Installation mit:${NC} ./auto-deploy.sh local --dry-run"
}

# Benutzerdefiniertes Setup
setup_custom() {
    echo -e "${BLUE}🔧 Benutzerdefiniertes Setup konfigurieren...${NC}"
    echo ""

    # .env.example als Basis kopieren
    if [[ -f ".env.example" ]]; then
        cp .env.example .env
        echo -e "${GREEN}✅ Beispiel-Konfiguration nach .env kopiert${NC}"
        echo -e "${YELLOW}Bitte bearbeiten Sie .env nach Ihren Wünschen und starten mit:${NC}"
        echo -e "${YELLOW}./auto-deploy.sh local${NC}"
    else
        echo -e "${RED}❌ .env.example nicht gefunden!${NC}"
    fi
}

# Hauptprogramm
main() {
    show_header

    while true; do
        show_menu
        read -p "Ihre Wahl: " choice
        echo ""

        case $choice in
            1)
                setup_webserver
                break
                ;;
            2)
                setup_docker_dev
                break
                ;;
            3)
                setup_monitoring
                break
                ;;
            4)
                setup_security
                break
                ;;
            5)
                setup_production
                break
                ;;
            6)
                setup_test
                break
                ;;
            7)
                setup_custom
                break
                ;;
            8)
                echo -e "${BLUE}📋 Erstelle nur Konfigurationsdateien...${NC}"
                if [[ -f ".env.example" ]]; then
                    cp .env.example .env
                    echo -e "${GREEN}✅ .env erstellt!${NC}"
                fi
                echo -e "${YELLOW}Passen Sie .env an und verwenden Sie ./auto-deploy.sh${NC}"
                break
                ;;
            0)
                echo -e "${YELLOW}Auf Wiedersehen!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Ungültige Wahl!${NC}"
                echo ""
                ;;
        esac
    done

    echo ""
    echo -e "${GREEN}Setup konfiguriert!${NC}"
    echo ""
    echo -e "${CYAN}Nächste Schritte:${NC}"
    echo -e "${YELLOW}1. Überprüfen Sie die .env Datei${NC}"
    echo -e "${YELLOW}2. Starten Sie die Installation: ./auto-deploy.sh local${NC}"
    echo -e "${YELLOW}3. Oder verwenden Sie Docker: ./auto-deploy.sh docker${NC}"
    echo ""
}

# Skript ausführen
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi