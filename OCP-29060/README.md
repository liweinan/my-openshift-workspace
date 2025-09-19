# OCP-29060: KMS Configuration Verification

This directory contains scripts and documentation for the **OCP-29060** test case: `[ipi-on-aws] IPI Installer with KMS configuration [master]`.

## Test Case Overview

**OCP-29060** verifies that OpenShift clusters can be created with custom KMS encryption for master node volumes, while worker nodes use the default AWS KMS key.

### Test Steps

1. **Create KMS key** in AWS region
2. **Create install-config** with KMS configuration
3. **Modify install-config** to add KMS key to master nodes
4. **Create cluster** with KMS configuration
5. **Extract infraID** from metadata.json
6. **Verify master volumes** are encrypted with custom KMS key
7. **Verify worker volumes** are encrypted with default AWS KMS key
8. **Destroy cluster** successfully

## Files

- `create-kms-key.sh` - KMS key creation script
- `verify-kms-encryption.sh` - KMS encryption verification script
- `README.md` - This documentation file

## Prerequisites

- AWS CLI configured with appropriate permissions
- `oc` (OpenShift CLI) installed
- `jq` command-line tool installed
- Access to the OpenShift cluster via kubeconfig
- `metadata.json` file from the installation
- Installer working directory with `install-config.yaml`

## Usage

### Step 1: Create KMS Key

```bash
# Basic usage - create KMS key in us-east-2
./create-kms-key.sh

# Specify different region
./create-kms-key.sh -r us-west-2

# Custom description
./create-kms-key.sh -d "My OpenShift cluster encryption key"

# Use custom key policy
./create-kms-key.sh -p custom-policy.json

# Dry run to see what would be created
./create-kms-key.sh --dry-run
```

### Step 2: Create and Configure Cluster

```bash
# Create install-config
openshift-install create install-config --dir demo1

# Modify install-config.yaml to add KMS key to master nodes
# Add the following to controlPlane section:
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      rootVolume:
        kmsKeyARN: arn:aws:kms:us-east-2:123456789012:key/12345678-1234-1234-1234-123456789012
  replicas: 3

# Create cluster
openshift-install create cluster --dir demo1
```

### Step 3: Verify KMS Encryption

```bash
# Basic verification
./verify-kms-encryption.sh \
  -k /path/to/kubeconfig \
  -m /path/to/metadata.json \
  -w /path/to/workdir

# With expected KMS keys
./verify-kms-encryption.sh \
  -k kubeconfig \
  -m metadata.json \
  -w workdir \
  --master-kms-key "arn:aws:kms:us-east-2:123456789012:key/12345678-1234-1234-1234-123456789012"

# Detailed output
./verify-kms-encryption.sh \
  -k kubeconfig \
  -m metadata.json \
  -w workdir \
  --detailed
```

## Parameters

### create-kms-key.sh

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `-r, --region` | AWS region | No | us-east-2 |
| `-d, --description` | Key description | No | "OpenShift cluster encryption key for testing" |
| `-p, --policy-file` | Path to custom key policy JSON file | No | Auto-generated |
| `-o, --output` | Output file for key information | No | kms-key-info.json |
| `--dry-run` | Show what would be created | No | false |

### verify-kms-encryption.sh

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `-k, --kubeconfig` | Path to kubeconfig file | Yes | - |
| `-m, --metadata` | Path to metadata.json file | Yes | - |
| `-w, --work-dir` | Path to installer working directory | Yes | - |
| `-r, --region` | AWS region | No | us-east-2 |
| `--master-kms-key` | Expected master KMS key ARN | No | Auto-detected |
| `--worker-kms-key` | Expected worker KMS key ARN | No | Default AWS KMS key |
| `--detailed` | Show detailed verification information | No | false |

## Verification Process

The verification script performs the following checks:

### 1. Cluster Information Extraction
- Extracts `infraID`, `clusterID`, and `clusterName` from `metadata.json`
- Validates cluster connection using kubeconfig

### 2. Volume Discovery
- Queries AWS EC2 instances using cluster tags
- Retrieves volume IDs for master and worker nodes
- Groups volumes by node type

### 3. KMS Encryption Verification
- Checks KMS key ID for each volume
- Verifies consistency within each node type
- Compares with expected KMS keys (if provided)

### 4. Expected Behavior
- **Master nodes**: Should use custom KMS key (if specified in install-config)
- **Worker nodes**: Should use default AWS KMS key for EBS
- **Consistency**: All volumes of the same node type should use the same KMS key

## Example Output

### KMS Key Creation
```
[INFO] Getting current user ARN...
[SUCCESS] User ARN: arn:aws:iam::123456789012:user/testuser
[INFO] Creating KMS key in region: us-east-2
[INFO] Description: OpenShift cluster encryption key for testing
[INFO] Using default key policy
[SUCCESS] KMS key created successfully!
[SUCCESS] Key ID: 12345678-1234-1234-1234-123456789012
[SUCCESS] Key ARN: arn:aws:kms:us-east-2:123456789012:key/12345678-1234-1234-1234-123456789012
[SUCCESS] Key information saved to: kms-key-info.json

Key information for install-config.yaml:
Key ID: 12345678-1234-1234-1234-123456789012
Key ARN: arn:aws:kms:us-east-2:123456789012:key/12345678-1234-1234-1234-123456789012

Add this to your install-config.yaml controlPlane section:
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      rootVolume:
        kmsKeyARN: arn:aws:kms:us-east-2:123456789012:key/12345678-1234-1234-1234-123456789012
  replicas: 3
```

### KMS Encryption Verification
```
[INFO] Using Kubeconfig: /path/to/kubeconfig
[INFO] Using Metadata: /path/to/metadata.json
[INFO] Using Work Directory: /path/to/workdir
[INFO] Using AWS Region: us-east-2
[INFO] Starting OCP-29060 KMS encryption verification...
[INFO] Extracting cluster information from metadata.json...
[SUCCESS] Extracted cluster information:
  - InfraID: test-cluster-abc123
  - ClusterID: d64b26be-5d5e-4bb2-a723-9c1e527d46bf
  - ClusterName: test-cluster
[INFO] Checking cluster connection...
[SUCCESS] Cluster connection successful
[INFO] Cluster ID: d64b26be-5d5e-4bb2-a723-9c1e527d46bf
[INFO] Getting default EBS KMS key for region us-east-2...
[INFO] Default EBS KMS key: arn:aws:kms:us-east-2:123456789012:key/9fe48bb2-a03e-4efe-86ec-4796e044cc8b
[INFO] Getting master node volumes...
[SUCCESS] Master nodes: All 3 volumes use the same KMS key
  KMS Key: arn:aws:kms:us-east-2:123456789012:key/12345678-1234-1234-1234-123456789012
[SUCCESS] Master nodes: KMS key matches expected value
[INFO] Getting worker node volumes...
[SUCCESS] Worker nodes: All 3 volumes use the same KMS key
  KMS Key: arn:aws:kms:us-east-2:123456789012:key/9fe48bb2-a03e-4efe-86ec-4796e044cc8b
[SUCCESS] Worker nodes: KMS key matches expected value

==========================================
        OCP-29060 KMS Verification Report
==========================================

📊 Cluster Information:
   InfraID: test-cluster-abc123
   Region: us-east-2

🔐 KMS Encryption Verification:
   ✅ Master nodes: KMS encryption verified
   ✅ Worker nodes: KMS encryption verified

🔑 Default EBS KMS Key:
   arn:aws:kms:us-east-2:123456789012:key/9fe48bb2-a03e-4efe-86ec-4796e044cc8b

🎯 Key Verification Points:
   • Master nodes: Should use custom KMS key (if specified in install-config)
   • Worker nodes: Should use default AWS KMS key for EBS
   • All volumes of the same node type should use the same KMS key
   • Cluster status: All nodes should be in Ready state

[SUCCESS] OCP-29060 KMS encryption verification completed successfully!
✅ All KMS encryption verifications passed!
```

## Manual Verification Commands

If you prefer to run the verification steps manually:

### 1. Extract Cluster Information

```bash
# Extract infraID from metadata.json
cat metadata.json | jq -r '.infraID'
```

### 2. Get Master Node Volumes

```bash
# Get master node volume IDs
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:kubernetes.io/cluster/<infraID>,Values=owned" "Name=tag:Name,Values=*master*" \
  --output json | jq -r '.Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId'
```

### 3. Check Master Volume KMS Keys

```bash
# Check each master volume's KMS key
aws ec2 describe-volumes \
  --region us-east-2 \
  --volume-ids <volume-id> \
  --output json | jq -r '.Volumes[].KmsKeyId'
```

### 4. Get Worker Node Volumes

```bash
# Get worker node volume IDs
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:kubernetes.io/cluster/<infraID>,Values=owned" "Name=tag:Name,Values=*worker*" \
  --output json | jq -r '.Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId'
```

### 5. Check Worker Volume KMS Keys

```bash
# Check each worker volume's KMS key
aws ec2 describe-volumes \
  --region us-east-2 \
  --volume-ids <volume-id> \
  --output json | jq -r '.Volumes[].KmsKeyId'
```

## Troubleshooting

### Common Issues

1. **AWS CLI not configured**
   ```bash
   aws configure
   ```

2. **Missing jq**
   ```bash
   # Install jq
   brew install jq  # macOS
   sudo apt-get install jq  # Ubuntu
   ```

3. **KMS key creation failed**
   - Verify AWS permissions for KMS operations
   - Check if the region supports KMS
   - Ensure the key policy is valid JSON

4. **Volume verification failed**
   - Verify AWS permissions for EC2 operations
   - Check if the cluster has been fully provisioned
   - Ensure the infraID is correct

5. **Cluster connection failed**
   - Verify kubeconfig file path
   - Check cluster accessibility
   - Ensure cluster is in Ready state

### Debug Mode

Use the `--detailed` flag to get more verbose output:

```bash
./verify-kms-encryption.sh -k kubeconfig -m metadata.json -w workdir --detailed
```

## Dependencies

- **AWS CLI**: For KMS and EC2 operations
- **OpenShift CLI (oc)**: For cluster connectivity
- **jq**: For JSON processing

## Test Case Requirements

This script verifies the following requirements from OCP-29060:

1. ✅ **Step 1**: Create KMS symmetric key in AWS region
2. ✅ **Step 5**: Extract infraID from metadata.json
3. ✅ **Step 6**: Verify master volumes are encrypted with custom KMS key
4. ✅ **Step 7**: Verify worker volumes are encrypted with default AWS KMS key

The script does not handle:
- Step 2: Install-config creation (user responsibility)
- Step 3: Install-config modification (user responsibility)
- Step 4: Cluster creation (user responsibility)
- Step 8: Cluster destruction (user responsibility)

## Exit Codes

- `0`: All verifications passed
- `1`: Verification failed or error occurred

## License

This script is part of the OpenShift testing framework and follows the same licensing terms.
