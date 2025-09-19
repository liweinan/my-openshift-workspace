#!/bin/bash

# OCP-29781 安全组检查脚本
# 验证安全组规则与机器CIDR匹配

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

# 获取集群infraID
get_infra_id() {
    local cluster_dir="$1"
    local metadata_file="${cluster_dir}/metadata.json"
    
    if [[ ! -f "${metadata_file}" ]]; then
        log_error "未找到metadata文件: ${metadata_file}"
        return 1
    fi
    
    local infra_id
    infra_id=$(jq -r '.infraID' "${metadata_file}")
    
    if [[ "${infra_id}" == "null" || -z "${infra_id}" ]]; then
        log_error "无法从metadata文件获取infraID"
        return 1
    fi
    
    echo "${infra_id}"
}

# 获取集群的安全组ID
get_security_groups() {
    local infra_id="$1"
    local region="${AWS_REGION:-us-east-2}"
    
    log_info "获取集群 ${infra_id} 的安全组..."
    
    local sg_ids
    sg_ids=$(aws ec2 describe-instances \
        --region "${region}" \
        --filters "Name=tag:kubernetes.io/cluster/${infra_id},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    if [[ -z "${sg_ids}" ]]; then
        log_error "未找到集群 ${infra_id} 的安全组"
        return 1
    fi
    
    echo "${sg_ids}"
}

# 检查安全组规则
check_security_group_rules() {
    local sg_id="$1"
    local expected_cidr="$2"
    local region="${AWS_REGION:-us-east-2}"
    
    log_info "检查安全组 ${sg_id} 的规则..."
    
    # 获取安全组详细信息
    local sg_info
    sg_info=$(aws ec2 describe-security-groups \
        --region "${region}" \
        --group-ids "${sg_id}" \
        --output json)
    
    # 检查master节点需要的端口
    local master_ports=(
        "6443:tcp"
        "22623:tcp"
        "22:tcp"
        "-1:icmp"
    )
    
    # 检查worker节点需要的端口
    local worker_ports=(
        "22:tcp"
        "-1:icmp"
    )
    
    local all_checks_passed=true
    
    # 检查所有端口规则
    for port_info in "${master_ports[@]}" "${worker_ports[@]}"; do
        local port=$(echo "${port_info}" | cut -d: -f1)
        local protocol=$(echo "${port_info}" | cut -d: -f2)
        
        # 检查规则是否存在且CIDR匹配
        local rule_exists
        rule_exists=$(echo "${sg_info}" | jq -r --arg port "${port}" --arg protocol "${protocol}" --arg cidr "${expected_cidr}" \
            '.SecurityGroups[].IpPermissions[] | 
            select(.IpProtocol == $protocol and .FromPort == ($port | tonumber) and .ToPort == ($port | tonumber)) |
            .IpRanges[] | select(.CidrIp == $cidr) | .CidrIp')
        
        if [[ -n "${rule_exists}" ]]; then
            log_success "端口 ${port}/${protocol} 规则正确，CIDR: ${expected_cidr}"
        else
            log_error "端口 ${port}/${protocol} 规则缺失或CIDR不匹配，期望: ${expected_cidr}"
            all_checks_passed=false
        fi
    done
    
    if [[ "${all_checks_passed}" == "true" ]]; then
        log_success "安全组 ${sg_id} 所有规则检查通过"
        return 0
    else
        log_error "安全组 ${sg_id} 规则检查失败"
        return 1
    fi
}

# 显示安全组详细信息
show_security_group_details() {
    local sg_id="$1"
    local region="${AWS_REGION:-us-east-2}"
    
    log_info "安全组 ${sg_id} 的详细信息:"
    
    aws ec2 describe-security-groups \
        --region "${region}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[].IpPermissions[] | {IpProtocol:.IpProtocol, FromPort:.FromPort, ToPort:.ToPort, IpRanges:[.IpRanges[].CidrIp]}' \
        --output table
}

# 检查集群安全组
check_cluster_security_groups() {
    local cluster_dir="$1"
    local expected_cidr="$2"
    
    log_info "检查集群 ${cluster_dir} 的安全组..."
    
    # 获取infraID
    local infra_id
    infra_id=$(get_infra_id "${cluster_dir}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    log_info "集群infraID: ${infra_id}"
    
    # 获取安全组ID列表
    local sg_ids
    sg_ids=$(get_security_groups "${infra_id}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    log_info "找到安全组: ${sg_ids}"
    
    local all_checks_passed=true
    
    # 检查每个安全组
    while IFS= read -r sg_id; do
        if [[ -n "${sg_id}" ]]; then
            log_info "检查安全组: ${sg_id}"
            show_security_group_details "${sg_id}"
            
            if ! check_security_group_rules "${sg_id}" "${expected_cidr}"; then
                all_checks_passed=false
            fi
            echo
        fi
    done <<< "${sg_ids}"
    
    if [[ "${all_checks_passed}" == "true" ]]; then
        log_success "集群 ${cluster_dir} 所有安全组检查通过"
        return 0
    else
        log_error "集群 ${cluster_dir} 安全组检查失败"
        return 1
    fi
}

# 显示使用说明
show_usage() {
    echo "使用方法: $0 <cluster_dir> <expected_cidr>"
    echo ""
    echo "参数:"
    echo "  cluster_dir    - 集群安装目录 (例如: cluster1, cluster2)"
    echo "  expected_cidr  - 期望的机器CIDR (例如: 10.134.0.0/16, 10.190.0.0/16)"
    echo ""
    echo "环境变量:"
    echo "  AWS_REGION     - AWS区域 (默认: us-east-2)"
    echo ""
    echo "示例:"
    echo "  $0 cluster1 10.134.0.0/16"
    echo "  $0 cluster2 10.190.0.0/16"
    echo "  AWS_REGION=us-west-2 $0 cluster1 10.134.0.0/16"
}

# 主函数
main() {
    if [[ $# -ne 2 ]]; then
        show_usage
        exit 1
    fi
    
    local cluster_dir="$1"
    local expected_cidr="$2"
    
    # 验证集群目录
    if [[ ! -d "${cluster_dir}" ]]; then
        log_error "集群目录不存在: ${cluster_dir}"
        exit 1
    fi
    
    # 验证CIDR格式
    if [[ ! "${expected_cidr}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "无效的CIDR格式: ${expected_cidr}"
        exit 1
    fi
    
    log_info "开始安全组检查"
    log_info "集群目录: ${cluster_dir}"
    log_info "期望CIDR: ${expected_cidr}"
    log_info "AWS区域: ${AWS_REGION:-us-east-2}"
    echo
    
    # 检查安全组
    if check_cluster_security_groups "${cluster_dir}" "${expected_cidr}"; then
        log_success "安全组检查完成 - 所有检查通过"
        exit 0
    else
        log_error "安全组检查完成 - 发现问题"
        exit 1
    fi
}

# 运行主函数
main "$@"
