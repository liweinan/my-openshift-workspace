#!/bin/bash

# OCPBUGS-69923 本地测试脚本
# 使用方法: ./run-local-test.sh [test_directory]

set -e

# 配置
INSTALLER_BIN="${INSTALLER_BIN:-/Users/weli/works/installer/bin/openshift-install}"
TEST_DIR="${1:-./test-ocpbugs-69923}"
AWS_REGION="${AWS_REGION:-us-east-2}"

echo "=========================================="
echo "OCPBUGS-69923 本地测试验证"
echo "=========================================="
echo ""
echo "Installer 路径: $INSTALLER_BIN"
echo "测试目录: $TEST_DIR"
echo "AWS 区域: $AWS_REGION"
echo ""

# 检查 installer 是否存在
if [ ! -f "$INSTALLER_BIN" ]; then
    echo "❌ 错误: 找不到 openshift-install: $INSTALLER_BIN"
    echo "   请设置 INSTALLER_BIN 环境变量或修改脚本中的路径"
    exit 1
fi

# 检查必要的工具
if ! command -v yq >/dev/null 2>&1; then
    echo "❌ 错误: 需要安装 yq 工具"
    echo "   安装方法: brew install yq"
    exit 1
fi

# 创建测试目录
echo "步骤 1: 创建测试目录"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
echo "✓ 测试目录已创建: $(pwd)"
echo ""

# 检查是否已有 install-config.yaml
if [ -f "install-config.yaml" ]; then
    echo "⚠️  发现已存在的 install-config.yaml"
    read -p "是否使用现有配置? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "请手动创建或编辑 install-config.yaml"
        echo "重要: 不要指定 controlPlane.platform.aws.zones"
        exit 1
    fi
else
    echo "步骤 2: 创建 install-config.yaml"
    echo ""
    echo "⚠️  需要创建 install-config.yaml 文件"
    echo ""
    echo "请确保 install-config.yaml 满足以下要求:"
    echo "  - 不指定 controlPlane.platform.aws.zones"
    echo "  - 不指定 compute[].platform.aws.zones"
    echo "  - 不使用 BYO subnets"
    echo ""
    echo "示例配置:"
    cat << 'EOF'
apiVersion: v1
baseDomain: example.com
metadata:
  name: test-cluster-69923
platform:
  aws:
    region: us-east-2
controlPlane:
  name: master
  replicas: 3
  platform:
    aws:
      # 注意：不要指定 zones
compute:
- name: worker
  replicas: 3
  platform:
    aws:
      # 注意：不要指定 zones
pullSecret: '{"auths":{...}}'
sshKey: 'ssh-rsa ...'
EOF
    echo ""
    read -p "按 Enter 继续（确保已创建 install-config.yaml）..."
    echo ""
fi

# 检查 install-config.yaml 是否存在
if [ ! -f "install-config.yaml" ]; then
    echo "❌ 错误: 找不到 install-config.yaml"
    echo "   请在 $TEST_DIR 目录中创建 install-config.yaml"
    exit 1
fi

# 验证 install-config.yaml 不包含 zones
echo "步骤 3: 验证 install-config.yaml 配置"
if yq eval '.controlPlane.platform.aws.zones' install-config.yaml 2>/dev/null | grep -qv "null" && yq eval '.controlPlane.platform.aws.zones' install-config.yaml 2>/dev/null | grep -qv "^$"; then
    echo "⚠️  警告: install-config.yaml 中指定了 controlPlane.platform.aws.zones"
    echo "   这不符合测试要求（修复仅适用于未指定 zones 的场景）"
    read -p "是否继续? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo "✓ install-config.yaml 验证通过"
echo ""

# 生成 manifests
echo "步骤 4: 生成 manifests"
echo "运行: $INSTALLER_BIN create manifests --dir ."
echo ""

if "$INSTALLER_BIN" create manifests --dir .; then
    echo ""
    echo "✓ Manifests 生成成功"
else
    echo ""
    echo "❌ Manifests 生成失败"
    exit 1
fi
echo ""

# 验证 zone 一致性
echo "步骤 5: 验证 CAPI 和 MAPI Zone 分配一致性"
echo ""

# 查找 manifest 文件
CAPI_FILES=$(find openshift -name "*cluster-api*master*.yaml" -type f 2>/dev/null | sort)
MAPI_FILES=$(find openshift -name "*machine-api*master*.yaml" -type f 2>/dev/null | sort)

if [ -z "$CAPI_FILES" ]; then
    echo "❌ 错误: 未找到 CAPI manifest 文件"
    exit 1
fi

if [ -z "$MAPI_FILES" ]; then
    echo "❌ 错误: 未找到 MAPI manifest 文件"
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
echo ""

# 比较
echo "=========================================="
echo "一致性检查结果"
echo "=========================================="

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
    echo "✅ 验证通过：所有机器的 zone 分配一致！"
    echo ""
    echo "修复验证: PASS ✓"
    echo ""
    echo "可以运行多次测试以验证确定性:"
    echo "  cd $TEST_DIR"
    echo "  rm -rf openshift"
    echo "  $INSTALLER_BIN create manifests --dir ."
    echo "  然后再次运行此脚本验证"
    exit 0
else
    echo "❌ 验证失败：发现 zone 分配不一致！"
    echo ""
    echo "修复验证: FAIL ✗"
    echo ""
    echo "可能的原因:"
    echo "  1. 修复未生效"
    echo "  2. install-config.yaml 配置不正确"
    echo "  3. 使用了 BYO subnets 或指定了 zones"
    exit 1
fi
