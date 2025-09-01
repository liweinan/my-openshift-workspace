#!/bin/bash

# Default values
AWS_PROFILE=""
REGION="us-east-1"
STACK_NAME="weli3-vpc"
VPC_CIDR="10.0.0.0/16"
AZ_COUNT=2
TEMPLATE_FILE="vpc-template-public-cluster.yaml"

usage() {
    echo "用法: $0 [options]"
    echo "选项:"
    echo "  -p, --profile <profile>      AWS CLI profile to use. Leave empty to use the default profile."
    echo "  -r, --region <region>        The AWS region where the stack will be updated. (Default: ${REGION})"
    echo "  -s, --stack-name <name>      The name of the CloudFormation stack to update. (Default: ${STACK_NAME})"
    echo "  -c, --vpc-cidr <cidr>        The CIDR block for the VPC. (Default: ${VPC_CIDR})"
    echo "  -a, --az-count <count>       The number of Availability Zones to use (1, 2, or 3). (Default: ${AZ_COUNT})"
    echo "  -t, --template-file <file>   The path to the CloudFormation template file. (Default: ${TEMPLATE_FILE})"
    echo "  -h, --help                   Show this help message."
    echo ""
    echo "注意: 此脚本将更新现有的 VPC 堆栈，添加 NAT Gateway 和修复网络配置。"
    echo "      更新过程中可能会短暂中断网络连接。"
    exit 1
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -p|--profile) AWS_PROFILE="$2"; shift ;;
        -r|--region) REGION="$2"; shift ;;
        -s|--stack-name) STACK_NAME="$2"; shift ;;
        -c|--vpc-cidr) VPC_CIDR="$2"; shift ;;
        -a|--az-count) AZ_COUNT="$2"; shift ;;
        -t|--template-file) TEMPLATE_FILE="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

echo "=========================================="
echo "VPC 堆栈更新工具"
echo "=========================================="
echo "堆栈名称: ${STACK_NAME}"
echo "区域: ${REGION}"
echo "模板文件: ${TEMPLATE_FILE}"
echo "VPC CIDR: ${VPC_CIDR}"
echo "可用区数量: ${AZ_COUNT}"
echo ""

# Check if stack exists
echo "检查堆栈是否存在..."
if ! aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    echo "错误: 堆栈 '${STACK_NAME}' 不存在或无法访问"
    exit 1
fi

echo "✓ 堆栈存在"
echo ""

# Show current stack status
echo "当前堆栈状态:"
aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].[StackStatus,StackStatusReason]' \
    --output table

echo ""

# Confirm update
echo "警告: 更新 VPC 堆栈可能会:"
echo "1. 短暂中断网络连接"
echo "2. 重新创建某些网络资源"
echo "3. 更改子网的 MapPublicIpOnLaunch 设置"
echo "4. 添加 NAT Gateway 和 EIP"
echo ""
read -p "是否继续更新? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "更新已取消"
    exit 0
fi

echo ""

# Construct the AWS CLI command
CMD="aws cloudformation deploy \
  --region ${REGION} \
  --stack-name ${STACK_NAME} \
  --template-file ${TEMPLATE_FILE} \
  --parameter-overrides \
    VpcCidr=${VPC_CIDR} \
    AvailabilityZoneCount=${AZ_COUNT} \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset"

if [ -n "${AWS_PROFILE}" ]; then
  CMD="${CMD} --profile ${AWS_PROFILE}"
fi

echo "执行更新命令:"
echo "${CMD}"
echo ""

# Execute the command
echo "开始更新堆栈..."
eval "${CMD}"

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✓ VPC 堆栈更新成功!"
    echo "=========================================="
    echo ""
    echo "更新后的堆栈输出:"
    aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query 'Stacks[0].Outputs' \
        --output table
    
    echo ""
    echo "下一步:"
    echo "1. 运行 './get-vpc-outputs.sh ${STACK_NAME}' 获取新的配置"
    echo "2. 更新你的 install-config.yaml 文件"
    echo "3. 重新运行 OpenShift 安装"
else
    echo ""
    echo "=========================================="
    echo "✗ VPC 堆栈更新失败!"
    echo "=========================================="
    echo "请检查错误信息并重试"
    exit 1
fi
