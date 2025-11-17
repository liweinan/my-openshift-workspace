#!/bin/bash

# Default values
AWS_PROFILE=""
REGION="us-east-1"
STACK_NAME="weli3-vpc"
VPC_CIDR="10.0.0.0/16"
AZ_COUNT=2
TEMPLATE_FILE="vpc-template-public-cluster.yaml"

usage() {
    echo "Usage: $0 [options]"
    echo "选项:"
    echo "  -p, --profile <profile>      AWS CLI profile to use. Leave empty to use the default profile."
    echo "  -r, --region <region>        The AWS region where the stack will be updated. (Default: ${REGION})"
    echo "  -s, --stack-name <name>      The name of the CloudFormation stack to update. (Default: ${STACK_NAME})"
    echo "  -c, --vpc-cidr <cidr>        The CIDR block for the VPC. (Default: ${VPC_CIDR})"
    echo "  -a, --az-count <count>       The number of Availability Zones to use (1, 2, or 3). (Default: ${AZ_COUNT})"
    echo "  -t, --template-file <file>   The path to the CloudFormation template file. (Default: ${TEMPLATE_FILE})"
    echo "  -h, --help                   Show this help message."
    echo ""
    echo "Note: This script will update the existing VPC stack, adding NAT Gateway and fixing network configuration."
    echo "      Network connectivity may be briefly interrupted during the update process."
    exit 1
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -p|--profile) AWS_PROFILE="$2"; shift ;;
        -r|--region) REGION="$2"; shift ;;
        -s|--stack-name) STACK_NAME="$2"; shift ;;
        -c|--vpc-cidr) VPC_CIDR="$2"; shift ;;
        -a|--az-count) AZ_COUNT="$2"; shift ;;
        -t|--template-file) TEMPLATE_FILE="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

echo "=========================================="
echo "VPC Stack Update Tool"
echo "=========================================="
echo "Stack Name: ${STACK_NAME}"
echo "Region: ${REGION}"
echo "Template File: ${TEMPLATE_FILE}"
echo "VPC CIDR: ${VPC_CIDR}"
echo "Availability Zone Count: ${AZ_COUNT}"
echo ""

# Check if stack exists
echo "Checking if stack exists..."
if ! aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    echo "Error: Stack '${STACK_NAME}' does not exist or cannot be accessed"
    exit 1
fi

echo "✓ Stack exists"
echo ""

# Show current stack status
echo "Current stack status:"
aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].[StackStatus,StackStatusReason]' \
    --output table

echo ""

# Confirm update
echo "Warning: Updating VPC stack may:"
echo "1. Briefly interrupt network connectivity"
echo "2. Recreate certain network resources"
echo "3. Change subnet MapPublicIpOnLaunch settings"
echo "4. Add NAT Gateway and EIP"
echo ""
read -p "Continue with update? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Update cancelled"
    exit 0
fi

echo ""

# Construct the AWS CLI command
CMD="aws cloudformation deploy \
  --region ${REGION} \
  --stack-name ${STACK_NAME} \
  --template-file ${TEMPLATE_FILE} \
  --parameter-overrides \
    VpcCidr=${VPC_CIDR} \
    AvailabilityZoneCount=${AZ_COUNT} \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset"

if [ -n "${AWS_PROFILE}" ]; then
  CMD="${CMD} --profile ${AWS_PROFILE}"
fi

echo "Executing update command:"
echo "${CMD}"
echo ""

# Execute the command
echo "Starting stack update..."
eval "${CMD}"

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✓ VPC stack update successful!"
    echo "=========================================="
    echo ""
    echo "Updated stack outputs:"
    aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query 'Stacks[0].Outputs' \
        --output table
    
    echo ""
    echo "Next steps:"
    echo "1. Run './get-vpc-outputs.sh ${STACK_NAME}' to get new configuration"
    echo "2. Update your install-config.yaml file"
    echo "3. Re-run OpenShift installation"
else
    echo ""
    echo "=========================================="
    echo "✗ VPC stack update failed!"
    echo "=========================================="
    echo "Please check error messages and retry"
    exit 1
fi
