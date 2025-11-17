#!/bin/bash

# Simplified Security Group Check Script

set -euo pipefail

AWS_REGION="us-east-1"
CLUSTER1_INFRA_ID="weli-test-a-p6fbf"
CLUSTER2_INFRA_ID="weli-test-b-2vgnm"

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

check_cluster() {
    local cluster_name=$1
    local infra_id=$2
    
    log_info "=== Checking ${cluster_name} (${infra_id}) ==="
    
    # Get security group IDs
    local security_groups
    security_groups=$(aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters "Name=tag:kubernetes.io/cluster/${infra_id},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    log_info "Security groups: ${security_groups}"
    echo
    
    # Check each security group
    for sg_id in $security_groups; do
        check_single_sg "${sg_id}" "${infra_id}"
    done
    echo
}

check_single_sg() {
    local sg_id=$1
    local infra_id=$2
    
    log_info "Checking security group: ${sg_id}"
    
    # Get security group information
    local sg_name
    sg_name=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].GroupName' \
        --output text)
    
    local sg_description
    sg_description=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].Description' \
        --output text)
    
    log_info "Name: ${sg_name}"
    log_info "Description: ${sg_description}"
    
    # Check key ports
    if [[ "${sg_name}" == *"controlplane"* ]]; then
        log_info "Type: Control Plane"
        check_controlplane_ports "${sg_id}"
    elif [[ "${sg_name}" == *"node"* ]]; then
        log_info "Type: Worker Node"
        check_worker_ports "${sg_id}"
    elif [[ "${sg_name}" == *"lb"* ]]; then
        log_info "Type: Load Balancer"
    elif [[ "${sg_name}" == *"apiserver"* ]]; then
        log_info "Type: API Server Load Balancer"
    else
        log_info "Type: Other"
    fi
    
    echo "----------------------------------------"
}

check_controlplane_ports() {
    local sg_id=$1
    
    log_info "Control Plane port check:"
    
    # Check port 6443
    local has_6443
    has_6443=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`6443` && ToPort==`6443`]' \
        --output text)
    
    if [[ -n "${has_6443}" ]]; then
        log_success "  ✅ 6443/tcp (API Server) - configured"
    else
        log_warning "  ⚠️  6443/tcp (API Server) - not found"
    fi
    
    # Check port 22623
    local has_22623
    has_22623=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`22623` && ToPort==`22623`]' \
        --output text)
    
    if [[ -n "${has_22623}" ]]; then
        log_success "  ✅ 22623/tcp (Machine Config Server) - configured"
    else
        log_warning "  ⚠️  22623/tcp (Machine Config Server) - not found"
    fi
    
    # Check port 22
    local has_22
    has_22=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`22` && ToPort==`22`]' \
        --output text)
    
    if [[ -n "${has_22}" ]]; then
        log_success "  ✅ 22/tcp (SSH) - configured"
    else
        log_warning "  ⚠️  22/tcp (SSH) - not found"
    fi
    
    # Check ICMP
    local has_icmp
    has_icmp=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[?IpProtocol==`icmp`]' \
        --output text)
    
    if [[ -n "${has_icmp}" ]]; then
        log_success "  ✅ ICMP - configured"
    else
        log_warning "  ⚠️  ICMP - not found"
    fi
}

check_worker_ports() {
    local sg_id=$1
    
    log_info "Worker Node port check:"
    
    # Check port 22
    local has_22
    has_22=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`22` && ToPort==`22`]' \
        --output text)
    
    if [[ -n "${has_22}" ]]; then
        log_success "  ✅ 22/tcp (SSH) - configured"
    else
        log_warning "  ⚠️  22/tcp (SSH) - not found"
    fi
    
    # Check ICMP
    local has_icmp
    has_icmp=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[?IpProtocol==`icmp`]' \
        --output text)
    
    if [[ -n "${has_icmp}" ]]; then
        log_success "  ✅ ICMP - configured"
    else
        log_warning "  ⚠️  ICMP - not found"
    fi
}

# Verify network isolation
verify_isolation() {
    log_info "=== Verifying Network Isolation ==="
    
    # Get security groups for both clusters
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
    
    # Check for shared security groups
    local shared_sgs=""
    for sg1 in $cluster1_sgs; do
        for sg2 in $cluster2_sgs; do
            if [[ "${sg1}" == "${sg2}" ]]; then
                shared_sgs="${shared_sgs} ${sg1}"
            fi
        done
    done
    
    if [[ -z "${shared_sgs}" ]]; then
        log_success "✅ Both clusters use completely independent security groups"
        log_success "✅ Network isolation is correctly configured"
    else
        log_error "❌ Found shared security groups: ${shared_sgs}"
        log_error "❌ Network isolation may have issues"
    fi
}

# Main function
main() {
    log_info "Starting security group verification"
    echo "=========================================="
    
    check_cluster "Cluster 1" "${CLUSTER1_INFRA_ID}"
    check_cluster "Cluster 2" "${CLUSTER2_INFRA_ID}"
    
    verify_isolation
    
    log_success "Security group verification completed!"
    echo
    log_info "OpenShift 4.x uses security group references to achieve network isolation"
    log_info "This is a more secure approach than CIDR rules"
}

main "$@"