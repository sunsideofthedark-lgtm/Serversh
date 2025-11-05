#!/bin/bash

# =============================================================================
# Module: System Update
# Category: System
# Description: Updates system packages to latest versions
# Version: 1.0.0
# =============================================================================

# Source module interface
source "${SERVERSH_LIB_DIR}/module_interface.sh" || exit $EXIT_MISSING_DEPS

# =============================================================================
# Required Functions
# =============================================================================

module_get_name() {
    echo "system/update"
    return $MODULE_SUCCESS
}

module_get_version() {
    echo "1.0.0"
    return $MODULE_SUCCESS
}

module_get_description() {
    echo "Updates system packages to latest versions with OS-specific package managers"
    return $MODULE_SUCCESS
}

module_get_category() {
    echo "$MODULE_CATEGORY_SYSTEM"
    return $MODULE_SUCCESS
}

module_get_dependencies() {
    echo ""
    return $MODULE_SUCCESS
}

module_validate_config() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Validating configuration for module: $module_name"

    # Get configuration options
    local auto_update
    auto_update=$(module_config_get "auto_update" "true")
    local exclude_packages
    exclude_packages=$(module_config_get "exclude_packages" "")
    local reboot_required
    reboot_required=$(module_config_get "reboot_required" "false")

    # Validate auto_update option
    if [[ "$auto_update" != "true" && "$auto_update" != "false" ]]; then
        module_log "ERROR" "Invalid auto_update value: $auto_update (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate reboot_required option
    if [[ "$reboot_required" != "true" && "$reboot_required" != "false" ]]; then
        module_log "ERROR" "Invalid reboot_required value: $reboot_required (must be true or false)"
        return $MODULE_CONFIG_ERROR
    fi

    # Validate exclude_packages format
    if [[ -n "$exclude_packages" ]]; then
        # Should be comma-separated list
        if [[ "$exclude_packages" =~ [^a-zA-Z0-9,_-] ]]; then
            module_log "ERROR" "Invalid characters in exclude_packages: $exclude_packages"
            return $MODULE_CONFIG_ERROR
        fi
    fi

    module_log "DEBUG" "Configuration validation passed"
    module_log "DEBUG" "  auto_update: $auto_update"
    module_log "DEBUG" "  exclude_packages: $exclude_packages"
    module_log "DEBUG" "  reboot_required: $reboot_required"

    return $MODULE_SUCCESS
}

module_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Installing module: $module_name"
    module_log "INFO" "Updating system packages"

    # Get OS information
    local os_id
    os_id=$(get_system_info "os")
    module_log "DEBUG" "Detected OS: $os_id"

    # OS-specific update logic
    case "$os_id" in
        ubuntu|debian)
            update_debian_system
            ;;
        centos|rhel|rocky|almalinux)
            update_redhat_system
            ;;
        fedora)
            update_fedora_system
            ;;
        opensuse*)
            update_suse_system
            ;;
        arch)
            update_arch_system
            ;;
        *)
            module_log "ERROR" "Unsupported OS for system updates: $os_id"
            return $MODULE_ERROR
            ;;
    esac

    local update_result=$?
    if [[ $update_result -eq $MODULE_SUCCESS ]]; then
        module_log "SUCCESS" "System packages updated successfully"

        # Check if reboot is required
        check_reboot_requirement
    else
        module_log "ERROR" "System update failed"
        return $MODULE_ERROR
    fi

    return $MODULE_SUCCESS
}

module_verify() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Verifying system update: $module_name"

    # Get OS information
    local os_id
    os_id=$(get_system_info "os")

    # Verify based on package manager
    case "$os_id" in
        ubuntu|debian)
            verify_debian_update
            ;;
        centos|rhel|rocky|almalinux|fedora)
            verify_redhat_update
            ;;
        opensuse*)
            verify_suse_update
            ;;
        arch)
            verify_arch_update
            ;;
        *)
            module_log "WARN" "Cannot verify update for unsupported OS: $os_id"
            return $MODULE_SUCCESS
            ;;
    esac

    return $MODULE_SUCCESS
}

# =============================================================================
# Optional Functions
# =============================================================================

module_pre_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running pre-installation for module: $module_name"

    # Check if we recently updated (within last hour)
    local update_marker="${SERVERSH_STATE_DIR}/last_system_update"
    local current_time
    current_time=$(unix_timestamp)

    if [[ -f "$update_marker" ]]; then
        local last_update
        last_update=$(cat "$update_marker" 2>/dev/null || echo "0")
        local time_diff=$((current_time - last_update))

        if [[ $time_diff -lt 3600 ]]; then
            local time_remaining=$((3600 - time_diff))
            module_log "INFO" "System was recently updated. Skipping update for $((time_remaining / 60)) more minutes."
            return $MODULE_SKIP
        fi
    fi

    # Check network connectivity
    if ! check_network_connectivity; then
        module_log "WARN" "No network connectivity. Update may fail."
        # Continue anyway - some systems have local package caches
    fi

    # Check available disk space for updates
    local var_space
    var_space=$(df /var 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    local var_space_gb=$((var_space / 1024 / 1024))

    if [[ $var_space_gb -lt 1 ]]; then
        module_log "WARN" "Low disk space in /var (${var_space_gb}GB). Update may fail."
    fi

    return $MODULE_SUCCESS
}

module_post_install() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running post-installation for module: $module_name"

    # Record update timestamp
    local update_marker="${SERVERSH_STATE_DIR}/last_system_update"
    local current_time
    current_time=$(unix_timestamp)
    echo "$current_time" > "$update_marker"

    # Clean up package caches if configured
    local cleanup_cache
    cleanup_cache=$(module_config_get "cleanup_cache" "true")
    if [[ "$cleanup_cache" == "true" ]]; then
        cleanup_package_cache
    fi

    return $MODULE_SUCCESS
}

module_rollback() {
    local module_name
    module_name=$(module_get_name)

    module_log "WARN" "Rolling back module: $module_name"

    # System updates are generally not rollbackable in a safe way
    # We can only remove the update marker
    local update_marker="${SERVERSH_STATE_DIR}/last_system_update"
    rm -f "$update_marker"

    module_log "INFO" "Removed update timestamp marker"
    module_log "WARN" "Note: Actual package rollback requires manual intervention"

    return $MODULE_SUCCESS
}

module_cleanup() {
    local module_name
    module_name=$(module_get_name)

    module_log "DEBUG" "Running cleanup for module: $module_name"

    # Remove any temporary files
    rm -f "${SERVERSH_STATE_DIR}/update_*.tmp" 2>/dev/null || true

    return $MODULE_SUCCESS
}

# =============================================================================
# OS-Specific Update Functions
# =============================================================================

update_debian_system() {
    module_log "INFO" "Updating Debian/Ubuntu system"

    # Update package lists
    module_log "INFO" "Updating package lists..."
    if ! apt-get update; then
        module_log "ERROR" "Failed to update package lists"
        return $MODULE_ERROR
    fi

    # Get exclude packages configuration
    local exclude_packages
    exclude_packages=$(module_config_get "exclude_packages" "")

    # Perform system upgrade
    module_log "INFO" "Upgrading packages..."
    local apt_cmd="apt-get upgrade -y"

    if [[ -n "$exclude_packages" ]]; then
        # Convert comma-separated to space-separated for apt
        local excluded_list
        excluded_list=$(echo "$exclude_packages" | tr ',' ' ')
        apt_cmd="apt-get upgrade -y --ignore-missing --no-install-recommends"
    fi

    if ! eval "$apt_cmd"; then
        module_log "ERROR" "Failed to upgrade packages"
        return $MODULE_ERROR
    fi

    # Perform full system upgrade (including kernel)
    module_log "INFO" "Performing full system upgrade..."
    if ! apt-get dist-upgrade -y; then
        module_log "ERROR" "Failed to perform full system upgrade"
        return $MODULE_ERROR
    fi

    # Remove unused packages
    module_log "INFO" "Removing unused packages..."
    apt-get autoremove -y || true

    # Clean package cache
    module_log "INFO" "Cleaning package cache..."
    apt-get autoclean || true

    return $MODULE_SUCCESS
}

update_redhat_system() {
    module_log "INFO" "Updating RHEL/CentOS system"

    local pkg_manager="yum"
    if command_exists dnf; then
        pkg_manager="dnf"
    fi

    # Update package metadata
    module_log "INFO" "Updating package metadata..."
    if ! $pkg_manager check-update; then
        module_log "ERROR" "Failed to check for updates"
        return $MODULE_ERROR
    fi

    # Update all packages
    module_log "INFO" "Updating all packages..."
    if ! $pkg_manager update -y; then
        module_log "ERROR" "Failed to update packages"
        return $MODULE_ERROR
    fi

    # Clean package cache
    module_log "INFO" "Cleaning package cache..."
    $pkg_manager clean all || true

    return $MODULE_SUCCESS
}

update_fedora_system() {
    module_log "INFO" "Updating Fedora system"

    # Refresh package metadata
    module_log "INFO" "Refreshing package metadata..."
    if ! dnf makecache; then
        module_log "ERROR" "Failed to refresh package metadata"
        return $MODULE_ERROR
    fi

    # Update all packages
    module_log "INFO" "Updating all packages..."
    if ! dnf upgrade -y; then
        module_log "ERROR" "Failed to update packages"
        return $MODULE_ERROR
    fi

    # Clean package cache
    module_log "INFO" "Cleaning package cache..."
    dnf clean all || true

    return $MODULE_SUCCESS
}

update_suse_system() {
    module_log "INFO" "Updating openSUSE system"

    # Refresh repositories
    module_log "INFO" "Refreshing repositories..."
    if ! zypper refresh; then
        module_log "ERROR" "Failed to refresh repositories"
        return $MODULE_ERROR
    fi

    # Update all packages
    module_log "INFO" "Updating all packages..."
    if ! zypper update -y; then
        module_log "ERROR" "Failed to update packages"
        return $MODULE_ERROR
    fi

    # Clean package cache
    module_log "INFO" "Cleaning package cache..."
    zypper clean --all || true

    return $MODULE_SUCCESS
}

update_arch_system() {
    module_log "INFO" "Updating Arch Linux system"

    # Update package databases
    module_log "INFO" "Updating package databases..."
    if ! pacman -Sy; then
        module_log "ERROR" "Failed to update package databases"
        return $MODULE_ERROR
    fi

    # Update all packages
    module_log "INFO" "Updating all packages..."
    if ! pacman -Syu --noconfirm; then
        module_log "ERROR" "Failed to update packages"
        return $MODULE_ERROR
    fi

    # Remove orphan packages
    module_log "INFO" "Removing orphan packages..."
    if pacman -Qtdq >/dev/null; then
        pacman -Rns $(pacman -Qtdq) --noconfirm || true
    fi

    # Clean package cache
    module_log "INFO" "Cleaning package cache..."
    pacman -Scc --noconfirm || true

    return $MODULE_SUCCESS
}

# =============================================================================
# Verification Functions
# =============================================================================

verify_debian_update() {
    module_log "DEBUG" "Verifying Debian/Ubuntu update"

    # Check if there are packages available for update
    local updates_available
    updates_available=$(apt list --upgradable 2>/dev/null | wc -l)
    updates_available=$((updates_available - 1))  # Subtract header line

    if [[ $updates_available -gt 0 ]]; then
        module_log "WARN" "There are still $updates_available packages available for update"
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "No pending updates available"
    return $MODULE_SUCCESS
}

verify_redhat_update() {
    module_log "DEBUG" "Verifying RHEL/CentOS/Fedora update"

    local pkg_manager="yum"
    if command_exists dnf; then
        pkg_manager="dnf"
    fi

    # Check for available updates
    if $pkg_manager check-update | grep -q "^\."; then
        module_log "WARN" "There are still packages available for update"
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "No pending updates available"
    return $MODULE_SUCCESS
}

verify_suse_update() {
    module_log "DEBUG" "Verifying openSUSE update"

    # Check for available updates
    if zypper list-updates | grep -q "^v"; then
        module_log "WARN" "There are still packages available for update"
        return $MODULE_ERROR
    fi

    module_log "DEBUG" "No pending updates available"
    return $MODULE_SUCCESS
}

verify_arch_update() {
    module_log "DEBUG" "Verifying Arch Linux update"

    # Arch Linux is rolling release, so we check if last sync was recent
    local last_sync_file="/var/lib/pacman/sync/core.db"
    if [[ -f "$last_sync_file" ]]; then
        local sync_time
        sync_time=$(stat -c %Y "$last_sync_file" 2>/dev/null || stat -f %m "$last_sync_file" 2>/dev/null)
        local current_time
        current_time=$(unix_timestamp)
        local time_diff=$((current_time - sync_time))

        # If sync was within last hour, consider it up to date
        if [[ $time_diff -lt 3600 ]]; then
            module_log "DEBUG" "Package databases are up to date"
            return $MODULE_SUCCESS
        fi
    fi

    module_log "WARN" "Package databases may be out of date"
    return $MODULE_ERROR
}

# =============================================================================
# Helper Functions
# =============================================================================

check_reboot_requirement() {
    local reboot_required
    reboot_required=$(module_config_get "reboot_required" "false")

    if [[ "$reboot_required" != "true" ]]; then
        module_log "DEBUG" "Reboot requirement check disabled by configuration"
        return $MODULE_SUCCESS
    fi

    local os_id
    os_id=$(get_system_info "os")
    local reboot_needed=false

    case "$os_id" in
        ubuntu|debian)
            # Check if a new kernel was installed
            if [[ -f /var/run/reboot-required ]]; then
                reboot_needed=true
                module_log "INFO" "Reboot required: /var/run/reboot-required exists"
            fi
            ;;
        centos|rhel|rocky|almalinux|fedora)
            # Check if kernel was updated
            local running_kernel
            running_kernel=$(uname -r)
            local latest_kernel
            latest_kernel=$(rpm -q --last kernel | head -1 | awk '{print $1}' | sed 's/kernel-//')

            if [[ "$running_kernel" != "$latest_kernel" ]]; then
                reboot_needed=true
                module_log "INFO" "Reboot required: kernel updated ($running_kernel -> $latest_kernel)"
            fi
            ;;
        arch)
            # Check for .pacnew files that require attention
            local pacnew_files
            pacnew_files=$(find /etc -name "*.pacnew" 2>/dev/null | wc -l)
            if [[ $pacnew_files -gt 0 ]]; then
                module_log "INFO" "Found $pacnew_files .pacnew files requiring attention"
                reboot_needed=true
            fi
            ;;
    esac

    if [[ "$reboot_needed" == true ]]; then
        # Store reboot requirement in state
        state_set "reboot_required" "true"
        module_log "WARN" "System reboot recommended after updates"

        # Create reboot marker
        echo "$(timestamp)" > "${SERVERSH_STATE_DIR}/reboot_required"
    fi
}

cleanup_package_cache() {
    module_log "DEBUG" "Cleaning package cache"

    local os_id
    os_id=$(get_system_info "os")

    case "$os_id" in
        ubuntu|debian)
            apt-get autoclean || true
            ;;
        centos|rhel|rocky|almalinux|fedora)
            if command_exists dnf; then
                dnf clean all || true
            else
                yum clean all || true
            fi
            ;;
        opensuse*)
            zypper clean --all || true
            ;;
        arch)
            pacman -Scc --noconfirm || true
            ;;
    esac
}

# Display update summary
show_update_summary() {
    local os_id
    os_id=$(get_system_info "os")
    local module_name
    module_name=$(module_get_name)

    module_log "INFO" "Update Summary for $module_name:"
    module_log "INFO" "  OS: $os_id"
    module_log "INFO" "  Update completed at: $(timestamp)"

    # Show package manager info
    case "$os_id" in
        ubuntu|debian)
            local package_count
            package_count=$(dpkg -l | grep "^ii" | wc -l)
            module_log "INFO" "  Installed packages: $package_count"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            local pkg_manager="yum"
            if command_exists dnf; then
                pkg_manager="dnf"
            fi
            module_log "INFO" "  Package manager: $pkg_manager"
            ;;
    esac
}

# Initialize module (optional - called when module is sourced)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    module_log "DEBUG" "System update module loaded"
fi

return $MODULE_SUCCESS