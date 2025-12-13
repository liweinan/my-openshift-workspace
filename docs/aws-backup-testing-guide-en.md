# AWS Backup Testing Guide

This guide describes how to test AWS Backup functionality, including creating backups, verifying backup status, and verifying the protection mechanism for backup resources during cluster destruction.

## Prerequisites

1. A deployed OpenShift cluster
2. AWS CLI configured with appropriate permissions
3. Cluster INFRA_ID (for identifying cluster resources)

## Test Steps

### 1. Find Cluster Instances

First, find all instances in the cluster:

```bash
export INFRA_ID="weli-test-6q9t4"  # Replace with actual INFRA_ID
export AWS_REGION="us-east-1"      # Replace with actual region

aws ec2 describe-instances \
  --region ${AWS_REGION} \
  --filters "Name=tag:kubernetes.io/cluster/${INFRA_ID},Values=owned" \
            "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

### 2. Get AWS Account ID

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
```

### 3. Create Backup Vault

Create a backup vault:

```bash
export BACKUP_VAULT_NAME="weli-test-backup-vault"

aws backup create-backup-vault \
  --backup-vault-name ${BACKUP_VAULT_NAME} \
  --region ${AWS_REGION}
```

Verify vault creation:

```bash
aws backup describe-backup-vault \
  --backup-vault-name ${BACKUP_VAULT_NAME} \
  --region ${AWS_REGION}
```

### 4. Create IAM Role

Check if IAM role exists:

```bash
aws iam get-role \
  --role-name AWSBackupDefaultServiceRole \
  --region ${AWS_REGION} 2>/dev/null || echo "Role does not exist"
```

If the role does not exist, create it:

#### 4.1 Create Trust Policy File

Create `backup-trust-policy.json` file:

```json
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
```

#### 4.2 Create IAM Role

```bash
aws iam create-role \
  --role-name AWSBackupDefaultServiceRole \
  --assume-role-policy-document file://backup-trust-policy.json \
  --description "Default service role for AWS Backup"
```

#### 4.3 Attach Required Policies

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

#### 4.4 Verify Role Configuration

```bash
aws iam get-role --role-name AWSBackupDefaultServiceRole
aws iam list-attached-role-policies --role-name AWSBackupDefaultServiceRole
```

#### 4.5 Set Role ARN

```bash
export BACKUP_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/AWSBackupDefaultServiceRole"
echo "Backup Role ARN: ${BACKUP_ROLE_ARN}"
```

### 5. Start Backup Job

Select an instance for backup testing:

```bash
export INSTANCE_ID="i-0db6e9b9d2e23e4d8"  # Replace with actual instance ID
export INSTANCE_ARN="arn:aws:ec2:${AWS_REGION}:${AWS_ACCOUNT_ID}:instance/${INSTANCE_ID}"
echo "Instance ARN: ${INSTANCE_ARN}"
```

Start the backup job:

```bash
aws backup start-backup-job \
  --backup-vault-name ${BACKUP_VAULT_NAME} \
  --resource-arn "${INSTANCE_ARN}" \
  --iam-role-arn "${BACKUP_ROLE_ARN}" \
  --region ${AWS_REGION} \
  --output json > backup-job.json

export BACKUP_JOB_ID=$(jq -r '.BackupJobId' backup-job.json)
echo "Backup Job ID: ${BACKUP_JOB_ID}"
```

### 6. Monitor Backup Status

Check backup job status:

```bash
aws backup describe-backup-job \
  --backup-job-id "${BACKUP_JOB_ID}" \
  --region ${AWS_REGION}
```

The backup status will change from `RUNNING` to `COMPLETED`. After the backup completes, an AMI will be created.

### 7. Verify Backup-Created AMI

Get Recovery Point ARN from backup job description (format: `arn:aws:ec2:us-east-1::image/ami-xxxxx`):

```bash
export RECOVERY_POINT_ARN=$(aws backup describe-backup-job \
  --backup-job-id "${BACKUP_JOB_ID}" \
  --region ${AWS_REGION} \
  --query 'RecoveryPointArn' --output text)

echo "Recovery Point ARN: ${RECOVERY_POINT_ARN}"
```

Extract the complete AMI ID (including `ami-` prefix) from Recovery Point ARN:

```bash
export AMI_ID=$(echo ${RECOVERY_POINT_ARN} | sed 's|.*/||')
echo "AMI ID: ${AMI_ID}"
```

Or extract directly from backup job output:

```bash
export AMI_ID=$(aws backup describe-backup-job \
  --backup-job-id "${BACKUP_JOB_ID}" \
  --region ${AWS_REGION} \
  --query 'RecoveryPointArn' --output text | sed 's|.*/||')
```

Check AMI status:

```bash
aws ec2 describe-images \
  --image-ids ${AMI_ID} \
  --region ${AWS_REGION} \
  --query 'Images[0].[ImageId,State,Name,CreationDate]' \
  --output table
```

AMI status will change from `pending` to `available`.

### 8. Verify AMI Tags

Check if AMI contains backup-related tags:

```bash
aws ec2 describe-images \
  --image-ids ${AMI_ID} \
  --region ${AWS_REGION} \
  --query 'Images[0].Tags[?Key==`aws:backup:source-resource`]' \
  --output table
```

### 9. Find All Backup-Created AMIs

Find all AMIs created by AWS Backup that belong to this cluster:

```bash
aws ec2 describe-images \
  --region ${AWS_REGION} \
  --filters "Name=tag:aws:backup:source-resource,Values=*" \
            "Name=tag:kubernetes.io/cluster/${INFRA_ID},Values=owned" \
  --query 'Images[*].[ImageId,Name,State]' \
  --output table
```

### 10. Test Protection Mechanism During Cluster Destruction

Destroy the cluster and verify that backup resources are protected:

```bash
openshift-install destroy cluster
```

In the destruction output, you should see the following warning messages indicating that backup resources are skipped:

#### AMI (Amazon Machine Image) Warning

When backing up an EC2 instance, AWS Backup creates an AMI (containing the instance's root volume snapshot). openshift-install proactively detects and skips deletion:

```
level=warning msg=Skipping AMI image ami-09bcdf46592428068 deletion since it is managed by the AWS Backup service. To delete this image, please use the AWS Backup APIs, CLI, or console id=ami-09bcdf46592428068 resourceType=image
```

**Characteristics**:
- Instance-level backup
- Contains instance configuration and root volume snapshot
- openshift-install proactively detects and skips deletion (preventive protection)

#### EBS Snapshot Warning

When an instance has attached EBS volumes, AWS Backup creates independent snapshots for these volumes. openshift-install attempts to delete them, but AWS API returns an error:

```
level=warning msg=Skipping snapshot snap-0bc7352ba38eb5f5c deletion error=operation error EC2: DeleteSnapshot, https response error StatusCode: 400, RequestID: 49a13435-f383-4a64-bc5f-7ddcd12ee5a7, api error InvalidParameterValue: This snapshot is managed by the AWS Backup service and cannot be deleted via EC2 APIs. If you wish to delete this snapshot, please do so via the Backup console. id=snap-0bc7352ba38eb5f5c resourceType=snapshot
```

**Characteristics**:
- Volume-level backup
- Contains snapshot of a single EBS volume only
- openshift-install attempts deletion but is rejected by AWS API (API-level protection)

**Summary of Differences**:
- **AMI**: Instance backup, openshift-install proactively skips (detects backup tags)
- **EBS Snapshot**: Volume backup, openshift-install attempts deletion but is rejected by AWS API

## Verification Points

1. **Backup job completed successfully**: `State` should be `COMPLETED`, `PercentDone` should be `100.0`
2. **AMI created successfully**: AMI status should be `available`
3. **Tags correct**: AMI should contain `aws:backup:source-resource` tag
4. **Protection mechanism works**: During cluster destruction, backup resources should be skipped and not deleted

## Cleanup

If you need to clean up backup resources:

```bash
# List all recovery points
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name ${BACKUP_VAULT_NAME} \
  --region ${AWS_REGION}

# Delete recovery point (will delete corresponding AMI and snapshot)
aws backup delete-recovery-point \
  --backup-vault-name ${BACKUP_VAULT_NAME} \
  --recovery-point-arn "${RECOVERY_POINT_ARN}" \
  --region ${AWS_REGION}

# Delete backup vault (requires deleting all recovery points first)
aws backup delete-backup-vault \
  --backup-vault-name ${BACKUP_VAULT_NAME} \
  --region ${AWS_REGION}
```

## Troubleshooting

### Error: IAM Role does not have sufficient permissions

**Cause**: IAM role is missing required policies.

**Solution**:
1. Confirm that `AWSBackupServiceRolePolicyForBackup` policy is attached
2. Confirm role ARN format is correct (does not include `/service-role/` path)

### Backup job stays in RUNNING state

**Possible causes**:
1. Instance is in use, backup takes time
2. Instance size is large, backup takes longer

**Solution**: Wait for backup to complete. Monitor progress via `PercentDone` field.

### AMI status stays pending

**Cause**: AMI creation takes time, especially for large instances.

**Solution**: Wait for AMI status to change to `available`. Usually takes several minutes to tens of minutes, depending on instance size.

## References

- [AWS Backup Documentation](https://docs.aws.amazon.com/aws-backup/)
- [AWS Backup IAM Role Configuration](https://docs.aws.amazon.com/aws-backup/latest/devguide/using-service-linked-roles.html)
