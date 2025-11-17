# OCP-23541 - [ipi-on-aws] [Hyperthreading] Create cluster with hyperthreading disabled on worker and master nodes

## Test Overview

This test case validates the ability to create an OpenShift cluster on AWS with hyperthreading disabled. The test ensures:

1. Hyperthreading is correctly configured during cluster installation
2. All nodes (master and worker) have hyperthreading disabled
3. MachineConfigPool correctly applies hyperthreading disable configuration
4. Node CPU information shows hyperthreading is disabled

## Test Steps

### Step 1: Create install-config.yaml and disable hyperthreading
Create the installation configuration file with hyperthreading disabled in install-config.yaml:
```yaml
compute:
- hyperthreading: Disabled
  name: worker
  platform:
    aws:
      type: m6i.xlarge
  replicas: 3
controlPlane:
  hyperthreading: Disabled
  name: master
  platform:
    aws:
      type: m6i.xlarge
  replicas: 3
```

### Step 2: Install cluster
Install the cluster using the modified install-config.yaml:
```bash
./openshift-install create cluster --dir test
```

**Expected Result:** Cluster creation successful

### Step 3: Verify hyperthreading disable status
Check hyperthreading status on all nodes:
```bash
# Check node status
oc get nodes

# Verify CPU information for each node
oc debug node/<node-name> -- chroot /host cat /proc/cpuinfo
```

**Expected Results:**
- `siblings` value equals `cpu cores` value
- Example: `siblings: 4` and `cpu cores: 4` indicates hyperthreading is disabled

### Step 4: Verify MachineConfigPool
Check MachineConfigPool status and configuration:
```bash
oc get machineconfigpools
oc describe machineconfigpools
```

**Expected Results:**
- MachineConfigPool status is Updated
- Configuration includes `99-master-disable-hyperthreading` and `99-worker-disable-hyperthreading`

## Automation Scripts

### setup-ocp-23541-test.sh

This script automates the complete test flow:

#### Features
- Generates install-config.yaml with hyperthreading disable configuration
- Automatically installs OpenShift cluster
- Verifies hyperthreading disable status on all nodes
- Checks MachineConfigPool configuration
- Provides detailed test result report

#### Usage
```bash
# Basic usage (with default parameters)
./setup-ocp-23541-test.sh

# Custom parameters
./setup-ocp-23541-test.sh \
  --region us-west-2 \
  --cluster-name my-hyperthreading-test \
  --instance-type m5.2xlarge \
  --worker-count 3 \
  --master-count 3

# Generate config only (skip installation)
./setup-ocp-23541-test.sh --skip-install
```

#### Parameters
- `-r, --region`: AWS region (default: us-east-2)
- `-n, --cluster-name`: Cluster name (default: hyperthreading-test)
- `-i, --instance-type`: Instance type (default: m6i.xlarge)
- `-w, --worker-count`: Worker node count (default: 3)
- `-m, --master-count`: Master node count (default: 3)
- `-d, --dir`: Installation directory (default: test)
- `--skip-install`: Skip cluster installation, generate config only
- `-h, --help`: Show help information

### verify-hyperthreading.sh

This script verifies hyperthreading disable status on existing clusters:

#### Features
- Verifies hyperthreading status on all nodes or specified nodes
- Checks MachineConfigPool configuration
- Provides detailed CPU information analysis
- Generates verification report

#### Usage
```bash
# Verify all nodes
./verify-hyperthreading.sh --kubeconfig /path/to/kubeconfig

# Verify specific node
./verify-hyperthreading.sh --kubeconfig /path/to/kubeconfig --node ip-10-0-130-76.us-east-2.compute.internal

# Show detailed CPU information
./verify-hyperthreading.sh --kubeconfig /path/to/kubeconfig --detailed
```

#### Parameters
- `-k, --kubeconfig <path>`: Kubeconfig file path (required)
- `-n, --node <node-name>`: Verify single node (optional)
- `-d, --detailed`: Show detailed CPU information (optional)
- `-h, --help`: Show help information

## Manual Execution Steps

### 1. Prepare environment
```bash
# Ensure required tools are installed
aws --version
openshift-install version
oc version

# Set AWS credentials
aws configure

# Prepare pull-secret.json file
cp pull-secret.json OCP-23541/
```

### 2. Run automation script
```bash
cd OCP-23541
./setup-ocp-23541-test.sh --region us-east-2
```

### 3. Manual verification (optional)
```bash
# Set kubeconfig
export KUBECONFIG=test/auth/kubeconfig

# Check node status
oc get nodes

# Verify hyperthreading status
./verify-hyperthreading.sh --kubeconfig test/auth/kubeconfig --detailed
```

### 4. Cleanup resources
```bash
# Destroy cluster
openshift-install destroy cluster --dir test
```

## Verification Points

### Hyperthreading Disable Verification
Execute the following command on nodes to verify hyperthreading status:
```bash
oc debug node/<node-name> -- chroot /host cat /proc/cpuinfo | grep -E "(siblings|cpu cores)"
```

**Correct Result Example:**
```
siblings    : 4
cpu cores   : 4
```
- `siblings` = `cpu cores` indicates hyperthreading is disabled

**Incorrect Result Example:**
```
siblings    : 8
cpu cores   : 4
```
- `siblings` > `cpu cores` indicates hyperthreading is not disabled

### MachineConfigPool Verification
```bash
oc get machineconfigpools -o wide
oc describe machineconfigpools master
oc describe machineconfigpools worker
```

**Expected Results:**
- Status is `Updated`
- Configuration names contain hyperthreading disable configuration
- All nodes are updated

### CPU Information Analysis
```bash
# Get detailed CPU information
oc debug node/<node-name> -- chroot /host cat /proc/cpuinfo

# Analyze logical and physical CPUs
oc debug node/<node-name> -- chroot /host nproc
oc debug node/<node-name> -- chroot /host lscpu
```

## Troubleshooting

### Common Issues

1. **Hyperthreading not disabled**
   - Check hyperthreading configuration in install-config.yaml
   - Verify MachineConfigPool status
   - Confirm nodes have fully restarted

2. **Cluster installation failed**
   - Check AWS permissions and quotas
   - Verify instance type support
   - Review openshift-install logs

3. **Verification script failed**
   - Confirm kubeconfig file is valid
   - Check node readiness status
   - Verify debug pod permissions

4. **MachineConfigPool not updated**
   - Wait for configuration application to complete
   - Check node status
   - Review MachineConfigOperator logs

### Debug Commands
```bash
# Check cluster status
oc get nodes -o wide
oc get machineconfigpools
oc get machineconfigs

# View configuration details
oc describe machineconfigpool master
oc describe machineconfigpool worker

# Check node events
oc describe node <node-name>

# View MachineConfigOperator logs
oc logs -n openshift-machine-config-operator deployment/machine-config-operator
```

## Requirements

### Required Tools
- `aws` CLI - AWS command line tool
- `openshift-install` - OpenShift installation tool
- `oc` - OpenShift client tool
- `jq` - JSON processing tool

### AWS Permissions
- EC2 permissions (instance management)
- IAM permissions (role and policy management)
- VPC permissions (network management)
- Route53 permissions (DNS management)

### File Requirements
- `pull-secret.json` - Red Hat pull secret
- SSH public key (~/.ssh/id_rsa.pub)

## Related Documentation

- [OpenShift IPI Installation Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-installer.html)
- [OpenShift Machine Config Operator Documentation](https://docs.openshift.com/container-platform/latest/post_installation_configuration/machine-configuration-tasks.html)
- [AWS EC2 Instance Type Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html)
- [OCP-23541 JIRA](https://issues.redhat.com/browse/OCP-23541)

## Notes

1. **Instance Type Selection**: After disabling hyperthreading, it's recommended to use larger instance types to ensure sufficient CPU performance
2. **Installation Time**: Disabling hyperthreading may require additional configuration time, please be patient
3. **Performance Impact**: Disabling hyperthreading may affect performance of certain workloads
4. **Cost Consideration**: Using larger instance types will increase AWS costs

## Test Result Examples

### Successful Verification Output
```
[INFO] Verifying node: ip-10-0-130-76.us-east-2.compute.internal
[INFO] Node role: worker
[INFO] CPU information analysis:
  - Logical CPU count: 4
  - Physical CPU count: 1
  - Siblings per physical CPU: 4
  - Cores per physical CPU: 4
[SUCCESS] ✅ Hyperthreading is disabled (siblings == cpu_cores)
```

### MachineConfigPool Status
```
NAME     CONFIG                                   UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
master   rendered-master-abc123                    True      False      False      3              3                   3                     0                      15m
worker   rendered-worker-def456                    True      False      False      3              3                   3                     0                      15m
```