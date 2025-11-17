# OpenShift Workspace Tools

This workspace contains various tool scripts for OpenShift cluster deployment, management, and cleanup.

## 🚀 Quick Start

### Cluster Deployment
```bash
# Create VPC
./tools/create-vpc-stack.sh

# Get VPC outputs
./tools/get-vpc-outputs.sh <stack-name>

# Create bastion host (private cluster)
./tools/create-bastion-host.sh <vpc-id> <subnet-id> <cluster-name>

# Install cluster
openshift-install create cluster --dir ./work1
```

### Cluster Destruction
```bash
# Standard destruction (with metadata.json)
openshift-install destroy cluster --dir ./work1

# Destruction without metadata.json
./tools/destroy-cluster-without-metadata.sh <cluster-name> <aws-region>

# Verify destruction status
./tools/check-cluster-destroy-status.sh ./work1 <aws-region>
```

### Workspace Cleanup
```bash
# Preview cleanup (recommended first)
./tools/cleanup-openshift-files.sh --dry-run

# Basic cleanup
./tools/cleanup-openshift-files.sh

# Safe cleanup (with backup)
./tools/cleanup-openshift-files-with-backup.sh
```

### Cleanup Orphaned Resources
```bash
# Find cluster information
./tools/find-cluster-info.sh weli-test

# Delete orphaned resources (dry-run mode)
./tools/delete-orphaned-cluster-resources.sh weli-test --dry-run

# Actually delete orphaned resources
./tools/delete-orphaned-cluster-resources.sh weli-test
```

## 📋 Tool Categories

### 🔍 Cluster Status Check Tools
- **`check-cluster-destroy-status.sh`** - Complete cluster destruction status check with detailed inspection report
- **`quick-check-destroy-status.sh`** - Quick check script providing concise status report

**Features:**
- Intelligent resource status analysis (distinguishing real leftover resources vs resources being deleted)
- Reduces false positives, provides more accurate status judgment
- Color output and better user experience
- Checks AWS resource tags, CloudFormation stacks, VPC, Route53 records

### 🧹 Cleanup Tools
- **`cleanup-openshift-files.sh`** - Basic cleanup script, directly deletes all OpenShift installation files
- **`cleanup-openshift-files-with-backup.sh`** - Cleanup script with backup functionality, backs up files before deletion

**Cleanup File Types:**
- Installation directories: `work*/`, `.openshift_install*`, `.clusterapi_output/`
- Authentication and certificates: `auth/`, `tls/`
- Metadata and configuration: `metadata.json`, `terraform.tfstate*`
- Logs and temporary files: `*.log`, `*.tmp`, `*.bak`
- OpenShift installer: `openshift-install`, `openshift-install-*.tar.gz`
- Release files: `release.txt`, `sha256sum.txt`, `pull-secret.json`

### 🔧 Cluster Destruction Tools
- **`destroy-cluster-without-metadata.sh`** - Complete automated destruction script containing all steps
- **`generate-metadata-for-destroy.sh`** - Script for generating metadata.json file

**Functions:**
- Automatically get cluster information from AWS
- Generate metadata.json file
- Verify cluster resource existence
- Execute cluster destruction
- Verify no leftover resources

### 🗑️ Orphaned Resource Cleanup Tools
- **`delete-orphaned-cluster-resources.sh`** - Script for deleting orphaned cluster resources
- **`find-cluster-info.sh`** - Script for finding cluster information

**Functions:**
- Delete Route53 records
- Delete CloudFormation stacks
- Delete S3 buckets
- Delete EC2 instances and volumes
- Delete load balancers
- Support dry-run mode preview

### 🏗️ VPC and Network Management
- **`create-vpc-stack.sh`** - Create VPC CloudFormation stack
- **`get-vpc-outputs.sh`** - Get VPC output information
- **`update-vpc-stack.sh`** - Update VPC stack
- **`tag-subnets.sh`** - Add tags to subnets

### 🖥️ Cluster Deployment Tools
- **`create-bastion-host.sh`** - Create bastion host
- **`configure-bastion-security.sh`** - Configure bastion host security group

### ☁️ AWS Resource Management
- **`delete-stacks-by-name.sh`** - Delete CloudFormation stacks by name
- **`find-stacks-by-name.sh`** - Find CloudFormation stacks
- **`get-stacks-status.sh`** - Get stack status

## 📁 Metadata Management Tools

### generate-metadata-for-destroy.sh
Used to dynamically generate `metadata.json` file for destroying OpenShift cluster when the original `metadata.json` file is not available.

**Usage:**
```bash
# Use cluster name (search from AWS VPC tags)
./tools/generate-metadata-for-destroy.sh <cluster-name> <aws-region>

# Use existing metadata.json file
./tools/generate-metadata-for-destroy.sh /path/to/metadata.json

# Specify output file
./tools/generate-metadata-for-destroy.sh <cluster-name> <aws-region> <output-file>
```

**Generated metadata.json format:**
```json
{
  "clusterName": "my-cluster",
  "clusterID": "12345678-1234-1234-1234-123456789012",
  "infraID": "my-cluster-abc123",
  "aws": {
    "region": "us-east-1",
    "identifier": [
      {"kubernetes.io/cluster/my-cluster-abc123": "owned"},
      {"sigs.k8s.io/cluster-api-provider-aws/cluster/my-cluster-abc123": "owned"}
    ]
  }
}
```

## 🎯 Usage Scenarios

### Scenario 1: Standard Cluster Deployment
```bash
# 1. Create VPC
./tools/create-vpc-stack.sh

# 2. Get configuration
./tools/get-vpc-outputs.sh my-vpc-stack

# 3. Install cluster
openshift-install create cluster --dir ./work1

# 4. Use cluster
export KUBECONFIG=./work1/auth/kubeconfig
oc get nodes
```

### Scenario 2: Private Cluster Deployment
```bash
# 1. Create VPC (private)
./tools/create-vpc-stack.sh

# 2. Create bastion host
./tools/create-bastion-host.sh vpc-xxx subnet-xxx my-cluster

# 3. Install cluster on bastion host
# (execute after copying files to bastion host)
openshift-install create cluster --dir .
```

### Scenario 3: Cluster Destruction and Cleanup
```bash
# 1. Destroy cluster
openshift-install destroy cluster --dir ./work1

# 2. Verify destruction status
./tools/check-cluster-destroy-status.sh ./work1 us-east-1

# 3. Clean up local files
./tools/cleanup-openshift-files.sh

# 4. Clean up AWS resources (if any leftovers)
./tools/delete-stacks-by-name.sh my-cluster
```

### Scenario 4: Destruction without metadata.json
```bash
# 1. Generate metadata.json
./tools/generate-metadata-for-destroy.sh my-cluster us-east-1

# 2. Destroy cluster
openshift-install destroy cluster --dir .

# 3. Verify destruction
./tools/check-cluster-destroy-status.sh . us-east-1
```

### Scenario 5: Cleanup Orphaned Resources
```bash
# 1. Find cluster information
./tools/find-cluster-info.sh weli-test

# 2. Preview resources to be deleted
./tools/delete-orphaned-cluster-resources.sh weli-test --dry-run

# 3. Actually delete orphaned resources
./tools/delete-orphaned-cluster-resources.sh weli-test
```

## 📋 Configuration Files

### Installation Configuration Samples
- `tools/install-config.sample.private.yaml` - Private cluster configuration
- `tools/install-config.sample.public.yaml` - Public cluster configuration

### VPC Templates
- `tools/vpc-template-private-cluster.yaml` - Private cluster VPC template
- `tools/vpc-template-public-cluster.yaml` - Public cluster VPC template
- `tools/vpc-template-original.yaml` - Original VPC template

## ⚙️ Dependency Requirements

### Required Tools
- `aws` CLI - AWS command line tool
- `jq` - JSON processing tool
- `openshift-install` - OpenShift installation tool

### AWS Permissions
- EC2 permissions (VPC, instance management)
- CloudFormation permissions (stack management)
- Resource Groups Tagging API permissions (resource tagging)
- Route53 permissions (DNS management)
- S3 permissions (bucket management)
- ELB permissions (load balancer management)

## 🔧 Troubleshooting

### Common Issues
1. **Permission errors**: Check AWS credentials and permissions
2. **Resource not found**: Confirm AWS region and resource names
3. **Destruction failure**: Check resource status, wait for deletion completion
4. **Incomplete cleanup**: Use cleanup script with backup
5. **False positive leftover resources**: Scripts now intelligently distinguish real leftover resources from resources being deleted, reducing false positives

### Getting Help
- Use `--help` or `--dry-run` parameters to preview operations
- Check AWS CloudTrail logs for detailed errors
- View detailed usage instructions for each tool

### Security Features

#### Confirmation Prompts
All deletion scripts will require user confirmation before deletion:
```
⚠️  This script will delete ALL resources associated with cluster 'cluster-name'
Are you sure you want to continue? (yes/no):
```

#### Preview Mode
Use `--dry-run` parameter to preview resources to be deleted without actually deleting:
```bash
./tools/delete-orphaned-cluster-resources.sh weli-test --dry-run
```

#### Backup Functionality
Scripts with backup functionality will:
- Create timestamped backup directory
- Copy all files to backup directory before deletion
- Display backup location and size
- Provide restore instructions

## 📚 Detailed Documentation

### Tool-Specific Documentation
- [VPC Template Description](tools/VPC_TEMPLATE_README.md)
- [Private Cluster Deployment Guide](tools/openshift-private-cluster-deployment-guide.md)
- [Cluster Configuration Samples](tools/CLUSTER_CONFIG_SAMPLES.md)
- [Usage Examples](tools/EXAMPLES.md)

### OCP Project Documentation
- [OCP-21535](OCP-21535/README.md) - RHEL Infrastructure Setup
- [OCP-21984](OCP-21984/README.md) - Cluster Worker Node Configuration
- [OCP-25698](OCP-25698/README.md) - Multi-cluster Shared Subnet Testing

## 🤝 Contributing

Issues and improvement suggestions are welcome. Please ensure:
1. Test new features
2. Update related documentation
3. Follow existing code style
4. Add appropriate error handling

## 📄 License

This project follows the Apache 2.0 license.
OpenShift is licensed under the Apache Public License 2.0. The source code for this program is [located on github](https://github.com/openshift/installer).