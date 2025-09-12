#!/bin/bash

# quick-generate-metadata.sh
# 快速生成 metadata.json 的简化版本

set -o nounset
set -o errexit
set -o pipefail

# 检查参数
if [[ $# -lt 4 ]]; then
    echo "用法: $0 <cluster_name> <region> <infra_id> <cluster_id> [output_dir]"
    echo "示例: $0 my-cluster us-east-1 my-cluster-abc123 12345678-1234-1234-1234-123456789012"
    exit 1
fi

CLUSTER_NAME="$1"
REGION="$2"
INFRA_ID="$3"
CLUSTER_ID="$4"
OUTPUT_DIR="${5:-./cleanup}"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 生成 metadata.json
cat > "$OUTPUT_DIR/metadata.json" << EOF
{
  "clusterName": "$CLUSTER_NAME",
  "clusterID": "$CLUSTER_ID",
  "infraID": "$INFRA_ID",
  "aws": {
    "region": "$REGION",
    "identifier": [
      {
        "kubernetes.io/cluster/$INFRA_ID": "owned"
      },
      {
        "openshiftClusterID": "$CLUSTER_ID"
      },
      {
        "sigs.k8s.io/cluster-api-provider-aws/cluster/$INFRA_ID": "owned"
      }
    ]
  }
}
EOF

echo "✅ metadata.json 已生成到: $OUTPUT_DIR/metadata.json"
echo "📋 销毁命令:"
echo "   cd $OUTPUT_DIR"
echo "   openshift-install destroy cluster --dir . --log-level debug"
