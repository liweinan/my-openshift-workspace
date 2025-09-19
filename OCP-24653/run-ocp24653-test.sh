#!/bin/bash

# OCP-24653 - [ipi-on-aws] bootimage override in install-config
# 测试自定义AMI ID在install-config中的使用

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 配置变量
CLUSTER_NAME="ocp-24653-test"
AWS_REGION="us-east-2"
CUSTOM_AMI_ID="ami-0faab67bebd0fe719"

echo "=== OCP-24653 测试开始 ==="
echo "集群名称: $CLUSTER_NAME"
echo "AWS区域: $AWS_REGION"
echo "自定义AMI ID: $CUSTOM_AMI_ID"

# 检查AMI状态
echo "=== 检查自定义AMI状态 ==="
AMI_STATE=$(aws ec2 describe-images --region $AWS_REGION --image-ids $CUSTOM_AMI_ID --query 'Images[0].State' --output text)
echo "AMI状态: $AMI_STATE"

if [ "$AMI_STATE" != "available" ]; then
    echo "❌ AMI尚未可用，请等待复制完成"
    echo "当前状态: $AMI_STATE"
    exit 1
fi

echo "✅ AMI可用，开始安装"

# 创建安装目录
INSTALL_DIR="${CLUSTER_NAME}-install"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 复制install-config
cp ../install-config.yaml .

echo "=== 开始OpenShift安装 ==="
echo "使用自定义AMI: $CUSTOM_AMI_ID"

# 创建manifests
openshift-install create manifests

# 开始安装
openshift-install create cluster --log-level=debug

echo "=== 安装完成，验证AMI使用情况 ==="

# 获取集群信息
INFRA_ID=$(cat metadata.json | jq -r .infraID)
echo "InfraID: $INFRA_ID"

# 检查worker节点的AMI ID
echo "=== 检查Worker节点AMI ID ==="
WORKER_AMIS=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "Name=tag:kubernetes.io/cluster/$INFRA_ID,Values=owned" \
              "Name=tag:sigs.k8s.io/cluster-api-provider-aws/role,Values=node" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].ImageId' \
    --output text | tr '\t' '\n' | sort | uniq)

echo "Worker节点使用的AMI ID:"
echo "$WORKER_AMIS"

# 验证是否使用了自定义AMI
if echo "$WORKER_AMIS" | grep -q "$CUSTOM_AMI_ID"; then
    echo "✅ 成功！Worker节点使用了自定义AMI: $CUSTOM_AMI_ID"
else
    echo "❌ 失败！Worker节点未使用自定义AMI"
    echo "期望: $CUSTOM_AMI_ID"
    echo "实际: $WORKER_AMIS"
    exit 1
fi

# 检查master节点的AMI ID
echo "=== 检查Master节点AMI ID ==="
MASTER_AMIS=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "Name=tag:kubernetes.io/cluster/$INFRA_ID,Values=owned" \
              "Name=tag:sigs.k8s.io/cluster-api-provider-aws/role,Values=control-plane" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].ImageId' \
    --output text | tr '\t' '\n' | sort | uniq)

echo "Master节点使用的AMI ID:"
echo "$MASTER_AMIS"

# 验证是否使用了自定义AMI
if echo "$MASTER_AMIS" | grep -q "$CUSTOM_AMI_ID"; then
    echo "✅ 成功！Master节点使用了自定义AMI: $CUSTOM_AMI_ID"
else
    echo "❌ 失败！Master节点未使用自定义AMI"
    echo "期望: $CUSTOM_AMI_ID"
    echo "实际: $MASTER_AMIS"
    exit 1
fi

echo "=== OCP-24653 测试完成 ==="
echo "✅ 所有节点都成功使用了自定义AMI: $CUSTOM_AMI_ID"
