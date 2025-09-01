#!/bin/bash

# Check if a stack name is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <stack-name>"
  echo "Please provide the name of the CloudFormation stack."
  echo "The script will output configurations for both private and public clusters."
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

echo ""
echo "=================================================================="
echo "PRIVATE CLUSTER CONFIGURATION"
echo "=================================================================="
echo "# Use this configuration for private clusters (publish: Internal)"
echo "# Only private subnets are needed for private clusters"
echo "platform:"
echo "  aws:"
echo "    region: ${REGION}"
echo "    vpc:"
echo "      subnets:"

# Determine zones based on region
if [ "${REGION}" = "us-east-1" ]; then
    ZONES=("us-east-1a" "us-east-1b")
elif [ "${REGION}" = "us-west-2" ]; then
    ZONES=("us-west-2a" "us-west-2b")
elif [ "${REGION}" = "eu-west-1" ]; then
    ZONES=("eu-west-1a" "eu-west-1b")
else
    # Generic zone naming for other regions
    ZONES=("${REGION}a" "${REGION}b")
fi

# Private cluster configuration - only private subnets
if [ -n "${PRIVATE_SUBNET_IDS}" ]; then
    PRIVATE_SUBNET_ARRAY=($(echo "${PRIVATE_SUBNET_IDS}" | tr ',' ' '))
    
    for i in "${!PRIVATE_SUBNET_ARRAY[@]}"; do
        if [ $i -lt ${#ZONES[@]} ]; then
            echo "      - id: ${PRIVATE_SUBNET_ARRAY[$i]}"
            echo "        zone: ${ZONES[$i]}"
        fi
    done
    
    echo ""
    echo "publish: Internal"
    echo ""
    echo "Note: Private clusters use only private subnets for enhanced security."
    echo "      All nodes will be deployed in private subnets."
else
    echo "# ERROR: No Private Subnets found."
    echo "# Please ensure your VPC has private subnets configured."
fi

echo ""
echo "=================================================================="
echo "PUBLIC CLUSTER CONFIGURATION"
echo "=================================================================="
echo "# Use this configuration for public clusters (publish: External)"
echo "# Both public and private subnets are needed for public clusters"
echo "platform:"
echo "  aws:"
echo "    region: ${REGION}"
echo "    vpc:"
echo "      subnets:"

# Public cluster configuration - both public and private subnets
if [ -n "${PUBLIC_SUBNET_IDS}" ] && [ -n "${PRIVATE_SUBNET_IDS}" ]; then
    PUBLIC_SUBNET_ARRAY=($(echo "${PUBLIC_SUBNET_IDS}" | tr ',' ' '))
    PRIVATE_SUBNET_ARRAY=($(echo "${PRIVATE_SUBNET_IDS}" | tr ',' ' '))
    
    # Print public subnets with zones
    echo "      # Public subnets for each availability zone"
    for i in "${!PUBLIC_SUBNET_ARRAY[@]}"; do
        if [ $i -lt ${#ZONES[@]} ]; then
            echo "      - id: ${PUBLIC_SUBNET_ARRAY[$i]}"
            echo "        zone: ${ZONES[$i]}"
        fi
    done
    
    # Print private subnets with zones
    echo "      # Private subnets for each availability zone"
    for i in "${!PRIVATE_SUBNET_ARRAY[@]}"; do
        if [ $i -lt ${#ZONES[@]} ]; then
            echo "      - id: ${PRIVATE_SUBNET_ARRAY[$i]}"
            echo "        zone: ${ZONES[$i]}"
        fi
    done
    
    echo ""
    echo "publish: External"
    echo ""
    echo "Note: Public clusters use both public and private subnets."
    echo "      Control plane nodes in private subnets, workers can be in public subnets."
else
    echo "# ERROR: Public clusters require both public and private subnets."
    echo "# Please ensure your VPC has both subnet types configured."
fi

echo ""
echo "=================================================================="
echo "CONFIGURATION SUMMARY"
echo "=================================================================="
echo "Choose the appropriate configuration based on your cluster type:"
echo ""
echo "🔒 PRIVATE CLUSTER:"
echo "   - Use the first configuration above"
echo "   - Only private subnets in install-config.yaml"
echo "   - Set publish: Internal"
echo "   - Higher security, requires bastion host or VPN"
echo ""
echo "🌐 PUBLIC CLUSTER:"
echo "   - Use the second configuration above"
echo "   - Both public and private subnets in install-config.yaml"
echo "   - Set publish: External"
echo "   - Easier deployment, direct internet access"
echo ""
echo "Note: Both configurations use the same VPC infrastructure."
echo "      The difference is in which subnets are referenced in install-config.yaml."
