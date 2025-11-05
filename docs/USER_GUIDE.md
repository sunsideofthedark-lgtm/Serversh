# ServerSH User Guide

This comprehensive user guide covers all aspects of using ServerSH for server management and deployment.

## Table of Contents

- [Getting Started](#getting-started)
- [Configuration Management](#configuration-management)
- [Module Usage](#module-usage)
- [Backup & Recovery](#backup--recovery)
- [Multi-Server Management](#multi-server-management)
- [Security Management](#security-management)
- [Monitoring and Logging](#monitoring-and-logging)
- [Advanced Usage](#advanced-usage)
- [Best Practices](#best-practices)

## Getting Started

### First-Time Setup

1. **Install ServerSH**
   ```bash
   git clone https://github.com/sunsideofthedark-lgtm/Serversh.git
   cd Serversh
   ./quick-setup.sh
   ```

2. **Configure Basic Settings**
   ```bash
   # Edit configuration
   nano .env

   # Key settings to configure:
   SERVERSH_HOSTNAME=your-server-name
   SERVERSH_USERNAME=admin
   SERVERSH_USER_PASSWORD=YourSecurePassword123!
   ```

3. **Verify Installation**
   ```bash
   sudo ./serversh/scripts/status.sh
   ```

### Daily Operations

Common daily tasks:

```bash
# Check system status
./serversh/scripts/status.sh

# Create backup
sudo ./serversh/scripts/backupctl.sh create full

# Check service status
sudo systemctl status docker ssh prometheus

# View logs
sudo journalctl -u serversh -f
```

## Configuration Management

### Environment Configuration

The `.env` file is the primary configuration method:

```bash
# System Settings
SERVERSH_HOSTNAME=prod-server
SERVERSH_FQDN=prod-server.example.com

# User Management
SERVERSH_USERNAME=admin
SERVERSH_USER_PASSWORD=SecurePassword123!
SERVERSH_USER_SUDO=true

# SSH Configuration
SERVERSH_SSH_ENABLE=true
SERVERSH_SSH_INTERACTIVE_PORT=true
SERVERSH_SSH_PREFERRED_PORT=2222

# Docker Settings
SERVERSH_DOCKER_ENABLE=true
SERVERSH_DOCKER_NETWORK_MTU=1450
SERVERSH_DOCKER_IPV6=true

# Monitoring
SERVERSH_PROMETHEUS_ENABLE=true
SERVERSH_NODE_EXPORTER_ENABLE=true

# Backup Configuration
SERVERSH_BACKUP_ENABLE=true
SERVERSH_BACKUP_BASE_DIR=/backup
SERVERSH_BACKUP_SCHEDULE="0 2 * * *"
```

### YAML Configuration

For complex configurations, use YAML files:

```yaml
# serversh/configs/production.yaml
system/hostname:
  hostname: "prod-server"
  fqdn: "prod-server.example.com"

security/users:
  create_user: true
  username: "admin"
  password: "SecurePassword123!"
  ssh_key: true
  sudo: true
  additional_ssh_keys:
    - "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDC... user@example.com"

security/ssh:
  enable: true
  interactive_port: true
  preferred_port: 2222
  security_settings:
    permit_root_login: "no"
    password_authentication: "no"
    client_alive_interval: 300

container/docker:
  enable: true
  install_compose: true
  network_config:
    mtu: 1450
    ipv6: true
    name: "newt_talk"

monitoring/prometheus:
  enable: true
  prometheus_port: 9090
  node_exporter_port: 9100
```

### Configuration Validation

Validate your configuration before installation:

```bash
# Validate environment configuration
./serversh/scripts/validate-config.sh --env=.env

# Validate YAML configuration
./serversh/scripts/validate-config.sh --yaml=configs/production.yaml

# Check specific module configuration
sudo ./serversh/modules/security/ssh.sh validate
```

## Module Usage

### System Modules

#### System Updates

Keep your system updated automatically:

```bash
# Enable automatic updates
echo "SERVERSH_UPDATE_AUTO=true" >> .env

# Run manual updates
sudo ./serversh/modules/system/update.sh install

# Check update status
sudo ./serversh/modules/system/update.sh status
```

#### Hostname Management

Configure system hostname:

```bash
# Set hostname
echo "SERVERSH_HOSTNAME=myserver" >> .env
echo "SERVERSH_FQDN=myserver.example.com" >> .env

# Apply hostname configuration
sudo ./serversh/modules/system/hostname.sh install

# Verify hostname
hostname
hostname -f
```

### Security Modules

#### User Management

Create and manage users:

```bash
# Create admin user
echo "SERVERSH_USERNAME=admin" >> .env
echo "SERVERSH_USER_PASSWORD=SecurePass123!" >> .env

# Add SSH keys
echo "SERVERSH_ADDITIONAL_SSH_KEYS=\"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDC... user@example.com\"" >> .env

# Apply user configuration
sudo ./serversh/modules/security/users.sh install
```

#### SSH Configuration

Secure SSH access:

```bash
# Interactive port selection
sudo ./serversh/modules/security/ssh_interactive.sh install

# Manual port configuration
echo "SERVERSH_SSH_PORT=2222" >> .env
echo "SERVERSH_SSH_INTERACTIVE_PORT=false" >> .env

# Test SSH configuration
sudo sshd -t

# Restart SSH service
sudo systemctl restart ssh
```

#### Firewall Management

Configure firewall rules:

```bash
# Enable firewall
echo "SERVERSH_FIREWALL_ENABLE=true" >> .env
echo "SERVERSH_FIREWALL_ALLOWED_PORTS=\"80/tcp,443/tcp\"" >> .env

# Apply firewall configuration
sudo ./serversh/modules/security/firewall.sh install

# Check firewall status
sudo ufw status  # Ubuntu/Debian
sudo firewall-cmd --list-all  # CentOS/RHEL
```

### Application Modules

#### Docker Management

Manage Docker containers and networks:

```bash
# Install Docker
echo "SERVERSH_DOCKER_ENABLE=true" >> .env
sudo ./serversh/modules/container/docker.sh install

# Test Docker installation
docker run hello-world

# Check Docker networks
docker network ls
docker network inspect newt_talk

# Manage Docker user
sudo usermod -aG docker $USER
newgrp docker
```

#### Monitoring with Prometheus

Set up system monitoring:

```bash
# Enable monitoring
echo "SERVERSH_PROMETHEUS_ENABLE=true" >> .env
echo "SERVERSH_PROMETHEUS_PORT=9090" >> .env

# Install monitoring stack
sudo ./serversh/modules/monitoring/prometheus.sh install

# Access Prometheus
curl http://localhost:9090/api/v1/status/config

# Check Node Exporter metrics
curl http://localhost:9100/metrics
```

#### Optional Software

Install additional tools:

```bash
# Install Tailscale VPN
echo "SERVERSH_INSTALL_TAILSCALE=true" >> .env
echo "SERVERSH_TAILSCALE_SSH=true" >> .env
sudo ./serversh/modules/applications/optional_software.sh install

# Connect to Tailscale
sudo tailscale up --ssh --authkey=your-authkey

# Install utilities
echo "SERVERSH_UTILITY_PACKAGES=\"htop,vim,git,curl,wget,tree\"" >> .env
sudo ./serversh/modules/applications/optional_software.sh install
```

## Backup & Recovery

### Creating Backups

#### Full Backups

```bash
# Create full system backup
sudo ./serversh/scripts/backupctl.sh create full

# Create backup of specific directories
sudo ./serversh/scripts/backupctl.sh create full "/etc,/home,/var/www"

# Create encrypted backup
echo "SERVERSH_BACKUP_ENCRYPTION=true" >> .env
echo "SERVERSH_BACKUP_ENCRYPTION_KEY=your-encryption-key" >> .env
sudo ./serversh/scripts/backupctl.sh create full
```

#### Incremental Backups

```bash
# Create incremental backup
sudo ./serversh/scripts/backupctl.sh create incremental

# Create backup since specific date
sudo ./serversh/scripts/backupctl.sh create incremental --since="2024-01-01"
```

#### Scheduled Backups

```bash
# Enable automatic backups
echo "SERVERSH_BACKUP_ENABLE=true" >> .env
echo "SERVERSH_BACKUP_SCHEDULE=\"0 2 * * *\"" >> .env
sudo ./serversh/scripts/backupctl.sh schedule

# View backup schedule
crontab -l | grep serversh
```

### Managing Backups

#### Listing Backups

```bash
# List all backups
./serversh/scripts/backupctl.sh list

# List specific backup types
./serversh/scripts/backupctl.sh list full
./serversh/scripts/backupctl.sh list incremental
```

#### Backup Verification

```bash
# Verify backup integrity
sudo ./serversh/scripts/backupctl.sh verify /backup/full/2024-01-01_02-00-00

# Verify all backups
sudo ./serversh/scripts/backupctl.sh verify --all
```

#### Cleanup Operations

```bash
# Clean old backups (based on retention policy)
sudo ./serversh/scripts/backupctl.sh cleanup

# Clean specific backup type
sudo ./serversh/scripts/backupctl.sh cleanup --type=incremental

# Custom cleanup (older than 30 days)
sudo ./serversh/scripts/backupctl.sh cleanup --older-than=30d
```

### Recovery Operations

#### Full System Recovery

```bash
# Restore from backup
sudo ./serversh/scripts/backupctl.sh restore /backup/full/2024-01-01_02-00-00 /

# Restore to specific directory
sudo ./serversh/scripts/backupctl.sh restore /backup/full/2024-01-01_02-00-00 /restore
```

#### Selective Recovery

```bash
# Restore specific files
sudo ./serversh/scripts/backupctl.sh restore /backup/full/2024-01-01_02-00-00 /restore --include="*.conf"

# Exclude specific directories
sudo ./serversh/scripts/backupctl.sh restore /backup/full/2024-01-01_02-00-00 /restore --exclude="/var/cache"
```

#### Disaster Recovery

```bash
# Create disaster recovery package
sudo ./serversh/scripts/backupctl.sh disaster-recovery

# Recover from disaster package
tar -xzf disaster_recovery_*.tar.gz
cd disaster_recovery_*
sudo ./recover.sh
```

## Multi-Server Management

### Cluster Setup

#### Single Node Cluster

```bash
# Initialize single node cluster
sudo ./serversh/scripts/clusterctl.sh init --mode=single_node

# Check cluster status
./serversh/scripts/clusterctl.sh status

# List nodes in cluster
./serversh/scripts/clusterctl.sh node list
```

#### Multi-Node Cluster

```bash
# Initialize master node
sudo ./serversh/scripts/clusterctl.sh init --mode=multi_master

# Get join token for worker
TOKEN=$(sudo ./serversh/scripts/clusterctl.sh token create --role=worker)

# Join worker node to cluster
sudo ./serversh/scripts/clusterctl.sh join --token=$TOKEN --master=master-ip

# Add additional master
MASTER_TOKEN=$(sudo ./serversh/scripts/clusterctl.sh token create --role=master)
sudo ./serversh/scripts/clusterctl.sh join --token=$MASTER_TOKEN --master=master-ip
```

### Load Balancing

#### HAProxy Configuration

```bash
# Configure load balancer
./serversh/scripts/clusterctl.sh backend add --name=web --port=80 --nodes=node1,node2,node3

# Check load balancer status
./serversh/scripts/clusterctl.sh lb status

# Test load balancing
curl http://localhost/haproxy-stats
```

#### Service Discovery

```bash
# Register service
./serversh/scripts/clusterctl.sh service register --name=web-app --port=8080 --health=/health

# List services
./serversh/scripts/clusterctl.sh service list

# Check service health
./serversh/scripts/clusterctl.sh service health --name=web-app
```

### Node Management

#### Node Operations

```bash
# Pause node for maintenance
./serversh/scripts/clusterctl.sh node pause --name=node2

# Resume node operation
./serversh/scripts/clusterctl.sh node resume --name=node2

# Remove node from cluster
./serversh/scripts/clusterctl.sh node remove --name=node3 --graceful

# Check node status
./serversh/scripts/clusterctl.sh node status --name=node1
```

## Security Management

### SSH Security

#### Key Management

```bash
# Generate SSH keys for new user
sudo -u admin ssh-keygen -t ed25519 -f /home/admin/.ssh/id_ed25519

# Add authorized keys
sudo -u admin mkdir -p /home/admin/.ssh
sudo -u admin chmod 700 /home/admin/.ssh
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDC..." | sudo -u admin tee -a /home/admin/.ssh/authorized_keys
sudo -u admin chmod 600 /home/admin/.ssh/authorized_keys
```

#### Security Hardening

```bash
# Apply SSH hardening
sudo ./serversh/modules/security/ssh.sh install

# Test SSH configuration
sudo sshd -t

# Check SSH security
sshd -T | grep -E "(permitrootlogin|passwordauthentication|port)"
```

### Firewall Management

#### UFW (Ubuntu/Debian)

```bash
# Enable firewall
sudo ufw enable

# Allow SSH port
sudo ufw allow 2222/tcp

# Allow web services
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Check firewall status
sudo ufw status verbose
```

#### Firewalld (CentOS/RHEL)

```bash
# Configure firewall
sudo firewall-cmd --set-default-zone=drop
sudo firewall-cmd --permanent --add-port=2222/tcp
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# Check firewall rules
sudo firewall-cmd --list-all
```

### Fail2ban Integration

```bash
# Configure fail2ban
echo "SERVERSH_INSTALL_FAIL2BAN=true" >> .env
sudo ./serversh/modules/applications/optional_software.sh install

# Check fail2ban status
sudo fail2ban-client status

# Unban IP if needed
sudo fail2ban-client set sshd unbanip 192.168.1.100
```

## Monitoring and Logging

### System Monitoring

#### Prometheus Metrics

```bash
# Access Prometheus web interface
curl http://localhost:9090

# Query system metrics
curl -G 'http://localhost:9090/api/v1/query' --data-urlencode 'query=up'

# Check target status
curl http://localhost:9090/api/v1/targets
```

#### Node Exporter

```bash
# Check system metrics
curl http://localhost:9100/metrics

# Monitor CPU usage
curl -s http://localhost:9100/metrics | grep node_cpu_seconds_total

# Monitor memory usage
curl -s http://localhost:9100/metrics | grep node_memory_MemAvailable_bytes
```

### Log Management

#### System Logs

```bash
# View ServerSH logs
sudo journalctl -u serversh -f

# View all relevant services
sudo journalctl -u serversh -u docker -u ssh -u prometheus -f

# Filter by log level
sudo journalctl -p err -u serversh
```

#### Application Logs

```bash
# Backup logs
sudo tail -f /var/log/serversh/backup.log

# Installation logs
sudo tail -f /var/log/serversh/installation.log

# Cluster logs
sudo tail -f /var/log/serversh/cluster.log
```

### Performance Monitoring

#### System Resources

```bash
# Check system performance
htop

# Disk usage
df -h

# Memory usage
free -h

# Network connections
ss -tulpn
```

#### Docker Monitoring

```bash
# Container status
docker ps
docker stats

# Resource usage
docker system df
docker system events
```

## Advanced Usage

### Custom Modules

Create your own modules:

```bash
# Create module directory
mkdir -p serversh/modules/custom/myapp

# Create module script
cat > serversh/modules/custom/myapp/myapp.sh << 'EOF'
#!/bin/bash
set -euo pipefail

source "${SERVERSH_ROOT}/core/utils.sh"
source "${SERVERSH_ROOT}/core/logger.sh"

MODULE_NAME="custom/myapp"
MODULE_VERSION="1.0.0"

validate() {
    log_info "Validating myapp configuration"
}

install() {
    log_info "Installing myapp"
    # Your installation logic here
    save_state "${MODULE_NAME}" "installed"
}

uninstall() {
    log_info "Uninstalling myapp"
    # Your uninstallation logic here
    save_state "${MODULE_NAME}" "uninstalled"
}

case "${1:-}" in
    "validate") validate ;;
    "install") install ;;
    "uninstall") uninstall ;;
    *) echo "Usage: $0 {validate|install|uninstall}"; exit 1 ;;
esac
EOF

chmod +x serversh/modules/custom/myapp/myapp.sh
```

### Automation Scripts

Create custom automation scripts:

```bash
# Create deployment script
cat > deploy-app.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Backup current state
sudo ./serversh/scripts/backupctl.sh create full

# Update system
sudo apt update && sudo apt upgrade -y

# Deploy application
docker-compose -f docker-compose.prod.yml up -d

# Verify deployment
curl -f http://localhost:8080/health

echo "Deployment completed successfully"
EOF

chmod +x deploy-app.sh
```

### Integration with CI/CD

Integrate ServerSH into CI/CD pipelines:

```yaml
# .github/workflows/deploy.yml
name: Deploy with ServerSH

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2

    - name: Setup ServerSH
      run: |
        curl -fsSL https://raw.githubusercontent.com/sunsideofthedark-lgtm/Serversh/main/install.sh | bash

    - name: Configure Environment
      run: |
        cp .env.production .env

    - name: Deploy Server
      run: |
        sudo ./serversh/scripts/install-from-env.sh
```

## Best Practices

### Security Best Practices

1. **Use Strong Passwords**
   ```bash
   # Generate strong password
   openssl rand -base64 32
   ```

2. **Regular Updates**
   ```bash
   # Enable automatic security updates
   echo "SERVERSH_AUTO_SECURITY_UPDATES=true" >> .env
   ```

3. **SSH Key Authentication**
   ```bash
   # Disable password authentication
   echo "SERVERSH_SSH_PASSWORD_AUTHENTICATION=no" >> .env
   ```

4. **Firewall Configuration**
   ```bash
   # Use restrictive firewall policies
   echo "SERVERSH_FIREWALL_DEFAULT_POLICY=deny" >> .env
   ```

### Backup Best Practices

1. **Regular Backups**
   ```bash
   # Schedule daily backups
   echo "SERVERSH_BACKUP_SCHEDULE=\"0 2 * * *\"" >> .env
   ```

2. **Off-site Backups**
   ```bash
   # Enable remote backups
   echo "SERVERSH_BACKUP_REMOTE_ENABLE=true" >> .env
   ```

3. **Backup Verification**
   ```bash
   # Regular backup verification
   sudo ./serversh/scripts/backupctl.sh verify --all
   ```

4. **Disaster Recovery Testing**
   ```bash
   # Test disaster recovery
   sudo ./serversh/scripts/backupctl.sh disaster-recovery
   ```

### Performance Optimization

1. **Resource Monitoring**
   ```bash
   # Monitor system resources
   htop
   iotop
   nethogs
   ```

2. **Docker Optimization**
   ```bash
   # Optimize Docker configuration
   echo "SERVERSH_DOCKER_LOG_LEVEL=warn" >> .env
   echo "SERVERSH_DOCKER_STORAGE_DRIVER=overlay2" >> .env
   ```

3. **Network Optimization**
   ```bash
   # Optimize network settings
   echo "SERVERSH_DOCKER_NETWORK_MTU=1450" >> .env
   ```

### Maintenance Routines

1. **Daily Checks**
   ```bash
   # Create daily check script
   cat > daily-check.sh << 'EOF'
   #!/bin/bash
   ./serversh/scripts/status.sh
   sudo ./serversh/scripts/backupctl.sh status
   docker system df
   EOF
   ```

2. **Weekly Maintenance**
   ```bash
   # Weekly cleanup
   sudo apt autoremove
   docker system prune -f
   sudo ./serversh/scripts/backupctl.sh cleanup
   ```

3. **Monthly Reviews**
   ```bash
   # Monthly security review
   sudo ./serversh/scripts/backupctl.sh disaster-recovery
   # Review logs and performance metrics
   ```

This user guide provides comprehensive coverage of ServerSH functionality. For specific technical details, refer to the individual module documentation and API references.