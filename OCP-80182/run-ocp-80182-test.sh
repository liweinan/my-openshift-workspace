#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# OCP-80182 Test Script
# Install a cluster in a VPC with only public subnets provided

# Configuration
STACK_NAME="ocp-80182-vpc"
TEMPLATE_FILE="../tools/vpc-template-public-only.yaml"
REGION="us-east-1"
AZ_COUNT=3
CLUSTER_NAME="ocp-80182-test"
BASE_DOMAIN="example.com"

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

# Function to create VPC
create_vpc() {
    log_info "Creating VPC with public-only subnets..."
    
    # Check if stack already exists
    if aws cloudformation describe-stacks --stack-name ${STACK_NAME} &> /dev/null; then
        log_warning "Stack ${STACK_NAME} already exists. Deleting it first..."
        aws cloudformation delete-stack --stack-name ${STACK_NAME}
        aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}
    fi
    
    # Create VPC stack
    ../tools/create-vpc-stack.sh \
        --stack-name ${STACK_NAME} \
        --template-file ${TEMPLATE_FILE} \
        --az-count ${AZ_COUNT} \
        --region ${REGION}
    
    if [ $? -eq 0 ]; then
        log_success "VPC created successfully"
    else
        log_error "Failed to create VPC"
        exit 1
    fi
}

# Function to verify VPC configuration
verify_vpc() {
    log_info "Verifying VPC configuration..."
    
    # Get VPC ID
    VPC_ID=$(aws cloudformation describe-stacks \
        --stack-name ${STACK_NAME} \
        --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
        --output text)
    
    if [ -z "${VPC_ID}" ]; then
        log_error "Failed to get VPC ID"
        exit 1
    fi
    
    log_info "VPC ID: ${VPC_ID}"
    
    # Check subnets
    log_info "Checking subnets..."
    aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[*].[SubnetId,MapPublicIpOnLaunch,AvailabilityZone]' \
        --output table
    
    # Check for NAT gateways (should be empty)
    log_info "Checking for NAT gateways (should be empty)..."
    NAT_COUNT=$(aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=${VPC_ID}" \
        --query 'NatGateways | length(@)')
    
    if [ "${NAT_COUNT}" -gt 0 ]; then
        log_error "Found ${NAT_COUNT} NAT gateways, but should be 0 for public-only setup"
        exit 1
    fi
    
    log_success "VPC configuration verified - no NAT gateways found"
}

# Function to get subnet IDs
get_subnet_ids() {
    log_info "Getting subnet IDs..."
    
    SUBNET_IDS=$(aws cloudformation describe-stacks \
        --stack-name ${STACK_NAME} \
        --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
        --output text)
    
    if [ -z "${SUBNET_IDS}" ]; then
        log_error "Failed to get subnet IDs"
        exit 1
    fi
    
    log_info "Subnet IDs: ${SUBNET_IDS}"
}

# Function to create install-config.yaml
create_install_config() {
    log_info "Creating install-config.yaml..."
    
    # Set environment variable
    export OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY=true
    log_info "Set OPENSHIFT_INSTALL_AWS_PUBLIC_ONLY=true"
    
    # Create install-config.yaml
    cat > install-config.yaml << EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
platform:
  aws:
    region: ${REGION}
    subnets:
$(echo ${SUBNET_IDS} | tr ',' '\n' | sed 's/^/      - /')
pullSecret: '{"auths":{"quay.io":{"auth":"$(echo -n 'username:password' | base64)"}}}'
sshKey: |
  ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7vbqajDhA...
EOF
    
    log_success "install-config.yaml created"
    log_warning "Please update pullSecret and sshKey in install-config.yaml before proceeding"
}

# Function to install cluster
install_cluster() {
    log_info "Installing OpenShift cluster..."
    
    # Check if install-config.yaml exists
    if [ ! -f "install-config.yaml" ]; then
        log_error "install-config.yaml not found"
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

# Function to cleanup
cleanup() {
    log_info "Cleaning up resources..."
    
    # Destroy cluster if it exists
    if [ -f "auth/kubeconfig" ]; then
        log_info "Destroying cluster..."
        openshift-install destroy cluster --log-level=info
    fi
    
    # Delete VPC stack
    log_info "Deleting VPC stack..."
    aws cloudformation delete-stack --stack-name ${STACK_NAME}
    aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}
    
    log_success "Cleanup completed"
}

# Main function
main() {
    log_info "Starting OCP-80182 test..."
    
    case "${1:-run}" in
        "run")
            check_prerequisites
            create_vpc
            verify_vpc
            get_subnet_ids
            create_install_config
            log_warning "Please update pullSecret and sshKey in install-config.yaml, then run: $0 install"
            ;;
        "install")
            install_cluster
            verify_cluster
            log_success "OCP-80182 test completed successfully!"
            ;;
        "cleanup")
            cleanup
            ;;
        "verify")
            verify_vpc
            ;;
        *)
            echo "Usage: $0 {run|install|cleanup|verify}"
            echo "  run     - Create VPC and prepare install-config.yaml"
            echo "  install - Install OpenShift cluster"
            echo "  cleanup - Clean up all resources"
            echo "  verify  - Verify VPC configuration only"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
