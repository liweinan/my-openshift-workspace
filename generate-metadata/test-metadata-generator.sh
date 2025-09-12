#!/bin/bash

# test-metadata-generator.sh
# 测试 metadata.json 生成器

set -o nounset
set -o errexit
set -o pipefail

# 测试参数
TEST_CLUSTER_NAME="test-cluster"
TEST_REGION="us-east-1"
TEST_INFRA_ID="test-cluster-abc123"
TEST_CLUSTER_ID="12345678-1234-1234-1234-123456789012"
TEST_OUTPUT_DIR="./test-cleanup"

echo "🧪 测试 metadata.json 生成器..."
echo

# 清理之前的测试文件
rm -rf "$TEST_OUTPUT_DIR"

echo "📋 测试参数:"
echo "  集群名称: $TEST_CLUSTER_NAME"
echo "  AWS 区域: $TEST_REGION"
echo "  基础设施 ID: $TEST_INFRA_ID"
echo "  集群 ID: $TEST_CLUSTER_ID"
echo "  输出目录: $TEST_OUTPUT_DIR"
echo

# 测试完整功能版本
echo "🔧 测试完整功能版本..."
if ./generate-metadata-for-destroy.sh \
  -c "$TEST_CLUSTER_NAME" \
  -r "$TEST_REGION" \
  -i "$TEST_INFRA_ID" \
  -u "$TEST_CLUSTER_ID" \
  -o "$TEST_OUTPUT_DIR"; then
    echo "✅ 完整功能版本测试通过"
else
    echo "❌ 完整功能版本测试失败"
    exit 1
fi

echo

# 验证生成的文件
echo "🔍 验证生成的文件..."
if [[ -f "$TEST_OUTPUT_DIR/metadata.json" ]]; then
    echo "✅ metadata.json 文件存在"
    
    # 验证 JSON 格式
    if jq empty "$TEST_OUTPUT_DIR/metadata.json" 2>/dev/null; then
        echo "✅ JSON 格式有效"
    else
        echo "❌ JSON 格式无效"
        exit 1
    fi
    
    # 验证必需字段
    local required_fields=("clusterName" "clusterID" "infraID" "aws.region" "aws.identifier")
    local all_fields_valid=true
    
    for field in "${required_fields[@]}"; do
        if jq -e ".$field" "$TEST_OUTPUT_DIR/metadata.json" > /dev/null 2>&1; then
            echo "✅ 字段 '$field' 存在"
        else
            echo "❌ 字段 '$field' 缺失"
            all_fields_valid=false
        fi
    done
    
    if [[ "$all_fields_valid" == true ]]; then
        echo "✅ 所有必需字段都存在"
    else
        echo "❌ 某些必需字段缺失"
        exit 1
    fi
    
    # 显示生成的内容
    echo
    echo "📄 生成的 metadata.json 内容:"
    cat "$TEST_OUTPUT_DIR/metadata.json" | jq .
    
else
    echo "❌ metadata.json 文件不存在"
    exit 1
fi

echo

# 清理测试文件
rm -rf "$TEST_OUTPUT_DIR"

# 测试简化版本
echo "🔧 测试简化版本..."
if ./quick-generate-metadata.sh "$TEST_CLUSTER_NAME" "$TEST_REGION" "$TEST_INFRA_ID" "$TEST_CLUSTER_ID" "$TEST_OUTPUT_DIR"; then
    echo "✅ 简化版本测试通过"
else
    echo "❌ 简化版本测试失败"
    exit 1
fi

echo

# 验证简化版本生成的文件
echo "🔍 验证简化版本生成的文件..."
if [[ -f "$TEST_OUTPUT_DIR/metadata.json" ]]; then
    echo "✅ metadata.json 文件存在"
    
    # 验证 JSON 格式
    if jq empty "$TEST_OUTPUT_DIR/metadata.json" 2>/dev/null; then
        echo "✅ JSON 格式有效"
    else
        echo "❌ JSON 格式无效"
        exit 1
    fi
    
    # 显示生成的内容
    echo
    echo "📄 生成的 metadata.json 内容:"
    cat "$TEST_OUTPUT_DIR/metadata.json" | jq .
    
else
    echo "❌ metadata.json 文件不存在"
    exit 1
fi

echo

# 清理测试文件
rm -rf "$TEST_OUTPUT_DIR"

echo "🎉 所有测试通过！"
echo
echo "📋 使用示例:"
echo "  # 完整功能版本"
echo "  ./generate-metadata-for-destroy.sh -c \"my-cluster\" -r \"us-east-1\" -i \"my-cluster-abc123\" -u \"12345678-1234-1234-1234-123456789012\""
echo
echo "  # 简化版本"
echo "  ./quick-generate-metadata.sh \"my-cluster\" \"us-east-1\" \"my-cluster-abc123\" \"12345678-1234-1234-1234-123456789012\""
echo
echo "  # 销毁集群"
echo "  cd cleanup"
echo "  openshift-install destroy cluster --dir . --log-level debug"
