#!/bin/bash

# OCP-29781 VPC Creation Script
# Create VPC and subnets using multi-CIDR template

set -euo pipefail

# Default configuration variables
DEFAULT_STACK_NAME="ocp29781-vpc-$(date +%s)"
DEFAULT_AWS_REGION="us-east-2"
DEFAULT_VPC_CIDR="10.0.0.0/16"
DEFAULT_VPC_CIDR2="10.134.0.0/16"
DEFAULT_VPC_CIDR3="10.190.0.0/16"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/01_vpc_multiCidr.yaml"

# Parse command line arguments
STACK_NAME="${DEFAULT_STACK_NAME}"
AWS_REGION="${DEFAULT_AWS_REGION}"
VPC_CIDR="${DEFAULT_VPC_CIDR}"
VPC_CIDR2="${DEFAULT_VPC_CIDR2}"
VPC_CIDR3="${DEFAULT_VPC_CIDR3}"
SHOW_HELP=false

# Display help information
show_help() {
    cat << EOF
OCP-29781 VPC Creation Script

Usage: $0 [options]

Options:
    -n, --name NAME          Specify VPC stack name (default: ${DEFAULT_STACK_NAME})
    -r, --region REGION     Specify AWS region (default: ${DEFAULT_AWS_REGION})
    -c, --cidr CIDR         Specify primary VPC CIDR (default: ${DEFAULT_VPC_CIDR})
    -c2, --cidr2 CIDR2      Specify second VPC CIDR (default: ${DEFAULT_VPC_CIDR2})
    -c3, --cidr3 CIDR3      Specify third VPC CIDR (default: ${DEFAULT_VPC_CIDR3})
    -h, --help              Display this help information

Examples:
    $0                                    # Use default configuration
    $0 -n my-vpc -r us-west-2            # Specify name and region
    $0 --name test-vpc --cidr 10.1.0.0/16 # Specify name and CIDR

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            STACK_NAME="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -c|--cidr)
            VPC_CIDR="$2"
            shift 2
            ;;
        -c2|--cidr2)
            VPC_CIDR2="$2"
            shift 2
            ;;
        -c3|--cidr3)
            VPC_CIDR3="$2"
            shift 2
            ;;
        -h|--help)
            SHOW_HELP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Display help and exit
if [[ "${SHOW_HELP}" == "true" ]]; then
    show_help
    exit 0
fi

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured, please run 'aws configure'"
        exit 1
    fi
    
    # Check template file
    if [[ ! -f "${TEMPLATE_FILE}" ]]; then
        log_error "Template file does not exist: ${TEMPLATE_FILE}"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Create VPC stack
create_vpc_stack() {
    log_info "Creating VPC stack: ${STACK_NAME}"
    log_info "Using template: ${TEMPLATE_FILE}"
    log_info "VPC CIDR configuration:"
    log_info "  Primary CIDR: ${VPC_CIDR}"
    log_info "  Second CIDR: ${VPC_CIDR2}"
    log_info "  Third CIDR: ${VPC_CIDR3}"
    
    # Create CloudFormation stack
    aws cloudformation create-stack \
        --region "${AWS_REGION}" \
        --stack-name "${STACK_NAME}" \
        --template-body "file://${TEMPLATE_FILE}" \
        --capabilities CAPABILITY_IAM \
        --parameters \
            ParameterKey=VpcCidr,ParameterValue="${VPC_CIDR}" \
            ParameterKey=VpcCidr2,ParameterValue="${VPC_CIDR2}" \
            ParameterKey=VpcCidr3,ParameterValue="${VPC_CIDR3}" \
            ParameterKey=AvailabilityZoneCount,ParameterValue=3 \
        --tags \
            Key=Project,Value=OCP-29781 \
            Key=Environment,Value=Test \
            Key=Purpose,Value=MultiCIDR-VPC-Test \
            Key=StackName,Value="${STACK_NAME}"
    
    if [[ $? -eq 0 ]]; then
        log_success "VPC stack creation initiated"
    else
        log_error "VPC stack creation failed"
        exit 1
    fi
}

# Wait for stack creation to complete
wait_for_stack_completion() {
    log_info "Waiting for stack creation to complete..."
    log_info "This may take a few minutes..."
    
    aws cloudformation wait stack-create-complete --region "${AWS_REGION}" --stack-name "${STACK_NAME}"
    
    if [[ $? -eq 0 ]]; then
        log_success "Stack creation completed"
    else
        log_error "Stack creation failed or timed out"
        log_info "Please check CloudFormation console for details"
        exit 1
    fi
}

# Get stack outputs
get_stack_outputs() {
    log_info "Retrieving stack output information..."
    
    # Get VPC ID
    local vpc_id
    vpc_id=$(aws cloudformation describe-stacks \
        --region "${AWS_REGION}" \
        --stack-name "${STACK_NAME}" \
        --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
        --output text)
    
    if [[ -n "${vpc_id}" ]]; then
        log_success "VPC ID: ${vpc_id}"
        echo "VPC_ID=${vpc_id}" > vpc-info.env
    else
        log_warning "Cannot get VPC ID"
    fi
    
    # Get subnet information
    log_info "Retrieving subnet information..."
    aws cloudformation describe-stacks \
        --region "${AWS_REGION}" \
        --stack-name "${STACK_NAME}" \
        --query 'Stacks[0].Outputs[?contains(OutputKey, `Subnet`)].{Key:OutputKey,Value:OutputValue}' \
        --output table
    
    # Save stack output to file
    aws cloudformation describe-stacks \
        --region "${AWS_REGION}" \
        --stack-name "${STACK_NAME}" \
        --output json > stack-output.json
    
    log_success "Stack output saved to stack-output.json"
}

# Validate created resources
validate_resources() {
    log_info "Validating created resources..."
    
    # Read VPC ID from environment file
    if [[ -f "vpc-info.env" ]]; then
        source vpc-info.env
        log_info "Validating VPC: ${VPC_ID}"
        
        if aws ec2 describe-vpcs --region "${AWS_REGION}" --vpc-ids "${VPC_ID}" &> /dev/null; then
            log_success "VPC exists and is accessible"
        else
            log_error "VPC validation failed"
            return 1
        fi
        
        # Check subnet count
        local subnet_count
        subnet_count=$(aws ec2 describe-subnets \
            --region "${AWS_REGION}" \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'length(Subnets)' \
            --output text)
        
        log_info "Found ${subnet_count} subnets in VPC"
        
        # Display all subnet information
        aws ec2 describe-subnets \
            --region "${AWS_REGION}" \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'Subnets[*].{SubnetId:SubnetId,CidrBlock:CidrBlock,AvailabilityZone:AvailabilityZone,State:State}' \
            --output table
    else
        log_warning "VPC information file not found"
    fi
}

# Display usage information
show_usage() {
    echo "VPC creation completed!"
    echo ""
    echo "Next steps:"
    echo "1. Check stack-output.json file to get subnet IDs"
    echo "2. Update subnet IDs in install-config-cluster1.yaml and install-config-cluster2.yaml"
    echo "3. Run cluster installation script"
    echo ""
    echo "Cleanup resources:"
    echo "aws cloudformation delete-stack --stack-name ${STACK_NAME}"
    echo ""
    echo "Stack name: ${STACK_NAME}"
    echo "VPC information saved to: vpc-info.env"
    echo "Stack output saved to: stack-output.json"
}

# Main function
main() {
    log_info "Starting OCP-29781 VPC creation process"
    
    # Display configuration
    log_info "Configuration information:"
    log_info "  Stack name: ${STACK_NAME}"
    log_info "  Template file: ${TEMPLATE_FILE}"
    log_info "  AWS region: ${AWS_REGION}"
    log_info "  VPC CIDR: ${VPC_CIDR}"
    log_info "  VPC CIDR2: ${VPC_CIDR2}"
    log_info "  VPC CIDR3: ${VPC_CIDR3}"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Create VPC stack
    create_vpc_stack
    
    # Wait for completion
    wait_for_stack_completion
    
    # Get outputs
    get_stack_outputs
    
    # Validate resources
    validate_resources
    
    # Display usage information
    show_usage
    
    log_success "VPC creation process completed!"
}

# Run main function
main "$@"