#!/bin/bash

################################################################################
# Quick Cleanup Script for weli-test Cluster Backup
#
# This script quickly cleans up AWS Backup resources for weli-test cluster.
# It sets all variables automatically.
#
# Usage:
#   ./cleanup-weli-test-backup.sh [--force]
################################################################################

set -euo pipefail

# Auto-set variables for weli-test cluster
export VAULT_NAME="weli-test-backup-vault"
export AWS_REGION="us-east-1"
FORCE=false

# Parse arguments
if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Quick Cleanup: weli-test Backup"
echo "=========================================="
echo "Vault: $VAULT_NAME"
echo "Region: $AWS_REGION"
echo ""

# Confirm deletion
if [ "$FORCE" != "true" ]; then
    echo -e "${YELLOW}WARNING: This will delete all backup resources!${NC}"
    echo -e "${YELLOW}Press Ctrl+C to cancel, or Enter to continue...${NC}"
    read
fi

# Get recovery points
echo -e "${BLUE}Listing recovery points...${NC}"
RECOVERY_POINTS=$(aws backup list-recovery-points-by-backup-vault \
    --backup-vault-name "$VAULT_NAME" \
    --region "$AWS_REGION" \
    --query 'RecoveryPoints[*].RecoveryPointArn' \
    --output text 2>/dev/null || echo "")

if [ -z "$RECOVERY_POINTS" ] || [ "$RECOVERY_POINTS" = "None" ]; then
    echo "No recovery points found"
else
    echo "Found recovery points, deleting..."
    echo "$RECOVERY_POINTS" | tr '\t' '\n' | while read -r rp; do
        if [ -n "$rp" ]; then
            echo "  Deleting: $(echo "$rp" | sed 's/.*\///')"
            aws backup delete-recovery-point \
                --backup-vault-name "$VAULT_NAME" \
                --recovery-point-arn "$rp" \
                --region "$AWS_REGION" 2>/dev/null || true
        fi
    done
    
    echo "Waiting for deletions..."
    sleep 15
fi

# Delete vault
echo -e "${BLUE}Deleting backup vault...${NC}"
aws backup delete-backup-vault \
    --backup-vault-name "$VAULT_NAME" \
    --region "$AWS_REGION" 2>/dev/null || echo "Vault may already be deleted"

echo ""
echo -e "${GREEN}Cleanup completed!${NC}"
