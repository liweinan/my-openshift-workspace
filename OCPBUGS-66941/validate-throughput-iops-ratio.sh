#!/bin/bash

# OCPBUGS-66941 / PR-10222 - AWS gp3 Root Volume Throughput/IOPS Ratio Validation
# This script validates the throughput to IOPS ratio constraint for gp3 volumes
# AWS constraint: throughput (MiBps) / iops <= 0.25 (maximum 0.25 MiBps per iops)

set -o errexit
set -o pipefail
set -o nounset

# Configuration
OPENSHIFT_INSTALL_PATH=""
WORK_DIR="/tmp/test-gp3-throughput-iops-ratio"
CONFIG_DIR="${WORK_DIR}"
CONFIG="${CONFIG_DIR}/install-config.yaml"

# Example pull secret for testing (obviously fake)
PULL_SECRET='{"auths":{"example.com":{"auth":"ZXhhbXBsZS11c2VyOmV4YW1wbGUtcGFzc3dvcmQ="},"registry.example.com":{"auth":"ZXhhbXBsZS11c2VyOmV4YW1wbGUtcGFzc3dvcmQ="}}}'

PASSED=0
FAILED=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--installer)
            OPENSHIFT_INSTALL_PATH="$2"
            shift 2
            ;;
        -w|--work-dir)
            WORK_DIR="$2"
            CONFIG_DIR="${WORK_DIR}"
            CONFIG="${CONFIG_DIR}/install-config.yaml"
            shift 2
            ;;
        -h|--help)
            cat << EOF
Usage: $0 -i INSTALLER [OPTIONS]

Required:
  -i, --installer PATH      Path to openshift-install binary

Optional:
  -w, --work-dir DIR        Working directory (default: /tmp/test-gp3-throughput-iops-ratio)
  -h, --help                Show this help message

Example:
  $0 -i ./openshift-install
  $0 -i /path/to/openshift-install -w /tmp/my-test-dir
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use -h or --help for usage information" >&2
            exit 1
            ;;
    esac
done

# Check if openshift-install path is provided
if [[ -z "${OPENSHIFT_INSTALL_PATH}" ]]; then
    echo "ERROR: openshift-install path is required. Use -i or --installer to specify the path." >&2
    echo "Use -h or --help for usage information" >&2
    exit 1
fi

# Check if openshift-install file exists and is executable
if [[ ! -f "${OPENSHIFT_INSTALL_PATH}" ]]; then
    echo "ERROR: openshift-install binary not found: ${OPENSHIFT_INSTALL_PATH}" >&2
    exit 1
fi

if [[ ! -x "${OPENSHIFT_INSTALL_PATH}" ]]; then
    echo "ERROR: openshift-install binary is not executable: ${OPENSHIFT_INSTALL_PATH}" >&2
    exit 1
fi

mkdir -p "${CONFIG_DIR}"

# Generate temporary SSH key pair for testing
TEMP_SSH_KEY="${CONFIG_DIR}/test_ssh_key"
TEMP_SSH_KEY_PUB="${TEMP_SSH_KEY}.pub"
if ! ssh-keygen -t rsa -N "" -f "${TEMP_SSH_KEY}" -C "test@example.com" &> /dev/null; then
    echo "ERROR: Failed to generate SSH key pair" >&2
    exit 1
fi

# Read the public key content
SSH_PUB_KEY=$(cat "${TEMP_SSH_KEY_PUB}")

# Cleanup function
cleanup() {
    rm -f "${TEMP_SSH_KEY}" "${TEMP_SSH_KEY_PUB}"
    rm -rf "${CONFIG_DIR}"
}
trap cleanup EXIT

# Print openshift-install version for debugging
echo "Using openshift-install: ${OPENSHIFT_INSTALL_PATH}"
echo "Version:"
"${OPENSHIFT_INSTALL_PATH}" version
echo ""

# Disable errexit for test execution (we want all tests to run)
set +o errexit

# Test Step 1: Valid throughput with sufficient explicit IOPS (1200 throughput / 4800 iops = 0.25)
echo "Step 1: Valid root volume throughput with sufficient explicit IOPS (1200 throughput / 4800 iops = 0.25)"
cat > "${CONFIG}" << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
metadata:
  name: test-cluster
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
    vpc: {}
    defaultMachinePlatform:
      rootVolume:
        type: gp3
        size: 100
        throughput: 1200
        iops: 4800
publish: External
pullSecret: '${PULL_SECRET}'
sshKey: |
$(echo "${SSH_PUB_KEY}" | sed 's/^/  /')
EOF
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}" | head -20
if [[ ${exit_code} -eq 0 ]]; then
    echo "  PASSED"
    ((PASSED++))
else
    echo "  FAILED (expected success)"
    ((FAILED++))
fi
echo ""

# Test Step 2: Valid throughput with default IOPS (750 throughput / 3000 iops = 0.25)
echo "Step 2: Valid root volume throughput with default IOPS (750 throughput / 3000 default iops = 0.25)"
cat > "${CONFIG}" << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
metadata:
  name: test-cluster
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
    vpc: {}
    defaultMachinePlatform:
      rootVolume:
        type: gp3
        size: 100
        throughput: 750
publish: External
pullSecret: '${PULL_SECRET}'
sshKey: |
$(echo "${SSH_PUB_KEY}" | sed 's/^/  /')
EOF
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}" | head -20
if [[ ${exit_code} -eq 0 ]]; then
    echo "  PASSED"
    ((PASSED++))
else
    echo "  FAILED (expected success)"
    ((FAILED++))
fi
echo ""

# Test Step 3: Invalid throughput exceeding ratio with default IOPS (1200 throughput / 3000 iops = 0.4 > 0.25)
echo "Step 3: Invalid root volume throughput exceeding ratio with default IOPS (1200 throughput / 3000 default iops = 0.4 > 0.25)"
cat > "${CONFIG}" << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
metadata:
  name: test-cluster
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
    vpc: {}
    defaultMachinePlatform:
      rootVolume:
        type: gp3
        size: 100
        throughput: 1200
publish: External
pullSecret: '${PULL_SECRET}'
sshKey: |
$(echo "${SSH_PUB_KEY}" | sed 's/^/  /')
EOF
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qiE "throughput.*iops ratio.*too high|maximum is.*0\.25.*MiBps per iops"; then
    if echo "${output}" | grep -qi "4800"; then
        echo "  PASSED"
        ((PASSED++))
    else
        echo "  PARTIAL PASS (error message found but missing expected IOPS value)"
        ((FAILED++))
    fi
else
    echo "  FAILED (expected error about throughput/iops ratio)"
    ((FAILED++))
fi
echo ""

# Test Step 4: Invalid throughput exceeding ratio with explicit IOPS (1000 throughput / 3000 iops = 0.333 > 0.25)
echo "Step 4: Invalid root volume throughput exceeding ratio with explicit IOPS (1000 throughput / 3000 iops = 0.333 > 0.25)"
cat > "${CONFIG}" << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
metadata:
  name: test-cluster
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
    vpc: {}
    defaultMachinePlatform:
      rootVolume:
        type: gp3
        size: 100
        throughput: 1000
        iops: 3000
publish: External
pullSecret: '${PULL_SECRET}'
sshKey: |
$(echo "${SSH_PUB_KEY}" | sed 's/^/  /')
EOF
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qiE "throughput.*iops ratio.*too high|maximum is.*0\.25.*MiBps per iops"; then
    if echo "${output}" | grep -qi "4000"; then
        echo "  PASSED"
        ((PASSED++))
    else
        echo "  PARTIAL PASS (error message found but missing expected IOPS value)"
        ((FAILED++))
    fi
else
    echo "  FAILED (expected error about throughput/iops ratio)"
    ((FAILED++))
fi
echo ""

# Test Step 5: Valid throughput at boundary with explicit IOPS (500 throughput / 2000 iops = 0.25)
echo "Step 5: Valid root volume throughput at boundary with explicit IOPS (500 throughput / 2000 iops = 0.25)"
cat > "${CONFIG}" << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
metadata:
  name: test-cluster
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
    vpc: {}
    defaultMachinePlatform:
      rootVolume:
        type: gp3
        size: 100
        throughput: 500
        iops: 2000
publish: External
pullSecret: '${PULL_SECRET}'
sshKey: |
$(echo "${SSH_PUB_KEY}" | sed 's/^/  /')
EOF
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}" | head -20
if [[ ${exit_code} -eq 0 ]]; then
    echo "  PASSED"
    ((PASSED++))
else
    echo "  FAILED (expected success)"
    ((FAILED++))
fi
echo ""

# Test Step 6: Invalid throughput just above ratio with default IOPS (751 throughput / 3000 iops = 0.2503 > 0.25)
echo "Step 6: Invalid root volume throughput just above ratio with default IOPS (751 throughput / 3000 default iops = 0.2503 > 0.25)"
cat > "${CONFIG}" << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
metadata:
  name: test-cluster
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
    vpc: {}
    defaultMachinePlatform:
      rootVolume:
        type: gp3
        size: 100
        throughput: 751
publish: External
pullSecret: '${PULL_SECRET}'
sshKey: |
$(echo "${SSH_PUB_KEY}" | sed 's/^/  /')
EOF
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qiE "throughput.*iops ratio.*too high|maximum is.*0\.25.*MiBps per iops"; then
    echo "  PASSED"
    ((PASSED++))
else
    echo "  FAILED (expected error about throughput/iops ratio)"
    ((FAILED++))
fi
echo ""

# Test Step 7: Control plane with invalid throughput/iops ratio
echo "Step 7: Invalid root volume throughput/iops ratio for control plane"
cat > "${CONFIG}" << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
metadata:
  name: test-cluster
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
    vpc: {}
controlPlane:
  platform:
    aws:
      rootVolume:
        type: gp3
        size: 100
        throughput: 1000
        iops: 3000
publish: External
pullSecret: '${PULL_SECRET}'
sshKey: |
$(echo "${SSH_PUB_KEY}" | sed 's/^/  /')
EOF
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qiE "throughput.*iops ratio.*too high|maximum is.*0\.25.*MiBps per iops"; then
    echo "  PASSED"
    ((PASSED++))
else
    echo "  FAILED (expected error about throughput/iops ratio)"
    ((FAILED++))
fi
echo ""

# Test Step 8: Compute pool with invalid throughput/iops ratio
echo "Step 8: Invalid root volume throughput/iops ratio for compute pool"
cat > "${CONFIG}" << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
metadata:
  name: test-cluster
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
    vpc: {}
compute:
  - name: worker
    platform:
      aws:
        rootVolume:
          type: gp3
          size: 100
          throughput: 1000
          iops: 3000
publish: External
pullSecret: '${PULL_SECRET}'
sshKey: |
$(echo "${SSH_PUB_KEY}" | sed 's/^/  /')
EOF
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qiE "throughput.*iops ratio.*too high|maximum is.*0\.25.*MiBps per iops"; then
    echo "  PASSED"
    ((PASSED++))
else
    echo "  FAILED (expected error about throughput/iops ratio)"
    ((FAILED++))
fi
echo ""

# Re-enable errexit for summary
set -o errexit

# Print summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Total: $((PASSED + FAILED))"
echo "Passed: ${PASSED}"
echo "Failed: ${FAILED}"
echo "=========================================="

# Cleanup is handled by trap, but we need to exit with proper code
if [[ ${FAILED} -eq 0 ]]; then
    exit 0
else
    exit 1
fi
