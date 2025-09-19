#!/bin/bash

# OCP-23394 Bootstrap Log Collection Test Script
# Tests log collection from a cluster that failed to bootstrap

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
WORK_DIR="test-bootstrap-failure"
CLUSTER_NAME="bootstrap-test"
REGION="us-east-2"
SSH_KEY_PATH=""
INTERRUPT_METHOD="log"
TIMEOUT=1800  # 30 minutes
CLEANUP=true

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
OCP-23394 Bootstrap Log Collection Test Script

This script tests log collection from a cluster that failed to bootstrap.
It intentionally interrupts the installation process and collects debug logs.

Usage: $0 [OPTIONS]

Options:
    -w, --work-dir DIR        Working directory (default: test-bootstrap-failure)
    -n, --name NAME           Cluster name (default: bootstrap-test)
    -r, --region REGION       AWS region (default: us-east-2)
    -k, --ssh-key PATH        SSH key path (required)
    -m, --method METHOD       Interrupt method: log, wait (default: log)
    -t, --timeout SECONDS     Installation timeout (default: 1800)
    --no-cleanup              Don't cleanup after test
    -h, --help                Show this help message

Interrupt Methods:
    log    - Interrupt when seeing bootstrap-success message
    wait   - Interrupt during wait-for install-complete

Examples:
    $0 -k ~/.ssh/id_rsa
    $0 -k ~/.ssh/id_rsa -m wait -t 2400
    $0 -k ~/.ssh/id_rsa -n my-test -r us-west-2

EOF
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if openshift-install exists
    if ! command -v openshift-install &> /dev/null; then
        print_error "openshift-install not found. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check SSH key
    if [[ -z "$SSH_KEY_PATH" ]]; then
        print_error "SSH key path is required. Use -k option."
        exit 1
    fi
    
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        print_error "SSH key file not found: $SSH_KEY_PATH"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Setup SSH agent
setup_ssh_agent() {
    print_info "Setting up SSH agent..."
    
    # Start SSH agent if not running
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        eval `ssh-agent -s`
    fi
    
    # Add SSH key
    ssh-add "$SSH_KEY_PATH"
    
    # Verify key is added
    if ssh-add -l | grep -q "$(ssh-keygen -lf "$SSH_KEY_PATH" | awk '{print $2}')"; then
        print_success "SSH key added to agent"
    else
        print_error "Failed to add SSH key to agent"
        exit 1
    fi
}

# Create install config
create_install_config() {
    print_info "Creating install-config.yaml..."
    
    # Create work directory
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # Generate install-config.yaml
    openshift-install create install-config --dir . << EOF
apiVersion: v1
baseDomain: qe1.devcluster.openshift.com
metadata:
  name: $CLUSTER_NAME
platform:
  aws:
    region: $REGION
pullSecret: '{"auths":{"fake":{"auth":"bar"}}}'
sshKey: |
$(cat "$SSH_KEY_PATH" | sed 's/^/  /')
EOF
    
    print_success "Install config created"
}

# Monitor installation and interrupt
monitor_and_interrupt() {
    print_info "Starting cluster installation..."
    print_warning "Monitoring for interrupt condition..."
    
    if [[ "$INTERRUPT_METHOD" == "log" ]]; then
        monitor_log_message
    else
        monitor_wait_complete
    fi
}

# Monitor for bootstrap-success message
monitor_log_message() {
    print_info "Monitoring for bootstrap-success message..."
    
    # Start installation in background
    openshift-install create cluster --dir . > install.log 2>&1 &
    INSTALL_PID=$!
    
    # Monitor log file
    local found_message=false
    local start_time=$(date +%s)
    
    while [[ $found_message == false ]] && [[ $(($(date +%s) - start_time)) -lt $TIMEOUT ]]; do
        if [[ -f install.log ]]; then
            if grep -q "added bootstrap-success: Required control plane pods have been created" install.log; then
                print_success "Found bootstrap-success message! Interrupting installation..."
                kill -INT $INSTALL_PID 2>/dev/null || true
                found_message=true
                break
            fi
        fi
        sleep 5
    done
    
    if [[ $found_message == false ]]; then
        print_warning "Timeout reached or message not found. Stopping installation..."
        kill -TERM $INSTALL_PID 2>/dev/null || true
    fi
    
    # Wait for process to finish
    wait $INSTALL_PID 2>/dev/null || true
}

# Monitor wait-for complete
monitor_wait_complete() {
    print_info "Using wait-for method..."
    
    # Start installation
    openshift-install create cluster --dir . &
    INSTALL_PID=$!
    
    # Wait for bootstrap to complete
    print_info "Waiting for bootstrap to complete..."
    if openshift-install wait-for bootstrap-complete --dir . --log-level debug; then
        print_success "Bootstrap completed successfully"
        
        # Now interrupt during install-complete
        print_info "Interrupting during install-complete..."
        openshift-install wait-for install-complete --dir . &
        WAIT_PID=$!
        
        sleep 10  # Give it a moment to start
        kill -INT $WAIT_PID 2>/dev/null || true
        wait $WAIT_PID 2>/dev/null || true
    else
        print_warning "Bootstrap did not complete as expected"
    fi
    
    # Stop main installation
    kill -TERM $INSTALL_PID 2>/dev/null || true
    wait $INSTALL_PID 2>/dev/null || true
}

# Get cluster information
get_cluster_info() {
    print_info "Getting cluster information..."
    
    # Get bootstrap node IP
    BOOTSTRAP_IP=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$CLUSTER_NAME-bootstrap" \
        --query 'Reservations[*].Instances[*].PublicIpAddress' \
        --output text 2>/dev/null | head -1)
    
    if [[ -z "$BOOTSTRAP_IP" ]]; then
        print_error "Could not find bootstrap node IP"
        return 1
    fi
    
    # Get master node IPs
    MASTER_IPS=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$CLUSTER_NAME-master-*" \
        --query 'Reservations[*].Instances[*].PrivateIpAddress' \
        --output text 2>/dev/null | tr '\t' ' ')
    
    if [[ -z "$MASTER_IPS" ]]; then
        print_error "Could not find master node IPs"
        return 1
    fi
    
    print_success "Bootstrap IP: $BOOTSTRAP_IP"
    print_success "Master IPs: $MASTER_IPS"
}

# Collect logs
collect_logs() {
    print_info "Collecting bootstrap logs..."
    
    # Method 1: Using directory
    print_info "Trying method 1: Using directory..."
    if openshift-install gather bootstrap --dir . 2>/dev/null; then
        print_success "Log collection command generated"
    else
        print_warning "Method 1 failed, trying method 2..."
        
        # Method 2: Using specific IPs
        print_info "Trying method 2: Using specific IPs..."
        if openshift-install gather bootstrap \
            --bootstrap "$BOOTSTRAP_IP" \
            --master "$MASTER_IPS" 2>/dev/null; then
            print_success "Log collection command generated"
        else
            print_error "Both log collection methods failed"
            return 1
        fi
    fi
    
    # Execute the log collection
    print_info "Executing log collection..."
    if ssh -A -o ConnectTimeout=30 -o StrictHostKeyChecking=no \
        core@$BOOTSTRAP_IP "/usr/local/bin/installer-gather.sh $MASTER_IPS"; then
        print_success "Log collection completed on bootstrap node"
    else
        print_error "Failed to execute log collection on bootstrap node"
        return 1
    fi
    
    # Download log bundle
    print_info "Downloading log bundle..."
    if scp -o ConnectTimeout=30 -o StrictHostKeyChecking=no \
        core@$BOOTSTRAP_IP:~/log-bundle.tar.gz .; then
        print_success "Log bundle downloaded successfully"
    else
        print_error "Failed to download log bundle"
        return 1
    fi
}

# Verify logs
verify_logs() {
    print_info "Verifying collected logs..."
    
    if [[ ! -f log-bundle.tar.gz ]]; then
        print_error "Log bundle not found"
        return 1
    fi
    
    # Extract logs
    tar xvf log-bundle.tar.gz
    
    # Check for required directories
    local has_journal=false
    local has_nodes_list=false
    local has_serial=false
    
    if find . -name "journal" -type d | grep -q .; then
        has_journal=true
        print_success "Found journal logs"
    else
        print_warning "No journal logs found"
    fi
    
    if find . -name "nodes.list" | grep -q .; then
        has_nodes_list=true
        print_success "Found nodes.list"
    else
        print_warning "No nodes.list found"
    fi
    
    if find . -name "serial" -type d | grep -q .; then
        has_serial=true
        print_success "Found serial logs (4.11+)"
    else
        print_info "No serial logs found (may be pre-4.11)"
    fi
    
    # Show log structure
    print_info "Log bundle structure:"
    find . -type f -name "*.log" -o -name "nodes.list" | head -10
    
    # Check log sizes
    print_info "Log sizes:"
    du -sh */journal/ 2>/dev/null || true
    du -sh */serial/ 2>/dev/null || true
    
    # Test result
    if [[ $has_journal == true ]] && [[ $has_nodes_list == true ]]; then
        print_success "✅ Test PASSED - Required logs collected successfully"
        return 0
    else
        print_error "❌ Test FAILED - Missing required log components"
        return 1
    fi
}

# Cleanup
cleanup() {
    if [[ "$CLEANUP" == "true" ]]; then
        print_info "Cleaning up..."
        
        # Destroy cluster
        if [[ -f install-config.yaml ]]; then
            openshift-install destroy cluster --dir . --log-level error || true
        fi
        
        # Remove work directory
        cd ..
        rm -rf "$WORK_DIR"
        
        print_success "Cleanup completed"
    else
        print_info "Skipping cleanup (--no-cleanup specified)"
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
            -n|--name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -k|--ssh-key)
                SSH_KEY_PATH="$2"
                shift 2
                ;;
            -m|--method)
                INTERRUPT_METHOD="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --no-cleanup)
                CLEANUP=false
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
    
    # Validate inputs
    if [[ ! "$INTERRUPT_METHOD" =~ ^(log|wait)$ ]]; then
        print_error "Invalid interrupt method: $INTERRUPT_METHOD. Must be 'log' or 'wait'"
        exit 1
    fi
    
    print_info "Starting OCP-23394 bootstrap log collection test..."
    print_info "Work directory: $WORK_DIR"
    print_info "Cluster name: $CLUSTER_NAME"
    print_info "Region: $REGION"
    print_info "Interrupt method: $INTERRUPT_METHOD"
    
    # Execute test steps
    check_prerequisites
    setup_ssh_agent
    create_install_config
    monitor_and_interrupt
    get_cluster_info
    collect_logs
    verify_logs
    
    local test_result=$?
    
    # Cleanup
    cleanup
    
    if [[ $test_result -eq 0 ]]; then
        print_success "🎉 OCP-23394 test completed successfully!"
        exit 0
    else
        print_error "💥 OCP-23394 test failed!"
        exit 1
    fi
}

# Trap for cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
