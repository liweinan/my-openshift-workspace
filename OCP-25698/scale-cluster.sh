#!/bin/bash

# OCP-25698 Cluster Scaling Script
# Used to scale worker nodes in existing OpenShift cluster

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show help information
show_help() {
    cat << EOF
OCP-25698 Cluster Scaling Script

Usage:
    $0 --kubeconfig <path> [选项]

必需参数:
    -k, --kubeconfig <path>    Kubeconfig file path

可选参数:
    -r, --replicas <number>    Target replica count (default: 4)
    -n, --namespace <name>     MachineSet namespace (default: openshift-machine-api)
    -m, --machineset <name>   Specify MachineSet name (optional, lists all if not specified)
    -w, --wait                 Wait for scaling to complete
    -t, --timeout <seconds>    Wait timeout in seconds (default: 600 seconds)
    -d, --dry-run              Only show operations to be performed, do not execute
    -h, --help                 Show this help message

示例:
    # Basic usage - scale to 4 replicas
    $0 --kubeconfig /path/to/kubeconfig

    # Scale to 6 replicas
    $0 --kubeconfig /path/to/kubeconfig --replicas 6

    # Specify MachineSet name
    $0 --kubeconfig /path/to/kubeconfig --machineset my-cluster-abc123-worker-us-east-2a

    # Wait for scaling to complete
    $0 --kubeconfig /path/to/kubeconfig --wait

    # Dry run mode
    $0 --kubeconfig /path/to/kubeconfig --dry-run

EOF
}

# Default parameters
KUBECONFIG_PATH=""
REPLICAS=4
NAMESPACE="openshift-machine-api"
MACHINESET_NAME=""
WAIT_FOR_COMPLETION=false
TIMEOUT=600
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--kubeconfig)
            KUBECONFIG_PATH="$2"
            shift 2
            ;;
        -r|--replicas)
            REPLICAS="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -m|--machineset)
            MACHINESET_NAME="$2"
            shift 2
            ;;
        -w|--wait)
            WAIT_FOR_COMPLETION=true
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$KUBECONFIG_PATH" ]]; then
    print_error "--kubeconfig parameter must be specified"
    show_help
    exit 1
fi

# 验证kubeconfig文件是否存在
if [[ ! -f "$KUBECONFIG_PATH" ]]; then
    print_error "Kubeconfig file does not exist: $KUBECONFIG_PATH"
    exit 1
fi

# 验证副本数
if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]] || [[ "$REPLICAS" -lt 1 ]]; then
    print_error "Replica count must be a positive integer: $REPLICAS"
    exit 1
fi

# Set kubeconfig environment variable
export KUBECONFIG="$KUBECONFIG_PATH"

print_info "Using Kubeconfig: $KUBECONFIG_PATH"
print_info "Target replica count: $REPLICAS"
print_info "Namespace: $NAMESPACE"

# Check cluster connection
print_info "Checking cluster connection..."
if ! oc cluster-info >/dev/null 2>&1; then
    print_error "Cannot connect to cluster, please check kubeconfig file"
    exit 1
fi
print_success "Cluster connection normal"

# Get cluster information
CLUSTER_NAME=$(oc get clusterversion -o jsonpath='{.items[0].spec.clusterID}' 2>/dev/null || echo "unknown")
print_info "Cluster ID: $CLUSTER_NAME"

# List all MachineSets
list_machinesets() {
    print_info "Getting MachineSet list..."
    oc get machinesets -n "$NAMESPACE" -o wide
}

# Get MachineSet detailed information
get_machineset_info() {
    local machineset_name="$1"
    print_info "Getting MachineSet detailed information: $machineset_name"
    oc describe machineset "$machineset_name" -n "$NAMESPACE"
}

# Scale MachineSet
scale_machineset() {
    local machineset_name="$1"
    local target_replicas="$2"
    
    print_info "Scaling MachineSet: $machineset_name to $target_replicas replicas"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "[DRY RUN] Will execute: oc scale machineset $machineset_name -n $NAMESPACE --replicas=$target_replicas"
        return 0
    fi
    
    if oc scale machineset "$machineset_name" -n "$NAMESPACE" --replicas="$target_replicas"; then
        print_success "MachineSet scaling command executed successfully"
    else
        print_error "MachineSet scaling command execution failed"
        return 1
    fi
}

# Wait for scaling to complete
wait_for_scaling() {
    local machineset_name="$1"
    local target_replicas="$2"
    local timeout="$3"
    
    print_info "Waiting for scaling to complete (timeout: ${timeout} seconds)..."
    
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        local current_replicas=$(oc get machineset "$machineset_name" -n "$NAMESPACE" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
        local ready_replicas=$(oc get machineset "$machineset_name" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        
        print_info "Current replicas: $current_replicas, ready replicas: $ready_replicas, target: $target_replicas"
        
        if [[ "$ready_replicas" -eq "$target_replicas" ]]; then
            print_success "Scaling complete! All $target_replicas replicas are ready"
            return 0
        fi
        
        sleep 10
    done
    
    print_warning "Timeout reached, scaling may still be in progress"
    return 1
}

# Show node status
show_node_status() {
    print_info "Current node status:"
    oc get nodes -o wide
}

# Show Machine status
show_machine_status() {
    print_info "Current Machine status:"
    oc get machines -n "$NAMESPACE" -o wide
}

# 主逻辑
main() {
    print_info "Starting cluster scaling operation..."
    
    # 显示当前状态
    show_node_status
    echo ""
    show_machine_status
    echo ""
    
    # 列出MachineSet
    list_machinesets
    echo ""
    
    if [[ -n "$MACHINESET_NAME" ]]; then
        # 指定了MachineSet名称
        print_info "使用指定的MachineSet: $MACHINESET_NAME"
        
        # 验证MachineSet是否存在
        if ! oc get machineset "$MACHINESET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
            print_error "MachineSet不存在: $MACHINESET_NAME"
            exit 1
        fi
        
        # 显示MachineSet详细信息
        get_machineset_info "$MACHINESET_NAME"
        echo ""
        
        # 执行扩容
        scale_machineset "$MACHINESET_NAME" "$REPLICAS"
        
        if [[ "$WAIT_FOR_COMPLETION" == "true" ]]; then
            wait_for_scaling "$MACHINESET_NAME" "$REPLICAS" "$TIMEOUT"
        fi
        
    else
        # 没有指定MachineSet名称，列出所有并让用户选择
        print_info "No MachineSet name specified, will list all available MachineSets"
        
        local machinesets=$(oc get machinesets -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
        
        if [[ -z "$machinesets" ]]; then
            print_error "No MachineSets found"
            exit 1
        fi
        
        print_info "Found the following MachineSets:"
        for ms in $machinesets; do
            local current_replicas=$(oc get machineset "$ms" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
            local ready_replicas=$(oc get machineset "$ms" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            echo "  - $ms (当前: $current_replicas, 就绪: $ready_replicas)"
        done
        
        if [[ "$DRY_RUN" == "true" ]]; then
            print_warning "[DRY RUN] Will scale all MachineSets to $REPLICAS replicas"
            for ms in $machinesets; do
                print_warning "[DRY RUN] Will execute: oc scale machineset $ms -n $NAMESPACE --replicas=$REPLICAS"
            done
        else
            # 扩容所有MachineSet
            for ms in $machinesets; do
                echo ""
                print_info "Scaling MachineSet: $ms"
                scale_machineset "$ms" "$REPLICAS"
                
                if [[ "$WAIT_FOR_COMPLETION" == "true" ]]; then
                    wait_for_scaling "$ms" "$REPLICAS" "$TIMEOUT"
                fi
            done
        fi
    fi
    
    echo ""
    print_info "Scaling operation completed"
    
    # 显示最终状态
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        show_node_status
        echo ""
        show_machine_status
    fi
}

# 执行主函数
main "$@"
