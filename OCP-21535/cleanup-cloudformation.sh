#!/bin/bash

# 设置终端编码
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 设置变量
STACK_NAME="rhel-infrastructure"
REGION="us-east-1"

printf "CloudFormation Stack Cleanup\n"
printf "============================\n\n"

# 检查堆栈是否存在
printf "1. Checking if stack exists...\n"
if ! aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    printf "Stack ${STACK_NAME} does not exist\n"
    exit 0
fi

# 显示堆栈信息
printf "Stack found. Current status:\n"
aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].{StackName:StackName,StackStatus:StackStatus,CreationTime:CreationTime}' \
    --output table

# 确认删除
printf "\n2. Confirming deletion...\n"
read -p "Are you sure you want to delete stack '${STACK_NAME}'? This will remove ALL resources (y/n): " -n 1 -r
printf "\n"

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    printf "Deletion cancelled\n"
    exit 0
fi

# 删除堆栈
printf "3. Deleting stack...\n"
aws cloudformation delete-stack --stack-name "${STACK_NAME}" --region "${REGION}"

if [ $? -eq 0 ]; then
    printf "Stack deletion initiated. Waiting for completion...\n"
    aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" --region "${REGION}"
    
    if [ $? -eq 0 ]; then
        printf "Stack deletion completed successfully!\n"
        
        # 清理本地文件
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
