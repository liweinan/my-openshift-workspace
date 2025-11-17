#!/bin/bash

# OCP-29781 Setup Verification Script
# Verify VPC, subnet tags, and configuration are correct

set -euo pipefail

# Configuration variables
VPC_STACK_NAME="weli-test-vpc"
CLUSTER1_NAME="weli-test-a"
CLUSTER2_NAME="weli-test-b"
AWS_REGION="us-east-1"
VPC_ID="vpc-06230a0fab9777f55"

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

# Verify VPC status
verify_vpc() {
    log_info "Verifying VPC status..."
    
    if aws ec2 describe-vpcs --region "${AWS_REGION}" --vpc-ids "${VPC_ID}" &> /dev/null; then
        log_success "VPC ${VPC_ID} exists and is accessible"
        
        # Display VPC information
        aws ec2 describe-vpcs --region "${AWS_REGION}" --vpc-ids "${VPC_ID}" \
            --query 'Vpcs[0].{VpcId:VpcId,State:State,CidrBlock:CidrBlock}' \
            --output table
    else
        log_error "VPC ${VPC_ID} does not exist or is not accessible"
        return 1
    fi
}

# Verify subnet tags
verify_subnet_tags() {
    log_info "Verifying subnet tags..."
    
    # Get all subnets
    SUBNETS=$(aws ec2 describe-subnets \
        --region "${AWS_REGION}" \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[].SubnetId' \
        --output text)
    
    log_info "Checking subnet tags..."
    for subnet in $SUBNETS; do
        log_info "Checking subnet: ${subnet}"
        
        # Check cluster 1 tag
        CLUSTER1_TAG=$(aws ec2 describe-tags \
            --region "${AWS_REGION}" \
            --filters "Name=resource-id,Values=${subnet}" "Name=key,Values=kubernetes.io/cluster/${CLUSTER1_NAME}" \
            --query 'Tags[0].Value' \
            --output text 2>/dev/null || echo "None")
        
        # Check cluster 2 tag
        CLUSTER2_TAG=$(aws ec2 describe-tags \
            --region "${AWS_REGION}" \
            --filters "Name=resource-id,Values=${subnet}" "Name=key,Values=kubernetes.io/cluster/${CLUSTER2_NAME}" \
            --query 'Tags[0].Value' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "${CLUSTER1_TAG}" == "shared" ]]; then
            log_success "  ✓ ${CLUSTER1_NAME} tag: ${CLUSTER1_TAG}"
        else
            log_warning "  ⚠ ${CLUSTER1_NAME} tag: ${CLUSTER1_TAG}"
        fi
        
        if [[ "${CLUSTER2_TAG}" == "shared" ]]; then
            log_success "  ✓ ${CLUSTER2_NAME} tag: ${CLUSTER2_TAG}"
        else
            log_warning "  ⚠ ${CLUSTER2_NAME} tag: ${CLUSTER2_TAG}"
        fi
    done
}

# Verify subnet CIDR distribution
verify_subnet_cidrs() {
    log_info "Verifying subnet CIDR distribution..."
    
    aws ec2 describe-subnets \
        --region "${AWS_REGION}" \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[*].{SubnetId:SubnetId,CidrBlock:CidrBlock,AvailabilityZone:AvailabilityZone,State:State}' \
        --output table
}

# Verify install-config files
verify_install_configs() {
    log_info "Verifying install-config files..."
    
    # Check if files exist
    if [[ -f "install-config-cluster1.yaml" ]]; then
        log_success "install-config-cluster1.yaml exists"
    else
        log_error "install-config-cluster1.yaml does not exist"
        return 1
    fi
    
    if [[ -f "install-config-cluster2.yaml" ]]; then
        log_success "install-config-cluster2.yaml exists"
    else
        log_error "install-config-cluster2.yaml does not exist"
        return 1
    fi
    
    # Check if subnet IDs are correct
    log_info "Verifying subnet ID configuration..."
    
    # Cluster 1 subnets
    CLUSTER1_PRIVATE_SUBNET=$(grep -B 1 "role: private" install-config-cluster1.yaml | grep "id:" | awk '{print $2}')
    CLUSTER1_PUBLIC_SUBNET=$(grep -B 1 "role: public" install-config-cluster1.yaml | grep "id:" | awk '{print $2}')
    
    log_info "Cluster 1 subnet configuration:"
    log_info "  Private subnet: ${CLUSTER1_PRIVATE_SUBNET}"
    log_info "  Public subnet: ${CLUSTER1_PUBLIC_SUBNET}"
    
    # Cluster 2 subnets
    CLUSTER2_PRIVATE_SUBNET=$(grep -B 1 "role: private" install-config-cluster2.yaml | grep "id:" | awk '{print $2}')
    CLUSTER2_PUBLIC_SUBNET=$(grep -B 1 "role: public" install-config-cluster2.yaml | grep "id:" | awk '{print $2}')
    
    log_info "Cluster 2 subnet configuration:"
    log_info "  Private subnet: ${CLUSTER2_PRIVATE_SUBNET}"
    log_info "  Public subnet: ${CLUSTER2_PUBLIC_SUBNET}"
}

# Verify CIDR isolation
verify_cidr_isolation() {
    log_info "Verifying CIDR isolation..."
    
    # Cluster 1 uses 10.134.0.0/16
    CLUSTER1_CIDR=$(grep "cidr:" install-config-cluster1.yaml | grep "10.134" | awk '{print $2}')
    log_info "Cluster 1 machineNetwork CIDR: ${CLUSTER1_CIDR}"
    
    # Cluster 2 uses 10.190.0.0/16
    CLUSTER2_CIDR=$(grep "cidr:" install-config-cluster2.yaml | grep "10.190" | awk '{print $2}')
    log_info "Cluster 2 machineNetwork CIDR: ${CLUSTER2_CIDR}"
    
    if [[ "${CLUSTER1_CIDR}" == "10.134.0.0/16" ]] && [[ "${CLUSTER2_CIDR}" == "10.190.0.0/16" ]]; then
        log_success "CIDR isolation configuration is correct"
    else
        log_error "CIDR isolation configuration is incorrect"
        return 1
    fi
}

# Main function
main() {
    log_info "Starting OCP-29781 setup verification"
    echo
    
    verify_vpc
    echo
    
    verify_subnet_tags
    echo
    
    verify_subnet_cidrs
    echo
    
    verify_install_configs
    echo
    
    verify_cidr_isolation
    echo
    
    log_success "OCP-29781 setup verification completed!"
    echo
    log_info "Next step: run './run-ocp29781-test.sh' to start full testing"
}

# Run main function
main "$@"