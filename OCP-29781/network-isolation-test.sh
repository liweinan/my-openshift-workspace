#!/bin/bash

# OCP-29781 网络隔离测试脚本
# 验证两个集群之间无法通信

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
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

# 获取集群master节点IP
get_master_ips() {
    local cluster_dir="$1"
    local kubeconfig="${cluster_dir}/auth/kubeconfig"
    
    if [[ ! -f "${kubeconfig}" ]]; then
        log_error "未找到kubeconfig文件: ${kubeconfig}"
        return 1
    fi
    
    export KUBECONFIG="${kubeconfig}"
    
    local master_ips
    master_ips=$(oc get nodes -o wide --no-headers | awk '$3 == "master" {print $6}')
    
    if [[ -z "${master_ips}" ]]; then
        log_error "未找到master节点"
        return 1
    fi
    
    echo "${master_ips}"
}

# 部署SSH bastion
deploy_ssh_bastion() {
    local cluster_dir="$1"
    local kubeconfig="${cluster_dir}/auth/kubeconfig"
    
    log_info "部署SSH bastion到集群 ${cluster_dir}..."
    
    export KUBECONFIG="${kubeconfig}"
    
    # 检查bastion是否已存在
    if oc get service ssh-bastion -n openshift-ssh-bastion &> /dev/null; then
        log_info "SSH bastion已存在"
        return 0
    fi
    
    # 部署SSH bastion
    curl -s https://raw.githubusercontent.com/eparis/ssh-bastion/master/deploy/deploy.sh | bash
    
    if [[ $? -eq 0 ]]; then
        log_success "SSH bastion部署成功"
    else
        log_error "SSH bastion部署失败"
        return 1
    fi
}

# 通过bastion执行远程命令
run_remote_command() {
    local cluster_dir="$1"
    local target_ip="$2"
    local command="$3"
    local kubeconfig="${cluster_dir}/auth/kubeconfig"
    
    export KUBECONFIG="${kubeconfig}"
    
    # 获取bastion hostname
    local bastion_hostname
    bastion_hostname=$(oc get service -n openshift-ssh-bastion ssh-bastion -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    if [[ -z "${bastion_hostname}" ]]; then
        log_error "无法获取bastion hostname"
        return 1
    fi
    
    # 获取SSH密钥路径
    local ssh_key="${HOME}/.ssh/id_rsa"
    if [[ ! -f "${ssh_key}" ]]; then
        log_error "未找到SSH密钥: ${ssh_key}"
        return 1
    fi
    
    # 构建SSH命令
    local ssh_cmd="ssh -i \"${ssh_key}\" -t -t -o StrictHostKeyChecking=no -o ProxyCommand='ssh -i \"${ssh_key}\" -A -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -W %h:%p core@${bastion_hostname}' core@${target_ip} ${command}"
    
    log_info "执行远程命令: ${command}"
    log_info "目标IP: ${target_ip}"
    
    # 执行命令
    eval "${ssh_cmd}"
}

# 测试网络连通性
test_network_connectivity() {
    local source_cluster="$1"
    local target_cluster="$2"
    local ping_count="${3:-3}"
    
    log_info "测试网络连通性: ${source_cluster} -> ${target_cluster}"
    
    # 获取目标集群的master IP
    local target_ips
    target_ips=$(get_master_ips "${target_cluster}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # 获取源集群的master IP
    local source_ips
    source_ips=$(get_master_ips "${source_cluster}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # 选择第一个master节点作为源
    local source_ip
    source_ip=$(echo "${source_ips}" | head -1)
    
    # 选择第一个master节点作为目标
    local target_ip
    target_ip=$(echo "${target_ips}" | head -1)
    
    log_info "源IP: ${source_ip}"
    log_info "目标IP: ${target_ip}"
    
    # 部署SSH bastion到源集群
    if ! deploy_ssh_bastion "${source_cluster}"; then
        return 1
    fi
    
    # 执行ping测试
    log_info "执行ping测试..."
    local ping_output
    ping_output=$(run_remote_command "${source_cluster}" "${source_ip}" "ping -c ${ping_count} ${target_ip}" 2>&1)
    local ping_result=$?
    
    echo "Ping输出:"
    echo "${ping_output}"
    echo
    
    # 分析结果
    if echo "${ping_output}" | grep -q "100% packet loss"; then
        log_success "网络隔离测试通过 - 100% packet loss"
        return 0
    elif [[ ${ping_result} -eq 0 ]]; then
        log_error "网络隔离测试失败 - 可以ping通目标"
        return 1
    else
        log_warning "网络隔离测试结果不明确 - ping命令失败但未显示100% packet loss"
        return 1
    fi
}

# 显示使用说明
show_usage() {
    echo "使用方法: $0 <cluster1_dir> <cluster2_dir> [ping_count]"
    echo ""
    echo "参数:"
    echo "  cluster1_dir  - 第一个集群目录 (例如: cluster1)"
    echo "  cluster2_dir  - 第二个集群目录 (例如: cluster2)"
    echo "  ping_count    - ping次数 (默认: 3)"
    echo ""
    echo "示例:"
    echo "  $0 cluster1 cluster2"
    echo "  $0 cluster1 cluster2 5"
}

# 主函数
main() {
    if [[ $# -lt 2 || $# -gt 3 ]]; then
        show_usage
        exit 1
    fi
    
    local cluster1_dir="$1"
    local cluster2_dir="$2"
    local ping_count="${3:-3}"
    
    # 验证集群目录
    for cluster_dir in "${cluster1_dir}" "${cluster2_dir}"; do
        if [[ ! -d "${cluster_dir}" ]]; then
            log_error "集群目录不存在: ${cluster_dir}"
            exit 1
        fi
        
        local kubeconfig="${cluster_dir}/auth/kubeconfig"
        if [[ ! -f "${kubeconfig}" ]]; then
            log_error "未找到kubeconfig文件: ${kubeconfig}"
            exit 1
        fi
    done
    
    log_info "开始网络隔离测试"
    log_info "集群1: ${cluster1_dir}"
    log_info "集群2: ${cluster2_dir}"
    log_info "Ping次数: ${ping_count}"
    echo
    
    local all_tests_passed=true
    
    # 测试集群1到集群2的连通性
    log_info "=== 测试集群1到集群2的连通性 ==="
    if ! test_network_connectivity "${cluster1_dir}" "${cluster2_dir}" "${ping_count}"; then
        all_tests_passed=false
    fi
    echo
    
    # 测试集群2到集群1的连通性
    log_info "=== 测试集群2到集群1的连通性 ==="
    if ! test_network_connectivity "${cluster2_dir}" "${cluster1_dir}" "${ping_count}"; then
        all_tests_passed=false
    fi
    echo
    
    # 总结结果
    if [[ "${all_tests_passed}" == "true" ]]; then
        log_success "网络隔离测试完成 - 所有测试通过"
        log_success "两个集群之间无法通信，网络隔离正常"
        exit 0
    else
        log_error "网络隔离测试完成 - 发现问题"
        log_error "两个集群之间可以通信，网络隔离失败"
        exit 1
    fi
}

# 运行主函数
main "$@"
