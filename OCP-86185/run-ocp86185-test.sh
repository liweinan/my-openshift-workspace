#!/bin/bash

# OCP-86185 - AWS gp3 Root Volume Throughput Boundary Validation

set -o nounset
set -o errexit
set -o pipefail

WORK_DIR="${WORK_DIR:-test-gp3}"
CLUSTER_NAME="${CLUSTER_NAME:-ocp-86185-test}"
REGION="${REGION:-us-east-1}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
OPENSHIFT_INSTALL_PATH="${OPENSHIFT_INSTALL_PATH:-}"
PULL_SECRET_PATH="${PULL_SECRET_PATH:-}"
VERBOSE="${VERBOSE:-false}"

PASSED=0
FAILED=0
SKIPPED=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--installer)
            OPENSHIFT_INSTALL_PATH="$2"
            shift 2
            ;;
        -p|--pull-secret)
            PULL_SECRET_PATH="$2"
            shift 2
            ;;
        -k|--ssh-key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        -w|--work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        -n|--name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --no-cleanup)
            NO_CLEANUP=true
            shift
            ;;
        -h|--help)
            cat << EOF
Usage: $0 -i INSTALLER -p PULL_SECRET -k SSH_KEY [OPTIONS]

Required:
  -i, --installer PATH      openshift-install binary path
  -p, --pull-secret PATH    pull-secret file path
  -k, --ssh-key PATH        SSH public key file path

Optional:
  -w, --work-dir DIR        working directory (default: test-gp3)
  -n, --name NAME           cluster name (default: ocp-86185-test)
  -r, --region REGION       AWS region (default: us-east-1)
  -v, --verbose             verbose output
  --no-cleanup              don't cleanup after test
  -h, --help                show this help
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Check prerequisites
if [[ -z "${OPENSHIFT_INSTALL_PATH}" ]] || [[ ! -f "${OPENSHIFT_INSTALL_PATH}" ]]; then
    echo "ERROR: openshift-install binary not found: ${OPENSHIFT_INSTALL_PATH}" >&2
    exit 1
fi

if [[ -z "${SSH_KEY_PATH}" ]] || [[ ! -f "${SSH_KEY_PATH}" ]]; then
    echo "ERROR: SSH key file not found: ${SSH_KEY_PATH}" >&2
    exit 1
fi

if [[ -z "${PULL_SECRET_PATH}" ]] || [[ ! -f "${PULL_SECRET_PATH}" ]]; then
    echo "ERROR: Pull secret file not found: ${PULL_SECRET_PATH}" >&2
    exit 1
fi

if ! command -v yq-go &> /dev/null; then
    echo "ERROR: yq-go is required but not found" >&2
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo "ERROR: AWS credentials not configured" >&2
    exit 1
fi

CONFIG_DIR="${WORK_DIR}"
CONFIG="${CONFIG_DIR}/install-config.yaml"
BACKUP_DIR="${CONFIG_DIR}/backups"
mkdir -p "${CONFIG_DIR}" "${BACKUP_DIR}"

# Create base install-config.yaml
cat > "${CONFIG}" << EOF
apiVersion: v1
baseDomain: qe1.devcluster.openshift.com
metadata:
  name: ${CLUSTER_NAME}
platform:
  aws:
    region: ${REGION}
pullSecret: '$(cat "${PULL_SECRET_PATH}")'
sshKey: |
$(cat "${SSH_KEY_PATH}" | sed 's/^/  /')
EOF

# Backup base config
cp "${CONFIG}" "${BACKUP_DIR}/base-install-config.yaml"

# Disable errexit for test execution (we want all tests to run)
set +o errexit

# Test Step 1: Below minimum boundary (124)
echo "Step 1: Test just below minimum boundary (124)"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.type = "gp3"' "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.size = 120' "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.throughput = 124' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step1-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput must be between 125.*2000"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qiE "unknown field.*throughput|failed to parse first occurrence of unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 2: Above maximum boundary (2001)
echo "Step 2: Test just above maximum boundary (2001)"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.type = "gp3"' "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.size = 120' "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.throughput = 2001' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step2-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput must be between 125.*2000"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qiE "unknown field.*throughput|failed to parse first occurrence of unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 3: Throughput zero
echo "Step 3: Test throughput value zero"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.type = "gp3"' "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.size = 120' "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.throughput = 0' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step3-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput must be between 125.*2000"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qiE "unknown field.*throughput|failed to parse first occurrence of unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 4: Negative throughput value
echo "Step 4: Test negative throughput value"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.type = "gp3"' "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.size = 120' "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.throughput = -100' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step4-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput must be between 125.*2000"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qiE "unknown field.*throughput|failed to parse first occurrence of unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 5: Invalid throughput type (string)
echo "Step 5: Test invalid throughput type (string)"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.type = "gp3"' "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.size = 120' "${CONFIG}"
sed -i.bak 's/throughput:.*/throughput: "500"/' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step5-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "cannot unmarshal string.*throughput"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qi "unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 6: Unsupported volume type with throughput
echo "Step 6: Test unsupported volume type with throughput"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.type = "gp2"' "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.size = 120' "${CONFIG}"
yq-go e -i '.platform.aws.defaultMachinePlatform.rootVolume.throughput = 500' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step6-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput not supported for type gp2"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qi "unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 7: Control plane below minimum boundary
echo "Step 7: Test split configuration below minimum boundary (control plane)"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.controlPlane.platform.aws.rootVolume.type = "gp3"' "${CONFIG}"
yq-go e -i '.controlPlane.platform.aws.rootVolume.size = 150' "${CONFIG}"
yq-go e -i '.controlPlane.platform.aws.rootVolume.throughput = 50' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step7-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput must be between 125.*2000"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qiE "unknown field.*throughput|failed to parse first occurrence of unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 8: Control plane above maximum boundary
echo "Step 8: Test split configuration above maximum boundary (control plane)"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.controlPlane.platform.aws.rootVolume.type = "gp3"' "${CONFIG}"
yq-go e -i '.controlPlane.platform.aws.rootVolume.size = 150' "${CONFIG}"
yq-go e -i '.controlPlane.platform.aws.rootVolume.throughput = 5000' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step8-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput must be between 125.*2000"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qiE "unknown field.*throughput|failed to parse first occurrence of unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 9: Compute below minimum boundary
echo "Step 9: Test split configuration below minimum boundary (compute)"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.compute[0].name = "worker"' "${CONFIG}"
yq-go e -i '.compute[0].platform.aws.rootVolume.type = "gp3"' "${CONFIG}"
yq-go e -i '.compute[0].platform.aws.rootVolume.size = 120' "${CONFIG}"
yq-go e -i '.compute[0].platform.aws.rootVolume.throughput = 50' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step9-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput must be between 125.*2000"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qiE "unknown field.*throughput|failed to parse first occurrence of unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 10: Compute above maximum boundary
echo "Step 10: Test split configuration above maximum boundary (compute)"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.compute[0].name = "worker"' "${CONFIG}"
yq-go e -i '.compute[0].platform.aws.rootVolume.type = "gp3"' "${CONFIG}"
yq-go e -i '.compute[0].platform.aws.rootVolume.size = 120' "${CONFIG}"
yq-go e -i '.compute[0].platform.aws.rootVolume.throughput = 5000' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step10-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput must be between 125.*2000"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qiE "unknown field.*throughput|failed to parse first occurrence of unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 11: Control plane unsupported volume type
echo "Step 11: Test split configuration with unsupported volume type (control plane)"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.controlPlane.platform.aws.rootVolume.type = "gp2"' "${CONFIG}"
yq-go e -i '.controlPlane.platform.aws.rootVolume.size = 150' "${CONFIG}"
yq-go e -i '.controlPlane.platform.aws.rootVolume.throughput = 500' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step11-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput not supported for type gp2"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qi "unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 12: Compute unsupported volume type
echo "Step 12: Test split configuration with unsupported volume type (compute)"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.compute[0].name = "worker"' "${CONFIG}"
yq-go e -i '.compute[0].platform.aws.rootVolume.type = "gp2"' "${CONFIG}"
yq-go e -i '.compute[0].platform.aws.rootVolume.size = 120' "${CONFIG}"
yq-go e -i '.compute[0].platform.aws.rootVolume.throughput = 500' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step12-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput not supported for type gp2"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qi "unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 13: Compute throughput zero without volume type
echo "Step 13: Test throughput zero without volume type (compute)"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.compute[0].name = "worker"' "${CONFIG}"
yq-go e -i '.compute[0].platform.aws.rootVolume.size = 120' "${CONFIG}"
yq-go e -i '.compute[0].platform.aws.rootVolume.throughput = 0' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step13-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput must be between 125.*2000"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qiE "unknown field.*throughput|failed to parse first occurrence of unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 14: Control plane throughput zero without volume type
echo "Step 14: Test throughput zero without volume type (control plane)"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.controlPlane.platform.aws.rootVolume.size = 150' "${CONFIG}"
yq-go e -i '.controlPlane.platform.aws.rootVolume.throughput = 0' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step14-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput must be between 125.*2000"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qiE "unknown field.*throughput|failed to parse first occurrence of unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Test Step 15: Edge compute pool throughput without volume type
echo "Step 15: Test throughput without volume type for edge compute pool"
cp "${BACKUP_DIR}/base-install-config.yaml" "${CONFIG}"
yq-go e -i '.compute[0].architecture = "amd64"' "${CONFIG}"
yq-go e -i '.compute[0].hyperthreading = "Enabled"' "${CONFIG}"
yq-go e -i '.compute[0].name = "edge"' "${CONFIG}"
yq-go e -i '.compute[0].platform.aws.rootVolume.size = 120' "${CONFIG}"
yq-go e -i '.compute[0].platform.aws.rootVolume.throughput = 1200' "${CONFIG}"
yq-go e -i '.compute[0].replicas = 1' "${CONFIG}"
cp "${CONFIG}" "${BACKUP_DIR}/step15-install-config.yaml"
output=$("${OPENSHIFT_INSTALL_PATH}" create manifests --dir "${CONFIG_DIR}" 2>&1)
exit_code=$?
echo "${output}"
if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -qi "throughput not supported for type gp2"; then
    echo "  PASSED"
    ((PASSED++))
elif echo "${output}" | grep -qi "unknown field.*throughput"; then
    echo "  SKIPPED: feature not supported"
    ((SKIPPED++))
else
    echo "  FAILED"
    [[ "${VERBOSE}" == "true" ]] && echo "${output}" | head -20
    ((FAILED++))
fi

# Re-enable errexit for summary
set -o errexit

# Print summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Total: $((PASSED + FAILED + SKIPPED))"
echo "Passed: ${PASSED}"
echo "Failed: ${FAILED}"
if [[ ${SKIPPED} -gt 0 ]]; then
    echo "Skipped: ${SKIPPED} (feature not supported in this version)"
fi
echo "=========================================="

# Cleanup
if [[ "${NO_CLEANUP:-false}" != "true" ]]; then
    rm -rf "${CONFIG_DIR}"
fi

if [[ ${FAILED} -eq 0 ]]; then
    exit 0
else
    exit 1
fi
