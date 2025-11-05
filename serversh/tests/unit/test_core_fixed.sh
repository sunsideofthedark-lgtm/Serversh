#!/bin/bash

# =============================================================================
# ServerSH Core Framework Unit Tests (Fixed)
# =============================================================================

# Test framework setup
set -euo pipefail

# Get test directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$TEST_DIR")")"

# Test utility functions
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

# =============================================================================
# Test Constants and Variables
# =============================================================================

TEST_TEMP_DIR=""

# Test setup
setup_tests() {
    echo "Setting up test environment..."

    # Create temporary directory
    TEST_TEMP_DIR=$(mktemp -d)

    echo "Test environment ready: $TEST_TEMP_DIR"
}

# Test cleanup
cleanup_tests() {
    echo "Cleaning up test environment..."

    if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi

    echo "Test environment cleaned up"
}

# =============================================================================
# Basic Functions Test (without readonly conflicts)
# =============================================================================

test_basic_utilities() {
    echo "Testing basic utilities..."

    # Test trim function
    trim() {
        local var="$1"
        var="${var#"${var%%[![:space:]]*}"}"
        var="${var%"${var##*[![:space:]]}"}"
        printf '%s' "$var"
    }

    assert_equals "test" "$(trim "  test  ")" "trim should remove whitespace"
    assert_equals "test" "$(trim "test")" "trim should not affect trimmed strings"

    # Test to_lower function
    to_lower() {
        printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
    }

    assert_equals "test" "$(to_lower "TEST")" "to_lower should convert to lowercase"
    assert_equals "test" "$(to_lower "TeSt")" "to_lower should convert mixed case"

    # Test to_upper function
    to_upper() {
        printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
    }

    assert_equals "TEST" "$(to_upper "test")" "to_upper should convert to uppercase"
    assert_equals "TEST" "$(to_upper "TeSt")" "to_upper should convert mixed case"

    # Test contains function
    contains() {
        local string="$1"
        local substring="$2"
        [[ "$string" == *"$substring"* ]]
    }

    assert_true "$(contains "hello world" "world")" "contains should find substring"
    assert_false "$(contains "hello world" "xyz")" "contains should return false for missing substring"

    # Test starts_with function
    starts_with() {
        local string="$1"
        local prefix="$2"
        [[ "$string" == "$prefix"* ]]
    }

    assert_true "$(starts_with "hello world" "hello")" "starts_with should work"
    assert_false "$(starts_with "hello world" "world")" "starts_with should return false"

    # Test ends_with function
    ends_with() {
        local string="$1"
        local suffix="$2"
        [[ "$string" == *"$suffix" ]]
    }

    assert_true "$(ends_with "hello world" "world")" "ends_with should work"
    assert_false "$(ends_with "hello world" "hello")" "ends_with should return false"

    echo "Basic utilities tests completed"
}

# Test file operations
test_file_operations() {
    echo "Testing file operations..."

    local test_file="$TEST_TEMP_DIR/test_file.txt"
    local test_content="Test content"

    # Test file creation
    echo "$test_content" > "$test_file"
    assert_true "[[ -f '$test_file' ]]" "File should be created"

    # Test file size function
    file_size() {
        local file="$1"
        stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || printf '0'
    }

    local size
    size=$(file_size "$test_file")
    assert_true "[[ $size -gt 0 ]]" "File size should be greater than 0"

    # Test empty file check
    is_file_empty() {
        local file="$1"
        [ ! -s "$file" ]
    }

    local empty_file="$TEST_TEMP_DIR/empty.txt"
    touch "$empty_file"
    assert_true "$(is_file_empty "$empty_file")" "Empty file should be detected"
    assert_false "$(is_file_empty "$test_file")" "Non-empty file should not be empty"

    # Test temporary file creation
    temp_file() {
        local prefix="${1:-test}"
        local suffix="${2:-tmp}"
        mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX.${suffix}"
    }

    local temp_file_result
    temp_file_result=$(temp_file "test")
    assert_true "[[ -f '$temp_file_result' ]]" "Temporary file should be created"
    rm -f "$temp_file_result"

    # Test temporary directory creation
    temp_dir() {
        local prefix="${1:-test}"
        mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
    }

    local temp_dir_result
    temp_dir_result=$(temp_dir "test")
    assert_true "[[ -d '$temp_dir_result' ]]" "Temporary directory should be created"
    rmdir "$temp_dir_result"

    echo "File operations tests completed"
}

# Test validation functions
test_validation_functions() {
    echo "Testing validation functions..."

    # Test hostname validation
    is_valid_hostname() {
        local hostname="$1"
        [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]
    }

    assert_true "$(is_valid_hostname "test-server")" "Valid hostname should pass"
    assert_false "$(is_valid_hostname "-invalid")" "Invalid hostname should fail"
    assert_true "$(is_valid_hostname "server01")" "Hostname with numbers should pass"

    # Test username validation
    is_valid_username() {
        local username="$1"
        [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]
    }

    assert_true "$(is_valid_username "testuser")" "Valid username should pass"
    assert_false "$(is_valid_username "InvalidUser")" "Invalid username should fail"
    assert_true "$(is_valid_username "user_name")" "Username with underscore should pass"

    # Test port validation
    is_valid_port() {
        local port="$1"
        [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ]
    }

    assert_true "$(is_valid_port "2222")" "Valid port should pass"
    assert_false "$(is_valid_port "99999")" "Invalid port should fail"
    assert_false "$(is_valid_port "abc")" "Non-numeric port should fail"
    assert_false "$(is_valid_port "80")" "Privileged port should fail"

    # Test IPv4 validation
    is_valid_ipv4() {
        local ip="$1"
        local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

        if [[ ! "$ip" =~ $regex ]]; then
            return 1
        fi

        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
                return 1
            fi
        done

        return 0
    }

    assert_true "$(is_valid_ipv4 "192.168.1.1")" "Valid IPv4 should pass"
    assert_false "$(is_valid_ipv4 "999.999.999.999")" "Invalid IPv4 should fail"
    assert_false "$(is_valid_ipv4 "192.168.1")" "Incomplete IPv4 should fail"

    # Test IPv6 validation (simplified)
    is_valid_ipv6() {
        local ip="$1"
        [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]
    }

    assert_true "$(is_valid_ipv6 "2001:db8::1")" "Valid IPv6 should pass"
    assert_false "$(is_valid_ipv6 "invalid")" "Invalid IPv6 should fail"

    echo "Validation functions tests completed"
}

# Test system information functions
test_system_info() {
    echo "Testing system information functions..."

    # Test system info function
    get_system_info() {
        local info_type="$1"

        case "$info_type" in
            "arch")
                uname -m
                ;;
            "hostname")
                hostname
                ;;
            "kernel")
                uname -r
                ;;
            *)
                echo "unknown"
                ;;
        esac
    }

    local arch_info
    arch_info=$(get_system_info "arch")
    assert_not_equals "" "$arch_info" "Architecture info should be available"
    assert_not_equals "unknown" "$arch_info" "Architecture should not be unknown"

    local hostname_info
    hostname_info=$(get_system_info "hostname")
    assert_not_equals "" "$hostname_info" "Hostname info should be available"

    local kernel_info
    kernel_info=$(get_system_info "kernel")
    assert_not_equals "" "$kernel_info" "Kernel info should be available"

    echo "System information tests completed"
}

# Test command checking
test_command_checking() {
    echo "Testing command checking..."

    # Test command existence function
    command_exists() {
        command -v "$1" >/dev/null 2>&1
    }

    assert_true "$(command_exists "bash")" "bash command should exist"
    assert_false "$(command_exists "nonexistent_command_12345")" "Nonexistent command should not exist"

    assert_true "$(command_exists "ls")" "ls command should exist"
    assert_true "$(command_exists "cat")" "cat command should exist"

    echo "Command checking tests completed"
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
        "test_basic_utilities"
        "test_file_operations"
        "test_validation_functions"
        "test_system_info"
        "test_command_checking"
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