#!/bin/bash

# OCP-25698 Test Setup Script
# [ipi-on-aws] create multiple clusters using the same subnets from an existing VPC

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -r, --region <region>        AWS region (default: us-east-2)"
    echo "  -s, --stack-name <name>      VPC stack name (default: ocp-25698-shared-vpc)"
    echo "  -c, --vpc-cidr <cidr>        VPC CIDR (default: 10.0.0.0/16)"
    echo "  -a, --az-count <count>       Number of AZs (default: 2)"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "This script sets up the infrastructure for OCP-25698 test case:"
    echo "  - Creates a VPC with public and private subnets"
    echo "  - Generates install-config.yaml templates"
    echo "  - Provides step-by-step instructions for the test"
    exit 1
}

# Default values
REGION="us-east-2"
STACK_NAME="ocp-25698-shared-vpc"
VPC_CIDR="10.0.0.0/16"
AZ_COUNT=2

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -r|--region) REGION="$2"; shift ;;
        -s|--stack-name) STACK_NAME="$2"; shift ;;
        -c|--vpc-cidr) VPC_CIDR="$2"; shift ;;
        -a|--az-count) AZ_COUNT="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

print_info "Setting up OCP-25698 test infrastructure"
print_info "Region: ${REGION}"
print_info "Stack Name: ${STACK_NAME}"
print_info "VPC CIDR: ${VPC_CIDR}"
print_info "AZ Count: ${AZ_COUNT}"
echo ""

# Step 1: Create VPC
print_info "Step 1: Creating VPC with public and private subnets..."
../tools/create-vpc-stack.sh \
  --region "${REGION}" \
  --stack-name "${STACK_NAME}" \
  --vpc-cidr "${VPC_CIDR}" \
  --az-count "${AZ_COUNT}" \
  --template-file "../tools/vpc-template-public-cluster.yaml"

if [ $? -eq 0 ]; then
    print_success "VPC created successfully"
else
    print_error "Failed to create VPC"
    exit 1
fi

echo ""

# Step 2: Get VPC outputs and generate install-config
print_info "Step 2: Getting VPC outputs and generating install-config templates..."

# Get VPC outputs
VPC_OUTPUTS=$(../tools/get-vpc-outputs.sh "${STACK_NAME}" "${REGION}")

# Extract subnet IDs from the output
PUBLIC_SUBNETS=$(echo "${VPC_OUTPUTS}" | grep -A 10 "公有群集配置" | grep "id:" | sed 's/.*id: //' | tr '\n' ' ')
PRIVATE_SUBNETS=$(echo "${VPC_OUTPUTS}" | grep -A 10 "公有群集配置" | grep "id:" | tail -n +5 | sed 's/.*id: //' | tr '\n' ' ')

# Create install-config template for cluster A
cat > install-config-cluster-a.yaml << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
compute:
  - architecture: amd64
    hyperthreading: Enabled
    name: worker
    platform: {}
    replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 3
metadata:
  creationTimestamp: null
  name: cluster-a
networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  machineNetwork:
    - cidr: ${VPC_CIDR}
  networkType: OVNKubernetes
  serviceNetwork:
    - 172.30.0.0/16
platform:
  aws:
    region: ${REGION}
    subnets:
$(for subnet in ${PUBLIC_SUBNETS} ${PRIVATE_SUBNETS}; do echo "    - ${subnet}"; done)
publish: External
pullSecret: '{"auths":{"cloud.openshift.com":{"auth":"YOUR_AUTH_TOKEN_HERE","email":"your-email@example.com"},"quay.io":{"auth":"YOUR_AUTH_TOKEN_HERE","email":"your-email@example.com"},"registry.connect.redhat.com":{"auth":"YOUR_AUTH_TOKEN_HERE","email":"your-email@example.com"},"registry.redhat.io":{"auth":"YOUR_AUTH_TOKEN_HERE","email":"your-email@example.com"}}}'
sshKey: |
  ssh-rsa YOUR_SSH_PUBLIC_KEY_HERE your-email@example.com
EOF

# Create install-config template for cluster B
sed 's/name: cluster-a/name: cluster-b/' install-config-cluster-a.yaml > install-config-cluster-b.yaml

print_success "Generated install-config templates:"
print_info "  - install-config-cluster-a.yaml"
print_info "  - install-config-cluster-b.yaml"
echo ""

# Step 3: Tag subnets for shared usage
print_info "Step 3: Tagging subnets for shared cluster usage..."

# Tag subnets for cluster A
../tools/tag-subnets.sh "${STACK_NAME}" "cluster-a"

# Tag subnets for cluster B (shared)
../tools/tag-subnets.sh "${STACK_NAME}" "cluster-b"

print_success "Subnets tagged for shared usage"
echo ""

# Display test instructions
print_info "OCP-25698 Test Setup Complete!"
echo ""
print_warning "Next Steps:"
echo ""
echo "1. Update install-config files with your pull-secret and SSH key:"
echo "   - Edit install-config-cluster-a.yaml"
echo "   - Edit install-config-cluster-b.yaml"
echo ""
echo "2. Install Cluster A:"
echo "   mkdir cluster-a"
echo "   cp install-config-cluster-a.yaml cluster-a/install-config.yaml"
echo "   openshift-install create cluster --dir cluster-a"
echo ""
echo "3. Health check Cluster A:"
echo "   export KUBECONFIG=cluster-a/auth/kubeconfig"
echo "   oc get nodes"
echo "   oc get clusteroperators"
echo ""
echo "4. Install Cluster B:"
echo "   mkdir cluster-b"
echo "   cp install-config-cluster-b.yaml cluster-b/install-config.yaml"
echo "   openshift-install create cluster --dir cluster-b"
echo ""
echo "5. Health check Cluster B:"
echo "   export KUBECONFIG=cluster-b/auth/kubeconfig"
echo "   oc get nodes"
echo "   oc get clusteroperators"
echo ""
echo "6. Scale up worker nodes (Machine API):"
echo "   # For Cluster A"
echo "   export KUBECONFIG=cluster-a/auth/kubeconfig"
echo "   oc get machinesets"
echo "   oc scale machineset <machineset-name> --replicas=4"
echo ""
echo "   # For Cluster B"
echo "   export KUBECONFIG=cluster-b/auth/kubeconfig"
echo "   oc scale machineset <machineset-name> --replicas=4"
echo ""
echo "7. Destroy Cluster A:"
echo "   openshift-install destroy cluster --dir cluster-a"
echo ""
echo "8. Scale up Cluster B again:"
echo "   export KUBECONFIG=cluster-b/auth/kubeconfig"
echo "   oc scale machineset <machineset-name> --replicas=4"
echo ""
echo "9. Destroy Cluster B:"
echo "   openshift-install destroy cluster --dir cluster-b"
echo ""
echo "10. Verify subnets are clean:"
echo "    aws ec2 describe-subnets --subnet-ids <subnet-id> --query 'Subnets[0].Tags'"
echo ""
echo "11. Clean up VPC:"
echo "    aws cloudformation delete-stack --stack-name ${STACK_NAME}"
echo ""
print_success "Setup complete! Follow the steps above to execute the OCP-25698 test case."
