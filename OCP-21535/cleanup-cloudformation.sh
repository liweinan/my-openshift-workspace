#!/bin/bash

# Set terminal encoding
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Set variables
STACK_NAME="rhel-infrastructure"
REGION="us-east-1"

printf "CloudFormation Stack Cleanup\n"
printf "============================\n\n"

# Check if stack exists
printf "1. Checking if stack exists...\n"
if ! aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    printf "Stack ${STACK_NAME} does not exist\n"
    exit 0
fi

# Display stack info
printf "Stack found. Current status:\n"
aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].{StackName:StackName,StackStatus:StackStatus,CreationTime:CreationTime}' \
    --output table

# Confirm deletion
printf "\n2. Confirming deletion...\n"
read -p "Are you sure you want to delete stack '${STACK_NAME}'? This will remove ALL resources (y/n): " -n 1 -r
printf "\n"

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    printf "Deletion cancelled\n"
    exit 0
fi

# Delete stack
printf "3. Deleting stack...\n"
aws cloudformation delete-stack --stack-name "${STACK_NAME}" --region "${REGION}"

if [ $? -eq 0 ]; then
    printf "Stack deletion initiated. Waiting for completion...\n"
    aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" --region "${REGION}"
    
    if [ $? -eq 0 ]; then
        printf "Stack deletion completed successfully!\n"
        
        # Clean up local files
        printf "\n4. Cleaning up local files...\n"
        KEY_PAIR_NAME="weli-rhel-key"
        if [ -f "${KEY_PAIR_NAME}.pem" ]; then
            rm -f "${KEY_PAIR_NAME}.pem"
            printf "Removed key file: ${KEY_PAIR_NAME}.pem\n"
        fi
        
        printf "Cleanup completed!\n"
    else
        printf "Stack deletion failed or timed out\n"
        printf "You may need to manually delete the stack from AWS Console\n"
        exit 1
    fi
else
    printf "Failed to initiate stack deletion\n"
    exit 1
fi