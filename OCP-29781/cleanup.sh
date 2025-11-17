#!/bin/bash

# OCP-29781 Cleanup Script
# Destroy clusters and VPC stack

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

# Destroy cluster
destroy_cluster() {
    local cluster_dir="$1"
    
    if [[ ! -d "${cluster_dir}" ]]; then
        log_warning "Cluster directory does not exist: ${cluster_dir}"
        return 0
    fi
    
    log_info "Destroying cluster: ${cluster_dir}"
    
    if [[ -f "${cluster_dir}/auth/kubeconfig" ]]; then
        export KUBECONFIG="${cluster_dir}/auth/kubeconfig"
        
        # Check if cluster still exists
        if oc get nodes &> /dev/null; then
            log_info "Cluster still exists, starting destruction..."
            openshift-install --dir="${cluster_dir}" destroy cluster --log-level=info
            if [[ $? -eq 0 ]]; then
                log_success "Cluster ${cluster_dir} destruction completed"
            else
                log_error "Cluster ${cluster_dir} destruction failed"
                return 1
            fi
        else
            log_warning "Cluster ${cluster_dir} no longer exists or is not accessible"
        fi
    else
        log_warning "Kubeconfig file not found: ${cluster_dir}/auth/kubeconfig"
    fi
}

# Delete VPC stack
delete_vpc_stack() {
    local stack_name="$1"
    
    if [[ -z "${stack_name}" ]]; then
        log_warning "No stack name specified"
        return 0
    fi
    
    log_info "Deleting VPC stack: ${stack_name}"
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "${stack_name}" &> /dev/null; then
        log_info "Stack exists, starting deletion..."
        aws cloudformation delete-stack --stack-name "${stack_name}"
        
        if [[ $? -eq 0 ]]; then
            log_info "Waiting for stack deletion to complete..."
            aws cloudformation wait stack-delete-complete --stack-name "${stack_name}"
            
            if [[ $? -eq 0 ]]; then
                log_success "VPC stack ${stack_name} deletion completed"
            else
                log_error "VPC stack ${stack_name} deletion timed out or failed"
                return 1
            fi
        else
            log_error "Cannot delete VPC stack ${stack_name}"
            return 1
        fi
    else
        log_warning "VPC stack ${stack_name} does not exist"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Delete cluster directories
    for cluster_dir in cluster1 cluster2; do
        if [[ -d "${cluster_dir}" ]]; then
            log_info "Deleting cluster directory: ${cluster_dir}"
            rm -rf "${cluster_dir}"
        fi
    done
    
    # Delete temporary files
    local temp_files=(
        "vpc-info.env"
        "stack-output.json"
        "install-config-cluster1.yaml.bak"
        "install-config-cluster2.yaml.bak"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            log_info "Deleting temporary file: ${file}"
            rm -f "${file}"
        fi
    done
    
    log_success "Local file cleanup completed"
}

# Display usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Display this help information"
    echo "  -c, --cluster-only      Only destroy clusters, do not delete VPC stack"
    echo "  -v, --vpc-only          Only delete VPC stack, do not destroy clusters"
    echo "  -s, --stack-name NAME   Specify VPC stack name"
    echo "  -f, --force             Force cleanup without confirmation"
    echo ""
    echo "Examples:"
    echo "  $0                      # Clean up all resources"
    echo "  $0 -c                   # Only destroy clusters"
    echo "  $0 -v -s my-vpc-stack   # Only delete specified VPC stack"
    echo "  $0 -f                   # Force clean up all resources"
}

# Confirm cleanup operation
confirm_cleanup() {
    local force="$1"
    
    if [[ "${force}" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This operation will destroy all test resources, including:"
    echo "  - OpenShift clusters (cluster1, cluster2)"
    echo "  - VPC stack and related AWS resources"
    echo "  - Local temporary files"
    echo
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        log_info "Operation cancelled"
        exit 0
    fi
}

# Main function
main() {
    local cluster_only="false"
    local vpc_only="false"
    local stack_name=""
    local force="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--cluster-only)
                cluster_only="true"
                shift
                ;;
            -v|--vpc-only)
                vpc_only="true"
                shift
                ;;
            -s|--stack-name)
                stack_name="$2"
                shift 2
                ;;
            -f|--force)
                force="true"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Confirm cleanup operation
    confirm_cleanup "${force}"
    
    log_info "Starting OCP-29781 test resource cleanup"
    
    # Destroy clusters
    if [[ "${vpc_only}" != "true" ]]; then
        log_info "Destroying OpenShift clusters..."
        destroy_cluster "cluster1"
        destroy_cluster "cluster2"
    fi
    
    # Delete VPC stack
    if [[ "${cluster_only}" != "true" ]]; then
        # If no stack name specified, try to read from environment file
        if [[ -z "${stack_name}" && -f "vpc-info.env" ]]; then
            source vpc-info.env
            if [[ -n "${STACK_NAME:-}" ]]; then
                stack_name="${STACK_NAME}"
            fi
        fi
        
        # If still no stack name, try to find it
        if [[ -z "${stack_name}" ]]; then
            log_info "Looking for VPC stack..."
            stack_name=$(aws cloudformation list-stacks \
                --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
                --query 'StackSummaries[?contains(StackName, `ocp29781-vpc`)].StackName' \
                --output text | head -1)
        fi
        
        if [[ -n "${stack_name}" ]]; then
            delete_vpc_stack "${stack_name}"
        else
            log_warning "No VPC stack found"
        fi
    fi
    
    # Clean up local files
    cleanup_local_files
    
    log_success "Cleanup operation completed"
}

# Run main function
main "$@"