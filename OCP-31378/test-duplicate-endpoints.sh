#!/bin/bash

# OCP-31378 Duplicate Service Endpoints Test Script
# Tests that OpenShift installer validates against duplicate service endpoints

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Default values
WORK_DIR="test-duplicate-endpoints"
REGION="us-gov-west-1"
CLUSTER_NAME="test-duplicate-endpoints"
BASE_DOMAIN="example.com"
PULL_SECRET_FILE=""
SSH_KEY_FILE=""
OPENSHIFT_INSTALL_PATH=""
SERVICES=("ec2" "s3" "iam")
DRY_RUN=false
CLEANUP=true

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OCP-31378 Duplicate Service Endpoints Test Script
Tests that OpenShift installer validates against duplicate service endpoints

OPTIONS:
    -w, --work-dir DIR        Working directory for test (default: test-duplicate-endpoints)
    -r, --region REGION       AWS region (default: us-gov-west-1)
    -n, --name NAME           Cluster name (default: test-duplicate-endpoints)
    -d, --domain DOMAIN       Base domain (default: example.com)
    -p, --pull-secret FILE    Path to pull secret file (required)
    -s, --ssh-key FILE        Path to SSH public key file (required)
    --openshift-install PATH  Path to openshift-install binary (optional)
    --services SERVICES       Comma-separated list of services to test (default: ec2,s3,iam)
    --dry-run                 Show what would be created without actually creating
    --no-cleanup              Don't clean up test files after completion
    -h, --help                Show this help message

EXAMPLES:
    $0 -p pull-secret.json -s ~/.ssh/id_rsa.pub
    $0 -p pull-secret.json -s ~/.ssh/id_rsa.pub -r us-gov-east-1
    $0 -p pull-secret.json -s ~/.ssh/id_rsa.pub --services ec2,s3 --dry-run

TEST DESCRIPTION:
    This script tests OCP-31378 which verifies that the OpenShift installer
    properly validates against duplicate service endpoints in install-config.yaml.
    
    The test creates an install-config.yaml with duplicate endpoints for the
    same service and expects the installer to report a validation error.

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -n|--name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -d|--domain)
            BASE_DOMAIN="$2"
            shift 2
            ;;
        -p|--pull-secret)
            PULL_SECRET_FILE="$2"
            shift 2
            ;;
        -s|--ssh-key)
            SSH_KEY_FILE="$2"
            shift 2
            ;;
        --openshift-install)
            OPENSHIFT_INSTALL_PATH="$2"
            shift 2
            ;;
        --services)
            IFS=',' read -ra SERVICES <<< "$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-cleanup)
            CLEANUP=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$PULL_SECRET_FILE" ] || [ -z "$SSH_KEY_FILE" ]; then
    print_error "Missing required parameters"
    usage
    exit 1
fi

# Check if files exist
if [ ! -f "$PULL_SECRET_FILE" ]; then
    print_error "Pull secret file not found: $PULL_SECRET_FILE"
    exit 1
fi

if [ ! -f "$SSH_KEY_FILE" ]; then
    print_error "SSH key file not found: $SSH_KEY_FILE"
    exit 1
fi

# Determine openshift-install command
OPENSHIFT_INSTALL_CMD=""
if [ -n "$OPENSHIFT_INSTALL_PATH" ]; then
    if [ -f "$OPENSHIFT_INSTALL_PATH" ] && [ -x "$OPENSHIFT_INSTALL_PATH" ]; then
        OPENSHIFT_INSTALL_CMD="$OPENSHIFT_INSTALL_PATH"
    else
        print_error "openshift-install binary not found or not executable: $OPENSHIFT_INSTALL_PATH"
        exit 1
    fi
else
    if command -v openshift-install &> /dev/null; then
        OPENSHIFT_INSTALL_CMD="openshift-install"
    else
        print_error "openshift-install command not found"
        print_error "Please ensure openshift-install is installed and in your PATH, or use --openshift-install option"
        exit 1
    fi
fi

print_info "Using openshift-install: $OPENSHIFT_INSTALL_CMD"

# Generate service endpoints with duplicates
generate_service_endpoints() {
    local service_name="$1"
    local region="$2"
    
    # Generate two identical endpoints for the same service
    cat << EOF
    - name: $service_name
      url: https://$service_name.$region.amazonaws.com
    - name: $service_name
      url: https://$service_name.$region.amazonaws.com
EOF
}

# Create install-config.yaml with duplicate endpoints
create_install_config() {
    print_info "Creating install-config.yaml with duplicate service endpoints..."
    
    # Create work directory
    mkdir -p "$WORK_DIR"
    
    # Read pull secret
    local pull_secret
    pull_secret=$(cat "$PULL_SECRET_FILE")
    
    # Read SSH key
    local ssh_key
    ssh_key=$(cat "$SSH_KEY_FILE")
    
    # Generate service endpoints
    local service_endpoints=""
    for service in "${SERVICES[@]}"; do
        service_endpoints+=$(generate_service_endpoints "$service" "$REGION")
    done
    
    # Create install-config.yaml
    cat > "$WORK_DIR/install-config.yaml" << EOF
apiVersion: v1
baseDomain: $BASE_DOMAIN
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 1
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 1
metadata:
  name: $CLUSTER_NAME
platform:
  aws:
    region: $REGION
    serviceEndpoints:$service_endpoints
pullSecret: '$pull_secret'
sshKey: '$ssh_key'
EOF
    
    print_success "Created install-config.yaml with duplicate endpoints for services: ${SERVICES[*]}"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "Install-config.yaml content:"
        cat "$WORK_DIR/install-config.yaml"
        return 0
    fi
}

# Test installer validation
test_installer_validation() {
    print_info "Testing installer validation with duplicate endpoints..."
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would test installer validation"
        return 0
    fi
    
    # Try to create manifests (this should fail with validation error)
    print_info "Attempting to create manifests (expecting validation error)..."
    
    local validation_output
    local validation_exit_code
    
    # Capture both stdout and stderr
    validation_output=$("$OPENSHIFT_INSTALL_CMD" create manifests --dir "$WORK_DIR" 2>&1) || validation_exit_code=$?
    
    print_info "Installer output:"
    echo "$validation_output"
    
    # Check if validation failed as expected
    if [ $validation_exit_code -ne 0 ]; then
        # Check if the error message contains information about duplicate endpoints
        if echo "$validation_output" | grep -i "duplicate\|multiple.*endpoint\|service.*endpoint.*already" >/dev/null; then
            print_success "Validation error detected as expected!"
            print_success "Installer correctly rejected duplicate service endpoints"
            return 0
        else
            print_warning "Installer failed, but error message doesn't clearly indicate duplicate endpoint issue"
            print_warning "Exit code: $validation_exit_code"
            return 1
        fi
    else
        print_error "Installer validation passed unexpectedly!"
        print_error "Expected validation error for duplicate endpoints, but installation succeeded"
        return 1
    fi
}

# Clean up test files
cleanup() {
    if [ "$CLEANUP" = true ] && [ -d "$WORK_DIR" ]; then
        print_info "Cleaning up test files..."
        rm -rf "$WORK_DIR"
        print_success "Cleanup completed"
    else
        print_info "Test files preserved in: $WORK_DIR"
    fi
}

# Generate test report
generate_test_report() {
    local test_result="$1"
    
    echo ""
    echo "=========================================="
    echo "        OCP-31378 Test Report"
    echo "=========================================="
    echo ""
    echo "📊 Test Configuration:"
    echo "   Work Directory: $WORK_DIR"
    echo "   Region: $REGION"
    echo "   Cluster Name: $CLUSTER_NAME"
    echo "   Base Domain: $BASE_DOMAIN"
    echo "   Services Tested: ${SERVICES[*]}"
    echo ""
    echo "🔍 Test Description:"
    echo "   This test verifies that the OpenShift installer properly validates"
    echo "   against duplicate service endpoints in install-config.yaml."
    echo ""
    echo "   The test creates an install-config.yaml with duplicate endpoints"
    echo "   for the same service and expects the installer to report a"
    echo "   validation error."
    echo ""
    echo "🎯 Expected Result:"
    echo "   Installer should report validation error for duplicate endpoints"
    echo ""
    echo "📋 Actual Result:"
    if [ "$test_result" = "0" ]; then
        echo "   ✅ Test PASSED - Installer correctly rejected duplicate endpoints"
    else
        echo "   ❌ Test FAILED - Installer did not properly validate duplicate endpoints"
    fi
    echo ""
}

# Main function
main() {
    print_info "Starting OCP-31378 duplicate service endpoints test..."
    
    # Create install-config with duplicate endpoints
    create_install_config
    
    # Test installer validation
    local test_result=1
    if test_installer_validation; then
        test_result=0
    fi
    
    # Generate test report
    generate_test_report "$test_result"
    
    # Clean up
    cleanup
    
    # Final result
    if [ "$test_result" -eq 0 ]; then
        print_success "OCP-31378 test completed successfully!"
        echo "✅ Installer correctly validates against duplicate service endpoints!"
        exit 0
    else
        print_error "OCP-31378 test failed!"
        echo "❌ Installer did not properly validate duplicate service endpoints."
        exit 1
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
