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
else
  echo "Found the following stacks:"
  echo "${STACK_NAMES}"
fi
