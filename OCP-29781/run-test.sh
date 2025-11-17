#!/bin/bash

# OCP-29781 Main Test Script
# Execute complete test workflow

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Test step counter
STEP_COUNT=0

# Execute test step
run_step() {
    local step_name="$1"
    local step_command="$2"
    
    ((STEP_COUNT++))
    echo
    log_info "=== Step ${STEP_COUNT}: ${step_name} ==="
    
    if eval "${step_command}"; then
        log_success "Step ${STEP_COUNT} completed: ${step_name}"
        return 0
    else
        log_error "Step ${STEP_COUNT} failed: ${step_name}"
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required tools
    local required_tools=("aws" "openshift-install" "oc" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" &> /dev/null; then
            log_error "Required tool not found: ${tool}"
            return 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        return 1
    fi
    
    # Check configuration files
    local required_files=(
        "install-config-cluster1.yaml"
        "install-config-cluster2.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "${file}" ]]; then
            log_error "Configuration file not found: ${file}"
            return 1
        fi
        
        # Check if configuration files still contain placeholders
        if grep -q "YOUR_PULL_SECRET_HERE\|YOUR_SSH_PUBLIC_KEY_HERE" "${file}"; then
            log_error "Configuration file ${file} contains placeholders, please update with actual values"
            return 1
        fi
    done
    
    log_success "Prerequisites check passed"
    return 0
}

# Display usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Display this help information"
    echo "  -s, --step STEP         Start execution from specified step"
    echo "  -e, --end-step STEP     End execution at specified step"
    echo "  -c, --cleanup-only      Only execute cleanup steps"
    echo "  -f, --force             Force execution without confirmation"
    echo ""
    echo "Test steps:"
    echo "  1  - Create VPC and subnets"
    echo "  2  - Create cluster 1"
    echo "  3  - Cluster 1 health check"
    echo "  4  - Create cluster 2"
    echo "  5  - Cluster 2 health check"
    echo "  6  - Security group check"
    echo "  7  - Network isolation test"
    echo "  8  - Cleanup resources"
    echo ""
    echo "Examples:"
    echo "  $0                      # Execute complete test"
    echo "  $0 -s 3                 # Start from step 3"
    echo "  $0 -s 1 -e 5            # Execute steps 1-5"
    echo "  $0 -c                   # Only cleanup resources"
}

# Main function
main() {
    local start_step=1
    local end_step=8
    local cleanup_only=false
    local force=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -s|--step)
                start_step="$2"
                shift 2
                ;;
            -e|--end-step)
                end_step="$2"
                shift 2
                ;;
            -c|--cleanup-only)
                cleanup_only=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Confirm execution
    if [[ "${force}" != "true" ]]; then
        echo
        log_warning "This script will execute OCP-29781 test, including:"
        echo "  - Create VPC and subnets"
        echo "  - Create two OpenShift clusters"
        echo "  - Execute various validation tests"
        echo "  - Clean up all resources"
        echo
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled"
            exit 0
        fi
    fi
    
    log_info "Starting OCP-29781 test"
    log_info "Executing steps: ${start_step} - ${end_step}"
    echo
    
    # Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    
    local test_failed=false
    
    # Execute test steps
    if [[ "${cleanup_only}" == "true" ]]; then
        # Only execute cleanup
        if ! run_step "Cleanup resources" "./cleanup.sh -f"; then
            test_failed=true
        fi
    else
        # Execute complete test workflow
        if [[ ${start_step} -le 1 && ${end_step} -ge 1 ]]; then
            if ! run_step "Create VPC and subnets" "./create-vpc.sh"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 2 && ${end_step} -ge 2 ]]; then
            if ! run_step "Create cluster 1" "mkdir -p cluster1 && cp install-config-cluster1.yaml cluster1/install-config.yaml && openshift-install --dir=cluster1 create cluster"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 3 && ${end_step} -ge 3 ]]; then
            if ! run_step "Cluster 1 health check" "./health-check.sh cluster1"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 4 && ${end_step} -ge 4 ]]; then
            if ! run_step "Create cluster 2" "mkdir -p cluster2 && cp install-config-cluster2.yaml cluster2/install-config.yaml && openshift-install --dir=cluster2 create cluster"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 5 && ${end_step} -ge 5 ]]; then
            if ! run_step "Cluster 2 health check" "./health-check.sh cluster2"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 6 && ${end_step} -ge 6 ]]; then
            if ! run_step "Security group check" "./security-group-check.sh cluster1 10.134.0.0/16 && ./security-group-check.sh cluster2 10.190.0.0/16"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 7 && ${end_step} -ge 7 ]]; then
            if ! run_step "Network isolation test" "./network-isolation-test.sh cluster1 cluster2"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 8 && ${end_step} -ge 8 ]]; then
            if ! run_step "Cleanup resources" "./cleanup.sh -f"; then
                test_failed=true
            fi
        fi
    fi
    
    # Summarize results
    echo
    if [[ "${test_failed}" == "true" ]]; then
        log_error "Test failed"
        exit 1
    else
        log_success "Test completed"
        exit 0
    fi
}

# Run main function
main "$@"