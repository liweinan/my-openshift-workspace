#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# --- Configuration ---
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <stack-name-substring>"
  echo "Example: $0 weli"
  exit 1
fi

SEARCH_TERM=$1
REGION=${AWS_REGION:-"us-east-1"}

# --- Script Logic ---
echo "Searching for CloudFormation stacks containing '${SEARCH_TERM}' in region ${REGION}..."

STACK_NAMES=$(aws --region "${REGION}" cloudformation list-stacks \
  --query "StackSummaries[?contains(StackName, \`${SEARCH_TERM}\`)].[StackName]" \
  --output text)

if [[ -z "${STACK_NAMES}" ]]; then
  echo "No stacks found with the name containing '${SEARCH_TERM}'."
  exit 0
fi

echo "The following stacks will be DELETED:"
echo "${STACK_NAMES}"
echo ""
read -p "Are you sure you want to delete these stacks? (yes/no) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

for STACK_NAME in ${STACK_NAMES}; do
  echo "Issuing delete command for stack: ${STACK_NAME}"
  aws --region "${REGION}" cloudformation delete-stack --stack-name "${STACK_NAME}"
done

wait
echo "All delete commands have been sent."
