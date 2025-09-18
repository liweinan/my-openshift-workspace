#!/bin/bash

# OpenShift Image Query Script
# Query OPENSHIFT_INSTALL_OS_IMAGE_OVERRIDE and OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE

set -euo pipefail

# Color definitions
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

# Show help information
show_help() {
    cat << EOF
OpenShift Image Query Script

Usage:
    $0 [options]

Options:
    -v, --version <version>     OpenShift version (e.g., 4.15.0, 4.16.0)
    -r, --region <region>       AWS region (default: us-east-2)
    --ami <ami-id>              Specify RHCOS AMI ID directly
    --release <release-image>   Specify release image directly
    -h, --help                  Show this help information

Examples:
    # Query for specific version
    $0 --version 4.15.0

    # Query for specific region
    $0 --version 4.16.0 --region us-west-2

    # Use specific AMI and release image
    $0 --ami ami-05fbf3150ef4bc38f --release registry.svc.ci.openshift.org/ocp/release:4.0.0-0.nightly-2019-01-25-205123

EOF
}

# Default parameters
OPENSHIFT_VERSION=""
AWS_REGION="us-east-2"
AMI_ID=""
RELEASE_IMAGE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            OPENSHIFT_VERSION="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        --ami)
            AMI_ID="$2"
            shift 2
            ;;
        --release)
            RELEASE_IMAGE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

# Query RHCOS AMI for specific version
query_rhcos_ami() {
    local version="$1"
    local region="$2"
    
    print_info "Querying RHCOS AMI for version $version in region $region..."
    
    # Try to get from RHCOS releases
    local rhcos_url="https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com/storage/releases/rhcos-${version}/x86_64/meta.json"
    local rhcos_info=$(curl -s "$rhcos_url" 2>/dev/null || echo "")
    
    if [ -n "$rhcos_info" ]; then
        local ami_id=$(echo "$rhcos_info" | jq -r ".amis[\"$region\"].hvm" 2>/dev/null || echo "")
        if [ -n "$ami_id" ] && [ "$ami_id" != "null" ]; then
            echo "$ami_id"
            return 0
        fi
    fi
    
    # Fallback: try AWS CLI
    print_warning "Failed to get AMI from RHCOS releases, trying AWS CLI..."
    
    local ami_id=$(aws ec2 describe-images \
        --region "$region" \
        --owners 125523088429 \
        --filters "Name=name,Values=RHEL-*" "Name=architecture,Values=x86_64" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ami_id" ] && [ "$ami_id" != "None" ]; then
        echo "$ami_id"
        return 0
    fi
    
    print_error "Failed to find RHCOS AMI for version $version in region $region"
    return 1
}

# Query release image for specific version
query_release_image() {
    local version="$1"
    
    print_info "Querying release image for version $version..."
    
    # Try to get from release API
    local release_url="https://openshift-release.svc.ci.openshift.org/api/v1/releasestream/$version/latest"
    local release_info=$(curl -s "$release_url" 2>/dev/null || echo "")
    
    if [ -n "$release_info" ]; then
        local pullspec=$(echo "$release_info" | jq -r '.pullSpec' 2>/dev/null || echo "")
        if [ -n "$pullspec" ] && [ "$pullspec" != "null" ]; then
            echo "$pullspec"
            return 0
        fi
    fi
    
    # Fallback: construct standard pullspec
    local pullspec="registry.ci.openshift.org/ocp/release:$version"
    print_warning "Using fallback pullspec: $pullspec"
    echo "$pullspec"
}

# Main function
main() {
    print_info "OpenShift Image Environment Setup"
    
    # Check if we have specific AMI and release image
    if [ -n "$AMI_ID" ] && [ -n "$RELEASE_IMAGE" ]; then
        print_info "Using provided AMI and release image"
    elif [ -n "$OPENSHIFT_VERSION" ]; then
        # Query for the version
        AMI_ID=$(query_rhcos_ami "$OPENSHIFT_VERSION" "$AWS_REGION")
        if [ $? -ne 0 ]; then
            exit 1
        fi
        
        RELEASE_IMAGE=$(query_release_image "$OPENSHIFT_VERSION")
        if [ $? -ne 0 ]; then
            exit 1
        fi
    else
        print_error "Must specify either --version or both --ami and --release"
        show_help
        exit 1
    fi
    
    print_success "Found images:"
    print_info "  RHCOS AMI: $AMI_ID"
    print_info "  Release Image: $RELEASE_IMAGE"
    
    # Display the variables
    echo ""
    print_info "Environment variables:"
    echo "export OPENSHIFT_INSTALL_OS_IMAGE_OVERRIDE=$AMI_ID"
    echo "export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=$RELEASE_IMAGE"
    
    if [ -n "$OPENSHIFT_VERSION" ]; then
        echo "export OPENSHIFT_VERSION=$OPENSHIFT_VERSION"
    fi
    
    echo "export AWS_REGION=$AWS_REGION"
    
    print_success "Query completed!"
}

# Execute main function
main "$@"
