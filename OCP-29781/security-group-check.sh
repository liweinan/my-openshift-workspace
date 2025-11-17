#!/bin/bash

# OCP-29781 Security Group Check Script
# Verify security group rules match machine CIDR

set -euo pipefail

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

# Get cluster infraID
get_infra_id() {
    local cluster_dir="$1"
    local metadata_file="${cluster_dir}/metadata.json"
    
    if [[ ! -f "${metadata_file}" ]]; then
        log_error "Metadata file not found: ${metadata_file}"
        return 1
    fi
    
    local infra_id
    infra_id=$(jq -r '.infraID' "${metadata_file}")
    
    if [[ "${infra_id}" == "null" || -z "${infra_id}" ]]; then
        log_error "Cannot get infraID from metadata file"
        return 1
    fi
    
    echo "${infra_id}"
}

# Get security group IDs for cluster
get_security_groups() {
    local infra_id="$1"
    local region="${AWS_REGION:-us-east-2}"
    
    log_info "Retrieving security groups for cluster ${infra_id}..."
    
    local sg_ids
    sg_ids=$(aws ec2 describe-instances \
        --region "${region}" \
        --filters "Name=tag:kubernetes.io/cluster/${infra_id},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    if [[ -z "${sg_ids}" ]]; then
        log_error "No security groups found for cluster ${infra_id}"
        return 1
    fi
    
    echo "${sg_ids}"
}

# Check security group rules
check_security_group_rules() {
    local sg_id="$1"
    local expected_cidr="$2"
    local region="${AWS_REGION:-us-east-2}"
    
    log_info "Checking rules for security group ${sg_id}..."
    
    # Get security group details
    local sg_info
    sg_info=$(aws ec2 describe-security-groups \
        --region "${region}" \
        --group-ids "${sg_id}" \
        --output json)
    
    # Check ports needed for master nodes
    local master_ports=(
        "6443:tcp"
        "22623:tcp"
        "22:tcp"
        "-1:icmp"
    )
    
    # Check ports needed for worker nodes
    local worker_ports=(
        "22:tcp"
        "-1:icmp"
    )
    
    local all_checks_passed=true
    
    # Check all port rules
    for port_info in "${master_ports[@]}" "${worker_ports[@]}"; do
        local port=$(echo "${port_info}" | cut -d: -f1)
        local protocol=$(echo "${port_info}" | cut -d: -f2)
        
        # Check if rule exists and CIDR matches
        local rule_exists
        rule_exists=$(echo "${sg_info}" | jq -r --arg port "${port}" --arg protocol "${protocol}" --arg cidr "${expected_cidr}" \
            '.SecurityGroups[].IpPermissions[] | 
            select(.IpProtocol == $protocol and .FromPort == ($port | tonumber) and .ToPort == ($port | tonumber)) |
            .IpRanges[] | select(.CidrIp == $cidr) | .CidrIp')
        
        if [[ -n "${rule_exists}" ]]; then
            log_success "Port ${port}/${protocol} rule is correct, CIDR: ${expected_cidr}"
        else
            log_error "Port ${port}/${protocol} rule is missing or CIDR doesn't match, expected: ${expected_cidr}"
            all_checks_passed=false
        fi
    done
    
    if [[ "${all_checks_passed}" == "true" ]]; then
        log_success "All rules for security group ${sg_id} passed check"
        return 0
    else
        log_error "Security group ${sg_id} rule check failed"
        return 1
    fi
}

# Display security group details
show_security_group_details() {
    local sg_id="$1"
    local region="${AWS_REGION:-us-east-2}"
    
    log_info "Details for security group ${sg_id}:"
    
    aws ec2 describe-security-groups \
        --region "${region}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[].IpPermissions[] | {IpProtocol:.IpProtocol, FromPort:.FromPort, ToPort:.ToPort, IpRanges:[.IpRanges[].CidrIp]}' \
        --output table
}

# Check cluster security groups
check_cluster_security_groups() {
    local cluster_dir="$1"
    local expected_cidr="$2"
    
    log_info "Checking security groups for cluster ${cluster_dir}..."
    
    # Get infraID
    local infra_id
    infra_id=$(get_infra_id "${cluster_dir}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    log_info "Cluster infraID: ${infra_id}"
    
    # Get security group ID list
    local sg_ids
    sg_ids=$(get_security_groups "${infra_id}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    log_info "Found security groups: ${sg_ids}"
    
    local all_checks_passed=true
    
    # Check each security group
    while IFS= read -r sg_id; do
        if [[ -n "${sg_id}" ]]; then
            log_info "Checking security group: ${sg_id}"
            show_security_group_details "${sg_id}"
            
            if ! check_security_group_rules "${sg_id}" "${expected_cidr}"; then
                all_checks_passed=false
            fi
            echo
        fi
    done <<< "${sg_ids}"
    
    if [[ "${all_checks_passed}" == "true" ]]; then
        log_success "All security groups for cluster ${cluster_dir} passed check"
        return 0
    else
        log_error "Security group check failed for cluster ${cluster_dir}"
        return 1
    fi
}

# Display usage information
show_usage() {
    echo "Usage: $0 <cluster_dir> <expected_cidr>"
    echo ""
    echo "Parameters:"
    echo "  cluster_dir    - Cluster installation directory (e.g.: cluster1, cluster2)"
    echo "  expected_cidr  - Expected machine CIDR (e.g.: 10.134.0.0/16, 10.190.0.0/16)"
    echo ""
    echo "Environment variables:"
    echo "  AWS_REGION     - AWS region (default: us-east-2)"
    echo ""
    echo "Examples:"
    echo "  $0 cluster1 10.134.0.0/16"
    echo "  $0 cluster2 10.190.0.0/16"
    echo "  AWS_REGION=us-west-2 $0 cluster1 10.134.0.0/16"
}

# Main function
main() {
    if [[ $# -ne 2 ]]; then
        show_usage
        exit 1
    fi
    
    local cluster_dir="$1"
    local expected_cidr="$2"
    
    # Validate cluster directory
    if [[ ! -d "${cluster_dir}" ]]; then
        log_error "Cluster directory does not exist: ${cluster_dir}"
        exit 1
    fi
    
    # Validate CIDR format
    if [[ ! "${expected_cidr}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "Invalid CIDR format: ${expected_cidr}"
        exit 1
    fi
    
    log_info "Starting security group check"
    log_info "Cluster directory: ${cluster_dir}"
    log_info "Expected CIDR: ${expected_cidr}"
    log_info "AWS region: ${AWS_REGION:-us-east-2}"
    echo
    
    # Check security groups
    if check_cluster_security_groups "${cluster_dir}" "${expected_cidr}"; then
        log_success "Security group check completed - all checks passed"
        exit 0
    else
        log_error "Security group check completed - issues found"
        exit 1
    fi
}

# Run main function
main "$@"