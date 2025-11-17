#!/bin/bash
#
# example-get-cluster-ips.sh
# Demonstrates how to use the get-cluster-node-ips.sh script
#

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 示例集群名称
CLUSTER_NAME="weli-testx"
REGION="us-east-1"

print_info "Demonstrating various usage patterns of get-cluster-node-ips.sh script"
echo ""

print_info "1. Get all nodes in table format:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -f table"
echo ""

print_info "2. Get all nodes in JSON format:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -f json"
echo ""

print_info "3. Get all nodes in environment variable format:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -f export"
echo ""

print_info "4. Get only bootstrap node:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -t bootstrap -f table"
echo ""

print_info "5. Get only master nodes:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -t master -f export"
echo ""

print_info "6. Get only worker nodes:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -t worker -f table"
echo ""

print_info "7. Verbose output mode:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -f table -v"
echo ""

print_info "8. Cluster in different region:"
echo "./get-cluster-node-ips.sh -c my-cluster -r us-west-2 -f table"
echo ""

print_success "Script functionality:"
echo "- Supports automatic detection of node name formats with infraID"
echo "- Supports both private clusters (no public IPs) and public clusters"
echo "- Provides three output formats: table, json, export"
echo "- Supports filtering by node type: all, bootstrap, master, worker"
echo "- Supports verbose output mode for debugging"
echo ""

print_success "Use cases:"
echo "1. Get bootstrap IP for gather bootstrap command"
echo "2. Get master IPs for gather bootstrap command"
echo "3. Export environment variables for other scripts"
echo "4. Check cluster node status and network configuration"
echo "5. Node discovery in automation scripts"
