#!/bin/bash
set -x

# 设置终端编码
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 设置变量
IMAGE_ID="ami-0258229bf3cd8af20"
INSTANCE_TYPE="m5.xlarge"
KEY_NAME="weli-rhel-key"
SECURITY_GROUP_ID="sg-0faf59d58a5daebe4"
SUBNET_ID="subnet-0d863bd5fb43d9137"
REGION="us-east-1"
INSTANCE_NAME="rhel-8.1-instance"

printf "正在启动EC2实例...\n"

aws ec2 run-instances \
  --image-id "${IMAGE_ID}" \
  --instance-type "${INSTANCE_TYPE}" \
  --key-name "${KEY_NAME}" \
  --security-group-ids "${SECURITY_GROUP_ID}" \
  --subnet-id "${SUBNET_ID}" \
  --region "${REGION}" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
  --output table

if [ $? -eq 0 ]; then
    printf "实例启动命令执行成功\n"
    printf "请等待几分钟让实例完全启动，然后使用以下命令查看实例状态：\n"
    printf "aws ec2 describe-instances --filters \"Name=tag:Name,Values=${INSTANCE_NAME}\" --region ${REGION} --output table\n"
else
    printf "实例启动失败\n"
    exit 1
fi
