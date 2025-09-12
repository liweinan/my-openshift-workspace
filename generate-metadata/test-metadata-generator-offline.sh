#!/bin/bash

# test-metadata-generator-offline.sh
# 离线测试 metadata.json 生成器（不需要 AWS 凭证）

set -o nounset
set -o errexit
set -o pipefail

# 测试参数
TEST_CLUSTER_NAME="test-cluster"
TEST_REGION="us-east-1"
TEST_INFRA_ID="test-cluster-abc123"
TEST_CLUSTER_ID="12345678-1234-1234-1234-123456789012"
TEST_OUTPUT_DIR="./test-cleanup"

echo "🧪 离线测试 metadata.json 生成器..."
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

# 测试简化版本（不需要 AWS 验证）
echo "🔧 测试简化版本..."
if ./quick-generate-metadata.sh "$TEST_CLUSTER_NAME" "$TEST_REGION" "$TEST_INFRA_ID" "$TEST_CLUSTER_ID" "$TEST_OUTPUT_DIR"; then
    echo "✅ 简化版本测试通过"
else
    echo "❌ 简化版本测试失败"
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
    required_fields=("clusterName" "clusterID" "infraID" "aws.region" "aws.identifier")
    all_fields_valid=true
    
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
    
    # 验证字段值
    cluster_name=$(jq -r '.clusterName' "$TEST_OUTPUT_DIR/metadata.json")
    cluster_id=$(jq -r '.clusterID' "$TEST_OUTPUT_DIR/metadata.json")
    infra_id=$(jq -r '.infraID' "$TEST_OUTPUT_DIR/metadata.json")
    region=$(jq -r '.aws.region' "$TEST_OUTPUT_DIR/metadata.json")
    
    if [[ "$cluster_name" == "$TEST_CLUSTER_NAME" ]]; then
        echo "✅ clusterName 值正确: $cluster_name"
    else
        echo "❌ clusterName 值错误: 期望 '$TEST_CLUSTER_NAME', 实际 '$cluster_name'"
        exit 1
    fi
    
    if [[ "$cluster_id" == "$TEST_CLUSTER_ID" ]]; then
        echo "✅ clusterID 值正确: $cluster_id"
    else
        echo "❌ clusterID 值错误: 期望 '$TEST_CLUSTER_ID', 实际 '$cluster_id'"
        exit 1
    fi
    
    if [[ "$infra_id" == "$TEST_INFRA_ID" ]]; then
        echo "✅ infraID 值正确: $infra_id"
    else
        echo "❌ infraID 值错误: 期望 '$TEST_INFRA_ID', 实际 '$infra_id'"
        exit 1
    fi
    
    if [[ "$region" == "$TEST_REGION" ]]; then
        echo "✅ region 值正确: $region"
    else
        echo "❌ region 值错误: 期望 '$TEST_REGION', 实际 '$region'"
        exit 1
    fi
    
    # 验证 identifier 数组
    identifier_count=$(jq '.aws.identifier | length' "$TEST_OUTPUT_DIR/metadata.json")
    if [[ "$identifier_count" == "3" ]]; then
        echo "✅ identifier 数组包含 3 个元素"
    else
        echo "❌ identifier 数组元素数量错误: 期望 3, 实际 $identifier_count"
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

# 测试手动生成（验证格式）
echo "🔧 测试手动生成格式..."
cat > "$TEST_OUTPUT_DIR/manual-metadata.json" << EOF
{
  "clusterName": "$TEST_CLUSTER_NAME",
  "clusterID": "$TEST_CLUSTER_ID",
  "infraID": "$TEST_INFRA_ID",
  "aws": {
    "region": "$TEST_REGION",
    "identifier": [
      {
        "kubernetes.io/cluster/$TEST_INFRA_ID": "owned"
      },
      {
        "openshiftClusterID": "$TEST_CLUSTER_ID"
      },
      {
        "sigs.k8s.io/cluster-api-provider-aws/cluster/$TEST_INFRA_ID": "owned"
      }
    ]
  }
}
EOF

# 比较两个文件
if diff -q "$TEST_OUTPUT_DIR/metadata.json" "$TEST_OUTPUT_DIR/manual-metadata.json" > /dev/null; then
    echo "✅ 生成的 metadata.json 与预期格式完全匹配"
else
    echo "❌ 生成的 metadata.json 与预期格式不匹配"
    echo "差异:"
    diff "$TEST_OUTPUT_DIR/metadata.json" "$TEST_OUTPUT_DIR/manual-metadata.json" || true
    exit 1
fi

echo

# 清理测试文件
rm -rf "$TEST_OUTPUT_DIR"

echo "🎉 所有离线测试通过！"
echo
echo "📋 使用示例:"
echo "  # 简化版本（推荐用于快速生成）"
echo "  ./quick-generate-metadata.sh \"my-cluster\" \"us-east-1\" \"my-cluster-abc123\" \"12345678-1234-1234-1234-123456789012\""
echo
echo "  # 完整功能版本（需要 AWS 凭证，包含验证）"
echo "  ./generate-metadata-for-destroy.sh -c \"my-cluster\" -r \"us-east-1\" -i \"my-cluster-abc123\" -u \"12345678-1234-1234-1234-123456789012\""
echo
echo "  # 销毁集群"
echo "  cd cleanup"
echo "  openshift-install destroy cluster --dir . --log-level debug"
echo
echo "📖 详细说明请查看: README-metadata-generator.md"
