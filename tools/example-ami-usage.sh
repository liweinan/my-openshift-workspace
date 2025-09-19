#!/bin/bash

# Example usage of find-rhcos-ami.sh script
# Demonstrates different ways to use the AMI discovery script

set -e

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo "=========================================="
echo "    RHCOS AMI Discovery Script Examples"
echo "=========================================="
echo ""

print_info "Example 1: Get AMI ID for us-east-2 (default)"
AMI_ID=$(./tools/find-rhcos-ami.sh -r us-east-2 -q)
echo "AMI ID: $AMI_ID"
echo ""

print_info "Example 2: Get AMI ID for us-west-2"
AMI_ID_WEST=$(./tools/find-rhcos-ami.sh -r us-west-2 -q)
echo "AMI ID: $AMI_ID_WEST"
echo ""

print_info "Example 3: Get export command for environment variable"
EXPORT_CMD=$(./tools/find-rhcos-ami.sh -r us-east-1 -f export -q)
echo "$EXPORT_CMD"
eval "$EXPORT_CMD"
echo "Environment variable RHCOS_AMI_ID is now set to: $RHCOS_AMI_ID"
echo ""

print_info "Example 4: Get full JSON information"
echo "Full AMI information for us-east-2:"
./tools/find-rhcos-ami.sh -r us-east-2 -f json -q
echo ""

print_info "Example 5: Use in install-config.yaml generation"
WORKER_AMI=$(./tools/find-rhcos-ami.sh -r us-east-2 -q)
MASTER_AMI=$(./tools/find-rhcos-ami.sh -r us-east-2 -q)
echo "Worker AMI: $WORKER_AMI"
echo "Master AMI: $MASTER_AMI"
echo ""

print_info "Example 6: Use specific openshift-install binary"
OPENSHIFT_INSTALL_PATH="~/works/oc-swarm/openshift-versions/420rc1/openshift-install"
if [ -f "$OPENSHIFT_INSTALL_PATH" ]; then
    AMI_ID_SPECIFIC=$(./tools/find-rhcos-ami.sh -p "$OPENSHIFT_INSTALL_PATH" -r us-east-2 -q)
    echo "AMI ID using specific openshift-install: $AMI_ID_SPECIFIC"
else
    echo "Specific openshift-install not found at: $OPENSHIFT_INSTALL_PATH"
fi
echo ""

print_info "Example 7: Dual AMI mode - same region"
echo "Generate install-config snippet with different AMIs for master and worker:"
./tools/find-rhcos-ami.sh -d -f install-config -q
echo ""

print_info "Example 8: Dual AMI mode - different regions"
echo "Generate install-config snippet with master from us-east-1 and worker from us-west-2:"
./tools/find-rhcos-ami.sh -d --master-region us-east-1 --worker-region us-west-2 -f install-config -q
echo ""

print_info "Example 9: Dual AMI export commands"
echo "Export commands for dual AMI configuration:"
./tools/find-rhcos-ami.sh -d --master-region us-east-1 --worker-region us-west-2 -f export -q
echo ""

print_info "Example 10: Batch get AMIs for multiple regions"
REGIONS=("us-east-1" "us-east-2" "us-west-1" "us-west-2")
echo "AMI IDs for multiple regions:"
for region in "${REGIONS[@]}"; do
    ami=$(./tools/find-rhcos-ami.sh -r "$region" -q 2>/dev/null || echo "N/A")
    echo "  $region: $ami"
done
echo ""

print_success "All examples completed successfully!"
