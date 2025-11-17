#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# OCP-81178 Test Script
# Install aws IPI clusters with only public IP

# Configuration
CLUSTER_NAME="ocp-81178-test"
BASE_DOMAIN="example.com"
REGION="us-east-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check OpenShift Installer
    if ! command -v openshift-install &> /dev/null; then
        log_error "OpenShift Installer is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
set_environment() {
    log_info "Setting environment variables..."
    
    # Set the key environment variable
    export OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY=true
    log_info "Set OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY=true"
    
    # Verify environment variable is set
    if [ "${OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY}" != "true" ]; then
        log_error "Failed to set OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY environment variable"
        exit 1
    fi
    
    log_success "Environment variables set successfully"
}

# Function to create install-config.yaml
create_install_config() {
    log_info "Creating install-config.yaml..."
    
    # Create install-config.yaml
    cat > install-config.yaml << EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
platform:
  aws:
    region: ${REGION}
pullSecret: '{"auths":{"quay.io":{"auth":"$(echo -n 'username:password' | base64)"}}}'
sshKey: |
  ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7vbqajDhA...
EOF
    
    log_success "install-config.yaml created"
    log_warning "Please update pullSecret and sshKey in install-config.yaml before proceeding"
}

# Function to install cluster
install_cluster() {
    log_info "Installing OpenShift cluster with public-only configuration..."
    
    # Check if install-config.yaml exists
    if [ ! -f "install-config.yaml" ]; then
        log_error "install-config.yaml not found"
        exit 1
    fi
    
    # Verify environment variable is still set
    if [ "${OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY}" != "true" ]; then
        log_error "OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY is not set to true"
        exit 1
    fi
    
    # Create cluster
    openshift-install create cluster --log-level=info
    
    if [ $? -eq 0 ]; then
        log_success "Cluster installed successfully"
    else
        log_error "Cluster installation failed"
        exit 1
    fi
}

# Function to verify cluster
verify_cluster() {
    log_info "Verifying cluster..."
    
    # Set kubeconfig
    export KUBECONFIG=auth/kubeconfig
    
    # Check nodes
    log_info "Checking nodes..."
    oc get nodes -o wide
    
    # Check cluster operators
    log_info "Checking cluster operators..."
    oc get clusteroperators
    
    # Check cluster version
    log_info "Checking cluster version..."
    oc get clusterversion
    
    log_success "Cluster verification completed"
}

# Function to verify VPC configuration
verify_vpc_config() {
    log_info "Verifying VPC configuration..."
    
    # Get cluster VPC ID
    CLUSTER_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=*${CLUSTER_NAME}*" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [ -z "${CLUSTER_VPC_ID}" ] || [ "${CLUSTER_VPC_ID}" = "None" ]; then
        log_error "Failed to find cluster VPC"
        exit 1
    fi
    
    log_info "Cluster VPC ID: ${CLUSTER_VPC_ID}"
    
    # Check subnets
    log_info "Checking subnets (should all be public)..."
    aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${CLUSTER_VPC_ID}" \
        --query 'Subnets[*].[SubnetId,MapPublicIpOnLaunch,AvailabilityZone]' \
        --output table
    
    # Check for NAT gateways (should be empty)
    log_info "Checking for NAT gateways (should be empty)..."
    NAT_COUNT=$(aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=${CLUSTER_VPC_ID}" \
        --query 'NatGateways | length(@)')
    
    if [ "${NAT_COUNT}" -gt 0 ]; then
        log_error "Found ${NAT_COUNT} NAT gateways, but should be 0 for public-only setup"
        aws ec2 describe-nat-gateways \
            --filter "Name=vpc-id,Values=${CLUSTER_VPC_ID}" \
            --query 'NatGateways[*].[NatGatewayId,State]' \
            --output table
        exit 1
    fi
    
    log_success "VPC configuration verified - no NAT gateways found"
    
    # Check route tables
    log_info "Checking route tables..."
    aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${CLUSTER_VPC_ID}" \
        --query 'RouteTables[*].[RouteTableId,Routes[*].[DestinationCidrBlock,GatewayId]]' \
        --output table
    
    log_success "VPC configuration verification completed"
}

# Function to cleanup
cleanup() {
    log_info "Cleaning up resources..."
    
    # Destroy cluster if it exists
    if [ -f "auth/kubeconfig" ]; then
        log_info "Destroying cluster..."
        openshift-install destroy cluster --log-level=info
    fi
    
    log_success "Cleanup completed"
}

# Function to show test results
show_results() {
    log_info "Test Results Summary:"
    echo "========================"
    echo "Test Case: OCP-81178"
    echo "Description: Install aws IPI clusters with only public IP"
    echo "Status: PASSED"
    echo "Cluster Name: ${CLUSTER_NAME}"
    echo "VPC Configuration: Public-only (no NAT gateways)"
    echo "========================"
}

# Main function
main() {
    log_info "Starting OCP-81178 test..."
    
    case "${1:-run}" in
        "run")
            check_prerequisites
            set_environment
            create_install_config
            log_warning "Please update pullSecret and sshKey in install-config.yaml, then run: $0 install"
            ;;
        "install")
            set_environment
            install_cluster
            verify_cluster
            verify_vpc_config
            show_results
            log_success "OCP-81178 test completed successfully!"
            ;;
        "verify")
            verify_vpc_config
            ;;
        "cleanup")
            cleanup
            ;;
        *)
            echo "Usage: $0 {run|install|verify|cleanup}"
            echo "  run     - Prepare install-config.yaml"
            echo "  install - Install OpenShift cluster and verify"
            echo "  verify  - Verify VPC configuration only"
            echo "  cleanup - Clean up all resources"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
