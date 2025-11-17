# OCP-23394: Collect Logs from Bootstrap Failed Cluster

## Test Case Description
**OCP-23394**: `[ipi-on-aws] collect logs from a cluster that failed to bootstrap running installer on linux`

This test case verifies the ability to correctly collect debugging logs and troubleshooting information when OpenShift cluster installation bootstrap fails.

## Test Objectives
- Verify ability to collect bootstrap node logs when installation fails
- Ensure log collection tools work properly under abnormal conditions
- Verify collected logs contain necessary debugging information

## Prerequisites
- Linux environment
- AWS credentials configured
- `openshift-install` tool installed
- SSH key configured

## Detailed Test Steps

### Step 1: Set up SSH Agent
```bash
# Start SSH Agent
eval `ssh-agent -s`

# Add SSH key
ssh-add ~/.ssh/id_rsa
# Or add your SSH key file
ssh-add /path/to/your/ssh-key
```

**Verify SSH Agent Setup**:
```bash
# Check SSH Agent status
ssh-add -l
```

### Step 2: Start Cluster Installation
```bash
# Create working directory
mkdir -p test-bootstrap-failure
cd test-bootstrap-failure

# Generate install-config.yaml
openshift-install create install-config --dir .

# Start cluster installation
openshift-install create cluster --dir .
```

**Important**: Keep terminal window open and monitor installation output.

### Step 3: Monitor Installation Process and Choose Interruption Timing

#### Method A: Monitor Log Messages and Interrupt
During installation, monitor for the following key message:

```bash
# When you see the following message, immediately press Ctrl+C to interrupt:
"added bootstrap-success: Required control plane pods have been created"
```

#### Method B: Staged Interruption
```bash
# In another terminal window, wait for bootstrap to complete
openshift-install wait-for bootstrap-complete --dir .

# Then interrupt during install-complete phase
openshift-install wait-for install-complete --dir .
# Press Ctrl+C to interrupt installation process
```

### Step 4: Collect Bootstrap Logs

#### Method 1: Use Directory Parameter
```bash
# Use working directory to collect logs
openshift-install gather bootstrap --dir .
```

#### Method 2: Use Specific IP Addresses
```bash
# Get the following information from AWS console:
# - Bootstrap node public IP
# - Master node private IP addresses

# Use specific IP addresses to collect logs
openshift-install gather bootstrap \
  --bootstrap <BOOTSTRAP_PUBLIC_IP> \
  --master "<MASTER1_IP> <MASTER2_IP> <MASTER3_IP>"
```

**Example**:
```bash
openshift-install gather bootstrap \
  --bootstrap 54.238.178.100 \
  --master "10.0.134.134 10.0.148.230 10.0.166.246"
```

### Step 5: Execute Log Collection Commands
Follow the output from Step 4 to execute the corresponding SSH commands:

```bash
# Execute log collection script
ssh -A core@<BOOTSTRAP_IP> '/usr/local/bin/installer-gather.sh <MASTER1_IP> <MASTER2_IP> <MASTER3_IP>'

# Download log bundle
scp core@<BOOTSTRAP_IP>:~/log-bundle.tar.gz .
```

**Example**:
```bash
ssh -A core@54.238.178.100 '/usr/local/bin/installer-gather.sh 10.0.134.134 10.0.148.230 10.0.166.246'
scp core@54.238.178.100:~/log-bundle.tar.gz .
```

### Step 6: Extract and Check Log Content
```bash
# Extract log bundle
tar xvf log-bundle.tar.gz

# Check log directory structure
ls -la

# Check control plane node logs
ls -la */journal/

# Check node list
cat */resources/nodes.list
```

### Step 7: Verify Log Content (OpenShift 4.11+)
```bash
# Check serial logs (4.11 new feature)
ls -la */serial/

# Verify bootstrap node serial logs
ls -la */serial/bootstrap/

# Verify control plane node serial logs
ls -la */serial/master-*/
```

## Expected Results

### Success Criteria
1. **Log Collection Successful**: Able to successfully collect bootstrap node logs
2. **Log Content Complete**: Contains journal logs from at least one control plane subdirectory
3. **Node List Exists**: `resources/nodes.list` file exists and contains expected node list
4. **Serial Log Collection** (4.11+): Bootstrap and all available control plane node serial logs collected

### Verification Checkpoints
```bash
# Check if log bundle contains required files
find . -name "journal" -type d
find . -name "nodes.list"
find . -name "serial" -type d  # 4.11+

# Check log file sizes
du -sh */journal/
du -sh */serial/  # 4.11+
```

## Troubleshooting

### Common Issues

#### 1. SSH Connection Failed
```bash
# Check SSH Agent
ssh-add -l

# Re-add key
ssh-add ~/.ssh/id_rsa

# Test SSH connection
ssh -A core@<BOOTSTRAP_IP> 'echo "SSH connection successful"'
```

#### 2. Cannot Find Bootstrap Node IP
```bash
# Get from AWS console
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=<CLUSTER_NAME>-bootstrap" \
  --query 'Reservations[*].Instances[*].[PublicIpAddress,PrivateIpAddress]' \
  --output table
```

#### 3. Log Collection Script Execution Failed
```bash
# Manual execution of collection script
ssh -A core@<BOOTSTRAP_IP>
sudo /usr/local/bin/installer-gather.sh <MASTER1_IP> <MASTER2_IP> <MASTER3_IP>
```

### Debug Commands
```bash
# Check cluster status
openshift-install wait-for bootstrap-complete --dir . --log-level debug

# Check node status
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=<CLUSTER_NAME>-*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
  --output table
```

## Cleanup Steps
```bash
# Destroy cluster
openshift-install destroy cluster --dir .

# Clean up working directory
cd ..
rm -rf test-bootstrap-failure
```

## Notes
1. **Timing Selection**: Ensure interruption occurs when bootstrap succeeds but installation is incomplete
2. **Network Access**: Ensure ability to access bootstrap node public IP
3. **SSH Key**: Ensure SSH key is correctly configured and added to agent
4. **Log Size**: Log bundle may be large, ensure sufficient disk space
5. **Time Window**: Interruption timing is critical and requires quick response

## Related Documentation
- [OpenShift Installation Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-installer.html)
- [Troubleshooting Guide](https://docs.openshift.com/container-platform/latest/support/troubleshooting/troubleshooting-installations.html)