#!/bin/bash

# =============================================================================
# ServerSH Core Framework Unit Tests
# =============================================================================

# Test framework setup
set -euo pipefail

# Get test directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$TEST_DIR")")"

# Source test framework
if command -v bats >/dev/null 2>&1; then
    # Using bats test framework
    echo "Running tests with BATS framework"
else
    echo "Warning: BATS not found, running basic tests"
fi

# Source core components
SERVERSH_ROOT="$PROJECT_ROOT"
source "${PROJECT_ROOT}/core/constants.sh" || exit 1
source "${PROJECT_ROOT}/core/utils.sh" || exit 1

# =============================================================================
# Test Utility Functions
# =============================================================================

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"

    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $message"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        return 1
    else
        echo "PASS: $message"
        return 0
    fi
}

assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"

    if [[ "$not_expected" == "$actual" ]]; then
        echo "FAIL: $message"
        echo "  Should not equal: $not_expected"
        echo "  Actual: $actual"
        return 1
    else
        echo "PASS: $message"
        return 0
    fi
}

assert_true() {
    local condition="$1"
    local message="${2:-Assertion failed}"

    if [[ "$condition" != true ]]; then
        echo "FAIL: $message"
        echo "  Expected: true"
        echo "  Actual: $condition"
        return 1
    else
        echo "PASS: $message"
        return 0
    fi
}

assert_false() {
    local condition="$1"
    local message="${2:-Assertion failed}"

    if [[ "$condition" != false ]]; then
        echo "FAIL: $message"
        echo "  Expected: false"
        echo "  Actual: $condition"
        return 1
    else
        echo "PASS: $message"
        return 0
    fi
}

assert_command_success() {
    local command="$1"
    local message="${2:-Command should succeed}"

    if eval "$command" >/dev/null 2>&1; then
        echo "PASS: $message"
        return 0
    else
        echo "FAIL: $message"
        echo "  Command failed: $command"
        return 1
    fi
}

assert_command_failure() {
    local command="$1"
    local message="${2:-Command should fail}"

    if ! eval "$command" >/dev/null 2>&1; then
        echo "PASS: $message"
        return 0
    else
        echo "FAIL: $message"
        echo "  Command should have failed: $command"
        return 1
    fi
}

# =============================================================================
# Test Constants and Variables
# =============================================================================

TEST_TEMP_DIR=""
TEST_LOG_FILE=""

# Test setup
setup_tests() {
    echo "Setting up test environment..."

    # Create temporary directory
    TEST_TEMP_DIR=$(temp_dir "serversh_test")
    mkdir -p "$TEST_TEMP_DIR"

    # Create test log file
    TEST_LOG_FILE="$TEST_TEMP_DIR/test.log"

    # Set test environment variables
    export SERVERSH_TEST_MODE=true
    export SERVERSH_ROOT="$PROJECT_ROOT"
    export SERVERSH_STATE_DIR="$TEST_TEMP_DIR/state"
    export SERVERSH_LOG_DIR="$TEST_TEMP_DIR/logs"
    export SERVERSH_CONFIG_DIR="$TEST_TEMP_DIR/config"

    # Create required directories
    mkdir -p "$SERVERSH_STATE_DIR" "$SERVERSH_LOG_DIR" "$SERVERSH_CONFIG_DIR"

    echo "Test environment ready: $TEST_TEMP_DIR"
}

# Test cleanup
cleanup_tests() {
    echo "Cleaning up test environment..."

    if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi

    unset SERVERSH_TEST_MODE
    unset SERVERSH_ROOT
    unset SERVERSH_STATE_DIR
    unset SERVERSH_LOG_DIR
    unset SERVERSH_CONFIG_DIR

    echo "Test environment cleaned up"
}

# =============================================================================
# Test Functions
# =============================================================================

# Test constants
test_constants() {
    echo "Testing constants..."

    # Test version constants
    assert_not_equals "" "$SERVERSH_VERSION" "ServerSH version should be set"
    assert_not_equals "" "$SERVERSH_BUILD_DATE" "Build date should be set"

    # Test exit codes
    assert_equals "0" "$EXIT_SUCCESS" "EXIT_SUCCESS should be 0"
    assert_equals "1" "$EXIT_GENERAL_ERROR" "EXIT_GENERAL_ERROR should be 1"
    assert_equals "2" "$EXIT_INVALID_ARGS" "EXIT_INVALID_ARGS should be 2"

    # Test colors
    assert_not_equals "" "$COLOR_RESET" "COLOR_RESET should be set"
    assert_not_equals "" "$COLOR_RED" "COLOR_RED should be set"
    assert_not_equals "" "$COLOR_GREEN" "COLOR_GREEN should be set"

    # Test Docker constants (from example.sh)
    assert_equals "1450" "$DOCKER_MTU" "DOCKER_MTU should be 1450"
    assert_equals "true" "$DOCKER_IPV6_ENABLED" "DOCKER_IPV6_ENABLED should be true"
    assert_equals "newt_talk" "$DOCKER_DEFAULT_NETWORK" "DOCKER_DEFAULT_NETWORK should be newt_talk"

    echo "Constants tests completed"
}

# Test utility functions
test_utils() {
    echo "Testing utility functions..."

    # Test string utilities
    assert_equals "test" "$(trim "  test  ")" "trim should remove whitespace"
    assert_equals "test" "$(to_lower "TEST")" "to_lower should convert to lowercase"
    assert_equals "TEST" "$(to_upper "test")" "to_upper should convert to uppercase"

    assert_true "$(contains "hello world" "world")" "contains should find substring"
    assert_false "$(contains "hello world" "xyz")" "contains should return false for missing substring"

    assert_true "$(starts_with "hello world" "hello")" "starts_with should work"
    assert_false "$(starts_with "hello world" "world")" "starts_with should return false"

    assert_true "$(ends_with "hello world" "world")" "ends_with should work"
    assert_false "$(ends_with "hello world" "hello")" "ends_with should return false"

    # Test array utilities
    local test_array=("apple" "banana" "cherry")
    assert_true "$(array_contains "banana" "${test_array[@]}")" "array_contains should find element"
    assert_false "$(array_contains "orange" "${test_array[@]}")" "array_contains should return false for missing element"

    # Test validation functions
    assert_true "$(is_valid_hostname "test-server")" "Valid hostname should pass"
    assert_false "$(is_valid_hostname "-invalid")" "Invalid hostname should fail"

    assert_true "$(is_valid_username "testuser")" "Valid username should pass"
    assert_false "$(is_valid_username "InvalidUser")" "Invalid username should fail"

    assert_true "$(is_valid_port "2222")" "Valid port should pass"
    assert_false "$(is_valid_port "99999")" "Invalid port should fail"
    assert_false "$(is_valid_port "abc")" "Non-numeric port should fail"

    # Test IP validation
    assert_true "$(is_valid_ipv4 "192.168.1.1")" "Valid IPv4 should pass"
    assert_false "$(is_valid_ipv4 "999.999.999.999")" "Invalid IPv4 should fail"

    assert_true "$(is_valid_ipv6 "2001:db8::1")" "Valid IPv6 should pass"
    assert_false "$(is_valid_ipv6 "invalid")" "Invalid IPv6 should fail"

    echo "Utility functions tests completed"
}

# Test file operations
test_file_operations() {
    echo "Testing file operations..."

    local test_file="$TEST_TEMP_DIR/test_file.txt"
    local test_content="Test content"

    # Test file creation and operations
    echo "$test_content" > "$test_file"
    assert_true "[[ -f '$test_file' ]]" "File should be created"

    # Test file size
    local size
    size=$(file_size "$test_file")
    assert_true "[[ $size -gt 0 ]]" "File size should be greater than 0"

    # Test backup
    local backup_file
    backup_file=$(backup_file "$test_file")
    assert_true "[[ -f '$backup_file' ]]" "Backup file should be created"
    assert_true "[[ '$backup_file' != '$test_file' ]]" "Backup file should be different from original"

    # Test empty file check
    local empty_file="$TEST_TEMP_DIR/empty.txt"
    touch "$empty_file"
    assert_true "$(is_file_empty "$empty_file")" "Empty file should be detected"
    assert_false "$(is_file_empty "$test_file")" "Non-empty file should not be empty"

    # Test temporary files
    local temp_file
    temp_file=$(temp_file "test")
    assert_true "[[ -f '$temp_file' ]]" "Temporary file should be created"
    rm -f "$temp_file"

    local temp_dir
    temp_dir=$(temp_dir "test")
    assert_true "[[ -d '$temp_dir' ]]" "Temporary directory should be created"
    rmdir "$temp_dir"

    echo "File operations tests completed"
}

# Test system utilities
test_system_utilities() {
    echo "Testing system utilities..."

    # Test command existence
    assert_true "$(command_exists "bash")" "bash command should exist"
    assert_false "$(command_exists "nonexistent_command_12345")" "Nonexistent command should not exist"

    # Test system info
    local os_info
    os_info=$(get_system_info "os")
    assert_not_equals "" "$os_info" "OS info should be available"

    local arch_info
    arch_info=$(get_system_info "arch")
    assert_not_equals "" "$arch_info" "Architecture info should be available"

    local hostname_info
    hostname_info=$(get_system_info "hostname")
    assert_not_equals "" "$hostname_info" "Hostname info should be available"

    # Test service checking
    # Note: This test may fail depending on the system
    local service_result
    if is_service_running "cron" 2>/dev/null; then
        service_result="running"
    else
        service_result="not_running"
    fi
    echo "  Service check result: cron is $service_result"

    # Test package checking
    # Note: This test depends on what's installed on the system
    local package_result
    if is_package_installed "bash" 2>/dev/null; then
        package_result="installed"
    else
        package_result="not_installed"
    fi
    echo "  Package check result: bash is $package_result"

    echo "System utilities tests completed"
}

# Test network utilities
test_network_utilities() {
    echo "Testing network utilities..."

    # Test local IP (may not work on all systems)
    if command_exists ip; then
        local local_ip
        local_ip=$(get_local_ip)
        if [[ -n "$local_ip" ]]; then
            echo "  Local IP: $local_ip"
        else
            echo "  Local IP: Could not determine"
        fi
    fi

    # Test port validation
    assert_false "$(is_port_open 99999)" "High port should not be open"
    # Note: Don't test common ports as they might be open

    # Test network connectivity (may not work in all environments)
    if check_network_connectivity "8.8.8.8" 2 2>/dev/null; then
        echo "  Network connectivity: Available"
    else
        echo "  Network connectivity: Not available or timed out"
    fi

    echo "Network utilities tests completed"
}

# Test math utilities
test_math_utilities() {
    echo "Testing math utilities..."

    # Test number conversion
    assert_equals "123" "$(to_int "123")" "to_int should work with numbers"
    assert_equals "0" "$(to_int "abc")" "to_int should return 0 for non-numeric"

    # Test even/odd
    assert_true "$(is_even 4)" "4 should be even"
    assert_false "$(is_even 5)" "5 should not be even"
    assert_true "$(is_odd 5)" "5 should be odd"
    assert_false "$(is_odd 4)" "4 should not be odd"

    # Test percentage calculation
    local percentage
    percentage=$(percentage 25 100)
    assert_equals "25.00" "$percentage" "25% of 100 should be 25.00"

    percentage=$(percentage 1 3)
    assert_equals "33.33" "$percentage" "1/3 should be 33.33"

    # Test random number generation
    local random_num
    random_num=$(random_number 1 10)
    assert_true "[[ $random_num -ge 1 && $random_num -le 10 ]]" "Random number should be in range"

    echo "Math utilities tests completed"
}

# Test time utilities
test_time_utilities() {
    echo "Testing time utilities..."

    # Test timestamp
    local timestamp
    timestamp=$(timestamp)
    assert_true "[[ -n '$timestamp' ]]" "Timestamp should not be empty"
    echo "  Current timestamp: $timestamp"

    # Test unix timestamp
    local unix_ts
    unix_ts=$(unix_timestamp)
    assert_true "[[ $unix_ts -gt 1600000000 ]]" "Unix timestamp should be reasonable"

    # Test duration formatting
    assert_equals "1h 0m 0s" "$(format_duration 3600)" "3600 seconds should be 1h 0m 0s"
    assert_equals "1m 30s" "$(format_duration 90)" "90 seconds should be 1m 30s"
    assert_equals "45s" "$(format_duration 45)" "45 seconds should be 45s"

    # Test timeout checking
    local start_time
    start_time=$(unix_timestamp)
    assert_false "$(is_timeout_expired $start_time 10)" "Timeout should not expire immediately"

    echo "Time utilities tests completed"
}

# =============================================================================
# Test Runner
# =============================================================================

run_tests() {
    echo "=========================================="
    echo "ServerSH Core Framework Unit Tests"
    echo "=========================================="
    echo ""

    local test_count=0
    local pass_count=0
    local fail_count=0

    # List of test functions
    local tests=(
        "test_constants"
        "test_utils"
        "test_file_operations"
        "test_system_utilities"
        "test_network_utilities"
        "test_math_utilities"
        "test_time_utilities"
    )

    # Run each test
    for test_func in "${tests[@]}"; do
        echo ""
        echo "Running: $test_func"
        echo "----------------------------------------"

        if $test_func; then
            ((pass_count++))
        else
            ((fail_count++))
        fi
        ((test_count++))

        echo "----------------------------------------"
        echo "Status: $test_func completed"
        echo ""
    done

    # Print summary
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total tests: $test_count"
    echo "Passed: $pass_count"
    echo "Failed: $fail_count"
    echo ""

    if [[ $fail_count -eq 0 ]]; then
        echo "✅ All tests passed!"
        return 0
    else
        echo "❌ $fail_count test(s) failed!"
        return 1
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

# Handle command line arguments
case "${1:-run}" in
    "setup")
        setup_tests
        ;;
    "cleanup")
        cleanup_tests
        ;;
    "run")
        setup_tests
        trap cleanup_tests EXIT
        run_tests
        ;;
    "help"|"-h"|"--help")
        echo "ServerSH Core Framework Unit Tests"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  setup     - Set up test environment"
        echo "  run       - Run all tests (default)"
        echo "  cleanup   - Clean up test environment"
        echo "  help      - Show this help"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac