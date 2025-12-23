#!/bin/bash

# 检查 AWS AMI 的 RHCOS 版本
# 使用方法: ./check-ami-rhcos-version.sh <AMI_ID> [REGION]

set -o nounset
set -o errexit
set -o pipefail

AMI_ID="${1:-}"
REGION="${2:-${AWS_REGION:-us-east-1}}"

if [[ -z "${AMI_ID}" ]]; then
  echo "用法: $0 <AMI_ID> [REGION]"
  echo "示例: $0 ami-0b2043a9ef91f505c us-east-1"
  exit 1
fi

echo "=========================================="
echo "检查 AMI 的 RHCOS 版本"
echo "=========================================="
echo "AMI ID: ${AMI_ID}"
echo "Region: ${REGION}"
echo ""

# 方法 1: 查看 AMI 的详细信息（Name 和 Description 通常包含版本信息）
echo "=== 方法 1: 从 AMI 描述信息中提取 ==="
AMI_INFO=$(aws --region "${REGION}" ec2 describe-images --image-ids "${AMI_ID}" 2>/dev/null)

if [[ -z "${AMI_INFO}" ]]; then
  echo "❌ 错误: 无法获取 AMI 信息，请检查："
  echo "   1. AMI ID 是否正确"
  echo "   2. AMI 是否在指定区域存在"
  echo "   3. AWS 凭证是否配置正确"
  exit 1
fi

echo "AMI 名称:"
echo "${AMI_INFO}" | jq -r '.Images[0].Name // "N/A"'
echo ""

echo "AMI 描述:"
echo "${AMI_INFO}" | jq -r '.Images[0].Description // "N/A"'
echo ""

echo "AMI 标签:"
echo "${AMI_INFO}" | jq -r '.Images[0].Tags // [] | .[] | "\(.Key): \(.Value)"' || echo "无标签"
echo ""

# 方法 2: 从 AMI 名称中提取版本信息（RHCOS AMI 名称通常包含版本）
echo "=== 方法 2: 从 AMI 名称提取版本信息 ==="
AMI_NAME=$(echo "${AMI_INFO}" | jq -r '.Images[0].Name // ""')

if [[ -n "${AMI_NAME}" ]]; then
  # RHCOS AMI 名称格式示例：
  # - rhcos-413.92.202305021736-0-x86_64-Marketplace-59ead7de-2540-4653-a8b0-fa7926d5c845
  # - rhcos-x86_64-415.92.202402201450-0-59ead7de-2540-4653-a8b0-fa7926d5c845
  
  if echo "${AMI_NAME}" | grep -q "rhcos"; then
    echo "检测到 RHCOS AMI"
    
    # 提取版本号（格式：4.13.92 或 413.92）
    VERSION=$(echo "${AMI_NAME}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+|[0-9]{3}\.[0-9]+' | head -1)
    if [[ -n "${VERSION}" ]]; then
      # 如果是 3 位数字开头（如 413），转换为 4.13
      if [[ "${VERSION}" =~ ^[0-9]{3} ]]; then
        MAJOR="${VERSION:0:1}"
        MINOR="${VERSION:1:2}"
        PATCH="${VERSION:4}"
        VERSION="${MAJOR}.${MINOR}.${PATCH}"
      fi
      echo "RHCOS 版本: ${VERSION}"
    fi
    
    # 提取构建日期
    BUILD_DATE=$(echo "${AMI_NAME}" | grep -oE '[0-9]{14}' | head -1)
    if [[ -n "${BUILD_DATE}" ]]; then
      echo "构建日期: ${BUILD_DATE:0:4}-${BUILD_DATE:4:2}-${BUILD_DATE:6:2} ${BUILD_DATE:8:2}:${BUILD_DATE:10:2}:${BUILD_DATE:12:2}"
    fi
  else
    echo "⚠️  AMI 名称不包含 'rhcos'，可能不是标准 RHCOS AMI"
  fi
else
  echo "⚠️  无法获取 AMI 名称"
fi
echo ""

# 方法 3: 从 Marketplace 信息中查找（如果是 Marketplace AMI）
echo "=== 方法 3: 检查是否为 Marketplace AMI ==="
PRODUCT_CODE=$(echo "${AMI_INFO}" | jq -r '.Images[0].ProductCodes[0].ProductCodeId // "N/A"')
if [[ "${PRODUCT_CODE}" != "N/A" ]]; then
  echo "产品代码: ${PRODUCT_CODE}"
  echo "这是 Marketplace AMI"
  
  # 如果是 Marketplace AMI，可以从 Marketplace 描述中获取更多信息
  echo ""
  echo "从 AWS Marketplace 查询详细信息..."
  MARKETPLACE_INFO=$(aws --region "${REGION}" ec2 describe-images \
    --owners aws-marketplace \
    --filters "Name=image-id,Values=${AMI_ID}" 2>/dev/null || echo "")
  
  if [[ -n "${MARKETPLACE_INFO}" ]]; then
    MARKETPLACE_NAME=$(echo "${MARKETPLACE_INFO}" | jq -r '.Images[0].Name // "N/A"')
    MARKETPLACE_DESC=$(echo "${MARKETPLACE_INFO}" | jq -r '.Images[0].Description // "N/A"')
    echo "Marketplace 名称: ${MARKETPLACE_NAME}"
    echo "Marketplace 描述: ${MARKETPLACE_DESC}"
  fi
else
  echo "这不是 Marketplace AMI"
fi
echo ""

# 方法 4: 完整的 AMI 信息（JSON 格式）
echo "=== 方法 4: 完整 AMI 信息（JSON）==="
echo "${AMI_INFO}" | jq '.Images[0] | {
  ImageId: .ImageId,
  Name: .Name,
  Description: .Description,
  CreationDate: .CreationDate,
  Architecture: .Architecture,
  ImageLocation: .ImageLocation,
  Tags: .Tags
}'
echo ""

# 方法 5: 如果 AMI 在运行中的实例上，可以从实例检查
echo "=== 方法 5: 检查是否有运行中的实例使用此 AMI ==="
INSTANCES=$(aws --region "${REGION}" ec2 describe-instances \
  --filters "Name=image-id,Values=${AMI_ID}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text 2>/dev/null || echo "")

if [[ -n "${INSTANCES}" ]]; then
  echo "找到运行中的实例使用此 AMI:"
  echo "${INSTANCES}" | tr '\t' '\n'
  echo ""
  echo "可以通过以下命令登录实例检查 RHCOS 版本:"
  FIRST_INSTANCE=$(echo "${INSTANCES}" | awk '{print $1}')
  echo "  oc debug node/<node-name> -- chroot /host rpm-ostree status"
  echo "  或"
  echo "  ssh core@<instance-ip> rpm-ostree status"
else
  echo "未找到运行中的实例使用此 AMI"
  echo ""
  echo "如果需要检查 RHCOS 版本，可以："
  echo "  1. 启动一个临时实例使用此 AMI"
  echo "  2. 登录实例运行: rpm-ostree status"
  echo "  3. 检查输出中的 Version 字段"
fi

echo ""
echo "=========================================="
echo "总结"
echo "=========================================="
echo "最可靠的方法是从 AMI 名称中提取版本信息"
echo "如果 AMI 名称包含 'rhcos'，通常格式为:"
echo "  rhcos-<version>-<arch>-<build-date>-..."
echo ""
echo "如果无法从 AMI 信息确定版本，可以："
echo "  1. 启动一个临时实例"
echo "  2. 登录后运行: rpm-ostree status"
echo "  3. 查看 Version 字段"

