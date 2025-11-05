# ServerSH - Modular Server Installation Framework

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash Version](https://img.shields.io/badge/bash-5.0+-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Ubuntu%20%7C%20Debian%20%7C%20CentOS%20%7C%20RHEL%20%7C%20Fedora-lightgrey.svg)](https://github.com/sunsideofthedark-lgtm/Serversh)

**ServerSH** ist ein modulares, automatisierbares Framework für die Server-Installation und Konfiguration. Es vereinfacht komplexe Server-Setups durch eine intuitive Architektur, YAML-Konfiguration und umfassende Automatisierung.

## ✨ Hauptmerkmale

- 🚀 **Schnelle Installation**: Minuten statt Stunden für vollständige Server-Setups
- 🔧 **Modulare Architektur**: Nur die Features installieren, die du benötigst
- 🎯 **Automatisierung**: Vollständige Automatisierung via Umgebungsvariablen
- 🔒 **Security-First**: SSH-Hardening, Firewall, Fail2ban Integration
- 🐳 **Docker Support**: Optimierte Docker-Konfiguration mit Netzwerk-Setup
- 📊 **Monitoring**: Prometheus + Node Exporter Integration
- 🔄 **Backup & Recovery**: Vollständige Backup-Lösung mit Disaster Recovery
- 🌐 **Multi-Server**: Cluster-Management und Load Balancing
- 📱 **VPN Integration**: Tailscale mit SSH-Unterstützung
- 🛠️ **Extensible**: Einfache Entwicklung eigener Module

## 🚀 Schnellstart

### Methode 1: Quick Setup (Empfohlen)

```bash
# Klone das Repository
git clone https://github.com/sunsideofthedark-lgtm/Serversh.git
cd Serversh

# Kopiere und konfiguriere die Umgebung
cp .env.example .env
nano .env  # Passe deine Konfiguration an

# Führe die Installation aus
./quick-setup.sh
```

### Methode 2: Environment-Based Installation

```bash
# Konfiguriere .env Datei
cp .env.example .env

# Starte vollautomatische Installation
./serversh/scripts/install-from-env.sh
```

### Methode 3: Manuelle Installation

```bash
# Standard-Konfiguration verwenden
sudo ./serversh/scripts/install.sh
```

## 📋 Inhaltsverzeichnis

- [Installation](#installation)
- [Konfiguration](#konfiguration)
- [Module](#module)
- [Verwendung](#verwendung)
- [Backup & Recovery](#backup--recovery)
- [Multi-Server Management](#multi-server-management)
- [Sicherheit](#sicherheit)
- [Troubleshooting](#troubleshooting)
- [Entwicklung](#entwicklung)

## 🛠️ Installation

### Systemanforderungen

- **Betriebssysteme**: Ubuntu 18.04+, Debian 10+, CentOS 7+, RHEL 7+, Fedora 30+, Arch Linux, openSUSE Leap 15.4+
- **Bash**: Version 5.0 oder höher
- **Speicher**: Mindestens 2 GB RAM, 10 GB freier Speicherplatz
- **Netzwerk**: Internetverbindung für Paketinstallation

### Installationsschritte

1. **Repository klonen**
   ```bash
   git clone https://github.com/sunsideofthedark-lgtm/Serversh.git
   cd Serversh
   ```

2. **Konfiguration anpassen**
   ```bash
   # Environment-Konfiguration kopieren
   cp .env.example .env

   # Konfiguration bearbeiten
   nano .env
   ```

3. **Installation ausführen**
   ```bash
   # Interaktive Installation
   ./quick-setup.sh

   # Oder automatische Installation
   sudo ./serversh/scripts/install-from-env.sh
   ```

4. **Installation überprüfen**
   ```bash
   # Status prüfen
   sudo ./serversh/scripts/status.sh

   # Logs überprüfen
   sudo journalctl -u serversh -f
   ```

## ⚙️ Konfiguration

### Environment Variables (.env)

Die `.env` Datei enthält alle Konfigurationsoptionen für dein Server-Setup. Hier sind die wichtigsten Sektionen:

#### System-Konfiguration
```bash
# System Updates
SERVERSH_UPDATE_AUTO=true
SERVERSH_UPDATE_SECURITY_ONLY=false

# Hostname
SERVERSH_HOSTNAME=myserver
SERVERSH_FQDN=myserver.example.com
```

#### Benutzer-Konfiguration
```bash
# Hauptbenutzer
SERVERSH_CREATE_USER=true
SERVERSH_USERNAME=admin
SERVERSH_USER_PASSWORD=SecurePassword123!
SERVERSH_USER_SUDO=true
```

#### SSH-Konfiguration
```bash
# SSH Sicherheit
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_SSH_PREFERRED_PORT=2222
SERVERSH_SSH_PASSWORD_AUTHENTICATION=no
SERVERSH_SSH_PERMIT_ROOT_LOGIN=no
```

#### Docker-Konfiguration
```bash
# Docker Installation
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DOCKER_VERSION=latest
SERVERSH_DOCKER_INSTALL_COMPOSE=true

# Docker Netzwerk (MTU 1450 für Tailscale)
SERVERSH_DOCKER_NETWORK_MTU=1450
SERVERSH_DOCKER_NETWORK_NAME=newt_talk
SERVERSH_DOCKER_IPV6=true
```

#### Monitoring
```bash
# Prometheus
SERVERSH_PROMETHEUS_ENABLE=true
SERVERSH_PROMETHEUS_PORT=9090
SERVERSH_NODE_EXPORTER_ENABLE=true
```

#### Backup-Konfiguration
```bash
# Backup & Recovery
SERVERSH_BACKUP_ENABLE=true
SERVERSH_BACKUP_BASE_DIR=/backup
SERVERSH_BACKUP_SCHEDULE="0 2 * * *"
SERVERSH_BACKUP_RETENTION_DAYS=30
SERVERSH_BACKUP_ENCRYPTION=false
```

#### Tailscale VPN
```bash
# Tailscale Integration
SERVERSH_INSTALL_TAILSCALE=true
SERVERSH_TAILSCALE_SSH=true
SERVERSH_TAILSCALE_MAGICDNS=true
```

### YAML-Konfiguration

Alternativ kannst du YAML-Konfigurationsdateien verwenden:

```yaml
# serversh/configs/main.yaml
system:
  hostname: "myserver"
  update: true
  security_updates: true

security:
  ssh:
    enable: true
    port: 2222
    password_auth: false
  firewall:
    enable: true
    allow_ssh: true

applications:
  docker:
    enable: true
    compose: true
  prometheus:
    enable: true
    port: 9090
```

## 🧩 Module

ServerSH besteht aus modularen Komponenten, die je nach Bedarf installiert werden können:

### System Module

#### System Update (`system/update`)
- Automatische System-Updates
- Security-Only Updates
- Paket-Cleanup nach Updates

```yaml
system/update:
  auto_update: true
  security_only: false
  cleanup: true
```

#### Hostname (`system/hostname`)
- Hostname und FQDN Konfiguration
- /etc/hosts Update
- DNS-Validierung

```yaml
system/hostname:
  hostname: "myserver"
  fqdn: "myserver.example.com"
  update_hosts: true
  validate_dns: false
```

### Security Module

#### User Management (`security/users`)
- Benutzer-Erstellung mit SSH-Keys
- Sudo-Konfiguration
- Passwort-Richtlinien

```yaml
security/users:
  create_user: true
  username: "admin"
  password: "SecurePassword123!"
  ssh_key: true
  sudo: true
```

#### SSH Configuration (`security/ssh`)
- SSH-Hardening mit Port-Scanning
- Interaktive Port-Auswahl
- Security-Best-Practices

```yaml
security/ssh:
  enable: true
  interactive_port: true
  preferred_port: 2222
  security_settings:
    permit_root_login: "no"
    password_authentication: "no"
    client_alive_interval: 300
```

#### Firewall (`security/firewall`)
- UFW/Firewalld Auto-Detection
- Port-Management
- Logging-Konfiguration

```yaml
security/firewall:
  firewall_type: "auto"
  enable_firewall: true
  default_policy: "deny"
  allow_ssh: true
  allowed_ports: "80/tcp,443/tcp"
```

### Application Modules

#### Docker (`container/docker`)
- Docker Engine Installation
- Docker Compose
- Netzwerk-Konfiguration mit IPv6
- Benutzer-Rechte

```yaml
container/docker:
  version: "latest"
  install_compose: true
  network_config:
    mtu: 1450
    ipv6: true
    name: "newt_talk"
    ipv6_subnet: "2001:db8:1::/64"
```

#### Prometheus (`monitoring/prometheus`)
- Prometheus Installation
- Node Exporter
- Service-Konfiguration
- Retention-Policies

```yaml
monitoring/prometheus:
  prometheus_version: "latest"
  install_node_exporter: true
  prometheus_port: 9090
  node_exporter_port: 9100
  enable_service: true
```

#### Optional Software (`applications/optional_software`)
- Tailscale VPN Integration
- Development Tools
- System Utilities
- Shell Environment

```yaml
applications/optional_software:
  install_tailscale: true
  tailscale_ssh: true
  tailscale_magicdns: true
  install_utilities: true
  utility_packages: "htop,vim,git,curl,wget"
```

### Management Modules

#### Backup & Recovery (`backup/backup_recovery`)
- Multiple Backup-Strategien
- Verschlüsselung und Kompression
- Automatische Scheduling
- Disaster Recovery

```yaml
backup:
  enable: true
  base_directory: "/backup"
  schedule: "0 2 * * *"
  retention_days: 30
  compression: "gzip"
  encryption: false
  verify: true
```

#### Multi-Server Management (`management/multi_server`)
- Cluster-Konfiguration
- Load Balancing
- Service Discovery
- HAProxy Integration

```yaml
management/multi_server:
  cluster_mode: "single_node_cluster"
  etcd_enable: true
  load_balancer: "haproxy"
  monitoring: true
```

## 🎯 Verwendung

### Grundlegende Befehle

#### Installation
```bash
# Interaktive Installation
./quick-setup.sh

# Automatische Installation
sudo ./serversh/scripts/install-from-env.sh

# Mit benutzerdefinierter Konfiguration
sudo ./serversh/scripts/install.sh --config=my-config.yaml
```

#### Modul-Management
```bash
# Einzelnes Modul installieren
sudo ./serversh/scripts/install.sh --module=security/ssh

# Modul deinstallieren
sudo ./serversh/scripts/install.sh --uninstall --module=container/docker

# Modul-Status prüfen
sudo ./serversh/scripts/install.sh --status --module=monitoring/prometheus
```

#### Backup-Management
```bash
# Backup erstellen
sudo ./serversh/scripts/backupctl.sh create full

# Backup wiederherstellen
sudo ./serversh/scripts/backupctl.sh restore /backup/full/2024-01-01_02-00-00 /restore

# Backup-Liste anzeigen
./serversh/scripts/backupctl.sh list

# Backup-Status prüfen
./serversh/scripts/backupctl.sh status
```

#### Multi-Server-Management
```bash
# Cluster initialisieren
sudo ./serversh/scripts/clusterctl.sh init --mode=single_node

# Node zum Cluster hinzufügen
sudo ./serversh/scripts/clusterctl.sh join --token=TOKEN --master=master-ip

# Cluster-Status prüfen
./serversh/scripts/clusterctl.sh status
```

### Konfigurations-Beispiele

#### Minimal-Setup (Development)
```bash
# .env für minimales Setup
SERVERSH_HOSTNAME=dev-server
SERVERSH_USERNAME=dev
SERVERSH_USER_PASSWORD=dev123
SERVERSH_DOCKER_ENABLE=true
SERVERSH_PROMETHEUS_ENABLE=false
SERVERSH_BACKUP_ENABLE=false
```

#### Standard-Setup (Production)
```bash
# .env für Standard-Setup
SERVERSH_HOSTNAME=prod-server
SERVERSH_USERNAME=admin
SERVERSH_USER_PASSWORD=SecurePassword123!
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_FIREWALL_ENABLE=true
SERVERSH_DOCKER_ENABLE=true
SERVERSH_PROMETHEUS_ENABLE=true
SERVERSH_BACKUP_ENABLE=true
SERVERSH_INSTALL_TAILSCALE=true
```

#### Full-Cluster Setup
```bash
# .env für Cluster-Setup
SERVERSH_HOSTNAME=cluster-node-1
SERVERSH_MULTI_SERVER_MODE=cluster
SERVERSH_ETCD_ENABLE=true
SERVERSH_HAPROXY_ENABLE=true
SERVERSH_PROMETHEUS_ENABLE=true
SERVERSH_BACKUP_ENABLE=true
SERVERSH_BACKUP_REMOTE_ENABLE=true
```

## 💾 Backup & Recovery

### Backup-Strategien

#### Full Backup
```bash
# Vollständiges Backup erstellen
sudo ./serversh/scripts/backupctl.sh create full

# Mit benutzerdefinierten Quellen
sudo ./serversh/scripts/backupctl.sh create full "/etc,/home,/var/www"
```

#### Incremental Backup
```bash
# Inkrementelles Backup (seit letztem Full Backup)
sudo ./serversh/scripts/backupctl.sh create incremental

# Seit bestimmtem Zeitpunkt
sudo ./serversh/scripts/backupctl.sh create incremental --since="2024-01-01"
```

#### Differential Backup
```bash
# Differentielles Backup (seit letztem Full Backup)
sudo ./serversh/scripts/backupctl.sh create differential
```

#### Snapshot Backup
```bash
# Dateisystem-Snapshot
sudo ./serversh/scripts/backupctl.sh create snapshot
```

### Backup-Wiederherstellung

#### Komplette Wiederherstellung
```bash
# Aus Backup wiederherstellen
sudo ./serversh/scripts/backupctl.sh restore /backup/full/2024-01-01_02-00-00 /

# In bestimmtes Verzeichnis
sudo ./serversh/scripts/backupctl.sh restore /backup/full/2024-01-01_02-00-00 /restore
```

#### Selektive Wiederherstellung
```bash
# Nur bestimmte Dateien wiederherstellen
sudo ./serversh/scripts/backupctl.sh restore /backup/full/2024-01-01_02-00-00 /restore --include="*.conf"

# Bestimmte Verzeichnisse ausschließen
sudo ./serversh/scripts/backupctl.sh restore /backup/full/2024-01-01_02-00-00 /restore --exclude="/var/cache"
```

### Disaster Recovery

#### Disaster Recovery Package erstellen
```bash
# Komplettes DR-Paket erstellen
sudo ./serversh/scripts/backupctl.sh disaster-recovery

# Automatisches DR-Paket (monatlich)
sudo ./serversh/scripts/backupctl.sh schedule --type=disaster-recovery
```

#### System-Wiederherstellung
```bash
# Von Live-Medium booten und DR-Paket entpacken
tar -xzf disaster_recovery_2024-01-01_02-00-00.tar.gz
cd disaster_recovery_*

# Wiederherstellung starten
sudo ./recover.sh
```

### Backup-Management

#### Backup-Verifizierung
```bash
# Backup-Integrität prüfen
sudo ./serversh/scripts/backupctl.sh verify /backup/full/2024-01-01_02-00-00

# Alle Backups verifizieren
sudo ./serversh/scripts/backupctl.sh verify --all
```

#### Backup-Aufräumung
```bash
# Alte Backups löschen (gemäß Retention Policy)
sudo ./serversh/scripts/backupctl.sh cleanup

# Bestimmten Typ aufräumen
sudo ./serversh/scripts/backupctl.sh cleanup --type=incremental

# Manuelle Aufräumung mit Alters-Limit
sudo ./serversh/scripts/backupctl.sh cleanup --older-than=30d
```

## 🌐 Multi-Server Management

### Cluster-Konfiguration

#### Single Node Cluster
```bash
# Single Node Cluster initialisieren
sudo ./serversh/scripts/clusterctl.sh init --mode=single_node

# Status prüfen
./serversh/scripts/clusterctl.sh status
```

#### Multi-Node Cluster
```bash
# Master Node initialisieren
sudo ./serversh/scripts/clusterctl.sh init --mode=multi_master

# Worker Node hinzufügen
TOKEN=$(sudo ./serversh/scripts/clusterctl.sh token create --role=worker)
sudo ./serversh/scripts/clusterctl.sh join --token=$TOKEN --master=master-ip

# Additional Master hinzufügen
TOKEN=$(sudo ./serversh/scripts/clusterctl.sh token create --role=master)
sudo ./serversh/scripts/clusterctl.sh join --token=$TOKEN --master=master-ip
```

### Load Balancing

#### HAProxy Konfiguration
```bash
# HAProxy für Load Balancing installieren
sudo ./serversh/scripts/install.sh --module=management/multi_server

# Backend-Services konfigurieren
./serversh/scripts/clusterctl.sh backend add --name=web --port=80 --nodes=node1,node2,node3

# Load Balancer Status prüfen
./serversh/scripts/clusterctl.sh lb status
```

#### Service Discovery
```bash
# Service im Cluster registrieren
./serversh/scripts/clusterctl.sh service register --name=web-app --port=8080 --health=/health

# Services auflisten
./serversh/scripts/clusterctl.sh service list

# Service-Status prüfen
./serversh/scripts/clusterctl.sh service health --name=web-app
```

### Node Management

#### Node-Operationen
```bash
# Node entfernen (graceful)
./serversh/scripts/clusterctl.sh node remove --name=node3 --graceful

# Node pausieren (Wartung)
./serversh/scripts/clusterctl.sh node pause --name=node2

# Node reaktivieren
./serversh/scripts/clusterctl.sh node resume --name=node2

# Node-Status
./serversh/scripts/clusterctl.sh node status --name=node1
```

## 🔒 Sicherheit

### SSH-Hardening

#### Port-Konfiguration
```bash
# Interaktive Port-Auswahl
sudo ./serversh/scripts/install.sh --module=security/ssh_interactive

# Manuelles Port-Scanning
./serversh/scripts/port-scanner.sh --ranges=2000-2999,4000-4999
```

#### SSH-Konfiguration
```yaml
security/ssh:
  port: 2222
  permit_root_login: "no"
  password_authentication: "no"
  permit_empty_passwords: "no"
  client_alive_interval: 300
  client_alive_count_max: 2
  max_auth_tries: 3
  max_sessions: 10
```

### Firewall-Konfiguration

#### UFW (Ubuntu/Debian)
```bash
# UFW konfigurieren
sudo ufw enable
sudo ufw default deny incoming
sudo ufw allow 2222/tcp  # SSH Port
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
```

#### Firewalld (CentOS/RHEL)
```bash
# Firewalld konfigurieren
sudo firewall-cmd --set-default-zone=drop
sudo firewall-cmd --permanent --add-port=2222/tcp
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

### Fail2ban Integration

#### Konfiguration
```yaml
security:
  fail2ban:
    enable: true
    maxretry: 3
    findtime: 600
    bantime: 3600
    destemail: "admin@example.com"
    sendmail: true
```

#### Management
```bash
# Fail2ban Status prüfen
sudo fail2ban-client status

# IP unbanen
sudo fail2ban-client set sshd unbanip 192.168.1.100

# Logs anzeigen
sudo tail -f /var/log/fail2ban.log
```

### Tailscale VPN

#### Installation und Konfiguration
```bash
# Tailscale installieren
sudo ./serversh/scripts/install.sh --module=applications/optional_software

# Mit SSH-Unterstützung verbinden
sudo tailscale up --ssh --authkey=tskey-xxx

# Status prüfen
tailscale status
```

#### MagicDNS und SSH
```bash
# MagicDNS aktivieren
sudo tailscale set --magic-dns

# SSH über Tailscale
ssh admin@myserver.tailnet-xxxx.ts.net

# SSH-Keys anzeigen
tailscale status --self
```

## 🐛 Troubleshooting

### Häufige Probleme

#### SSH-Verbindungsprobleme
```bash
# SSH-Service Status prüfen
sudo systemctl status ssh

# SSH-Konfiguration validieren
sudo sshd -t

# Logs überprüfen
sudo journalctl -u ssh -f

# Port-Verfügbarkeit prüfen
sudo netstat -tlnp | grep :22
```

#### Docker-Probleme
```bash
# Docker-Service Status
sudo systemctl status docker

# Docker-Logs
sudo journalctl -u docker -f

# Netzwerk-Probleme
docker network ls
docker network inspect newt_talk

# Berechtigungen prüfen
groups $USER
sudo usermod -aG docker $USER
```

#### Backup-Probleme
```bash
# Backup-Status prüfen
./serversh/scripts/backupctl.sh status

# Konfiguration validieren
./serversh/scripts/backupctl.sh test

# Logs überprüfen
sudo journalctl -u serversh-backup -f

# Speicherplatz prüfen
df -h /backup
```

#### Cluster-Probleme
```bash
# Cluster-Status prüfen
./serversh/scripts/clusterctl.sh status

# Node-Konnektivität
./serversh/scripts/clusterctl.sh node test --name=node1

# Service-Logs
sudo journalctl -u etcd -f
sudo journalctl -u haproxy -f
```

### Debug-Modus

#### Installation mit Debug
```bash
# Debug-Modus aktivieren
export SERVERSH_DEBUG=true
export SERVERSH_VERBOSE_OUTPUT=true

# Installation mit Debug-Output
sudo ./serversh/scripts/install.sh --verbose --debug
```

#### Module-Debug
```bash
# Modul einzeln debuggen
sudo ./serversh/modules/security/ssh.sh validate
sudo ./serversh/modules/container/docker.sh install

# Logs für spezifisches Modul
sudo journalctl -u serversh | grep "ssh_module"
```

### Logging

#### System-Logs
```bash
# ServerSH Service Logs
sudo journalctl -u serversh -f

# Alle relevanten Logs
sudo journalctl -u serversh -u docker -u ssh -u prometheus -f

# Errors only
sudo journalctl -p err -u serversh
```

#### Backup-Logs
```bash
# Backup-Logs
sudo tail -f /var/log/serversh/backup.log

# Disaster Recovery Logs
sudo tail -f /var/log/serversh/disaster-recovery.log
```

#### Cluster-Logs
```bash
# etcd Logs
sudo journalctl -u etcd -f

# HAProxy Logs
sudo tail -f /var/log/haproxy.log

# Cluster Management Logs
sudo tail -f /var/log/serversh/cluster.log
```

## 🧪 Entwicklung

### Module entwickeln

#### Modul-Struktur
```
serversh/modules/category/module_name/
├── module_name.sh          # Haupt-Script
├── config.yaml             # Standard-Konfiguration
├── tests/                  # Tests
│   ├── test_module.sh
│   └── test_integration.sh
└── docs/                   # Dokumentation
    └── module.md
```

#### Modul-Template
```bash
#!/bin/bash

# =============================================================================
# ServerSH Module Template
# =============================================================================

set -euo pipefail

# Source required utilities
source "${SERVERSH_ROOT}/core/utils.sh"
source "${SERVERSH_ROOT}/core/logger.sh"
source "${SERVERSH_ROOT}/core/state.sh"

# Module metadata
MODULE_NAME="category/module_name"
MODULE_VERSION="1.0.0"
MODULE_DESCRIPTION="Module description"
MODULE_DEPENDENCIES=()

# Module functions
validate() {
    log_info "Validating ${MODULE_NAME} configuration"
    # Add validation logic here
}

install() {
    log_info "Installing ${MODULE_NAME}"
    # Add installation logic here
    save_state "${MODULE_NAME}" "installed"
}

uninstall() {
    log_info "Uninstalling ${MODULE_NAME}"
    # Add uninstallation logic here
    save_state "${MODULE_NAME}" "uninstalled"
}

# Execute module operations
case "${1:-}" in
    "validate")
        validate
        ;;
    "install")
        install
        ;;
    "uninstall")
        uninstall
        ;;
    *)
        echo "Usage: $0 {validate|install|uninstall}"
        exit 1
        ;;
esac
```

### Testing

#### Unit-Tests
```bash
# Tests ausführen
./tests/test_core.sh
./tests/test_modules.sh

# Coverage
./tests/run_coverage.sh
```

#### Integration-Tests
```bash
# Full Integration Test
./tests/integration/test_full_installation.sh

# Module-specific Tests
./tests/integration/test_docker_module.sh
./tests/integration/test_backup_module.sh
```

### Contributing

1. **Fork** das Repository
2. **Feature Branch** erstellen: `git checkout -b feature/amazing-feature`
3. **Änderungen** committen: `git commit -m 'Add amazing feature'`
4. **Push** zum Branch: `git push origin feature/amazing-feature`
5. **Pull Request** erstellen

### Code Standards

- **Shell**: Bash 5.0+ compatible
- **Style**: Follow Google Shell Style Guide
- **Documentation**: Markdown with proper headers
- **Testing**: Unit tests for all functions
- **Security**: No hardcoded secrets, proper input validation

## 📄 Lizenz

Dieses Projekt ist unter der MIT Lizenz lizenziert - siehe [LICENSE](LICENSE) Datei für Details.

## 🤝 Contributing

Contributions sind willkommen! Bitte lies [CONTRIBUTING.md](CONTRIBUTING.md) für Details über unseren Code of Conduct und den Contributing-Prozess.

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/sunsideofthedark-lgtm/Serversh/issues)
- **Discussions**: [GitHub Discussions](https://github.com/sunsideofthedark-lgtm/Serversh/discussions)
- **Documentation**: [Wiki](https://github.com/sunsideofthedark-lgtm/Serversh/wiki)

## 🙏 Danksagungen

- Allen Contributoren für ihre wertvollen Beiträge
- Der Open-Source Community für Inspiration und Tools
- Besonderen Dank an alle Tester und Feedback-Geber

---

**ServerSH** - Making Server Management Simple, Secure, and Automated.