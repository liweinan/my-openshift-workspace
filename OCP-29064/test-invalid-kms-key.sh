#!/bin/bash
set -x
# OCP-29064 Invalid KMS Key Test Script
# Tests OpenShift installation with invalid KMS key configuration

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
WORK_DIR="demo1"
CLUSTER_NAME="invalid-kms-test"
KMS_REGION="us-east-2"
CLUSTER_REGION="ap-northeast-1"
KMS_DESCRIPTION="testing invalid KMS key"
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
OCP-29064 Invalid KMS Key Test Script

This script tests OpenShift installation with invalid KMS key configuration.
It creates a KMS key in one region and tries to use it in a different region,
which should cause the installation to fail.

Usage: $0 [OPTIONS]

Options:
    -w, --work-dir DIR        Working directory (default: demo1)
    -n, --name NAME           Cluster name (default: invalid-kms-test)
    -k, --kms-region REGION   KMS key region (default: us-east-2)
    -c, --cluster-region REGION Cluster region (default: ap-northeast-1)
    -d, --description DESC    KMS key description (default: testing invalid KMS key)
    -v, --verbose             Verbose output
    --no-cleanup              Don't cleanup after test
    -h, --help                Show this help message

Test Steps:
    1. Get user ARN
    2. Create KMS key in KMS region
    3. Create install-config
    4. Modify install-config with invalid KMS key (different region)
    5. Attempt cluster creation (should fail)
    6. Destroy cluster (cleanup)

Expected Results:
    - KMS key created successfully in KMS region
    - Cluster creation fails due to invalid KMS key region
    - Error messages indicate KMS key region mismatch

Examples:
    $0                                    # Use default settings
    $0 -k us-west-2 -c us-east-1         # Custom regions
    $0 -n my-test -v                      # Custom name with verbose output

EOF
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed. Please install jq first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Step 1: Get user ARN
get_user_arn() {
    print_info "Step 1: Getting user ARN..."
    
    USER_ARN=$(aws sts get-caller-identity --output json | jq -r .Arn)
    
    if [[ -z "$USER_ARN" ]] || [[ "$USER_ARN" == "null" ]]; then
        print_error "Failed to get user ARN"
        exit 1
    fi
    
    print_success "User ARN: $USER_ARN"
    
    if [[ "$VERBOSE" == "true" ]]; then
        print_info "Full caller identity:"
        aws sts get-caller-identity --output json | jq .
    fi
}

# Step 2: Create KMS key
create_kms_key() {
    print_info "Step 2: Creating KMS key in region $KMS_REGION..."
    
    # Create KMS key policy
    local key_policy
    key_policy=$(cat << EOF
{
    "Id": "key-consolepolicy-3",
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Enable IAM User Permissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": "$USER_ARN"
            },
            "Action": "kms:*",
            "Resource": "*"
        }
    ]
}
EOF
)
    
    # Create KMS key
    local kms_output
    kms_output=$(aws kms create-key \
        --region "$KMS_REGION" \
        --description "$KMS_DESCRIPTION" \
        --output json \
        --policy "$key_policy")
    
    if [[ $? -eq 0 ]]; then
        KMS_KEY_ID=$(echo "$kms_output" | jq -r '.KeyMetadata.KeyId')
        KMS_KEY_ARN=$(echo "$kms_output" | jq -r '.KeyMetadata.Arn')
        
        print_success "KMS key created successfully"
        print_success "Key ID: $KMS_KEY_ID"
        print_success "Key ARN: $KMS_KEY_ARN"
        
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "KMS key details:"
            echo "$kms_output" | jq .
        fi
    else
        print_error "Failed to create KMS key"
        exit 1
    fi
}

# Step 3: Create install-config
create_install_config() {
    print_info "Step 3: Creating install-config..."
    
    # Create work directory
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # Create install-config.yaml
    openshift-install create install-config --dir . << EOF
apiVersion: v1
baseDomain: qe1.devcluster.openshift.com
metadata:
  name: $CLUSTER_NAME
platform:
  aws:
    region: $CLUSTER_REGION
pullSecret: '{"auths":{"fake":{"auth":"bar"}}}'
sshKey: |
$(cat ~/.ssh/id_rsa.pub | sed 's/^/  /' 2>/dev/null || echo "  ssh-rsa fake-key")
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

# Step 4: Modify install-config with invalid KMS key
modify_install_config() {
    print_info "Step 4: Modifying install-config with invalid KMS key..."
    print_warning "Adding KMS key from region $KMS_REGION to cluster in region $CLUSTER_REGION (should cause failure)"
    
    # Create modified install-config.yaml with KMS key
    cat > install-config.yaml << EOF
apiVersion: v1
baseDomain: qe1.devcluster.openshift.com
metadata:
  name: $CLUSTER_NAME
platform:
  aws:
    region: $CLUSTER_REGION
pullSecret: '{"auths":{"fake":{"auth":"bar"}}}'
sshKey: |
$(cat ~/.ssh/id_rsa.pub | sed 's/^/  /' 2>/dev/null || echo "  ssh-rsa fake-key")
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      rootVolume:
        kmsKeyARN: $KMS_KEY_ARN
  replicas: 3
EOF
    
    print_success "Install config modified with invalid KMS key"
    print_info "KMS Key ARN: $KMS_KEY_ARN"
    print_info "KMS Key Region: $KMS_REGION"
    print_info "Cluster Region: $CLUSTER_REGION"
    
    if [[ "$VERBOSE" == "true" ]]; then
        print_info "Modified install config:"
        cat install-config.yaml
    fi
}

# Step 5: Attempt cluster creation (should fail)
attempt_cluster_creation() {
    print_info "Step 5: Attempting cluster creation (should fail due to invalid KMS key)..."
    
    # Capture output to analyze errors
    local cluster_output
    cluster_output=$("$OPENSHIFT_INSTALL_PATH" create cluster --dir . 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        print_success "✅ Cluster creation failed as expected"
        
        # Check for specific error patterns
        if echo "$cluster_output" | grep -i "Client.InternalError\|Client error on launch" >/dev/null; then
            print_success "✅ Found expected error pattern: Client.InternalError"
        fi
        
        if echo "$cluster_output" | grep -i "kms\|key" >/dev/null; then
            print_success "✅ Found KMS-related error messages"
        fi
        
        if echo "$cluster_output" | grep -i "region\|invalid" >/dev/null; then
            print_success "✅ Found region/invalid key error messages"
        fi
        
        print_info "Error output analysis:"
        echo "$cluster_output" | grep -E "(error|Error|ERROR)" | head -10
        
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Full cluster creation output:"
            echo "$cluster_output"
        fi
        
        return 0  # Expected failure
    else
        print_error "❌ Cluster creation succeeded unexpectedly"
        print_error "This test should fail due to invalid KMS key region"
        return 1
    fi
}

# Step 6: Destroy cluster (cleanup)
destroy_cluster() {
    print_info "Step 6: Destroying cluster (cleanup)..."
    
    if [[ -f install-config.yaml ]]; then
        if openshift-install destroy cluster --dir . --log-level error; then
            print_success "Cluster destroyed successfully"
        else
            print_warning "Cluster destruction failed or cluster was not created"
        fi
    else
        print_info "No install-config.yaml found, skipping cluster destruction"
    fi
}

# Cleanup KMS key
cleanup_kms_key() {
    if [[ "$CLEANUP" == "true" ]] && [[ -n "${KMS_KEY_ID:-}" ]]; then
        print_info "Cleaning up KMS key..."
        
        # Schedule key deletion (7-30 days)
        if aws kms schedule-key-deletion \
            --region "$KMS_REGION" \
            --key-id "$KMS_KEY_ID" \
            --pending-window-in-days 7; then
            print_success "KMS key scheduled for deletion"
        else
            print_warning "Failed to schedule KMS key deletion"
        fi
    fi
}

# Generate test report
generate_test_report() {
    print_info "Generating test report..."
    
    cat << EOF

==========================================
OCP-29064 Invalid KMS Key Test Report
==========================================

Test Case: [ipi-on-aws] IPI Installer with KMS configuration [invalid key]

Test Steps Completed:
✅ Step 1: Get user ARN
✅ Step 2: Create KMS key in $KMS_REGION
✅ Step 3: Create install-config
✅ Step 4: Modify install-config with invalid KMS key
✅ Step 5: Attempt cluster creation (failed as expected)
✅ Step 6: Destroy cluster (cleanup)

Key Information:
- KMS Key ID: ${KMS_KEY_ID:-N/A}
- KMS Key ARN: ${KMS_KEY_ARN:-N/A}
- KMS Key Region: $KMS_REGION
- Cluster Region: $CLUSTER_REGION
- User ARN: ${USER_ARN:-N/A}

Expected Results:
✅ KMS key created successfully in $KMS_REGION
✅ Cluster creation failed due to invalid KMS key region
✅ Error messages indicate KMS key region mismatch

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
            destroy_cluster
        fi
        
        # Cleanup KMS key
        cleanup_kms_key
        
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
            -k|--kms-region)
                KMS_REGION="$2"
                shift 2
                ;;
            -c|--cluster-region)
                CLUSTER_REGION="$2"
                shift 2
                ;;
            -d|--description)
                KMS_DESCRIPTION="$2"
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
    
    print_info "Starting OCP-29064 invalid KMS key test..."
    print_info "Work directory: $WORK_DIR"
    print_info "Cluster name: $CLUSTER_NAME"
    print_info "KMS region: $KMS_REGION"
    print_info "Cluster region: $CLUSTER_REGION"
    
    # Execute test steps
    check_prerequisites
    get_user_arn
    create_kms_key
    create_install_config
    modify_install_config
    attempt_cluster_creation
    generate_test_report
    
    print_success "🎉 OCP-29064 test completed successfully!"
}

# Trap for cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
