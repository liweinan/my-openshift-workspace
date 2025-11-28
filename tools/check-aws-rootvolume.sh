#!/bin/bash

set -o errexit
set -o pipefail

# Script to verify AWS root volume configuration for OpenShift cluster
# Usage: check-aws-rootvolume.sh <cluster-dir>
# Example: check-aws-rootvolume.sh /Users/weli/works/oc-swarm/openshift-versions/work4
#
# Required environment variables:
#   RELEASE_REPO - Path to the openshift/release repository
#                  Default: /Users/weli/works/oc-swarm/release
#
# Optional environment variables:
#   AWS_SHARED_CREDENTIALS_FILE - Path to AWS credentials file
#                                  Default: ~/.aws/credentials (via .awscred symlink)

if [ $# -lt 1 ]; then
  echo "Usage: $0 <cluster-dir>"
  echo "Example: $0 /Users/weli/works/oc-swarm/openshift-versions/work4"
  echo ""
  echo "Required environment variables:"
  echo "  RELEASE_REPO - Path to the openshift/release repository"
  echo "                 Default: /Users/weli/works/oc-swarm/release"
  echo ""
  echo "Optional environment variables:"
  echo "  AWS_SHARED_CREDENTIALS_FILE - Path to AWS credentials file"
  echo "                                 Default: ~/.aws/credentials (via .awscred symlink)"
  exit 1
fi

CLUSTER_DIR="$1"

# Get the release repository path
RELEASE_REPO="${RELEASE_REPO:-/Users/weli/works/oc-swarm/release}"
VERIFY_SCRIPT="${RELEASE_REPO}/ci-operator/step-registry/cucushift/installer/check/aws/rootvolume/cucushift-installer-check-aws-rootvolume-commands.sh"

# Check and display required variables
echo "=========================================="
echo "Configuration Check"
echo "=========================================="
echo "Cluster directory: ${CLUSTER_DIR}"
echo "RELEASE_REPO: ${RELEASE_REPO}"
if [ -n "${AWS_SHARED_CREDENTIALS_FILE:-}" ]; then
  echo "AWS_SHARED_CREDENTIALS_FILE: ${AWS_SHARED_CREDENTIALS_FILE}"
else
  echo "AWS_SHARED_CREDENTIALS_FILE: (not set, will use ~/.aws/credentials)"
fi
echo ""

# Validate RELEASE_REPO
if [ ! -d "${RELEASE_REPO}" ]; then
  echo "Error: RELEASE_REPO directory does not exist: ${RELEASE_REPO}"
  echo ""
  echo "Please set RELEASE_REPO environment variable:"
  echo "  export RELEASE_REPO=/path/to/openshift/release"
  echo "  $0 ${CLUSTER_DIR}"
  exit 1
fi

if [ ! -f "${VERIFY_SCRIPT}" ]; then
  echo "Error: Verification script not found at ${VERIFY_SCRIPT}"
  echo ""
  echo "Please verify RELEASE_REPO is set correctly:"
  echo "  export RELEASE_REPO=/path/to/openshift/release"
  echo "  $0 ${CLUSTER_DIR}"
  exit 1
fi
echo "Verification script: ${VERIFY_SCRIPT}"
echo ""

if [ ! -d "${CLUSTER_DIR}" ]; then
  echo "Error: Directory ${CLUSTER_DIR} does not exist"
  exit 1
fi

echo "=========================================="
echo "Preparing Files"
echo "=========================================="

# Check if install-config.yaml exists (or .bkup)
if [ ! -f "${CLUSTER_DIR}/install-config.yaml" ]; then
  if [ -f "${CLUSTER_DIR}/install-config.yaml.bkup" ]; then
    echo "Restoring install-config.yaml from backup..."
    cp "${CLUSTER_DIR}/install-config.yaml.bkup" "${CLUSTER_DIR}/install-config.yaml"
  else
    echo "Error: install-config.yaml not found in ${CLUSTER_DIR}"
    exit 1
  fi
else
  echo "✓ install-config.yaml found"
fi

# Check if kubeconfig exists
if [ ! -f "${CLUSTER_DIR}/kubeconfig" ]; then
  if [ -f "${CLUSTER_DIR}/auth/kubeconfig" ]; then
    echo "Copying kubeconfig from auth/ directory..."
    cp "${CLUSTER_DIR}/auth/kubeconfig" "${CLUSTER_DIR}/kubeconfig"
  else
    echo "Error: kubeconfig not found in ${CLUSTER_DIR} or ${CLUSTER_DIR}/auth/"
    exit 1
  fi
else
  echo "✓ kubeconfig found"
fi

# Create .awscred symlink if it doesn't exist
if [ ! -f "${CLUSTER_DIR}/.awscred" ]; then
  if [ -f "${HOME}/.aws/credentials" ]; then
    echo "Creating .awscred symlink..."
    ln -sf "${HOME}/.aws/credentials" "${CLUSTER_DIR}/.awscred"
  else
    echo "Warning: ~/.aws/credentials not found, AWS credentials may not work"
  fi
else
  echo "✓ .awscred found"
fi

# Check metadata.json (optional)
if [ -f "${CLUSTER_DIR}/metadata.json" ]; then
  echo "✓ metadata.json found"
fi

echo ""
echo "=========================================="
echo "Running Verification"
echo "=========================================="
echo ""

# Run the verification script
SHARED_DIR="${CLUSTER_DIR}" \
CLUSTER_PROFILE_DIR="${CLUSTER_DIR}" \
bash "${VERIFY_SCRIPT}"
