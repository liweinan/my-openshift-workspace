# OCP-29064: IPI Installer with KMS configuration [invalid key]

## Test Case Description
**OCP-29064**: `[ipi-on-aws] IPI Installer with KMS configuration [invalid key]`

This test case verifies that the OpenShift installer can properly handle invalid KMS key configurations. By attempting to create a cluster with a KMS key region that doesn't match the cluster region, it validates that the installer can correctly identify and report errors.

## Test Objectives
- Verify error handling when KMS key region doesn't match cluster region
- Ensure installer can correctly identify invalid KMS configurations
- Verify accuracy and usefulness of error messages
- Test cluster destruction functionality in failure scenarios

## Prerequisites
- Linux environment
- AWS credentials configured
- `openshift-install` tool installed
- SSH key pair configured
- pull-secret file prepared
- `jq` and `yq` tools installed

## Test Steps

### Step 1: Get User ARN
```bash
# Get current user ARN
aws sts get-caller-identity --output json | jq -r .Arn
# Example output: arn:aws:iam::301721915996:user/yunjiang
```

### Step 2: Create KMS Key
```bash
# Create KMS key in us-east-2 region
aws kms create-key \
  --region us-east-2 \
  --description "testing" \
  --output json \
  --policy '{
    "Id": "key-consolepolicy-3",
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "Enable IAM User Permissions",
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::301721915996:user/yunjiang"
        },
        "Action": "kms:*",
        "Resource": "*"
      }
    ]
  }'
```

**Expected Result**: KMS key created successfully, record KeyId and ARN.

### Step 3: Create install-config
```bash
# Create install-config.yaml
openshift-install create install-config --dir demo1
```

### Step 4: Modify Configuration File, Add Invalid KMS Key
```yaml
# Add KMS configuration in install-config.yaml
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      rootVolume:
        kmsKeyARN: arn:aws:kms:us-east-2:301721915996:key/4f5265b4-16f7-4d85-9a09-7209ab0c8456
  replicas: 3
platform:
  aws:
    region: ap-northeast-1  # Note: KMS key is in us-east-2, but cluster is in ap-northeast-1
```

**Key Point**: KMS key is created in `us-east-2` region, but cluster is configured in `ap-northeast-1` region, this will cause a region mismatch error.

### Step 5: Attempt Cluster Creation (Should Fail)
```bash
# Attempt to create cluster
openshift-install create cluster --dir demo1
```

**Expected Result**: Cluster creation fails with error similar to:
```
Error: Error waiting for instance (i-xxx) to become ready: Failed to reach target state. Reason: Client.InternalError: Client error on launch
```

### Step 6: Destroy Cluster
```bash
# Destroy cluster (cleanup)
openshift-install destroy cluster --dir demo1
```

**Expected Result**: Cluster destruction successful.

## Automation Scripts

### 1. test-invalid-kms-key.sh
Complete automated test script that executes all test steps:

```bash
# Basic usage
./test-invalid-kms-key.sh

# Custom parameters
./test-invalid-kms-key.sh \
  -k us-west-2 \
  -c us-east-1 \
  -n my-invalid-kms-test \
  -v
```

**Parameter Description**:
- `-w, --work-dir`: Working directory (default: demo1)
- `-n, --name`: Cluster name (default: invalid-kms-test)
- `-k, --kms-region`: KMS key region (default: us-east-2)
- `-c, --cluster-region`: Cluster region (default: ap-northeast-1)
- `-d, --description`: KMS key description
- `-v, --verbose`: Verbose output
- `--no-cleanup`: Do not clean up test environment

### 2. verify-kms-config.sh
Script specifically for verifying KMS configurations:

```bash
# Verify install-config.yaml in current directory
./verify-kms-config.sh

# Verify configuration in specified directory
./verify-kms-config.sh -w /path/to/install/config

# Detailed output
./verify-kms-config.sh -v
```

## Verification Criteria

### Success Criteria
1. **KMS Key Creation Success**: KMS key successfully created in specified region
2. **Configuration Modified Correctly**: install-config.yaml correctly contains KMS key ARN
3. **Region Mismatch**: KMS key region doesn't match cluster region
4. **Cluster Creation Failed**: Cluster creation fails due to invalid KMS configuration
5. **Error Message Accurate**: Error message contains KMS-related Client error
6. **Cleanup Success**: Can successfully destroy cluster and clean up resources

### Detailed Verification Methods

#### 1. Check AWS Instance Status (Recommended Method)
This is the most direct and accurate verification method:

```bash
# Check status and error reasons for all related instances
aws ec2 describe-instances \
  --region <cluster-region> \
  --filters "Name=tag:Name,Values=<cluster-name>-*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,StateReason.Message]' \
  --output table
```

**Expected Result**: All instances have `terminated` status, error reasons are KMS-related:
```
|  i-xxxxxxxxxxxxxxxxx|  terminated |  Client.InvalidKMSKey.InvalidState: The KMS key provided is in an incorrect state   |
|  i-yyyyyyyyyyyyyyyyy|  terminated |  Client.InvalidKMSKey.InvalidState: The KMS key provided is in an incorrect state   |
```

#### 2. Check KMS Key Configuration
```bash
# Check KMS key status and region
aws kms describe-key --region <kms-region> --key-id <key-id>
```

**Expected Result**: 
- `KeyState: "Enabled"`
- `MultiRegion: false` (single region key)
- Key created in specified region

#### 3. Check install-config.yaml Configuration
```bash
# Verify KMS configuration
./verify-kms-config.sh

# Or manual check
yq eval '.controlPlane.platform.aws.rootVolume.kmsKeyARN' install-config.yaml
yq eval '.platform.aws.region' install-config.yaml
```

**Expected Result**: 
- KMS key ARN points to key in different region
- Cluster region doesn't match KMS key region

#### 4. Check Installation Logs
```bash
# Search for error information
grep -i "error\|failed" .openshift_install.log | tail -20

# Search for KMS-related errors
grep -i "kms\|key" .openshift_install.log | tail -10
```

**Expected Result**: Logs contain KMS-related error information

#### 5. Check Cluster API Resource Status
```bash
# Check AWSMachine resource status
cat .clusterapi_output/AWSMachine-*-master-*.yaml | grep -A 10 "status:"

# Or use kubectl (if available)
kubectl get awsmachines -o yaml | grep -A 5 "failurereason\|failuremessage"
```

**Expected Result**: 
- `instancestate: terminated`
- `failurereason: UpdateError`
- `failuremessage: EC2 instance state "terminated" is unexpected`

### Verification Commands Summary
```bash
# 1. Check instance status (most important)
aws ec2 describe-instances \
  --region us-east-1 \
  --filters "Name=tag:Name,Values=weli-testy-*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,StateReason.Message]' \
  --output table

# 2. Check KMS key
aws kms describe-key --region us-east-2 --key-id <key-id>

# 3. Verify configuration file
./verify-kms-config.sh

# 4. Check logs
grep -i "error\|kms\|key" .openshift_install.log | tail -10
```

## Troubleshooting

### Common Issues

#### 1. KMS Key Creation Failed
```bash
# Check AWS credentials
aws sts get-caller-identity

# Check permissions
aws iam get-user

# Check region availability
aws kms list-keys --region us-east-2
```

#### 2. Cluster Creation Unexpectedly Succeeded
```bash
# Check region configuration
yq eval '.platform.aws.region' install-config.yaml
yq eval '.controlPlane.platform.aws.rootVolume.kmsKeyARN' install-config.yaml

# Verify KMS key region
aws kms describe-key --region us-east-2 --key-id <key-id>

# Check instance status (if cluster creation succeeded, instances should be running normally)
aws ec2 describe-instances \
  --region <cluster-region> \
  --filters "Name=tag:Name,Values=<cluster-name>-*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table
```

#### 3. Error Message Not Clear
```bash
# Check detailed logs
openshift-install create cluster --dir demo1 --log-level debug

# Check Terraform logs
tail -f .openshift_install.log

# Directly check instance status and error reasons (most accurate method)
aws ec2 describe-instances \
  --region <cluster-region> \
  --filters "Name=tag:Name,Values=<cluster-name>-*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,StateReason.Message]' \
  --output table

# Check Cluster API resource status
cat .clusterapi_output/AWSMachine-*-master-*.yaml | grep -A 5 "failurereason\|failuremessage"
```

#### 4. Cleanup Failed
```bash
# Manually clean up KMS key
aws kms schedule-key-deletion --region us-east-2 --key-id <key-id> --pending-window-in-days 7

# Manually clean up EC2 resources
aws ec2 describe-instances --filters "Name=tag:Name,Values=<cluster-name>-*"
```

## Cleanup Steps
```bash
# Destroy cluster
openshift-install destroy cluster --dir demo1

# Clean up KMS key
aws kms schedule-key-deletion \
  --region us-east-2 \
  --key-id <key-id> \
  --pending-window-in-days 7

# Clean up working directory
rm -rf demo1
```

## Related Test Cases
- **OCP-29060**: IPI Installer with KMS configuration [master]
- **OCP-29063**: IPI Installer with KMS configuration [worker]
- **OCP-29074**: AWS manual mode configuration CCO

## Test Result Determination

### How to Correctly Determine if Test Succeeded

#### ✅ Signs of Test Success
1. **Instance Status Check** (most important):
   ```bash
   aws ec2 describe-instances \
     --region <cluster-region> \
     --filters "Name=tag:Name,Values=<cluster-name>-*" \
     --query 'Reservations[*].Instances[*].[InstanceId,State.Name,StateReason.Message]' \
     --output table
   ```
   **Expected Result**: All instances have `terminated` status, error reasons contain KMS-related errors

2. **Error Type Verification**:
   - `Client.InvalidKMSKey.InvalidState`
   - `Client.InternalError: Client error on launch`
   - Or other KMS-related Client errors

3. **Cluster Creation Failed**: Installation process ultimately fails, cannot complete cluster creation

#### ❌ Signs of Test Failure
1. **Cluster Creation Succeeded**: Instances running normally, cluster fully deployed
2. **Error Reason Not Relevant**: Instance failure reason is not KMS-related
3. **Configuration Error**: KMS key and cluster are in same region

#### Common Error Message Comparison
| Error Type | Test Result | Description |
|---------|---------|------|
| `Client.InvalidKMSKey.InvalidState` | ✅ Success | KMS key region mismatch |
| `Client.InternalError: Client error on launch` | ✅ Success | KMS-related launch error |
| `no such host` / `context deadline exceeded` | ❓ Need further check | May be network issue, need to check instance status |
| Cluster creation successful | ❌ Failure | Configuration may have issues |

### Verification Priority
1. **First Priority**: Check AWS instance status and error reasons
2. **Second Priority**: Verify KMS key configuration and region
3. **Third Priority**: Check error information in installation logs

## Notes
1. **Region Mismatch**: Ensure KMS key region is different from cluster region
2. **Permission Configuration**: Ensure KMS key policy contains correct user permissions
3. **Error Expectation**: This test expects cluster creation to fail
4. **Cleanup Important**: Clean up KMS keys promptly to avoid charges
5. **Log Analysis**: Carefully analyze error logs to verify error type
6. **Instance Status Check**: Most accurate verification method is to directly check AWS instance status

## Practical Application Value
This test verifies functionality important for:
- Understanding KMS key region limitations
- Verifying error handling mechanisms
- Ensuring configuration validation accuracy
- Testing cleanup functionality in failure scenarios

Very important for production environment configuration validation and error handling.