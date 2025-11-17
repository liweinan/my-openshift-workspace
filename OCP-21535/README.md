# RHEL Infrastructure Deployment

This project automates the deployment of RHEL 8.10 infrastructure using AWS CloudFormation, including VPC, security groups, subnets, and EC2 instances.

## Project Structure

```
OCP-21535/
├── deploy-cloudformation.sh      # Main deployment script
├── ssh-connect.sh               # SSH connection script
├── rhel-infrastructure.yaml     # CloudFormation template
├── cleanup-cloudformation.sh    # Cleanup script
├── create-key.sh               # Key pair creation script
├── create-security-group.sh    # Security group creation script
├── run-instance.sh             # Instance running script
├── register-rhel.sh            # RHEL registration script
├── quick-rhel-setup.sh         # Quick RHEL setup script (subscription management, repository configuration, tool installation)
├── check-username.sh           # Username checking script
├── simple-cleanup.sh           # Simple cleanup script
└── README.md                   # Project documentation
```

## Features

- **Automated Deployment**: One-click deployment of complete RHEL infrastructure
- **Key Pair Management**: Automatic handling of key pair creation, deletion, and updates
- **Network Configuration**: Automatic creation of VPC, subnets, route tables, and internet gateways
- **Security Groups**: Pre-configured SSH, HTTP, HTTPS, and ICMP access rules
- **Instance Configuration**: Uses latest RHEL 8.10 AMI
- **Error Handling**: Comprehensive error handling and rollback mechanisms

## System Requirements

- AWS CLI installed and configured
- Appropriate AWS permissions (EC2, CloudFormation, VPC, etc.)
- Bash shell environment

## Quick Start

### 1. Deploy Infrastructure

```bash
./deploy-cloudformation.sh
```

This script will:
- Validate CloudFormation template
- Clean up existing key pairs and stacks
- Create new key pair
- Deploy CloudFormation stack
- Provide connection information

### 2. Connect to RHEL Instance

```bash
# Use SSH connection script
./ssh-connect.sh

# Or use SSH command directly
ssh -i weli-rhel-key.pem ec2-user@<PUBLIC_IP>
```

### 3. Configure RHEL System

After connecting to the instance, run the quick setup script:

```bash
# Run on RHEL instance
sudo ./quick-rhel-setup.sh
```

This script will:
- Check Red Hat subscription status
- Configure software repositories (including EPEL)
- Install common tools (vim, wget, curl, git, htop)
- Update system packages

### 4. Cleanup Resources

```bash
# Delete CloudFormation stack
./cleanup-cloudformation.sh

# Or use simple cleanup script
./simple-cleanup.sh
```

## Configuration Parameters

### CloudFormation Parameters

| Parameter | Default Value | Description |
|----------|---------------|-------------|
| KeyPairName | weli-rhel-key | EC2 key pair name |
| InstanceType | m5.xlarge | EC2 instance type |
| RHELImageId | ami-07cf28d58cb5c8f73 | RHEL 8.10 AMI ID |
| VpcCidr | 10.0.0.0/16 | VPC CIDR block |
| SubnetCidr | 10.0.1.0/24 | Subnet CIDR block |

### Supported Instance Types

- t3.micro, t3.small, t3.medium, t3.large
- m5.large, m5.xlarge, m5.2xlarge
- c5.large, c5.xlarge

## Network Architecture

```
Internet Gateway
       |
   Route Table
       |
   Public Subnet (10.0.1.0/24)
       |
   EC2 Instance (RHEL 8.10)
       |
   Security Group
   ├── SSH (22) - 0.0.0.0/0
   ├── HTTP (80) - 0.0.0.0/0
   ├── HTTPS (443) - 0.0.0.0/0
   └── ICMP - 0.0.0.0/0
```

## Security Group Rules

| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| SSH | TCP | 22 | 0.0.0.0/0 | SSH access |
| HTTP | TCP | 80 | 0.0.0.0/0 | HTTP access |
| HTTPS | TCP | 443 | 0.0.0.0/0 | HTTPS access |
| ICMP | ICMP | -1 | 0.0.0.0/0 | Ping test |

## Troubleshooting

### Common Issues

1. **Key Pair Conflict**
   - Script automatically handles key pair deletion and recreation
   - If issues persist, manually delete key pairs in AWS

2. **SSH Connection Failed**
   - Check if security group allows SSH access
   - Confirm instance status is "running"
   - Verify key file permissions (chmod 400)

3. **Stack Creation Failed**
   - Check AWS permissions
   - View CloudFormation event logs
   - Confirm AMI ID is available in target region

4. **RHEL Setup Issues**
   - If repositories are disabled, check Red Hat subscription status
   - Use `subscription-manager status` to check subscription
   - If htop installation fails, manually install EPEL: `sudo dnf install -y epel-release`
   - For unregistered systems, use `sudo dnf install --enablerepo=*` to temporarily enable repositories

### Log Viewing

```bash
# View CloudFormation events
aws cloudformation describe-stack-events --stack-name weli-rhel-stack --region us-east-1

# View instance system logs
aws ec2 get-console-output --instance-id <INSTANCE_ID> --region us-east-1
```

## Script Descriptions

### deploy-cloudformation.sh
Main deployment script containing complete deployment workflow:
- Template validation
- Key pair management
- Stack creation/update
- Output information display

### ssh-connect.sh
SSH connection script that automatically gets instance IP and establishes connection.

### quick-rhel-setup.sh
RHEL system quick configuration script providing complete system setup workflow:

**Features:**
- **Subscription Management**: Check Red Hat subscription status, support multiple registration methods
- **Repository Configuration**: Enable RHEL official repositories and EPEL repository
- **Tool Installation**: Automatically install common development and management tools
- **System Update**: Update system packages to latest versions

**Supported Registration Methods:**
- Red Hat account registration (username/password)
- Activation key registration
- Skip registration (test environments only)

**Installed Packages:**
- Basic tools: `vim`, `wget`, `curl`, `git`
- System monitoring: `htop` (from EPEL repository)
- System updates: All available updates

**Usage:**
```bash
# Run on RHEL instance
sudo ./quick-rhel-setup.sh
```

### cleanup-cloudformation.sh
Cleanup script that deletes CloudFormation stack and related resources.

## Version Information

- **RHEL Version**: 8.10 (Ootpa)
- **AMI ID**: ami-07cf28d58cb5c8f73
- **Default Instance Type**: m5.xlarge
- **Default User**: ec2-user

## Notes

1. Ensure AWS CLI is properly configured before deployment
2. Instance initialization takes a few minutes after startup
3. Keep key file `weli-rhel-key.pem` secure, do not commit to version control
4. Production environments should use stricter network access controls

## License

This project follows the MIT license.