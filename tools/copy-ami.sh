#!/bin/bash

# 复制 AWS AMI 到同一区域或不同区域
# 使用方法: ./copy-ami.sh <SOURCE_AMI_ID> [OPTIONS]
#
# 选项:
#   --source-region <region>    源 AMI 所在区域（默认: us-east-1）
#   --target-region <region>    目标区域（默认: 与源区域相同）
#   --name <name>               新 AMI 的名称（默认: 基于源 AMI 名称）
#   --description <desc>        新 AMI 的描述（默认: 基于源 AMI 描述）
#   --wait                      等待 AMI 复制完成（状态变为 available）
#   --monitor                   监控复制进度直到完成

set -o nounset
set -o errexit
set -o pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 参数解析
SOURCE_AMI_ID=""
SOURCE_REGION="${AWS_REGION:-us-east-1}"
TARGET_REGION=""
NEW_AMI_NAME=""
NEW_AMI_DESCRIPTION=""
WAIT_FOR_AVAILABLE=false
MONITOR_PROGRESS=false

# 解析参数
while [[ $# -gt 0 ]]; do
  case $1 in
    --source-region)
      SOURCE_REGION="$2"
      shift 2
      ;;
    --target-region)
      TARGET_REGION="$2"
      shift 2
      ;;
    --name)
      NEW_AMI_NAME="$2"
      shift 2
      ;;
    --description)
      NEW_AMI_DESCRIPTION="$2"
      shift 2
      ;;
    --wait)
      WAIT_FOR_AVAILABLE=true
      shift
      ;;
    --monitor)
      MONITOR_PROGRESS=true
      WAIT_FOR_AVAILABLE=true
      shift
      ;;
    --help|-h)
      echo "用法: $0 <SOURCE_AMI_ID> [OPTIONS]"
      echo ""
      echo "选项:"
      echo "  --source-region <region>    源 AMI 所在区域（默认: us-east-1）"
      echo "  --target-region <region>    目标区域（默认: 与源区域相同）"
      echo "  --name <name>               新 AMI 的名称"
      echo "  --description <desc>        新 AMI 的描述"
      echo "  --wait                      等待 AMI 复制完成"
      echo "  --monitor                   监控复制进度直到完成"
      echo ""
      echo "示例:"
      echo "  $0 ami-01095d1967818437c --source-region us-east-1"
      echo "  $0 ami-01095d1967818437c --source-region us-east-1 --target-region us-west-2 --name my-copied-ami"
      echo "  $0 ami-01095d1967818437c --monitor"
      exit 0
      ;;
    -*)
      echo -e "${RED}❌ 错误: 未知选项 $1${NC}"
      exit 1
      ;;
    *)
      if [[ -z "${SOURCE_AMI_ID}" ]]; then
        SOURCE_AMI_ID="$1"
      else
        echo -e "${RED}❌ 错误: 多余的参数: $1${NC}"
        exit 1
      fi
      shift
      ;;
  esac
done

# 检查必需参数
if [[ -z "${SOURCE_AMI_ID}" ]]; then
  echo -e "${RED}❌ 错误: 必须提供源 AMI ID${NC}"
  echo ""
  echo "用法: $0 <SOURCE_AMI_ID> [OPTIONS]"
  echo "使用 --help 查看详细帮助"
  exit 1
fi

# 如果没有指定目标区域，使用源区域
if [[ -z "${TARGET_REGION}" ]]; then
  TARGET_REGION="${SOURCE_REGION}"
fi

# 检查必需的工具
command -v aws >/dev/null 2>&1 || { echo -e "${RED}❌ 错误: aws 命令未找到${NC}"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo -e "${RED}❌ 错误: jq 命令未找到${NC}"; exit 1; }

echo "=========================================="
echo "复制 AWS AMI"
echo "=========================================="
echo "源 AMI ID: ${SOURCE_AMI_ID}"
echo "源区域: ${SOURCE_REGION}"
echo "目标区域: ${TARGET_REGION}"
echo ""

# 验证源 AMI 是否存在
echo "=== 步骤 1: 验证源 AMI ==="
SOURCE_AMI_INFO=$(aws --region "${SOURCE_REGION}" ec2 describe-images --image-ids "${SOURCE_AMI_ID}" 2>/dev/null || echo "")

if [[ -z "${SOURCE_AMI_INFO}" ]]; then
  echo -e "${RED}❌ 错误: 无法获取源 AMI 信息${NC}"
  echo "   请检查："
  echo "   1. AMI ID 是否正确: ${SOURCE_AMI_ID}"
  echo "   2. AMI 是否在区域 ${SOURCE_REGION} 存在"
  echo "   3. AWS 凭证是否配置正确"
  exit 1
fi

SOURCE_AMI_NAME=$(echo "${SOURCE_AMI_INFO}" | jq -r '.Images[0].Name // ""')
SOURCE_AMI_DESC=$(echo "${SOURCE_AMI_INFO}" | jq -r '.Images[0].Description // ""')
SOURCE_AMI_STATE=$(echo "${SOURCE_AMI_INFO}" | jq -r '.Images[0].State // ""')

echo -e "${GREEN}✓${NC} 源 AMI 名称: ${SOURCE_AMI_NAME}"
echo -e "${GREEN}✓${NC} 源 AMI 状态: ${SOURCE_AMI_STATE}"

if [[ "${SOURCE_AMI_STATE}" != "available" ]]; then
  echo -e "${YELLOW}⚠️  警告: 源 AMI 状态不是 'available'，复制可能会失败${NC}"
fi
echo ""

# 确定新 AMI 的名称和描述
if [[ -z "${NEW_AMI_NAME}" ]]; then
  if [[ -n "${SOURCE_AMI_NAME}" ]]; then
    NEW_AMI_NAME="${SOURCE_AMI_NAME}-copy-$(date +%Y%m%d-%H%M%S)"
  else
    NEW_AMI_NAME="copied-ami-${SOURCE_AMI_ID}-$(date +%Y%m%d-%H%M%S)"
  fi
fi

if [[ -z "${NEW_AMI_DESCRIPTION}" ]]; then
  if [[ -n "${SOURCE_AMI_DESC}" ]]; then
    NEW_AMI_DESCRIPTION="Copied from ${SOURCE_AMI_ID} in ${SOURCE_REGION}. Original: ${SOURCE_AMI_DESC}"
  else
    NEW_AMI_DESCRIPTION="Copied from ${SOURCE_AMI_ID} in ${SOURCE_REGION} on $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  fi
fi

echo "=== 步骤 2: 开始复制 AMI ==="
echo "新 AMI 名称: ${NEW_AMI_NAME}"
echo "新 AMI 描述: ${NEW_AMI_DESCRIPTION}"
echo ""

# 执行复制
echo "正在复制 AMI..."
COPY_RESULT=$(aws --region "${TARGET_REGION}" ec2 copy-image \
  --source-region "${SOURCE_REGION}" \
  --source-image-id "${SOURCE_AMI_ID}" \
  --name "${NEW_AMI_NAME}" \
  --description "${NEW_AMI_DESCRIPTION}" \
  --output json 2>&1)

if [[ $? -ne 0 ]]; then
  echo -e "${RED}❌ 错误: AMI 复制失败${NC}"
  echo "${COPY_RESULT}"
  exit 1
fi

NEW_AMI_ID=$(echo "${COPY_RESULT}" | jq -r '.ImageId // ""')

if [[ -z "${NEW_AMI_ID}" ]]; then
  echo -e "${RED}❌ 错误: 无法从复制结果中提取新 AMI ID${NC}"
  echo "复制结果:"
  echo "${COPY_RESULT}"
  exit 1
fi

echo -e "${GREEN}✓${NC} AMI 复制已启动"
echo -e "${GREEN}✓${NC} 新 AMI ID: ${NEW_AMI_ID}"
echo ""

# 如果源和目标区域相同，显示复制任务信息
if [[ "${SOURCE_REGION}" == "${TARGET_REGION}" ]]; then
  echo "注意: 在同一区域内复制 AMI 会创建一个新的 AMI，但会共享底层快照。"
  echo "复制过程通常很快完成。"
else
  echo "注意: 跨区域复制 AMI 需要传输数据，可能需要较长时间。"
fi
echo ""

# 等待 AMI 可用
if [[ "${WAIT_FOR_AVAILABLE}" == true ]]; then
  echo "=== 步骤 3: 等待 AMI 可用 ==="
  echo "正在等待 AMI ${NEW_AMI_ID} 状态变为 'available'..."
  echo ""
  
  if [[ "${MONITOR_PROGRESS}" == true ]]; then
    # 监控模式：显示进度
    while true; do
      AMI_STATUS=$(aws --region "${TARGET_REGION}" ec2 describe-images \
        --image-ids "${NEW_AMI_ID}" \
        --query 'Images[0].State' \
        --output text 2>/dev/null || echo "unknown")
      
      if [[ "${AMI_STATUS}" == "available" ]]; then
        echo -e "${GREEN}✓${NC} AMI 已可用！"
        break
      elif [[ "${AMI_STATUS}" == "failed" ]] || [[ "${AMI_STATUS}" == "invalid" ]]; then
        echo -e "${RED}❌ 错误: AMI 复制失败，状态: ${AMI_STATUS}${NC}"
        exit 1
      else
        echo -e "${BLUE}⏳${NC} 当前状态: ${AMI_STATUS} (等待中...)"
        sleep 10
      fi
    done
  else
    # 简单等待模式
    aws --region "${TARGET_REGION}" ec2 wait image-available --image-ids "${NEW_AMI_ID}" 2>/dev/null || {
      AMI_STATUS=$(aws --region "${TARGET_REGION}" ec2 describe-images \
        --image-ids "${NEW_AMI_ID}" \
        --query 'Images[0].State' \
        --output text 2>/dev/null || echo "unknown")
      
      if [[ "${AMI_STATUS}" != "available" ]]; then
        echo -e "${RED}❌ 错误: AMI 复制失败或超时，状态: ${AMI_STATUS}${NC}"
        exit 1
      fi
    }
    echo -e "${GREEN}✓${NC} AMI 已可用！"
  fi
  echo ""
fi

# 显示最终信息
echo "=========================================="
echo "复制完成"
echo "=========================================="
echo -e "${GREEN}新 AMI ID: ${NEW_AMI_ID}${NC}"
echo "区域: ${TARGET_REGION}"
echo "名称: ${NEW_AMI_NAME}"
echo ""

# 显示新 AMI 的详细信息
if [[ "${WAIT_FOR_AVAILABLE}" == true ]]; then
  echo "=== 新 AMI 详细信息 ==="
  NEW_AMI_INFO=$(aws --region "${TARGET_REGION}" ec2 describe-images --image-ids "${NEW_AMI_ID}" 2>/dev/null)
  
  if [[ -n "${NEW_AMI_INFO}" ]]; then
    echo "${NEW_AMI_INFO}" | jq -r '.Images[0] | {
      ImageId: .ImageId,
      Name: .Name,
      Description: .Description,
      State: .State,
      CreationDate: .CreationDate,
      Architecture: .Architecture,
      ImageType: .ImageType,
      VirtualizationType: .VirtualizationType,
      RootDeviceType: .RootDeviceType
    }'
  fi
  echo ""
fi

echo "=========================================="
echo "使用新 AMI"
echo "=========================================="
echo "在 install-config.yaml 中使用:"
echo ""
echo "platform:"
echo "  aws:"
echo "    region: ${TARGET_REGION}"
echo "    amiID: ${NEW_AMI_ID}"
echo ""

