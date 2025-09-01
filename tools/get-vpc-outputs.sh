#!/bin/bash

# Check if a stack name is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <stack-name>"
  echo "Please provide the name of the CloudFormation stack."
  exit 1
fi

STACK_NAME=$1
# You can specify your AWS region here if needed.
# If you encounter errors, make sure this region matches where your stack was created.
REGION="us-east-1"

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "Error: jq is not installed. Please install jq to run this script."
    echo "On macOS: brew install jq"
    echo "On Debian/Ubuntu: sudo apt-get install jq"
    echo "On RHEL/CentOS: sudo yum install jq"
    exit 1
fi

echo "Querying stack '${STACK_NAME}' in region '${REGION}' for outputs..."

# AWS CLI command to describe the stack and extract outputs using jq
OUTPUTS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query "Stacks[0].Outputs" 2>/dev/null)

# Check if the command was successful
if [ $? -ne 0 ]; then
  echo "Error: Failed to describe stack '${STACK_NAME}'. Please check if the stack exists and you have the correct permissions."
  exit 1
fi

if [ -z "${OUTPUTS}" ] || [ "${OUTPUTS}" == "null" ]; then
    echo "Error: No outputs found for stack '${STACK_NAME}'."
    exit 1
fi

# Extract and print the VPC ID
VPC_ID=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="VpcId") | .OutputValue')

# Extract and print the Private Subnet IDs
PRIVATE_SUBNET_IDS=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="PrivateSubnetIds") | .OutputValue')
# Extract and print the Public Subnet IDs
PUBLIC_SUBNET_IDS=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="PublicSubnetIds") | .OutputValue')

echo "----------------------------------------------------------------"
echo "VPC Information"
echo "----------------------------------------------------------------"
echo "VPC ID: ${VPC_ID}"
echo "Public Subnets: ${PUBLIC_SUBNET_IDS}"
echo "Private Subnets: ${PRIVATE_SUBNET_IDS}"

# If it's a private cluster (PrivateSubnetIds is not empty), print the install-config.yaml section.
if [ -n "${PRIVATE_SUBNET_IDS}" ]; then
    echo ""
    echo "--- For install-config.yaml ---"
    echo "platform:"
    echo "  aws:"
    echo "    subnets:"
    # Convert comma-separated string to a YAML list format with correct indentation
    echo "${PRIVATE_SUBNET_IDS}" | tr ',' '\n' | sed 's/^/    - /'
fi
echo "----------------------------------------------------------------"
