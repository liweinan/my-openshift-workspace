# OCP-25698 - [ipi-on-aws] create multiple clusters using the same subnets from an existing VPC

## Test Overview

This test case verifies the ability to create multiple OpenShift clusters on AWS using the same subnets from an existing VPC. The test ensures:

1. Multiple clusters can share the same VPC subnets
2. Subnet labels are properly cleaned up after cluster destruction
3. Subnets can be reused between different clusters
4. Machine API scaling functionality works properly

## Test Steps

### Step 1: Create VPC and Subnets
Create a VPC and obtain its subnets (including private and public subnets)

### Step 2: Create install-config.yaml
Create the installation configuration file, specifying the subnets obtained from Step 1 in install-config.yaml:
```yaml
platform:
  aws:
    region: us-east-2
    subnets:
    - subnet-0fff91886b6abc830
    - subnet-0eb40a0b8ef183641
    - subnet-0a9699835fa8193fd
    - subnet-0d8cb2cfaeff3128e
```

### Step 3: Install Cluster A
Use the install-config.yaml to trigger IPI installation on AWS to get Cluster A

### Step 4: Cluster A Health Check
After installation completes, perform health checks on Cluster A

### Step 5: Install Cluster B
Use the same install-config.yaml but with a different cluster name to trigger IPI installation on AWS to get Cluster B

### Step 6: Cluster B Health Check
After installation completes, perform health checks on Cluster B

### Step 7: Cluster A Scaling
Successfully scale a new worker node for Cluster A through Machine API

### Step 8: Cluster B Scaling
Successfully scale a new worker node for Cluster B through Machine API

### Step 9: Destroy Cluster A
Destroy Cluster A, ensuring the entire Cluster A (including scaled worker nodes) is removed

**Expected Result:**
```
DEBUG search for untaggable resources              
DEBUG Search for and remove tags in us-east-2 matching kubernetes.io/cluster/jialiu43-bz-gckbt: shared
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-gckbt: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-0d452b3ad90f1ce64"
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-gckbt: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-01e1cd2de0d7882bc"
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-gckbt: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-0f59af3f18571734c"
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-gckbt: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-023cac778b5464173"
```

### Step 10: Cluster B Scaling Again
Successfully scale a new worker node for Cluster B through Machine API

### Step 11: Cluster B Health Check
After installation completes, perform health checks on Cluster B

### Step 12: Destroy Cluster B
Destroy Cluster B, ensuring the entire Cluster B (including scaled worker nodes) is removed

**Expected Result:**
```
DEBUG search for untaggable resources              
DEBUG Search for and remove tags in us-east-2 matching kubernetes.io/cluster/jialiu43-bz-priv-z6hld : shared
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-priv-z6hld: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-0d452b3ad90f1ce64"
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-priv-z6hld: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-01e1cd2de0d7882bc"
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-priv-z6hld: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-0f59af3f18571734c"
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-priv-z6hld: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-023cac778b5464173"
```

### Step 13: Verify Subnet Status
Ensure the subnets created in Step 1 still exist and have no `kubernetes.io/cluster/${INFRA_ID}: shared` labels

### Step 14: Clean up VPC
Manually delete the VPC to ensure no dependent resources remain

## Automation Scripts

### setup-ocp-25698-test.sh

This script automates the test preparation:

#### Features
- Creates VPC and subnets (public + private)
- Generates install-config.yaml templates for two clusters
- Adds shared labels to subnets
- Provides complete test step instructions

### scale-cluster.sh

This script is used to scale existing OpenShift cluster worker nodes:

#### Features
- Supports specifying kubeconfig path
- Auto-discovers or manually specifies MachineSet
- Supports waiting for scaling to complete
- Provides dry-run mode
- Shows real-time scaling progress and status

#### Usage
```bash
# Basic usage - scale to 4 replicas
./scale-cluster.sh --kubeconfig /path/to/kubeconfig

# Scale to 6 replicas
./scale-cluster.sh --kubeconfig /path/to/kubeconfig --replicas 6

# Specify MachineSet name
./scale-cluster.sh --kubeconfig /path/to/kubeconfig --machineset my-cluster-abc123-worker-us-east-2a

# Wait for scaling to complete
./scale-cluster.sh --kubeconfig /path/to/kubeconfig --wait

# Dry-run mode
./scale-cluster.sh --kubeconfig /path/to/kubeconfig --dry-run
```

#### Parameters
- `-k, --kubeconfig <path>`: Kubeconfig file path (required)
- `-r, --replicas <number>`: Target replica count (default: 4)
- `-n, --namespace <name>`: MachineSet namespace (default: openshift-machine-api)
- `-m, --machineset <name>`: Specify MachineSet name (optional)
- `-w, --wait`: Wait for scaling to complete
- `-t, --timeout <seconds>`: Wait timeout (default: 600 seconds)
- `-d, --dry-run`: Only show operations to be performed, do not execute
- `-h, --help`: Show help information

#### Usage
```bash
# Basic usage (using default parameters)
./setup-ocp-25698-test.sh

# Custom parameters
./setup-ocp-25698-test.sh \
  --region us-east-2 \
  --stack-name my-shared-vpc \
  --vpc-cidr 10.0.0.0/16 \
  --az-count 2

# Use existing VPC (skip VPC creation)
./setup-ocp-25698-test.sh \
  --region us-east-2 \
  --stack-name existing-vpc-stack \
  --skip-vpc
```

#### Parameters
- `-r, --region`: AWS region (default: us-east-2)
- `-s, --stack-name`: VPC stack name (default: ocp-25698-shared-vpc)
- `-c, --vpc-cidr`: VPC CIDR (default: 10.0.0.0/16)
- `-a, --az-count`: Number of availability zones (default: 2)
- `--skip-vpc`: Skip VPC creation, use existing VPC
- `-h, --help`: Show help information

## Manual Execution Steps

### 1. Prepare Environment
```bash
# Ensure required tools are installed
aws --version
openshift-install version
oc version

# Set AWS credentials
aws configure
```

### 2. Run Setup Script
```bash
cd OCP-25698
./setup-ocp-25698-test.sh --region us-east-2
```

### 3. Update Configuration Files
Edit the generated install-config files, add your pull-secret and SSH keys:
```bash
# Edit cluster A configuration
vim install-config-cluster-a.yaml

# Edit cluster B configuration
vim install-config-cluster-b.yaml
```

### 4. Install Cluster A
```bash
mkdir cluster-a
cp install-config-cluster-a.yaml cluster-a/install-config.yaml
openshift-install create cluster --dir cluster-a
```

### 5. Cluster A Health Check
```bash
export KUBECONFIG=cluster-a/auth/kubeconfig
oc get nodes
oc get clusteroperators
oc get machinesets
```

### 6. Install Cluster B
```bash
mkdir cluster-b
cp install-config-cluster-b.yaml cluster-b/install-config.yaml
openshift-install create cluster --dir cluster-b
```

### 7. Cluster B Health Check
```bash
export KUBECONFIG=cluster-b/auth/kubeconfig
oc get nodes
oc get clusteroperators
oc get machinesets
```

### 8. Scaling Tests

#### Using Automation Scripts (Recommended)
```bash
# Cluster A scaling
./scale-cluster.sh --kubeconfig cluster-a/auth/kubeconfig --replicas 4 --wait

# Cluster B scaling
./scale-cluster.sh --kubeconfig cluster-b/auth/kubeconfig --replicas 4 --wait
```

#### Manual Scaling (Alternative)

##### Get MachineSet Names
```bash
# View all MachineSets
oc get machinesets -n openshift-machine-api

# View MachineSet details
oc describe machineset <machineset-name> -n openshift-machine-api
```

##### Execute Scaling
```bash
# Cluster A scaling
export KUBECONFIG=cluster-a/auth/kubeconfig
oc get machinesets -n openshift-machine-api
oc scale machineset <machineset-name> -n openshift-machine-api --replicas=4

# Cluster B scaling
export KUBECONFIG=cluster-b/auth/kubeconfig
oc get machinesets -n openshift-machine-api
oc scale machineset <machineset-name> -n openshift-machine-api --replicas=4
```

##### Verify Scaling Results
```bash
# View MachineSet status
oc get machinesets -n openshift-machine-api

# View Machine status
oc get machines -n openshift-machine-api

# View node status
oc get nodes

# Wait for new nodes to be ready
oc get nodes -w
```

### 9. Destroy Cluster A
```bash
openshift-install destroy cluster --dir cluster-a
```

### 10. Cluster B Scaling Again
```bash
# Using automation script (recommended)
./scale-cluster.sh --kubeconfig cluster-b/auth/kubeconfig --replicas 4 --wait

# Or execute manually
export KUBECONFIG=cluster-b/auth/kubeconfig
oc get machinesets -n openshift-machine-api
oc scale machineset <machineset-name> -n openshift-machine-api --replicas=4

# Verify scaling results
oc get nodes
oc get machines -n openshift-machine-api
```

### 11. Destroy Cluster B
```bash
openshift-install destroy cluster --dir cluster-b
```

### 12. Verify Subnet Cleanup
```bash
# Check subnet labels
aws ec2 describe-subnets --subnet-ids <subnet-id> --query 'Subnets[0].Tags'

# Should have no kubernetes.io/cluster/ labels
```

### 13. Clean up VPC
```bash
aws cloudformation delete-stack --stack-name ocp-25698-shared-vpc
```

## Verification Points

### Subnet Label Verification
During cluster destruction, you should see the following logs:
```
DEBUG search for untaggable resources              
DEBUG Search for and remove tags in us-east-2 matching kubernetes.io/cluster/<INFRA_ID>: shared
INFO Removed tag kubernetes.io/cluster/<INFRA_ID>: shared  arn="arn:aws:ec2:us-east-2:<ACCOUNT>:subnet/<SUBNET-ID>"
```

### Subnet Reuse Verification
- Clusters A and B should be able to use the same subnets
- After Cluster A is destroyed, Cluster B should still work normally
- Subnet labels should be cleaned up correctly to allow subsequent reuse

### Machine API Verification
- Scaling operations should succeed
- New nodes should correctly join the cluster
- Nodes should receive correct network configuration

### MachineSet Name Format
MachineSet names typically follow this format:
- `weli-clus-a-<random-string>-worker-<az>` (Cluster A)
- `weli-clus-b-<random-string>-worker-<az>` (Cluster B)

For example:
- `weli-clus-a-abc123-worker-us-east-2a`
- `weli-clus-a-abc123-worker-us-east-2b`
- `weli-clus-b-def456-worker-us-east-2a`
- `weli-clus-b-def456-worker-us-east-2b`

### Complete Scaling Process Example

#### Using Automation Scripts (Recommended)
```bash
# 1. Cluster A scaling
./scale-cluster.sh --kubeconfig /path/to/cluster-a/auth/kubeconfig --replicas 4 --wait

# 2. Cluster B scaling
./scale-cluster.sh --kubeconfig /path/to/cluster-b/auth/kubeconfig --replicas 4 --wait

# 3. Cluster B scaling again (testing subnet reuse)
./scale-cluster.sh --kubeconfig /path/to/cluster-b/auth/kubeconfig --replicas 6 --wait
```

#### Manual Scaling Process
```bash
# 1. Switch to Cluster A
export KUBECONFIG=/path/to/cluster-a/auth/kubeconfig

# 2. View MachineSets
oc get machinesets -n openshift-machine-api

# 3. Scale (assuming MachineSet name is weli-clus-a-abc123-worker-us-east-2a)
oc scale machineset weli-clus-a-abc123-worker-us-east-2a -n openshift-machine-api --replicas=4

# 4. Wait for new nodes to be ready
oc get nodes -w

# 5. Switch to Cluster B
export KUBECONFIG=/path/to/cluster-b/auth/kubeconfig

# 6. Perform same operations for Cluster B
oc get machinesets -n openshift-machine-api
oc scale machineset <machineset-name> -n openshift-machine-api --replicas=4
```

## Troubleshooting

### Common Issues

1. **Subnet Label Conflicts**
   - Ensure subnets are correctly labeled using the `tag-subnets.sh` script
   - Check that label values are `shared`

2. **Cluster Installation Failed**
   - Verify subnet IDs are correct
   - Check VPC and subnet configuration
   - Confirm AWS permissions are sufficient

3. **Scaling Failed**
   - Check MachineSet configuration
   - Verify subnet capacity
   - View Machine API logs

4. **Label Residue After Destruction**
   - Check openshift-install logs
   - Manually clean up residual labels
   - Verify subnet status

### Debug Commands
```bash
# Check subnet labels
aws ec2 describe-subnets --subnet-ids <subnet-id> --query 'Subnets[0].Tags'

# Check VPC status
aws ec2 describe-vpcs --vpc-ids <vpc-id>

# Check cluster status
oc get nodes -o wide
oc get machinesets -n openshift-machine-api
oc get machines -n openshift-machine-api

# Check MachineSet details
oc describe machineset <machineset-name> -n openshift-machine-api

# Check Machine status
oc describe machine <machine-name> -n openshift-machine-api

# Check node labels and taints
oc get nodes --show-labels
oc describe node <node-name>
```

## Requirements

### Required Tools
- `aws` CLI - AWS command line tool
- `openshift-install` - OpenShift installation tool
- `oc` - OpenShift client tool
- `jq` - JSON processing tool

### AWS Permissions
- EC2 permissions (VPC, subnet, instance management)
- CloudFormation permissions (stack management)
- IAM permissions (role and policy management)

### Network Requirements
- Subnets must support multiple availability zones
- Subnet CIDRs must not overlap
- Must include both public and private subnets

## Related Documentation

- [OpenShift IPI Installation Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-installer.html)
- [AWS VPC and Subnet Documentation](https://docs.aws.amazon.com/vpc/)
- [OpenShift Machine API Documentation](https://docs.openshift.com/container-platform/latest/machine_management/)
- [OCP-25698 JIRA](https://issues.redhat.com/browse/OCP-25698)