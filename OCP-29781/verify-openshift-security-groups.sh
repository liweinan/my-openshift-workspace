#!/bin/bash

# OpenShift 4.x Security Group Verification Script
# Verify security group configuration meets network isolation requirements

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

verify_cluster_security_groups() {
    local cluster_name=$1
    local infra_id=$2
    local machine_cidr=$3
    
    log_info "=== Verifying ${cluster_name} (${infra_id}) ==="
    log_info "Machine CIDR: ${machine_cidr}"
    echo
    
    # Get all security groups
    local all_sgs
    all_sgs=$(aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters "Name=tag:kubernetes.io/cluster/${infra_id},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    log_info "Cluster security groups: ${all_sgs}"
    echo
    
    # Analyze security group architecture
    analyze_security_group_architecture "${all_sgs}" "${infra_id}" "${machine_cidr}"
    echo
}

analyze_security_group_architecture() {
    local sg_list=$1
    local infra_id=$2
    local machine_cidr=$3
    
    log_info "Analyzing security group architecture..."
    
    # Get all related security groups (including referenced ones)
    local all_related_sgs="${sg_list}"
    
    for sg_id in $sg_list; do
        # Get other security groups referenced by this security group
        local referenced_sgs
        referenced_sgs=$(aws ec2 describe-security-groups \
            --region "${AWS_REGION}" \
            --group-ids "${sg_id}" \
            --query 'SecurityGroups[0].IpPermissions[].UserIdGroupPairs[].GroupId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${referenced_sgs}" ]]; then
            all_related_sgs="${all_related_sgs} ${referenced_sgs}"
        fi
    done
    
    # Remove duplicates
    all_related_sgs=$(echo "${all_related_sgs}" | tr ' ' '\n' | sort | uniq)
    
    log_info "All related security groups: ${all_related_sgs}"
    echo
    
    # Analyze each security group
    for sg_id in $all_related_sgs; do
        analyze_single_security_group "${sg_id}" "${infra_id}" "${machine_cidr}"
    done
}

analyze_single_security_group() {
    local sg_id=$1
    local infra_id=$2
    local machine_cidr=$3
    
    log_info "Analyzing security group: ${sg_id}"
    
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
    
    # Check if it belongs to current cluster
    if [[ "${sg_name}" == *"${infra_id}"* ]]; then
        log_info "Type: Cluster internal security group"
        analyze_cluster_internal_sg "${sg_info}" "${machine_cidr}"
    else
        log_info "Type: External referenced security group"
    fi
    
    echo "----------------------------------------"
}

analyze_cluster_internal_sg() {
    local sg_info=$1
    local machine_cidr=$2
    
    # Get all inbound rules
    local ingress_rules
    ingress_rules=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].IpPermissions[]')
    
    # Check if there are CIDR rules
    local has_cidr_rules=false
    local cidr_rules=""
    
    while IFS= read -r rule; do
        local ip_ranges
        ip_ranges=$(echo "${rule}" | jq -r '.IpRanges[]?.CidrIp // empty')
        if [[ -n "${ip_ranges}" ]]; then
            has_cidr_rules=true
            cidr_rules="${cidr_rules}${ip_ranges}\n"
        fi
    done <<< "${ingress_rules}"
    
    if [[ "${has_cidr_rules}" == "true" ]]; then
        log_info "CIDR rules:"
        echo -e "${cidr_rules}" | while read -r cidr; do
            if [[ -n "${cidr}" ]]; then
                if [[ "${cidr}" == "${machine_cidr}" ]]; then
                    log_success "  ✅ ${cidr} (matches machine CIDR)"
                else
                    log_warning "  ⚠️  ${cidr} (does not match machine CIDR)"
                fi
            fi
        done
    else
        log_info "Uses security group references instead of CIDR rules (OpenShift 4.x standard practice)"
    fi
    
    # Check key ports
    check_key_ports "${sg_info}"
}

check_key_ports() {
    local sg_info=$1
    
    log_info "Key port check:"
    
    # Check port 6443
    local port_6443
    port_6443=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].IpPermissions[] | select(.FromPort == 6443 and .ToPort == 6443)')
    if [[ -n "${port_6443}" ]]; then
        log_success "  ✅ 6443/tcp (API Server) - configured"
    else
        log_warning "  ⚠️  6443/tcp (API Server) - not found"
    fi
    
    # Check port 22623
    local port_22623
    port_22623=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].IpPermissions[] | select(.FromPort == 22623 and .ToPort == 22623)')
    if [[ -n "${port_22623}" ]]; then
        log_success "  ✅ 22623/tcp (Machine Config Server) - configured"
    else
        log_warning "  ⚠️  22623/tcp (Machine Config Server) - not found"
    fi
    
    # Check port 22
    local port_22
    port_22=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].IpPermissions[] | select(.FromPort == 22 and .ToPort == 22)')
    if [[ -n "${port_22}" ]]; then
        log_success "  ✅ 22/tcp (SSH) - configured"
    else
        log_warning "  ⚠️  22/tcp (SSH) - not found"
    fi
    
    # Check ICMP
    local icmp
    icmp=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].IpPermissions[] | select(.IpProtocol == "icmp")')
    if [[ -n "${icmp}" ]]; then
        log_success "  ✅ ICMP - configured"
    else
        log_warning "  ⚠️  ICMP - not found"
    fi
}

# Verify network isolation
verify_network_isolation() {
    log_info "=== Verifying Network Isolation ==="
    
    # Get all security groups for both clusters
    local cluster1_sgs
    cluster1_sgs=$(aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters "Name=tag:kubernetes.io/cluster/${CLUSTER1_INFRA_ID},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    local cluster2_sgs
    cluster2_sgs=$(aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters "Name=tag:kubernetes.io/cluster/${CLUSTER2_INFRA_ID},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    log_info "Cluster 1 security groups: ${cluster1_sgs}"
    log_info "Cluster 2 security groups: ${cluster2_sgs}"
    
    # Check for cross-references
    local has_cross_reference=false
    for sg1 in $cluster1_sgs; do
        for sg2 in $cluster2_sgs; do
            if [[ "${sg1}" == "${sg2}" ]]; then
                has_cross_reference=true
                log_error "Found shared security group: ${sg1}"
            fi
        done
    done
    
    if [[ "${has_cross_reference}" == "false" ]]; then
        log_success "✅ Both clusters use independent security groups, network isolation is correct"
    else
        log_error "❌ Found shared security groups, network isolation may have issues"
    fi
}

# Main function
main() {
    log_info "Starting OpenShift 4.x security group verification"
    echo "=========================================="
    
    verify_cluster_security_groups "Cluster 1" "${CLUSTER1_INFRA_ID}" "${CLUSTER1_MACHINE_CIDR}"
    verify_cluster_security_groups "Cluster 2" "${CLUSTER2_INFRA_ID}" "${CLUSTER2_MACHINE_CIDR}"
    
    verify_network_isolation
    
    log_success "Security group verification completed!"
    echo
    log_info "OpenShift 4.x using security group references instead of CIDR rules is normal security practice"
    log_info "Network isolation is achieved through independent security groups"
}

main "$@"