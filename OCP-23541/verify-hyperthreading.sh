#!/bin/bash

# OCP-23541 超线程验证脚本
# 用于验证OpenShift集群中所有节点的超线程禁用状态

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
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

# 显示帮助信息
show_help() {
    cat << EOF
OCP-23541 超线程验证脚本

用法:
    $0 --kubeconfig <path> [选项]

必需参数:
    -k, --kubeconfig <path>    Kubeconfig文件路径

可选参数:
    -n, --node <node-name>     指定单个节点进行验证
    -d, --detailed             显示详细的CPU信息
    -h, --help                 显示此帮助信息

示例:
    # 验证所有节点
    $0 --kubeconfig /path/to/kubeconfig

    # 验证特定节点
    $0 --kubeconfig /path/to/kubeconfig --node ip-10-0-130-76.us-east-2.compute.internal

    # 显示详细CPU信息
    $0 --kubeconfig /path/to/kubeconfig --detailed

EOF
}

# 默认参数
KUBECONFIG_PATH=""
NODE_NAME=""
DETAILED=false

# 解析命令行参数
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
            print_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 验证必需参数
if [[ -z "$KUBECONFIG_PATH" ]]; then
    print_error "必须指定 --kubeconfig 参数"
    show_help
    exit 1
fi

# 验证kubeconfig文件是否存在
if [[ ! -f "$KUBECONFIG_PATH" ]]; then
    print_error "Kubeconfig文件不存在: $KUBECONFIG_PATH"
    exit 1
fi

# 设置kubeconfig环境变量
export KUBECONFIG="$KUBECONFIG_PATH"

print_info "使用Kubeconfig: $KUBECONFIG_PATH"

# 检查集群连接
print_info "检查集群连接..."
if ! oc cluster-info >/dev/null 2>&1; then
    print_error "无法连接到集群，请检查kubeconfig文件"
    exit 1
fi
print_success "集群连接正常"

# 获取集群信息
CLUSTER_NAME=$(oc get clusterversion -o jsonpath='{.items[0].spec.clusterID}' 2>/dev/null || echo "unknown")
print_info "集群ID: $CLUSTER_NAME"

# 获取节点列表
get_nodes() {
    if [[ -n "$NODE_NAME" ]]; then
        # 验证指定节点是否存在
        if oc get node "$NODE_NAME" >/dev/null 2>&1; then
            echo "$NODE_NAME"
        else
            print_error "节点不存在: $NODE_NAME"
            exit 1
        fi
    else
        # 获取所有节点
        oc get nodes -o jsonpath='{.items[*].metadata.name}'
    fi
}

# 验证单个节点的超线程状态
verify_node_hyperthreading() {
    local node="$1"
    print_info "验证节点: $node"
    
    # 获取节点角色
    local roles=$(oc get node "$node" -o jsonpath='{.metadata.labels.node-role\.kubernetes\.io/worker}{" "}{.metadata.labels.node-role\.kubernetes\.io/master}' | tr -d ' ')
    if [[ -z "$roles" ]]; then
        roles="unknown"
    fi
    
    print_info "节点角色: $roles"
    
    # 创建debug pod并获取CPU信息
    print_info "创建debug pod获取CPU信息..."
    
    local cpu_info=""
    local debug_pod_name="debug-$(date +%s)"
    
    # 使用oc debug命令获取CPU信息
    if cpu_info=$(oc debug "node/$node" -- chroot /host cat /proc/cpuinfo 2>/dev/null); then
        # 分析CPU信息
        local siblings=$(echo "$cpu_info" | grep "siblings" | head -1 | awk '{print $3}')
        local cpu_cores=$(echo "$cpu_info" | grep "cpu cores" | head -1 | awk '{print $4}')
        local processor_count=$(echo "$cpu_info" | grep "^processor" | wc -l)
        local physical_cpus=$(echo "$cpu_info" | grep "physical id" | sort -u | wc -l)
        
        print_info "CPU信息分析:"
        echo "  - 逻辑CPU数量: $processor_count"
        echo "  - 物理CPU数量: $physical_cpus"
        echo "  - 每个物理CPU的siblings: $siblings"
        echo "  - 每个物理CPU的cores: $cpu_cores"
        
        # 判断超线程状态
        if [ "$siblings" = "$cpu_cores" ]; then
            print_success "✅ 超线程已禁用 (siblings == cpu_cores)"
            return 0
        else
            print_error "❌ 超线程可能未禁用 (siblings != cpu_cores)"
            return 1
        fi
        
        # 显示详细CPU信息
        if [ "$DETAILED" = true ]; then
            print_info "详细CPU信息:"
            echo "$cpu_info" | grep -E "(processor|physical id|siblings|cpu cores|model name)" | head -20
        fi
        
    else
        print_error "无法获取节点 $node 的CPU信息"
        return 1
    fi
}

# 验证MachineConfigPool
verify_machine_config_pools() {
    print_info "验证MachineConfigPool状态..."
    
    # 获取MachineConfigPool信息
    oc get machineconfigpools -o wide
    
    print_info "检查超线程禁用配置..."
    
    # 检查master和worker的配置
    for pool in master worker; do
        if oc get machineconfigpools "$pool" >/dev/null 2>&1; then
            local config_name=$(oc get machineconfigpools "$pool" -o jsonpath='{.status.configuration.name}')
            print_info "$pool 配置: $config_name"
            
            # 检查MachineConfig中是否包含disable-hyperthreading
            if oc get machineconfig "$config_name" -o yaml 2>/dev/null | grep -q "disable-hyperthreading"; then
                print_success "✅ $pool 节点包含超线程禁用配置"
            else
                print_warning "⚠️  $pool 节点可能未包含超线程禁用配置"
            fi
        fi
    done
}

# 主验证函数
main() {
    print_info "开始OCP-23541超线程验证..."
    
    # 获取节点列表
    local nodes=$(get_nodes)
    print_info "将验证以下节点: $nodes"
    
    # 验证MachineConfigPool
    verify_machine_config_pools
    echo ""
    
    # 验证每个节点的超线程状态
    local total_nodes=0
    local disabled_nodes=0
    local failed_nodes=0
    
    for node in $nodes; do
        echo "=================================="
        if verify_node_hyperthreading "$node"; then
            ((disabled_nodes++))
        else
            ((failed_nodes++))
        fi
        ((total_nodes++))
        echo ""
    done
    
    # 显示验证结果
    echo "=================================="
    print_info "验证结果总结:"
    echo "  总节点数: $total_nodes"
    echo "  超线程已禁用: $disabled_nodes"
    echo "  超线程未禁用: $failed_nodes"
    
    if [ $failed_nodes -eq 0 ]; then
        print_success "🎉 所有节点的超线程都已正确禁用！"
        exit 0
    else
        print_error "❌ 有 $failed_nodes 个节点的超线程可能未正确禁用"
        exit 1
    fi
}

# 执行主函数
main "$@"
