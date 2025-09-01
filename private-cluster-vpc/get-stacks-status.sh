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
  --query "StackSummaries[?contains(StackName, \`${SEARCH_TERM}\`) && StackStatus != 'DELETE_COMPLETE'].[StackName]" \
  --output text)

if [[ -z "${STACK_NAMES}" ]]; then
  echo "No active stacks found with the name containing '${SEARCH_TERM}'."
  exit 0
fi

echo "Current status of matching stacks:"
echo "${STACK_NAMES}" | while read -r STACK_NAME; do
  if [ -n "${STACK_NAME}" ]; then
    STATUS=$(aws --region "${REGION}" cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "DELETED")
    echo "- ${STACK_NAME}: ${STATUS}"
  fi
done

echo ""
echo "Note: AWS API status can be eventually consistent. If a stack was just deleted, it might take a moment to appear here or disappear from the list."
