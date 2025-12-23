#!/bin/bash

################################################################################
# AWS Backup Auto-Creation Script
#
# This script automatically creates AWS Backup for OpenShift cluster instances
# after cluster installation completes.
#
# Usage:
#   ./create-aws-backup.sh [options]
#
# Options:
#   --install-dir <dir>        Installation directory (default: current directory)
#   --cluster-id <id>          Cluster infrastructure ID (auto-detected if not specified)
#   --region <region>          AWS region (default: us-east-1)
#   --instance-id <id>         EC2 instance ID to backup (default: first master)
#   --vault-name <name>        Backup vault name (default: <cluster-id>-backup-vault)
#   --monitor                  Monitor backup job until completion
#   --help                     Show this help message
#
# Examples:
#   # Basic usage (after cluster install)
#   ./create-aws-backup.sh
#
#   # Specify installation directory
#   ./create-aws-backup.sh --install-dir ~/works/openshift-versions/work2
#
#   # Monitor backup progress
#   ./create-aws-backup.sh --monitor
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
INSTALL_DIR="."
CLUSTER_ID=""
AWS_REGION="us-east-1"
INSTANCE_ID=""
VAULT_NAME=""
MONITOR=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --cluster-id)
            CLUSTER_ID="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --instance-id)
            INSTANCE_ID="$2"
            shift 2
            ;;
        --vault-name)
            VAULT_NAME="$2"
            shift 2
            ;;
        --monitor)
            MONITOR=true
            shift
            ;;
        --help)
            head -n 25 "$0" | tail -n +3
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check metadata.json
    if [ ! -f "$INSTALL_DIR/metadata.json" ]; then
        log_error "metadata.json not found in $INSTALL_DIR"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Get cluster information from metadata.json
get_cluster_info() {
    log_info "Reading cluster information from metadata.json..."
    
    if [ -z "$CLUSTER_ID" ]; then
        CLUSTER_ID=$(jq -r '.infraID // .clusterID' "$INSTALL_DIR/metadata.json" 2>/dev/null || echo "")
        if [ -z "$CLUSTER_ID" ] || [ "$CLUSTER_ID" = "null" ]; then
            log_error "Could not determine cluster ID from metadata.json"
            exit 1
        fi
    fi
    
    if [ -z "$AWS_REGION" ]; then
        AWS_REGION=$(jq -r '.aws.region // "us-east-1"' "$INSTALL_DIR/metadata.json" 2>/dev/null || echo "us-east-1")
    fi
    
    if [ -z "$VAULT_NAME" ]; then
        VAULT_NAME="${CLUSTER_ID}-backup-vault"
    fi
    
    log_info "Cluster ID: $CLUSTER_ID"
    log_info "Region: $AWS_REGION"
    log_info "Backup Vault: $VAULT_NAME"
}

# Get AWS account ID
get_aws_account_id() {
    log_info "Getting AWS account ID..."
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$AWS_REGION")
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
}

# List cluster instances and select one
select_instance() {
    log_info "Listing cluster instances..."
    
    if [ -z "$INSTANCE_ID" ]; then
        # Try to get first master instance
        INSTANCE_ID=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_ID},Values=owned" \
                      "Name=instance-state-name,Values=running" \
                      "Name=tag:Name,Values=*master*" \
            --query 'Reservations[0].Instances[0].InstanceId' \
            --output text 2>/dev/null || echo "")
        
        if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
            # Fallback to any running instance
            INSTANCE_ID=$(aws ec2 describe-instances \
                --region "$AWS_REGION" \
                --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_ID},Values=owned" \
                          "Name=instance-state-name,Values=running" \
                --query 'Reservations[0].Instances[0].InstanceId' \
                --output text 2>/dev/null || echo "")
        fi
        
        if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
            log_error "No running instances found for cluster $CLUSTER_ID"
            exit 1
        fi
    fi
    
    # Get instance details
    INSTANCE_NAME=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].Tags[?Key==`Name`].Value' \
        --output text 2>/dev/null || echo "unknown")
    
    log_info "Selected instance: $INSTANCE_ID ($INSTANCE_NAME)"
}

# Create backup vault
create_backup_vault() {
    log_info "Creating backup vault: $VAULT_NAME..."
    
    if aws backup describe-backup-vault \
        --backup-vault-name "$VAULT_NAME" \
        --region "$AWS_REGION" &> /dev/null; then
        log_warning "Backup vault $VAULT_NAME already exists"
    else
        aws backup create-backup-vault \
            --backup-vault-name "$VAULT_NAME" \
            --region "$AWS_REGION" \
            --output json > /tmp/backup-vault.json
        
        log_success "Backup vault created"
    fi
}

# Check and create IAM role
setup_iam_role() {
    log_info "Checking IAM role: AWSBackupDefaultServiceRole..."
    
    if aws iam get-role --role-name AWSBackupDefaultServiceRole &> /dev/null; then
        log_info "IAM role already exists"
    else
        log_info "Creating IAM role..."
        
        # Create trust policy
        cat > /tmp/backup-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "backup.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
        
        # Create role
        aws iam create-role \
            --role-name AWSBackupDefaultServiceRole \
            --assume-role-policy-document file:///tmp/backup-trust-policy.json \
            --description "Default service role for AWS Backup" \
            --output json > /tmp/iam-role.json
        
        log_success "IAM role created"
    fi
    
    # Attach policies
    log_info "Attaching IAM policies..."
    
    aws iam attach-role-policy \
        --role-name AWSBackupDefaultServiceRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup \
        2>/dev/null || log_warning "Backup policy may already be attached"
    
    aws iam attach-role-policy \
        --role-name AWSBackupDefaultServiceRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores \
        2>/dev/null || log_warning "Restore policy may already be attached"
    
    # Get role ARN
    ROLE_ARN=$(aws iam get-role --role-name AWSBackupDefaultServiceRole --query 'Role.Arn' --output text)
    BACKUP_ROLE_ARN="$ROLE_ARN"
    
    log_info "Using IAM role ARN: $BACKUP_ROLE_ARN"
}

# Create backup job
create_backup_job() {
    log_info "Creating backup job for instance: $INSTANCE_ID..."
    
    INSTANCE_ARN="arn:aws:ec2:${AWS_REGION}:${AWS_ACCOUNT_ID}:instance/${INSTANCE_ID}"
    log_info "Instance ARN: $INSTANCE_ARN"
    
    # Start backup job
    aws backup start-backup-job \
        --backup-vault-name "$VAULT_NAME" \
        --resource-arn "$INSTANCE_ARN" \
        --iam-role-arn "$BACKUP_ROLE_ARN" \
        --region "$AWS_REGION" \
        --output json > /tmp/backup-job.json
    
    BACKUP_JOB_ID=$(jq -r '.BackupJobId' /tmp/backup-job.json)
    
    log_success "Backup job created: $BACKUP_JOB_ID"
    echo "$BACKUP_JOB_ID" > /tmp/backup-job-id.txt
    
    # Save backup information
    cat > "$INSTALL_DIR/backup-info.json" <<EOF
{
  "backupJobId": "$BACKUP_JOB_ID",
  "backupVaultName": "$VAULT_NAME",
  "instanceId": "$INSTANCE_ID",
  "instanceName": "$INSTANCE_NAME",
  "region": "$AWS_REGION",
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log_info "Backup information saved to: $INSTALL_DIR/backup-info.json"
}

# Monitor backup job
monitor_backup_job() {
    if [ "$MONITOR" != "true" ]; then
        log_info "Backup job started. Use --monitor to track progress."
        log_info "Check status with: aws backup describe-backup-job --backup-job-id $BACKUP_JOB_ID --region $AWS_REGION"
        return
    fi
    
    log_info "Monitoring backup job: $BACKUP_JOB_ID..."
    log_info "This may take 15-30 minutes depending on instance size..."
    
    local max_wait=3600  # 60 minutes max
    local elapsed=0
    local check_interval=30
    
    while [ $elapsed -lt $max_wait ]; do
        local status=$(aws backup describe-backup-job \
            --backup-job-id "$BACKUP_JOB_ID" \
            --region "$AWS_REGION" \
            --query 'State' \
            --output text)
        
        local percent=$(aws backup describe-backup-job \
            --backup-job-id "$BACKUP_JOB_ID" \
            --region "$AWS_REGION" \
            --query 'PercentDone' \
            --output text 2>/dev/null || echo "0.0")
        
        echo -ne "\r[$(date +%H:%M:%S)] Backup status: $status (${percent}%)"
        
        if [ "$status" = "COMPLETED" ]; then
            echo ""
            log_success "Backup completed successfully"
            
            # Get recovery point ARN
            RECOVERY_POINT_ARN=$(aws backup describe-backup-job \
                --backup-job-id "$BACKUP_JOB_ID" \
                --region "$AWS_REGION" \
                --query 'RecoveryPointArn' \
                --output text)
            
            log_info "Recovery Point ARN: $RECOVERY_POINT_ARN"
            
            # Extract AMI ID
            AMI_ID=$(echo "$RECOVERY_POINT_ARN" | sed 's/.*image\///')
            log_info "AMI ID: $AMI_ID"
            
            return 0
        elif [ "$status" = "FAILED" ] || [ "$status" = "ABORTED" ]; then
            echo ""
            log_error "Backup failed with status: $status"
            aws backup describe-backup-job \
                --backup-job-id "$BACKUP_JOB_ID" \
                --region "$AWS_REGION" \
                --query '[State,StatusMessage]' \
                --output text
            return 1
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    echo ""
    log_warning "Backup monitoring timeout after $max_wait seconds"
    return 1
}

# Main execution
main() {
    log_info "=========================================="
    log_info "AWS Backup Auto-Creation"
    log_info "=========================================="
    echo ""
    
    check_prerequisites
    get_cluster_info
    get_aws_account_id
    select_instance
    create_backup_vault
    setup_iam_role
    create_backup_job
    monitor_backup_job
    
    echo ""
    log_success "=========================================="
    log_success "Backup creation completed!"
    log_success "=========================================="
    echo ""
    log_info "Backup Job ID: $BACKUP_JOB_ID"
    log_info "Backup Vault: $VAULT_NAME"
    log_info "Instance: $INSTANCE_ID ($INSTANCE_NAME)"
    echo ""
    log_info "To check backup status:"
    echo "  aws backup describe-backup-job --backup-job-id $BACKUP_JOB_ID --region $AWS_REGION"
    echo ""
    log_info "To monitor backup progress, run:"
    echo "  $0 --install-dir $INSTALL_DIR --monitor"
}

# Run main function
main "$@"
