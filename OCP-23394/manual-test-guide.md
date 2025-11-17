# OCP-23394 Manual Test Guide

## Test Case Corresponding Steps

### Step 1: Set up SSH Agent
**Test Case Step**: `set up the ssh-agent`
```bash
# Set up SSH Agent
eval `ssh-agent -s`
ssh-add ~/.ssh/id_rsa

# Verify setup
ssh-add -l
```

**Expected Result**: SSH Agent started successfully, SSH key added

### Step 2: Start Cluster Installation
**Test Case Step**: `launch a cluster`
```bash
# Create working directory
mkdir test-bootstrap-failure
cd test-bootstrap-failure

# Generate install-config.yaml
openshift-install create install-config --dir .

# Start cluster installation
openshift-install create cluster --dir .
```

**Expected Result**: Cluster installation starts, installation progress output visible

### Step 3: Interrupt Installation Process
**Test Case Step**: `enter 'ctrl-c' to break openshift-install when the condition is satisfied`

#### Important Note: Bootstrap Node Lifecycle
- **Bootstrap Node Creation**: Created at installation start
- **Bootstrap Node Function**: Starts control plane nodes
- **Bootstrap Node Destruction**: Destroyed after `wait-for bootstrap-complete` completes
- **Log Collection**: `gather bootstrap` command collects relevant logs from control plane nodes when bootstrap node doesn't exist

#### Method A: Monitor Log Messages and Interrupt
**Critical Timing**: When you see the following message, immediately press `Ctrl+C` to interrupt:
```
added bootstrap-success: Required control plane pods have been created
```

#### Method B: Staged Interruption
```bash
# Wait for bootstrap to complete (bootstrap node will be destroyed at this point)
openshift-install wait-for bootstrap-complete --dir .

# Then interrupt during install-complete phase
openshift-install wait-for install-complete --dir .
# Press Ctrl+C to interrupt
```

**Expected Result**: Installation process successfully interrupted, bootstrap node completed its work but cluster installation not finished

### Step 4: Collect Bootstrap Logs
**Test Case Step**: `use the sub-command 'gather' to collect information`

#### Important Note: Log Collection Mechanism
- **When Bootstrap Node Exists**: Collect logs directly from bootstrap node
- **When Bootstrap Node Destroyed**: Collect relevant bootstrap logs from control plane nodes
- **Smart Collection**: `gather bootstrap` command automatically handles both scenarios

#### Method 1: Use Directory Parameter (Recommended)
```bash
openshift-install gather bootstrap --dir .
```

#### Method 2: Use Specific IP Addresses
```bash
openshift-install gather bootstrap \
  --bootstrap <BOOTSTRAP_IP> \
  --master "<MASTER1_IP> <MASTER2_IP> <MASTER3_IP>"
```

**Expected Result**: Output similar to:
```
INFO Use the following commands to gather logs from the cluster
INFO ssh -A core@<BOOTSTRAP_IP> '/usr/local/bin/installer-gather.sh <MASTER1_IP> <MASTER2_IP> <MASTER3_IP>'
INFO scp core@<BOOTSTRAP_IP>:~/log-bundle.tar.gz .
```

**Note**: If bootstrap node has been destroyed, the command will collect relevant logs from control plane nodes.

### Step 5: Execute Log Collection Commands
**Test Case Step**: `Following the guide to gather debugging data`

```bash
# Execute log collection script
ssh -A core@<BOOTSTRAP_IP> '/usr/local/bin/installer-gather.sh <MASTER1_IP> <MASTER2_IP> <MASTER3_IP>'

# Download log bundle
scp core@<BOOTSTRAP_IP>:~/log-bundle.tar.gz .
```

**Expected Results**: 
- SSH connection successful, log collection script execution completed
- Output: `Log bundle written to ~/log-bundle.tar.gz`
- Log bundle successfully downloaded to local

### Step 6: Verify Log Content
**Test Case Step**: `check the contents of the logs to verify that at least one of the control-plane sub-directories has a journal log and the resources/nodes.list to exist`

```bash
# Extract log bundle
tar xvf log-bundle.tar.gz

# Check log directory structure
ls -la

# Check control plane node logs
find . -name "journal" -type d
ls -la */journal/

# Check node list
find . -name "nodes.list"
cat */resources/nodes.list
```

**Expected Results**:
- At least one control plane subdirectory contains journal logs
- `resources/nodes.list` file exists and contains expected node list
- Log files are reasonably sized with complete content

### Step 7: Verify Serial Logs (OpenShift 4.11+)
**Test Case Step**: `Check the content of log-bundle directory, the bootstrap and all available control-plane nodes' serial logs should be gathered under [log-bundle directory]/serial`

```bash
# Check serial log directory
find . -name "serial" -type d
ls -la */serial/

# Verify bootstrap node serial logs
ls -la */serial/bootstrap/

# Verify control plane node serial logs
ls -la */serial/master-*/
```

**Expected Results** (4.11+):
- Bootstrap and all available control plane node serial logs collected
- Serial logs located in `[log-bundle directory]/serial` directory
- Log files contain system boot and runtime information

## Getting IP Addresses

### Bootstrap Node IP
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=<CLUSTER_NAME>-bootstrap" \
  --query 'Reservations[*].Instances[*].PublicIpAddress' \
  --output text
```

### Master Node IP
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=<CLUSTER_NAME>-master-*" \
  --query 'Reservations[*].Instances[*].PrivateIpAddress' \
  --output text
```

## Test Result Verification

### Success Criteria Checklist
**Test Case Expected Result**: Verify log collection functionality works properly when installation fails

✅ **Must Meet Conditions**:
1. **Log Collection Successful**: Able to successfully collect bootstrap node logs
2. **Journal Logs Exist**: Contains journal logs from at least one control plane subdirectory
3. **Node List Exists**: `resources/nodes.list` file exists and contains expected node list
4. **Serial Log Collection** (4.11+): Bootstrap and all available control plane node serial logs collected

### Verification Commands
```bash
# Check log bundle integrity
tar -tf log-bundle.tar.gz | head -20

# Verify required files exist
find . -name "journal" -type d | wc -l  # Should be > 0
find . -name "nodes.list" | wc -l       # Should be > 0
find . -name "serial" -type d | wc -l   # 4.11+ Should be > 0

# Check log file sizes
du -sh */journal/ 2>/dev/null
du -sh */serial/ 2>/dev/null  # 4.11+

# Verify node list content
cat */resources/nodes.list
```

### Test Result Determination
- **✅ PASS**: All must-meet conditions are satisfied
- **❌ FAIL**: Any must-meet condition is missing

## Cleanup Steps
```bash
# Destroy cluster
openshift-install destroy cluster --dir .

# Clean up directory
cd ..
rm -rf test-bootstrap-failure
```

## Troubleshooting

### SSH Connection Issues
```bash
# Check SSH Agent
ssh-add -l

# Test connection
ssh -A core@<BOOTSTRAP_IP> 'echo "Connection OK"'
```

### Cannot Find IP Address
```bash
# Check all instances
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=<CLUSTER_NAME>-*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
  --output table
```

### Log Collection Failed
```bash
# Manual execution
ssh -A core@<BOOTSTRAP_IP>
sudo /usr/local/bin/installer-gather.sh <MASTER1_IP> <MASTER2_IP> <MASTER3_IP>
```

## Test Case Summary

**OCP-23394**: `[ipi-on-aws] collect logs from a cluster that failed to bootstrap running installer on linux`

**Test Objective**: Verify the ability to correctly collect debugging logs and troubleshooting information when OpenShift cluster installation bootstrap fails.

**Key Test Points**:
1. **Interruption Timing**: Interrupt when bootstrap succeeds but installation is incomplete
2. **Log Collection**: Verify `openshift-install gather bootstrap` command functionality
3. **Log Completeness**: Ensure collected logs contain necessary debugging information
4. **Troubleshooting**: Verify log collection tools work properly under abnormal conditions

**Real-world Application Value**: This test validates functionality that is very important for production environment fault diagnosis and problem troubleshooting, ensuring sufficient debugging information can be collected when cluster installation fails.