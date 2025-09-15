#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# --- Configuration ---
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <installer-working-directory> [aws-region]"
  echo "Example: $0 ./work1 us-east-2"
  echo "Example: $0 ./work1  # uses AWS_REGION env var or defaults to us-east-1"
  echo "Example: $0 /Users/weli/works/oc-swarm/openshift-progress/works us-west-2"
  exit 1
fi

INSTALLER_DIR=$1
AWS_REGION=${2:-${AWS_REGION:-"us-east-1"}}

# --- Validation ---
if [ ! -d "${INSTALLER_DIR}" ]; then
  echo "Error: Installer working directory '${INSTALLER_DIR}' does not exist."
  exit 1
fi

METADATA_FILE="${INSTALLER_DIR}/metadata.json"
if [ ! -f "${METADATA_FILE}" ]; then
  echo "Error: metadata.json not found in '${INSTALLER_DIR}'."
  echo "Please check the path and ensure metadata.json exists."
  exit 1
fi

# --- Extract cluster information ---
echo "=== Cluster Destroy Status Check ==="
echo "Installer directory: ${INSTALLER_DIR}"
echo "AWS Region: ${AWS_REGION}"
echo "Metadata file: ${METADATA_FILE}"
echo ""

# Extract cluster information from metadata.json
CLUSTER_NAME=$(jq -r '.clusterName' "${METADATA_FILE}")
CLUSTER_ID=$(jq -r '.clusterID' "${METADATA_FILE}")
INFRA_ID=$(jq -r '.infraID' "${METADATA_FILE}")
CLUSTER_DOMAIN=$(jq -r '.aws.clusterDomain // empty' "${METADATA_FILE}")

echo "Cluster Information:"
echo "- Cluster Name: ${CLUSTER_NAME}"
echo "- Cluster ID: ${CLUSTER_ID}"
echo "- Infra ID: ${INFRA_ID}"
if [ -n "${CLUSTER_DOMAIN}" ]; then
  echo "- Cluster Domain: ${CLUSTER_DOMAIN}"
fi
echo ""

# --- Check AWS Resource Tags ---
echo "=== Checking AWS Resource Tags ==="
echo "Searching for resources with cluster tag 'kubernetes.io/cluster/${INFRA_ID}'..."

# Check for any resources with the cluster tag
TAGGED_RESOURCES=$(aws --region "${AWS_REGION}" resourcegroupstaggingapi get-tag-keys 2>/dev/null | grep "kubernetes.io/cluster/${INFRA_ID}" || true)

if [ -n "${TAGGED_RESOURCES}" ]; then
  echo "⚠️  WARNING: Found resources with cluster tag:"
  echo "${TAGGED_RESOURCES}"
  echo ""
  
  # Get detailed resource information
  echo "Getting detailed resource information..."
  RESOURCE_DETAILS=$(aws --region "${AWS_REGION}" resourcegroupstaggingapi get-resources \
    --tag-filters "Key=kubernetes.io/cluster/${INFRA_ID},Values=owned" 2>/dev/null || echo "[]")
  
  if [ "${RESOURCE_DETAILS}" != "[]" ] && [ -n "${RESOURCE_DETAILS}" ]; then
    echo "Resources still tagged with cluster ownership:"
    echo "${RESOURCE_DETAILS}" | jq -r '.ResourceTagMappingList[] | "- \(.ResourceARN) (Tags: \(.Tags | length))"' 2>/dev/null || echo "${RESOURCE_DETAILS}"
    echo ""
    
    # Check resource states
    echo "Checking resource states..."
    echo "${RESOURCE_DETAILS}" | jq -r '.ResourceTagMappingList[].ResourceARN' 2>/dev/null | while read -r resource_arn; do
      if [ -n "${resource_arn}" ]; then
        # Extract resource type and name from ARN
        resource_type=$(echo "${resource_arn}" | cut -d':' -f6 | cut -d'/' -f1)
        resource_name=$(echo "${resource_arn}" | cut -d':' -f6 | cut -d'/' -f2-)
        
        case "${resource_type}" in
          "ec2")
            echo "Checking EC2 instance: ${resource_name}"
            instance_state=$(aws --region "${AWS_REGION}" ec2 describe-instances \
              --instance-ids "${resource_name}" \
              --query 'Reservations[0].Instances[0].State.Name' \
              --output text 2>/dev/null || echo "NOT_FOUND")
            echo "  State: ${instance_state}"
            ;;
          "elasticloadbalancing")
            echo "Checking Load Balancer: ${resource_name}"
            lb_state=$(aws --region "${AWS_REGION}" elbv2 describe-load-balancers \
              --load-balancer-arns "${resource_arn}" \
              --query 'LoadBalancers[0].State.Code' \
              --output text 2>/dev/null || echo "NOT_FOUND")
            echo "  State: ${lb_state}"
            ;;
          "route53")
            echo "Checking Route53 hosted zone: ${resource_name}"
            zone_state=$(aws --region "${AWS_REGION}" route53 get-hosted-zone \
              --id "${resource_name}" \
              --query 'HostedZone.Id' \
              --output text 2>/dev/null || echo "NOT_FOUND")
            echo "  State: ${zone_state}"
            ;;
          *)
            echo "Resource type ${resource_type} detected: ${resource_name}"
            ;;
        esac
      fi
    done
  else
    echo "✅ No resources found with cluster ownership tags."
  fi
else
  echo "✅ No resources found with cluster tag 'kubernetes.io/cluster/${INFRA_ID}'."
fi

echo ""

# --- Check for orphaned resources ---
echo "=== Checking for Orphaned Resources ==="

# Check CloudFormation stacks
echo "Checking CloudFormation stacks..."
CF_STACKS=$(aws --region "${AWS_REGION}" cloudformation list-stacks \
  --query "StackSummaries[?contains(StackName, \`${INFRA_ID}\`) && StackStatus != 'DELETE_COMPLETE'].[StackName,StackStatus]" \
  --output text 2>/dev/null || echo "")

if [ -n "${CF_STACKS}" ]; then
  echo "⚠️  Found CloudFormation stacks:"
  echo "${CF_STACKS}" | while read -r stack_name stack_status; do
    if [ -n "${stack_name}" ]; then
      echo "- ${stack_name}: ${stack_status}"
    fi
  done
else
  echo "✅ No CloudFormation stacks found with infra ID '${INFRA_ID}'."
fi

# Check VPCs
echo ""
echo "Checking VPCs..."
VPC_ID=$(aws --region "${AWS_REGION}" ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${INFRA_ID}-vpc" \
  --query 'Vpcs[0].VpcId' \
  --output text 2>/dev/null || echo "None")

if [ "${VPC_ID}" != "None" ] && [ "${VPC_ID}" != "null" ]; then
  echo "⚠️  Found VPC: ${VPC_ID}"
  VPC_STATE=$(aws --region "${AWS_REGION}" ec2 describe-vpcs \
    --vpc-ids "${VPC_ID}" \
    --query 'Vpcs[0].State' \
    --output text 2>/dev/null || echo "UNKNOWN")
  echo "  State: ${VPC_STATE}"
else
  echo "✅ No VPC found with name '${INFRA_ID}-vpc'."
fi

# Check Route53 records
if [ -n "${CLUSTER_DOMAIN}" ]; then
  echo ""
  echo "Checking Route53 records for domain '${CLUSTER_DOMAIN}'..."
  HOSTED_ZONE_ID=$(aws --region "${AWS_REGION}" route53 list-hosted-zones \
    --query "HostedZones[?Name==\`${CLUSTER_DOMAIN}.\`].Id" \
    --output text 2>/dev/null || echo "")
  
  if [ -n "${HOSTED_ZONE_ID}" ]; then
    echo "⚠️  Found hosted zone: ${HOSTED_ZONE_ID}"
    RECORDS=$(aws --region "${AWS_REGION}" route53 list-resource-record-sets \
      --hosted-zone-id "${HOSTED_ZONE_ID}" \
      --query 'ResourceRecordSets[?Type==`A` || Type==`CNAME`].[Name,Type]' \
      --output text 2>/dev/null || echo "")
    
    if [ -n "${RECORDS}" ]; then
      echo "  DNS Records:"
      echo "${RECORDS}" | while read -r record_name record_type; do
        if [ -n "${record_name}" ]; then
          echo "    - ${record_name} (${record_type})"
        fi
      done
    else
      echo "  No A or CNAME records found."
    fi
  else
    echo "✅ No hosted zone found for domain '${CLUSTER_DOMAIN}'."
  fi
fi

echo ""

# --- Summary ---
echo "=== Summary ==="
echo "Cluster destroy status check completed."
echo ""
echo "If you see any warnings above, please:"
echo "1. Wait a few minutes and run this script again (some resources may be in 'deleting' state)"
echo "2. Check the AWS Management Console to verify resource states"
echo "3. If resources are not in 'deleted' or 'terminated' state, this may indicate a bug"
echo ""
echo "Expected behavior: All resources should be deleted or in 'deleted'/'terminated' state."
