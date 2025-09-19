#!/bin/bash

# 简化的安全组验证脚本

set -euo pipefail

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
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_cluster_security_groups() {
    local cluster_name=$1
    local infra_id=$2
    local machine_cidr=$3
    
    log_info "=== 检查 ${cluster_name} (${infra_id}) ==="
    log_info "Machine CIDR: ${machine_cidr}"
    echo
    
    # 获取安全组ID
    local security_groups
    security_groups=$(aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters "Name=tag:kubernetes.io/cluster/${infra_id},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    log_info "安全组ID: ${security_groups}"
    echo
    
    # 检查每个安全组
    for sg_id in $security_groups; do
        check_single_security_group "${sg_id}" "${machine_cidr}"
    done
    echo
}

check_single_security_group() {
    local sg_id=$1
    local expected_cidr=$2
    
    log_info "检查安全组: ${sg_id}"
    
    # 获取安全组信息
    local sg_info
    sg_info=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --output json)
    
    local sg_name
    sg_name=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].GroupName')
    local sg_description
    sg_description=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].Description')
    
    log_info "名称: ${sg_name}"
    log_info "描述: ${sg_description}"
    
    # 检查关键端口
    if [[ "${sg_name}" == *"controlplane"* ]]; then
        log_info "类型: Master/Control Plane"
        check_master_ports "${sg_info}" "${expected_cidr}"
    elif [[ "${sg_name}" == *"node"* ]]; then
        log_info "类型: Worker Node"
        check_worker_ports "${sg_info}" "${expected_cidr}"
    elif [[ "${sg_name}" == *"lb"* ]]; then
        log_info "类型: Load Balancer (跳过验证)"
    else
        log_warning "未知类型"
    fi
    
    echo "----------------------------------------"
}

check_master_ports() {
    local sg_info=$1
    local expected_cidr=$2
    
    log_info "验证Master端口:"
    
    # 检查6443/tcp
    check_port_in_sg "${sg_info}" "tcp" "6443" "6443" "${expected_cidr}" "API Server"
    
    # 检查22623/tcp
    check_port_in_sg "${sg_info}" "tcp" "22623" "22623" "${expected_cidr}" "Machine Config Server"
    
    # 检查22/tcp
    check_port_in_sg "${sg_info}" "tcp" "22" "22" "${expected_cidr}" "SSH"
    
    # 检查ICMP
    check_port_in_sg "${sg_info}" "icmp" "-1" "-1" "${expected_cidr}" "ICMP"
}

check_worker_ports() {
    local sg_info=$1
    local expected_cidr=$2
    
    log_info "验证Worker端口:"
    
    # 检查22/tcp
    check_port_in_sg "${sg_info}" "tcp" "22" "22" "${expected_cidr}" "SSH"
    
    # 检查ICMP
    check_port_in_sg "${sg_info}" "icmp" "-1" "-1" "${expected_cidr}" "ICMP"
}

check_port_in_sg() {
    local sg_info=$1
    local protocol=$2
    local from_port=$3
    local to_port=$4
    local expected_cidr=$5
    local port_name=$6
    
    # 查找匹配的端口规则
    local matching_rules
    matching_rules=$(echo "${sg_info}" | jq -r --arg protocol "${protocol}" --arg from_port "${from_port}" --arg to_port "${to_port}" \
        '.SecurityGroups[0].IpPermissions[] | 
        select(.IpProtocol == $protocol and .FromPort == ($from_port | tonumber) and .ToPort == ($to_port | tonumber)) | 
        .IpRanges[].CidrIp')
    
    if [[ -z "${matching_rules}" ]]; then
        log_warning "  ${port_name} (${protocol}:${from_port}-${to_port}): 未找到规则"
        return
    fi
    
    # 检查是否包含期望的CIDR
    if echo "${matching_rules}" | grep -q "${expected_cidr}"; then
        log_success "  ${port_name} (${protocol}:${from_port}-${to_port}): ✅ 包含 ${expected_cidr}"
    else
        log_error "  ${port_name} (${protocol}:${from_port}-${to_port}): ❌ 缺少 ${expected_cidr}"
        log_info "    实际CIDR: ${matching_rules}"
    fi
}

# 主函数
main() {
    log_info "开始安全组验证"
    echo "=========================================="
    
    check_cluster_security_groups "集群1" "${CLUSTER1_INFRA_ID}" "${CLUSTER1_MACHINE_CIDR}"
    check_cluster_security_groups "集群2" "${CLUSTER2_INFRA_ID}" "${CLUSTER2_MACHINE_CIDR}"
    
    log_success "安全组验证完成！"
}

main "$@"
