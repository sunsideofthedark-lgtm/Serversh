# Testing Framework Specification

## Overview

The testing framework provides comprehensive validation for the modular server setup system, including unit tests, integration tests, and end-to-end scenarios. The framework ensures reliability, security, and performance across all supported platforms.

## Testing Architecture

```
tests/
├── framework/
│   ├── test-runner.sh           # Main test runner
│   ├── assertions.sh            # Assertion functions
│   ├── mocks.sh                 # Mock utilities
│   └── fixtures/                # Test fixtures and data
├── unit/
│   ├── core/                    # Core framework tests
│   ├── utils/                   # Utility function tests
│   └── modules/                 # Module unit tests
├── integration/
│   ├── module-interactions/     # Module integration tests
│   ├── dependency-resolution/   # Dependency resolution tests
│   └── configuration/           # Configuration tests
├── e2e/
│   ├── scenarios/               # End-to-end scenarios
│   ├── performance/             # Performance tests
│   └── security/                # Security tests
├── helpers/
│   ├── test-environment.sh      # Test environment setup
│   ├── cleanup.sh               # Test cleanup
│   └── reporting.sh             # Test reporting
└── config/
    ├── test-config.yaml         # Test configuration
    └── environments/            # Test environment configs
```

## Test Framework Core

### Test Runner (`tests/framework/test-runner.sh`)

```bash
#!/bin/bash

# Test Runner Framework
# Version: 1.0.0

set -euo pipefail

# Framework configuration
readonly TEST_FRAMEWORK_VERSION="1.0.0"
readonly TEST_RESULTS_DIR="test-results"
readonly TEST_LOG_DIR="$TEST_RESULTS_DIR/logs"
readonly TEST_REPORT_DIR="$TEST_RESULTS_DIR/reports"

# Test statistics
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -g TEST_SKIPPED=0
declare -g CURRENT_SUITE=""
declare -g CURRENT_TEST=""

# Colors for output
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_BLUE='\033[0;34m'
readonly C_CYAN='\033[0;36m'
readonly C_RESET='\033[0m'

# Load framework components
source "$(dirname "$0")/assertions.sh"
source "$(dirname "$0")/mocks.sh"

# Initialize test environment
test_init() {
    local test_name="${1:-all}"

    echo -e "${C_BLUE}Initializing test framework v${TEST_FRAMEWORK_VERSION}${C_RESET}"
    echo "Test name: $test_name"
    echo "Timestamp: $(date)"
    echo

    # Create directories
    mkdir -p "$TEST_LOG_DIR" "$TEST_REPORT_DIR"

    # Initialize test results
    echo '{"tests": [], "summary": {}}' > "$TEST_RESULTS_DIR/results.json"

    # Load test configuration
    if [[ -f "tests/config/test-config.yaml" ]]; then
        source "$(dirname "$0")/../helpers/config-loader.sh"
        config_load "tests/config/test-config.yaml"
    fi

    # Setup test environment
    source "$(dirname "$0")/../helpers/test-environment.sh"
    test_env_setup
}

# Run test suite
run_test_suite() {
    local suite_path="$1"
    CURRENT_SUITE=$(basename "$suite_path")

    echo -e "${C_CYAN}Running test suite: $CURRENT_SUITE${C_RESET}"

    # Find and run test files
    find "$suite_path" -name "test_*.sh" -type f | sort | while read -r test_file; do
        run_test_file "$test_file"
    done

    echo
}

# Run individual test file
run_test_file() {
    local test_file="$1"
    CURRENT_TEST=$(basename "$test_file" .sh)

    echo -e "${C_BLUE}  Running: $CURRENT_TEST${C_RESET}"

    # Create test log file
    local test_log="$TEST_LOG_DIR/${CURRENT_SUITE}_${CURRENT_TEST}.log"

    # Run test in subshell to capture output
    (
        # Source test file
        source "$test_file"

        # Run setup if exists
        if declare -f setup >/dev/null; then
            setup
        fi

        # Run tests
        if declare -f run_tests >/dev/null; then
            run_tests
        else
            echo "No run_tests function found in $test_file"
            exit 1
        fi

        # Run cleanup if exists
        if declare -f cleanup >/dev/null; then
            cleanup
        fi
    ) 2>&1 | tee "$test_log"

    # Check test results
    if [[ $? -eq 0 ]]; then
        echo -e "    ${C_GREEN}✓ PASSED${C_RESET}"
        ((TEST_PASSED++))
    else
        echo -e "    ${C_RED}✗ FAILED${C_RESET}"
        ((TEST_FAILED++))
    fi

    ((TEST_TOTAL++))
}

# Generate test report
generate_report() {
    local report_file="$TEST_REPORT_DIR/test-report.html"

    echo -e "${C_CYAN}Generating test report...${C_RESET}"

    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Test Report - $(date)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f4f4f4; padding: 20px; border-radius: 5px; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .stat { background: #e9ecef; padding: 15px; border-radius: 5px; text-align: center; }
        .passed { background: #d4edda; color: #155724; }
        .failed { background: #f8d7da; color: #721c24; }
        .skipped { background: #fff3cd; color: #856404; }
        .test-suite { margin: 20px 0; }
        .test-case { margin: 10px 0; padding: 10px; border-left: 3px solid #ddd; }
        .test-case.passed { border-left-color: #28a745; }
        .test-case.failed { border-left-color: #dc3545; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Test Report</h1>
        <p>Generated: $(date)</p>
        <p>Framework Version: $TEST_FRAMEWORK_VERSION</p>
    </div>

    <div class="summary">
        <div class="stat">
            <h3>Total Tests</h3>
            <h2>$TEST_TOTAL</h2>
        </div>
        <div class="stat passed">
            <h3>Passed</h3>
            <h2>$TEST_PASSED</h2>
        </div>
        <div class="stat failed">
            <h3>Failed</h3>
            <h2>$TEST_FAILED</h2>
        </div>
        <div class="stat skipped">
            <h3>Skipped</h3>
            <h2>$TEST_SKIPPED</h2>
        </div>
    </div>

    <h2>Test Suites</h2>
EOF

    # Add test suite results
    for log_file in "$TEST_LOG_DIR"/*.log; do
        if [[ -f "$log_file" ]]; then
            local suite_name=$(basename "$log_file" .log)
            echo "    <div class=\"test-suite\">" >> "$report_file"
            echo "        <h3>$suite_name</h3>" >> "$report_file"

            # Parse log file for test results
            grep -E "(✓ PASSED|✗ FAILED)" "$log_file" | while read -r line; do
                local test_name=$(echo "$line" | sed 's/.*: //')
                local status="passed"
                if [[ "$line" =~ ✗ ]]; then
                    status="failed"
                fi
                echo "        <div class=\"test-case $status\">$test_name</div>" >> "$report_file"
            done

            echo "    </div>" >> "$report_file"
        fi
    done

    cat >> "$report_file" << EOF
</body>
</html>
EOF

    echo "Test report generated: $report_file"
}

# Cleanup test environment
test_cleanup() {
    echo -e "${C_CYAN}Cleaning up test environment...${C_RESET}"

    # Run cleanup helper
    source "$(dirname "$0")/../helpers/cleanup.sh"
    test_env_cleanup

    # Show final statistics
    echo
    echo -e "${C_BLUE}Test Results:${C_RESET}"
    echo "  Total: $TEST_TOTAL"
    echo -e "  Passed: ${C_GREEN}$TEST_PASSED${C_RESET}"
    echo -e "  Failed: ${C_RED}$TEST_FAILED${C_RESET}"
    echo -e "  Skipped: ${C_YELLOW}$TEST_SKIPPED${C_RESET}"

    if [[ $TEST_FAILED -eq 0 ]]; then
        echo -e "${C_GREEN}All tests passed!${C_RESET}"
        exit 0
    else
        echo -e "${C_RED}Some tests failed!${C_RESET}"
        exit 1
    fi
}

# Main execution
main() {
    local test_type="${1:-all}"

    case "$test_type" in
        "unit")
            test_init "unit"
            run_test_suite "tests/unit"
            ;;
        "integration")
            test_init "integration"
            run_test_suite "tests/integration"
            ;;
        "e2e")
            test_init "e2e"
            run_test_suite "tests/e2e"
            ;;
        "all")
            test_init "all"
            run_test_suite "tests/unit"
            run_test_suite "tests/integration"
            run_test_suite "tests/e2e"
            ;;
        *)
            echo "Usage: $0 [unit|integration|e2e|all]"
            exit 1
            ;;
    esac

    generate_report
    test_cleanup
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

### Assertions Framework (`tests/framework/assertions.sh`)

```bash
#!/bin/bash

# Assertion functions for testing framework

# Assert that command succeeds
assert_success() {
    local description="$1"
    shift

    if "$@"; then
        echo "  ✓ $description"
        return 0
    else
        echo "  ✗ $description"
        echo "    Command: $*"
        return 1
    fi
}

# Assert that command fails
assert_failure() {
    local description="$1"
    shift

    if ! "$@"; then
        echo "  ✓ $description"
        return 0
    else
        echo "  ✗ $description"
        echo "    Command should have failed: $*"
        return 1
    fi
}

# Assert equals
assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$expected" == "$actual" ]]; then
        echo "  ✓ $description"
        return 0
    else
        echo "  ✗ $description"
        echo "    Expected: $expected"
        echo "    Actual: $actual"
        return 1
    fi
}

# Assert not equals
assert_not_equals() {
    local description="$1"
    local not_expected="$2"
    local actual="$3"

    if [[ "$not_expected" != "$actual" ]]; then
        echo "  ✓ $description"
        return 0
    else
        echo "  ✗ $description"
        echo "    Should not equal: $not_expected"
        echo "    Actual: $actual"
        return 1
    fi
}

# Assert contains
assert_contains() {
    local description="$1"
    local haystack="$2"
    local needle="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  ✓ $description"
        return 0
    else
        echo "  ✗ $description"
        echo "    String should contain: $needle"
        echo "    Actual: $haystack"
        return 1
    fi
}

# Assert file exists
assert_file_exists() {
    local description="$1"
    local file_path="$2"

    if [[ -f "$file_path" ]]; then
        echo "  ✓ $description"
        return 0
    else
        echo "  ✗ $description"
        echo "    File not found: $file_path"
        return 1
    fi
}

# Assert file not exists
assert_file_not_exists() {
    local description="$1"
    local file_path="$2"

    if [[ ! -f "$file_path" ]]; then
        echo "  ✓ $description"
        return 0
    else
        echo "  ✗ $description"
        echo "    File should not exist: $file_path"
        return 1
    fi
}

# Assert directory exists
assert_directory_exists() {
    local description="$1"
    local dir_path="$2"

    if [[ -d "$dir_path" ]]; then
        echo "  ✓ $description"
        return 0
    else
        echo "  ✗ $description"
        echo "    Directory not found: $dir_path"
        return 1
    fi
}

# Assert command exists
assert_command_exists() {
    local description="$1"
    local command="$2"

    if command -v "$command" >/dev/null 2>&1; then
        echo "  ✓ $description"
        return 0
    else
        echo "  ✗ $description"
        echo "    Command not found: $command"
        return 1
    fi
}

# Assert service is active
assert_service_active() {
    local description="$1"
    local service="$2"

    if systemctl is-active --quiet "$service"; then
        echo "  ✓ $description"
        return 0
    else
        echo "  ✗ $description"
        echo "    Service not active: $service"
        return 1
    fi
}

# Assert port is listening
assert_port_listening() {
    local description="$1"
    local port="$2"
    local protocol="${3:-tcp}"

    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        echo "  ✓ $description"
        return 0
    else
        echo "  ✗ $description"
        echo "    Port not listening: $port/$protocol"
        return 1
    fi
}

# Assert JSON field equals
assert_json_field_equals() {
    local description="$1"
    local json_file="$2"
    local field_path="$3"
    local expected="$4"

    if command -v jq >/dev/null 2>&1; then
        local actual=$(jq -r ".$field_path" "$json_file" 2>/dev/null)
        if [[ "$actual" == "$expected" ]]; then
            echo "  ✓ $description"
            return 0
        else
            echo "  ✗ $description"
            echo "    Expected: $expected"
            echo "    Actual: $actual"
            return 1
        fi
    else
        echo "  ✗ $description"
        echo "    jq is required for JSON assertions"
        return 1
    fi
}

# Assert array contains
assert_array_contains() {
    local description="$1"
    local -n array_ref=$2
    local element="$3"

    for item in "${array_ref[@]}"; do
        if [[ "$item" == "$element" ]]; then
            echo "  ✓ $description"
            return 0
        fi
    done

    echo "  ✗ $description"
    echo "    Array does not contain: $element"
    echo "    Array contents: ${array_ref[*]}"
    return 1
}

# Assert regex matches
assert_regex_matches() {
    local description="$1"
    local string="$2"
    local pattern="$3"

    if [[ "$string" =~ $pattern ]]; then
        echo "  ✓ $description"
        return 0
    else
        echo "  ✗ $description"
        echo "    String: $string"
        echo "    Pattern: $pattern"
        return 1
    fi
}
```

## Module Testing Examples

### Docker Module Tests (`tests/unit/modules/docker/test.sh`)

```bash
#!/bin/bash

# Docker Module Unit Tests

# Test setup
setup() {
    echo "Setting up Docker module tests..."

    # Load module
    source "$(dirname "$0")/../../../../modules/infrastructure/docker/module.sh"

    # Mock system functions
    mock_system_commands

    # Create test environment
    export TEST_STATE_DIR="/tmp/serversh-test"
    mkdir -p "$TEST_STATE_DIR"
}

# Test cleanup
cleanup() {
    echo "Cleaning up Docker module tests..."

    # Remove test environment
    rm -rf "$TEST_STATE_DIR"

    # Restore mocks
    restore_system_commands
}

# Mock system commands for testing
mock_system_commands() {
    # Mock docker command
    docker() {
        case "$1" in
            "--version")
                echo "Docker version 24.0.0, build 1234567"
                ;;
            "info")
                echo "Containers: 1"
                echo "Images: 3"
                ;;
            "run")
                if [[ "$*" == *"hello-world"* ]]; then
                    echo "Hello from Docker!"
                fi
                ;;
            "network")
                case "$2" in
                    "ls")
                        echo "newt_talk"
                        ;;
                    "create")
                        # Mock network creation
                        ;;
                esac
                ;;
            *)
                echo "docker mock: $*"
                ;;
        esac
    }

    # Mock systemctl
    systemctl() {
        case "$1" in
            "is-active")
                if [[ "$2" == "docker" ]]; then
                    return 0
                fi
                return 1
                ;;
            "enable"|"start"|"stop"|"disable")
                # Mock service management
                return 0
                ;;
        esac
    }

    # Mock package manager functions
    apt-get() {
        echo "apt-get mock: $*"
        return 0
    }

    yum() {
        echo "yum mock: $*"
        return 0
    }

    # Mock file system operations
    groupadd() {
        echo "groupadd mock: $*"
        return 0
    }

    export -f docker systemctl apt-get yum groupadd
}

# Restore system commands
restore_system_commands() {
    unset -f docker systemctl apt-get yum groupadd
}

# Run tests
run_tests() {
    echo "Running Docker module tests..."

    test_module_metadata
    test_pre_check
    test_installation
    test_configuration
    test_post_check
    test_status
    test_health_check
}

# Test module metadata
test_module_metadata() {
    echo "Testing module metadata..."

    assert_equals "Module name should be docker" "docker" "$MODULE_NAME"
    assert_equals "Module version should be set" "2.0.0" "$MODULE_VERSION"
    assert_contains "Module description should mention Docker" "$MODULE_DESCRIPTION" "Docker"
    assert_array_contains "System detection should be a dependency" MODULE_DEPENDENCIES "system-detection"
    assert_array_contains "Network should be a dependency" MODULE_DEPENDENCIES "network"
    assert_array_contains "Security should be a dependency" MODULE_DEPENDENCIES "security"
}

# Test pre-installation checks
test_pre_check() {
    echo "Testing pre-installation checks..."

    # Test with Docker already installed
    assert_success "Pre-check should pass with Docker installed" module_pre_check

    # Test kernel version check (mocked)
    local kernel_version=$(uname -r)
    assert_regex_matches "Kernel version should be valid" "$kernel_version" "^[0-9]+\.[0-9]+\.[0-9]+"

    # Test architecture check
    local arch=$(uname -m)
    case "$arch" in
        "x86_64"|"aarch64"|"armv7l")
            echo "  ✓ Supported architecture: $arch"
            ;;
        *)
            echo "  ✗ Unsupported architecture: $arch"
            return 1
            ;;
    esac
}

# Test installation
test_installation() {
    echo "Testing Docker installation..."

    # Test Docker installation methods
    DOCKER_INSTALL_METHOD="repository"
    assert_success "Repository installation should succeed" module_install

    # Verify Docker command exists
    assert_command_exists "Docker command should be available" docker

    # Test binary installation method
    DOCKER_INSTALL_METHOD="binary"
    assert_success "Binary installation should be handled" module_install
}

# Test configuration
test_configuration() {
    echo "Testing Docker configuration..."

    # Set test configuration
    DOCKER_NETWORK_MTU="1450"
    DOCKER_ENABLE_IPV6="true"
    DOCKER_STORAGE_DRIVER="overlay2"
    DOCKER_LOG_DRIVER="json-file"

    assert_success "Docker configuration should succeed" module_configure

    # Check daemon configuration file
    assert_file_exists "Docker daemon config should exist" "/etc/docker/daemon.json"

    # Verify configuration content
    if command -v jq >/dev/null 2>&1; then
        assert_json_field_equals "MTU should be set" "/etc/docker/daemon.json" "mtu" "1450"
        assert_json_field_equals "IPv6 should be enabled" "/etc/docker/daemon.json" "ipv6" "true"
        assert_json_field_equals "Storage driver should be overlay2" "/etc/docker/daemon.json" "storage-driver" "overlay2"
    fi
}

# Test post-installation validation
test_post_check() {
    echo "Testing post-installation validation..."

    assert_success "Post-check should pass" module_post_check
    assert_service_active "Docker service should be active" docker

    # Test Docker functionality
    assert_success "Docker test container should run" docker run --rm hello-world

    # Test network creation
    assert_contains "Docker should have newt_talk network" "$(docker network ls)" "newt_talk"
}

# Test status reporting
test_status() {
    echo "Testing status reporting..."

    local status_output=$(module_status)
    assert_contains "Status should be installed" "$status_output" "installed"
    assert_contains "Status should show version" "$status_output" "Docker version"
    assert_contains "Status should show daemon status" "$status_output" "daemon_status"
}

# Test health check
test_health_check() {
    echo "Testing health check..."

    assert_success "Health check should pass" module_health_check
}
```

### Integration Test: Module Dependencies (`tests/integration/dependency-resolution/test.sh`)

```bash
#!/bin/bash

# Module Dependency Resolution Integration Tests

setup() {
    echo "Setting up dependency resolution tests..."

    # Load framework
    source "$(dirname "$0")/../../../lib/core/framework.sh"
    source "$(dirname "$0")/../../../lib/core/dependency-resolver.sh"
    source "$(dirname "$0")/../../../lib/core/module-loader.sh"

    # Create test modules directory
    export TEST_MODULES_DIR="/tmp/test-modules"
    mkdir -p "$TEST_MODULES_DIR"

    create_test_modules
}

cleanup() {
    echo "Cleaning up dependency resolution tests..."
    rm -rf "$TEST_MODULES_DIR"
}

# Create test modules for dependency testing
create_test_modules() {
    # Module A (no dependencies)
    mkdir -p "$TEST_MODULES_DIR/module-a"
    cat > "$TEST_MODULES_DIR/module-a/module.sh" << 'EOF'
readonly MODULE_NAME="module-a"
readonly MODULE_VERSION="1.0.0"
readonly MODULE_DEPENDENCIES=()
module_pre_check() { return 0; }
module_install() { return 0; }
module_configure() { return 0; }
module_post_check() { return 0; }
module_uninstall() { return 0; }
module_status() { echo "status: installed"; }
EOF

    # Module B (depends on A)
    mkdir -p "$TEST_MODULES_DIR/module-b"
    cat > "$TEST_MODULES_DIR/module-b/module.sh" << 'EOF'
readonly MODULE_NAME="module-b"
readonly MODULE_VERSION="1.0.0"
readonly MODULE_DEPENDENCIES=("module-a")
module_pre_check() { return 0; }
module_install() { return 0; }
module_configure() { return 0; }
module_post_check() { return 0; }
module_uninstall() { return 0; }
module_status() { echo "status: installed"; }
EOF

    # Module C (depends on B)
    mkdir -p "$TEST_MODULES_DIR/module-c"
    cat > "$TEST_MODULES_DIR/module-c/module.sh" << 'EOF'
readonly MODULE_NAME="module-c"
readonly MODULE_VERSION="1.0.0"
readonly MODULE_DEPENDENCIES=("module-b")
module_pre_check() { return 0; }
module_install() { return 0; }
module_configure() { return 0; }
module_post_check() { return 0; }
module_uninstall() { return 0; }
module_status() { echo "status: installed"; }
EOF

    # Module D (circular dependency with C)
    mkdir -p "$TEST_MODULES_DIR/module-d"
    cat > "$TEST_MODULES_DIR/module-d/module.sh" << 'EOF'
readonly MODULE_NAME="module-d"
readonly MODULE_VERSION="1.0.0"
readonly MODULE_DEPENDENCIES=("module-c")
module_pre_check() { return 0; }
module_install() { return 0; }
module_configure() { return 0; }
module_post_check() { return 0; }
module_uninstall() { return 0; }
module_status() { echo "status: installed"; }
EOF

    # Add circular dependency to module C
    sed -i 's/readonly MODULE_DEPENDENCIES=("module-b")/readonly MODULE_DEPENDENCIES=("module-b" "module-d")/' "$TEST_MODULES_DIR/module-c/module.sh"
}

run_tests() {
    echo "Running dependency resolution tests..."

    test_module_discovery
    test_dependency_graph_construction
    test_circular_dependency_detection
    test_installation_order_calculation
    test_dependency_validation
}

# Test module discovery
test_module_discovery() {
    echo "Testing module discovery..."

    module_discover "$TEST_MODULES_DIR"

    assert_success "Module discovery should succeed" test -n "${MODULE_REGISTRY[module-a]}"
    assert_success "Module B should be discovered" test -n "${MODULE_REGISTRY[module-b]}"
    assert_success "Module C should be discovered" test -n "${MODULE_REGISTRY[module-c]}"
    assert_success "Module D should be discovered" test -n "${MODULE_REGISTRY[module-d]}"
}

# Test dependency graph construction
test_dependency_graph_construction() {
    echo "Testing dependency graph construction..."

    dependency_build_graph

    # Check direct dependencies
    assert_contains "Module B should depend on A" "${DEPENDENCY_GRAPH[module-b]}" "module-a"
    assert_contains "Module C should depend on B" "${DEPENDENCY_GRAPH[module-c]}" "module-b"
    assert_contains "Module C should depend on D" "${DEPENDENCY_GRAPH[module-c]}" "module-d"
    assert_contains "Module D should depend on C" "${DEPENDENCY_GRAPH[module-d]}" "module-c"
}

# Test circular dependency detection
test_circular_dependency_detection() {
    echo "Testing circular dependency detection..."

    # Detect circular dependencies
    if dependency_detect_cycles; then
        echo "  ✗ Should detect circular dependencies"
        return 1
    else
        echo "  ✓ Circular dependencies detected correctly"
    fi
}

# Test installation order calculation
test_installation_order_calculation() {
    echo "Testing installation order calculation..."

    # Create modules without circular dependencies for this test
    mkdir -p "$TEST_MODULES_DIR/clean-module-c"
    cat > "$TEST_MODULES_DIR/clean-module-c/module.sh" << 'EOF'
readonly MODULE_NAME="clean-module-c"
readonly MODULE_VERSION="1.0.0"
readonly MODULE_DEPENDENCIES=("module-b")
module_pre_check() { return 0; }
module_install() { return 0; }
module_configure() { return 0; }
module_post_check() { return 0; }
module_uninstall() { return 0; }
module_status() { echo "status: installed"; }
EOF

    # Rebuild dependency graph
    MODULE_REGISTRY=()
    DEPENDENCY_GRAPH=()
    module_discover "$TEST_MODULES_DIR"
    dependency_build_graph

    # Calculate installation order
    local install_order=($(dependency_calculate_install_order "clean-module-c"))

    # Module A should be first (no dependencies)
    assert_equals "Module A should be first in order" "module-a" "${install_order[0]}"

    # Module B should be second (depends on A)
    assert_equals "Module B should be second in order" "module-b" "${install_order[1]}"

    # Module C should be third (depends on B)
    assert_equals "Module C should be third in order" "clean-module-c" "${install_order[2]}"
}

# Test dependency validation
test_dependency_validation() {
    echo "Testing dependency validation..."

    # Test with missing dependency
    mkdir -p "$TEST_MODULES_DIR/module-e"
    cat > "$TEST_MODULES_DIR/module-e/module.sh" << 'EOF'
readonly MODULE_NAME="module-e"
readonly MODULE_VERSION="1.0.0"
readonly MODULE_DEPENDENCIES=("non-existent-module")
module_pre_check() { return 0; }
module_install() { return 0; }
module_configure() { return 0; }
module_post_check() { return 0; }
module_uninstall() { return 0; }
module_status() { echo "status: installed"; }
EOF

    module_discover "$TEST_MODULES_DIR"

    if dependency_validate "module-e"; then
        echo "  ✗ Should fail validation for missing dependency"
        return 1
    else
        echo "  ✓ Missing dependency validation works"
    fi
}
```

## End-to-End Scenarios

### Complete Server Setup Scenario (`tests/e2e/scenarios/test_complete_setup.sh`)

```bash
#!/bin/bash

# Complete Server Setup E2E Test

setup() {
    echo "Setting up complete setup E2E test..."

    # Create test environment
    export TEST_ENVIRONMENT="/tmp/serversh-e2e-$(date +%s)"
    mkdir -p "$TEST_ENVIRONMENT"

    # Copy framework to test environment
    cp -r "$(dirname "$0")/../../.." "$TEST_ENVIRONMENT/serversh"
    cd "$TEST_ENVIRONMENT/serversh"

    # Create test configuration
    cat > config.yaml << 'EOF'
modules:
  enabled:
    - system-detection
    - security
    - docker
    - nginx

docker:
  version: "latest"
  network:
    mtu: 1450
    ipv6: true

nginx:
  version: "stable"
  sites:
    - name: "test.local"
      type: "static"
      port: 80
EOF

    # Mock system requirements
    setup_mock_environment
}

cleanup() {
    echo "Cleaning up complete setup E2E test..."

    cd /
    rm -rf "$TEST_ENVIRONMENT"
}

setup_mock_environment() {
    # Create mock system files
    mkdir -p "$TEST_ENVIRONMENT/mock/etc"
    mkdir -p "$TEST_ENVIRONMENT/mock/var/log"

    # Mock OS detection
    echo "ID=ubuntu" > "$TEST_ENVIRONMENT/mock/etc/os-release"
    echo "VERSION_ID=\"20.04\"" >> "$TEST_ENVIRONMENT/mock/etc/os-release"
    echo "PRETTY_NAME=\"Ubuntu 20.04 LTS\"" >> "$TEST_ENVIRONMENT/mock/etc/os-release"

    # Mock systemctl
    cat > "$TEST_ENVIRONMENT/mock/systemctl" << 'EOF'
#!/bin/bash
case "$1" in
    "is-active")
        if [[ "$2" == "docker" || "$2" == "nginx" ]]; then
            echo "active"
            exit 0
        fi
        echo "inactive"
        exit 3
        ;;
    "enable"|"start")
        echo "Mock: systemctl $*"
        exit 0
        ;;
esac
EOF
    chmod +x "$TEST_ENVIRONMENT/mock/systemctl"

    # Add mock directory to PATH
    export PATH="$TEST_ENVIRONMENT/mock:$PATH"
}

run_tests() {
    echo "Running complete setup E2E test..."

    test_system_detection
    test_security_configuration
    test_docker_installation
    test_nginx_installation
    test_integration_verification
}

test_system_detection() {
    echo "Testing system detection..."

    # Load system detection module
    source "modules/core/system-detection/module.sh"

    assert_success "System detection should succeed" module_pre_check
    assert_success "System detection should complete" module_install

    local status_output=$(module_status)
    assert_contains "Should detect Ubuntu" "$status_output" "ubuntu"
    assert_contains "Should detect version" "$status_output" "20.04"
}

test_security_configuration() {
    echo "Testing security configuration..."

    # Load security module
    source "modules/core/security/module.sh"

    assert_success "Security pre-check should pass" module_pre_check
    assert_success "Security configuration should succeed" module_install

    # Test user creation (mock)
    assert_success "Security post-check should pass" module_post_check

    local status_output=$(module_status)
    assert_contains "Security should be configured" "$status_output" "configured"
}

test_docker_installation() {
    echo "Testing Docker installation..."

    # Load Docker module
    source "modules/infrastructure/docker/module.sh"

    # Mock Docker installation
    docker() {
        echo "Docker version 24.0.0, build test"
    }
    export -f docker

    assert_success "Docker pre-check should pass" module_pre_check
    assert_success "Docker installation should succeed" module_install
    assert_success "Docker configuration should succeed" module_configure
    assert_success "Docker post-check should pass" module_post_check

    local status_output=$(module_status)
    assert_contains "Docker should be installed" "$status_output" "installed"
}

test_nginx_installation() {
    echo "Testing NGINX installation..."

    # Load NGINX module
    source "modules/infrastructure/nginx/module.sh"

    # Mock NGINX installation
    nginx() {
        echo "nginx version: nginx/1.18.0"
    }
    export -f nginx

    assert_success "NGINX pre-check should pass" module_pre_check
    assert_success "NGINX installation should succeed" module_install
    assert_success "NGINX configuration should succeed" module_configure
    assert_success "NGINX post-check should pass" module_post_check

    local status_output=$(module_status)
    assert_contains "NGINX should be installed" "$status_output" "installed"
}

test_integration_verification() {
    echo "Testing integration verification..."

    # Test that both Docker and NGINX are running
    assert_service_active "Docker should be active" docker
    assert_service_active "NGINX should be active" nginx

    # Test network connectivity between containers (mock)
    assert_success "Container network should work" docker run --rm busybox ping -c 1 8.8.8.8

    # Test NGINX configuration (mock)
    assert_success "NGINX should serve content" curl -I http://localhost

    # Test that configuration files are created
    assert_file_exists "Docker daemon config should exist" "/etc/docker/daemon.json"
    assert_file_exists "NGINX config should exist" "/etc/nginx/sites-available/test.local"
}
```

## Performance Testing

### Load Testing (`tests/e2e/performance/test_load.sh`)

```bash
#!/bin/bash

# Performance Load Tests

setup() {
    echo "Setting up performance tests..."

    # Install performance monitoring tools
    command -v sysstat >/dev/null 2>&1 || apt-get install -y sysstat

    # Start monitoring
    start_performance_monitoring
}

cleanup() {
    echo "Cleaning up performance tests..."
    stop_performance_monitoring
    generate_performance_report
}

start_performance_monitoring() {
    echo "Starting performance monitoring..."

    # CPU monitoring
    sar -u 1 300 > "$TEST_RESULTS_DIR/cpu_usage.log" &
    CPU_MONITOR_PID=$!

    # Memory monitoring
    sar -r 1 300 > "$TEST_RESULTS_DIR/memory_usage.log" &
    MEMORY_MONITOR_PID=$!

    # Disk I/O monitoring
    sar -d 1 300 > "$TEST_RESULTS_DIR/disk_io.log" &
    DISK_MONITOR_PID=$!

    # Network monitoring
    sar -n DEV 1 300 > "$TEST_RESULTS_DIR/network_usage.log" &
    NETWORK_MONITOR_PID=$!
}

stop_performance_monitoring() {
    echo "Stopping performance monitoring..."

    kill $CPU_MONITOR_PID $MEMORY_MONITOR_PID $DISK_MONITOR_PID $NETWORK_MONITOR_PID 2>/dev/null || true
}

run_tests() {
    echo "Running performance tests..."

    test_installation_performance
    test_concurrent_module_execution
    test_resource_usage_limits
    test_scalability_limits
}

test_installation_performance() {
    echo "Testing installation performance..."

    local start_time=$(date +%s)

    # Run complete installation
    timeout 300 ./bin/server-setup install --config tests/config/performance.yaml

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo "Installation completed in ${duration}s"

    # Assert performance requirements
    assert_success "Installation should complete within 5 minutes" test $duration -lt 300
}

test_concurrent_module_execution() {
    echo "Testing concurrent module execution..."

    # Install modules concurrently
    local pids=()

    # Start Docker installation in background
    (timeout 120 ./bin/server-setup install docker) &
    pids+=($!)

    # Start NGINX installation in background
    (timeout 120 ./bin/server-setup install nginx) &
    pids+=($!)

    # Wait for all installations
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait $pid; then
            failed=1
        fi
    done

    assert_success "Concurrent installations should succeed" test $failed -eq 0
}

test_resource_usage_limits() {
    echo "Testing resource usage limits..."

    # Monitor resource usage during installation
    local max_cpu=0
    local max_memory=0

    # Parse CPU usage logs
    if [[ -f "$TEST_RESULTS_DIR/cpu_usage.log" ]]; then
        max_cpu=$(grep -E "^[0-9]+" "$TEST_RESULTS_DIR/cpu_usage.log" | awk '{print $NF}' | sort -n | tail -1)
    fi

    # Parse memory usage logs
    if [[ -f "$TEST_RESULTS_DIR/memory_usage.log" ]]; then
        max_memory=$(grep -E "^[0-9]+" "$TEST_RESULTS_DIR/memory_usage.log" | awk '{print $5}' | sort -n | tail -1)
    fi

    echo "Maximum CPU usage: ${max_cpu}%"
    echo "Maximum memory usage: ${max_memory}MB"

    # Assert resource limits
    assert_success "CPU usage should stay below 90%" test ${max_cpu%.*} -lt 90
    assert_success "Memory usage should stay below 2GB" test $max_memory -lt 2048
}

test_scalability_limits() {
    echo "Testing scalability limits..."

    # Test with multiple modules
    local modules=("docker" "nginx" "mysql" "redis" "monitoring")
    local start_time=$(date +%s)

    for module in "${modules[@]}"; do
        timeout 60 ./bin/server-setup install "$module" &
    done

    wait

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo "Scalability test completed in ${duration}s"

    # Assert scalability requirements
    assert_success "Multiple modules should install within 10 minutes" test $duration -lt 600
}
```

This comprehensive testing framework provides:

1. **Modular Test Architecture**: Separate test types with clear responsibilities
2. **Comprehensive Assertions**: Wide range of assertion functions for different scenarios
3. **Mocking Framework**: Ability to mock system commands and services
4. **Integration Testing**: Test module interactions and dependencies
5. **End-to-End Scenarios**: Complete workflow testing
6. **Performance Testing**: Load and scalability testing
7. **Detailed Reporting**: HTML reports with detailed test results
8. **Environment Isolation**: Clean test environments with proper cleanup

The framework ensures the reliability and quality of the modular server setup system across all supported platforms and configurations.