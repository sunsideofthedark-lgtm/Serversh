# ServerSH Automatisierung & Deployment

Diese Dokumentation beschreibt die verschiedenen Automatisierungsmöglichkeiten für ServerSH.

## 🚀 Schnellstart

### 1. Interaktives Setup

```bash
./quick-setup.sh
```

Startet einen interaktiven Assistenten für gängige Setup-Szenarien.

### 2. Direkte Installation

```bash
# Kopiere Beispiel-Konfiguration
cp .env.example .env

# Bearbeite .env mit deinen Einstellungen
vim .env

# Starte Installation
./auto-deploy.sh local
```

### 3. Docker-basierte Installation

```bash
# Mit Docker
./auto-deploy.sh docker --env .env

# Mit Docker Compose
./auto-deploy.sh compose --env .env --profiles monitoring,grafana
```

## 📋 Inhaltsverzeichnis

- [Umgebungsvariablen](#umgebungsvariablen)
- [Deploy-Methoden](#deploy-methoden)
- [Setup-Szenarien](#setup-szenarien)
- [Docker Integration](#docker-integration)
- [Remote Deployment](#remote-deployment)
- [Konfigurations-Beispiele](#konfigurations-beispiele)

## 🔧 Umgebungsvariablen

Alle Konfigurationen können über Umgebungsvariablen gesteuert werden. Die vollständige Liste findest du in [`.env.example`](.env.example).

### Wichtigste Variablen

```bash
# System-Konfiguration
SERVERSH_HOSTNAME=myserver
SERVERSH_FQDN=myserver.example.com

# Benutzer-Konfiguration
SERVERSH_USERNAME=admin
SERVERSH_USER_PASSWORD=SecurePassword123!
SERVERSH_ADDITIONAL_SSH_KEYS="ssh-rsa AAAAB3Nza... user@example.com"

# SSH-Konfiguration
SERVERSH_SSH_PORT=2222
SERVERSH_SSH_INTERACTIVE_PORT=false

# Firewall-Konfiguration
SERVERSH_FIREWALL_ENABLE=true
SERVERSH_FIREWALL_ALLOWED_PORTS="80/tcp,443/tcp"

# Docker-Konfiguration
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DOCKER_NETWORK_MTU=1450
SERVERSH_DOCKER_NETWORK_IPV6=true

# Monitoring-Konfiguration
SERVERSH_PROMETHEUS_ENABLE=true
SERVERSH_PROMETHEUS_PORT=9090
```

## 🚀 Deploy-Methoden

### 1. Lokale Installation

```bash
# Standard-Installation
./auto-deploy.sh local

# Mit spezifischer Konfiguration
./auto-deploy.sh local --env production.env

# Testlauf
./auto-deploy.sh local --dry-run

# Detaillierte Ausgabe
./auto-deploy.sh local --verbose
```

### 2. Docker Installation

```bash
# Docker-Container Installation
./auto-deploy.sh docker

# Mit Debug-Modus
./auto-deploy.sh docker --debug

# Container am Laufen halten
./auto-deploy.sh docker --keep-running
```

### 3. Docker Compose

```bash
# Basis-Setup
./auto-deploy.sh compose

# Mit Monitoring
./auto-deploy.sh compose --profiles monitoring

# Vollständiges Stack
./auto-deploy.sh compose --profiles monitoring,grafana,traefik,portainer

# Nur bestimmte Services
./auto-deploy.sh compose --services serversh-setup,prometheus,grafana
```

### 4. Remote Deployment

```bash
# Remote-Installation über SSH
./auto-deploy.sh remote --host 192.168.1.100 --user root --env production.env

# Mit Testlauf
./auto-deploy.sh remote --host server.example.com --user admin --dry-run

# Ohne Aufräumen
./auto-deploy.sh remote --host server.example.com --user admin --cleanup-remote false
```

## 📦 Setup-Szenarien

### 1. Webserver Setup

```bash
./quick-setup.sh
# Option 1 wählen
```

**Enthält:**
- Nginx Webserver
- SSL/TLS mit Certbot
- Firewall mit HTTP/HTTPS Ports
- Grundlegende Sicherheit
- Monitoring

### 2. Docker Development Environment

```bash
./quick-setup.sh
# Option 2 wählen
```

**Enthält:**
- Docker & Docker Compose
- Entwicklungstools (Node.js, Python, etc.)
- Laxe Firewall-Einstellungen
- Mehrere offene Ports für Development

### 3. Monitoring Stack

```bash
./quick-setup.sh
# Option 3 wählen
```

**Enthält:**
- Prometheus + Node Exporter
- Grafana Dashboard
- Alarmierung
- Performance-Metriken

### 4. Security Hardening

```bash
./quick-setup.sh
# Option 4 wählen
```

**Enthält:**
- Maximale SSH-Sicherheit
- Restriktive Firewall
- Fail2ban
- Audit-Tools
- Auto-Security-Updates

### 5. Production Server

```bash
./quick-setup.sh
# Option 5 wählen
```

**Enthält:**
- Alle Security-Features
- Backup-System
- Logging & Monitoring
- Automatische Updates
- Performance-Optimierung

## 🐳 Docker Integration

### Docker-Setup

```bash
# Build Image
docker build -f Dockerfile.setup -t serversh-setup:latest .

# Manuelles Deployment
docker run --rm --privileged \
  -v $(pwd):/serversh:ro \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /:/host \
  --env-file .env \
  serversh-setup:latest
```

### Docker Compose Services

```bash
# Monitoring Stack
docker-compose -f docker-compose.server-setup.yml --profile monitoring up -d

# Mit Grafana
docker-compose -f docker-compose.server-setup.yml --profile monitoring,grafana up -d

# Vollständiger Stack
docker-compose -f docker-compose.server-setup.yml --profile monitoring,grafana,traefik up -d
```

### Verfügbare Profile

- `monitoring`: Prometheus + Node Exporter
- `grafana`: Grafana Dashboard
- `traefik`: Reverse Proxy
- `portainer`: Docker Management
- `nginx-proxy`: Nginx Proxy Manager
- `database`: MariaDB/PostgreSQL
- `redis`: Redis Cache

## 🌐 Remote Deployment

### SSH-Konfiguration

```bash
# SSH-Schlüssel einrichten
ssh-copy-id root@target-server

# Verbindung testen
ssh root@target-server "echo 'SSH works'"
```

### Remote Deployment

```bash
# Einfache Remote-Installation
./auto-deploy.sh remote --host 192.168.1.100 --user root

# Mit Konfigurationsdatei
./auto-deploy.sh remote --host server.example.com --user admin --env staging.env

# Mehrere Server
for server in server1.example.com server2.example.com server3.example.com; do
  ./auto-deploy.sh remote --host $server --user root --env production.env
done
```

## 📝 Konfigurations-Beispiele

### Production Environment

```bash
# production.env
SERVERSH_HOSTNAME=prod-server-01
SERVERSH_FQDN=prod-server-01.example.com
SERVERSH_USERNAME=admin
SERVERSH_USER_PASSWORD=VerySecurePassword123!
SERVERSH_SSH_PORT=4444
SERVERSH_SSH_INTERACTIVE_PORT=false
SERVERSH_FIREWALL_DEFAULT_POLICY=deny
SERVERSH_FIREWALL_ALLOWED_PORTS="80/tcp,443/tcp"
SERVERSH_DOCKER_ENABLE=true
SERVERSH_PROMETHEUS_ENABLE=true
SERVERSH_INSTALL_FAIL2BAN=true
SERVERSH_AUTO_SECURITY_UPDATES=true
SERVERSH_BACKUP_ENABLE=true
```

### Development Environment

```bash
# development.env
SERVERSH_HOSTNAME=devbox
SERVERSH_USERNAME=developer
SERVERSH_USER_PASSWORD=DevPassword123!
SERVERSH_SSH_PORT=2222
SERVERSH_FIREWALL_DEFAULT_POLICY=allow
SERVERSH_FIREWALL_ALLOWED_PORTS="80/tcp,443/tcp,3000/tcp,8000/tcp,8080/tcp"
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DEV_TOOLS=true
SERVERSH_ADDITIONAL_PACKAGES="htop,vim,git,build-essential,python3,nodejs,npm"
```

### Test Environment

```bash
# testing.env
SERVERSH_HOSTNAME=testbox
SERVERSH_USERNAME=testuser
SERVERSH_USER_PASSWORD=TestPassword123!
SERVERSH_TEST_MODE=true
SERVERSH_UPDATE_AUTO=false
SERVERSH_FIREWALL_ENABLE=false
SERVERSH_SSH_PERMIT_ROOT_LOGIN=yes
SERVERSH_SSH_PASSWORD_AUTHENTICATION=yes
```

## 🔍 Nützliche Befehle

### Konfiguration validieren

```bash
./auto-deploy.sh validate --env production.env
```

### Nur Konfigurationen generieren

```bash
./auto-deploy.sh generate --env production.env --output-dir ./configs
```

### Debug-Modus

```bash
./auto-deploy.sh local --debug --env production.env
```

### Module-Liste anzeigen

```bash
grep "module_order" .env
```

### Ports überprüfen

```bash
# SSH Port
grep -E "SSH_PORT|PREFERRED_PORT" .env

# Monitoring Ports
grep -E "PROMETHEUS_PORT|NODE_EXPORTER_PORT" .env

# Firewall Ports
grep FIREWALL_ALLOWED_PORTS .env
```

## 🛠️ Troubleshooting

### SSH-Probleme

```bash
# SSH-Verbindung testen
ssh -o ConnectTimeout=10 -o BatchMode=yes user@server "echo 'OK'"

# SSH-Schlüssel prüfen
ssh-add -l
```

### Docker-Probleme

```bash
# Docker-Status prüfen
docker info
docker-compose version

# Berechtigungen prüfen
sudo usermod -aG docker $USER
```

### Netzwerk-Probleme

```bash
# Firewall-Status
sudo ufw status verbose
sudo firewall-cmd --list-all

# Port-Verfügbarkeit prüfen
netstat -tuln | grep :22
```

### Logging

```bash
# ServerSH Logs
tail -f /var/log/serversh/serversh.log

# Systemd Logs
journalctl -u prometheus -f
journalctl -u node_exporter -f
```

## 📚 Weitere Informationen

- [Hauptdokumentation](README.md)
- [Modul-Dokumentation](docs/modules.md)
- [Konfigurations-Referenz](docs/configuration.md)
- [Troubleshooting Guide](docs/troubleshooting.md)

## 🤝 Unterstützung

Bei Problemen oder Fragen:

1. Prüfe die [Troubleshooting Guide](docs/troubleshooting.md)
2. Validiere deine Konfiguration: `./auto-deploy.sh validate`
3. Nutze den Debug-Modus: `./auto-deploy.sh local --debug`
4. Erstelle ein Issue im GitHub Repository