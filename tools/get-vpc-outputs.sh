#!/bin/bash

# Check parameters
if [ $# -lt 1 ]; then
    echo "Usage: $0 <STACK_NAME>"
    echo "Example: $0 my-vpc-stack"
    echo ""
    echo "Note: This script outputs configurations for both private and public clusters, please choose according to your needs"
    exit 1
fi

STACK_NAME=$1
REGION=${2:-"us-east-1"}

echo "Querying CloudFormation stack: $STACK_NAME"
echo "Region: $REGION"
echo ""

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo "Error: Stack '$STACK_NAME' does not exist or cannot be accessed"
    exit 1
fi

# Get VPC ID
VPC_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
    --output text)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
    echo "Error: Unable to get VPC ID"
    exit 1
fi

echo "VPC ID: $VPC_ID"
echo ""

# Get availability zones
ZONES=($(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`AvailabilityZones`].OutputValue' \
    --output text | tr ',' ' '))

if [ ${#ZONES[@]} -eq 0 ]; then
    echo "Error: Unable to get availability zone information"
    exit 1
fi

echo "Availability zones: ${ZONES[*]}"
echo ""

# Get public subnets
PUBLIC_SUBNET_IDS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
    --output text)

if [ -z "$PUBLIC_SUBNET_IDS" ] || [ "$PUBLIC_SUBNET_IDS" = "None" ]; then
    echo "Error: Unable to get public subnet ID"
    exit 1
fi

# Get private subnets
PRIVATE_SUBNET_IDS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnetIds`].OutputValue' \
    --output text)

if [ -z "$PRIVATE_SUBNET_IDS" ] || [ "$PRIVATE_SUBNET_IDS" = "None" ]; then
    echo "Error: Unable to get private subnet ID"
    exit 1
fi

# Convert to arrays
PUBLIC_SUBNET_ARRAY=($(echo "$PUBLIC_SUBNET_IDS" | tr ',' ' '))
PRIVATE_SUBNET_ARRAY=($(echo "$PRIVATE_SUBNET_IDS" | tr ',' ' '))

echo "Number of public subnets: ${#PUBLIC_SUBNET_ARRAY[@]}"
echo "Number of private subnets: ${#PRIVATE_SUBNET_ARRAY[@]}"
echo ""

echo "=========================================="
echo "Private cluster configuration (publish: Internal)"
echo "=========================================="
echo "platform:"
echo "  aws:"
echo "    region: $REGION"
echo "    vpc:"
echo "      subnets:"
for i in "${!PRIVATE_SUBNET_ARRAY[@]}"; do
    echo "      - id: ${PRIVATE_SUBNET_ARRAY[$i]}"
done
echo "publish: Internal"
echo ""
echo "Note: Private clusters only use private subnets and access the internet via NAT Gateway"
echo ""

echo "=========================================="
echo "Public cluster configuration (publish: External)"
echo "=========================================="
echo "platform:"
echo "  aws:"
echo "    region: $REGION"
echo "    vpc:"
echo "      subnets:"
for i in "${!PUBLIC_SUBNET_ARRAY[@]}"; do
    echo "      - id: ${PUBLIC_SUBNET_ARRAY[$i]}"
done
for i in "${!PRIVATE_SUBNET_ARRAY[@]}"; do
    echo "      - id: ${PRIVATE_SUBNET_ARRAY[$i]}"
done
echo "publish: External"
echo ""
echo "Note: Public clusters use a combination of public + private subnets"
echo ""

echo "=========================================="
echo "Usage instructions:"
echo "1. Copy the above configuration to your install-config.yaml file"
echo "2. Choose publish: Internal or External according to your needs"
echo "3. Ensure pull-secret is properly configured"
echo "=========================================="
