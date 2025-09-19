#!/bin/bash

# OCP-29781 主测试脚本
# 执行完整的测试流程

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

# 测试步骤计数器
STEP_COUNT=0

# 执行测试步骤
run_step() {
    local step_name="$1"
    local step_command="$2"
    
    ((STEP_COUNT++))
    echo
    log_info "=== 步骤 ${STEP_COUNT}: ${step_name} ==="
    
    if eval "${step_command}"; then
        log_success "步骤 ${STEP_COUNT} 完成: ${step_name}"
        return 0
    else
        log_error "步骤 ${STEP_COUNT} 失败: ${step_name}"
        return 1
    fi
}

# 检查前置条件
check_prerequisites() {
    log_info "检查前置条件..."
    
    # 检查必要的工具
    local required_tools=("aws" "openshift-install" "oc" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" &> /dev/null; then
            log_error "未找到必要工具: ${tool}"
            return 1
        fi
    done
    
    # 检查AWS凭据
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS凭据未配置"
        return 1
    fi
    
    # 检查配置文件
    local required_files=(
        "install-config-cluster1.yaml"
        "install-config-cluster2.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "${file}" ]]; then
            log_error "未找到配置文件: ${file}"
            return 1
        fi
        
        # 检查配置文件中是否还有占位符
        if grep -q "YOUR_PULL_SECRET_HERE\|YOUR_SSH_PUBLIC_KEY_HERE" "${file}"; then
            log_error "配置文件 ${file} 包含占位符，请更新实际值"
            return 1
        fi
    done
    
    log_success "前置条件检查通过"
    return 0
}

# 显示使用说明
show_usage() {
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help              显示此帮助信息"
    echo "  -s, --step STEP         从指定步骤开始执行"
    echo "  -e, --end-step STEP     在指定步骤结束执行"
    echo "  -c, --cleanup-only      仅执行清理步骤"
    echo "  -f, --force             强制执行，不询问确认"
    echo ""
    echo "测试步骤:"
    echo "  1  - 创建VPC和子网"
    echo "  2  - 创建集群1"
    echo "  3  - 集群1健康检查"
    echo "  4  - 创建集群2"
    echo "  5  - 集群2健康检查"
    echo "  6  - 安全组检查"
    echo "  7  - 网络隔离测试"
    echo "  8  - 清理资源"
    echo ""
    echo "示例:"
    echo "  $0                      # 执行完整测试"
    echo "  $0 -s 3                 # 从步骤3开始"
    echo "  $0 -s 1 -e 5            # 执行步骤1-5"
    echo "  $0 -c                   # 仅清理资源"
}

# 主函数
main() {
    local start_step=1
    local end_step=8
    local cleanup_only=false
    local force=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -s|--step)
                start_step="$2"
                shift 2
                ;;
            -e|--end-step)
                end_step="$2"
                shift 2
                ;;
            -c|--cleanup-only)
                cleanup_only=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            *)
                log_error "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 确认执行
    if [[ "${force}" != "true" ]]; then
        echo
        log_warning "此脚本将执行OCP-29781测试，包括："
        echo "  - 创建VPC和子网"
        echo "  - 创建两个OpenShift集群"
        echo "  - 执行各种验证测试"
        echo "  - 清理所有资源"
        echo
        read -p "确定要继续吗？(y/N): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "操作已取消"
            exit 0
        fi
    fi
    
    log_info "开始OCP-29781测试"
    log_info "执行步骤: ${start_step} - ${end_step}"
    echo
    
    # 检查前置条件
    if ! check_prerequisites; then
        log_error "前置条件检查失败"
        exit 1
    fi
    
    local test_failed=false
    
    # 执行测试步骤
    if [[ "${cleanup_only}" == "true" ]]; then
        # 仅执行清理
        if ! run_step "清理资源" "./cleanup.sh -f"; then
            test_failed=true
        fi
    else
        # 执行完整测试流程
        if [[ ${start_step} -le 1 && ${end_step} -ge 1 ]]; then
            if ! run_step "创建VPC和子网" "./create-vpc.sh"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 2 && ${end_step} -ge 2 ]]; then
            if ! run_step "创建集群1" "mkdir -p cluster1 && cp install-config-cluster1.yaml cluster1/install-config.yaml && openshift-install --dir=cluster1 create cluster"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 3 && ${end_step} -ge 3 ]]; then
            if ! run_step "集群1健康检查" "./health-check.sh cluster1"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 4 && ${end_step} -ge 4 ]]; then
            if ! run_step "创建集群2" "mkdir -p cluster2 && cp install-config-cluster2.yaml cluster2/install-config.yaml && openshift-install --dir=cluster2 create cluster"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 5 && ${end_step} -ge 5 ]]; then
            if ! run_step "集群2健康检查" "./health-check.sh cluster2"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 6 && ${end_step} -ge 6 ]]; then
            if ! run_step "安全组检查" "./security-group-check.sh cluster1 10.134.0.0/16 && ./security-group-check.sh cluster2 10.190.0.0/16"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 7 && ${end_step} -ge 7 ]]; then
            if ! run_step "网络隔离测试" "./network-isolation-test.sh cluster1 cluster2"; then
                test_failed=true
            fi
        fi
        
        if [[ ${start_step} -le 8 && ${end_step} -ge 8 ]]; then
            if ! run_step "清理资源" "./cleanup.sh -f"; then
                test_failed=true
            fi
        fi
    fi
    
    # 总结结果
    echo
    if [[ "${test_failed}" == "true" ]]; then
        log_error "测试失败"
        exit 1
    else
        log_success "测试完成"
        exit 0
    fi
}

# 运行主函数
main "$@"
