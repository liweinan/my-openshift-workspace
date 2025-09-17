#!/bin/bash

# OCP-25698 集群扩容脚本
# 用于扩展现有的OpenShift集群工作节点

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
OCP-25698 集群扩容脚本

用法:
    $0 --kubeconfig <path> [选项]

必需参数:
    -k, --kubeconfig <path>    Kubeconfig文件路径

可选参数:
    -r, --replicas <number>    目标副本数 (默认: 4)
    -n, --namespace <name>     MachineSet命名空间 (默认: openshift-machine-api)
    -m, --machineset <name>   指定MachineSet名称 (可选，不指定则列出所有)
    -w, --wait                 等待扩容完成
    -t, --timeout <seconds>    等待超时时间 (默认: 600秒)
    -d, --dry-run              仅显示将要执行的操作，不实际执行
    -h, --help                 显示此帮助信息

示例:
    # 基本用法 - 扩容到4个副本
    $0 --kubeconfig /path/to/kubeconfig

    # 扩容到6个副本
    $0 --kubeconfig /path/to/kubeconfig --replicas 6

    # 指定MachineSet名称
    $0 --kubeconfig /path/to/kubeconfig --machineset my-cluster-abc123-worker-us-east-2a

    # 等待扩容完成
    $0 --kubeconfig /path/to/kubeconfig --wait

    # 干运行模式
    $0 --kubeconfig /path/to/kubeconfig --dry-run

EOF
}

# 默认参数
KUBECONFIG_PATH=""
REPLICAS=4
NAMESPACE="openshift-machine-api"
MACHINESET_NAME=""
WAIT_FOR_COMPLETION=false
TIMEOUT=600
DRY_RUN=false

# 解析命令行参数
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

# 验证副本数
if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]] || [[ "$REPLICAS" -lt 1 ]]; then
    print_error "副本数必须是正整数: $REPLICAS"
    exit 1
fi

# 设置kubeconfig环境变量
export KUBECONFIG="$KUBECONFIG_PATH"

print_info "使用Kubeconfig: $KUBECONFIG_PATH"
print_info "目标副本数: $REPLICAS"
print_info "命名空间: $NAMESPACE"

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

# 列出所有MachineSet
list_machinesets() {
    print_info "获取MachineSet列表..."
    oc get machinesets -n "$NAMESPACE" -o wide
}

# 获取MachineSet详细信息
get_machineset_info() {
    local machineset_name="$1"
    print_info "获取MachineSet详细信息: $machineset_name"
    oc describe machineset "$machineset_name" -n "$NAMESPACE"
}

# 扩容MachineSet
scale_machineset() {
    local machineset_name="$1"
    local target_replicas="$2"
    
    print_info "扩容MachineSet: $machineset_name 到 $target_replicas 个副本"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "[DRY RUN] 将执行: oc scale machineset $machineset_name -n $NAMESPACE --replicas=$target_replicas"
        return 0
    fi
    
    if oc scale machineset "$machineset_name" -n "$NAMESPACE" --replicas="$target_replicas"; then
        print_success "MachineSet扩容命令执行成功"
    else
        print_error "MachineSet扩容命令执行失败"
        return 1
    fi
}

# 等待扩容完成
wait_for_scaling() {
    local machineset_name="$1"
    local target_replicas="$2"
    local timeout="$3"
    
    print_info "等待扩容完成 (超时: ${timeout}秒)..."
    
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        local current_replicas=$(oc get machineset "$machineset_name" -n "$NAMESPACE" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
        local ready_replicas=$(oc get machineset "$machineset_name" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        
        print_info "当前副本数: $current_replicas, 就绪副本数: $ready_replicas, 目标: $target_replicas"
        
        if [[ "$ready_replicas" -eq "$target_replicas" ]]; then
            print_success "扩容完成！所有 $target_replicas 个副本都已就绪"
            return 0
        fi
        
        sleep 10
    done
    
    print_warning "等待超时，扩容可能仍在进行中"
    return 1
}

# 显示节点状态
show_node_status() {
    print_info "当前节点状态:"
    oc get nodes -o wide
}

# 显示Machine状态
show_machine_status() {
    print_info "当前Machine状态:"
    oc get machines -n "$NAMESPACE" -o wide
}

# 主逻辑
main() {
    print_info "开始集群扩容操作..."
    
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
        print_info "未指定MachineSet名称，将列出所有可用的MachineSet"
        
        local machinesets=$(oc get machinesets -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
        
        if [[ -z "$machinesets" ]]; then
            print_error "未找到任何MachineSet"
            exit 1
        fi
        
        print_info "找到以下MachineSet:"
        for ms in $machinesets; do
            local current_replicas=$(oc get machineset "$ms" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
            local ready_replicas=$(oc get machineset "$ms" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            echo "  - $ms (当前: $current_replicas, 就绪: $ready_replicas)"
        done
        
        if [[ "$DRY_RUN" == "true" ]]; then
            print_warning "[DRY RUN] 将扩容所有MachineSet到 $REPLICAS 个副本"
            for ms in $machinesets; do
                print_warning "[DRY RUN] 将执行: oc scale machineset $ms -n $NAMESPACE --replicas=$REPLICAS"
            done
        else
            # 扩容所有MachineSet
            for ms in $machinesets; do
                echo ""
                print_info "扩容MachineSet: $ms"
                scale_machineset "$ms" "$REPLICAS"
                
                if [[ "$WAIT_FOR_COMPLETION" == "true" ]]; then
                    wait_for_scaling "$ms" "$REPLICAS" "$TIMEOUT"
                fi
            done
        fi
    fi
    
    echo ""
    print_info "扩容操作完成"
    
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
