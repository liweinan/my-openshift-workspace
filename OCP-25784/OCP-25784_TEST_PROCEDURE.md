# OCP-25784 - [ipi-on-aws] Create private clusters with no public endpoints and access from internet

## Test Objectives
Validate the creation of private OpenShift clusters on AWS, ensuring clusters have no public endpoints and can only be accessed from instances within the VPC.

## Prerequisites
- AWS CLI configured
- OpenShift installation tools prepared
- Network proxy settings (if required)

## Test Steps

### Step 1: Create VPC and Bastion Host

#### 1.1 Create VPC Stack
```bash
# Create VPC using private cluster VPC template
../tools/create-vpc-stack.sh -s <vpc-stack-name> -t ../tools/vpc-template-private-cluster.yaml \
  --parameter-overrides VpcCidr=10.0.0.0/16 AvailabilityZoneCount=2
```

**Expected Result**: VPC stack created successfully, outputs include:
- VPC ID
- Private subnet ID list
- Public subnet ID list

#### 1.2 Create Bastion Host
```bash
# Set proxy (if required)
export http_proxy=http://squid.corp.redhat.com:3128
export https_proxy=http://squid.corp.redhat.com:3128

# Create bastion host
../tools/create-bastion-host.sh <vpc-id> <public-subnet-id> <bastion-name>
```

**Expected Result**: Bastion host created successfully, obtain:
- Public IP address
- SSH connection information

#### 1.3 Tag Subnets
```bash
# Tag subnets for OpenShift installation
../tools/tag-subnets.sh <vpc-stack-name> <cluster-name> <aws-region>
```

**Expected Result**: Subnets successfully tagged, including:
- `kubernetes.io/cluster/<cluster-name>=shared`
- `kubernetes.io/role/elb=1` (public subnets)
- `kubernetes.io/role/internal-elb=1` (private subnets)

### Step 2: Prepare Installation Tools

#### 2.1 Download OpenShift CLI
```bash
# Download oc tool
./download-oc.sh --version 4.20.0-rc.2
tar -xzf openshift-client-linux-4.20.0-rc.2-x86_64.tar.gz
chmod +x oc kubectl
```

#### 2.2 Transfer Tools and Credentials to Bastion Host
```bash
# Transfer oc tool to bastion host
scp oc core@<bastion-public-ip>:~/

# Transfer OpenShift pull-secret
scp ~/.openshift/pull-secret core@<bastion-public-ip>:~/

# Transfer AWS credentials
scp -r ~/.aws core@<bastion-public-ip>:~/

# Transfer authentication files (if required)
scp <auth-file> core@<bastion-public-ip>:~/
```

#### 2.3 Extract Installation Tools on Bastion Host
```bash
# SSH to bastion host
ssh core@<bastion-public-ip>

# Extract openshift-install tool
./oc adm release extract --tools quay.io/openshift-release-dev/ocp-release:4.20.0-rc.2-x86_64 -a auth.json
tar zxvf openshift-install-linux-4.20.0-rc.2.tar.gz
chmod +x openshift-install
```

### Step 3: Create install-config.yaml

#### 3.1 Generate Base Configuration
```bash
# Run on bastion host
./openshift-install create install-config

# Or manually create install-config.yaml file
cat > install-config.yaml << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
metadata:
  name: <cluster-name>
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
    vpc:
      subnets:
        - id: <private-subnet-1>
        - id: <private-subnet-2>
publish: Internal
pullSecret: '$(cat ~/pull-secret)'
EOF
```

#### 3.2 Configure Private Cluster
Edit `install-config.yaml` to ensure it contains the following key configurations:

```yaml
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
metadata:
  name: <cluster-name>
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
    vpc:
      subnets:
        - id: <private-subnet-1>
        - id: <private-subnet-2>
publish: Internal  # Key: Set to Internal
pullSecret: '{"auths":{"registry.redhat.io":{"auth":"..."}}}'  # Copy from local pull-secret file
```

**Expected Result**: `install-config.yaml` created successfully, `publish` field set to `Internal`

### Step 4: Execute IPI Installation

#### 4.1 Start Cluster Installation
```bash
# Run on bastion host
./openshift-install create cluster
```

**Expected Results**: 
- Installation process proceeds normally
- `WARNING process cluster-api-provider-aws exited with error: signal: killed` appears (normal)
- Finally displays `Install complete!`
- Provides kubeadmin password and console URL

#### 4.2 Verify Installation Results
```bash
# Set kubeconfig
export KUBECONFIG=/var/home/core/auth/kubeconfig

# Check node status
./oc get nodes

# Check cluster operator status
./oc get clusteroperators
```

**Expected Results**:
- All node status is `Ready`
- All cluster operator status is `Available`

### Step 5: Verify Private Cluster Access

#### 5.1 Access Applications Within VPC
```bash
# Test console access from bastion host
curl -v -k console-openshift-console.apps.<cluster-name>.qe.devcluster.openshift.com
```

**Expected Result**: 
- Successfully connect to console URL
- Returns HTTP 302 redirect response

#### 5.2 Verify No Access from Outside VPC
```bash
# Test from machine outside VPC
curl -v -k console-openshift-console.apps.<cluster-name>.qe.devcluster.openshift.com
```

**Expected Result**: 
- Cannot resolve hostname
- Connection fails

### Step 6: Cleanup Resources

#### 6.1 Destroy Cluster
```bash
# Run on bastion host
./openshift-install destroy cluster
```

**Expected Result**: 
- Cluster resources successfully deleted
- Displays `Uninstallation complete!`

#### 6.2 Cleanup VPC and Bastion
```bash
# Delete bastion host stack
aws cloudformation delete-stack --stack-name <bastion-stack-name>

# Delete VPC stack
aws cloudformation delete-stack --stack-name <vpc-stack-name>
```

## Verification Points

### Network Isolation Verification
1. **VPC Internal Access**: Can access OpenShift console from bastion host
2. **VPC External Access**: Cannot access any cluster endpoints from outside VPC
3. **DNS Resolution**: Cluster domain names only resolvable within VPC

### Security Configuration Verification
1. **Private Subnets**: All worker and master nodes deployed in private subnets
2. **Internal Load Balancers**: Use internal load balancers
3. **Route53 Private Zone**: Use private hosted zones

### Functionality Verification
1. **Cluster Health**: All nodes and operators status normal
2. **Application Deployment**: Can deploy and access applications
3. **Network Policy**: Network isolation policies effective

## Troubleshooting

### Common Issues
1. **Credential Issues**: Ensure pull-secret and AWS credentials are correctly transferred to bastion host
2. **Subnet Tagging Issues**: Ensure subnets are correctly tagged with Kubernetes labels
3. **Network Connection Issues**: Check security group and route table configurations
4. **DNS Resolution Issues**: Verify Route53 private zone configuration

### Debug Commands
```bash
# Check credential files
ls -la ~/.aws/
ls -la ~/pull-secret

# Check VPC configuration
aws ec2 describe-vpcs --vpc-ids <vpc-id>

# Check subnet tags
aws ec2 describe-subnets --subnet-ids <subnet-id>

# Check security groups
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<vpc-id>"

# Verify AWS credentials
aws sts get-caller-identity
```

## Test Pass Criteria
- [ ] VPC and bastion host created successfully
- [ ] Subnets correctly tagged
- [ ] Private cluster installation successful
- [ ] All nodes and operators status normal
- [ ] VPC internal cluster access possible
- [ ] VPC external cluster access blocked
- [ ] Cluster resources successfully cleaned up