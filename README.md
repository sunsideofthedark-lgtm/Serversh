# ServerSH - Simple Server Management

🚀 **One Script, One Config, Complete Server Management**

ServerSH ist ein modulares Server-Management-System, das komplexe Server-Setups durch eine einzige Konfigurationsdatei und ein einziges Skript vereinfacht.

## ✨ Hauptmerkmale

- 🚀 **Ein-Klick Installation**: `./cli.sh install`
- 🌐 **Web-Interface**: Visuelle Server-Verwaltung
- 🔑 **SSH Key Management**: Multi-Format Downloads
- 🐳 **Docker Integration**: Optimierte Container-Verwaltung
- 📊 **Monitoring**: Prometheus + Node Exporter
- 🔄 **Backup & Recovery**: Vollständige Backup-Lösung
- 🔒 **Security-First**: SSH-Hardening, Firewall, Fail2ban
- 📱 **VPN Ready**: Tailscale Integration

## 🚀 Schnellstart

### Methode 1: CLI Installation (Empfohlen)
```bash
# Klone das Repository
git clone https://github.com/sunsideofthedark-lgtm/Serversh.git
cd Serversh

# Interaktive Installation
./cli.sh install
```

### Methode 2: Web Interface
```bash
# Installiere nur Web UI
./cli.sh install-web

# Oder alles mit Web UI
./cli.sh install --with-web
```

### Methode 3: Automatisch
```bash
# Automatische Installation mit Standard-Konfiguration
./cli.sh install --auto

# Mit Konfigurationsprofil
./cli.sh install --profile=production
```

## 📋 Inhaltsverzeichnis

- [Installation](#installation)
- [Konfiguration](#konfiguration)
- [Web Interface](#web-interface)
- [CLI Befehle](#cli-befehle)
- [Profile](#profile)
- [Beispiele](#beispiele)

## 🛠️ Installation

### Systemanforderungen
- **OS**: Ubuntu 18.04+, Debian 10+, CentOS 7+, RHEL 7+, Fedora 30+, Arch Linux
- **RAM**: Mindestens 2 GB
- **Speicher**: Mindestens 10 GB frei
- **Zugriff**: Root-Rechte

### Installationsschritte

1. **Repository klonen**
   ```bash
   git clone https://github.com/sunsideofthedark-lgtm/Serversh.git
   cd Serversh
   ```

2. **Installation starten**
   ```bash
   # Interaktive Installation
   ./cli.sh install

   # Oder automatische Installation
   ./cli.sh install --auto
   ```

3. **Fertig!** 🎉
   ```bash
   # Web Interface: http://deine-server-ip:8080
   # Login mit deinen Root-Daten
   ```

## ⚙️ Konfiguration

Die gesamte Konfiguration erfolgt über die `.env` Datei:

```bash
# Kopiere Vorlage
cp .env.example .env

# Konfiguriere deine Einstellungen
nano .env
```

### Wichtigste Einstellungen

```bash
# System-Konfiguration
SERVERSH_HOSTNAME=myserver
SERVERSH_USERNAME=admin
SERVERSH_USER_PASSWORD=SecurePassword123!

# SSH-Konfiguration
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true

# Docker-Konfiguration
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DOCKER_INSTALL_COMPOSE=true

# Web UI
SERVERSH_WEB_UI_ENABLE=true
SERVERSH_WEB_UI_PORT=8080

# Monitoring
SERVERSH_PROMETHEUS_ENABLE=true

# Backup
SERVERSH_BACKUP_ENABLE=true
```

## 🌐 Web Interface

Nach der Installation erreichst du das Web Interface unter:

```
http://deine-server-ip:8080
```

**Login mit Root-Credentials**

### Features
- 📊 **Dashboard**: System-Überwachung und Ressourcen-Nutzung
- ⚙️ **Konfiguration**: Visuelle Konfiguration aller Einstellungen
- 📦 **Module Management**: Installiere und verwalte Module
- 🔑 **SSH Keys**: Generiere und lade SSH Keys herunter
- 💾 **Backup Management**: Erstelle und verwalte Backups

## 🔧 CLI Befehle

### Grundlegende Befehle
```bash
# Installation
./cli.sh install                    # Interaktive Installation
./cli.sh install --auto             # Automatische Installation
./cli.sh install --profile=standard  # Mit Profil

# Web UI Management
./cli.sh install-web                 # Nur Web UI installieren
./cli.sh web start                   # Web UI starten
./cli.sh web status                  # Web UI Status

# System Management
./cli.sh status                      # System-Status
./cli.sh update                      # System aktualisieren
./cli.sh backup create               # Backup erstellen
./cli.sh config                      # Konfiguration anzeigen

# Module Management
./cli.sh module list                 # Module auflisten
./cli.sh module install docker       # Modul installieren
./cli.sh module status prometheus     # Modul-Status
```

### Erweiterte Befehle
```bash
# Backup Management
./cli.sh backup create full
./cli.sh backup restore /backup/full/date /target
./cli.sh backup list
./cli.sh backup schedule

# SSH Management
./cli.sh ssh keys generate
./cli.sh ssh keys list
./cli.sh ssh keys download openssh

# Multi-Server (falls installiert)
./cli.sh cluster init
./cli.sh cluster status
./cli.sh cluster join --token=TOKEN
```

## 📋 Profile

### Available Profiles
- **minimal**: Basic system + SSH + Docker
- **standard**: Full production setup with monitoring
- **full**: Complete setup with all features
- **development**: Development tools and utilities

### Profile verwenden
```bash
# Mit Profil installieren
./cli.sh install --profile=standard

# Profil als .env erstellen
./cli.sh create-profile production
```

## 📚 Beispiele

### Minimal Setup (Development)
```bash
./cli.sh install --profile=minimal
```
*Installiert: System, SSH, Docker*

### Standard Setup (Production)
```bash
./cli.sh install --profile=standard
```
*Installiert: System, SSH, Docker, Monitoring, Firewall, Web UI*

### Full Setup (Complete)
```bash
./cli.sh install --profile=full
```
*Installiert: Alle Features inklusive Cluster, Advanced Backup, etc.*

### Custom Configuration
```bash
# .env Datei anpassen
nano .env

# Installation mit Custom Config
./cli.sh install --env=.env
```

## 🔧 Manuelle Konfiguration

### SSH Keys generieren
```bash
# Generiere neue SSH Keys
./cli.sh ssh keys generate

# Liste vorhandene Keys
./cli.sh ssh keys list

# Lade Key herunter
./cli.sh ssh keys download openssh
```

### Backup erstellen
```bash
# Vollständiges Backup
./cli.sh backup create full

# Inkrementelles Backup
./cli.sh backup create incremental

# Backup Schedule einrichten
./cli.sh backup schedule
```

### Web UI Management
```bash
# Web UI Status
./cli.sh web status

# Web UI Logs
./cli.sh web logs

# Web UI neu starten
./cli.sh web restart
```

## 🛠️ Module

### Available Modules
```bash
# System Module
system/update          # System Updates
system/hostname        # Hostname Konfiguration

# Security Module
security/users          # Benutzer-Management
security/ssh            # SSH Konfiguration
security/firewall       # Firewall-Konfiguration

# Application Module
container/docker       # Docker Installation
monitoring/prometheus   # Prometheus Monitoring
backup/backup_recovery # Backup & Recovery

# Optional Module
applications/optional_software  # Zusätzliche Software
webui/webui                    # Web Interface
```

### Module Management
```bash
# Module installieren
./cli.sh module install docker
./cli.sh module install prometheus

# Module-Status prüfen
./cli.sh module status docker

# Module deinstallieren
./cli.sh module uninstall docker
```

## 🔒 Sicherheit

### SSH Security
```bash
# SSH-Konfiguration
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_SSH_PASSWORD_AUTHENTICATION=false
```

### Firewall
```bash
# Firewall aktivieren
SERVERSH_FIREWALL_ENABLE=true
SERVERSH_FIREWALL_ALLOWED_PORTS="80/tcp,443/tcp"
```

### Monitoring
```bash
# System-Monitoring
SERVERSH_PROMETHEUS_ENABLE=true
SERVERSH_NODE_EXPORTER_ENABLE=true
```

## 📊 Monitoring

### System-Überwachung
- **Prometheus**: Metriken-Sammlung
- **Node Exporter**: System-Metriken
- **Web UI**: Visuelles Dashboard
- **Alerts**: E-Mail-Benachrichtigungen

### Zugriffe nach Installation
```bash
# Web Interface
http://deine-server-ip:8080

# Prometheus
http://deine-server-ip:9090

# Node Exporter
http://deine-server-ip:9100/metrics
```

## 💾 Backup & Recovery

### Backup-Strategien
- **Full Backup**: Vollständiges System-Backup
- **Incremental Backup**: Nur Änderungen seit letztem Backup
- **Automated Backup**: Zeitgesteuerte Backups
- **Remote Backup**: Backup zu externem Speicher

### Backup Management
```bash
# Backup erstellen
./cli.sh backup create full

# Backup wiederherstellen
./cli.sh backup restore /backup/date /target

# Backup Schedule einrichten
./cli.sh backup schedule
```

## 🐚 Docker Integration

### Docker-Netzwerk (MTU 1450 für Tailscale)
```bash
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DOCKER_INSTALL_COMPOSE=true
SERVERSH_DOCKER_NETWORK_MTU=1450
SERVERSH_DOCKER_IPV6=true
```

### Nach Installation
```bash
# Docker-Status prüfen
docker ps
docker network ls
docker network inspect newt_talk
```

## 📱 VPN Integration (Tailscale)

### Konfiguration
```bash
SERVERSH_INSTALL_TAILSCALE=true
SERVERSH_TAILSCALE_SSH=true
SERVERSH_TAILSCALE_MAGICDNS=true
```

### Nach Installation
```bash
# Tailscale verbinden
sudo tailscale up --ssh --authkey=YOUR_AUTHKEY

# Status prüfen
tailscale status
```

## 🐛 Troubleshooting

### Häufige Probleme
```bash
# System-Status prüfen
./cli.sh status

# Logs anzeigen
./cli.sh logs

# Web UI Probleme
./cli.sh web status
./cli.sh web logs

# SSH Probleme
./cli.sh module status security/ssh

# Docker Probleme
./cli.sh module status container/docker
```

### Diagnose
```bash
# Vollständige Diagnose
./cli.sh diagnose

# Module-Status
./cli.sh module list
./cli.sh module status
```

## 📖 Dokumentation

### Ausführliche Dokumentation
- **Installation Guide**: Vollständige Installationsanleitung
- **User Guide**: Detaillierte Benutzeranleitung
- **API Reference**: API-Dokumentation für Entwickler
- **Module Guide**: Modul-Entwicklungs-Guide

### Community
- **GitHub Issues**: [github.com/sunsideofthedark-lgtm/Serversh/issues](https://github.com/sunsideofthedark-lgtm/Serversh/issues)
- **Discussions**: [github.com/sunsideofthedark-lgtm/Serversh/discussions](https://github.com/sunsideofthedark-lgtm/Serversh/discussions)

## 🤝 Contributing

1. **Fork** das Repository
2. **Feature Branch** erstellen: `git checkout -b feature/amazing-feature`
3. **Commits** machen: `git commit -m 'Add amazing feature'`
4. **Push** zum Branch: `git push origin feature/amazing-feature`
5. **Pull Request** erstellen

## 📄 Lizenz

Dieses Projekt ist unter der MIT Lizenz lizenziert - siehe [LICENSE](LICENSE) Datei für Details.

---

**ServerSH** - Making Server Management Simple, Secure, and Automated. 🚀

*Ein Projekt von der Community für die Community.*