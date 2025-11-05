#!/bin/bash

# =============================================================================
# ServerSH Backup Control Script
# =============================================================================
# Management tool for ServerSH backup operations

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
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

# Usage information
show_usage() {
    cat << EOF
ServerSH Backup Control Tool

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    create [TYPE] [SOURCE]     Create a new backup
        TYPE: full, incremental, differential, snapshot (default: full)
        SOURCE: Backup source path (default: from config)

    restore <BACKUP_PATH> <TARGET>  Restore from backup
        BACKUP_PATH: Path to backup directory
        TARGET: Restore target directory

    list [TYPE]                List available backups
        TYPE: full, incremental, differential, snapshot

    status                     Show backup system status
    schedule                   Setup backup schedule
    unschedule                 Remove backup schedule
    verify <BACKUP_PATH>       Verify backup integrity
    cleanup [TYPE]             Cleanup old backups
        TYPE: Backup type to cleanup (default: all)

    disaster-recovery          Create disaster recovery package

    config                     Show current configuration
    test                       Test backup configuration

EXAMPLES:
    $0 create full             Create full backup
    $0 create incremental /home  Create incremental backup of /home
    $0 restore /backup/full/2024-01-01_02-00-00 /restore
    $0 list                    List all backups
    $0 status                  Show system status
    $0 verify /backup/full/2024-01-01_02-00-00
    $0 disaster-recovery       Create DR package

EOF
}

# Load configuration
load_config() {
    local config_file="${SERVERSH_CONFIG_DIR:-/etc/serversh}/backup.yaml"

    if [[ ! -f "$config_file" ]]; then
        config_file="$PROJECT_DIR/configs/backup.yaml"
    fi

    if [[ ! -f "$config_file" ]]; then
        log_error "Backup configuration file not found"
        log_info "Expected locations:"
        log_info "  - ${SERVERSH_CONFIG_DIR:-/etc/serversh}/backup.yaml"
        log_info "  - $PROJECT_DIR/configs/backup.yaml"
        exit 1
    fi

    export BACKUP_CONFIG_FILE="$config_file"
}

# Simple YAML parser
get_yaml_value() {
    local file="$1"
    local key="$2"
    local default="${3:-}"

    # Simple grep-based YAML parsing
    local value
    value=$(grep "^[[:space:]]*${key}:" "$file" | head -n1 | sed "s/^[[:space:]]*${key}:[[:space:]]*//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '"')

    if [[ -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Create backup
create_backup() {
    local backup_type="${1:-full}"
    local backup_source="${2:-}"

    log_info "Creating $backup_type backup..."

    # Source backup module
    source "$PROJECT_DIR/modules/backup/backup_recovery.sh"

    # Execute backup
    if create_backup "$backup_type" "$backup_source" "$BACKUP_CONFIG_FILE"; then
        log_success "Backup completed successfully"
    else
        log_error "Backup failed"
        exit 1
    fi
}

# Restore backup
restore_backup() {
    local backup_path="$1"
    local restore_target="$2"

    if [[ -z "$backup_path" || -z "$restore_target" ]]; then
        log_error "Both backup path and restore target are required"
        show_usage
        exit 1
    fi

    log_info "Restoring from: $backup_path"
    log_info "Restoring to: $restore_target"

    # Source backup module
    source "$PROJECT_DIR/modules/backup/backup_recovery.sh"

    # Execute restore
    if restore_backup "$backup_path" "$restore_target" "$BACKUP_CONFIG_FILE"; then
        log_success "Restore completed successfully"
    else
        log_error "Restore failed"
        exit 1
    fi
}

# List backups
list_backups() {
    local backup_type="${1:-}"

    local backup_dir
    backup_dir=$(get_yaml_value "$BACKUP_CONFIG_FILE" "backup.base_directory" "/backup")

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory not found: $backup_dir"
        exit 1
    fi

    log_info "Available backups in: $backup_dir"

    if [[ -n "$backup_type" ]]; then
        if [[ ! -d "$backup_dir/$backup_type" ]]; then
            log_error "Backup type not found: $backup_type"
            exit 1
        fi
        echo ""
        echo "$backup_type backups:"
        ls -la "$backup_dir/$backup_type" | grep "^d" | grep "????-??-??_??-??-??" | awk '{print $9, $6, $7, $8}' | while read -r dir month day time; do
            echo "  $dir ($month $day $time)"
        done
    else
        # List all backup types
        for type in full incremental differential snapshot disaster_recovery; do
            if [[ -d "$backup_dir/$type" ]]; then
                echo ""
                echo "$type backups:"
                ls -la "$backup_dir/$type" | grep "^d" | grep "????-??-??_??-??-??" | awk '{print $9, $6, $7, $8}' | while read -r dir month day time; do
                    local size=$(du -sh "$backup_dir/$type/$dir" 2>/dev/null | cut -f1)
                    echo "  $dir ($month $day $time) - $size"
                done
            fi
        done
    fi
}

# Show backup status
show_status() {
    log_info "Backup System Status"
    echo ""

    local backup_dir
    backup_dir=$(get_yaml_value "$BACKUP_CONFIG_FILE" "backup.base_directory" "/backup")

    echo "Configuration: $BACKUP_CONFIG_FILE"
    echo "Backup Directory: $backup_dir"
    echo ""

    # Check directory
    if [[ -d "$backup_dir" ]]; then
        local total_size
        total_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1)
        local total_backups
        total_backups=$(find "$backup_dir" -maxdepth 2 -type d -name "????-??-??_??-??-??" | wc -l)

        echo "Directory Status: Available"
        echo "Total Size: $total_size"
        echo "Total Backups: $total_backups"
    else
        echo "Directory Status: Not Found"
    fi

    echo ""

    # Check backup tools
    log_info "Required Tools Status:"
    local tools=("rsync" "tar" "gzip")
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "  $tool: ✓ Installed"
        else
            echo "  $tool: ✗ Missing"
        fi
    done

    echo ""

    # Check schedule
    local schedule_enabled
    schedule_enabled=$(get_yaml_value "$BACKUP_CONFIG_FILE" "backup.enable_schedule" "false")
    echo "Automatic Schedule: $schedule_enabled"

    if [[ "$schedule_enabled" == "true" ]]; then
        local schedule
        schedule=$(get_yaml_value "$BACKUP_CONFIG_FILE" "backup.schedule" "Not configured")
        echo "Schedule: $schedule"

        # Check crontab
        if crontab -l 2>/dev/null | grep -q "ServerSH Backup Job"; then
            echo "Crontab Status: ✓ Active"
        else
            echo "Crontab Status: ✗ Not found"
        fi
    fi

    echo ""

    # Disk space
    if [[ -d "$backup_dir" ]]; then
        log_info "Disk Space:"
        df -h "$backup_dir" | tail -n1 | while read -r filesystem size used avail use_percent mount; do
            echo "  Total: $size, Used: $used, Available: $avail ($use_percent)"
        done
    fi
}

# Setup schedule
setup_schedule() {
    log_info "Setting up backup schedule..."

    # Source backup module
    source "$PROJECT_DIR/modules/backup/backup_recovery.sh"

    if setup_backup_schedule "$BACKUP_CONFIG_FILE"; then
        log_success "Backup schedule configured"
    else
        log_error "Failed to setup backup schedule"
        exit 1
    fi
}

# Remove schedule
remove_schedule() {
    log_info "Removing backup schedule..."

    # Source backup module
    source "$PROJECT_DIR/modules/backup/backup_recovery.sh"

    if remove_backup_schedule; then
        log_success "Backup schedule removed"
    else
        log_error "Failed to remove backup schedule"
        exit 1
    fi
}

# Verify backup
verify_backup() {
    local backup_path="$1"

    if [[ -z "$backup_path" ]]; then
        log_error "Backup path is required"
        exit 1
    fi

    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup path not found: $backup_path"
        exit 1
    fi

    log_info "Verifying backup: $backup_path"

    # Source backup module
    source "$PROJECT_DIR/modules/backup/backup_recovery.sh"

    if verify_backup "$backup_path" "$BACKUP_CONFIG_FILE"; then
        log_success "Backup verification passed"
    else
        log_error "Backup verification failed"
        exit 1
    fi
}

# Cleanup old backups
cleanup_backups() {
    local backup_type="${1:-all}"

    log_info "Cleaning up old backups (type: $backup_type)..."

    # Source backup module
    source "$PROJECT_DIR/modules/backup/backup_recovery.sh"

    if [[ "$backup_type" == "all" ]]; then
        for type in full incremental differential snapshot; do
            cleanup_old_backups "$type" "$BACKUP_CONFIG_FILE"
        done
    else
        cleanup_old_backups "$backup_type" "$BACKUP_CONFIG_FILE"
    fi

    log_success "Backup cleanup completed"
}

# Create disaster recovery package
create_disaster_recovery() {
    log_info "Creating disaster recovery package..."

    # Source backup module
    source "$PROJECT_DIR/modules/backup/backup_recovery.sh"

    if create_disaster_recovery "$BACKUP_CONFIG_FILE"; then
        log_success "Disaster recovery package created"
    else
        log_error "Failed to create disaster recovery package"
        exit 1
    fi
}

# Show configuration
show_config() {
    log_info "Backup Configuration:"
    echo ""

    echo "Configuration File: $BACKUP_CONFIG_FILE"
    echo ""

    local backup_dir
    backup_dir=$(get_yaml_value "$BACKUP_CONFIG_FILE" "backup.base_directory" "/backup")
    echo "Base Directory: $backup_dir"

    local retention_days
    retention_days=$(get_yaml_value "$BACKUP_CONFIG_FILE" "backup.retention_days" "30")
    echo "Retention Days: $retention_days"

    local schedule
    schedule=$(get_yaml_value "$BACKUP_CONFIG_FILE" "backup.schedule" "Not configured")
    echo "Schedule: $schedule"

    local compression
    compression=$(get_yaml_value "$BACKUP_CONFIG_FILE" "backup.compression" "gzip")
    echo "Compression: $compression"

    local encryption
    encryption=$(get_yaml_value "$BACKUP_CONFIG_FILE" "backup.encryption" "false")
    echo "Encryption: $encryption"

    local sources
    sources=$(get_yaml_value "$BACKUP_CONFIG_FILE" "backup.sources" "/etc,/home,/var/www,/opt")
    echo "Sources: $sources"

    echo ""

    # Show remote configuration
    local remote_enabled
    remote_enabled=$(get_yaml_value "$BACKUP_CONFIG_FILE" "backup.remote.enable" "false")
    echo "Remote Backup: $remote_enabled"

    if [[ "$remote_enabled" == "true" ]]; then
        local remote_type
        remote_type=$(get_yaml_value "$BACKUP_CONFIG_FILE" "backup.remote.type" "rsync")
        echo "Remote Type: $remote_type"

        local remote_host
        remote_host=$(get_yaml_value "$BACKUP_CONFIG_FILE" "backup.remote.host" "")
        echo "Remote Host: $remote_host"
    fi
}

# Test configuration
test_config() {
    log_info "Testing backup configuration..."

    # Source backup module
    source "$PROJECT_DIR/modules/backup/backup_recovery.sh"

    if validate_backup_config "$BACKUP_CONFIG_FILE"; then
        log_success "Configuration test passed"
    else
        log_error "Configuration test failed"
        exit 1
    fi
}

# Main function
main() {
    # Check if running as root for some operations
    if [[ "$EUID" -ne 0 ]] && [[ "${1:-}" =~ ^(create|restore|schedule|unschedule|cleanup|disaster-recovery)$ ]]; then
        log_error "This command requires root privileges"
        exit 1
    fi

    # Load configuration
    load_config

    # Parse command
    case "${1:-}" in
        "create")
            create_backup "${2:-full}" "${3:-}"
            ;;
        "restore")
            restore_backup "$2" "$3"
            ;;
        "list")
            list_backups "${2:-}"
            ;;
        "status")
            show_status
            ;;
        "schedule")
            setup_schedule
            ;;
        "unschedule")
            remove_schedule
            ;;
        "verify")
            verify_backup "$2"
            ;;
        "cleanup")
            cleanup_backups "${2:-all}"
            ;;
        "disaster-recovery")
            create_disaster_recovery
            ;;
        "config")
            show_config
            ;;
        "test")
            test_config
            ;;
        "help"|"--help"|"-h"|"")
            show_usage
            ;;
        *)
            log_error "Unknown command: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"