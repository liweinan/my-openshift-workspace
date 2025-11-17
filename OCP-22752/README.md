# OCP-22752: Create assets step by step then create cluster

## Test Case Description
**OCP-22752**: `[ipi-on-aws] Create assets step by step then create cluster without customization`

This test case verifies that the OpenShift installer can create various assets step by step (install-config, manifests, ignition configs), then successfully create a cluster, while ensuring SSH keys are correctly distributed in the ignition configuration files.

## Test Objectives
- Verify the step-by-step creation of OpenShift assets functionality
- Ensure correct SSH key distribution in ignition configuration files
- Verify asset matching messages during cluster creation
- Test cluster creation without customization

## Prerequisites
- Linux environment
- AWS credentials configured
- `openshift-install` tool installed
- SSH key pair configured
- pull-secret file prepared

## Test Steps

### Step 1: Generate Public Key
```bash
# Generate public key from private key
ssh-keygen -y -f libra.pem > ~/.ssh/id_rsa.pub
```

### Step 2: Create install-config
```bash
# Navigate to installer directory
cd <dir where installer is downloaded>

# Create install-config
./openshift-install create install-config --dir test
```

### Step 3: Create manifests
```bash
# Create manifests
./openshift-install create manifests --dir test
```

### Step 4: Create ignition configs
```bash
# Create ignition configs
./openshift-install create ignition-configs --dir test
```

**Expected Result**: bootstrap.ign/worker.ign/master.ign ignition configuration files created successfully, no warning logs.

### Step 5: Verify SSH Key Distribution
```bash
# Check master.ign - should not contain SSH keys
cat test/master.ign | jq '.passwd'
# Expected Result: {}

# Check worker.ign - should not contain SSH keys
cat test/worker.ign | jq '.passwd'
# Expected Result: {}

# Check bootstrap.ign - should contain SSH keys
cat test/bootstrap.ign | jq '.passwd'
# Expected Result: Contains SSH keys for core user
```

### Step 6: Create Cluster
```bash
# Create cluster
./openshift-install create cluster --dir test
```

**Expected Result**: Cluster created successfully, installation log contains "On-disk <asset.name> matches asset in state file" messages.

## Automation Scripts

### 1. test-step-by-step-assets.sh
Complete automated test script that executes all test steps:

```bash
# Basic usage
./test-step-by-step-assets.sh \
  -k ~/.ssh/id_rsa \
  -i ./openshift-install \
  -p pull-secret.json

# Custom parameters
./test-step-by-step-assets.sh \
  -k libra.pem \
  -i ./openshift-install \
  -p pull-secret.json \
  -n my-test-cluster \
  -r us-west-2 \
  -v
```

**Parameter Description**:
- `-k, --ssh-key`: SSH private key path (required)
- `-i, --installer`: openshift-install binary path (required)
- `-p, --pull-secret`: pull-secret file path (required)
- `-n, --name`: Cluster name (default: step-by-step-test)
- `-r, --region`: AWS region (default: us-east-2)
- `-w, --work-dir`: Working directory (default: test-step-by-step)
- `-v, --verbose`: Verbose output
- `--no-cleanup`: Do not clean up test environment

### 2. verify-ignition-ssh-keys.sh
Script specifically for verifying SSH key distribution in ignition configuration files:

```bash
# Verify ignition files in current directory
./verify-ignition-ssh-keys.sh

# Verify ignition files in specified directory
./verify-ignition-ssh-keys.sh -w /path/to/ignition/files

# Detailed output
./verify-ignition-ssh-keys.sh -v
```

## Verification Criteria

### Success Criteria
1. **Asset Creation Success**: All steps execute successfully
2. **SSH Key Distribution Correct**:
   - bootstrap.ign contains SSH keys for core user
   - master.ign does not contain SSH keys
   - worker.ign does not contain SSH keys
3. **No Warning Logs**: No warnings during ignition config creation
4. **Asset Matching Messages**: Cluster creation log contains asset matching messages
5. **Cluster Creation Success**: Cluster can be created and accessed successfully

### Verification Commands
```bash
# Check ignition files exist
ls -la *.ign

# Verify SSH key distribution
./verify-ignition-ssh-keys.sh

# Check cluster status
KUBECONFIG=auth/kubeconfig oc get nodes
```

## Troubleshooting

### Common Issues

#### 1. SSH Key Generation Failed
```bash
# Check private key file
ls -la libra.pem

# Check private key permissions
chmod 600 libra.pem

# Regenerate public key
ssh-keygen -y -f libra.pem > ~/.ssh/id_rsa.pub
```

#### 2. Ignition Config Creation Failed
```bash
# Check install-config.yaml
cat install-config.yaml

# Check manifests directory
ls -la manifests/

# Recreate ignition configs
./openshift-install create ignition-configs --dir .
```

#### 3. SSH Key Distribution Incorrect
```bash
# Manual verification
cat bootstrap.ign | jq '.passwd.users[] | select(.name == "core") | .sshAuthorizedKeys'
cat master.ign | jq '.passwd'
cat worker.ign | jq '.passwd'
```

#### 4. Cluster Creation Failed
```bash
# Check installation log
tail -f .openshift_install.log

# Check AWS resources
aws ec2 describe-instances --filters "Name=tag:Name,Values=<cluster-name>-*"
```

## Cleanup Steps
```bash
# Destroy cluster
./openshift-install destroy cluster --dir test

# Clean up working directory
rm -rf test
```

## Related Test Cases
- **OCP-22317**: Merged ignition config creation test
- **OCP-21585**: Merged cluster creation test
- **OCP-22316**: Merged asset matching verification test
- **CORS-959**: SSH key distribution validation

## Notes
1. **SSH Key Distribution**: Ensure SSH keys are only in bootstrap.ign, not in master.ign or worker.ign
2. **Asset Matching**: Asset matching messages should be visible during cluster creation
3. **No Warning Logs**: Ignition config creation should have no warnings
4. **Step-by-Step Execution**: Execute strictly in order, do not skip any steps
5. **Environment Cleanup**: Clean up AWS resources promptly after testing

## Practical Application Value
This test verifies functionality important for:
- Understanding OpenShift installation process step-by-step execution
- Verifying ignition configuration correctness
- Ensuring SSH key security distribution
- Testing installer asset management functionality

Very important for production environment deployment and troubleshooting.