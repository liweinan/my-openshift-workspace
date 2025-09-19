#!/bin/bash

# OCP-29781 VPC创建脚本
# 使用多CIDR模板创建VPC和子网

set -euo pipefail

# 默认配置变量
DEFAULT_STACK_NAME="ocp29781-vpc-$(date +%s)"
DEFAULT_AWS_REGION="us-east-2"
DEFAULT_VPC_CIDR="10.0.0.0/16"
DEFAULT_VPC_CIDR2="10.134.0.0/16"
DEFAULT_VPC_CIDR3="10.190.0.0/16"

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/01_vpc_multiCidr.yaml"

# 解析命令行参数
STACK_NAME="${DEFAULT_STACK_NAME}"
AWS_REGION="${DEFAULT_AWS_REGION}"
VPC_CIDR="${DEFAULT_VPC_CIDR}"
VPC_CIDR2="${DEFAULT_VPC_CIDR2}"
VPC_CIDR3="${DEFAULT_VPC_CIDR3}"
SHOW_HELP=false

# 显示帮助信息
show_help() {
    cat << EOF
OCP-29781 VPC创建脚本

用法: $0 [选项]

选项:
    -n, --name NAME          指定VPC堆栈名称 (默认: ${DEFAULT_STACK_NAME})
    -r, --region REGION     指定AWS区域 (默认: ${DEFAULT_AWS_REGION})
    -c, --cidr CIDR         指定主VPC CIDR (默认: ${DEFAULT_VPC_CIDR})
    -c2, --cidr2 CIDR2      指定第二个VPC CIDR (默认: ${DEFAULT_VPC_CIDR2})
    -c3, --cidr3 CIDR3      指定第三个VPC CIDR (默认: ${DEFAULT_VPC_CIDR3})
    -h, --help              显示此帮助信息

示例:
    $0                                    # 使用默认配置
    $0 -n my-vpc -r us-west-2            # 指定名称和区域
    $0 --name test-vpc --cidr 10.1.0.0/16 # 指定名称和CIDR

EOF
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            STACK_NAME="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -c|--cidr)
            VPC_CIDR="$2"
            shift 2
            ;;
        -c2|--cidr2)
            VPC_CIDR2="$2"
            shift 2
            ;;
        -c3|--cidr3)
            VPC_CIDR3="$2"
            shift 2
            ;;
        -h|--help)
            SHOW_HELP=true
            shift
            ;;
        *)
            echo "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 显示帮助信息并退出
if [[ "${SHOW_HELP}" == "true" ]]; then
    show_help
    exit 0
fi

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

# 检查前置条件
check_prerequisites() {
    log_info "检查前置条件..."
    
    # 检查AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI未安装"
        exit 1
    fi
    
    # 检查AWS凭据
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS凭据未配置，请运行 'aws configure'"
        exit 1
    fi
    
    # 检查模板文件
    if [[ ! -f "${TEMPLATE_FILE}" ]]; then
        log_error "模板文件不存在: ${TEMPLATE_FILE}"
        exit 1
    fi
    
    log_success "前置条件检查通过"
}

# 创建VPC堆栈
create_vpc_stack() {
    log_info "创建VPC堆栈: ${STACK_NAME}"
    log_info "使用模板: ${TEMPLATE_FILE}"
    log_info "VPC CIDR配置:"
    log_info "  主CIDR: ${VPC_CIDR}"
    log_info "  第二CIDR: ${VPC_CIDR2}"
    log_info "  第三CIDR: ${VPC_CIDR3}"
    
    # 创建CloudFormation堆栈
    aws cloudformation create-stack \
        --region "${AWS_REGION}" \
        --stack-name "${STACK_NAME}" \
        --template-body "file://${TEMPLATE_FILE}" \
        --capabilities CAPABILITY_IAM \
        --parameters \
            ParameterKey=VpcCidr,ParameterValue="${VPC_CIDR}" \
            ParameterKey=VpcCidr2,ParameterValue="${VPC_CIDR2}" \
            ParameterKey=VpcCidr3,ParameterValue="${VPC_CIDR3}" \
            ParameterKey=AvailabilityZoneCount,ParameterValue=3 \
        --tags \
            Key=Project,Value=OCP-29781 \
            Key=Environment,Value=Test \
            Key=Purpose,Value=MultiCIDR-VPC-Test \
            Key=StackName,Value="${STACK_NAME}"
    
    if [[ $? -eq 0 ]]; then
        log_success "VPC堆栈创建已启动"
    else
        log_error "VPC堆栈创建失败"
        exit 1
    fi
}

# 等待堆栈创建完成
wait_for_stack_completion() {
    log_info "等待堆栈创建完成..."
    log_info "这可能需要几分钟时间..."
    
    aws cloudformation wait stack-create-complete --region "${AWS_REGION}" --stack-name "${STACK_NAME}"
    
    if [[ $? -eq 0 ]]; then
        log_success "堆栈创建完成"
    else
        log_error "堆栈创建失败或超时"
        log_info "请检查CloudFormation控制台获取详细信息"
        exit 1
    fi
}

# 获取堆栈输出
get_stack_outputs() {
    log_info "获取堆栈输出信息..."
    
    # 获取VPC ID
    local vpc_id
    vpc_id=$(aws cloudformation describe-stacks \
        --region "${AWS_REGION}" \
        --stack-name "${STACK_NAME}" \
        --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
        --output text)
    
    if [[ -n "${vpc_id}" ]]; then
        log_success "VPC ID: ${vpc_id}"
        echo "VPC_ID=${vpc_id}" > vpc-info.env
    else
        log_warning "无法获取VPC ID"
    fi
    
    # 获取子网信息
    log_info "获取子网信息..."
    aws cloudformation describe-stacks \
        --region "${AWS_REGION}" \
        --stack-name "${STACK_NAME}" \
        --query 'Stacks[0].Outputs[?contains(OutputKey, `Subnet`)].{Key:OutputKey,Value:OutputValue}' \
        --output table
    
    # 保存堆栈输出到文件
    aws cloudformation describe-stacks \
        --region "${AWS_REGION}" \
        --stack-name "${STACK_NAME}" \
        --output json > stack-output.json
    
    log_success "堆栈输出已保存到 stack-output.json"
}

# 验证创建的资源
validate_resources() {
    log_info "验证创建的资源..."
    
    # 从环境文件读取VPC ID
    if [[ -f "vpc-info.env" ]]; then
        source vpc-info.env
        log_info "验证VPC: ${VPC_ID}"
        
        if aws ec2 describe-vpcs --region "${AWS_REGION}" --vpc-ids "${VPC_ID}" &> /dev/null; then
            log_success "VPC存在且可访问"
        else
            log_error "VPC验证失败"
            return 1
        fi
        
        # 检查子网数量
        local subnet_count
        subnet_count=$(aws ec2 describe-subnets \
            --region "${AWS_REGION}" \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'length(Subnets)' \
            --output text)
        
        log_info "VPC中发现 ${subnet_count} 个子网"
        
        # 显示所有子网信息
        aws ec2 describe-subnets \
            --region "${AWS_REGION}" \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'Subnets[*].{SubnetId:SubnetId,CidrBlock:CidrBlock,AvailabilityZone:AvailabilityZone,State:State}' \
            --output table
    else
        log_warning "未找到VPC信息文件"
    fi
}

# 显示使用说明
show_usage() {
    echo "VPC创建完成！"
    echo ""
    echo "下一步操作："
    echo "1. 检查 stack-output.json 文件获取子网ID"
    echo "2. 更新 install-config-cluster1.yaml 和 install-config-cluster2.yaml 中的子网ID"
    echo "3. 运行集群安装脚本"
    echo ""
    echo "清理资源："
    echo "aws cloudformation delete-stack --stack-name ${STACK_NAME}"
    echo ""
    echo "堆栈名称: ${STACK_NAME}"
    echo "VPC信息已保存到: vpc-info.env"
    echo "堆栈输出已保存到: stack-output.json"
}

# 主函数
main() {
    log_info "开始OCP-29781 VPC创建流程"
    
    # 显示配置
    log_info "配置信息:"
    log_info "  堆栈名称: ${STACK_NAME}"
    log_info "  模板文件: ${TEMPLATE_FILE}"
    log_info "  AWS区域: ${AWS_REGION}"
    log_info "  VPC CIDR: ${VPC_CIDR}"
    log_info "  VPC CIDR2: ${VPC_CIDR2}"
    log_info "  VPC CIDR3: ${VPC_CIDR3}"
    echo
    
    # 检查前置条件
    check_prerequisites
    
    # 创建VPC堆栈
    create_vpc_stack
    
    # 等待完成
    wait_for_stack_completion
    
    # 获取输出
    get_stack_outputs
    
    # 验证资源
    validate_resources
    
    # 显示使用说明
    show_usage
    
    log_success "VPC创建流程完成！"
}

# 运行主函数
main "$@"
