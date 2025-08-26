#!/bin/bash

# 设置变量
REGION="us-east-1"
KEY_NAME="weli-rhel-key"
SECURITY_GROUP_NAME="weli-rhel-ssh-sg"
VPC_NAME="weli-vpc"
INSTANCE_NAME="rhel-8.1-instance"

echo "Manual AWS Resource Cleanup"
echo "=========================="
echo ""
echo "This script will delete the following resources:"
echo "- EC2 Instance: $INSTANCE_NAME"
echo "- Security Group: $SECURITY_GROUP_NAME"
echo "- Key Pair: $KEY_NAME"
echo "- VPC and all associated resources"
echo ""

# 确认删除
read -p "Are you sure you want to delete these resources? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo "Starting cleanup process..."
echo ""

# 1. 删除EC2实例
echo "1. Deleting EC2 instance..."
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text \
  --region "$REGION")

if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
    echo "Found instance: $INSTANCE_ID"
    
    # 检查实例状态
    INSTANCE_STATE=$(aws ec2 describe-instances \
      --instance-ids "$INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].State.Name' \
      --output text \
      --region "$REGION")
    
    if [ "$INSTANCE_STATE" != "terminated" ]; then
        echo "Terminating instance..."
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
        
        if [ $? -eq 0 ]; then
            echo "Waiting for instance termination..."
            aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$REGION"
            echo "Instance terminated successfully"
        else
            echo "Failed to terminate instance"
        fi
    else
        echo "Instance already terminated"
    fi
else
    echo "No instance found with name: $INSTANCE_NAME"
fi

# 2. 删除安全组
echo ""
echo "2. Deleting security group..."
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
  --query 'SecurityGroups[0].GroupId' \
  --output text \
  --region "$REGION")

if [ "$SECURITY_GROUP_ID" != "None" ] && [ -n "$SECURITY_GROUP_ID" ]; then
    echo "Found security group: $SECURITY_GROUP_ID"
    
    # 删除安全组规则
    echo "Removing security group rules..."
    aws ec2 revoke-security-group-ingress \
      --group-id "$SECURITY_GROUP_ID" \
      --protocol tcp \
      --port 22 \
      --cidr 0.0.0.0/0 \
      --region "$REGION" 2>/dev/null || true
    
    aws ec2 revoke-security-group-ingress \
      --group-id "$SECURITY_GROUP_ID" \
      --protocol tcp \
      --port 80 \
      --cidr 0.0.0.0/0 \
      --region "$REGION" 2>/dev/null || true
    
    aws ec2 revoke-security-group-ingress \
      --group-id "$SECURITY_GROUP_ID" \
      --protocol tcp \
      --port 443 \
      --cidr 0.0.0.0/0 \
      --region "$REGION" 2>/dev/null || true
    
    aws ec2 revoke-security-group-ingress \
      --group-id "$SECURITY_GROUP_ID" \
      --protocol icmp \
      --port -1 \
      --cidr 0.0.0.0/0 \
      --region "$REGION" 2>/dev/null || true
    
    # 删除安全组
    echo "Deleting security group..."
    aws ec2 delete-security-group --group-id "$SECURITY_GROUP_ID" --region "$REGION"
    
    if [ $? -eq 0 ]; then
        echo "Security group deleted successfully"
    else
        echo "Failed to delete security group"
    fi
else
    echo "No security group found with name: $SECURITY_GROUP_NAME"
fi

# 3. 删除密钥对
echo ""
echo "3. Deleting key pair..."
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo "Found key pair: $KEY_NAME"
    aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$REGION"
    
    if [ $? -eq 0 ]; then
        echo "Key pair deleted successfully"
        
        # 删除本地密钥文件
        if [ -f "$KEY_NAME.pem" ]; then
            rm -f "$KEY_NAME.pem"
            echo "Local key file removed: $KEY_NAME.pem"
        fi
    else
        echo "Failed to delete key pair"
    fi
else
    echo "No key pair found with name: $KEY_NAME"
fi

# 4. 删除VPC相关资源
echo ""
echo "4. Deleting VPC and associated resources..."
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=$VPC_NAME" \
  --query 'Vpcs[0].VpcId' \
  --output text \
  --region "$REGION")

if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
    echo "Found VPC: $VPC_ID"
    
    # 删除子网
    echo "Deleting subnets..."
    SUBNET_IDS=$(aws ec2 describe-subnets \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'Subnets[*].SubnetId' \
      --output text \
      --region "$REGION")
    
    for SUBNET_ID in $SUBNET_IDS; do
        if [ "$SUBNET_ID" != "None" ] && [ -n "$SUBNET_ID" ]; then
            echo "Deleting subnet: $SUBNET_ID"
            aws ec2 delete-subnet --subnet-id "$SUBNET_ID" --region "$REGION"
        fi
    done
    
    # 删除路由表（除了主路由表）
    echo "Deleting route tables..."
    ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
      --output text \
      --region "$REGION")
    
    for ROUTE_TABLE_ID in $ROUTE_TABLE_IDS; do
        if [ "$ROUTE_TABLE_ID" != "None" ] && [ -n "$ROUTE_TABLE_ID" ]; then
            echo "Deleting route table: $ROUTE_TABLE_ID"
            aws ec2 delete-route-table --route-table-id "$ROUTE_TABLE_ID" --region "$REGION"
        fi
    done
    
    # 删除互联网网关
    echo "Deleting internet gateway..."
    IGW_ID=$(aws ec2 describe-internet-gateways \
      --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
      --query 'InternetGateways[0].InternetGatewayId' \
      --output text \
      --region "$REGION")
    
    if [ "$IGW_ID" != "None" ] && [ -n "$IGW_ID" ]; then
        echo "Detaching internet gateway: $IGW_ID"
        aws ec2 detach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$REGION"
        
        echo "Deleting internet gateway: $IGW_ID"
        aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$REGION"
    fi
    
    # 删除VPC
    echo "Deleting VPC: $VPC_ID"
    aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION"
    
    if [ $? -eq 0 ]; then
        echo "VPC and all associated resources deleted successfully"
    else
        echo "Failed to delete VPC"
    fi
else
    echo "No VPC found with name: $VPC_NAME"
fi

echo ""
echo "Cleanup completed!"
echo "Note: Some resources may take a few minutes to be fully deleted."
