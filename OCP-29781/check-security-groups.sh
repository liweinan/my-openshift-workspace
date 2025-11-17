#!/bin/bash

# Simplified Security Group Verification Script

set -euo pipefail

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
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_cluster_security_groups() {
    local cluster_name=$1
    local infra_id=$2
    local machine_cidr=$3
    
    log_info "=== Checking ${cluster_name} (${infra_id}) ==="
    log_info "Machine CIDR: ${machine_cidr}"
    echo
    
    # Get security group IDs
    local security_groups
    security_groups=$(aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters "Name=tag:kubernetes.io/cluster/${infra_id},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    log_info "Security group IDs: ${security_groups}"
    echo
    
    # Check each security group
    for sg_id in $security_groups; do
        check_single_security_group "${sg_id}" "${machine_cidr}"
    done
    echo
}

check_single_security_group() {
    local sg_id=$1
    local expected_cidr=$2
    
    log_info "Checking security group: ${sg_id}"
    
    # Get security group information
    local sg_info
    sg_info=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --output json)
    
    local sg_name
    sg_name=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].GroupName')
    local sg_description
    sg_description=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].Description')
    
    log_info "Name: ${sg_name}"
    log_info "Description: ${sg_description}"
    
    # Check key ports
    if [[ "${sg_name}" == *"controlplane"* ]]; then
        log_info "Type: Master/Control Plane"
        check_master_ports "${sg_info}" "${expected_cidr}"
    elif [[ "${sg_name}" == *"node"* ]]; then
        log_info "Type: Worker Node"
        check_worker_ports "${sg_info}" "${expected_cidr}"
    elif [[ "${sg_name}" == *"lb"* ]]; then
        log_info "Type: Load Balancer (skipping verification)"
    else
        log_warning "Unknown type"
    fi
    
    echo "----------------------------------------"
}

check_master_ports() {
    local sg_info=$1
    local expected_cidr=$2
    
    log_info "Verifying Master ports:"
    
    # Check 6443/tcp
    check_port_in_sg "${sg_info}" "tcp" "6443" "6443" "${expected_cidr}" "API Server"
    
    # Check 22623/tcp
    check_port_in_sg "${sg_info}" "tcp" "22623" "22623" "${expected_cidr}" "Machine Config Server"
    
    # Check 22/tcp
    check_port_in_sg "${sg_info}" "tcp" "22" "22" "${expected_cidr}" "SSH"
    
    # Check ICMP
    check_port_in_sg "${sg_info}" "icmp" "-1" "-1" "${expected_cidr}" "ICMP"
}

check_worker_ports() {
    local sg_info=$1
    local expected_cidr=$2
    
    log_info "Verifying Worker ports:"
    
    # Check 22/tcp
    check_port_in_sg "${sg_info}" "tcp" "22" "22" "${expected_cidr}" "SSH"
    
    # Check ICMP
    check_port_in_sg "${sg_info}" "icmp" "-1" "-1" "${expected_cidr}" "ICMP"
}

check_port_in_sg() {
    local sg_info=$1
    local protocol=$2
    local from_port=$3
    local to_port=$4
    local expected_cidr=$5
    local port_name=$6
    
    # Find matching port rules
    local matching_rules
    matching_rules=$(echo "${sg_info}" | jq -r --arg protocol "${protocol}" --arg from_port "${from_port}" --arg to_port "${to_port}" \
        '.SecurityGroups[0].IpPermissions[] | 
        select(.IpProtocol == $protocol and .FromPort == ($from_port | tonumber) and .ToPort == ($to_port | tonumber)) | 
        .IpRanges[].CidrIp')
    
    if [[ -z "${matching_rules}" ]]; then
        log_warning "  ${port_name} (${protocol}:${from_port}-${to_port}): No rules found"
        return
    fi
    
    # Check if expected CIDR is included
    if echo "${matching_rules}" | grep -q "${expected_cidr}"; then
        log_success "  ${port_name} (${protocol}:${from_port}-${to_port}): ✅ Contains ${expected_cidr}"
    else
        log_error "  ${port_name} (${protocol}:${from_port}-${to_port}): ❌ Missing ${expected_cidr}"
        log_info "    Actual CIDR: ${matching_rules}"
    fi
}

# Main function
main() {
    log_info "Starting security group verification"
    echo "=========================================="
    
    check_cluster_security_groups "Cluster 1" "${CLUSTER1_INFRA_ID}" "${CLUSTER1_MACHINE_CIDR}"
    check_cluster_security_groups "Cluster 2" "${CLUSTER2_INFRA_ID}" "${CLUSTER2_MACHINE_CIDR}"
    
    log_success "Security group verification completed!"
}

main "$@"