# ServerSH Installation Guide

This guide provides detailed installation instructions for ServerSH on various Linux distributions.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Supported Systems](#supported-systems)
- [Installation Methods](#installation-methods)
- [Configuration](#configuration)
- [Post-Installation](#post-installation)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements

- **OS**: Linux (Ubuntu 18.04+, Debian 10+, CentOS 7+, RHEL 7+, Fedora 30+, Arch Linux, openSUSE Leap 15.4+)
- **RAM**: Minimum 2 GB, Recommended 4 GB+
- **Storage**: Minimum 10 GB free space
- **Network**: Internet connection for package installation
- **Access**: Root or sudo privileges

### Required Packages

ServerSH automatically installs dependencies, but these packages should be available:

```bash
# Ubuntu/Debian
apt update && apt install -y curl wget git gnupg

# CentOS/RHEL
yum update && yum install -y curl wget git gnupg

# Fedora
dnf update && dnf install -y curl wget git gnupg

# Arch Linux
pacman -Syu curl wget git gnupg
```

## Supported Systems

### Linux Distributions

| Distribution | Versions | Package Manager | Support Level |
|--------------|----------|----------------|---------------|
| Ubuntu | 18.04 LTS, 20.04 LTS, 22.04 LTS | apt | ✅ Full |
| Debian | 10, 11, 12 | apt | ✅ Full |
| CentOS | 7, 8, 9 | yum/dnf | ✅ Full |
| RHEL | 7, 8, 9 | yum/dnf | ✅ Full |
| Fedora | 35+ | dnf | ✅ Full |
| Arch Linux | Rolling | pacman | ✅ Full |
| openSUSE | Leap 15.4+ | zypper | ✅ Full |

### Architecture Support

- **x86_64**: Full support
- **ARM64**: Experimental support
- **ARM32**: Limited support

## Installation Methods

### Method 1: Quick Setup (Recommended)

The quickest way to get ServerSH running with interactive configuration.

```bash
# Clone the repository
git clone https://github.com/sunsideofthedark-lgtm/Serversh.git
cd Serversh

# Run the interactive setup
./quick-setup.sh
```

The quick setup will:
- Detect your system and dependencies
- Guide you through configuration
- Install selected modules
- Provide access credentials

### Method 2: Environment-Based Installation

For automated or reproducible installations using environment variables.

```bash
# Clone the repository
git clone https://github.com/sunsideofthedark-lgtm/Serversh.git
cd Serversh

# Copy and configure environment file
cp .env.example .env
nano .env

# Run automated installation
sudo ./serversh/scripts/install-from-env.sh
```

### Method 3: Manual Installation

For complete control over the installation process.

```bash
# Clone the repository
git clone https://github.com/sunsideofthedark-lgtm/Serversh.git
cd Serversh

# Create configuration file
cat > serversh/configs/custom.yaml << EOF
system/hostname:
  hostname: "myserver"

security/users:
  create_user: true
  username: "admin"
  password: "SecurePassword123!"

container/docker:
  enable: true
EOF

# Run installation with custom config
sudo ./serversh/scripts/install.sh --config=serversh/configs/custom.yaml
```

### Method 4: One-Line Installation

Install ServerSH directly from the internet:

```bash
# Using curl
curl -fsSL https://raw.githubusercontent.com/sunsideofthedark-lgtm/Serversh/main/install.sh | bash

# Using wget
wget -qO- https://raw.githubusercontent.com/sunsideofthedark-lgtm/Serversh/main/install.sh | bash
```

## Configuration

### Environment Variables

Create a `.env` file with your configuration:

```bash
# System Configuration
SERVERSH_HOSTNAME=myserver
SERVERSH_USERNAME=admin
SERVERSH_USER_PASSWORD=SecurePassword123!

# SSH Configuration
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_SSH_PREFERRED_PORT=2222

# Docker Configuration
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DOCKER_INSTALL_COMPOSE=true

# Monitoring
SERVERSH_PROMETHEUS_ENABLE=true

# Backup
SERVERSH_BACKUP_ENABLE=true
SERVERSH_BACKUP_BASE_DIR=/backup
```

### YAML Configuration

Alternative configuration using YAML:

```yaml
# serversh/configs/main.yaml
system/hostname:
  hostname: "myserver"
  fqdn: "myserver.example.com"

security/users:
  create_user: true
  username: "admin"
  password: "SecurePassword123!"
  ssh_key: true
  sudo: true

security/ssh:
  enable: true
  interactive_port: true
  preferred_port: 2222

container/docker:
  enable: true
  install_compose: true
  network_config:
    mtu: 1450
    ipv6: true

monitoring/prometheus:
  enable: true
  prometheus_port: 9090
```

### Module Selection

Choose which modules to install:

```bash
# Install specific modules
sudo ./serversh/scripts/install.sh \
  --modules=system/update,system/hostname,security/users,security/ssh,container/docker

# Install all modules
sudo ./serversh/scripts/install.sh --all-modules

# Install with custom configuration
sudo ./serversh/scripts/install.sh \
  --config=my-config.yaml \
  --modules=security/ssh,container/docker
```

## Post-Installation

### Verification

Verify that ServerSH was installed correctly:

```bash
# Check installation status
sudo ./serversh/scripts/status.sh

# Check module status
sudo ./serversh/scripts/install.sh --status

# View logs
sudo journalctl -u serversh -f
```

### Access Information

After installation, you'll receive access information:

```bash
# SSH Access (example)
ssh admin@your-server-ip -p 2222

# Web Services
- Prometheus: http://your-server-ip:9090
- Node Exporter: http://your-server-ip:9100

# Docker
docker ps
docker network ls
```

### First Steps

1. **Test SSH Access**
   ```bash
   ssh admin@your-server-ip -p 2222
   ```

2. **Verify Docker**
   ```bash
   docker run hello-world
   ```

3. **Check Monitoring**
   ```bash
   curl http://localhost:9100/metrics
   ```

4. **Configure Backups**
   ```bash
   sudo ./serversh/scripts/backupctl.sh create full
   ```

### Service Management

Manage ServerSH services:

```bash
# Start services
sudo systemctl start serversh
sudo systemctl enable serversh

# Check status
sudo systemctl status serversh

# Restart services
sudo systemctl restart serversh

# View logs
sudo journalctl -u serversh -f
```

## Troubleshooting

### Common Issues

#### Permission Denied
```bash
# Ensure proper permissions
chmod +x ./serversh/scripts/*.sh
sudo chown -R $USER:$USER ./serversh
```

#### Missing Dependencies
```bash
# Install missing packages
sudo ./serversh/scripts/install.sh --install-deps

# Check system compatibility
./serversh/scripts/system-check.sh
```

#### Port Conflicts
```bash
# Check port usage
sudo netstat -tlnp | grep :22
sudo netstat -tlnp | grep :2222

# Find available ports
sudo ./serversh/scripts/port-scanner.sh --ranges=2000-2999
```

#### Docker Issues
```bash
# Check Docker service
sudo systemctl status docker

# Test Docker installation
docker run hello-world

# Check Docker network
docker network inspect newt_talk
```

#### SSH Connection Issues
```bash
# Check SSH service
sudo systemctl status ssh

# Check SSH configuration
sudo sshd -t

# Test SSH connection
ssh -v admin@localhost -p 2222
```

### Debug Mode

Enable debug mode for troubleshooting:

```bash
# Enable debug logging
export SERVERSH_DEBUG=true
export SERVERSH_VERBOSE_OUTPUT=true

# Run installation with debug
sudo ./serversh/scripts/install.sh --debug --verbose

# Check logs
sudo journalctl -u serversh -f --priority=debug
```

### Log Files

Check various log files:

```bash
# System logs
sudo journalctl -u serversh -f
sudo journalctl -u docker -f
sudo journalctl -u ssh -f

# Application logs
sudo tail -f /var/log/serversh/installation.log
sudo tail -f /var/log/serversh/backup.log

# Module-specific logs
sudo journalctl -u serversh | grep "docker_module"
```

### Getting Help

If you encounter issues:

1. **Check Documentation**: Read the full documentation at [docs/](../)
2. **Search Issues**: Check [GitHub Issues](https://github.com/sunsideofthedark-lgtm/Serversh/issues)
3. **Create Debug Log**:
   ```bash
   sudo ./serversh/scripts/install.sh --debug > debug.log 2>&1
   ```
4. **Report Issue**: Create a new issue with your system information and debug logs

### System Information

Collect system information for support:

```bash
# Generate system report
sudo ./serversh/scripts/system-info.sh

# Manual collection
uname -a
cat /etc/os-release
docker --version
python3 --version
```

## Next Steps

After successful installation:

1. **Secure Your Server**: Review security settings
2. **Configure Monitoring**: Set up alerts and notifications
3. **Setup Backups**: Configure automated backups
4. **Install Applications**: Deploy your applications using Docker
5. **Monitor Performance**: Use Prometheus for monitoring
6. **Join Community**: Participate in discussions and contribute

For more information, see the [full documentation](../README.md).