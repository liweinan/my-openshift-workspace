#!/bin/bash

# OCP-24653 - [ipi-on-aws] bootimage override in install-config
# Test custom AMI ID usage in install-config

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration variables
CLUSTER_NAME="ocp-24653-test"
AWS_REGION="us-east-2"
CUSTOM_AMI_ID="ami-0faab67bebd0fe719"

echo "=== OCP-24653 Test Started ==="
echo "Cluster name: $CLUSTER_NAME"
echo "AWS region: $AWS_REGION"
echo "Custom AMI ID: $CUSTOM_AMI_ID"

# Check AMI status
echo "=== Checking Custom AMI Status ==="
AMI_STATE=$(aws ec2 describe-images --region $AWS_REGION --image-ids $CUSTOM_AMI_ID --query 'Images[0].State' --output text)
echo "AMI status: $AMI_STATE"

if [ "$AMI_STATE" != "available" ]; then
    echo "❌ AMI is not yet available, please wait for copy to complete"
    echo "Current status: $AMI_STATE"
    exit 1
fi

echo "✅ AMI is available, starting installation"

# Create installation directory
INSTALL_DIR="${CLUSTER_NAME}-install"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Copy install-config
cp ../install-config.yaml .

echo "=== Starting OpenShift Installation ==="
echo "Using custom AMI: $CUSTOM_AMI_ID"

# Create manifests
openshift-install create manifests

# Start installation
openshift-install create cluster --log-level=debug

echo "=== Installation Complete, Verifying AMI Usage ==="

# Get cluster information
INFRA_ID=$(cat metadata.json | jq -r .infraID)
echo "InfraID: $INFRA_ID"

# Check worker node AMI IDs
echo "=== Checking Worker Node AMI IDs ==="
WORKER_AMIS=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "Name=tag:kubernetes.io/cluster/$INFRA_ID,Values=owned" \
              "Name=tag:sigs.k8s.io/cluster-api-provider-aws/role,Values=node" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].ImageId' \
    --output text | tr '\t' '\n' | sort | uniq)

echo "AMI IDs used by worker nodes:"
echo "$WORKER_AMIS"

# Verify if custom AMI is used
if echo "$WORKER_AMIS" | grep -q "$CUSTOM_AMI_ID"; then
    echo "✅ Success! Worker nodes are using custom AMI: $CUSTOM_AMI_ID"
else
    echo "❌ Failed! Worker nodes are not using custom AMI"
    echo "Expected: $CUSTOM_AMI_ID"
    echo "Actual: $WORKER_AMIS"
    exit 1
fi

# Check master node AMI IDs
echo "=== Checking Master Node AMI IDs ==="
MASTER_AMIS=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "Name=tag:kubernetes.io/cluster/$INFRA_ID,Values=owned" \
              "Name=tag:sigs.k8s.io/cluster-api-provider-aws/role,Values=control-plane" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].ImageId' \
    --output text | tr '\t' '\n' | sort | uniq)

echo "AMI IDs used by master nodes:"
echo "$MASTER_AMIS"

# 验证是否使用了自定义AMI
if echo "$MASTER_AMIS" | grep -q "$CUSTOM_AMI_ID"; then
    echo "✅ Success! Master nodes are using custom AMI: $CUSTOM_AMI_ID"
else
    echo "❌ Failed! Master nodes are not using custom AMI"
    echo "期望: $CUSTOM_AMI_ID"
    echo "实际: $MASTER_AMIS"
    exit 1
fi

echo "=== OCP-24653 Test Completed ==="
echo "✅ All nodes successfully using custom AMI: $CUSTOM_AMI_ID"
