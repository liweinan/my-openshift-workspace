#!/bin/bash

# OCP-29781 清理脚本
# 销毁集群和VPC堆栈

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

# 销毁集群
destroy_cluster() {
    local cluster_dir="$1"
    
    if [[ ! -d "${cluster_dir}" ]]; then
        log_warning "集群目录不存在: ${cluster_dir}"
        return 0
    fi
    
    log_info "销毁集群: ${cluster_dir}"
    
    if [[ -f "${cluster_dir}/auth/kubeconfig" ]]; then
        export KUBECONFIG="${cluster_dir}/auth/kubeconfig"
        
        # 检查集群是否仍然存在
        if oc get nodes &> /dev/null; then
            log_info "集群仍然存在，开始销毁..."
            openshift-install --dir="${cluster_dir}" destroy cluster --log-level=info
            if [[ $? -eq 0 ]]; then
                log_success "集群 ${cluster_dir} 销毁成功"
            else
                log_error "集群 ${cluster_dir} 销毁失败"
                return 1
            fi
        else
            log_warning "集群 ${cluster_dir} 已不存在或无法访问"
        fi
    else
        log_warning "未找到kubeconfig文件: ${cluster_dir}/auth/kubeconfig"
    fi
}

# 删除VPC堆栈
delete_vpc_stack() {
    local stack_name="$1"
    
    if [[ -z "${stack_name}" ]]; then
        log_warning "未指定堆栈名称"
        return 0
    fi
    
    log_info "删除VPC堆栈: ${stack_name}"
    
    # 检查堆栈是否存在
    if aws cloudformation describe-stacks --stack-name "${stack_name}" &> /dev/null; then
        log_info "堆栈存在，开始删除..."
        aws cloudformation delete-stack --stack-name "${stack_name}"
        
        if [[ $? -eq 0 ]]; then
            log_info "等待堆栈删除完成..."
            aws cloudformation wait stack-delete-complete --stack-name "${stack_name}"
            
            if [[ $? -eq 0 ]]; then
                log_success "VPC堆栈 ${stack_name} 删除成功"
            else
                log_error "VPC堆栈 ${stack_name} 删除超时或失败"
                return 1
            fi
        else
            log_error "无法删除VPC堆栈 ${stack_name}"
            return 1
        fi
    else
        log_warning "VPC堆栈 ${stack_name} 不存在"
    fi
}

# 清理本地文件
cleanup_local_files() {
    log_info "清理本地文件..."
    
    # 删除集群目录
    for cluster_dir in cluster1 cluster2; do
        if [[ -d "${cluster_dir}" ]]; then
            log_info "删除集群目录: ${cluster_dir}"
            rm -rf "${cluster_dir}"
        fi
    done
    
    # 删除临时文件
    local temp_files=(
        "vpc-info.env"
        "stack-output.json"
        "install-config-cluster1.yaml.bak"
        "install-config-cluster2.yaml.bak"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            log_info "删除临时文件: ${file}"
            rm -f "${file}"
        fi
    done
    
    log_success "本地文件清理完成"
}

# 显示使用说明
show_usage() {
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help              显示此帮助信息"
    echo "  -c, --cluster-only      仅销毁集群，不删除VPC堆栈"
    echo "  -v, --vpc-only          仅删除VPC堆栈，不销毁集群"
    echo "  -s, --stack-name NAME   指定VPC堆栈名称"
    echo "  -f, --force             强制清理，不询问确认"
    echo ""
    echo "示例:"
    echo "  $0                      # 清理所有资源"
    echo "  $0 -c                   # 仅销毁集群"
    echo "  $0 -v -s my-vpc-stack   # 仅删除指定VPC堆栈"
    echo "  $0 -f                   # 强制清理所有资源"
}

# 确认清理操作
confirm_cleanup() {
    local force="$1"
    
    if [[ "${force}" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "此操作将销毁所有测试资源，包括："
    echo "  - OpenShift集群 (cluster1, cluster2)"
    echo "  - VPC堆栈和相关AWS资源"
    echo "  - 本地临时文件"
    echo
    read -p "确定要继续吗？(y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        log_info "操作已取消"
        exit 0
    fi
}

# 主函数
main() {
    local cluster_only="false"
    local vpc_only="false"
    local stack_name=""
    local force="false"
    
    # 解析命令行参数
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
                log_error "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 确认清理操作
    confirm_cleanup "${force}"
    
    log_info "开始清理OCP-29781测试资源"
    
    # 销毁集群
    if [[ "${vpc_only}" != "true" ]]; then
        log_info "销毁OpenShift集群..."
        destroy_cluster "cluster1"
        destroy_cluster "cluster2"
    fi
    
    # 删除VPC堆栈
    if [[ "${cluster_only}" != "true" ]]; then
        # 如果没有指定堆栈名称，尝试从环境文件读取
        if [[ -z "${stack_name}" && -f "vpc-info.env" ]]; then
            source vpc-info.env
            if [[ -n "${STACK_NAME:-}" ]]; then
                stack_name="${STACK_NAME}"
            fi
        fi
        
        # 如果仍然没有堆栈名称，尝试查找
        if [[ -z "${stack_name}" ]]; then
            log_info "查找VPC堆栈..."
            stack_name=$(aws cloudformation list-stacks \
                --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
                --query 'StackSummaries[?contains(StackName, `ocp29781-vpc`)].StackName' \
                --output text | head -1)
        fi
        
        if [[ -n "${stack_name}" ]]; then
            delete_vpc_stack "${stack_name}"
        else
            log_warning "未找到VPC堆栈"
        fi
    fi
    
    # 清理本地文件
    cleanup_local_files
    
    log_success "清理操作完成"
}

# 运行主函数
main "$@"
