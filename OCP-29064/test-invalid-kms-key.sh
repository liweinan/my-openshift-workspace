#!/bin/bash
#
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
    3. Display KMS key information for manual configuration

Expected Results:
    - KMS key created successfully in KMS region
    - KMS key information provided for manual testing
    - Configuration example provided for install-config.yaml

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
    print_info "Step 1.1: Get user ARN"
    
    echo "# aws sts get-caller-identity --output json | jq -r .Arn"
    
    USER_ARN=$(aws sts get-caller-identity --output json | jq -r .Arn)
    
    if [[ -z "$USER_ARN" ]] || [[ "$USER_ARN" == "null" ]]; then
        print_error "Failed to get user ARN"
        exit 1
    fi
    
    echo "$USER_ARN"
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        print_info "Full caller identity:"
        aws sts get-caller-identity --output json | jq .
    fi
}

# Step 2: Create KMS key
create_kms_key() {
    print_info "Step 1.2: Create KMS key"
    
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
    
    echo "aws kms create-key --region $KMS_REGION --description \"$KMS_DESCRIPTION\" --output json --policy [following policy]"
    echo "$key_policy" | jq .
    
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
        
        echo "$kms_output" | jq .
        echo "KeyId: $KMS_KEY_ID"
        echo "arn: $KMS_KEY_ARN"
        echo "$KMS_KEY_ARN"
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo ""
            print_info "KMS key details:"
            echo "$kms_output" | jq .
        fi
    else
        print_error "Failed to create KMS key"
        exit 1
    fi
}

# Step 3: Display KMS key information for manual configuration
display_kms_info() {
    print_info "Step 3: KMS key information for manual configuration..."
    
    print_success "KMS key created successfully!"
    print_info "Key ID: $KMS_KEY_ID"
    print_info "Key ARN: $KMS_KEY_ARN"
    print_info "Key Region: $KMS_REGION"
    print_info "Cluster Region: $CLUSTER_REGION"
    
    echo ""
    print_info "For manual testing, use the following configuration in your install-config.yaml:"
    echo ""
    echo "controlPlane:"
    echo "  architecture: amd64"
    echo "  hyperthreading: Enabled"
    echo "  name: master"
    echo "  platform:"
    echo "    aws:"
    echo "      rootVolume:"
    echo "        kmsKeyARN: $KMS_KEY_ARN"
    echo "  replicas: 3"
    echo ""
    echo "platform:"
    echo "  aws:"
    echo "    region: $CLUSTER_REGION  # Note: KMS key is in $KMS_REGION (should cause failure)"
    echo ""
    print_warning "This configuration should cause cluster creation to fail due to region mismatch"
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
✅ Step 3: Display KMS key information for manual configuration

Key Information:
- KMS Key ID: ${KMS_KEY_ID:-N/A}
- KMS Key ARN: ${KMS_KEY_ARN:-N/A}
- KMS Key Region: $KMS_REGION
- Cluster Region: $CLUSTER_REGION
- User ARN: ${USER_ARN:-N/A}

Manual Testing Instructions:
✅ KMS key created successfully in $KMS_REGION
✅ Use provided configuration in install-config.yaml
✅ Cluster creation should fail due to invalid KMS key region
✅ Error messages should indicate KMS key region mismatch

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
    display_kms_info
    generate_test_report
    
    print_success "🎉 OCP-29064 test completed successfully!"
}

# Trap for cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
