#!/bin/bash
# run-ocp25784-test.sh
# OCP-25784 - [ipi-on-aws] Create private clusters with no public endpoints and access from internet

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(dirname "$SCRIPT_DIR")/tools"

# Default values
DEFAULT_VPC_STACK_NAME="weli-vpc-priv"
DEFAULT_CLUSTER_NAME="weli-priv-test"
DEFAULT_AWS_REGION="us-east-1"
DEFAULT_VPC_CIDR="10.0.0.0/16"
DEFAULT_BASTION_NAME="weli-test"

# --- Logging functions ---
log_info() {
    echo "[INFO] $@"
}

log_success() {
    echo "[SUCCESS] $@"
}

log_error() {
    echo "[ERROR] $@" >&2
}

log_warning() {
    echo "[WARNING] $@"
}

# --- Helper functions ---
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OCP-25784 Private Cluster Test Runner

OPTIONS:
    -v, --vpc-stack-name NAME     VPC CloudFormation stack name (default: $DEFAULT_VPC_STACK_NAME)
    -c, --cluster-name NAME       OpenShift cluster name (default: $DEFAULT_CLUSTER_NAME)
    -r, --region REGION           AWS region (default: $DEFAULT_AWS_REGION)
    -b, --bastion-name NAME       Bastion host name (default: $DEFAULT_BASTION_NAME)
    -d, --vpc-cidr CIDR           VPC CIDR block (default: $DEFAULT_VPC_CIDR)
    -p, --proxy                   Enable proxy settings
    -s, --skip-cleanup            Skip cleanup after test
    -h, --help                    Show this help message

EXAMPLES:
    # Run with default settings
    $0

    # Run with custom cluster name
    $0 --cluster-name my-private-cluster

    # Run with proxy enabled
    $0 --proxy

    # Run without cleanup
    $0 --skip-cleanup

ENVIRONMENT VARIABLES:
    VPC_STACK_NAME               Override default VPC stack name
    CLUSTER_NAME                 Override default cluster name
    AWS_REGION                   Override default AWS region
    BASTION_NAME                 Override default bastion name
    VPC_CIDR                     Override default VPC CIDR
EOF
}

# --- Default values ---
VPC_STACK_NAME="${VPC_STACK_NAME:-$DEFAULT_VPC_STACK_NAME}"
CLUSTER_NAME="${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}"
AWS_REGION="${AWS_REGION:-$DEFAULT_AWS_REGION}"
BASTION_NAME="${BASTION_NAME:-$DEFAULT_BASTION_NAME}"
VPC_CIDR="${VPC_CIDR:-$DEFAULT_VPC_CIDR}"
ENABLE_PROXY=false
SKIP_CLEANUP=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--vpc-stack-name)
            VPC_STACK_NAME="$2"
            shift 2
            ;;
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -b|--bastion-name)
            BASTION_NAME="$2"
            shift 2
            ;;
        -d|--vpc-cidr)
            VPC_CIDR="$2"
            shift 2
            ;;
        -p|--proxy)
            ENABLE_PROXY=true
            shift
            ;;
        -s|--skip-cleanup)
            SKIP_CLEANUP=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# --- Validation ---
if [[ ! -d "$TOOLS_DIR" ]]; then
    log_error "Tools directory not found: $TOOLS_DIR"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Please install AWS CLI."
    exit 1
fi

# --- Core functions ---
setup_proxy() {
    if [[ "$ENABLE_PROXY" == "true" ]]; then
        log_info "Setting up proxy configuration..."
        export http_proxy=http://squid.corp.redhat.com:3128
        export https_proxy=http://squid.corp.redhat.com:3128
        log_success "Proxy configuration set"
    fi
}

create_vpc() {
    log_info "Creating VPC stack: $VPC_STACK_NAME"
    
    local template_file="$TOOLS_DIR/vpc-template-private-cluster.yaml"
    if [[ ! -f "$template_file" ]]; then
        log_error "VPC template not found: $template_file"
        return 1
    fi
    
    if "$TOOLS_DIR/create-vpc-stack.sh" -s "$VPC_STACK_NAME" -t "$template_file" \
        --parameter-overrides "VpcCidr=$VPC_CIDR" "AvailabilityZoneCount=2"; then
        log_success "VPC stack created successfully"
    else
        log_error "Failed to create VPC stack"
        return 1
    fi
}

get_vpc_outputs() {
    log_info "Getting VPC outputs..."
    
    local vpc_id
    local public_subnet_ids
    local private_subnet_ids
    
    vpc_id=$(aws cloudformation describe-stacks \
        --stack-name "$VPC_STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
        --output text)
    
    public_subnet_ids=$(aws cloudformation describe-stacks \
        --stack-name "$VPC_STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
        --output text)
    
    private_subnet_ids=$(aws cloudformation describe-stacks \
        --stack-name "$VPC_STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnetIds`].OutputValue' \
        --output text)
    
    if [[ -z "$vpc_id" || -z "$public_subnet_ids" || -z "$private_subnet_ids" ]]; then
        log_error "Failed to get VPC outputs"
        return 1
    fi
    
    # Export for use in other functions
    export VPC_ID="$vpc_id"
    export PUBLIC_SUBNET_IDS="$public_subnet_ids"
    export PRIVATE_SUBNET_IDS="$private_subnet_ids"
    
    log_success "VPC outputs retrieved:"
    log_info "  VPC ID: $VPC_ID"
    log_info "  Public Subnets: $PUBLIC_SUBNET_IDS"
    log_info "  Private Subnets: $PRIVATE_SUBNET_IDS"
}

create_bastion() {
    log_info "Creating bastion host: $BASTION_NAME"
    
    # Get first public subnet ID
    local public_subnet_id
    public_subnet_id=$(echo "$PUBLIC_SUBNET_IDS" | cut -d',' -f1)
    
    if "$TOOLS_DIR/create-bastion-host.sh" "$VPC_ID" "$public_subnet_id" "$BASTION_NAME"; then
        log_success "Bastion host created successfully"
    else
        log_error "Failed to create bastion host"
        return 1
    fi
}

tag_subnets() {
    log_info "Tagging subnets for cluster: $CLUSTER_NAME"
    
    if "$TOOLS_DIR/tag-subnets.sh" "$VPC_STACK_NAME" "$CLUSTER_NAME" "$AWS_REGION"; then
        log_success "Subnets tagged successfully"
    else
        log_error "Failed to tag subnets"
        return 1
    fi
}

download_tools() {
    log_info "Downloading OpenShift CLI tools..."
    
    if [[ -f "$TOOLS_DIR/download-oc.sh" ]]; then
        cd "$TOOLS_DIR"
        if ./download-oc.sh --version 4.20.0-rc.2; then
            log_success "OpenShift CLI tools downloaded"
        else
            log_error "Failed to download OpenShift CLI tools"
            return 1
        fi
        cd "$SCRIPT_DIR"
    else
        log_warning "download-oc.sh not found, skipping tool download"
    fi
}

get_bastion_info() {
    log_info "Getting bastion host information..."
    
    local bastion_stack_name="${BASTION_NAME}-bastion"
    local public_ip
    
    public_ip=$(aws cloudformation describe-stacks \
        --stack-name "$bastion_stack_name" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`PublicIP`].OutputValue' \
        --output text)
    
    if [[ -z "$public_ip" ]]; then
        log_error "Failed to get bastion public IP"
        return 1
    fi
    
    export BASTION_PUBLIC_IP="$public_ip"
    log_success "Bastion host information:"
    log_info "  Public IP: $BASTION_PUBLIC_IP"
    log_info "  SSH Command: ssh core@$BASTION_PUBLIC_IP"
}

create_install_config() {
    log_info "Creating install-config.yaml template..."
    
    # Get first two private subnet IDs
    local subnet1 subnet2
    subnet1=$(echo "$PRIVATE_SUBNET_IDS" | cut -d',' -f1)
    subnet2=$(echo "$PRIVATE_SUBNET_IDS" | cut -d',' -f2)
    
    cat > "$SCRIPT_DIR/install-config-template.yaml" << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
metadata:
  name: $CLUSTER_NAME
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: $VPC_CIDR
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: $AWS_REGION
    vpc:
      subnets:
        - id: $subnet1
        - id: $subnet2
publish: Internal
EOF
    
    log_success "install-config-template.yaml created"
    log_info "Please copy this file to your bastion host and customize as needed"
}

cleanup() {
    if [[ "$SKIP_CLEANUP" == "true" ]]; then
        log_info "Skipping cleanup as requested"
        return 0
    fi
    
    log_info "Starting cleanup..."
    
    # Clean up bastion host
    local bastion_stack_name="${BASTION_NAME}-bastion"
    if aws cloudformation describe-stacks --stack-name "$bastion_stack_name" --region "$AWS_REGION" &>/dev/null; then
        log_info "Deleting bastion host stack: $bastion_stack_name"
        aws cloudformation delete-stack --stack-name "$bastion_stack_name" --region "$AWS_REGION"
    fi
    
    # Clean up VPC stack
    if aws cloudformation describe-stacks --stack-name "$VPC_STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
        log_info "Deleting VPC stack: $VPC_STACK_NAME"
        aws cloudformation delete-stack --stack-name "$VPC_STACK_NAME" --region "$AWS_REGION"
    fi
    
    log_success "Cleanup initiated"
}

# --- Main execution ---
main() {
    log_info "Starting OCP-25784 Private Cluster Test"
    log_info "Configuration:"
    log_info "  VPC Stack Name: $VPC_STACK_NAME"
    log_info "  Cluster Name: $CLUSTER_NAME"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  Bastion Name: $BASTION_NAME"
    log_info "  VPC CIDR: $VPC_CIDR"
    log_info "  Proxy Enabled: $ENABLE_PROXY"
    log_info "  Skip Cleanup: $SKIP_CLEANUP"
    echo
    
    # Setup proxy if requested
    setup_proxy
    
    # Create VPC
    create_vpc || exit 1
    
    # Get VPC outputs
    get_vpc_outputs || exit 1
    
    # Create bastion host
    create_bastion || exit 1
    
    # Tag subnets
    tag_subnets || exit 1
    
    # Download tools
    download_tools || exit 1
    
    # Get bastion info
    get_bastion_info || exit 1
    
    # Create install config template
    create_install_config || exit 1
    
    log_success "OCP-25784 test setup completed successfully!"
    echo
    log_info "Next steps:"
    log_info "1. SSH to bastion host: ssh core@$BASTION_PUBLIC_IP"
    log_info "2. Copy install-config-template.yaml to bastion host"
    log_info "3. Run openshift-install create cluster on bastion host"
    log_info "4. Verify private cluster access"
    echo
    log_info "To cleanup resources, run: $0 --skip-cleanup false"
}

# --- Error handling ---
trap cleanup EXIT

# --- Run main function ---
main "$@"
