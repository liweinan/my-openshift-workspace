#!/bin/bash

# OCP-29781 Security Group Verification Script
# Verify security group configuration matches machine CIDRs

set -euo pipefail

# Configuration variables
AWS_REGION="us-east-1"
CLUSTER1_INFRA_ID="weli-test-a-p6fbf"
CLUSTER2_INFRA_ID="weli-test-b-2vgnm"
CLUSTER1_MACHINE_CIDR="10.134.0.0/16"
CLUSTER2_MACHINE_CIDR="10.190.0.0/16"

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

# Verify security groups for a single cluster
verify_cluster_security_groups() {
    local cluster_name=$1
    local infra_id=$2
    local machine_cidr=$3
    
    log_info "Verifying cluster: ${cluster_name} (${infra_id})"
    log_info "Machine CIDR: ${machine_cidr}"
    echo
    
    # Get all security group IDs
    log_info "Retrieving security group IDs..."
    local security_groups
    security_groups=$(aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters "Name=tag:kubernetes.io/cluster/${infra_id},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    if [[ -z "${security_groups}" ]]; then
        log_error "No security groups found for cluster ${cluster_name}"
        return 1
    fi
    
    log_info "Found security groups: ${security_groups}"
    echo
    
    # Check each security group
    for sg_id in $security_groups; do
        verify_security_group "${sg_id}" "${machine_cidr}" "${cluster_name}"
    done
}

# Verify a single security group
verify_security_group() {
    local sg_id=$1
    local expected_cidr=$2
    local cluster_name=$3
    
    log_info "Checking security group: ${sg_id}"
    
    # Get security group details
    local sg_info
    sg_info=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0]')
    
    # Get security group name and description
    local sg_name
    sg_name=$(echo "${sg_info}" | jq -r '.GroupName')
    local sg_description
    sg_description=$(echo "${sg_info}" | jq -r '.Description')
    
    log_info "Security group name: ${sg_name}"
    log_info "Description: ${sg_description}"
    
    # Determine if it's master or worker security group
    local sg_type="unknown"
    if [[ "${sg_description}" == *"controlplane"* ]] || [[ "${sg_name}" == *"controlplane"* ]]; then
        sg_type="master"
    elif [[ "${sg_description}" == *"node"* ]] || [[ "${sg_name}" == *"node"* ]]; then
        sg_type="worker"
    elif [[ "${sg_description}" == *"lb"* ]] || [[ "${sg_name}" == *"lb"* ]]; then
        sg_type="loadbalancer"
    fi
    
    log_info "Security group type: ${sg_type}"
    
    # Check CIDR configuration for key ports
    if [[ "${sg_type}" == "master" ]]; then
        verify_master_ports "${sg_id}" "${expected_cidr}"
    elif [[ "${sg_type}" == "worker" ]]; then
        verify_worker_ports "${sg_id}" "${expected_cidr}"
    elif [[ "${sg_type}" == "loadbalancer" ]]; then
        log_info "Skipping Load Balancer security group validation"
    else
        log_warning "Cannot determine security group type, skipping port validation"
    fi
    
    echo "----------------------------------------"
}

# Verify master ports
verify_master_ports() {
    local sg_id=$1
    local expected_cidr=$2
    
    log_info "Verifying master port configuration..."
    
    # Check 6443/tcp (API Server)
    check_port_cidr "${sg_id}" "tcp" "6443" "6443" "${expected_cidr}" "API Server"
    
    # Check 22623/tcp (Machine Config Server)
    check_port_cidr "${sg_id}" "tcp" "22623" "22623" "${expected_cidr}" "Machine Config Server"
    
    # Check 22/tcp (SSH)
    check_port_cidr "${sg_id}" "tcp" "22" "22" "${expected_cidr}" "SSH"
    
    # Check ICMP
    check_port_cidr "${sg_id}" "icmp" "-1" "-1" "${expected_cidr}" "ICMP"
}

# Verify worker ports
verify_worker_ports() {
    local sg_id=$1
    local expected_cidr=$2
    
    log_info "Verifying worker port configuration..."
    
    # Check 22/tcp (SSH)
    check_port_cidr "${sg_id}" "tcp" "22" "22" "${expected_cidr}" "SSH"
    
    # Check ICMP
    check_port_cidr "${sg_id}" "icmp" "-1" "-1" "${expected_cidr}" "ICMP"
}

# Check CIDR configuration for specific port
check_port_cidr() {
    local sg_id=$1
    local protocol=$2
    local from_port=$3
    local to_port=$4
    local expected_cidr=$5
    local port_name=$6
    
    # Get CIDR configuration for this port
    local actual_cidrs
    actual_cidrs=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query "SecurityGroups[0].IpPermissions[?IpProtocol=='${protocol}' && FromPort==\`${from_port}\` && ToPort==\`${to_port}\`].IpRanges[].CidrIp" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "${actual_cidrs}" ]]; then
        log_warning "  ${port_name} (${protocol}:${from_port}-${to_port}): No CIDR configuration found"
        return
    fi
    
    # Check if expected CIDR is included
    if echo "${actual_cidrs}" | grep -q "${expected_cidr}"; then
        log_success "  ${port_name} (${protocol}:${from_port}-${to_port}): ✅ Contains expected CIDR ${expected_cidr}"
    else
        log_error "  ${port_name} (${protocol}:${from_port}-${to_port}): ❌ Missing expected CIDR ${expected_cidr}"
        log_info "    Actual CIDR: ${actual_cidrs}"
    fi
}

# Display security group details
show_security_group_details() {
    local sg_id=$1
    local cluster_name=$2
    
    log_info "Security group ${sg_id} details:"
    
    aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[]' \
        --output json | jq '[.[] | {IpProtocol:.IpProtocol, FromPort: .FromPort, ToPort: .ToPort, IpRanges:[.IpRanges[].CidrIp]}]'
}

# Main function
main() {
    log_info "Starting OCP-29781 security group verification"
    echo "=========================================="
    
    # Verify cluster 1
    log_info "Verifying cluster 1 security group configuration"
    echo "----------------------------------------"
    verify_cluster_security_groups "Cluster 1" "${CLUSTER1_INFRA_ID}" "${CLUSTER1_MACHINE_CIDR}"
    echo
    
    # Verify cluster 2
    log_info "Verifying cluster 2 security group configuration"
    echo "----------------------------------------"
    verify_cluster_security_groups "Cluster 2" "${CLUSTER2_INFRA_ID}" "${CLUSTER2_MACHINE_CIDR}"
    echo
    
    log_success "Security group verification completed!"
    echo
    log_info "✅ indicates correct configuration"
    log_info "❌ indicates configuration issues"
}

# Run main function
main "$@"