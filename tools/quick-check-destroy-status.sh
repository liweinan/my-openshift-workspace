#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# --- Configuration ---
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <installer-working-directory> [aws-region]"
  echo "Example: $0 ./work1 us-east-2"
  exit 1
fi

INSTALLER_DIR=$1
AWS_REGION=${2:-${AWS_REGION:-"us-east-1"}}

# --- Extract infraID ---
METADATA_FILE="${INSTALLER_DIR}/metadata.json"
if [ ! -f "${METADATA_FILE}" ]; then
  echo "Error: metadata.json not found in '${INSTALLER_DIR}'."
  exit 1
fi

INFRA_ID=$(jq -r '.infraID' "${METADATA_FILE}")
echo "Checking destroy status for infraID: ${INFRA_ID}"
echo "Region: ${AWS_REGION}"
echo ""

# --- Quick check for tagged resources ---
echo "Checking for resources with cluster tag..."
TAGGED_RESOURCES=$(aws --region "${AWS_REGION}" resourcegroupstaggingapi get-tag-keys 2>/dev/null | grep "kubernetes.io/cluster/${INFRA_ID}" || true)

if [ -n "${TAGGED_RESOURCES}" ]; then
  echo "❌ Found resources with cluster tag:"
  echo "${TAGGED_RESOURCES}"
  echo ""
  
  # Get resource details
  RESOURCE_DETAILS=$(aws --region "${AWS_REGION}" resourcegroupstaggingapi get-resources \
    --tag-filters "Key=kubernetes.io/cluster/${INFRA_ID},Values=owned" 2>/dev/null || echo "[]")
  
  if [ "${RESOURCE_DETAILS}" != "[]" ] && [ -n "${RESOURCE_DETAILS}" ]; then
    echo "Resources still tagged:"
    echo "${RESOURCE_DETAILS}" | jq -r '.ResourceTagMappingList[] | "- \(.ResourceARN)"' 2>/dev/null || echo "${RESOURCE_DETAILS}"
  fi
else
  echo "✅ No resources found with cluster tag."
fi

echo ""

# --- Check CloudFormation stacks ---
echo "Checking CloudFormation stacks..."
CF_STACKS=$(aws --region "${AWS_REGION}" cloudformation list-stacks \
  --query "StackSummaries[?contains(StackName, \`${INFRA_ID}\`) && StackStatus != 'DELETE_COMPLETE'].[StackName,StackStatus]" \
  --output text 2>/dev/null || echo "")

if [ -n "${CF_STACKS}" ]; then
  echo "❌ Found CloudFormation stacks:"
  echo "${CF_STACKS}" | while read -r stack_name stack_status; do
    if [ -n "${stack_name}" ]; then
      echo "- ${stack_name}: ${stack_status}"
    fi
  done
else
  echo "✅ No CloudFormation stacks found."
fi

echo ""
echo "=== Quick Check Complete ==="
