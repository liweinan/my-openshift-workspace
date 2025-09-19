#!/bin/bash

# OCP-22752 Ignition SSH Keys Verification Script
# Verifies SSH key distribution in ignition config files

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
WORK_DIR="."
VERBOSE=false

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Show help
show_help() {
    cat << EOF
OCP-22752 Ignition SSH Keys Verification Script

This script verifies SSH key distribution in OpenShift ignition config files.
It checks that SSH keys are present in bootstrap.ign but not in master.ign or worker.ign.

Usage: $0 [OPTIONS]

Options:
    -w, --work-dir DIR        Working directory containing ignition files (default: .)
    -v, --verbose             Verbose output
    -h, --help                Show this help message

Expected Results:
    - bootstrap.ign: Should contain SSH keys for 'core' user
    - master.ign: Should NOT contain SSH keys (empty passwd)
    - worker.ign: Should NOT contain SSH keys (empty passwd)

Examples:
    $0                                    # Check current directory
    $0 -w /path/to/ignition/files        # Check specific directory
    $0 -v                                # Verbose output

EOF
}

# Check if jq is available
check_jq() {
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed. Please install jq first."
        exit 1
    fi
}

# Verify ignition file exists
check_ignition_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        print_error "Ignition file not found: $file"
        return 1
    fi
    return 0
}

# Verify bootstrap.ign contains SSH keys
verify_bootstrap_ssh_keys() {
    print_info "Verifying bootstrap.ign SSH keys..."
    
    if ! check_ignition_file "bootstrap.ign"; then
        return 1
    fi
    
    # Extract passwd section
    local passwd_section
    passwd_section=$(cat bootstrap.ign | jq '.passwd' 2>/dev/null || echo "{}")
    
    if [[ "$passwd_section" == "{}" ]]; then
        print_error "❌ bootstrap.ign does NOT contain passwd section"
        return 1
    fi
    
    # Check for core user
    local core_user
    core_user=$(echo "$passwd_section" | jq '.users[] | select(.name == "core")' 2>/dev/null || echo "null")
    
    if [[ "$core_user" == "null" ]]; then
        print_error "❌ bootstrap.ign does NOT contain 'core' user"
        return 1
    fi
    
    # Check for SSH authorized keys
    local ssh_keys
    ssh_keys=$(echo "$core_user" | jq '.sshAuthorizedKeys' 2>/dev/null || echo "null")
    
    if [[ "$ssh_keys" == "null" ]] || [[ "$ssh_keys" == "[]" ]]; then
        print_error "❌ bootstrap.ign does NOT contain SSH authorized keys for 'core' user"
        return 1
    fi
    
    # Count SSH keys
    local key_count
    key_count=$(echo "$ssh_keys" | jq 'length' 2>/dev/null || echo "0")
    
    if [[ "$key_count" -gt 0 ]]; then
        print_success "✅ bootstrap.ign contains $key_count SSH key(s) for 'core' user"
        
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "SSH keys in bootstrap.ign:"
            echo "$ssh_keys" | jq -r '.[]' | sed 's/^/  /'
        fi
        return 0
    else
        print_error "❌ bootstrap.ign contains empty SSH authorized keys"
        return 1
    fi
}

# Verify master.ign does NOT contain SSH keys
verify_master_no_ssh_keys() {
    print_info "Verifying master.ign does NOT contain SSH keys..."
    
    if ! check_ignition_file "master.ign"; then
        return 1
    fi
    
    # Extract passwd section
    local passwd_section
    passwd_section=$(cat master.ign | jq '.passwd' 2>/dev/null || echo "{}")
    
    if [[ "$passwd_section" == "{}" ]]; then
        print_success "✅ master.ign correctly does NOT contain passwd section"
        return 0
    fi
    
    # Check for users
    local users
    users=$(echo "$passwd_section" | jq '.users' 2>/dev/null || echo "null")
    
    if [[ "$users" == "null" ]] || [[ "$users" == "[]" ]]; then
        print_success "✅ master.ign correctly does NOT contain users"
        return 0
    fi
    
    # Check for SSH keys in any user
    local has_ssh_keys
    has_ssh_keys=$(echo "$passwd_section" | jq '.users[] | has("sshAuthorizedKeys")' 2>/dev/null || echo "false")
    
    if echo "$has_ssh_keys" | grep -q "true"; then
        print_error "❌ master.ign incorrectly contains SSH keys"
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Master.ign passwd section:"
            echo "$passwd_section" | jq .
        fi
        return 1
    else
        print_success "✅ master.ign correctly does NOT contain SSH keys"
        return 0
    fi
}

# Verify worker.ign does NOT contain SSH keys
verify_worker_no_ssh_keys() {
    print_info "Verifying worker.ign does NOT contain SSH keys..."
    
    if ! check_ignition_file "worker.ign"; then
        return 1
    fi
    
    # Extract passwd section
    local passwd_section
    passwd_section=$(cat worker.ign | jq '.passwd' 2>/dev/null || echo "{}")
    
    if [[ "$passwd_section" == "{}" ]]; then
        print_success "✅ worker.ign correctly does NOT contain passwd section"
        return 0
    fi
    
    # Check for users
    local users
    users=$(echo "$passwd_section" | jq '.users' 2>/dev/null || echo "null")
    
    if [[ "$users" == "null" ]] || [[ "$users" == "[]" ]]; then
        print_success "✅ worker.ign correctly does NOT contain users"
        return 0
    fi
    
    # Check for SSH keys in any user
    local has_ssh_keys
    has_ssh_keys=$(echo "$passwd_section" | jq '.users[] | has("sshAuthorizedKeys")' 2>/dev/null || echo "false")
    
    if echo "$has_ssh_keys" | grep -q "true"; then
        print_error "❌ worker.ign incorrectly contains SSH keys"
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Worker.ign passwd section:"
            echo "$passwd_section" | jq .
        fi
        return 1
    else
        print_success "✅ worker.ign correctly does NOT contain SSH keys"
        return 0
    fi
}

# Generate verification report
generate_report() {
    local bootstrap_result=$1
    local master_result=$2
    local worker_result=$3
    
    print_info "Generating verification report..."
    
    cat << EOF

==========================================
OCP-22752 Ignition SSH Keys Verification Report
==========================================

Test Case: [ipi-on-aws] Create assets step by step then create cluster without customization
Verification: SSH key distribution in ignition config files

Results:
EOF

    if [[ $bootstrap_result -eq 0 ]]; then
        echo "✅ bootstrap.ign: Contains SSH keys (CORRECT)"
    else
        echo "❌ bootstrap.ign: Missing SSH keys (INCORRECT)"
    fi
    
    if [[ $master_result -eq 0 ]]; then
        echo "✅ master.ign: No SSH keys (CORRECT)"
    else
        echo "❌ master.ign: Contains SSH keys (INCORRECT)"
    fi
    
    if [[ $worker_result -eq 0 ]]; then
        echo "✅ worker.ign: No SSH keys (CORRECT)"
    else
        echo "❌ worker.ign: Contains SSH keys (INCORRECT)"
    fi
    
    echo ""
    
    if [[ $bootstrap_result -eq 0 ]] && [[ $master_result -eq 0 ]] && [[ $worker_result -eq 0 ]]; then
        echo "🎉 Overall Result: PASS - All SSH key distributions are correct"
        echo ""
        echo "Expected Results Verified:"
        echo "✅ bootstrap.ign contains SSH keys for 'core' user"
        echo "✅ master.ign does NOT contain SSH keys"
        echo "✅ worker.ign does NOT contain SSH keys"
        return 0
    else
        echo "💥 Overall Result: FAIL - SSH key distribution is incorrect"
        echo ""
        echo "Issues Found:"
        [[ $bootstrap_result -ne 0 ]] && echo "❌ bootstrap.ign SSH key issue"
        [[ $master_result -ne 0 ]] && echo "❌ master.ign SSH key issue"
        [[ $worker_result -ne 0 ]] && echo "❌ worker.ign SSH key issue"
        return 1
    fi
}

# Main function
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -w|--work-dir)
                WORK_DIR="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Change to work directory
    if [[ "$WORK_DIR" != "." ]]; then
        if [[ ! -d "$WORK_DIR" ]]; then
            print_error "Work directory not found: $WORK_DIR"
            exit 1
        fi
        cd "$WORK_DIR"
    fi
    
    print_info "Starting OCP-22752 ignition SSH keys verification..."
    print_info "Work directory: $(pwd)"
    
    # Check prerequisites
    check_jq
    
    # Verify ignition files
    local bootstrap_result=0
    local master_result=0
    local worker_result=0
    
    verify_bootstrap_ssh_keys || bootstrap_result=1
    verify_master_no_ssh_keys || master_result=1
    verify_worker_no_ssh_keys || worker_result=1
    
    # Generate report
    generate_report $bootstrap_result $master_result $worker_result
    local overall_result=$?
    
    exit $overall_result
}

# Run main function
main "$@"
