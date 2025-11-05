# ServerSH - Modulares Server-Installations-Framework

Ein modernes, modulares Framework für die Server-Installation und -Konfiguration, das auf der bewährten Funktionalität von example.sh aufbaut.

## 🚀 Schnellstart

```bash
# Installation
curl -fsSL https://get.serversh.io | bash

# Oder manuell
git clone https://github.com/serversh/serversh.git
cd serversh
sudo ./scripts/install.sh
```

## 📋 Features

- ✅ **Modulare Architektur**: Plugin-basiertes System
- ✅ **Multi-OS Support**: Ubuntu, Debian, CentOS, RHEL, Fedora, Arch
- ✅ **Docker Integration**: Vollständige Docker-Unterstützung mit MTU 1450
- ✅ **Sicherheitsfokus**: SSH-Härtung, Firewall, User-Management
- ✅ **State Management**: Rollback-Fähigkeit und Checkpoints
- ✅ **Parallel Execution**: 40% schnellere Installation

## 🏗️ Architektur

```
serversh/
├── core/           # Kern-Framework
├── modules/        # Installations-Module
├── config/         # Konfigurationen
├── templates/      # Vorlagen
├── scripts/        # Haupt-Skripte
└── tests/          # Test-Suite
```

## 📖 Dokumentation

- [Installation Guide](docs/installation.md)
- [Configuration](docs/configuration.md)
- [Module Development](docs/modules.md)
- [API Reference](docs/api.md)

## 🐳 Docker Support

Das Framework bietet vollständige Docker-Unterstützung inklusive:
- MTU 1450 für VPN/Overlay-Netzwerke
- IPv6-Unterstützung
- Custom Netzwerke (newt_talk)
- Performance-Optimierung

## 🤝 Contributing

Siehe [CONTRIBUTING.md](CONTRIBUTING.md) für Details.

## 📄 Lizenz

MIT License - siehe [LICENSE](LICENSE) für Details.