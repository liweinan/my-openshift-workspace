# OCP-86185 - AWS gp3 Root Volume Throughput Boundary Validation

## Overview

OCP-86185 test case validates that AWS gp3 root volume throughput boundary conditions are properly enforced during the `create manifests` phase. The test verifies that invalid throughput values are rejected with appropriate error messages.

## Test Objectives

- Validate that `throughput` value must be between 125 and 2000 MiB/s (inclusive)
- Verify that `type` must be `gp3` when `throughput` is specified
- Test boundary conditions for both control plane and compute nodes
- Ensure all validation occurs during `create manifests` phase (no cluster installation required)

## Test Cases

The script executes 15 test cases covering:

1. **Minimum boundary validation**: Tests rejection of values below 125 MiB/s (124, 0, negative values)
2. **Maximum boundary validation**: Tests rejection of values above 2000 MiB/s (2001)
3. **Type validation**: Tests rejection of string values and non-gp3 volume types
4. **Control plane configurations**: Tests control plane specific throughput settings
5. **Compute node configurations**: Tests compute node specific throughput settings
6. **Edge compute pool**: Tests edge pool default behavior (gp2 does not support throughput)

## Prerequisites

- `openshift-install` binary
- AWS CLI configured with appropriate credentials
- Pull secret file
- SSH public key file
- `jq` (optional, for verbose output parsing)

## Quick Start

### Basic Usage

```bash
./run-ocp86185-test.sh \
  -i ./openshift-install \
  -p pull-secret.json \
  -k ~/.ssh/id_rsa.pub
```

### With Custom Configuration

```bash
./run-ocp86185-test.sh \
  -i ./openshift-install \
  -p pull-secret.json \
  -k ~/.ssh/id_rsa.pub \
  -n my-test-cluster \
  -r us-west-2 \
  -w custom-test-dir \
  -v
```

### Skip Cleanup

```bash
./run-ocp86185-test.sh \
  -i ./openshift-install \
  -p pull-secret.json \
  -k ~/.ssh/id_rsa.pub \
  --no-cleanup
```

## Command Line Options

| Option | Description | Required | Default |
|--------|-------------|----------|---------|
| `-i, --installer PATH` | Path to openshift-install binary | Yes | - |
| `-p, --pull-secret PATH` | Path to pull-secret file | Yes | - |
| `-k, --ssh-key PATH` | Path to SSH public key file | Yes | - |
| `-w, --work-dir DIR` | Working directory | No | `test-gp3` |
| `-n, --name NAME` | Cluster name | No | `ocp-86185-test` |
| `-r, --region REGION` | AWS region | No | `us-east-1` |
| `-v, --verbose` | Enable verbose output | No | false |
| `--no-cleanup` | Don't cleanup after test | No | false |
| `-h, --help` | Show help message | No | - |

## Test Steps

The script automatically executes all 15 test steps:

1. **Step 1**: Test just below minimum boundary (throughput = 124)
2. **Step 2**: Test just above maximum boundary (throughput = 2001)
3. **Step 3**: Test throughput value zero
4. **Step 4**: Test negative throughput value
5. **Step 5**: Test invalid throughput type (string)
6. **Step 6**: Test unsupported volume type with throughput (gp2)
7. **Step 7**: Test split configuration below minimum boundary (control plane)
8. **Step 8**: Test split configuration above maximum boundary (control plane)
9. **Step 9**: Test split configuration below minimum boundary (compute)
10. **Step 10**: Test split configuration above maximum boundary (compute)
11. **Step 11**: Test split configuration with unsupported volume type (control plane)
12. **Step 12**: Test split configuration with unsupported volume type (compute)
13. **Step 13**: Test throughput zero without volume type (compute)
14. **Step 14**: Test throughput zero without volume type (control plane)
15. **Step 15**: Test throughput without volume type for edge compute pool

## Expected Results

All test steps should **fail** during `create manifests` phase with appropriate error messages:

- Boundary violations: `throughput must be between 125 MiB/s and 2000 MiB/s`
- Type mismatches: `cannot unmarshal string into int64`
- Unsupported volume types: `throughput is not supported for the specified volume type` or similar

## Test Report

After all tests complete, the script generates a summary report showing:

- Total number of tests executed
- Number of passed/failed tests
- Detailed results for each test step
- Overall test result (PASS/FAIL)

## Notes

- All boundary validation occurs during `create manifests` phase
- No actual cluster installation is required
- The script creates a temporary install-config.yaml for each test step
- Test directory is cleaned up automatically unless `--no-cleanup` is specified
- Each test step verifies that the expected error message is present in the output

## Troubleshooting

### Command succeeds when it should fail

If a test step succeeds when it should fail, this indicates:
- The validation logic may not be working as expected
- The test configuration may be incorrect
- Check the verbose output (`-v`) for more details

### Error message mismatch

If the error message doesn't match the expected pattern:
- Check the actual error output in verbose mode
- Verify the expected error pattern in the test case documentation
- The error message format may have changed in newer versions

### AWS credentials not configured

Ensure AWS CLI is properly configured:
```bash
aws configure
aws sts get-caller-identity
```

## File Structure

```
OCP-86185/
├── README.md                 # This file
└── run-ocp86185-test.sh     # Automated test script
```
