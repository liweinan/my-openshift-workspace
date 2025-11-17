#!/bin/bash

# test-metadata-generator-offline.sh
# Offline test for metadata.json generator (no AWS credentials required)

set -o nounset
set -o errexit
set -o pipefail

# 测试参数
TEST_CLUSTER_NAME="test-cluster"
TEST_REGION="us-east-1"
TEST_INFRA_ID="test-cluster-abc123"
TEST_CLUSTER_ID="12345678-1234-1234-1234-123456789012"
TEST_OUTPUT_DIR="./test-cleanup"

echo "🧪 Offline testing metadata.json generator..."
echo

# 清理之前的测试文件
rm -rf "$TEST_OUTPUT_DIR"

echo "📋 Test parameters:"
echo "  Cluster name: $TEST_CLUSTER_NAME"
echo "  AWS region: $TEST_REGION"
echo "  Infrastructure ID: $TEST_INFRA_ID"
echo "  Cluster ID: $TEST_CLUSTER_ID"
echo "  Output directory: $TEST_OUTPUT_DIR"
echo

# Test simplified version (no AWS validation required)
echo "🔧 Testing simplified version..."
if ./quick-generate-metadata.sh "$TEST_CLUSTER_NAME" "$TEST_REGION" "$TEST_INFRA_ID" "$TEST_CLUSTER_ID" "$TEST_OUTPUT_DIR"; then
    echo "✅ Simplified version test passed"
else
    echo "❌ Simplified version test failed"
    exit 1
fi

echo

# Validate generated files
echo "🔍 Validating generated files..."
if [[ -f "$TEST_OUTPUT_DIR/metadata.json" ]]; then
    echo "✅ metadata.json file exists"
    
    # 验证 JSON 格式
    if jq empty "$TEST_OUTPUT_DIR/metadata.json" 2>/dev/null; then
        echo "✅ JSON format is valid"
    else
        echo "❌ JSON format is invalid"
        exit 1
    fi
    
    # 验证必需字段
    required_fields=("clusterName" "clusterID" "infraID" "aws.region" "aws.identifier")
    all_fields_valid=true
    
    for field in "${required_fields[@]}"; do
        if jq -e ".$field" "$TEST_OUTPUT_DIR/metadata.json" > /dev/null 2>&1; then
            echo "✅ Field '$field' exists"
        else
            echo "❌ Field '$field' is missing"
            all_fields_valid=false
        fi
    done
    
    if [[ "$all_fields_valid" == true ]]; then
        echo "✅ All required fields are present"
    else
        echo "❌ Some required fields are missing"
        exit 1
    fi
    
    # 验证字段值
    cluster_name=$(jq -r '.clusterName' "$TEST_OUTPUT_DIR/metadata.json")
    cluster_id=$(jq -r '.clusterID' "$TEST_OUTPUT_DIR/metadata.json")
    infra_id=$(jq -r '.infraID' "$TEST_OUTPUT_DIR/metadata.json")
    region=$(jq -r '.aws.region' "$TEST_OUTPUT_DIR/metadata.json")
    
    if [[ "$cluster_name" == "$TEST_CLUSTER_NAME" ]]; then
        echo "✅ clusterName value is correct: $cluster_name"
    else
        echo "❌ clusterName value is incorrect: expected '$TEST_CLUSTER_NAME', actual '$cluster_name'"
        exit 1
    fi
    
    if [[ "$cluster_id" == "$TEST_CLUSTER_ID" ]]; then
        echo "✅ clusterID value is correct: $cluster_id"
    else
        echo "❌ clusterID value is incorrect: expected '$TEST_CLUSTER_ID', actual '$cluster_id'"
        exit 1
    fi
    
    if [[ "$infra_id" == "$TEST_INFRA_ID" ]]; then
        echo "✅ infraID value is correct: $infra_id"
    else
        echo "❌ infraID value is incorrect: expected '$TEST_INFRA_ID', actual '$infra_id'"
        exit 1
    fi
    
    if [[ "$region" == "$TEST_REGION" ]]; then
        echo "✅ region value is correct: $region"
    else
        echo "❌ region value is incorrect: expected '$TEST_REGION', actual '$region'"
        exit 1
    fi
    
    # 验证 identifier 数组
    identifier_count=$(jq '.aws.identifier | length' "$TEST_OUTPUT_DIR/metadata.json")
    if [[ "$identifier_count" == "3" ]]; then
        echo "✅ identifier array contains 3 elements"
    else
        echo "❌ identifier array element count is incorrect: expected 3, actual $identifier_count"
        exit 1
    fi
    
    # 显示生成的内容
    echo
    echo "📄 Generated metadata.json content:"
    cat "$TEST_OUTPUT_DIR/metadata.json" | jq .
    
else
    echo "❌ metadata.json file does not exist"
    exit 1
fi

echo

# Test manual generation (validate format)
echo "🔧 Testing manual generation format..."
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
    echo "✅ Generated metadata.json matches expected format exactly"
else
    echo "❌ Generated metadata.json does not match expected format"
    echo "Differences:"
    diff "$TEST_OUTPUT_DIR/metadata.json" "$TEST_OUTPUT_DIR/manual-metadata.json" || true
    exit 1
fi

echo

# 清理测试文件
rm -rf "$TEST_OUTPUT_DIR"

echo "🎉 All offline tests passed!"
echo
echo "📋 Usage examples:"
echo "  # Simplified version (recommended for quick generation)"
echo "  ./quick-generate-metadata.sh \"my-cluster\" \"us-east-1\" \"my-cluster-abc123\" \"12345678-1234-1234-1234-123456789012\""
echo
echo "  # Full-featured version (requires AWS credentials, includes validation)"
echo "  ./generate-metadata-for-destroy.sh -c \"my-cluster\" -r \"us-east-1\" -i \"my-cluster-abc123\" -u \"12345678-1234-1234-1234-123456789012\""
echo
echo "  # Destroy cluster"
echo "  cd cleanup"
echo "  openshift-install destroy cluster --dir . --log-level debug"
echo
echo "📖 For detailed instructions see: README-metadata-generator.md"
