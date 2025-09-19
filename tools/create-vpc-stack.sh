#!/bin/bash

# Default values
AWS_PROFILE=""
REGION="us-east-1"
STACK_NAME="my-private-cluster-vpc"
VPC_CIDR="10.0.0.0/16"
AZ_COUNT=2
TEMPLATE_FILE="vpc-template-private-cluster.yaml"

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -p, --profile <profile>      AWS CLI profile to use. Leave empty to use the default profile."
    echo "  -r, --region <region>        The AWS region where the stack will be created. (Default: ${REGION})"
    echo "  -s, --stack-name <name>      The name of the CloudFormation stack. (Default: ${STACK_NAME})"
    echo "  -c, --vpc-cidr <cidr>        The CIDR block for the VPC. (Default: ${VPC_CIDR})"
    echo "  -a, --az-count <count>       The number of Availability Zones to use (1, 2, or 3). (Default: ${AZ_COUNT})"
    echo "  -t, --template-file <file>   The path to the CloudFormation template file. (Default: ${TEMPLATE_FILE})"
    echo "  -h, --help                   Show this help message."
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

# Construct the AWS CLI command
CMD="aws cloudformation deploy \
  --region ${REGION} \
  --stack-name ${STACK_NAME} \
  --template-file ${TEMPLATE_FILE} \
  --parameter-overrides \
    VpcCidr=${VPC_CIDR} \
    AvailabilityZoneCount=${AZ_COUNT} \
  --capabilities CAPABILITY_IAM"

if [ -n "${AWS_PROFILE}" ]; then
  CMD="${CMD} --profile ${AWS_PROFILE}"
fi

echo "Executing command:"
echo "${CMD}"
echo ""

# Execute the command
eval "${CMD}"

# Check if the command was successful
if [ $? -eq 0 ]; then
    echo ""
    echo "VPC stack created successfully!"
    echo ""
    echo "Getting VPC outputs..."
    
    # Get VPC outputs
    aws cloudformation describe-stacks \
        --region ${REGION} \
        --stack-name ${STACK_NAME} \
        --query 'Stacks[0].Outputs' \
        --output table
    
    echo ""
    echo "To get subnet IDs for install-config.yaml, run:"
    echo "  ../tools/get-vpc-outputs.sh ${STACK_NAME} ${REGION}"
fi
