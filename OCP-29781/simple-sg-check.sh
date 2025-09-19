#!/bin/bash

# 简化的安全组检查脚本

set -euo pipefail

AWS_REGION="us-east-1"
CLUSTER1_INFRA_ID="weli-test-a-p6fbf"
CLUSTER2_INFRA_ID="weli-test-b-2vgnm"

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

check_cluster() {
    local cluster_name=$1
    local infra_id=$2
    
    log_info "=== 检查 ${cluster_name} (${infra_id}) ==="
    
    # 获取安全组ID
    local security_groups
    security_groups=$(aws ec2 describe-instances \
        --region "${AWS_REGION}" \
        --filters "Name=tag:kubernetes.io/cluster/${infra_id},Values=owned" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text | tr '\t' '\n' | sort | uniq)
    
    log_info "安全组: ${security_groups}"
    echo
    
    # 检查每个安全组
    for sg_id in $security_groups; do
        check_single_sg "${sg_id}" "${infra_id}"
    done
    echo
}

check_single_sg() {
    local sg_id=$1
    local infra_id=$2
    
    log_info "检查安全组: ${sg_id}"
    
    # 获取安全组信息
    local sg_name
    sg_name=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].GroupName' \
        --output text)
    
    local sg_description
    sg_description=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].Description' \
        --output text)
    
    log_info "名称: ${sg_name}"
    log_info "描述: ${sg_description}"
    
    # 检查关键端口
    if [[ "${sg_name}" == *"controlplane"* ]]; then
        log_info "类型: Control Plane"
        check_controlplane_ports "${sg_id}"
    elif [[ "${sg_name}" == *"node"* ]]; then
        log_info "类型: Worker Node"
        check_worker_ports "${sg_id}"
    elif [[ "${sg_name}" == *"lb"* ]]; then
        log_info "类型: Load Balancer"
    elif [[ "${sg_name}" == *"apiserver"* ]]; then
        log_info "类型: API Server Load Balancer"
    else
        log_info "类型: 其他"
    fi
    
    echo "----------------------------------------"
}

check_controlplane_ports() {
    local sg_id=$1
    
    log_info "Control Plane端口检查:"
    
    # 检查6443端口
    local has_6443
    has_6443=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`6443` && ToPort==`6443`]' \
        --output text)
    
    if [[ -n "${has_6443}" ]]; then
        log_success "  ✅ 6443/tcp (API Server) - 已配置"
    else
        log_warning "  ⚠️  6443/tcp (API Server) - 未找到"
    fi
    
    # 检查22623端口
    local has_22623
    has_22623=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`22623` && ToPort==`22623`]' \
        --output text)
    
    if [[ -n "${has_22623}" ]]; then
        log_success "  ✅ 22623/tcp (Machine Config Server) - 已配置"
    else
        log_warning "  ⚠️  22623/tcp (Machine Config Server) - 未找到"
    fi
    
    # 检查22端口
    local has_22
    has_22=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`22` && ToPort==`22`]' \
        --output text)
    
    if [[ -n "${has_22}" ]]; then
        log_success "  ✅ 22/tcp (SSH) - 已配置"
    else
        log_warning "  ⚠️  22/tcp (SSH) - 未找到"
    fi
    
    # 检查ICMP
    local has_icmp
    has_icmp=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[?IpProtocol==`icmp`]' \
        --output text)
    
    if [[ -n "${has_icmp}" ]]; then
        log_success "  ✅ ICMP - 已配置"
    else
        log_warning "  ⚠️  ICMP - 未找到"
    fi
}

check_worker_ports() {
    local sg_id=$1
    
    log_info "Worker Node端口检查:"
    
    # 检查22端口
    local has_22
    has_22=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`22` && ToPort==`22`]' \
        --output text)
    
    if [[ -n "${has_22}" ]]; then
        log_success "  ✅ 22/tcp (SSH) - 已配置"
    else
        log_warning "  ⚠️  22/tcp (SSH) - 未找到"
    fi
    
    # 检查ICMP
    local has_icmp
    has_icmp=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --group-ids "${sg_id}" \
        --query 'SecurityGroups[0].IpPermissions[?IpProtocol==`icmp`]' \
        --output text)
    
    if [[ -n "${has_icmp}" ]]; then
        log_success "  ✅ ICMP - 已配置"
    else
        log_warning "  ⚠️  ICMP - 未找到"
    fi
}

# 验证网络隔离
verify_isolation() {
    log_info "=== 验证网络隔离 ==="
    
    # 获取两个集群的安全组
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
    
    # 检查是否有共享安全组
    local shared_sgs=""
    for sg1 in $cluster1_sgs; do
        for sg2 in $cluster2_sgs; do
            if [[ "${sg1}" == "${sg2}" ]]; then
                shared_sgs="${shared_sgs} ${sg1}"
            fi
        done
    done
    
    if [[ -z "${shared_sgs}" ]]; then
        log_success "✅ 两个集群使用完全独立的安全组"
        log_success "✅ 网络隔离配置正确"
    else
        log_error "❌ 发现共享安全组: ${shared_sgs}"
        log_error "❌ 网络隔离可能有问题"
    fi
}

# 主函数
main() {
    log_info "开始安全组验证"
    echo "=========================================="
    
    check_cluster "集群1" "${CLUSTER1_INFRA_ID}"
    check_cluster "集群2" "${CLUSTER2_INFRA_ID}"
    
    verify_isolation
    
    log_success "安全组验证完成！"
    echo
    log_info "OpenShift 4.x使用安全组引用实现网络隔离"
    log_info "这是比CIDR规则更安全的方法"
}

main "$@"
