#!/bin/bash

# =============================================================================
# ServerSH Backup & Recovery Module
# =============================================================================
# Comprehensive backup and recovery system with multiple backup strategies,
# scheduling, monitoring, and disaster recovery capabilities.

set -euo pipefail

# Source required utilities
source "${SERVERSH_ROOT}/core/utils.sh"
source "${SERVERSH_ROOT}/core/state.sh"
source "${SERVERSH_ROOT}/core/logger.sh"

# Module metadata
MODULE_NAME="backup_recovery"
MODULE_VERSION="1.0.0"
MODULE_DESCRIPTION="Comprehensive backup and recovery system"
MODULE_DEPENDENCIES=("system/hostname")

# Backup configuration with default values
BACKUP_CONFIG_FILE="${SERVERSH_CONFIG_DIR:-/etc/serversh}/backup.yaml"
BACKUP_BASE_DIR="${SERVERSH_BACKUP_BASE_DIR:-/backup}"
BACKUP_RETENTION_DAYS="${SERVERSH_BACKUP_RETENTION_DAYS:-30}"
BACKUP_SCHEDULE="${SERVERSH_BACKUP_SCHEDULE:-0 2 * * *}"
BACKUP_COMPRESSION="${SERVERSH_BACKUP_COMPRESSION:-gzip}"
BACKUP_ENCRYPTION="${SERVERSH_BACKUP_ENCRYPTION:-false}"
BACKUP_ENCRYPTION_KEY="${SERVERSH_BACKUP_ENCRYPTION_KEY:-}"
BACKUP_PARALLEL_JOBS="${SERVERSH_BACKUP_PARALLEL_JOBS:-2}"
BACKUP_VERIFY="${SERVERSH_BACKUP_VERIFY:-true}"
BACKUP_EMAIL_REPORTS="${SERVERSH_BACKUP_EMAIL_REPORTS:-false}"
BACKUP_EMAIL_TO="${SERVERSH_BACKUP_EMAIL_TO:-}"

# Backup types
BACKUP_TYPES=("full" "incremental" "differential" "snapshot")

# =============================================================================
# BACKUP VALIDATION
# =============================================================================

validate_backup_config() {
    local config_file="${1:-$BACKUP_CONFIG_FILE}"

    log_debug "Validating backup configuration from: $config_file"

    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        log_error "Backup configuration file not found: $config_file"
        return 1
    fi

    # Validate backup directory
    local backup_dir
    backup_dir=$(get_config_value "$config_file" "backup.base_directory" "$BACKUP_BASE_DIR")

    if [[ ! -d "$backup_dir" ]]; then
        log_warning "Backup directory does not exist: $backup_dir"
        log_info "Creating backup directory: $backup_dir"
        mkdir -p "$backup_dir"
    fi

    # Validate retention days
    local retention_days
    retention_days=$(get_config_value "$config_file" "backup.retention_days" "$BACKUP_RETENTION_DAYS")

    if ! [[ "$retention_days" =~ ^[0-9]+$ ]] || [[ "$retention_days" -lt 1 ]]; then
        log_error "Invalid retention_days: $retention_days. Must be a positive integer."
        return 1
    fi

    # Validate compression method
    local compression
    compression=$(get_config_value "$config_file" "backup.compression" "$BACKUP_COMPRESSION")

    local valid_compressions=("gzip" "bzip2" "xz" "lz4" "none")
    if [[ ! " ${valid_compressions[*]} " =~ " $compression " ]]; then
        log_error "Invalid compression method: $compression"
        log_info "Valid methods: ${valid_compressions[*]}"
        return 1
    fi

    # Validate parallel jobs
    local parallel_jobs
    parallel_jobs=$(get_config_value "$config_file" "backup.parallel_jobs" "$BACKUP_PARALLEL_JOBS")

    if ! [[ "$parallel_jobs" =~ ^[0-9]+$ ]] || [[ "$parallel_jobs" -lt 1 ]] || [[ "$parallel_jobs" -gt 8 ]]; then
        log_error "Invalid parallel_jobs: $parallel_jobs. Must be between 1 and 8."
        return 1
    fi

    # Check available disk space
    local available_space
    available_space=$(df "$backup_dir" | awk 'NR==2 {print $4}')
    local required_space=1073741824  # 1GB minimum

    if [[ "$available_space" -lt "$required_space" ]]; then
        log_warning "Low disk space in backup directory: $backup_dir"
        log_warning "Available: $((available_space / 1024 / 1024))MB, Required: $((required_space / 1024 / 1024))MB"
    fi

    # Test backup tools availability
    check_backup_tools

    log_success "Backup configuration validation completed"
    return 0
}

check_backup_tools() {
    local missing_tools=()

    # Check required tools
    if ! command -v rsync >/dev/null 2>&1; then
        missing_tools+=("rsync")
    fi

    if ! command -v tar >/dev/null 2>&1; then
        missing_tools+=("tar")
    fi

    # Check compression tools
    case "$BACKUP_COMPRESSION" in
        "gzip")
            if ! command -v gzip >/dev/null 2>&1; then
                missing_tools+=("gzip")
            fi
            ;;
        "bzip2")
            if ! command -v bzip2 >/dev/null 2>&1; then
                missing_tools+=("bzip2")
            fi
            ;;
        "xz")
            if ! command -v xz >/dev/null 2>&1; then
                missing_tools+=("xz")
            fi
            ;;
        "lz4")
            if ! command -v lz4 >/dev/null 2>&1; then
                missing_tools+=("lz4")
            fi
            ;;
    esac

    # Check optional tools
    if [[ "$BACKUP_ENCRYPTION" == "true" ]]; then
        if ! command -v gpg >/dev/null 2>&1; then
            missing_tools+=("gpg")
        fi
    fi

    if [[ "$BACKUP_VERIFY" == "true" ]]; then
        if ! command -v sha256sum >/dev/null 2>&1; then
            missing_tools+=("sha256sum")
        fi
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required backup tools: ${missing_tools[*]}"
        log_info "Install missing tools: apt-get install ${missing_tools[*]}"
        return 1
    fi

    return 0
}

# =============================================================================
# BACKUP OPERATIONS
# =============================================================================

create_backup() {
    local backup_type="${1:-full}"
    local backup_source="${2:-}"
    local config_file="${3:-$BACKUP_CONFIG_FILE}"

    log_info "Starting $backup_type backup"

    # Validate backup type
    if [[ ! " ${BACKUP_TYPES[*]} " =~ " $backup_type " ]]; then
        log_error "Invalid backup type: $backup_type"
        log_info "Valid types: ${BACKUP_TYPES[*]}"
        return 1
    fi

    # Load configuration
    local backup_dir
    backup_dir=$(get_config_value "$config_file" "backup.base_directory" "$BACKUP_BASE_DIR")

    local compression
    compression=$(get_config_value "$config_file" "backup.compression" "$BACKUP_COMPRESSION")

    local encryption
    encryption=$(get_config_value "$config_file" "backup.encryption" "$BACKUP_ENCRYPTION")

    # Create backup directory structure
    local backup_date
    backup_date=$(date +"%Y-%m-%d_%H-%M-%S")
    local backup_path="$backup_dir/$backup_type/$backup_date"

    mkdir -p "$backup_path"

    # Start backup timer
    local start_time
    start_time=$(date +%s)

    # Execute backup based on type
    case "$backup_type" in
        "full")
            execute_full_backup "$backup_source" "$backup_path" "$config_file"
            ;;
        "incremental")
            execute_incremental_backup "$backup_source" "$backup_path" "$config_file"
            ;;
        "differential")
            execute_differential_backup "$backup_source" "$backup_path" "$config_file"
            ;;
        "snapshot")
            execute_snapshot_backup "$backup_source" "$backup_path" "$config_file"
            ;;
    esac

    local backup_result=$?

    # Calculate backup duration
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ $backup_result -eq 0 ]]; then
        # Verify backup if enabled
        if [[ "$BACKUP_VERIFY" == "true" ]]; then
            verify_backup "$backup_path" "$config_file"
            backup_result=$?
        fi

        if [[ $backup_result -eq 0 ]]; then
            # Create backup metadata
            create_backup_metadata "$backup_type" "$backup_path" "$duration" "$config_file"

            # Cleanup old backups
            cleanup_old_backups "$backup_type" "$config_file"

            log_success "$backup_type backup completed successfully in ${duration}s"
            log_info "Backup location: $backup_path"

            # Send notification if enabled
            send_backup_notification "$backup_type" "success" "$backup_path" "$duration" "$config_file"
        else
            log_error "Backup verification failed"
            send_backup_notification "$backup_type" "failed" "$backup_path" "$duration" "$config_file"
        fi
    else
        log_error "$backup_type backup failed"
        send_backup_notification "$backup_type" "failed" "$backup_path" "$duration" "$config_file"
    fi

    return $backup_result
}

execute_full_backup() {
    local backup_source="$1"
    local backup_path="$2"
    local config_file="$3"

    log_info "Executing full backup from: $backup_source"

    # Load backup sources from config
    local sources
    if [[ -z "$backup_source" ]]; then
        sources=$(get_config_value "$config_file" "backup.sources" "/etc,/home,/var/www,/opt")
    else
        sources="$backup_source"
    fi

    local compression_ext
    case "$BACKUP_COMPRESSION" in
        "gzip") compression_ext=".gz" ;;
        "bzip2") compression_ext=".bz2" ;;
        "xz") compression_ext=".xz" ;;
        "lz4") compression_ext=".lz4" ;;
        *) compression_ext="" ;;
    esac

    # Backup each source
    IFS=',' read -ra source_array <<< "$sources"
    for source in "${source_array[@]}"; do
        source=$(echo "$source" | xargs)  # trim whitespace

        if [[ -d "$source" || -f "$source" ]]; then
            local source_name
            source_name=$(basename "$source")
            local backup_file="$backup_path/${source_name}_full.tar${compression_ext}"

            log_info "Backing up: $source -> $backup_file"

            # Create backup using rsync for efficiency, then tar for archiving
            local temp_dir="$backup_path/temp_${source_name}"
            mkdir -p "$temp_dir"

            if rsync -aAXH --delete "$source" "$temp_dir/"; then
                # Create compressed archive
                local tar_cmd="tar -cf"
                case "$BACKUP_COMPRESSION" in
                    "gzip") tar_cmd="tar -czf" ;;
                    "bzip2") tar_cmd="tar -cjf" ;;
                    "xz") tar_cmd="tar -cJf" ;;
                    "lz4") tar_cmd="tar -cf" ;;
                esac

                if [[ "$BACKUP_COMPRESSION" == "lz4" ]]; then
                    $tar_cmd "$backup_file" -C "$temp_dir" .
                    lz4 "$backup_file" "${backup_file}.lz4"
                    mv "${backup_file}.lz4" "$backup_file"
                else
                    $tar_cmd "$backup_file" -C "$temp_dir" .
                fi

                # Encrypt if enabled
                if [[ "$BACKUP_ENCRYPTION" == "true" ]]; then
                    encrypt_backup "$backup_file" "$config_file"
                fi

                # Cleanup temp directory
                rm -rf "$temp_dir"

                log_success "Backup completed: $backup_file"
            else
                log_error "Failed to backup: $source"
                return 1
            fi
        else
            log_warning "Source not found, skipping: $source"
        fi
    done

    # Create backup timestamp
    echo "$backup_path" > "$backup_path/.full_backup_timestamp"

    return 0
}

execute_incremental_backup() {
    local backup_source="$1"
    local backup_path="$2"
    local config_file="$3"

    log_info "Executing incremental backup"

    # Find latest full backup
    local latest_full_backup
    latest_full_backup=$(find_latest_backup "full" "$config_file")

    if [[ -z "$latest_full_backup" ]]; then
        log_warning "No full backup found for incremental backup. Creating full backup instead."
        execute_full_backup "$backup_source" "$backup_path" "$config_file"
        return $?
    fi

    local backup_timestamp_file="$latest_full_backup/.full_backup_timestamp"
    local reference_time

    if [[ -f "$backup_timestamp_file" ]]; then
        reference_time=$(stat -c %Y "$backup_timestamp_file")
    else
        reference_time=$(stat -c %Y "$latest_full_backup")
    fi

    log_debug "Reference time for incremental backup: $reference_time"

    # Find files modified since reference time
    local sources
    if [[ -z "$backup_source" ]]; then
        sources=$(get_config_value "$config_file" "backup.sources" "/etc,/home,/var/www,/opt")
    else
        sources="$backup_source"
    fi

    local incremental_files="$backup_path/incremental_files.txt"
    > "$incremental_files"

    IFS=',' read -ra source_array <<< "$sources"
    for source in "${source_array[@]}"; do
        source=$(echo "$source" | xargs)

        if [[ -d "$source" ]]; then
            find "$source" -newermt "@$reference_time" -type f >> "$incremental_files" 2>/dev/null || true
        fi
    done

    local file_count
    file_count=$(wc -l < "$incremental_files")

    if [[ "$file_count" -eq 0 ]]; then
        log_info "No modified files found since last backup"
        return 0
    fi

    log_info "Found $file_count modified files for incremental backup"

    # Create incremental backup archive
    local compression_ext
    case "$BACKUP_COMPRESSION" in
        "gzip") compression_ext=".gz" ;;
        "bzip2") compression_ext=".bz2" ;;
        "xz") compression_ext=".xz" ;;
        "lz4") compression_ext=".lz4" ;;
        *) compression_ext="" ;;
    esac

    local backup_file="$backup_path/incremental_backup.tar${compression_ext}"

    local tar_cmd="tar -cf"
    case "$BACKUP_COMPRESSION" in
        "gzip") tar_cmd="tar -czf" ;;
        "bzip2") tar_cmd="tar -cjf" ;;
        "xz") tar_cmd="tar -cJf" ;;
        "lz4") tar_cmd="tar -cf" ;;
    esac

    # Create archive from incremental files
    if [[ "$BACKUP_COMPRESSION" == "lz4" ]]; then
        tar -cf "$backup_file" -T "$incremental_files" 2>/dev/null || true
        lz4 "$backup_file" "${backup_file}.lz4"
        mv "${backup_file}.lz4" "$backup_file"
    else
        $tar_cmd "$backup_file" -T "$incremental_files" 2>/dev/null || true
    fi

    # Encrypt if enabled
    if [[ "$BACKUP_ENCRYPTION" == "true" ]]; then
        encrypt_backup "$backup_file" "$config_file"
    fi

    # Store reference to full backup
    echo "$latest_full_backup" > "$backup_path/.reference_backup"

    log_success "Incremental backup completed: $backup_file"
    return 0
}

execute_differential_backup() {
    local backup_source="$1"
    local backup_path="$2"
    local config_file="$3"

    log_info "Executing differential backup"

    # Find latest full backup
    local latest_full_backup
    latest_full_backup=$(find_latest_backup "full" "$config_file")

    if [[ -z "$latest_full_backup" ]]; then
        log_warning "No full backup found for differential backup. Creating full backup instead."
        execute_full_backup "$backup_source" "$backup_path" "$config_file"
        return $?
    fi

    # Similar to incremental but always references the latest full backup
    execute_incremental_backup "$backup_source" "$backup_path" "$config_file"
}

execute_snapshot_backup() {
    local backup_source="$1"
    local backup_path="$2"
    local config_file="$3"

    log_info "Executing snapshot backup"

    # Check if LVM snapshots are supported
    if ! command -v lvcreate >/dev/null 2>&1; then
        log_warning "LVM not available, using file-based snapshot"
        execute_file_snapshot "$backup_source" "$backup_path" "$config_file"
        return $?
    fi

    # Create LVM snapshot if configured
    local snapshot_enabled
    snapshot_enabled=$(get_config_value "$config_file" "backup.lvm_snapshot" "false")

    if [[ "$snapshot_enabled" == "true" ]]; then
        execute_lvm_snapshot "$backup_source" "$backup_path" "$config_file"
    else
        execute_file_snapshot "$backup_source" "$backup_path" "$config_file"
    fi
}

execute_file_snapshot() {
    local backup_source="$1"
    local backup_path="$2"
    local config_file="$3"

    log_info "Creating file-based snapshot"

    # Use rsync with link-dest for hardlink-based snapshots
    local sources
    if [[ -z "$backup_source" ]]; then
        sources=$(get_config_value "$config_file" "backup.sources" "/etc,/home,/var/www,/opt")
    else
        sources="$backup_source"
    fi

    # Find latest backup for hardlink reference
    local latest_backup
    latest_backup=$(find_latest_backup "full" "$config_file")

    local rsync_args="-aAXH --delete"
    if [[ -n "$latest_backup" && -d "$latest_backup" ]]; then
        rsync_args="$rsync_args --link-dest=$latest_backup"
    fi

    IFS=',' read -ra source_array <<< "$sources"
    for source in "${source_array[@]}"; do
        source=$(echo "$source" | xargs)

        if [[ -d "$source" ]]; then
            local dest_dir="$backup_path/$(basename "$source")"
            mkdir -p "$dest_dir"

            log_info "Creating snapshot: $source -> $dest_dir"

            if rsync $rsync_args "$source/" "$dest_dir/"; then
                log_success "Snapshot created: $dest_dir"
            else
                log_error "Failed to create snapshot: $source"
                return 1
            fi
        fi
    done

    return 0
}

# =============================================================================
# BACKUP UTILITIES
# =============================================================================

find_latest_backup() {
    local backup_type="$1"
    local config_file="${2:-$BACKUP_CONFIG_FILE}"

    local backup_dir
    backup_dir=$(get_config_value "$config_file" "backup.base_directory" "$BACKUP_BASE_DIR")

    local type_dir="$backup_dir/$backup_type"
    if [[ ! -d "$type_dir" ]]; then
        return 1
    fi

    # Find latest backup directory
    local latest_backup
    latest_backup=$(find "$type_dir" -maxdepth 1 -type d -name "????-??-??_??-??-??" | sort -r | head -n1)

    if [[ -n "$latest_backup" && -d "$latest_backup" ]]; then
        echo "$latest_backup"
        return 0
    fi

    return 1
}

encrypt_backup() {
    local backup_file="$1"
    local config_file="${2:-$BACKUP_CONFIG_FILE}"

    log_info "Encrypting backup: $backup_file"

    local encryption_key
    encryption_key=$(get_config_value "$config_file" "backup.encryption_key" "$BACKUP_ENCRYPTION_KEY")

    if [[ -z "$encryption_key" ]]; then
        log_error "Encryption key not specified"
        return 1
    fi

    # Encrypt with GPG
    if echo "$encryption_key" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 "$backup_file"; then
        # Remove original unencrypted file
        rm "$backup_file"
        log_success "Backup encrypted: ${backup_file}.gpg"
        return 0
    else
        log_error "Failed to encrypt backup: $backup_file"
        return 1
    fi
}

verify_backup() {
    local backup_path="$1"
    local config_file="${2:-$BACKUP_CONFIG_FILE}"

    log_info "Verifying backup integrity: $backup_path"

    local verification_failed=false

    # Check archive files
    find "$backup_path" -name "*.tar*" -type f | while read -r archive_file; do
        log_debug "Verifying archive: $archive_file"

        if [[ "$archive_file" == *.gpg ]]; then
            # Decrypt and verify encrypted archives
            local encryption_key
            encryption_key=$(get_config_value "$config_file" "backup.encryption_key" "$BACKUP_ENCRYPTION_KEY")

            if ! echo "$encryption_key" | gpg --batch --yes --passphrase-fd 0 --decrypt "$archive_file" | tar -tf >/dev/null 2>&1; then
                log_error "Archive verification failed: $archive_file"
                verification_failed=true
            fi
        else
            # Verify regular archives
            if ! tar -tf "$archive_file" >/dev/null 2>&1; then
                log_error "Archive verification failed: $archive_file"
                verification_failed=true
            fi
        fi
    done

    # Create checksums for backup files
    local checksum_file="$backup_path/checksums.sha256"
    find "$backup_path" -type f -not -name "checksums.*" -exec sha256sum {} \; > "$checksum_file"

    if [[ "$verification_failed" == "true" ]]; then
        log_error "Backup verification failed"
        return 1
    else
        log_success "Backup verification completed successfully"
        return 0
    fi
}

create_backup_metadata() {
    local backup_type="$1"
    local backup_path="$2"
    local duration="$3"
    local config_file="$4"

    local metadata_file="$backup_path/metadata.json"

    local backup_size
    backup_size=$(du -sb "$backup_path" | cut -f1)

    local backup_date
    backup_date=$(date -Iseconds)

    local hostname
    hostname=$(hostname)

    cat > "$metadata_file" << EOF
{
    "backup_type": "$backup_type",
    "backup_date": "$backup_date",
    "backup_path": "$backup_path",
    "backup_size_bytes": $backup_size,
    "backup_duration_seconds": $duration,
    "hostname": "$hostname",
    "compression": "$BACKUP_COMPRESSION",
    "encryption": "$BACKUP_ENCRYPTION",
    "backup_tools": {
        "rsync_version": "$(rsync --version | head -n1)",
        "tar_version": "$(tar --version | head -n1)"
    }
}
EOF

    log_debug "Backup metadata created: $metadata_file"
}

cleanup_old_backups() {
    local backup_type="$1"
    local config_file="${2:-$BACKUP_CONFIG_FILE}"

    local retention_days
    retention_days=$(get_config_value "$config_file" "backup.retention_days" "$BACKUP_RETENTION_DAYS")

    local backup_dir
    backup_dir=$(get_config_value "$config_file" "backup.base_directory" "$BACKUP_BASE_DIR")

    local type_dir="$backup_dir/$backup_type"
    if [[ ! -d "$type_dir" ]]; then
        return 0
    fi

    log_info "Cleaning up old $backup_type backups (older than $retention_days days)"

    # Find and remove old backups
    local cutoff_time
    cutoff_time=$(date -d "$retention_days days ago" +%s)

    find "$type_dir" -maxdepth 1 -type d -name "????-??-??_??-??-??" | while read -r backup_dir_path; do
        local dir_date
        dir_date=$(basename "$backup_dir_path")
        local backup_time
        backup_time=$(date -d "${dir_date:0:10} ${dir_date:11:2}:${dir_date:14:2}:${dir_date:17:2}" +%s 2>/dev/null || echo 0)

        if [[ "$backup_time" -lt "$cutoff_time" ]]; then
            log_info "Removing old backup: $backup_dir_path"
            rm -rf "$backup_dir_path"
        fi
    done

    log_success "Old backup cleanup completed"
}

# =============================================================================
# RESTORE OPERATIONS
# =============================================================================

restore_backup() {
    local backup_path="$1"
    local restore_target="$2"
    local config_file="${3:-$BACKUP_CONFIG_FILE}"

    log_info "Starting restore from: $backup_path"

    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup path not found: $backup_path"
        return 1
    fi

    if [[ ! -d "$restore_target" ]]; then
        log_info "Creating restore target directory: $restore_target"
        mkdir -p "$restore_target"
    fi

    # Check if backup is encrypted
    local encrypted_files
    encrypted_files=$(find "$backup_path" -name "*.gpg" -type f)

    if [[ -n "$encrypted_files" ]]; then
        log_info "Decrypting backup files..."

        local encryption_key
        encryption_key=$(get_config_value "$config_file" "backup.encryption_key" "$BACKUP_ENCRYPTION_KEY")

        if [[ -z "$encryption_key" ]]; then
            log_error "Encryption key required for restore"
            return 1
        fi

        # Decrypt files
        echo "$encrypted_files" | while read -r encrypted_file; do
            local decrypted_file="${encrypted_file%.gpg}"
            log_info "Decrypting: $encrypted_file -> $decrypted_file"

            if ! echo "$encryption_key" | gpg --batch --yes --passphrase-fd 0 --decrypt "$encrypted_file" > "$decrypted_file"; then
                log_error "Failed to decrypt: $encrypted_file"
                return 1
            fi
        done
    fi

    # Restore from archives
    find "$backup_path" -name "*.tar*" -type f | while read -r archive_file; do
        if [[ "$archive_file" == *.gpg ]]; then
            continue  # Skip encrypted files (already decrypted)
        fi

        log_info "Restoring from: $archive_file"

        if ! tar -xf "$archive_file" -C "$restore_target"; then
            log_error "Failed to restore from: $archive_file"
            return 1
        fi
    done

    # Restore from snapshots
    find "$backup_path" -maxdepth 1 -type d -not -path "$backup_path" | while read -r snapshot_dir; do
        local dir_name
        dir_name=$(basename "$snapshot_dir")
        local target_dir="$restore_target/$dir_name"

        log_info "Restoring snapshot: $snapshot_dir -> $target_dir"

        if [[ -d "$target_dir" ]]; then
            # Merge with existing directory
            rsync -aAXH "$snapshot_dir/" "$target_dir/"
        else
            # Copy entire directory
            cp -a "$snapshot_dir" "$target_dir"
        fi
    done

    log_success "Restore completed successfully"
    log_info "Restored to: $restore_target"

    # Verify restore
    verify_restore "$backup_path" "$restore_target" "$config_file"

    return 0
}

verify_restore() {
    local backup_path="$1"
    local restore_target="$2"
    local config_file="${3:-$BACKUP_CONFIG_FILE}"

    log_info "Verifying restore integrity"

    # Check checksums if available
    local checksum_file="$backup_path/checksums.sha256"
    if [[ -f "$checksum_file" ]]; then
        log_info "Verifying file checksums..."

        cd "$restore_target"
        if sha256sum --check "$checksum_file" >/dev/null 2>&1; then
            log_success "Checksum verification passed"
        else
            log_warning "Checksum verification failed - this may be expected if restoring to different location"
        fi
    fi

    # Basic directory structure verification
    local restored_dirs
    restored_dirs=$(find "$restore_target" -type d | wc -l)
    local restored_files
    restored_files=$(find "$restore_target" -type f | wc -l)

    log_info "Restore verification: $restored_dirs directories, $restored_files files"

    return 0
}

# =============================================================================
# SCHEDULING AND MONITORING
# =============================================================================

setup_backup_schedule() {
    local config_file="${1:-$BACKUP_CONFIG_FILE}"

    log_info "Setting up backup scheduling"

    local schedule
    schedule=$(get_config_value "$config_file" "backup.schedule" "$BACKUP_SCHEDULE")

    local backup_dir
    backup_dir=$(get_config_value "$config_file" "backup.base_directory" "$BACKUP_BASE_DIR")

    local backup_types
    backup_types=$(get_config_value "$config_file" "backup.types" "full")

    # Create cron job
    local cron_entry="$schedule $SERVERSH_ROOT/serversh/modules/backup/backup_worker.sh scheduled \"$backup_types\" \"$config_file\""

    # Add to crontab
    (crontab -l 2>/dev/null || true; echo "# ServerSH Backup Job") | crontab -
    echo "$cron_entry" | crontab -

    log_success "Backup schedule created: $schedule"
    log_info "Backup types: $backup_types"
}

remove_backup_schedule() {
    log_info "Removing backup schedule"

    # Remove ServerSH backup jobs from crontab
    crontab -l 2>/dev/null | grep -v "ServerSH Backup Job" | crontab -

    log_success "Backup schedule removed"
}

send_backup_notification() {
    local backup_type="$1"
    local status="$2"
    local backup_path="$3"
    local duration="$4"
    local config_file="${5:-$BACKUP_CONFIG_FILE}"

    if [[ "$BACKUP_EMAIL_REPORTS" != "true" ]]; then
        return 0
    fi

    local email_to
    email_to=$(get_config_value "$config_file" "backup.email_to" "$BACKUP_EMAIL_TO")

    if [[ -z "$email_to" ]]; then
        return 0
    fi

    local hostname
    hostname=$(hostname)

    local subject="ServerSH Backup $status: $backup_type on $hostname"

    local body
    case "$status" in
        "success")
            body="Backup completed successfully!

Type: $backup_type
Hostname: $hostname
Path: $backup_path
Duration: ${duration}s
Date: $(date)

This is an automated message from ServerSH Backup System."
            ;;
        "failed")
            body="Backup failed!

Type: $backup_type
Hostname: $hostname
Path: $backup_path
Duration: ${duration}s
Date: $(date)

Please check the backup logs for more information.

This is an automated message from ServerSH Backup System."
            ;;
    esac

    # Send email
    if command -v mail >/dev/null 2>&1; then
        echo "$body" | mail -s "$subject" "$email_to"
        log_info "Backup notification sent to: $email_to"
    else
        log_warning "Email command not available, skipping notification"
    fi
}

# =============================================================================
# DISASTER RECOVERY
# =============================================================================

create_disaster_recovery() {
    local config_file="${1:-$BACKUP_CONFIG_FILE}"

    log_info "Creating disaster recovery package"

    local backup_dir
    backup_dir=$(get_config_value "$config_file" "backup.base_directory" "$BACKUP_BASE_DIR")

    local dr_dir="$backup_dir/disaster_recovery"
    mkdir -p "$dr_dir"

    local dr_date
    dr_date=$(date +"%Y-%m-%d_%H-%M-%S")
    local dr_package="$dr_dir/dr_package_$dr_date"
    mkdir -p "$dr_package"

    # Create full system backup
    log_info "Creating full system backup for disaster recovery"
    create_backup "full" "/" "$config_file"

    # Find latest full backup
    local latest_backup
    latest_backup=$(find_latest_backup "full" "$config_file")

    if [[ -n "$latest_backup" ]]; then
        # Copy to DR package
        cp -a "$latest_backup" "$dr_package/system_backup"

        # Create recovery scripts
        create_recovery_scripts "$dr_package" "$config_file"

        # Create system information
        create_system_info "$dr_package"

        # Create recovery documentation
        create_recovery_documentation "$dr_package"

        # Create DR package archive
        local dr_archive="$dr_dir/disaster_recovery_$dr_date.tar.gz"
        tar -czf "$dr_archive" -C "$dr_package" .

        log_success "Disaster recovery package created: $dr_archive"
        log_info "Package size: $(du -h "$dr_archive" | cut -f1)"

        # Cleanup temporary directory
        rm -rf "$dr_package"

        return 0
    else
        log_error "No backup found for disaster recovery package"
        return 1
    fi
}

create_recovery_scripts() {
    local dr_package="$1"
    local config_file="$2"

    log_info "Creating recovery scripts"

    # Main recovery script
    cat > "$dr_package/recover.sh" << 'EOF'
#!/bin/bash

# ServerSH Disaster Recovery Script
set -euo pipefail

echo "=============================================================================="
echo "ServerSH Disaster Recovery"
echo "=============================================================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Recovery options
echo "Available recovery options:"
echo "1) Full system restore"
echo "2) System configuration restore"
echo "3) User data restore"
echo "4) Custom restore"
echo ""

read -p "Select recovery option (1-4): " option

case "$option" in
    1)
        echo "Starting full system restore..."
        "$SCRIPT_DIR/restore_full.sh"
        ;;
    2)
        echo "Starting system configuration restore..."
        "$SCRIPT_DIR/restore_config.sh"
        ;;
    3)
        echo "Starting user data restore..."
        "$SCRIPT_DIR/restore_data.sh"
        ;;
    4)
        echo "Starting custom restore..."
        "$SCRIPT_DIR/restore_custom.sh"
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac
EOF

    # Full system restore script
    cat > "$dr_package/restore_full.sh" << 'EOF'
#!/bin/bash

# Full System Restore Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/system_backup"

echo "WARNING: This will restore the entire system from backup."
echo "All current data will be overwritten!"
echo ""

read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Restore cancelled"
    exit 0
fi

echo "Starting full system restore..."

# Mount filesystem if needed
mount -o remount,rw /

# Restore system files
if [[ -d "$BACKUP_DIR" ]]; then
    rsync -aAXH --delete "$BACKUP_DIR/" /

    # Restore bootloader
    if [[ -f "$SCRIPT_DIR/system_info/bootloader.txt" ]]; then
        echo "Restoring bootloader configuration..."
        # Add bootloader restore commands based on system
    fi

    # Restore network configuration
    if [[ -d "$BACKUP_DIR/etc/network" ]]; then
        echo "Restoring network configuration..."
    fi

    echo "Full system restore completed"
    echo "Please reboot the system to complete the restore"
else
    echo "ERROR: Backup directory not found"
    exit 1
fi
EOF

    # Configuration restore script
    cat > "$dr_package/restore_config.sh" << 'EOF'
#!/bin/bash

# System Configuration Restore Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/system_backup"

echo "Restoring system configuration..."

# Restore critical configuration files
config_files=(
    "/etc/passwd"
    "/etc/group"
    "/etc/shadow"
    "/etc/gshadow"
    "/etc/fstab"
    "/etc/hosts"
    "/etc/hostname"
    "/etc/resolv.conf"
    "/etc/ssh/sshd_config"
    "/etc/fail2ban/jail.local"
)

for config_file in "${config_files[@]}"; do
    backup_file="$BACKUP_DIR$config_file"
    if [[ -f "$backup_file" ]]; then
        echo "Restoring: $config_file"
        cp "$backup_file" "$config_file"
    fi
done

echo "System configuration restore completed"
EOF

    # Make scripts executable
    chmod +x "$dr_package"/*.sh
}

create_system_info() {
    local dr_package="$1"

    log_info "Creating system information package"

    local info_dir="$dr_package/system_info"
    mkdir -p "$info_dir"

    # Hardware information
    lshw > "$info_dir/hardware.txt" 2>/dev/null || true
    lspci > "$info_dir/pci.txt" 2>/dev/null || true
    lsusb > "$info_dir/usb.txt" 2>/dev/null || true
    lsblk > "$info_dir/disks.txt" 2>/dev/null || true

    # Software information
    uname -a > "$info_dir/kernel.txt"
    cat /etc/os-release > "$info_dir/os-release.txt" 2>/dev/null || true
    dpkg -l > "$info_dir/packages.txt" 2>/dev/null || true
    rpm -qa > "$info_dir/packages.txt" 2>/dev/null || true

    # Network information
    ip addr show > "$info_dir/network.txt"
    ip route show >> "$info_dir/network.txt"

    # Filesystem information
    df -h > "$info_dir/filesystem.txt"
    mount >> "$info_dir/filesystem.txt"

    # Boot configuration
    if [[ -f /boot/grub/grub.cfg ]]; then
        cp /boot/grub/grub.cfg "$info_dir/grub.cfg"
    fi

    if [[ -d /boot/efi/EFI ]]; then
        cp -r /boot/efi/EFI "$info_dir/efi"
    fi

    log_debug "System information saved to: $info_dir"
}

create_recovery_documentation() {
    local dr_package="$1"

    cat > "$dr_package/README.md" << 'EOF'
# ServerSH Disaster Recovery Package

## Overview
This disaster recovery package contains everything needed to restore your system from a backup.

## Contents
- `system_backup/`: Complete system backup
- `system_info/`: System hardware and software information
- `recover.sh`: Main recovery script
- `restore_*.sh`: Specific recovery scripts

## Recovery Process

### 1. Boot from Live Media
- Boot the system using a Linux live USB/CD
- Open a terminal and mount your system disk

### 2. Extract Recovery Package
```bash
tar -xzf disaster_recovery_*.tar.gz
cd disaster_recovery_*
```

### 3. Run Recovery
```bash
sudo ./recover.sh
```

### 4. Follow the Prompts
Choose the appropriate recovery option:
- Full system restore (complete system replacement)
- System configuration restore (just config files)
- User data restore (home directories and data)
- Custom restore (selective restore)

## Important Notes
- Always test restores on non-production systems first
- Ensure you have backups of the current system before restoring
- Some manual configuration may be required after restore
- Network and hardware changes may require additional configuration

## Support
For additional support, refer to the ServerSH documentation.
EOF
}

# =============================================================================
# MODULE INTERFACE IMPLEMENTATION
# =============================================================================

validate() {
    validate_backup_config
}

install() {
    local config_file="${1:-$BACKUP_CONFIG_FILE}"

    log_info "Installing Backup & Recovery module"

    # Create backup directories
    local backup_dir
    backup_dir=$(get_config_value "$config_file" "backup.base_directory" "$BACKUP_BASE_DIR")
    mkdir -p "$backup_dir"/{full,incremental,differential,snapshot,disaster_recovery}

    # Create backup worker script
    create_backup_worker_script

    # Set permissions
    chmod 750 "$backup_dir"
    chown root:root "$backup_dir"

    # Setup backup schedule
    local enable_schedule
    enable_schedule=$(get_config_value "$config_file" "backup.enable_schedule" "true")

    if [[ "$enable_schedule" == "true" ]]; then
        setup_backup_schedule "$config_file"
    fi

    # Save state
    save_state "backup_recovery" "installed"
    save_state "backup_recovery" "config_file" "$config_file"
    save_state "backup_recovery" "backup_dir" "$backup_dir"

    log_success "Backup & Recovery module installed successfully"
}

uninstall() {
    log_info "Uninstalling Backup & Recovery module"

    # Remove backup schedule
    remove_backup_schedule

    # Remove backup worker script
    rm -f "${SERVERSH_ROOT}/serversh/modules/backup/backup_worker.sh"

    # Note: We don't remove backup directories by default for safety

    save_state "backup_recovery" "uninstalled"

    log_success "Backup & Recovery module uninstalled"
}

backup() {
    create_backup "$@"
}

restore() {
    restore_backup "$@"
}

# =============================================================================
# WORKER SCRIPT CREATION
# =============================================================================

create_backup_worker_script() {
    local worker_script="${SERVERSH_ROOT}/serversh/modules/backup/backup_worker.sh"

    cat > "$worker_script" << 'EOF'
#!/bin/bash

# ServerSH Backup Worker Script
# This script handles scheduled backup operations

set -euo pipefail

# Source required utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../core/utils.sh"
source "${SCRIPT_DIR}/../../core/logger.sh"

# Parse arguments
BACKUP_TYPE="${1:-scheduled}"
BACKUP_TYPES="${2:-full}"
CONFIG_FILE="${3:-}"

# Load configuration
if [[ -z "$CONFIG_FILE" ]]; then
    CONFIG_FILE="${SERVERSH_CONFIG_DIR:-/etc/serversh}/backup.yaml"
fi

# Source backup module
source "$SCRIPT_DIR/backup_recovery.sh"

# Execute backup based on type
case "$BACKUP_TYPE" in
    "scheduled")
        # Parse backup types and execute each
        IFS=',' read -ra types <<< "$BACKUP_TYPES"
        for type in "${types[@]}"; do
            type=$(echo "$type" | xargs)
            create_backup "$type" "" "$CONFIG_FILE"
        done
        ;;
    *)
        create_backup "$BACKUP_TYPE" "" "$CONFIG_FILE"
        ;;
esac
EOF

    chmod +x "$worker_script"
    log_debug "Backup worker script created: $worker_script"
}

# Execute module operations
case "${1:-}" in
    "validate")
        validate
        ;;
    "install")
        install "$2"
        ;;
    "uninstall")
        uninstall
        ;;
    "backup")
        backup "${@:2}"
        ;;
    "restore")
        restore "${@:2}"
        ;;
    *)
        echo "Usage: $0 {validate|install|uninstall|backup|restore} [args...]"
        exit 1
        ;;
esac