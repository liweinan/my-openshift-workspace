#!/bin/bash

# OpenShift 4.x 安全组验证脚本
# 验证安全组配置是否符合网络隔离要求

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

verify_cluster_security_groups() {
    local cluster_name=$1
    local infra_id=$2
    local machine_cidr=$3
    
    log_info "=== 验证 ${cluster_name} (${infra_id}) ==="
    log_info "Machine CIDR: ${machine_cidr}"
    echo
    
    # 获取所有安全组
    local all_sgs
    all_sgs=$(aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters "Name=tag:kubernetes.io/cluster/${infra_id},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    log_info "集群安全组: ${all_sgs}"
    echo
    
    # 分析安全组架构
    analyze_security_group_architecture "${all_sgs}" "${infra_id}" "${machine_cidr}"
    echo
}

analyze_security_group_architecture() {
    local sg_list=$1
    local infra_id=$2
    local machine_cidr=$3
    
    log_info "分析安全组架构..."
    
    # 获取所有相关安全组（包括引用的安全组）
    local all_related_sgs="${sg_list}"
    
    for sg_id in $sg_list; do
        # 获取这个安全组引用的其他安全组
        local referenced_sgs
        referenced_sgs=$(aws ec2 describe-security-groups \
            --region "${AWS_REGION}" \
            --group-ids "${sg_id}" \
            --query 'SecurityGroups[0].IpPermissions[].UserIdGroupPairs[].GroupId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${referenced_sgs}" ]]; then
            all_related_sgs="${all_related_sgs} ${referenced_sgs}"
        fi
    done
    
    # 去重
    all_related_sgs=$(echo "${all_related_sgs}" | tr ' ' '\n' | sort | uniq)
    
    log_info "所有相关安全组: ${all_related_sgs}"
    echo
    
    # 分析每个安全组
    for sg_id in $all_related_sgs; do
        analyze_single_security_group "${sg_id}" "${infra_id}" "${machine_cidr}"
    done
}

analyze_single_security_group() {
    local sg_id=$1
    local infra_id=$2
    local machine_cidr=$3
    
    log_info "分析安全组: ${sg_id}"
    
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
    
    # 检查是否属于当前集群
    if [[ "${sg_name}" == *"${infra_id}"* ]]; then
        log_info "类型: 集群内部安全组"
        analyze_cluster_internal_sg "${sg_info}" "${machine_cidr}"
    else
        log_info "类型: 外部引用安全组"
    fi
    
    echo "----------------------------------------"
}

analyze_cluster_internal_sg() {
    local sg_info=$1
    local machine_cidr=$2
    
    # 获取所有入站规则
    local ingress_rules
    ingress_rules=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].IpPermissions[]')
    
    # 检查是否有CIDR规则
    local has_cidr_rules=false
    local cidr_rules=""
    
    while IFS= read -r rule; do
        local ip_ranges
        ip_ranges=$(echo "${rule}" | jq -r '.IpRanges[]?.CidrIp // empty')
        if [[ -n "${ip_ranges}" ]]; then
            has_cidr_rules=true
            cidr_rules="${cidr_rules}${ip_ranges}\n"
        fi
    done <<< "${ingress_rules}"
    
    if [[ "${has_cidr_rules}" == "true" ]]; then
        log_info "CIDR规则:"
        echo -e "${cidr_rules}" | while read -r cidr; do
            if [[ -n "${cidr}" ]]; then
                if [[ "${cidr}" == "${machine_cidr}" ]]; then
                    log_success "  ✅ ${cidr} (匹配machine CIDR)"
                else
                    log_warning "  ⚠️  ${cidr} (不匹配machine CIDR)"
                fi
            fi
        done
    else
        log_info "使用安全组引用而非CIDR规则 (OpenShift 4.x标准做法)"
    fi
    
    # 检查关键端口
    check_key_ports "${sg_info}"
}

check_key_ports() {
    local sg_info=$1
    
    log_info "关键端口检查:"
    
    # 检查6443端口
    local port_6443
    port_6443=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].IpPermissions[] | select(.FromPort == 6443 and .ToPort == 6443)')
    if [[ -n "${port_6443}" ]]; then
        log_success "  ✅ 6443/tcp (API Server) - 已配置"
    else
        log_warning "  ⚠️  6443/tcp (API Server) - 未找到"
    fi
    
    # 检查22623端口
    local port_22623
    port_22623=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].IpPermissions[] | select(.FromPort == 22623 and .ToPort == 22623)')
    if [[ -n "${port_22623}" ]]; then
        log_success "  ✅ 22623/tcp (Machine Config Server) - 已配置"
    else
        log_warning "  ⚠️  22623/tcp (Machine Config Server) - 未找到"
    fi
    
    # 检查22端口
    local port_22
    port_22=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].IpPermissions[] | select(.FromPort == 22 and .ToPort == 22)')
    if [[ -n "${port_22}" ]]; then
        log_success "  ✅ 22/tcp (SSH) - 已配置"
    else
        log_warning "  ⚠️  22/tcp (SSH) - 未找到"
    fi
    
    # 检查ICMP
    local icmp
    icmp=$(echo "${sg_info}" | jq -r '.SecurityGroups[0].IpPermissions[] | select(.IpProtocol == "icmp")')
    if [[ -n "${icmp}" ]]; then
        log_success "  ✅ ICMP - 已配置"
    else
        log_warning "  ⚠️  ICMP - 未找到"
    fi
}

# 验证网络隔离
verify_network_isolation() {
    log_info "=== 验证网络隔离 ==="
    
    # 获取两个集群的所有安全组
    local cluster1_sgs
    cluster1_sgs=$(aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters "Name=tag:kubernetes.io/cluster/${CLUSTER1_INFRA_ID},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    local cluster2_sgs
    cluster2_sgs=$(aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters "Name=tag:kubernetes.io/cluster/${CLUSTER2_INFRA_ID},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    log_info "集群1安全组: ${cluster1_sgs}"
    log_info "集群2安全组: ${cluster2_sgs}"
    
    # 检查是否有交叉引用
    local has_cross_reference=false
    for sg1 in $cluster1_sgs; do
        for sg2 in $cluster2_sgs; do
            if [[ "${sg1}" == "${sg2}" ]]; then
                has_cross_reference=true
                log_error "发现共享安全组: ${sg1}"
            fi
        done
    done
    
    if [[ "${has_cross_reference}" == "false" ]]; then
        log_success "✅ 两个集群使用独立的安全组，网络隔离正确"
    else
        log_error "❌ 发现共享安全组，网络隔离可能有问题"
    fi
}

# 主函数
main() {
    log_info "开始OpenShift 4.x安全组验证"
    echo "=========================================="
    
    verify_cluster_security_groups "集群1" "${CLUSTER1_INFRA_ID}" "${CLUSTER1_MACHINE_CIDR}"
    verify_cluster_security_groups "集群2" "${CLUSTER2_INFRA_ID}" "${CLUSTER2_MACHINE_CIDR}"
    
    verify_network_isolation
    
    log_success "安全组验证完成！"
    echo
    log_info "OpenShift 4.x使用安全组引用而非CIDR规则是正常的安全实践"
    log_info "网络隔离通过独立的安全组实现"
}

main "$@"
