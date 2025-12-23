# AWS Backup Manual Creation Guide

This guide provides step-by-step instructions for manually creating AWS Backup for OpenShift cluster instances. This is useful when you prefer manual control or need to understand each step of the process.

## Prerequisites

- AWS CLI installed and configured
- OpenShift cluster installation completed
- `metadata.json` file available in installation directory
- AWS credentials with permissions for:
  - EC2 (describe instances)
  - AWS Backup (create vault, start backup jobs)
  - IAM (create role, attach policies)

## Step-by-Step Instructions

### Step 1: Get Cluster Information

First, identify your cluster information from `metadata.json`:

```bash
cd ~/works/openshift-versions/work2

# Get cluster infrastructure ID
export CLUSTER_ID=$(jq -r '.infraID' metadata.json)
echo "Cluster ID: $CLUSTER_ID"

# Get AWS region
export AWS_REGION=$(jq -r '.aws.region' metadata.json)
echo "Region: $AWS_REGION"

# Get AWS account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"
```

**Example Output**:
```
Cluster ID: weli-test-6q9t4
Region: us-east-1
AWS Account ID: 301721915996
```

### Step 2: List Cluster Instances

List all instances in your cluster to select one for backup:

```bash
# List all cluster instances
aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_ID},Values=owned" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

**Example Output**:
```
---------------------------------------------------------------------------------------------
|                                     DescribeInstances                                     |
+----------------------+-------------+----------+-------------------------------------------+
|  i-0db6e9b9d2e23e4d8 |  m6i.xlarge |  running |  weli-test-6q9t4-master-2                 |
|  i-0eb07aa15582ca2df |  m6i.xlarge |  running |  weli-test-6q9t4-worker-us-east-1d-ccmjn  |
|  i-0b5d45a3b9e06239e |  m6i.xlarge |  running |  weli-test-6q9t4-master-1                 |
|  i-0368eaa7273bad511 |  m6i.xlarge |  running |  weli-test-6q9t4-worker-us-east-1c-lkfcz  |
|  i-0cee5f3aaf42c40e8 |  m6i.xlarge |  running |  weli-test-6q9t4-worker-us-east-1f-vfw4w  |
|  i-03ddc45af66f00cd2 |  m6i.xlarge |  running |  weli-test-6q9t4-master-0                 |
+----------------------+-------------+----------+-------------------------------------------+
```

### Step 3: Select Instance for Backup

Choose an instance to backup. Typically, you would select a master node:

```bash
# Set the instance ID (replace with your chosen instance)
export INSTANCE_ID="i-0db6e9b9d2e23e4d8"

# Verify the instance
aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' \
  --output table
```

### Step 4: Create Backup Vault

Create a backup vault to store your backups:

```bash
# Set vault name (using cluster ID)
export VAULT_NAME="${CLUSTER_ID}-backup-vault"
echo "Vault Name: $VAULT_NAME"

# Create backup vault
aws backup create-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION"
```

**Expected Output**:
```json
{
    "BackupVaultName": "weli-test-6q9t4-backup-vault",
    "BackupVaultArn": "arn:aws:backup:us-east-1:301721915996:backup-vault:weli-test-6q9t4-backup-vault",
    "CreationDate": "2025-12-11T16:39:11.988000+08:00"
}
```

**Verify vault creation**:
```bash
aws backup describe-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION"
```

### Step 5: Check IAM Role

Check if the AWS Backup service role exists:

```bash
# Check if role exists
aws iam get-role --role-name AWSBackupDefaultServiceRole 2>/dev/null || echo "Role does not exist"
```

**If role exists**, get the role ARN:
```bash
export BACKUP_ROLE_ARN=$(aws iam get-role \
  --role-name AWSBackupDefaultServiceRole \
  --query 'Role.Arn' \
  --output text)
echo "Role ARN: $BACKUP_ROLE_ARN"
```

**If role does not exist**, create it:

#### 5.1: Create Trust Policy File

```bash
cat > backup-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "backup.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
```

#### 5.2: Create IAM Role

```bash
aws iam create-role \
  --role-name AWSBackupDefaultServiceRole \
  --assume-role-policy-document file://backup-trust-policy.json \
  --description "Default service role for AWS Backup"
```

**Expected Output**:
```json
{
    "Role": {
        "Path": "/",
        "RoleName": "AWSBackupDefaultServiceRole",
        "RoleId": "AROAUMQAHCJOKD7J6JZ47",
        "Arn": "arn:aws:iam::301721915996:role/AWSBackupDefaultServiceRole",
        "CreateDate": "2025-12-11T08:47:48+00:00",
        ...
    }
}
```

#### 5.3: Attach Policies

```bash
# Attach backup policy
aws iam attach-role-policy \
  --role-name AWSBackupDefaultServiceRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup

# Attach restore policy
aws iam attach-role-policy \
  --role-name AWSBackupDefaultServiceRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores
```

#### 5.4: Verify Policies

```bash
aws iam list-attached-role-policies \
  --role-name AWSBackupDefaultServiceRole \
  --output table
```

**Expected Output**:
```
----------------------------------------
|      ListAttachedRolePolicies      |
+------------------------------------+
|  AWSBackupServiceRolePolicyForBackup |
|  AWSBackupServiceRolePolicyForRestores|
+------------------------------------+
```

#### 5.5: Get Role ARN

```bash
export BACKUP_ROLE_ARN=$(aws iam get-role \
  --role-name AWSBackupDefaultServiceRole \
  --query 'Role.Arn' \
  --output text)
echo "Backup Role ARN: $BACKUP_ROLE_ARN"
```

**Note**: The role ARN path may be `/` (not `/service-role/`). Use the actual ARN from the output.

### Step 6: Create Instance ARN

Create the instance ARN for the backup job:

```bash
export INSTANCE_ARN="arn:aws:ec2:${AWS_REGION}:${AWS_ACCOUNT_ID}:instance/${INSTANCE_ID}"
echo "Instance ARN: $INSTANCE_ARN"
```

**Example**:
```
Instance ARN: arn:aws:ec2:us-east-1:301721915996:instance/i-0db6e9b9d2e23e4d8
```

### Step 7: Start Backup Job

Create the on-demand backup job:

```bash
aws backup start-backup-job \
  --backup-vault-name "$VAULT_NAME" \
  --resource-arn "$INSTANCE_ARN" \
  --iam-role-arn "$BACKUP_ROLE_ARN" \
  --region "$AWS_REGION" \
  --output json > backup-job.json
```

**Expected Output** (saved to `backup-job.json`):
```json
{
    "BackupJobId": "5b5d4f88-13e6-4300-a633-ee776f169238",
    "CreationDate": "2025-12-11T16:54:48.097000+08:00",
    "IsParent": false
}
```

**Get backup job ID**:
```bash
export BACKUP_JOB_ID=$(jq -r '.BackupJobId' backup-job.json)
echo "Backup Job ID: $BACKUP_JOB_ID"
```

### Step 8: Monitor Backup Job

Check the backup job status:

```bash
# Check current status
aws backup describe-backup-job \
  --backup-job-id "$BACKUP_JOB_ID" \
  --region "$AWS_REGION"
```

**Initial Status** (RUNNING):
```json
{
    "BackupJobId": "5b5d4f88-13e6-4300-a633-ee776f169238",
    "State": "RUNNING",
    "PercentDone": "0.0",
    "RecoveryPointArn": "arn:aws:ec2:us-east-1::image/ami-09bcdf46592428068",
    ...
}
```

**Monitor progress** (optional):
```bash
while true; do
  STATUS=$(aws backup describe-backup-job \
    --backup-job-id "$BACKUP_JOB_ID" \
    --region "$AWS_REGION" \
    --query 'State' \
    --output text)
  
  PERCENT=$(aws backup describe-backup-job \
    --backup-job-id "$BACKUP_JOB_ID" \
    --region "$AWS_REGION" \
    --query 'PercentDone' \
    --output text)
  
  echo "$(date): Status: $STATUS, Progress: $PERCENT%"
  
  if [ "$STATUS" = "COMPLETED" ] || [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "ABORTED" ]; then
    break
  fi
  
  sleep 30
done
```

**Completed Status**:
```json
{
    "BackupJobId": "5b5d4f88-13e6-4300-a633-ee776f169238",
    "State": "COMPLETED",
    "PercentDone": "100.0",
    "CompletionDate": "2025-12-11T17:31:06.950000+08:00",
    "BackupSizeInBytes": 128849018880,
    "RecoveryPointArn": "arn:aws:ec2:us-east-1::image/ami-09bcdf46592428068",
    ...
}
```

### Step 9: Verify Backup Resources

After backup completes, verify the created resources:

#### 9.1: Check AMI

```bash
# Get AMI ID from recovery point ARN
AMI_ID=$(aws backup describe-backup-job \
  --backup-job-id "$BACKUP_JOB_ID" \
  --region "$AWS_REGION" \
  --query 'RecoveryPointArn' \
  --output text | sed 's/.*image\///')

echo "AMI ID: $AMI_ID"

# Check AMI status
aws ec2 describe-images \
  --image-ids "$AMI_ID" \
  --region "$AWS_REGION" \
  --query 'Images[0].[ImageId,State,Name,CreationDate]' \
  --output table
```

**Wait for AMI to be available** (may take a few minutes):
```bash
while true; do
  STATE=$(aws ec2 describe-images \
    --image-ids "$AMI_ID" \
    --region "$AWS_REGION" \
    --query 'Images[0].State' \
    --output text)
  
  echo "AMI State: $STATE"
  
  if [ "$STATE" = "available" ] || [ "$STATE" = "failed" ]; then
    break
  fi
  
  sleep 30
done
```

#### 9.2: Verify Backup Tag

Check that the AMI has the backup tag:

```bash
aws ec2 describe-images \
  --image-ids "$AMI_ID" \
  --region "$AWS_REGION" \
  --query 'Images[0].Tags[?Key==`aws:backup:source-resource`]' \
  --output table
```

**Expected Output**:
```
--------------------------------------------------------------------------------------------
|                                      DescribeImages                                      |
+-----------------------------+------------------------------------------------------------+
|             Key             |                           Value                            |
+-----------------------------+------------------------------------------------------------+
|  aws:backup:source-resource |  i-0db6e9b9d2e23e4d8:5b5d4f88-13e6-4300-a633-ee776f169238  |
+-----------------------------+------------------------------------------------------------+
```

#### 9.3: List All Backup AMIs

```bash
aws ec2 describe-images \
  --region "$AWS_REGION" \
  --filters "Name=tag:aws:backup:source-resource,Values=*" \
            "Name=tag:kubernetes.io/cluster/${CLUSTER_ID},Values=owned" \
  --query 'Images[*].[ImageId,Name,State]' \
  --output table
```

### Step 10: Save Backup Information

Save the backup information for future reference:

```bash
cat > backup-info.json <<EOF
{
  "backupJobId": "$BACKUP_JOB_ID",
  "backupVaultName": "$VAULT_NAME",
  "instanceId": "$INSTANCE_ID",
  "region": "$AWS_REGION",
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

cat backup-info.json
```

## Complete Command Sequence

Here's a complete sequence you can copy and paste (adjust variables as needed):

```bash
# Step 1: Set variables
cd ~/works/openshift-versions/work2
export CLUSTER_ID=$(jq -r '.infraID' metadata.json)
export AWS_REGION=$(jq -r '.aws.region' metadata.json)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export INSTANCE_ID="i-0db6e9b9d2e23e4d8"  # Replace with your instance ID
export VAULT_NAME="${CLUSTER_ID}-backup-vault"

# Step 2: Create backup vault
aws backup create-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$AWS_REGION"

# Step 3: Check/create IAM role
if ! aws iam get-role --role-name AWSBackupDefaultServiceRole &> /dev/null; then
  cat > backup-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "backup.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
  
  aws iam create-role \
    --role-name AWSBackupDefaultServiceRole \
    --assume-role-policy-document file://backup-trust-policy.json \
    --description "Default service role for AWS Backup"
  
  aws iam attach-role-policy \
    --role-name AWSBackupDefaultServiceRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup
  
  aws iam attach-role-policy \
    --role-name AWSBackupDefaultServiceRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores
fi

export BACKUP_ROLE_ARN=$(aws iam get-role \
  --role-name AWSBackupDefaultServiceRole \
  --query 'Role.Arn' \
  --output text)

# Step 4: Create backup job
export INSTANCE_ARN="arn:aws:ec2:${AWS_REGION}:${AWS_ACCOUNT_ID}:instance/${INSTANCE_ID}"

aws backup start-backup-job \
  --backup-vault-name "$VAULT_NAME" \
  --resource-arn "$INSTANCE_ARN" \
  --iam-role-arn "$BACKUP_ROLE_ARN" \
  --region "$AWS_REGION" \
  --output json > backup-job.json

export BACKUP_JOB_ID=$(jq -r '.BackupJobId' backup-job.json)
echo "Backup Job ID: $BACKUP_JOB_ID"

# Step 5: Monitor (optional)
aws backup describe-backup-job \
  --backup-job-id "$BACKUP_JOB_ID" \
  --region "$AWS_REGION" \
  --query '[State,PercentDone]' \
  --output table
```

## Troubleshooting

### Issue: IAM Role ARN Path

**Problem**: Role ARN may be `arn:aws:iam::ACCOUNT:role/AWSBackupDefaultServiceRole` (not `/service-role/`)

**Solution**: Always use the actual ARN from `aws iam get-role`:
```bash
export BACKUP_ROLE_ARN=$(aws iam get-role \
  --role-name AWSBackupDefaultServiceRole \
  --query 'Role.Arn' \
  --output text)
```

### Issue: Backup Job Fails with Permission Error

**Problem**: "IAM Role does not have sufficient permissions"

**Solution**: 
1. Verify policies are attached:
   ```bash
   aws iam list-attached-role-policies --role-name AWSBackupDefaultServiceRole
   ```
2. Ensure both policies are attached
3. Wait a few seconds after attaching policies before creating backup job

### Issue: AMI State Stays "pending"

**Solution**: 
- This is normal - AMI creation takes 5-15 minutes
- Wait for backup job to complete first
- Then wait for AMI to become "available"

### Issue: Cannot Find Instance

**Solution**: 
- Ensure cluster installation completed
- Check instance is running:
  ```bash
  aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
  ```
- Verify cluster tag is correct

## Next Steps

After backup is created:

1. **Test Destroy**: Run `openshift-install destroy cluster` to verify detection
2. **Cleanup**: Use cleanup scripts when done testing
3. **Documentation**: See related guides for more information

## Related Documentation

- [AWS Backup Testing Guide](./aws-backup-testing-guide.md)
- [AWS Backup Testing Guide for weli-test Cluster](./aws-backup-testing-guide-weli-test.md)
- [AWS Backup Cleanup Guide](./aws-backup-cleanup-guide.md)
- [AWS Backup Deletion Detection Mechanism](./aws-backup-deletion-detection-mechanism.md)
- [Create AWS Backup Script](../scripts/README-create-aws-backup.md)
