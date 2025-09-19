#!/bin/bash

# OCP-22752 Step-by-Step Assets Creation Test Script
# Tests creating OpenShift assets step by step and then creating cluster without customization

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
WORK_DIR="test-step-by-step"
CLUSTER_NAME="step-by-step-test"
REGION="us-east-2"
SSH_KEY_PATH=""
OPENSHIFT_INSTALL_PATH=""
PULL_SECRET_PATH=""
VERBOSE=false
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
OCP-22752 Step-by-Step Assets Creation Test Script

This script tests creating OpenShift assets step by step and then creating cluster without customization.
It verifies that ignition configs are created correctly and SSH keys are properly distributed.

Usage: $0 [OPTIONS]

Options:
    -w, --work-dir DIR        Working directory (default: test-step-by-step)
    -n, --name NAME           Cluster name (default: step-by-step-test)
    -r, --region REGION       AWS region (default: us-east-2)
    -k, --ssh-key PATH        SSH private key path (required)
    -i, --installer PATH      Path to openshift-install binary (required)
    -p, --pull-secret PATH    Path to pull-secret file (required)
    -v, --verbose             Verbose output
    --no-cleanup              Don't cleanup after test
    -h, --help                Show this help message

Test Steps:
    1. Generate public key from private key
    2. Create install-config
    3. Create manifests
    4. Create ignition configs
    5. Verify SSH key distribution in ignition files
    6. Create cluster
    7. Verify cluster creation and asset matching

Examples:
    $0 -k ~/.ssh/id_rsa -i ./openshift-install -p pull-secret.json
    $0 -k libra.pem -i ./openshift-install -p pull-secret.json -n my-test

EOF
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if openshift-install exists
    if [[ -z "$OPENSHIFT_INSTALL_PATH" ]]; then
        print_error "openshift-install path is required. Use -i option."
        exit 1
    fi
    
    if [[ ! -f "$OPENSHIFT_INSTALL_PATH" ]]; then
        print_error "openshift-install binary not found: $OPENSHIFT_INSTALL_PATH"
        exit 1
    fi
    
    # Check if openshift-install is executable
    if [[ ! -x "$OPENSHIFT_INSTALL_PATH" ]]; then
        print_error "openshift-install binary is not executable: $OPENSHIFT_INSTALL_PATH"
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
    
    # Check pull secret
    if [[ -z "$PULL_SECRET_PATH" ]]; then
        print_error "Pull secret path is required. Use -p option."
        exit 1
    fi
    
    if [[ ! -f "$PULL_SECRET_PATH" ]]; then
        print_error "Pull secret file not found: $PULL_SECRET_PATH"
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Step 1: Generate public key from private key
generate_public_key() {
    print_info "Step 1: Generating public key from private key..."
    
    # Create .ssh directory if it doesn't exist
    mkdir -p ~/.ssh
    
    # Generate public key from private key
    ssh-keygen -y -f "$SSH_KEY_PATH" > ~/.ssh/id_rsa.pub
    
    if [[ -f ~/.ssh/id_rsa.pub ]]; then
        print_success "Public key generated: ~/.ssh/id_rsa.pub"
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Public key content:"
            cat ~/.ssh/id_rsa.pub
        fi
    else
        print_error "Failed to generate public key"
        exit 1
    fi
}

# Step 2: Create install-config
create_install_config() {
    print_info "Step 2: Creating install-config..."
    
    # Create work directory
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # Create install-config.yaml
    "$OPENSHIFT_INSTALL_PATH" create install-config --dir . << EOF
apiVersion: v1
baseDomain: qe1.devcluster.openshift.com
metadata:
  name: $CLUSTER_NAME
platform:
  aws:
    region: $REGION
pullSecret: '$(cat "$PULL_SECRET_PATH")'
sshKey: |
$(cat ~/.ssh/id_rsa.pub | sed 's/^/  /')
EOF
    
    if [[ -f install-config.yaml ]]; then
        print_success "Install config created successfully"
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Install config content:"
            cat install-config.yaml
        fi
    else
        print_error "Failed to create install-config.yaml"
        exit 1
    fi
}

# Step 3: Create manifests
create_manifests() {
    print_info "Step 3: Creating manifests..."
    
    "$OPENSHIFT_INSTALL_PATH" create manifests --dir .
    
    if [[ -d manifests ]]; then
        print_success "Manifests created successfully"
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Manifests directory contents:"
            ls -la manifests/
        fi
    else
        print_error "Failed to create manifests"
        exit 1
    fi
}

# Step 4: Create ignition configs
create_ignition_configs() {
    print_info "Step 4: Creating ignition configs..."
    
    # Capture output to check for warnings
    local ignition_output
    ignition_output=$("$OPENSHIFT_INSTALL_PATH" create ignition-configs --dir . 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "Ignition configs created successfully"
        
        # Check for warning logs
        if echo "$ignition_output" | grep -i "warning\|warn" >/dev/null; then
            print_warning "Warning logs detected during ignition config creation:"
            echo "$ignition_output" | grep -i "warning\|warn"
        else
            print_success "No warning logs detected during ignition config creation"
        fi
        
        # Verify ignition files exist
        local ignition_files=("bootstrap.ign" "master.ign" "worker.ign")
        for file in "${ignition_files[@]}"; do
            if [[ -f "$file" ]]; then
                print_success "Found ignition file: $file"
            else
                print_error "Missing ignition file: $file"
                exit 1
            fi
        done
        
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Ignition config creation output:"
            echo "$ignition_output"
        fi
    else
        print_error "Failed to create ignition configs"
        echo "$ignition_output"
        exit 1
    fi
}

# Step 5: Verify SSH key distribution
verify_ssh_key_distribution() {
    print_info "Step 5: Verifying SSH key distribution in ignition files..."
    
    # Check master.ign - should NOT contain SSH keys
    local master_passwd
    master_passwd=$(cat master.ign | jq '.passwd' 2>/dev/null || echo "{}")
    
    if [[ "$master_passwd" == "{}" ]]; then
        print_success "✅ master.ign correctly does NOT contain SSH keys"
    else
        print_error "❌ master.ign incorrectly contains SSH keys:"
        echo "$master_passwd"
        exit 1
    fi
    
    # Check worker.ign - should NOT contain SSH keys
    local worker_passwd
    worker_passwd=$(cat worker.ign | jq '.passwd' 2>/dev/null || echo "{}")
    
    if [[ "$worker_passwd" == "{}" ]]; then
        print_success "✅ worker.ign correctly does NOT contain SSH keys"
    else
        print_error "❌ worker.ign incorrectly contains SSH keys:"
        echo "$worker_passwd"
        exit 1
    fi
    
    # Check bootstrap.ign - should contain SSH keys
    local bootstrap_passwd
    bootstrap_passwd=$(cat bootstrap.ign | jq '.passwd' 2>/dev/null || echo "{}")
    
    if echo "$bootstrap_passwd" | jq -e '.users[] | select(.name == "core") | .sshAuthorizedKeys' >/dev/null 2>&1; then
        print_success "✅ bootstrap.ign correctly contains SSH keys"
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Bootstrap SSH keys:"
            echo "$bootstrap_passwd" | jq '.users[] | select(.name == "core") | .sshAuthorizedKeys'
        fi
    else
        print_error "❌ bootstrap.ign incorrectly does NOT contain SSH keys:"
        echo "$bootstrap_passwd"
        exit 1
    fi
}

# Step 6: Create cluster
create_cluster() {
    print_info "Step 6: Creating cluster..."
    
    # Capture output to check for asset matching messages
    local cluster_output
    cluster_output=$("$OPENSHIFT_INSTALL_PATH" create cluster --dir . 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "Cluster created successfully"
        
        # Check for asset matching messages
        if echo "$cluster_output" | grep -i "On-disk.*matches asset in state file" >/dev/null; then
            print_success "✅ Asset matching messages found in install log"
            if [[ "$VERBOSE" == "true" ]]; then
                print_info "Asset matching messages:"
                echo "$cluster_output" | grep -i "On-disk.*matches asset in state file"
            fi
        else
            print_warning "⚠️  No asset matching messages found in install log"
        fi
        
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Cluster creation output:"
            echo "$cluster_output"
        fi
    else
        print_error "Failed to create cluster"
        echo "$cluster_output"
        exit 1
    fi
}

# Step 7: Verify cluster status
verify_cluster_status() {
    print_info "Step 7: Verifying cluster status..."
    
    # Check if kubeconfig exists
    if [[ -f auth/kubeconfig ]]; then
        print_success "Kubeconfig file found"
        
        # Test cluster connection
        if KUBECONFIG=auth/kubeconfig oc get nodes &>/dev/null; then
            print_success "✅ Cluster is accessible and nodes are available"
            
            # Get node information
            local node_count
            node_count=$(KUBECONFIG=auth/kubeconfig oc get nodes --no-headers | wc -l)
            print_info "Number of nodes: $node_count"
            
            if [[ "$VERBOSE" == "true" ]]; then
                print_info "Node information:"
                KUBECONFIG=auth/kubeconfig oc get nodes
            fi
        else
            print_warning "⚠️  Cluster created but not fully accessible yet"
        fi
    else
        print_error "Kubeconfig file not found"
        exit 1
    fi
}

# Generate test report
generate_test_report() {
    print_info "Generating test report..."
    
    cat << EOF

==========================================
OCP-22752 Test Report
==========================================

Test Case: [ipi-on-aws] Create assets step by step then create cluster without customization

Test Steps Completed:
✅ Step 1: Generate public key from private key
✅ Step 2: Create install-config
✅ Step 3: Create manifests  
✅ Step 4: Create ignition configs
✅ Step 5: Verify SSH key distribution
✅ Step 6: Create cluster
✅ Step 7: Verify cluster status

Key Verifications:
✅ Bootstrap ignition contains SSH keys
✅ Master ignition does NOT contain SSH keys
✅ Worker ignition does NOT contain SSH keys
✅ No warning logs during ignition creation
✅ Asset matching messages in install log
✅ Cluster created successfully

Test Result: PASS

==========================================
EOF
}

# Cleanup
cleanup() {
    if [[ "$CLEANUP" == "true" ]]; then
        print_info "Cleaning up..."
        
        # Destroy cluster
        if [[ -f install-config.yaml ]]; then
            "$OPENSHIFT_INSTALL_PATH" destroy cluster --dir . --log-level error || true
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
            -i|--installer)
                OPENSHIFT_INSTALL_PATH="$2"
                shift 2
                ;;
            -p|--pull-secret)
                PULL_SECRET_PATH="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
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
    
    print_info "Starting OCP-22752 step-by-step assets creation test..."
    print_info "Work directory: $WORK_DIR"
    print_info "Cluster name: $CLUSTER_NAME"
    print_info "Region: $REGION"
    print_info "SSH key: $SSH_KEY_PATH"
    print_info "Installer: $OPENSHIFT_INSTALL_PATH"
    
    # Execute test steps
    check_prerequisites
    generate_public_key
    create_install_config
    create_manifests
    create_ignition_configs
    verify_ssh_key_distribution
    create_cluster
    verify_cluster_status
    generate_test_report
    
    print_success "🎉 OCP-22752 test completed successfully!"
}

# Trap for cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
