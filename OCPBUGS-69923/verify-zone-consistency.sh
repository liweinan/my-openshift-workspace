#!/bin/bash

# 验证 CAPI 和 MAPI manifest 中的 zone 分配一致性
# 使用方法: ./verify-zone-consistency.sh <installation_directory>

set -e

INSTALL_DIR="${1:-.}"

if [ ! -d "$INSTALL_DIR" ]; then
    echo "错误: 目录不存在: $INSTALL_DIR"
    echo "使用方法: $0 <installation_directory>"
    exit 1
fi

echo "=========================================="
echo "验证 CAPI 和 MAPI Zone 分配一致性"
echo "=========================================="
echo ""
echo "安装目录: $INSTALL_DIR"
echo ""

# 检查必要的工具
if ! command -v yq >/dev/null 2>&1; then
    echo "错误: 需要安装 yq 工具"
    echo "安装方法: brew install yq 或访问 https://github.com/mikefarah/yq"
    exit 1
fi

# 检查 manifest 文件是否存在
CAPI_FILES=$(find "$INSTALL_DIR"/openshift -name "*cluster-api*master*.yaml" -type f 2>/dev/null | sort)
MAPI_FILES=$(find "$INSTALL_DIR"/openshift -name "*machine-api*master*.yaml" -type f 2>/dev/null | sort)

if [ -z "$CAPI_FILES" ]; then
    echo "❌ 错误: 未找到 CAPI manifest 文件"
    echo "   请确保已运行: openshift-install create manifests --dir=$INSTALL_DIR"
    exit 1
fi

if [ -z "$MAPI_FILES" ]; then
    echo "❌ 错误: 未找到 MAPI manifest 文件"
    echo "   请确保已运行: openshift-install create manifests --dir=$INSTALL_DIR"
    exit 1
fi

# 获取 CAPI zones
echo "CAPI Machine Zones:"
capi_zones=()
capi_index=0
for file in $CAPI_FILES; do
    zone=$(yq eval '.spec.template.spec.providerSpec.value.placement.availabilityZone' "$file" 2>/dev/null)
    if [ -n "$zone" ] && [ "$zone" != "null" ]; then
        capi_zones+=("$zone")
        echo "  master-$capi_index ($(basename "$file")): $zone"
        capi_index=$((capi_index + 1))
    fi
done

if [ ${#capi_zones[@]} -eq 0 ]; then
    echo "  ⚠️  警告: 未找到 CAPI zone 信息"
fi

echo ""

# 获取 MAPI zones
echo "MAPI Machine Zones:"
mapi_zones=()
mapi_index=0
for file in $MAPI_FILES; do
    zone=$(yq eval '.spec.providerSpec.value.placement.availabilityZone' "$file" 2>/dev/null)
    if [ -n "$zone" ] && [ "$zone" != "null" ]; then
        mapi_zones+=("$zone")
        echo "  master-$mapi_index ($(basename "$file")): $zone"
        mapi_index=$((mapi_index + 1))
    fi
done

if [ ${#mapi_zones[@]} -eq 0 ]; then
    echo "  ⚠️  警告: 未找到 MAPI zone 信息"
fi

echo ""

# 比较
echo "=========================================="
echo "一致性检查"
echo "=========================================="

if [ ${#capi_zones[@]} -eq 0 ] || [ ${#mapi_zones[@]} -eq 0 ]; then
    echo "❌ 无法进行比较：缺少 zone 信息"
    exit 1
fi

if [ ${#capi_zones[@]} -ne ${#mapi_zones[@]} ]; then
    echo "⚠️  警告: CAPI 和 MAPI 的机器数量不一致"
    echo "   CAPI: ${#capi_zones[@]} 台机器"
    echo "   MAPI: ${#mapi_zones[@]} 台机器"
    echo ""
fi

all_match=true
max_count=${#capi_zones[@]}
if [ ${#mapi_zones[@]} -gt $max_count ]; then
    max_count=${#mapi_zones[@]}
fi

for i in $(seq 0 $((max_count - 1))); do
    capi_zone="${capi_zones[$i]:-N/A}"
    mapi_zone="${mapi_zones[$i]:-N/A}"
    
    if [ "$capi_zone" = "$mapi_zone" ] && [ "$capi_zone" != "N/A" ]; then
        echo "✓ 匹配: master-$i - Zone: $capi_zone"
    else
        echo "❌ 不匹配: master-$i - CAPI: $capi_zone, MAPI: $mapi_zone"
        all_match=false
    fi
done

echo ""

if [ "$all_match" = true ]; then
    echo "✅ 所有机器的 zone 分配一致！"
    echo ""
    echo "验证通过：修复生效 ✓"
    exit 0
else
    echo "❌ 发现 zone 分配不一致！"
    echo ""
    echo "验证失败：需要检查修复是否生效"
    exit 1
fi
