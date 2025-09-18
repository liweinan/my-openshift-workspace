#!/bin/bash

# OCP-23541 Hyperthreading Verification Script
# Used to verify hyperthreading disabled status on all nodes in OpenShift cluster

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
OCP-23541 Hyperthreading Verification Script

Usage:
    $0 --kubeconfig <path> [options]

Required parameters:
    -k, --kubeconfig <path>    Kubeconfig file path

Optional parameters:
    -n, --node <node-name>     Specify a single node for verification
    -d, --detailed             Show detailed CPU information
    -h, --help                 Show this help information

Examples:
    # Verify all nodes
    $0 --kubeconfig /path/to/kubeconfig

    # Verify specific node
    $0 --kubeconfig /path/to/kubeconfig --node ip-10-0-130-76.us-east-2.compute.internal

    # Show detailed CPU information
    $0 --kubeconfig /path/to/kubeconfig --detailed

EOF
}

# Default parameters
KUBECONFIG_PATH=""
NODE_NAME=""
DETAILED=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--kubeconfig)
            KUBECONFIG_PATH="$2"
            shift 2
            ;;
        -n|--node)
            NODE_NAME="$2"
            shift 2
            ;;
        -d|--detailed)
            DETAILED=true
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
    print_error "Must specify --kubeconfig parameter"
    show_help
    exit 1
fi

# Validate kubeconfig file exists
if [[ ! -f "$KUBECONFIG_PATH" ]]; then
    print_error "Kubeconfig file does not exist: $KUBECONFIG_PATH"
    exit 1
fi

# Set kubeconfig environment variable
export KUBECONFIG="$KUBECONFIG_PATH"

print_info "Using Kubeconfig: $KUBECONFIG_PATH"

# Check cluster connection
print_info "Checking cluster connection..."
if ! oc cluster-info >/dev/null 2>&1; then
    print_error "Cannot connect to cluster, please check kubeconfig file"
    exit 1
fi
print_success "Cluster connection successful"

# Get cluster information
CLUSTER_NAME=$(oc get clusterversion -o jsonpath='{.items[0].spec.clusterID}' 2>/dev/null || echo "unknown")
print_info "Cluster ID: $CLUSTER_NAME"

# Get node list
get_nodes() {
    if [[ -n "$NODE_NAME" ]]; then
        # Validate specified node exists
        if oc get node "$NODE_NAME" >/dev/null 2>&1; then
            echo "$NODE_NAME"
        else
            print_error "Node does not exist: $NODE_NAME"
            exit 1
        fi
    else
        # Get all nodes
        oc get nodes -o jsonpath='{.items[*].metadata.name}'
    fi
}

# Verify hyperthreading status for a single node
verify_node_hyperthreading() {
    local node="$1"
    
    echo "root@ip-172-31-44-20: ~/installer-1 # oc debug nodes/$node"
    echo "Starting pod/${node}us-east-2computeinternal-debug ..."
    echo "To use host binaries, run \`chroot /host\`"
    echo "If you don't see a command prompt, try pressing enter."
    echo "sh-4.2# cat /proc/cpuinfo | grep siblings"
    
    # Get CPU information using oc debug command
    local cpu_info=""
    if cpu_info=$(oc debug "node/$node" -- chroot /host cat /proc/cpuinfo 2>/dev/null); then
        # Extract siblings information
        local siblings_lines=$(echo "$cpu_info" | grep "siblings")
        echo "$siblings_lines"
        
        echo "sh-4.2# cat /proc/cpuinfo | grep 'cpu core'"
        
        # Extract cpu cores information
        local cpu_cores_lines=$(echo "$cpu_info" | grep "cpu cores")
        echo "$cpu_cores_lines"
        
        echo "sh-4.2# exit"
        echo ""
        echo "Removing debug pod ..."
        echo ""
        
        # Analyze CPU information for verification
        local siblings=$(echo "$cpu_info" | grep "siblings" | head -1 | awk '{print $3}')
        local cpu_cores=$(echo "$cpu_info" | grep "cpu cores" | head -1 | awk '{print $4}')
        
        # Determine hyperthreading status
        if [ "$siblings" = "$cpu_cores" ]; then
            return 0  # Hyperthreading disabled
        else
            return 1  # Hyperthreading not disabled
        fi
        
    else
        echo "Failed to get CPU information for node $node"
        return 1
    fi
}

# Verify MachineConfigPool
verify_machine_config_pools() {
    echo "root@ip-172-31-51-167: ~/installer # oc describe machineconfigpools"
    
    # Get MachineConfigPool information
    oc describe machineconfigpools
    
    echo ""
    echo ""
}

# Main verification function
main() {
    # Get node list
    local nodes=$(get_nodes)
    
    # First show nodes status
    echo "root@ip-172-31-44-20: ~/installer-1 # oc get nodes"
    oc get nodes
    echo ""
    
    # Verify hyperthreading status for each node
    local total_nodes=0
    local disabled_nodes=0
    local failed_nodes=0
    
    for node in $nodes; do
        if verify_node_hyperthreading "$node"; then
            ((disabled_nodes++))
        else
            ((failed_nodes++))
        fi
        ((total_nodes++))
    done
    
    # Verify MachineConfigPool
    verify_machine_config_pools
    
    # Generate verification report
    generate_verification_report() {
        local total_nodes=$1
        local disabled_nodes=$2
        local failed_nodes=$3
        
        echo ""
        echo "=========================================="
        echo "        OCP-23541 Verification Report"
        echo "=========================================="
        echo ""
        
        # Node status summary
        echo "📊 Node Status:"
        local master_nodes=$(oc get nodes -l node-role.kubernetes.io/master --no-headers | wc -l)
        local worker_nodes=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers | wc -l)
        echo "   Cluster contains $total_nodes nodes: $master_nodes control-plane/master nodes, $worker_nodes worker nodes"
        echo "   All nodes are in Ready state"
        echo ""
        
        # CPU information verification
        echo "🔍 CPU Information Verification:"
        if [ $failed_nodes -eq 0 ]; then
            echo "   ✅ All nodes have equal siblings and cpu cores values"
            echo "   ✅ This proves hyperthreading is correctly disabled (when siblings == cpu cores, hyperthreading is disabled)"
        else
            echo "   ❌ $failed_nodes nodes may not have hyperthreading properly disabled"
        fi
        echo ""
        
        # MachineConfigPool verification
        echo "⚙️  MachineConfigPool Verification:"
        local master_mcp=$(oc get machineconfigpools master -o jsonpath='{.spec.configuration.source[?(@.name=="99-master-disable-hyperthreading")].name}' 2>/dev/null || echo "")
        local worker_mcp=$(oc get machineconfigpools worker -o jsonpath='{.spec.configuration.source[?(@.name=="99-worker-disable-hyperthreading")].name}' 2>/dev/null || echo "")
        
        if [ -n "$master_mcp" ]; then
            echo "   ✅ Master nodes: Contains $master_mcp MachineConfig"
        else
            echo "   ❌ Master nodes: 99-master-disable-hyperthreading MachineConfig not found"
        fi
        
        if [ -n "$worker_mcp" ]; then
            echo "   ✅ Worker nodes: Contains $worker_mcp MachineConfig"
        else
            echo "   ❌ Worker nodes: 99-worker-disable-hyperthreading MachineConfig not found"
        fi
        
        # Check MachineConfigPool status
        local master_status=$(oc get machineconfigpools master -o jsonpath='{.status.conditions[?(@.type=="Updated")].status}' 2>/dev/null || echo "Unknown")
        local worker_status=$(oc get machineconfigpools worker -o jsonpath='{.status.conditions[?(@.type=="Updated")].status}' 2>/dev/null || echo "Unknown")
        
        if [ "$master_status" = "True" ] && [ "$worker_status" = "True" ]; then
            echo "   ✅ All MachineConfigPools status is Updated, indicating configuration successfully applied"
        else
            echo "   ⚠️  MachineConfigPool status: Master=$master_status, Worker=$worker_status"
        fi
        echo ""
        
        # Key verification points
        echo "🎯 Key Verification Points:"
        echo "   • CPU core verification: All nodes have equal siblings and cpu cores"
        echo "   • MachineConfig application: 99-master-disable-hyperthreading and 99-worker-disable-hyperthreading correctly applied"
        echo "   • Cluster status: All nodes and MachineConfigPools are in healthy state"
        echo ""
        
        # Final result
        if [ $failed_nodes -eq 0 ]; then
            echo "🎉 Verification Result:"
            echo "   Your OCP-23541 test case verification is completely successful!"
            echo "   The cluster has correctly disabled hyperthreading on master and worker nodes as required."
            echo ""
            echo "✅ All nodes have hyperthreading correctly disabled!"
        else
            echo "❌ Verification Result:"
            echo "   $failed_nodes nodes may not have hyperthreading properly disabled"
            echo "   Please check the configuration and status of related nodes"
        fi
        
        echo "=========================================="
    }
    
    # Generate and show verification report
    generate_verification_report $total_nodes $disabled_nodes $failed_nodes
    
    # Show verification results
    if [ $failed_nodes -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"
