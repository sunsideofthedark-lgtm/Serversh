# ServerSH - Technische Spezifikationen

## 🔧 Core-Framework Architektur

### 1. Engine Core (`core/engine.sh`)

**Zuständigkeiten:**
- Modul-Lifecycle Management
- Abhängigkeitsauflösung
- State-Management
- Error-Handling und Recovery

**API-Schnittstelle:**
```bash
# Modul-Management
engine_register_module()     # Modul registrieren
engine_resolve_dependencies() # Abhängigkeiten auflösen
engine_execute_module()      # Modul ausführen
engine_rollback_module()     # Modul zurückrollen

# State-Management
engine_create_checkpoint()   # Prüfpunkt erstellen
engine_restore_checkpoint()  # Prüfpunkt wiederherstellen
engine_get_state()          # Aktuellen Status abrufen
```

### 2. Configuration Manager (`core/config.sh`)

**Funktionen:**
- YAML/JSON Konfigurationsverarbeitung
- Schema-Validierung
- Environment-spezifische Overrides
- Konfigurations-Migration

**Konfigurationshierarchie:**
```
1. Module Defaults (modules/*/config.yaml)
2. Global Defaults (config/default.yaml)
3. Profile Settings (config/profiles/*.yaml)
4. User Config (serversh.yaml)
5. Environment Variables
6. Command Line Arguments
```

### 3. State Manager (`core/state.sh`)

**State-Struktur:**
```json
{
  "version": "1.0.0",
  "timestamp": "2024-01-01T00:00:00Z",
  "modules": {
    "system/update": {
      "status": "completed",
      "checksum": "abc123...",
      "rollback_data": {...}
    }
  },
  "checkpoints": [
    {
      "id": "checkpoint_001",
      "timestamp": "2024-01-01T00:00:00Z",
      "description": "Before docker installation"
    }
  ]
}
```

## 🧩 Modul-Spezifikationen

### Modul-Interface Standard

**Jedes Modul muss folgende Funktionen implementieren:**

```bash
# Metadaten
module_get_name()          # Modul-Name
module_get_version()       # Modul-Version
module_get_description()   # Beschreibung
module_get_dependencies()  # Abhängigkeiten

# Lifecycle
module_validate_config()   # Konfiguration validieren
module_pre_install()       # Vor-Installations-Checks
module_install()          # Haupt-Installation
module_post_install()      # Nach-Installations-Tasks
module_verify()           # Installations-Verifizierung
module_rollback()         # Rollback-Funktionalität
module_cleanup()          # Cleanup bei Fehlern

# Status
module_get_status()       # Installations-Status
module_get_logs()         # Installations-Logs
```

### Modul-Konfigurations-Schema

```yaml
# modules/*/config.yaml
name: "docker"
version: "1.0.0"
description: "Docker Container Platform Installation"
category: "container"

dependencies:
  modules: ["system/update"]
  packages: ["curl", "gnupg"]
  services: []

configuration:
  schema:
    type: "object"
    properties:
      version:
        type: "string"
        enum: ["latest", "stable", "20.10", "23.0"]
        default: "latest"
      networks:
        type: "array"
        items:
          type: "object"
          properties:
            name:
              type: "string"
              pattern: "^[a-zA-Z0-9_-]+$"
            mtu:
              type: "integer"
              minimum: 576
              maximum: 9000
              default: 1500
            ipv6:
              type: "boolean"
              default: false

environment:
  supported_os: ["ubuntu", "debian", "centos", "rhel", "fedora"]
  min_memory: "2GB"
  min_disk: "20GB"

rollback:
  supported: true
  automatic: false
  cleanup_data: false
```

## 🐳 Docker-Modul Spezifikationen

### Docker Installation (`modules/container/docker.sh`)

**Installationsschritte:**
1. **Pre-Checks**
   - OS-Kompatibilität prüfen
   - Virtualisierung prüfen
   - Alte Docker-Installationen entfernen

2. **Repository Setup**
   - GPG-Key importieren
   - Repository hinzufügen
   - Paket-Cache aktualisieren

3. **Paket-Installation**
   - Docker Engine installieren
   - Docker CLI installieren
   - Containerd installieren
   - BuildKit installieren

4. **Konfiguration**
   - Daemon-Konfiguration erstellen
   - User-Group setup
   - Log-Rotation konfigurieren

5. **Post-Installation**
   - Service starten und enablen
   - Hello World Test
   - User zur Gruppe hinzufügen

**Docker Daemon Konfiguration:**
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "default-address-pools": [
    {
      "base": "172.25.0.0/16",
      "size": 24
    }
  ],
  "ipv6": true,
  "fixed-cidr-v6": "2001:db8:1::/64",
  "mtu": 1450,
  "experimental": false,
  "metrics-addr": "127.0.0.1:9323",
  "exec-opts": ["native.cgroupdriver=systemd"]
}
```

### Docker Netzwerke (`modules/container/networks.sh`)

**Netzwerk-Typen:**
- **Bridge Network**: Standard Docker Bridge
- **Custom Bridge**: Benutzerdefinierte Bridge mit MTU/IPv6
- **Overlay Network**: Multi-Host Netzwerke
- **MacVLAN Network**: Direkte Host-Netzwerk-Anbindung

**Netzwerk-Erstellung:**
```bash
docker network create \
  --driver bridge \
  --opt com.docker.network.bridge.name=br-newt \
  --opt com.docker.network.driver.mtu=1450 \
  --opt com.docker.network.bridge.enable_icc=true \
  --opt com.docker.network.bridge.enable_ip_masquerade=true \
  --opt com.docker.network.host_binding_ipv4=0.0.0.0 \
  --ipv6 \
  --subnet=172.25.0.0/16 \
  --gateway=172.25.0.1 \
  --subnet=2001:db8:1::/80 \
  --gateway=2001:db8:1::1 \
  newt_talk
```

## 🔒 Sicherheits-Modul Spezifikationen

### SSH Hardening (`modules/security/ssh.sh`)

**Sicherheitsmaßnahmen:**
1. **Port-Änderung**
   - Dynamische Port-Auswahl
   - Port-Verfügbarkeitsprüfung
   - Firewall-Anpassung

2. **Authentifizierung**
   - Passwort-Auth deaktivieren
   - SSH-Key-Auth erzwingen
   - Pubkey-Accepted-Key-Types einschränken

3. **Zugriffsbeschränkung**
   - Root-Login deaktivieren
   - AllowGroups für SSH-Zugriff
   - IP-Whitelist (optional)

4. **Hardening-Optionen**
   - Protocol 2 only
   - Kex-Algorithmen einschränken
   - MAC-Algorithmen einschränken
   - Ciphers einschränken

**SSH-Konfigurations-Template:**
```
# ServerSH SSH Security Configuration
Port {{ssh_port}}
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowGroups remotessh

# Key Exchange Algorithms
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512

# Ciphers
Ciphers chacha20-poly1305@openssl.com,aes256-gcm@openssl.com

# MACs
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com

# Security Options
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
MaxSessions 10
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitEmptyPasswords no
PermitUserEnvironment no
Compression no
```

### Firewall Konfiguration (`modules/security/firewall.sh`)

**Unterstützte Firewalls:**
- **UFW** (Ubuntu/Debian)
- **firewalld** (RHEL/CentOS/Fedora)
- **iptables** (Fallback)

**Firewall-Regeln-Struktur:**
```yaml
firewall:
  default_policy: "deny"
  rules:
    - name: "SSH"
      port: "{{ssh_port}}"
      protocol: "tcp"
      action: "allow"
      source: "any"
    - name: "HTTP"
      port: "80"
      protocol: "tcp"
      action: "allow"
      source: "any"
    - name: "HTTPS"
      port: "443"
      protocol: "tcp"
      action: "allow"
      source: "any"
    - name: "Pangolin_VPN"
      port: "51820"
      protocol: "udp"
      action: "allow"
      source: "any"
```

## 📊 Monitoring-Modul Spezifikationen

### Prometheus Node Exporter (`modules/monitoring/prometheus.sh`)

**Metriken-Kategorien:**
- **System-Metriken**: CPU, Memory, Disk, Network
- **Filesystem-Metriken**: Disk Usage, I/O
- **Network-Metriken**: Interface-Traffic, Connections
- **Process-Metriken**: Process Count, States

**Service-Konfiguration:**
```ini
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter \
  --collector.cpu \
  --collector.diskstats \
  --collector.filesystem \
  --collector.meminfo \
  --collector.netdev \
  --collector.time \
  --web.listen-address=0.0.0.0:9100 \
  --web.telemetry-path=/metrics \
  --no-collector.ipvs \
  --no-collector.mdadm \
  --no-collector.nfs \
  --no-collector.nfsd \
  --no-collector.wifi \
  --no-collector.zfs

[Install]
WantedBy=multi-user.target
```

## 🔄 State-Management Spezifikationen

### Checkpoint-System

**Checkpoint-Struktur:**
```json
{
  "checkpoint_id": "checkpoint_001",
  "timestamp": "2024-01-01T00:00:00Z",
  "description": "Before Docker installation",
  "modules_completed": ["system/update", "security/ssh", "security/firewall"],
  "system_state": {
    "packages": {...},
    "services": {...},
    "files": [...],
    "users": [...]
  },
  "rollback_commands": [
    "systemctl stop docker",
    "apt-get remove -y docker-ce docker-ce-cli",
    "usermod -G docker $USER"
  ]
}
```

### Recovery-Mechanismen

**Automatische Recovery:**
1. **Fehler-Erkennung**: Modul-Installation schlägt fehl
2. **State-Analyse**: Letzten gültigen Checkpoint finden
3. **Rollback-Initiierung**: Automatische Wiederherstellung
4. **Fehler-Analyse**: Ursache des Fehlers protokollieren
5. **Benachrichtigung**: Admin über Problem informieren

**Manuelle Recovery:**
```bash
# Status anzeigen
serversh status

# Letzten Checkpoint wiederherstellen
serversh rollback latest

# Spezifischen Checkpoint wiederherstellen
serversh rollback checkpoint_001

# Installation fortsetzen
serversh continue

# Vollständige Neustart
serversh reset
```

## 🧪 Testing-Framework Spezifikationen

### Unit-Tests

**Test-Struktur:**
```bash
# tests/unit/test_module_docker.sh
#!/bin/bash

test_docker_installation() {
  # Testet Docker-Installation
}

test_docker_configuration() {
  # Testet Docker-Konfiguration
}

test_docker_network_creation() {
  # Testet Docker-Netzwerk-Erstellung
}
```

### Integration-Tests

**Test-Szenarien:**
- **Full Installation**: Komplette Server-Installation
- **Partial Installation**: Nur bestimmte Module
- **Rollback Scenarios**: Fehler und Recovery
- **Update Scenarios**: Modul-Updates

### E2E-Tests

**Automatisierte Test-Umgebung:**
- **VM-Setup**: Automatische VM-Erstellung
- **Multi-OS Testing**: Tests auf verschiedenen Distributionen
- **Performance Testing**: Installationszeiten messen
- **Security Testing**: Sicherheits-Scan der Installation

## 📈 Performance-Optimierungen

### Parallele Ausführung

**Abhängigkeits-Graph:**
```
system/update → security/users → security/ssh → security/firewall
             ↘ container/docker → container/networks
                           ↘ monitoring/prometheus
```

**Parallele Installation:**
- Module ohne Abhängigkeiten können parallel installiert werden
- Intelligente Abhängigkeitsauflösung
- Resource-Management (CPU, Memory, I/O)

### Caching-Strategien

**Download-Cache:**
- Pakete einmal herunterladen
- Lokaler Mirror für Downloads
- Integritäts-Prüfung (Checksums)

**Konfigurations-Cache:**
- Geparste Konfigurationen cachen
- Template-Rendering optimieren
- Validierungsergebnisse speichern

## 🚀 Deployment-Spezifikationen

### Installations-Medium

**Single Binary:**
```bash
# Download
curl -fsSL https://get.serversh.io | bash

# Alternative: Binary Download
wget https://github.com/serversh/serversh/releases/latest/download/serversh-linux-amd64
chmod +x serversh-linux-amd64
sudo ./serversh-linux-amd64 install
```

**Package-Repository:**
- **APT Repository** (Debian/Ubuntu)
- **YUM Repository** (RHEL/CentOS)
- **Pacman Repository** (Arch Linux)

### Update-Mechanismus

**Self-Update:**
```bash
# Check for updates
serversh check-update

# Update framework
serversh update

# Update modules
serversh update-modules

# Full system update
serversh update-all
```

**Rolling Updates:**
- Modul-Updates ohne Ausfallzeiten
- Konfigurations-Migration
- Automated Testing vor Deployment

---

*Diese technischen Spezifikationen dienen als detaillierte Grundlage für die Implementierung des ServerSH Frameworks. Sie definieren die Architektur, Schnittstellen und Technologien, die für die Entwicklung verwendet werden sollen.*