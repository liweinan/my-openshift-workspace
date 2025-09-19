#!/bin/bash

# OCP-29064 KMS Configuration Verification Script
# Verifies KMS key configuration in install-config.yaml

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
OCP-29064 KMS Configuration Verification Script

This script verifies KMS key configuration in OpenShift install-config.yaml.
It checks for KMS key ARN configuration and validates region compatibility.

Usage: $0 [OPTIONS]

Options:
    -w, --work-dir DIR        Working directory containing install-config.yaml (default: .)
    -v, --verbose             Verbose output
    -h, --help                Show this help message

Verification Checks:
    1. KMS key ARN presence in install-config.yaml
    2. KMS key region vs cluster region compatibility
    3. KMS key format validation
    4. Control plane KMS configuration

Examples:
    $0                                    # Check current directory
    $0 -w /path/to/install/config        # Check specific directory
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

# Verify install-config.yaml exists
check_install_config() {
    if [[ ! -f "install-config.yaml" ]]; then
        print_error "install-config.yaml not found in current directory"
        return 1
    fi
    return 0
}

# Extract KMS key ARN from install-config.yaml
extract_kms_key_arn() {
    local kms_arn
    kms_arn=$(yq eval '.controlPlane.platform.aws.rootVolume.kmsKeyARN' install-config.yaml 2>/dev/null || echo "")
    
    if [[ -z "$kms_arn" ]] || [[ "$kms_arn" == "null" ]]; then
        print_warning "No KMS key ARN found in install-config.yaml"
        return 1
    fi
    
    echo "$kms_arn"
    return 0
}

# Extract cluster region from install-config.yaml
extract_cluster_region() {
    local cluster_region
    cluster_region=$(yq eval '.platform.aws.region' install-config.yaml 2>/dev/null || echo "")
    
    if [[ -z "$cluster_region" ]] || [[ "$cluster_region" == "null" ]]; then
        print_error "No cluster region found in install-config.yaml"
        return 1
    fi
    
    echo "$cluster_region"
    return 0
}

# Extract KMS key region from ARN
extract_kms_region() {
    local kms_arn="$1"
    local kms_region
    
    # Extract region from ARN: arn:aws:kms:region:account:key/key-id
    kms_region=$(echo "$kms_arn" | sed -n 's/arn:aws:kms:\([^:]*\):.*/\1/p')
    
    if [[ -z "$kms_region" ]]; then
        print_error "Could not extract region from KMS ARN: $kms_arn"
        return 1
    fi
    
    echo "$kms_region"
    return 0
}

# Validate KMS ARN format
validate_kms_arn_format() {
    local kms_arn="$1"
    
    # Check if ARN matches expected format
    if [[ "$kms_arn" =~ ^arn:aws:kms:[a-z0-9-]+:[0-9]+:key/[a-f0-9-]+$ ]]; then
        print_success "✅ KMS ARN format is valid"
        return 0
    else
        print_error "❌ KMS ARN format is invalid: $kms_arn"
        return 1
    fi
}

# Check KMS key region compatibility
check_region_compatibility() {
    local kms_region="$1"
    local cluster_region="$2"
    
    if [[ "$kms_region" == "$cluster_region" ]]; then
        print_success "✅ KMS key region ($kms_region) matches cluster region ($cluster_region)"
        return 0
    else
        print_warning "⚠️  KMS key region ($kms_region) does NOT match cluster region ($cluster_region)"
        print_warning "This configuration will cause cluster creation to fail"
        return 1
    fi
}

# Verify KMS key exists in AWS
verify_kms_key_exists() {
    local kms_arn="$1"
    local kms_region="$2"
    
    print_info "Verifying KMS key exists in AWS..."
    
    # Extract key ID from ARN
    local key_id
    key_id=$(echo "$kms_arn" | sed -n 's/.*:key\/\(.*\)/\1/p')
    
    if [[ -z "$key_id" ]]; then
        print_error "Could not extract key ID from ARN: $kms_arn"
        return 1
    fi
    
    # Check if key exists
    if aws kms describe-key \
        --region "$kms_region" \
        --key-id "$key_id" \
        --output json &>/dev/null; then
        print_success "✅ KMS key exists in AWS"
        
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "KMS key details:"
            aws kms describe-key \
                --region "$kms_region" \
                --key-id "$key_id" \
                --output json | jq .
        fi
        return 0
    else
        print_error "❌ KMS key does not exist in AWS or is not accessible"
        return 1
    fi
}

# Check control plane configuration
check_control_plane_config() {
    print_info "Checking control plane KMS configuration..."
    
    # Check if controlPlane section exists
    local control_plane_exists
    control_plane_exists=$(yq eval 'has("controlPlane")' install-config.yaml 2>/dev/null || echo "false")
    
    if [[ "$control_plane_exists" != "true" ]]; then
        print_error "❌ controlPlane section not found in install-config.yaml"
        return 1
    fi
    
    # Check if platform.aws section exists in controlPlane
    local aws_platform_exists
    aws_platform_exists=$(yq eval '.controlPlane | has("platform")' install-config.yaml 2>/dev/null || echo "false")
    
    if [[ "$aws_platform_exists" != "true" ]]; then
        print_error "❌ controlPlane.platform section not found"
        return 1
    fi
    
    # Check if rootVolume section exists
    local root_volume_exists
    root_volume_exists=$(yq eval '.controlPlane.platform.aws | has("rootVolume")' install-config.yaml 2>/dev/null || echo "false")
    
    if [[ "$root_volume_exists" != "true" ]]; then
        print_error "❌ controlPlane.platform.aws.rootVolume section not found"
        return 1
    fi
    
    # Check if kmsKeyARN exists
    local kms_key_arn_exists
    kms_key_arn_exists=$(yq eval '.controlPlane.platform.aws.rootVolume | has("kmsKeyARN")' install-config.yaml 2>/dev/null || echo "false")
    
    if [[ "$kms_key_arn_exists" != "true" ]]; then
        print_error "❌ kmsKeyARN not found in controlPlane.platform.aws.rootVolume"
        return 1
    fi
    
    print_success "✅ Control plane KMS configuration structure is correct"
    return 0
}

# Generate verification report
generate_report() {
    local kms_arn="$1"
    local kms_region="$2"
    local cluster_region="$3"
    local format_valid=$4
    local region_compatible=$5
    local key_exists=$6
    local config_valid=$7
    
    print_info "Generating verification report..."
    
    cat << EOF

==========================================
OCP-29064 KMS Configuration Verification Report
==========================================

Test Case: [ipi-on-aws] IPI Installer with KMS configuration [invalid key]

Configuration Details:
- KMS Key ARN: $kms_arn
- KMS Key Region: $kms_region
- Cluster Region: $cluster_region

Verification Results:
EOF

    if [[ $format_valid -eq 0 ]]; then
        echo "✅ KMS ARN Format: Valid"
    else
        echo "❌ KMS ARN Format: Invalid"
    fi
    
    if [[ $region_compatible -eq 0 ]]; then
        echo "✅ Region Compatibility: Compatible"
    else
        echo "❌ Region Compatibility: Incompatible (Expected for this test)"
    fi
    
    if [[ $key_exists -eq 0 ]]; then
        echo "✅ KMS Key Exists: Yes"
    else
        echo "❌ KMS Key Exists: No"
    fi
    
    if [[ $config_valid -eq 0 ]]; then
        echo "✅ Configuration Structure: Valid"
    else
        echo "❌ Configuration Structure: Invalid"
    fi
    
    echo ""
    
    if [[ $format_valid -eq 0 ]] && [[ $key_exists -eq 0 ]] && [[ $config_valid -eq 0 ]]; then
        if [[ $region_compatible -eq 1 ]]; then
            echo "🎉 Overall Result: PASS - Invalid KMS configuration detected"
            echo ""
            echo "This configuration should cause cluster creation to fail due to:"
            echo "❌ KMS key region ($kms_region) does not match cluster region ($cluster_region)"
            return 0
        else
            echo "⚠️  Overall Result: WARNING - Valid KMS configuration"
            echo ""
            echo "This configuration should work for cluster creation."
            echo "For OCP-29064 test, you need an invalid KMS configuration."
            return 1
        fi
    else
        echo "💥 Overall Result: FAIL - Configuration issues detected"
        echo ""
        echo "Issues Found:"
        [[ $format_valid -ne 0 ]] && echo "❌ KMS ARN format issue"
        [[ $key_exists -ne 0 ]] && echo "❌ KMS key does not exist"
        [[ $config_valid -ne 0 ]] && echo "❌ Configuration structure issue"
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
    
    print_info "Starting OCP-29064 KMS configuration verification..."
    print_info "Work directory: $(pwd)"
    
    # Check prerequisites
    check_jq
    
    # Check if yq is available
    if ! command -v yq &> /dev/null; then
        print_error "yq is required but not installed. Please install yq first."
        exit 1
    fi
    
    # Verify install-config.yaml exists
    if ! check_install_config; then
        exit 1
    fi
    
    # Extract configuration
    local kms_arn
    kms_arn=$(extract_kms_key_arn)
    if [[ $? -ne 0 ]]; then
        print_error "No KMS key ARN found in install-config.yaml"
        exit 1
    fi
    
    local cluster_region
    cluster_region=$(extract_cluster_region)
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    
    local kms_region
    kms_region=$(extract_kms_region "$kms_arn")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    
    print_info "KMS Key ARN: $kms_arn"
    print_info "KMS Key Region: $kms_region"
    print_info "Cluster Region: $cluster_region"
    
    # Perform verifications
    local format_valid=0
    local region_compatible=0
    local key_exists=0
    local config_valid=0
    
    validate_kms_arn_format "$kms_arn" || format_valid=1
    check_region_compatibility "$kms_region" "$cluster_region" || region_compatible=1
    verify_kms_key_exists "$kms_arn" "$kms_region" || key_exists=1
    check_control_plane_config || config_valid=1
    
    # Generate report
    generate_report "$kms_arn" "$kms_region" "$cluster_region" \
                   $format_valid $region_compatible $key_exists $config_valid
    local overall_result=$?
    
    exit $overall_result
}

# Run main function
main "$@"
