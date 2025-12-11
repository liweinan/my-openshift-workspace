#!/bin/bash

################################################################################
# AWS Backup Quick Cleanup Script
#
# This script quickly cleans up AWS Backup resources (recovery points and vault).
#
# Usage:
#   ./cleanup-aws-backup.sh [options]
#
# Options:
#   --vault-name <name>        Backup vault name (required)
#   --region <region>         AWS region (default: us-east-1)
#   --force                   Skip confirmation prompt
#   --help                    Show this help message
#
# Examples:
#   ./cleanup-aws-backup.sh --vault-name weli-test-backup-vault
#   ./cleanup-aws-backup.sh --vault-name my-vault --region us-west-2 --force
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
VAULT_NAME=""
AWS_REGION="us-east-1"
FORCE=false
CLEANUP_IAM_ROLE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vault-name)
            VAULT_NAME="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --cleanup-iam-role)
            CLEANUP_IAM_ROLE=true
            shift
            ;;
        --help)
            head -n 20 "$0" | tail -n +3
            echo ""
            echo "Additional options:"
            echo "  --cleanup-iam-role    Also delete AWSBackupDefaultServiceRole IAM role"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if vault name provided
if [ -z "$VAULT_NAME" ]; then
    echo -e "${RED}Error: --vault-name is required${NC}"
    echo ""
    echo "Usage: $0 --vault-name <vault-name> [--region <region>] [--force]"
    echo ""
    echo "Examples:"
    echo "  $0 --vault-name weli-test-backup-vault"
    echo "  $0 --vault-name my-vault --region us-west-2 --force"
    exit 1
fi

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure'."
    exit 1
fi

# Display configuration
echo "=========================================="
echo "AWS Backup Cleanup"
echo "=========================================="
echo "Vault Name: $VAULT_NAME"
echo "Region: $AWS_REGION"
echo ""

# Confirm deletion
if [ "$FORCE" != "true" ]; then
    echo -e "${YELLOW}WARNING: This will delete all recovery points and the backup vault!${NC}"
    echo -e "${YELLOW}Press Ctrl+C to cancel, or Enter to continue...${NC}"
    read
fi

# Step 1: Check if vault exists
log_info "Step 1: Checking backup vault..."
if ! aws backup describe-backup-vault \
    --backup-vault-name "$VAULT_NAME" \
    --region "$AWS_REGION" &> /dev/null; then
    log_warning "Backup vault '$VAULT_NAME' not found (may already be deleted)"
    exit 0
fi

VAULT_INFO=$(aws backup describe-backup-vault \
    --backup-vault-name "$VAULT_NAME" \
    --region "$AWS_REGION" \
    --output json)

RECOVERY_POINT_COUNT=$(echo "$VAULT_INFO" | jq -r '.NumberOfRecoveryPoints // 0')
log_info "Found vault with $RECOVERY_POINT_COUNT recovery point(s)"

# Step 2: List recovery points
log_info "Step 2: Listing recovery points..."
RECOVERY_POINTS=$(aws backup list-recovery-points-by-backup-vault \
    --backup-vault-name "$VAULT_NAME" \
    --region "$AWS_REGION" \
    --query 'RecoveryPoints[*].RecoveryPointArn' \
    --output text 2>/dev/null || echo "")

if [ -z "$RECOVERY_POINTS" ] || [ "$RECOVERY_POINTS" = "None" ]; then
    log_info "No recovery points found"
    RECOVERY_POINTS=""
else
    # Count recovery points
    RP_COUNT=$(echo "$RECOVERY_POINTS" | tr '\t' '\n' | grep -v '^$' | wc -l | tr -d ' ')
    log_info "Found $RP_COUNT recovery point(s) to delete"
    
    # Display recovery points
    echo "$RECOVERY_POINTS" | tr '\t' '\n' | while read -r rp; do
        if [ -n "$rp" ]; then
            echo "  - $rp"
        fi
    done
fi

# Step 3: Delete recovery points
if [ -n "$RECOVERY_POINTS" ]; then
    echo ""
    log_info "Step 3: Deleting recovery points..."
    
    SUCCESS_COUNT=0
    FAILED_COUNT=0
    
    echo "$RECOVERY_POINTS" | tr '\t' '\n' | while read -r rp; do
        if [ -n "$rp" ]; then
            echo -n "  Deleting: $(echo "$rp" | sed 's/.*\///') ... "
            
            if aws backup delete-recovery-point \
                --backup-vault-name "$VAULT_NAME" \
                --recovery-point-arn "$rp" \
                --region "$AWS_REGION" &> /dev/null; then
                echo -e "${GREEN}✓${NC}"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                echo -e "${RED}✗${NC} (may have retention policy)"
                FAILED_COUNT=$((FAILED_COUNT + 1))
            fi
        fi
    done
    
    # Wait for deletions to process
    if [ "$SUCCESS_COUNT" -gt 0 ]; then
        echo ""
        log_info "Waiting for deletions to process (10 seconds)..."
        sleep 10
    fi
    
    # Check remaining recovery points
    REMAINING=$(aws backup list-recovery-points-by-backup-vault \
        --backup-vault-name "$VAULT_NAME" \
        --region "$AWS_REGION" \
        --query 'length(RecoveryPoints)' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$REMAINING" != "0" ] && [ "$REMAINING" != "None" ]; then
        log_warning "$REMAINING recovery point(s) still exist"
        log_warning "They may have retention policies. Check AWS Console or wait and retry."
    else
        log_success "All recovery points deleted"
    fi
else
    log_info "No recovery points to delete"
fi

# Step 4: Delete backup vault
echo ""
log_info "Step 4: Deleting backup vault..."

# Verify vault is empty before deletion
FINAL_COUNT=$(aws backup list-recovery-points-by-backup-vault \
    --backup-vault-name "$VAULT_NAME" \
    --region "$AWS_REGION" \
    --query 'length(RecoveryPoints)' \
    --output text 2>/dev/null || echo "0")

if [ "$FINAL_COUNT" != "0" ] && [ "$FINAL_COUNT" != "None" ]; then
    log_error "Cannot delete vault: $FINAL_COUNT recovery point(s) still exist"
    log_error "Please wait for recovery points to be deleted, or delete them manually"
    exit 1
fi

if aws backup delete-backup-vault \
    --backup-vault-name "$VAULT_NAME" \
    --region "$AWS_REGION" &> /dev/null; then
    log_success "Backup vault deleted"
else
    log_warning "Failed to delete vault (may already be deleted or not empty)"
fi

# Final verification
echo ""
log_info "Verifying cleanup..."
if aws backup describe-backup-vault \
    --backup-vault-name "$VAULT_NAME" \
    --region "$AWS_REGION" &> /dev/null; then
    log_warning "Vault still exists (may take a moment to delete)"
else
    log_success "Vault successfully deleted"
fi

# Optional: Cleanup IAM role
if [ "$CLEANUP_IAM_ROLE" = "true" ]; then
    echo ""
    log_info "Step 5: Cleaning up IAM role..."
    
    ROLE_NAME="AWSBackupDefaultServiceRole"
    
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        log_info "Found IAM role: $ROLE_NAME"
        
        # Detach policies
        log_info "Detaching policies..."
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup \
            2>/dev/null || log_warning "Backup policy may not be attached"
        
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores \
            2>/dev/null || log_warning "Restore policy may not be attached"
        
        # Delete role
        log_info "Deleting IAM role..."
        if aws iam delete-role --role-name "$ROLE_NAME" &> /dev/null; then
            log_success "IAM role deleted"
        else
            log_warning "Failed to delete IAM role (may be in use or have dependencies)"
        fi
    else
        log_info "IAM role does not exist, skipping"
    fi
fi

echo ""
echo "=========================================="
log_success "Cleanup completed!"
echo "=========================================="
