# AWS Backup Cleanup Guide

This guide explains how to clean up AWS Backup resources created during testing or production use.

## Overview

When AWS Backup creates backups, it creates:
- **Recovery Points**: The actual backup data (AMIs, snapshots, etc.)
- **Backup Vault**: Container for recovery points
- **Backup Jobs**: Job records (automatically cleaned up after completion)

To fully clean up, you need to delete recovery points before deleting the backup vault.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Permissions for AWS Backup operations:
  - `backup:DeleteRecoveryPoint`
  - `backup:ListRecoveryPointsByBackupVault`
  - `backup:DeleteBackupVault`

## Quick Cleanup Scripts

### Option 1: General Cleanup Script

Use the general cleanup script for any backup vault:

```bash
# Basic usage
./scripts/cleanup-aws-backup.sh --vault-name weli-test-backup-vault

# With region
./scripts/cleanup-aws-backup.sh --vault-name my-vault --region us-west-2

# Skip confirmation
./scripts/cleanup-aws-backup.sh --vault-name my-vault --force
```

### Option 2: Quick Cleanup for weli-test Cluster

For the weli-test cluster, use the pre-configured script:

```bash
# Interactive (with confirmation)
./scripts/cleanup-weli-test-backup.sh

# Skip confirmation
./scripts/cleanup-weli-test-backup.sh --force
```

This script automatically sets:
- Vault name: `weli-test-backup-vault`
- Region: `us-east-1`

## Step-by-Step Cleanup

If you prefer manual cleanup or need more control, follow these steps:

### Step 1: Identify Backup Resources

First, identify what needs to be cleaned up:

```bash
# Set variables
export VAULT_NAME="weli-test-backup-vault"  # Your backup vault name
export AWS_REGION="us-east-1"

# List all backup vaults
aws backup list-backup-vaults \
  --region "$AWS_REGION" \
  --output table

# Describe specific vault
aws backup describe-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION"
```

### Step 2: List Recovery Points

List all recovery points in the vault:

```bash
# List recovery points
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION" \
  --output json > recovery-points.json

# View in table format
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION" \
  --query 'RecoveryPoints[*].[RecoveryPointArn,CreationDate,Status]' \
  --output table

# Get recovery point ARNs only
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION" \
  --query 'RecoveryPoints[*].RecoveryPointArn' \
  --output text > recovery-point-arns.txt
```

### Step 3: Delete Recovery Points

Recovery points must be deleted individually. Each recovery point deletion will also delete the associated AMI and snapshots.

#### Option A: Delete Single Recovery Point

```bash
# Get recovery point ARN
export RECOVERY_POINT_ARN="arn:aws:ec2:us-east-1::image/ami-09bcdf46592428068"

# Delete recovery point
aws backup delete-recovery-point \
  --backup-vault-name "$VAULT_NAME" \
  --recovery-point-arn "$RECOVERY_POINT_ARN" \
  --region "$AWS_REGION"
```

#### Option B: Delete All Recovery Points (Script)

```bash
#!/bin/bash

VAULT_NAME="weli-test-backup-vault"
AWS_REGION="us-east-1"

# Get all recovery point ARNs
RECOVERY_POINTS=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION" \
  --query 'RecoveryPoints[*].RecoveryPointArn' \
  --output text)

if [ -z "$RECOVERY_POINTS" ] || [ "$RECOVERY_POINTS" = "None" ]; then
  echo "No recovery points found"
  exit 0
fi

# Delete each recovery point
for rp in $RECOVERY_POINTS; do
  echo "Deleting recovery point: $rp"
  aws backup delete-recovery-point \
    --backup-vault-name "$VAULT_NAME" \
    --recovery-point-arn "$rp" \
    --region "$AWS_REGION"
  
  if [ $? -eq 0 ]; then
    echo "✓ Successfully deleted: $rp"
  else
    echo "✗ Failed to delete: $rp"
  fi
done
```

#### Option C: Delete with Wait (Recommended)

Some recovery points may have retention policies. This script waits for deletion to complete:

```bash
#!/bin/bash

VAULT_NAME="weli-test-backup-vault"
AWS_REGION="us-east-1"

# Function to wait for recovery point deletion
wait_for_deletion() {
  local rp_arn=$1
  local max_wait=600  # 10 minutes
  local elapsed=0
  local check_interval=10
  
  while [ $elapsed -lt $max_wait ]; do
    # Check if recovery point still exists
    local exists=$(aws backup list-recovery-points-by-backup-vault \
      --backup-vault-name "$VAULT_NAME" \
      --region "$AWS_REGION" \
      --query "RecoveryPoints[?RecoveryPointArn=='$rp_arn'].RecoveryPointArn" \
      --output text)
    
    if [ -z "$exists" ] || [ "$exists" = "None" ]; then
      return 0  # Deleted
    fi
    
    echo "  Waiting for deletion... (${elapsed}s)"
    sleep $check_interval
    elapsed=$((elapsed + check_interval))
  done
  
  return 1  # Timeout
}

# Get all recovery point ARNs
RECOVERY_POINTS=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION" \
  --query 'RecoveryPoints[*].RecoveryPointArn' \
  --output text)

if [ -z "$RECOVERY_POINTS" ] || [ "$RECOVERY_POINTS" = "None" ]; then
  echo "No recovery points found"
  exit 0
fi

# Delete each recovery point
for rp in $RECOVERY_POINTS; do
  echo "Deleting recovery point: $rp"
  aws backup delete-recovery-point \
    --backup-vault-name "$VAULT_NAME" \
    --recovery-point-arn "$rp" \
    --region "$AWS_REGION"
  
  if [ $? -eq 0 ]; then
    echo "  Deletion initiated, waiting for completion..."
    wait_for_deletion "$rp"
    if [ $? -eq 0 ]; then
      echo "✓ Successfully deleted: $rp"
    else
      echo "⚠ Deletion may still be in progress: $rp"
    fi
  else
    echo "✗ Failed to delete: $rp"
  fi
done
```

### Step 4: Verify Recovery Points Deleted

```bash
# Check recovery point count
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION" \
  --query 'length(RecoveryPoints)' \
  --output text

# Should return 0 if all deleted
```

### Step 5: Delete Backup Vault

**Important**: Backup vault can only be deleted when it's empty (no recovery points).

```bash
# Delete backup vault
aws backup delete-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION"

# Verify deletion
aws backup describe-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION" 2>&1

# Should return: "An error occurred (ResourceNotFoundException)"
```

## Complete Cleanup Script

Here's a complete script that handles all cleanup steps:

```bash
#!/bin/bash

################################################################################
# AWS Backup Complete Cleanup Script
#
# This script deletes all recovery points and the backup vault.
#
# Usage:
#   ./cleanup-aws-backup.sh [--vault-name <name>] [--region <region>] [--force]
################################################################################

set -euo pipefail

# Default values
VAULT_NAME=""
AWS_REGION="us-east-1"
FORCE=false

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
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if vault name provided
if [ -z "$VAULT_NAME" ]; then
    echo "Error: --vault-name is required"
    echo "Usage: $0 --vault-name <vault-name> [--region <region>] [--force]"
    exit 1
fi

echo "=========================================="
echo "AWS Backup Cleanup"
echo "=========================================="
echo "Vault Name: $VAULT_NAME"
echo "Region: $AWS_REGION"
echo ""

# Confirm deletion
if [ "$FORCE" != "true" ]; then
    echo "WARNING: This will delete all recovery points and the backup vault!"
    echo "Press Ctrl+C to cancel, or Enter to continue..."
    read
fi

# Step 1: List recovery points
echo "Step 1: Listing recovery points..."
RECOVERY_POINTS=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION" \
  --query 'RecoveryPoints[*].RecoveryPointArn' \
  --output text 2>/dev/null || echo "")

if [ -z "$RECOVERY_POINTS" ] || [ "$RECOVERY_POINTS" = "None" ]; then
    echo "  No recovery points found"
else
    COUNT=$(echo "$RECOVERY_POINTS" | wc -w)
    echo "  Found $COUNT recovery point(s)"
fi

# Step 2: Delete recovery points
if [ -n "$RECOVERY_POINTS" ] && [ "$RECOVERY_POINTS" != "None" ]; then
    echo ""
    echo "Step 2: Deleting recovery points..."
    for rp in $RECOVERY_POINTS; do
        echo "  Deleting: $rp"
        if aws backup delete-recovery-point \
          --backup-vault-name "$VAULT_NAME" \
          --recovery-point-arn "$rp" \
          --region "$AWS_REGION" 2>/dev/null; then
            echo "    ✓ Deletion initiated"
        else
            echo "    ✗ Failed to delete (may have retention policy)"
        fi
    done
    
    # Wait a bit for deletions to process
    echo ""
    echo "  Waiting for deletions to process..."
    sleep 10
    
    # Check remaining recovery points
    REMAINING=$(aws backup list-recovery-points-by-backup-vault \
      --backup-vault-name "$VAULT_NAME" \
      --region "$AWS_REGION" \
      --query 'length(RecoveryPoints)' \
      --output text 2>/dev/null || echo "0")
    
    if [ "$REMAINING" != "0" ]; then
        echo "  ⚠ Warning: $REMAINING recovery point(s) still exist"
        echo "    They may have retention policies. Check AWS Console for details."
    else
        echo "  ✓ All recovery points deleted"
    fi
fi

# Step 3: Delete backup vault
echo ""
echo "Step 3: Deleting backup vault..."
if aws backup delete-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION" 2>/dev/null; then
    echo "  ✓ Backup vault deleted"
else
    echo "  ✗ Failed to delete vault (may not be empty or already deleted)"
    echo "    Check if all recovery points are deleted first"
fi

echo ""
echo "=========================================="
echo "Cleanup completed"
echo "=========================================="
```

Save this as `cleanup-aws-backup.sh` and make it executable:

```bash
chmod +x cleanup-aws-backup.sh
./cleanup-aws-backup.sh --vault-name weli-test-backup-vault --region us-east-1
```

## Quick Cleanup Commands

### For weli-test Cluster

```bash
# Set variables
export VAULT_NAME="weli-test-backup-vault"
export AWS_REGION="us-east-1"

# List recovery points
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION" \
  --query 'RecoveryPoints[*].[RecoveryPointArn,CreationDate]' \
  --output table

# Delete all recovery points
for rp in $(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION" \
  --query 'RecoveryPoints[*].RecoveryPointArn' \
  --output text); do
  echo "Deleting: $rp"
  aws backup delete-recovery-point \
    --backup-vault-name "$VAULT_NAME" \
    --recovery-point-arn "$rp" \
    --region "$AWS_REGION"
done

# Wait and verify
sleep 30
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION" \
  --query 'length(RecoveryPoints)' \
  --output text

# Delete vault
aws backup delete-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION"
```

## Troubleshooting

### Issue: Cannot Delete Recovery Point

**Error**: `InvalidRequestException: Recovery point cannot be deleted because it is within the minimum retention period`

**Solution**: 
- Recovery points may have retention policies
- Wait for the retention period to expire
- Check retention settings in AWS Console
- Some recovery points cannot be deleted immediately

### Issue: Vault Not Empty

**Error**: `InvalidRequestException: Backup vault cannot be deleted because it contains recovery points`

**Solution**:
1. List all recovery points:
   ```bash
   aws backup list-recovery-points-by-backup-vault \
     --backup-vault-name "$VAULT_NAME" \
     --region "$AWS_REGION"
   ```

2. Delete each recovery point individually
3. Wait for deletions to complete (may take time)
4. Verify vault is empty:
   ```bash
   aws backup describe-backup-vault \
     --backup-vault-name "$VAULT_NAME" \
     --region "$AWS_REGION" \
     --query 'NumberOfRecoveryPoints'
   ```

5. Then delete the vault

### Issue: Recovery Point Still Exists After Deletion

**Solution**:
- Deletion is asynchronous and may take time
- Wait 5-10 minutes and check again
- Some recovery points with retention policies cannot be deleted immediately
- Check AWS Console for deletion status

### Issue: Permission Denied

**Error**: `AccessDeniedException`

**Solution**:
- Ensure your AWS credentials have the following permissions:
  - `backup:DeleteRecoveryPoint`
  - `backup:ListRecoveryPointsByBackupVault`
  - `backup:DeleteBackupVault`
  - `backup:DescribeBackupVault`

- Check IAM policies:
  ```bash
  aws iam get-user-policy --user-name <username> --policy-name <policy-name>
  ```

## Verification

After cleanup, verify everything is deleted:

```bash
# Check vault exists (should fail)
aws backup describe-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION" 2>&1 | grep -q "ResourceNotFoundException" && \
  echo "✓ Vault deleted" || echo "✗ Vault still exists"

# Check AMI still exists (should fail)
aws ec2 describe-images \
  --image-ids ami-09bcdf46592428068 \
  --region "$AWS_REGION" 2>&1 | grep -q "InvalidAMIID.NotFound" && \
  echo "✓ AMI deleted" || echo "✗ AMI still exists"

# List all backup vaults
aws backup list-backup-vaults \
  --region "$AWS_REGION" \
  --query 'BackupVaultList[?BackupVaultName==`'"$VAULT_NAME"'`]' \
  --output table

# Should return empty if deleted
```

## Using AWS Console

You can also clean up via AWS Console:

1. **Navigate to AWS Backup Console**
   - Go to: https://console.aws.amazon.com/backup
   - Select region: `us-east-1`

2. **Delete Recovery Points**
   - Click "Protected resources" → "Backups"
   - Find your backup vault
   - Select recovery points
   - Click "Delete"

3. **Delete Backup Vault**
   - Go to "Backup vaults"
   - Select your vault
   - Click "Delete" (only if empty)

## Related Resources

- [AWS Backup Documentation](https://docs.aws.amazon.com/aws-backup/)
- [AWS Backup CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/backup/)
- [AWS Backup Testing Guide](./aws-backup-testing-guide.md)
- [Test Script README](../scripts/README-aws-backup-test.md)

## IAM Role and Policy Cleanup

If you manually created the `AWSBackupDefaultServiceRole` IAM role during testing, you may want to clean it up as well.

### Check IAM Role

```bash
# Check if role exists
aws iam get-role --role-name AWSBackupDefaultServiceRole

# List attached policies
aws iam list-attached-role-policies --role-name AWSBackupDefaultServiceRole
```

### Delete IAM Role

**Important Considerations**:
- The `AWSBackupDefaultServiceRole` is a standard AWS Backup service role
- If you plan to use AWS Backup again, you should **keep** this role
- If this was only for testing and you won't use AWS Backup again, you can delete it
- **AWS-managed policies** (like `AWSBackupServiceRolePolicyForBackup`) don't need to be deleted - they're provided by AWS

#### Step 1: Detach Policies

```bash
# Detach backup policy
aws iam detach-role-policy \
  --role-name AWSBackupDefaultServiceRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup

# Detach restore policy
aws iam detach-role-policy \
  --role-name AWSBackupDefaultServiceRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores
```

#### Step 2: Delete Role

```bash
# Delete the role
aws iam delete-role --role-name AWSBackupDefaultServiceRole
```

### Complete IAM Cleanup Script

```bash
#!/bin/bash

ROLE_NAME="AWSBackupDefaultServiceRole"

echo "Checking IAM role: $ROLE_NAME"

# Check if role exists
if ! aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
    echo "Role does not exist, nothing to clean up"
    exit 0
fi

echo "Role exists, proceeding with cleanup..."

# Detach policies
echo "Detaching policies..."
aws iam detach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup \
  2>/dev/null || echo "Backup policy may not be attached"

aws iam detach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores \
  2>/dev/null || echo "Restore policy may not be attached"

# Delete role
echo "Deleting role..."
if aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null; then
    echo "✓ Role deleted successfully"
else
    echo "✗ Failed to delete role (may be in use or have other dependencies)"
fi
```

### When to Keep vs Delete IAM Role

**Keep the role if**:
- ✅ You plan to use AWS Backup again in the future
- ✅ Other backup jobs or vaults might use this role
- ✅ You're in a shared AWS account

**Delete the role if**:
- ✅ This was only for testing purposes
- ✅ You won't use AWS Backup again
- ✅ You want to clean up all test resources
- ✅ You're in a personal/test AWS account

## Summary

Complete cleanup process:
1. ✅ List recovery points in vault
2. ✅ Delete each recovery point (deletes AMI and snapshots)
3. ✅ Wait for deletions to complete
4. ✅ Verify vault is empty
5. ✅ Delete backup vault
6. ⚠️ **Optional**: Delete IAM role (if created for testing only)

**Note**: Recovery point deletion is asynchronous and may take time. Some recovery points with retention policies cannot be deleted immediately.

**Important**: AWS-managed policies (like `AWSBackupServiceRolePolicyForBackup`) are provided by AWS and don't need to be deleted. Only the IAM role itself needs to be deleted if you want to remove it.
