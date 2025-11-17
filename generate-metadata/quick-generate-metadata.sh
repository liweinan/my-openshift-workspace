#!/bin/bash

# quick-generate-metadata.sh
# Quick generation of metadata.json - simplified version

set -o nounset
set -o errexit
set -o pipefail

# Check parameters
if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <cluster_name> <region> <infra_id> <cluster_id> [output_dir]"
    echo "Example: $0 my-cluster us-east-1 my-cluster-abc123 12345678-1234-1234-1234-123456789012"
    exit 1
fi

CLUSTER_NAME="$1"
REGION="$2"
INFRA_ID="$3"
CLUSTER_ID="$4"
OUTPUT_DIR="${5:-./cleanup}"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate metadata.json
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

echo "✅ metadata.json generated at: $OUTPUT_DIR/metadata.json"
echo "📋 Destroy commands:"
echo "   cd $OUTPUT_DIR"
echo "   openshift-install destroy cluster --dir . --log-level debug"
