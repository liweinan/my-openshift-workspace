#!/bin/bash

# OCP-29781 设置验证脚本
# 验证VPC、子网标签和配置是否正确

set -euo pipefail

# 配置变量
VPC_STACK_NAME="weli-test-vpc"
CLUSTER1_NAME="weli-test-a"
CLUSTER2_NAME="weli-test-b"
AWS_REGION="us-east-1"
VPC_ID="vpc-06230a0fab9777f55"

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

# 验证VPC状态
verify_vpc() {
    log_info "验证VPC状态..."
    
    if aws ec2 describe-vpcs --region "${AWS_REGION}" --vpc-ids "${VPC_ID}" &> /dev/null; then
        log_success "VPC ${VPC_ID} 存在且可访问"
        
        # 显示VPC信息
        aws ec2 describe-vpcs --region "${AWS_REGION}" --vpc-ids "${VPC_ID}" \
            --query 'Vpcs[0].{VpcId:VpcId,State:State,CidrBlock:CidrBlock}' \
            --output table
    else
        log_error "VPC ${VPC_ID} 不存在或不可访问"
        return 1
    fi
}

# 验证子网标签
verify_subnet_tags() {
    log_info "验证子网标签..."
    
    # 获取所有子网
    SUBNETS=$(aws ec2 describe-subnets \
        --region "${AWS_REGION}" \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[].SubnetId' \
        --output text)
    
    log_info "检查子网标签..."
    for subnet in $SUBNETS; do
        log_info "检查子网: ${subnet}"
        
        # 检查集群1标签
        CLUSTER1_TAG=$(aws ec2 describe-tags \
            --region "${AWS_REGION}" \
            --filters "Name=resource-id,Values=${subnet}" "Name=key,Values=kubernetes.io/cluster/${CLUSTER1_NAME}" \
            --query 'Tags[0].Value' \
            --output text 2>/dev/null || echo "None")
        
        # 检查集群2标签
        CLUSTER2_TAG=$(aws ec2 describe-tags \
            --region "${AWS_REGION}" \
            --filters "Name=resource-id,Values=${subnet}" "Name=key,Values=kubernetes.io/cluster/${CLUSTER2_NAME}" \
            --query 'Tags[0].Value' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "${CLUSTER1_TAG}" == "shared" ]]; then
            log_success "  ✓ ${CLUSTER1_NAME} 标签: ${CLUSTER1_TAG}"
        else
            log_warning "  ⚠ ${CLUSTER1_NAME} 标签: ${CLUSTER1_TAG}"
        fi
        
        if [[ "${CLUSTER2_TAG}" == "shared" ]]; then
            log_success "  ✓ ${CLUSTER2_NAME} 标签: ${CLUSTER2_TAG}"
        else
            log_warning "  ⚠ ${CLUSTER2_NAME} 标签: ${CLUSTER2_TAG}"
        fi
    done
}

# 验证子网CIDR分布
verify_subnet_cidrs() {
    log_info "验证子网CIDR分布..."
    
    aws ec2 describe-subnets \
        --region "${AWS_REGION}" \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[*].{SubnetId:SubnetId,CidrBlock:CidrBlock,AvailabilityZone:AvailabilityZone,State:State}' \
        --output table
}

# 验证install-config文件
verify_install_configs() {
    log_info "验证install-config文件..."
    
    # 检查文件是否存在
    if [[ -f "install-config-cluster1.yaml" ]]; then
        log_success "install-config-cluster1.yaml 存在"
    else
        log_error "install-config-cluster1.yaml 不存在"
        return 1
    fi
    
    if [[ -f "install-config-cluster2.yaml" ]]; then
        log_success "install-config-cluster2.yaml 存在"
    else
        log_error "install-config-cluster2.yaml 不存在"
        return 1
    fi
    
    # 检查子网ID是否正确
    log_info "验证子网ID配置..."
    
    # 集群1子网
    CLUSTER1_PRIVATE_SUBNET=$(grep -B 1 "role: private" install-config-cluster1.yaml | grep "id:" | awk '{print $2}')
    CLUSTER1_PUBLIC_SUBNET=$(grep -B 1 "role: public" install-config-cluster1.yaml | grep "id:" | awk '{print $2}')
    
    log_info "集群1子网配置:"
    log_info "  私有子网: ${CLUSTER1_PRIVATE_SUBNET}"
    log_info "  公共子网: ${CLUSTER1_PUBLIC_SUBNET}"
    
    # 集群2子网
    CLUSTER2_PRIVATE_SUBNET=$(grep -B 1 "role: private" install-config-cluster2.yaml | grep "id:" | awk '{print $2}')
    CLUSTER2_PUBLIC_SUBNET=$(grep -B 1 "role: public" install-config-cluster2.yaml | grep "id:" | awk '{print $2}')
    
    log_info "集群2子网配置:"
    log_info "  私有子网: ${CLUSTER2_PRIVATE_SUBNET}"
    log_info "  公共子网: ${CLUSTER2_PUBLIC_SUBNET}"
}

# 验证CIDR隔离
verify_cidr_isolation() {
    log_info "验证CIDR隔离..."
    
    # 集群1使用10.134.0.0/16
    CLUSTER1_CIDR=$(grep "cidr:" install-config-cluster1.yaml | grep "10.134" | awk '{print $2}')
    log_info "集群1 machineNetwork CIDR: ${CLUSTER1_CIDR}"
    
    # 集群2使用10.190.0.0/16
    CLUSTER2_CIDR=$(grep "cidr:" install-config-cluster2.yaml | grep "10.190" | awk '{print $2}')
    log_info "集群2 machineNetwork CIDR: ${CLUSTER2_CIDR}"
    
    if [[ "${CLUSTER1_CIDR}" == "10.134.0.0/16" ]] && [[ "${CLUSTER2_CIDR}" == "10.190.0.0/16" ]]; then
        log_success "CIDR隔离配置正确"
    else
        log_error "CIDR隔离配置错误"
        return 1
    fi
}

# 主函数
main() {
    log_info "开始OCP-29781设置验证"
    echo
    
    verify_vpc
    echo
    
    verify_subnet_tags
    echo
    
    verify_subnet_cidrs
    echo
    
    verify_install_configs
    echo
    
    verify_cidr_isolation
    echo
    
    log_success "OCP-29781设置验证完成！"
    echo
    log_info "下一步：运行 './run-ocp29781-test.sh' 开始完整测试"
}

# 运行主函数
main "$@"
