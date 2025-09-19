#!/bin/bash
#
# example-get-cluster-ips.sh
# 演示如何使用 get-cluster-node-ips.sh 脚本
#

set -euo pipefail

# 颜色代码
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

print_info "演示 get-cluster-node-ips.sh 脚本的各种用法"
echo ""

print_info "1. 获取所有节点的表格格式显示:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -f table"
echo ""

print_info "2. 获取所有节点的 JSON 格式输出:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -f json"
echo ""

print_info "3. 获取所有节点的环境变量格式:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -f export"
echo ""

print_info "4. 仅获取 bootstrap 节点:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -t bootstrap -f table"
echo ""

print_info "5. 仅获取 master 节点:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -t master -f export"
echo ""

print_info "6. 仅获取 worker 节点:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -t worker -f table"
echo ""

print_info "7. 详细输出模式:"
echo "./get-cluster-node-ips.sh -c $CLUSTER_NAME -r $REGION -f table -v"
echo ""

print_info "8. 不同区域的集群:"
echo "./get-cluster-node-ips.sh -c my-cluster -r us-west-2 -f table"
echo ""

print_success "脚本功能说明:"
echo "- 支持自动检测带 infraID 的节点名称格式"
echo "- 支持私有集群（无公网 IP）和公有集群"
echo "- 提供三种输出格式：table, json, export"
echo "- 支持按节点类型过滤：all, bootstrap, master, worker"
echo "- 支持详细输出模式用于调试"
echo ""

print_success "使用场景:"
echo "1. 获取 bootstrap IP 用于 gather bootstrap 命令"
echo "2. 获取 master IPs 用于 gather bootstrap 命令"
echo "3. 导出环境变量用于其他脚本"
echo "4. 检查集群节点状态和网络配置"
echo "5. 自动化脚本中的节点发现"
