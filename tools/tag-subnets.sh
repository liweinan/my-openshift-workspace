#!/bin/bash

# Check for required arguments
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 <stack-name> <cluster-name> [aws-region]"
  echo "Please provide the CloudFormation stack name and the desired OpenShift cluster name."
  echo "AWS region is optional (default: us-east-1)."
  exit 1
fi

STACK_NAME=$1
CLUSTER_NAME=$2
REGION="${3:-us-east-1}"

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "Error: jq is not installed. Please install jq to run this script."
    exit 1
fi

echo "Querying stack '${STACK_NAME}' in region '${REGION}' for subnet outputs..."

# Get stack outputs
OUTPUTS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query "Stacks[0].Outputs" 2>/dev/null)

if [ $? -ne 0 ]; then
  echo "Error: Failed to describe stack '${STACK_NAME}'."
  exit 1
fi

# Get public and private subnet IDs from outputs
PUBLIC_SUBNET_IDS=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="PublicSubnetIds") | .OutputValue')
PRIVATE_SUBNET_IDS=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="PrivateSubnetIds") | .OutputValue')

if [ -z "${PUBLIC_SUBNET_IDS}" ] && [ -z "${PRIVATE_SUBNET_IDS}" ]; then
    echo "Error: No public or private subnets found in the outputs for stack '${STACK_NAME}'."
    exit 1
fi

# --- Tagging Logic ---
CLUSTER_TAG_KEY="kubernetes.io/cluster/${CLUSTER_NAME}"
CLUSTER_TAG_VALUE="shared"
PUBLIC_ROLE_TAG_KEY="kubernetes.io/role/elb"
PRIVATE_ROLE_TAG_KEY="kubernetes.io/role/internal-elb"
ROLE_TAG_VALUE="1"

# Additional tags for better resource management
ENVIRONMENT_TAG_KEY="Environment"
ENVIRONMENT_TAG_VALUE="openshift"
PROJECT_TAG_KEY="Project"
PROJECT_TAG_VALUE="${CLUSTER_NAME}"

echo "Starting subnet tagging for cluster: ${CLUSTER_NAME}"
echo "Region: ${REGION}"
echo ""

# Tag Public Subnets
if [ -n "${PUBLIC_SUBNET_IDS}" ]; then
    echo "Tagging Public Subnets..."
    for SUBNET_ID in $(echo "${PUBLIC_SUBNET_IDS}" | tr ',' ' '); do
        echo "  - Tagging ${SUBNET_ID} with public role tags"
        
        # Create tags for public subnet
        aws ec2 create-tags --region "${REGION}" --resources "${SUBNET_ID}" \
            --tags \
            "Key=${CLUSTER_TAG_KEY},Value=${CLUSTER_TAG_VALUE}" \
            "Key=${PUBLIC_ROLE_TAG_KEY},Value=${ROLE_TAG_VALUE}" \
            "Key=${ENVIRONMENT_TAG_KEY},Value=${ENVIRONMENT_TAG_VALUE}" \
            "Key=${PROJECT_TAG_KEY},Value=${PROJECT_TAG_VALUE}"
            
        if [ $? -eq 0 ]; then
            echo "    ✓ Successfully tagged ${SUBNET_ID}"
        else
            echo "    ✗ Error: Failed to tag subnet ${SUBNET_ID}"
        fi
    done
    echo ""
fi

# Tag Private Subnets
if [ -n "${PRIVATE_SUBNET_IDS}" ]; then
    echo "Tagging Private Subnets..."
    for SUBNET_ID in $(echo "${PRIVATE_SUBNET_IDS}" | tr ',' ' '); do
        echo "  - Tagging ${SUBNET_ID} with private role tags"
        
        # Create tags for private subnet
        aws ec2 create-tags --region "${REGION}" --resources "${SUBNET_ID}" \
            --tags \
            "Key=${CLUSTER_TAG_KEY},Value=${CLUSTER_TAG_VALUE}" \
            "Key=${PRIVATE_ROLE_TAG_KEY},Value=${ROLE_TAG_VALUE}" \
            "Key=${ENVIRONMENT_TAG_KEY},Value=${ENVIRONMENT_TAG_VALUE}" \
            "Key=${PROJECT_TAG_KEY},Value=${PROJECT_TAG_VALUE}"
            
        if [ $? -eq 0 ]; then
            echo "    ✓ Successfully tagged ${SUBNET_ID}"
        else
            echo "    ✗ Error: Failed to tag subnet ${SUBNET_ID}"
        fi
    done
    echo ""
fi

echo "Subnet tagging complete."
echo ""
echo "Applied tags:"
echo "  - ${CLUSTER_TAG_KEY}=${CLUSTER_TAG_VALUE}"
echo "  - ${ENVIRONMENT_TAG_KEY}=${ENVIRONMENT_TAG_VALUE}"
echo "  - ${PROJECT_TAG_KEY}=${PROJECT_TAG_VALUE}"
echo "  - Public subnets: ${PUBLIC_ROLE_TAG_KEY}=${ROLE_TAG_VALUE}"
echo "  - Private subnets: ${PRIVATE_ROLE_TAG_KEY}=${ROLE_TAG_VALUE}"
echo ""
echo "Note: These tags are required for OpenShift to properly manage load balancers and networking."
