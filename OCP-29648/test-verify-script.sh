#!/bin/bash

# Test script for OCP-29648 verify-custom-ami.sh
# This script tests the verification script with mock data

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create test directory
TEST_DIR="/tmp/ocp-29648-test"
print_info "Creating test directory: $TEST_DIR"
mkdir -p "$TEST_DIR"

# Create mock metadata.json
print_info "Creating mock metadata.json"
cat > "$TEST_DIR/metadata.json" << EOF
{
  "clusterName": "test-cluster",
  "clusterID": "d64b26be-5d5e-4bb2-a723-9c1e527d46bf",
  "infraID": "test-cluster-abc123",
  "aws": {
    "region": "us-east-2",
    "identifier": [
      {
        "kubernetes.io/cluster/test-cluster-abc123": "owned"
      },
      {
        "openshiftClusterID": "d64b26be-5d5e-4bb2-a723-9c1e527d46bf"
      }
    ]
  }
}
EOF

# Create mock install-config.yaml
print_info "Creating mock install-config.yaml"
cat > "$TEST_DIR/install-config.yaml" << EOF
apiVersion: v1
baseDomain: example.com
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    aws:
      amiID: ami-03c1d60abaef1ca7e
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      amiID: ami-02e68e65b656320fa
  replicas: 3
metadata:
  name: test-cluster
platform:
  aws:
    region: us-east-2
pullSecret: '{"auths":{"fake-registry":{"auth":"fake-auth"}}}'
sshKey: ssh-rsa fake-ssh-key
EOF

# Create mock kubeconfig
print_info "Creating mock kubeconfig"
cat > "$TEST_DIR/kubeconfig" << EOF
apiVersion: v1
clusters:
- cluster:
    server: https://fake-cluster.example.com:6443
  name: test-cluster
contexts:
- context:
    cluster: test-cluster
    user: admin
  name: test-cluster
current-context: test-cluster
kind: Config
users:
- name: admin
  user:
    token: fake-token
EOF

print_success "Test files created successfully"
print_info "Test directory: $TEST_DIR"
print_info "Files created:"
echo "  - metadata.json"
echo "  - install-config.yaml"
echo "  - kubeconfig"

print_info ""
print_info "To test the verification script, run:"
echo "  ./verify-custom-ami.sh \\"
echo "    -k $TEST_DIR/kubeconfig \\"
echo "    -m $TEST_DIR/metadata.json \\"
echo "    -w $TEST_DIR \\"
echo "    --worker-ami ami-03c1d60abaef1ca7e \\"
echo "    --master-ami ami-02e68e65b656320fa"

print_info ""
print_info "Note: This will fail at the cluster connection step since it's a mock kubeconfig,"
print_info "but it will demonstrate the script's parameter parsing and file validation."
