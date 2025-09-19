#!/bin/bash

# OCP-29781 安全组验证脚本
# 验证安全组配置是否与machine CIDRs匹配

set -euo pipefail

# 配置变量
AWS_REGION="us-east-1"
CLUSTER1_INFRA_ID="weli-test-a-p6fbf"
CLUSTER2_INFRA_ID="weli-test-b-2vgnm"
CLUSTER1_MACHINE_CIDR="10.134.0.0/16"
CLUSTER2_MACHINE_CIDR="10.190.0.0/16"

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

# 验证单个集群的安全组
verify_cluster_security_groups() {
    local cluster_name=$1
    local infra_id=$2
    local machine_cidr=$3
    
    log_info "验证集群: ${cluster_name} (${infra_id})"
    log_info "Machine CIDR: ${machine_cidr}"
    echo
    
    # 获取所有安全组ID
    log_info "获取安全组ID..."
    local security_groups
    security_groups=$(aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters "Name=tag:kubernetes.io/cluster/${infra_id},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    if [[ -z "${security_groups}" ]]; then
        log_error "未找到集群 ${cluster_name} 的安全组"
        return 1
    fi
    
    log_info "找到安全组: ${security_groups}"
    echo
    
    # 检查每个安全组
    for sg_id in $security_groups; do
        verify_security_group "${sg_id}" "${machine_cidr}" "${cluster_name}"
    done
}

# 验证单个安全组
verify_security_group() {
    local sg_id=$1
    local expected_cidr=$2
    local cluster_name=$3
    
    log_info "检查安全组: ${sg_id}"
    
    # 获取安全组详细信息
    local sg_info
    sg_info=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0]')
    
    # 获取安全组名称和描述
    local sg_name
    sg_name=$(echo "${sg_info}" | jq -r '.GroupName')
    local sg_description
    sg_description=$(echo "${sg_info}" | jq -r '.Description')
    
    log_info "安全组名称: ${sg_name}"
    log_info "描述: ${sg_description}"
    
    # 判断是master还是worker安全组
    local sg_type="unknown"
    if [[ "${sg_description}" == *"controlplane"* ]] || [[ "${sg_name}" == *"controlplane"* ]]; then
        sg_type="master"
    elif [[ "${sg_description}" == *"node"* ]] || [[ "${sg_name}" == *"node"* ]]; then
        sg_type="worker"
    elif [[ "${sg_description}" == *"lb"* ]] || [[ "${sg_name}" == *"lb"* ]]; then
        sg_type="loadbalancer"
    fi
    
    log_info "安全组类型: ${sg_type}"
    
    # 检查关键端口的CIDR配置
    if [[ "${sg_type}" == "master" ]]; then
        verify_master_ports "${sg_id}" "${expected_cidr}"
    elif [[ "${sg_type}" == "worker" ]]; then
        verify_worker_ports "${sg_id}" "${expected_cidr}"
    elif [[ "${sg_type}" == "loadbalancer" ]]; then
        log_info "跳过Load Balancer安全组验证"
    else
        log_warning "无法确定安全组类型，跳过端口验证"
    fi
    
    echo "----------------------------------------"
}

# 验证master端口
verify_master_ports() {
    local sg_id=$1
    local expected_cidr=$2
    
    log_info "验证master端口配置..."
    
    # 检查6443/tcp (API Server)
    check_port_cidr "${sg_id}" "tcp" "6443" "6443" "${expected_cidr}" "API Server"
    
    # 检查22623/tcp (Machine Config Server)
    check_port_cidr "${sg_id}" "tcp" "22623" "22623" "${expected_cidr}" "Machine Config Server"
    
    # 检查22/tcp (SSH)
    check_port_cidr "${sg_id}" "tcp" "22" "22" "${expected_cidr}" "SSH"
    
    # 检查ICMP
    check_port_cidr "${sg_id}" "icmp" "-1" "-1" "${expected_cidr}" "ICMP"
}

# 验证worker端口
verify_worker_ports() {
    local sg_id=$1
    local expected_cidr=$2
    
    log_info "验证worker端口配置..."
    
    # 检查22/tcp (SSH)
    check_port_cidr "${sg_id}" "tcp" "22" "22" "${expected_cidr}" "SSH"
    
    # 检查ICMP
    check_port_cidr "${sg_id}" "icmp" "-1" "-1" "${expected_cidr}" "ICMP"
}

# 检查特定端口的CIDR配置
check_port_cidr() {
    local sg_id=$1
    local protocol=$2
    local from_port=$3
    local to_port=$4
    local expected_cidr=$5
    local port_name=$6
    
    # 获取该端口的CIDR配置
    local actual_cidrs
    actual_cidrs=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query "SecurityGroups[0].IpPermissions[?IpProtocol=='${protocol}' && FromPort==\`${from_port}\` && ToPort==\`${to_port}\`].IpRanges[].CidrIp" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "${actual_cidrs}" ]]; then
        log_warning "  ${port_name} (${protocol}:${from_port}-${to_port}): 未找到CIDR配置"
        return
    fi
    
    # 检查是否包含期望的CIDR
    if echo "${actual_cidrs}" | grep -q "${expected_cidr}"; then
        log_success "  ${port_name} (${protocol}:${from_port}-${to_port}): ✅ 包含期望CIDR ${expected_cidr}"
    else
        log_error "  ${port_name} (${protocol}:${from_port}-${to_port}): ❌ 缺少期望CIDR ${expected_cidr}"
        log_info "    实际CIDR: ${actual_cidrs}"
    fi
}

# 显示安全组详细信息
show_security_group_details() {
    local sg_id=$1
    local cluster_name=$2
    
    log_info "安全组 ${sg_id} 详细信息:"
    
    aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[]' \
        --output json | jq '[.[] | {IpProtocol:.IpProtocol, FromPort: .FromPort, ToPort: .ToPort, IpRanges:[.IpRanges[].CidrIp]}]'
}

# 主函数
main() {
    log_info "开始OCP-29781安全组验证"
    echo "=========================================="
    
    # 验证集群1
    log_info "验证集群1安全组配置"
    echo "----------------------------------------"
    verify_cluster_security_groups "集群1" "${CLUSTER1_INFRA_ID}" "${CLUSTER1_MACHINE_CIDR}"
    echo
    
    # 验证集群2
    log_info "验证集群2安全组配置"
    echo "----------------------------------------"
    verify_cluster_security_groups "集群2" "${CLUSTER2_INFRA_ID}" "${CLUSTER2_MACHINE_CIDR}"
    echo
    
    log_success "安全组验证完成！"
    echo
    log_info "如果看到 ✅ 表示配置正确"
    log_info "如果看到 ❌ 表示配置有问题"
}

# 运行主函数
main "$@"
