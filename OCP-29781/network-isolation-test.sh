#!/bin/bash

# OCP-29781 Network Isolation Test Script
# Verify that the two clusters cannot communicate with each other

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

# Get cluster master node IPs
get_master_ips() {
    local cluster_dir="$1"
    local kubeconfig="${cluster_dir}/auth/kubeconfig"
    
    if [[ ! -f "${kubeconfig}" ]]; then
        log_error "Kubeconfig file not found: ${kubeconfig}"
        return 1
    fi
    
    export KUBECONFIG="${kubeconfig}"
    
    local master_ips
    master_ips=$(oc get nodes -o wide --no-headers | awk '$3 == "master" {print $6}')
    
    if [[ -z "${master_ips}" ]]; then
        log_error "No master nodes found"
        return 1
    fi
    
    echo "${master_ips}"
}

# Deploy SSH bastion
deploy_ssh_bastion() {
    local cluster_dir="$1"
    local kubeconfig="${cluster_dir}/auth/kubeconfig"
    
    log_info "Deploying SSH bastion to cluster ${cluster_dir}..."
    
    export KUBECONFIG="${kubeconfig}"
    
    # Check if bastion already exists
    if oc get service ssh-bastion -n openshift-ssh-bastion &> /dev/null; then
        log_info "SSH bastion already exists"
        return 0
    fi
    
    # Deploy SSH bastion
    curl -s https://raw.githubusercontent.com/eparis/ssh-bastion/master/deploy/deploy.sh | bash
    
    if [[ $? -eq 0 ]]; then
        log_success "SSH bastion deployment successful"
    else
        log_error "SSH bastion deployment failed"
        return 1
    fi
}

# Execute remote command through bastion
run_remote_command() {
    local cluster_dir="$1"
    local target_ip="$2"
    local command="$3"
    local kubeconfig="${cluster_dir}/auth/kubeconfig"
    
    export KUBECONFIG="${kubeconfig}"
    
    # Get bastion hostname
    local bastion_hostname
    bastion_hostname=$(oc get service -n openshift-ssh-bastion ssh-bastion -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    if [[ -z "${bastion_hostname}" ]]; then
        log_error "Cannot get bastion hostname"
        return 1
    fi
    
    # Get SSH key path
    local ssh_key="${HOME}/.ssh/id_rsa"
    if [[ ! -f "${ssh_key}" ]]; then
        log_error "SSH key not found: ${ssh_key}"
        return 1
    fi
    
    # Build SSH command
    local ssh_cmd="ssh -i \"${ssh_key}\" -t -t -o StrictHostKeyChecking=no -o ProxyCommand='ssh -i \"${ssh_key}\" -A -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -W %h:%p core@${bastion_hostname}' core@${target_ip} ${command}"
    
    log_info "Executing remote command: ${command}"
    log_info "Target IP: ${target_ip}"
    
    # Execute command
    eval "${ssh_cmd}"
}

# Test network connectivity
test_network_connectivity() {
    local source_cluster="$1"
    local target_cluster="$2"
    local ping_count="${3:-3}"
    
    log_info "Testing network connectivity: ${source_cluster} -> ${target_cluster}"
    
    # Get target cluster master IP
    local target_ips
    target_ips=$(get_master_ips "${target_cluster}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Get source cluster master IP
    local source_ips
    source_ips=$(get_master_ips "${source_cluster}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Select first master node as source
    local source_ip
    source_ip=$(echo "${source_ips}" | head -1)
    
    # Select first master node as target
    local target_ip
    target_ip=$(echo "${target_ips}" | head -1)
    
    log_info "Source IP: ${source_ip}"
    log_info "Target IP: ${target_ip}"
    
    # Deploy SSH bastion to source cluster
    if ! deploy_ssh_bastion "${source_cluster}"; then
        return 1
    fi
    
    # Execute ping test
    log_info "Executing ping test..."
    local ping_output
    ping_output=$(run_remote_command "${source_cluster}" "${source_ip}" "ping -c ${ping_count} ${target_ip}" 2>&1)
    local ping_result=$?
    
    echo "Ping output:"
    echo "${ping_output}"
    echo
    
    # Analyze results
    if echo "${ping_output}" | grep -q "100% packet loss"; then
        log_success "Network isolation test passed - 100% packet loss"
        return 0
    elif [[ ${ping_result} -eq 0 ]]; then
        log_error "Network isolation test failed - can ping target"
        return 1
    else
        log_warning "Network isolation test results are unclear - ping command failed but doesn't show 100% packet loss"
        return 1
    fi
}

# Display usage information
show_usage() {
    echo "Usage: $0 <cluster1_dir> <cluster2_dir> [ping_count]"
    echo ""
    echo "Parameters:"
    echo "  cluster1_dir  - First cluster directory (e.g.: cluster1)"
    echo "  cluster2_dir  - Second cluster directory (e.g.: cluster2)"
    echo "  ping_count    - Number of ping attempts (default: 3)"
    echo ""
    echo "Examples:"
    echo "  $0 cluster1 cluster2"
    echo "  $0 cluster1 cluster2 5"
}

# Main function
main() {
    if [[ $# -lt 2 || $# -gt 3 ]]; then
        show_usage
        exit 1
    fi
    
    local cluster1_dir="$1"
    local cluster2_dir="$2"
    local ping_count="${3:-3}"
    
    # Validate cluster directories
    for cluster_dir in "${cluster1_dir}" "${cluster2_dir}"; do
        if [[ ! -d "${cluster_dir}" ]]; then
            log_error "Cluster directory does not exist: ${cluster_dir}"
            exit 1
        fi
        
        local kubeconfig="${cluster_dir}/auth/kubeconfig"
        if [[ ! -f "${kubeconfig}" ]]; then
            log_error "Kubeconfig file not found: ${kubeconfig}"
            exit 1
        fi
    done
    
    log_info "Starting network isolation test"
    log_info "Cluster 1: ${cluster1_dir}"
    log_info "Cluster 2: ${cluster2_dir}"
    log_info "Ping count: ${ping_count}"
    echo
    
    local all_tests_passed=true
    
    # Test connectivity from cluster1 to cluster2
    log_info "=== Testing connectivity from cluster1 to cluster2 ==="
    if ! test_network_connectivity "${cluster1_dir}" "${cluster2_dir}" "${ping_count}"; then
        all_tests_passed=false
    fi
    echo
    
    # Test connectivity from cluster2 to cluster1
    log_info "=== Testing connectivity from cluster2 to cluster1 ==="
    if ! test_network_connectivity "${cluster2_dir}" "${cluster1_dir}" "${ping_count}"; then
        all_tests_passed=false
    fi
    echo
    
    # Summarize results
    if [[ "${all_tests_passed}" == "true" ]]; then
        log_success "Network isolation test completed - all tests passed"
        log_success "The two clusters cannot communicate with each other, network isolation is normal"
        exit 0
    else
        log_error "Network isolation test completed - issues found"
        log_error "The two clusters can communicate with each other, network isolation failed"
        exit 1
    fi
}

# Run main function
main "$@"