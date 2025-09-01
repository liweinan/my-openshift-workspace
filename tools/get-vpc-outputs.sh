#!/bin/bash

# 检查参数
if [ $# -lt 1 ]; then
    echo "用法: $0 <STACK_NAME>"
    echo "示例: $0 my-vpc-stack"
    echo ""
    echo "注意: 此脚本会输出私有群集和公有群集的配置，请根据你的需求选择"
    exit 1
fi

STACK_NAME=$1
REGION=${2:-"us-east-1"}

echo "正在查询 CloudFormation 堆栈: $STACK_NAME"
echo "区域: $REGION"
echo ""

# 检查堆栈是否存在
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo "错误: 堆栈 '$STACK_NAME' 不存在或无法访问"
    exit 1
fi

# 获取 VPC ID
VPC_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
    --output text)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
    echo "错误: 无法获取 VPC ID"
    exit 1
fi

echo "VPC ID: $VPC_ID"
echo ""

# 获取可用区
ZONES=($(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`AvailabilityZones`].OutputValue' \
    --output text | tr ',' ' '))

if [ ${#ZONES[@]} -eq 0 ]; then
    echo "错误: 无法获取可用区信息"
    exit 1
fi

echo "可用区: ${ZONES[*]}"
echo ""

# 获取公共子网
PUBLIC_SUBNET_IDS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
    --output text)

if [ -z "$PUBLIC_SUBNET_IDS" ] || [ "$PUBLIC_SUBNET_IDS" = "None" ]; then
    echo "错误: 无法获取公共子网 ID"
    exit 1
fi

# 获取私有子网
PRIVATE_SUBNET_IDS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnetIds`].OutputValue' \
    --output text)

if [ -z "$PRIVATE_SUBNET_IDS" ] || [ "$PRIVATE_SUBNET_IDS" = "None" ]; then
    echo "错误: 无法获取私有子网 ID"
    exit 1
fi

# 转换为数组
PUBLIC_SUBNET_ARRAY=($(echo "$PUBLIC_SUBNET_IDS" | tr ',' ' '))
PRIVATE_SUBNET_ARRAY=($(echo "$PRIVATE_SUBNET_IDS" | tr ',' ' '))

echo "公共子网数量: ${#PUBLIC_SUBNET_ARRAY[@]}"
echo "私有子网数量: ${#PRIVATE_SUBNET_ARRAY[@]}"
echo ""

echo "=========================================="
echo "私有群集配置 (publish: Internal)"
echo "=========================================="
echo "platform:"
echo "  aws:"
echo "    region: $REGION"
echo "    vpc:"
echo "      subnets:"
for i in "${!PRIVATE_SUBNET_ARRAY[@]}"; do
    echo "      - id: ${PRIVATE_SUBNET_ARRAY[$i]}"
done
echo "publish: Internal"
echo ""
echo "注意: 私有群集只使用私有子网，通过 NAT Gateway 访问互联网"
echo ""

echo "=========================================="
echo "公有群集配置 (publish: External)"
echo "=========================================="
echo "platform:"
echo "  aws:"
echo "    region: $REGION"
echo "    vpc:"
echo "      subnets:"
for i in "${!PUBLIC_SUBNET_ARRAY[@]}"; do
    echo "      - id: ${PUBLIC_SUBNET_ARRAY[$i]}"
done
for i in "${!PRIVATE_SUBNET_ARRAY[@]}"; do
    echo "      - id: ${PRIVATE_SUBNET_ARRAY[$i]}"
done
echo "publish: External"
echo ""
echo "注意: 公有群集使用公共+私有子网组合"
echo ""

echo "=========================================="
echo "使用说明:"
echo "1. 复制上述配置到你的 install-config.yaml 文件中"
echo "2. 根据你的需求选择 publish: Internal 或 External"
echo "3. 确保 pull-secret 已正确配置"
echo "=========================================="
