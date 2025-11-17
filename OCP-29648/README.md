# OCP-29648: Custom AMI Verification

This directory contains scripts and documentation for the **OCP-29648** test case: `[ipi-on-aws] Create cluster with custom AMI`.

## Test Case Overview

**OCP-29648** verifies that OpenShift clusters can be created using custom AMIs for both master and worker nodes, and that the cluster correctly uses the specified AMIs.

### Test Steps

1. **Install cluster** with custom AMIs specified in `install-config.yaml`
2. **Record infraID and openshiftClusterID** from `metadata.json`
3. **Verify AMI usage** by checking actual EC2 instances
4. **Destroy cluster** successfully

## Files

- `verify-custom-ami.sh` - Main verification script
- `README.md` - This documentation file

## Prerequisites

- AWS CLI configured with appropriate permissions
- `oc` (OpenShift CLI) installed
- `jq` and `yq` command-line tools installed
- Access to the OpenShift cluster via kubeconfig
- `metadata.json` file from the installation
- Installer working directory with `install-config.yaml`

## Usage

### Basic Usage

```bash
./verify-custom-ami.sh -k <kubeconfig> -m <metadata.json> -w <work-dir>
```

### With Expected AMI IDs

```bash
./verify-custom-ami.sh \
  -k /path/to/kubeconfig \
  -m /path/to/metadata.json \
  -w /path/to/workdir \
  --worker-ami ami-03c1d60abaef1ca7e \
  --master-ami ami-02e68e65b656320fa
```

### With Detailed Output

```bash
./verify-custom-ami.sh \
  -k kubeconfig \
  -m metadata.json \
  -w workdir \
  --detailed
```

## Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `-k, --kubeconfig` | Path to kubeconfig file | Yes | - |
| `-m, --metadata` | Path to metadata.json file | Yes | - |
| `-w, --work-dir` | Path to installer working directory | Yes | - |
| `-r, --region` | AWS region | No | us-east-2 |
| `--worker-ami` | Expected worker AMI ID | No | Auto-detected |
| `--master-ami` | Expected master AMI ID | No | Auto-detected |
| `--detailed` | Show detailed verification information | No | false |

## Verification Process

The script performs the following verifications:

### 1. Cluster Information Extraction
- Extracts `infraID`, `clusterID`, and `clusterName` from `metadata.json`
- Validates cluster connection using kubeconfig

### 2. Expected AMI Detection
- Automatically extracts expected AMI IDs from `install-config.yaml`
- Falls back to manually provided AMI IDs if available

### 3. Actual AMI Verification
- Queries AWS EC2 instances using cluster tags
- Retrieves actual AMI IDs for worker and master nodes
- Verifies AMI consistency across all nodes of the same type

### 4. AMI Comparison
- Compares actual AMI IDs with expected AMI IDs
- Validates that all worker nodes use the same AMI
- Validates that all master nodes use the same AMI

## Example Output

```
[INFO] Using Kubeconfig: /path/to/kubeconfig
[INFO] Using Metadata: /path/to/metadata.json
[INFO] Using Work Directory: /path/to/workdir
[INFO] Using AWS Region: us-east-2
[INFO] Extracting cluster information from metadata.json...
[SUCCESS] Extracted cluster information:
  - InfraID: test-cluster-abc123
  - ClusterID: d64b26be-5d5e-4bb2-a723-9c1e527d46bf
  - ClusterName: test-cluster
[INFO] Extracting expected AMI IDs from install-config.yaml...
[INFO] Expected Worker AMI from install-config: ami-03c1d60abaef1ca7e
[INFO] Expected Master AMI from install-config: ami-02e68e65b656320fa
[INFO] Checking cluster connection...
[SUCCESS] Cluster connection successful
[INFO] Cluster ID: d64b26be-5d5e-4bb2-a723-9c1e527d46bf
[INFO] Getting cluster node information...
[INFO] Cluster node status:
  - Total nodes: 6
  - Ready nodes: 6
[INFO] Querying actual AMI IDs from AWS EC2 instances...
[INFO] Getting worker node AMI IDs...
[INFO] Getting master node AMI IDs...
[INFO] Actual AMI IDs:
  - Worker AMI: ami-03c1d60abaef1ca7e
  - Master AMI: ami-02e68e65b656320fa
[INFO] Verifying AMI consistency...
[SUCCESS] AMI consistency verified:
  - All worker nodes use the same AMI
  - All master nodes use the same AMI
[INFO] Verifying expected AMI IDs...
[SUCCESS] Worker AMI matches expected: ami-03c1d60abaef1ca7e
[SUCCESS] Master AMI matches expected: ami-02e68e65b656320fa

==========================================
        OCP-29648 Verification Report
==========================================

📊 Cluster Information:
   InfraID: test-cluster-abc123
   Region: us-east-2

🔍 AMI Verification:
   Worker AMI: ami-03c1d60abaef1ca7e
   Master AMI: ami-02e68e65b656320fa

⚙️  Expected AMI Comparison:
   ✅ Worker AMI matches expected: ami-03c1d60abaef1ca7e
   ✅ Master AMI matches expected: ami-02e68e65b656320fa

🎯 Key Verification Points:
   • AMI consistency: All worker nodes use the same AMI
   • AMI consistency: All master nodes use the same AMI
   • AMI validation: Actual AMIs match expected AMIs from install-config
   • Cluster status: All nodes are in Ready state

[SUCCESS] OCP-29648 verification completed successfully!
✅ All AMI verifications passed!
```

## Manual Verification Commands

If you prefer to run the verification steps manually:

### 1. Extract Cluster Information

```bash
# Extract infraID from metadata.json
cat metadata.json | jq -r '.infraID'

# Extract clusterID from metadata.json
cat metadata.json | jq -r '.clusterID'
```

### 2. Verify Worker AMI

```bash
# Get worker node AMI IDs
aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/<infraID>,Values=owned" "Name=tag:Name,Values=*worker*" \
  --output json | jq '.Reservations[].Instances[].ImageId' | sort | uniq
```

### 3. Verify Master AMI

```bash
# Get master node AMI IDs
aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/<infraID>,Values=owned" "Name=tag:Name,Values=*master*" \
  --output json | jq '.Reservations[].Instances[].ImageId' | sort | uniq
```

### 4. Check Cluster Status

```bash
# Check node status
oc get nodes

# Check cluster version
oc get clusterversion
```

## Troubleshooting

### Common Issues

1. **AWS CLI not configured**
   ```bash
   aws configure
   ```

2. **Missing jq or yq**
   ```bash
   # Install jq
   brew install jq  # macOS
   sudo apt-get install jq  # Ubuntu
   
   # Install yq
   brew install yq  # macOS
   sudo apt-get install yq  # Ubuntu
   ```

3. **Cluster connection failed**
   - Verify kubeconfig file path
   - Check cluster accessibility
   - Ensure cluster is in Ready state

4. **AMI verification failed**
   - Verify AWS region is correct
   - Check AWS permissions for EC2 describe-instances
   - Ensure cluster has been fully provisioned

### Debug Mode

Use the `--detailed` flag to get more verbose output:

```bash
./verify-custom-ami.sh -k kubeconfig -m metadata.json -w workdir --detailed
```

## Dependencies

- **AWS CLI**: For querying EC2 instances
- **OpenShift CLI (oc)**: For cluster connectivity
- **jq**: For JSON processing
- **yq**: For YAML processing (install-config.yaml)

## Test Case Requirements

This script verifies the following requirements from OCP-29648:

1. ✅ **Step 2**: Record infraID and openshiftClusterID from metadata.json
2. ✅ **Step 3**: Confirm master and worker are using the same image and RHCOS version
3. ✅ **Expected Result**: Master and worker AMI should be the same as specified in install-config

The script does not handle:
- Step 1: Cluster installation (user responsibility)
- Step 4: Cluster destruction (user responsibility)

## Exit Codes

- `0`: All verifications passed
- `1`: Verification failed or error occurred

## License

This script is part of the OpenShift testing framework and follows the same licensing terms.