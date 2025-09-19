#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail
#set -x

# --- Configuration ---
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <vpc-id> <public-subnet-id> <cluster-name> [path-to-ignition-file]"
  echo "Example (default SSH key): $0 vpc-0123... subnet-fedcba... my-cluster"
  echo "Example (custom ignition): $0 vpc-0123... subnet-fedcba... my-cluster ./my-cluster.ign"
  exit 1
fi

VPC_ID=$1
PUBLIC_SUBNET_ID=$2
CLUSTER_NAME=$3
BASTION_IGNITION_FILE=${4:-""}
REGION=${AWS_REGION:-"us-east-1"}
DEFAULT_SSH_KEY_PATH="/Users/weli/.ssh/id_rsa.pub"

# --- Script Logic ---
BASTION_STACK_NAME="${CLUSTER_NAME}-bastion"
S3_BUCKET_NAME="${CLUSTER_NAME}-bastion-ign-$(date +%s)"
BASTION_CF_TPL_FILE="./${CLUSTER_NAME}-bastion-cf-tpl.yaml"
TEMP_IGNITION_FILE=$(mktemp)
# Clean up temporary files on exit
trap 'rm -f "${TEMP_IGNITION_FILE}" "${BASTION_CF_TPL_FILE}"' EXIT

# --- Ignition File Handling ---
if [[ -z "${BASTION_IGNITION_FILE}" ]]; then
  echo "No ignition file provided. Generating a temporary one with default SSH key."
  if [[ ! -f "${DEFAULT_SSH_KEY_PATH}" ]]; then
    echo "Error: Default SSH key not found at ${DEFAULT_SSH_KEY_PATH}"
    exit 1
  fi
  SSH_KEY_CONTENT=$(cat "${DEFAULT_SSH_KEY_PATH}")
  jq -n \
    --arg ssh_key "$SSH_KEY_CONTENT" \
    '{"ignition": {"version": "3.2.0"}, "passwd": {"users": [{"name": "core", "sshAuthorizedKeys": [$ssh_key]}]}}' > "${TEMP_IGNITION_FILE}"
  BASTION_IGNITION_FILE=${TEMP_IGNITION_FILE}
fi

# --- Pre-flight Checks ---
if ! command -v jq &> /dev/null || ! command -v aws &> /dev/null || ! command -v openshift-install &> /dev/null; then
    echo "Error: jq, aws cli, or openshift-install is not installed or not in your PATH." && exit 1
fi

# --- AMI Discovery ---
echo "Fetching RHCOS AMI using openshift-install..."
AMI_ID=$(openshift-install coreos print-stream-json | jq -r --arg region "${REGION}" '.architectures.x86_64.images.aws.regions[$region].image')
if [[ -z "${AMI_ID}" ]]; then
  echo "ERROR: Bastion host AMI was NOT found in region ${REGION}." && exit 1
fi
echo "Found RHCOS AMI ID: ${AMI_ID}"

# --- S3 and Ignition Upload ---
IGNITION_S3_LOCATION="s3://${S3_BUCKET_NAME}/bastion.ign"
echo "Creating temporary S3 bucket: ${S3_BUCKET_NAME}"
aws --region ${REGION} s3 mb "s3://${S3_BUCKET_NAME}"
echo "Uploading ignition file to ${IGNITION_S3_LOCATION}"
aws --region ${REGION} s3 cp "${BASTION_IGNITION_FILE}" "${IGNITION_S3_LOCATION}"

# --- CloudFormation Template Generation ---
BASTION_INSTANCE_TYPE="t2.medium"
if [[ "${REGION}" == "us-gov-east-1" ]]; then
    BASTION_INSTANCE_TYPE="t3a.medium"
fi

cat > ${BASTION_CF_TPL_FILE} << EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Template for Bastion Host Launch
Parameters:
  VpcId: {Type: AWS::EC2::VPC::Id}
  AmiId: {Type: AWS::EC2::Image::Id}
  PublicSubnet: {Type: AWS::EC2::Subnet::Id}
  BastionHostInstanceType: {Type: String}
  BastionIgnitionLocation: {Type: String}
  ClusterName: {Type: String}
Resources:
  BastionIamRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement: [{"Effect": "Allow", "Principal": {"Service": ["ec2.amazonaws.com"]}, "Action": ["sts:AssumeRole"]}]
      Path: "/"
      Policies:
      - PolicyName: !Join ["-", [!Ref ClusterName, "bastion-policy"]]
        PolicyDocument:
          Version: "2012-10-17"
          Statement:
          - {Effect: "Allow", Action: "s3:GetObject", Resource: !Join ["", ["arn:aws:s3:::", !Ref ClusterName, "-bastion-ign-*/*"]]}
  BastionInstanceProfile:
    Type: "AWS::IAM::InstanceProfile"
    Properties: {Path: "/", Roles: [!Ref "BastionIamRole"]}
  BastionSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Bastion Host Security Group
      SecurityGroupIngress:
      - {IpProtocol: tcp, FromPort: 22, ToPort: 22, CidrIp: 0.0.0.0/0}
      VpcId: !Ref VpcId
  BastionInstance:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: !Ref AmiId
      IamInstanceProfile: !Ref BastionInstanceProfile
      InstanceType: !Ref BastionHostInstanceType
      NetworkInterfaces:
      - {AssociatePublicIpAddress: "True", DeviceIndex: "0", GroupSet: [!GetAtt BastionSecurityGroup.GroupId], SubnetId: !Ref "PublicSubnet"}
      Tags:
      - {Key: Name, Value: !Join ["-", [!Ref ClusterName, "bastion"]]}
      UserData:
        Fn::Base64:
          !Sub
            - '{"ignition":{"config":{"replace":{"source":"\${IgnitionLocation}"}},"version":"3.2.0"}}'
            - IgnitionLocation: !Ref BastionIgnitionLocation
Outputs:
  PublicIp: {Description: The bastion host Public IP, Value: !GetAtt BastionInstance.PublicIp}
  BastionSecurityGroupId: {Description: Bastion Host Security Group ID, Value: !GetAtt BastionSecurityGroup.GroupId}
EOF

# --- Create Bastion Stack ---
echo "Creating CloudFormation stack for bastion host..."
aws --region ${REGION} cloudformation create-stack --stack-name ${BASTION_STACK_NAME} \
    --template-body file://${BASTION_CF_TPL_FILE} \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
        ParameterKey=BastionHostInstanceType,ParameterValue="${BASTION_INSTANCE_TYPE}" \
        ParameterKey=PublicSubnet,ParameterValue="${PUBLIC_SUBNET_ID}" \
        ParameterKey=AmiId,ParameterValue="${AMI_ID}" \
        ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}" \
        ParameterKey=BastionIgnitionLocation,ParameterValue="${IGNITION_S3_LOCATION}"

echo "Waiting for stack ${BASTION_STACK_NAME} to be created..."
aws --region "${REGION}" cloudformation wait stack-create-complete --stack-name "${BASTION_STACK_NAME}"
echo "Bastion stack created successfully."

# --- Final Output and Cleanup ---
BASTION_PUBLIC_IP="$(aws --region "${REGION}" cloudformation describe-stacks --stack-name "${BASTION_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey == `PublicIp`].OutputValue' --output text)"

echo "Cleaning up temporary S3 bucket..."
aws --region ${REGION} s3 rb "s3://${S3_BUCKET_NAME}" --force

echo "--- Bastion Host Details ---"
echo "Public IP: ${BASTION_PUBLIC_IP}"
echo "SSH User: core"
echo "SSH Command: ssh core@${BASTION_PUBLIC_IP}"
echo "--------------------------"
echo ""
echo "Note: After cluster installation is complete, run configure-bastion-security.sh to enable API access"
