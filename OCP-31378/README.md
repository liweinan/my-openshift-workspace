# OCP-31378: Duplicate Service Endpoints Validation

This directory contains scripts and documentation for the **OCP-31378** test case: `[ipi-on-aws][custom-region] Only one custom endpoint can be provided for each service.`

## Test Case Overview

**OCP-31378** verifies that the OpenShift installer properly validates against duplicate service endpoints in the `install-config.yaml` file. The test ensures that when multiple endpoints are provided for the same service, the installer reports a validation error.

### Test Steps

1. **Create install-config** with duplicate service endpoints
2. **Trigger IPI install** and expect validation error
3. **Verify** that installer correctly rejects the configuration

## Files

- `test-duplicate-endpoints.sh` - Main test script
- `README.md` - This documentation file

## Prerequisites

- `openshift-install` binary available
- Pull secret file
- SSH public key file
- AWS credentials configured (for validation)

## Usage

### Basic Usage

```bash
./test-duplicate-endpoints.sh \
  -p /path/to/pull-secret.json \
  -s /path/to/ssh-key.pub
```

### With Custom Configuration

```bash
./test-duplicate-endpoints.sh \
  -p pull-secret.json \
  -s ~/.ssh/id_rsa.pub \
  -r us-gov-east-1 \
  -n my-test-cluster \
  -d example.com
```

### Dry Run Mode

```bash
./test-duplicate-endpoints.sh \
  -p pull-secret.json \
  -s ~/.ssh/id_rsa.pub \
  --dry-run
```

## Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `-w, --work-dir` | Working directory for test | No | test-duplicate-endpoints |
| `-r, --region` | AWS region | No | us-gov-west-1 |
| `-n, --name` | Cluster name | No | test-duplicate-endpoints |
| `-d, --domain` | Base domain | No | example.com |
| `-p, --pull-secret` | Path to pull secret file | Yes | - |
| `-s, --ssh-key` | Path to SSH public key file | Yes | - |
| `--openshift-install` | Path to openshift-install binary | No | PATH |
| `--services` | Comma-separated list of services | No | ec2,s3,iam |
| `--dry-run` | Show what would be created | No | false |
| `--no-cleanup` | Don't clean up test files | No | false |

## Test Process

The script performs the following steps:

### 1. Configuration Generation
- Creates a working directory for the test
- Generates an `install-config.yaml` with duplicate service endpoints
- Configures the specified services with identical endpoints

### 2. Validation Testing
- Attempts to run `openshift-install create manifests`
- Captures the installer output and exit code
- Analyzes the output for validation error messages

### 3. Result Analysis
- Checks if the installer correctly rejected the configuration
- Verifies that the error message indicates duplicate endpoint issues
- Reports the test result

## Example Generated install-config.yaml

```yaml
apiVersion: v1
baseDomain: example.com
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 1
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 1
metadata:
  name: test-duplicate-endpoints
platform:
  aws:
    region: us-gov-west-1
    serviceEndpoints:
    - name: ec2
      url: https://ec2.us-gov-west-1.amazonaws.com
    - name: ec2
      url: https://ec2.us-gov-west-1.amazonaws.com
    - name: s3
      url: https://s3.us-gov-west-1.amazonaws.com
    - name: s3
      url: https://s3.us-gov-west-1.amazonaws.com
    - name: iam
      url: https://iam.us-gov-west-1.amazonaws.com
    - name: iam
      url: https://iam.us-gov-west-1.amazonaws.com
pullSecret: '{"auths":{"fake-registry":{"auth":"fake-auth"}}}'
sshKey: 'ssh-rsa fake-ssh-key'
```

## Expected Behavior

### Successful Test (Expected)
- Installer should fail with validation error
- Error message should indicate duplicate endpoint issues
- Exit code should be non-zero

### Failed Test (Unexpected)
- Installer should not proceed with duplicate endpoints
- If installer succeeds, it indicates a validation bug

## Example Output

### Successful Test
```
[INFO] Starting OCP-31378 duplicate service endpoints test...
[INFO] Creating install-config.yaml with duplicate service endpoints...
[SUCCESS] Created install-config.yaml with duplicate endpoints for services: ec2 s3 iam
[INFO] Testing installer validation with duplicate endpoints...
[INFO] Attempting to create manifests (expecting validation error)...
[INFO] Installer output:
FATAL failed to fetch Master Machines: failed to load asset "Install Config": invalid "install-config.yaml" file: [platform.aws.serviceEndpoints[1].name: duplicate value "ec2", platform.aws.serviceEndpoints[3].name: duplicate value "s3", platform.aws.serviceEndpoints[5].name: duplicate value "iam"]
[SUCCESS] Validation error detected as expected!
[SUCCESS] Installer correctly rejected duplicate service endpoints

==========================================
        OCP-31378 Test Report
==========================================

📊 Test Configuration:
   Work Directory: test-duplicate-endpoints
   Region: us-gov-west-1
   Cluster Name: test-duplicate-endpoints
   Base Domain: example.com
   Services Tested: ec2 s3 iam

🔍 Test Description:
   This test verifies that the OpenShift installer properly validates
   against duplicate service endpoints in install-config.yaml.

   The test creates an install-config.yaml with duplicate endpoints
   for the same service and expects the installer to report a
   validation error.

🎯 Expected Result:
   Installer should report validation error for duplicate endpoints

📋 Actual Result:
   ✅ Test PASSED - Installer correctly rejected duplicate endpoints

[SUCCESS] OCP-31378 test completed successfully!
✅ Installer correctly validates against duplicate service endpoints!
```

## Manual Testing

If you prefer to test manually:

### 1. Create install-config.yaml with Duplicates

```bash
# Create a basic install-config
openshift-install create install-config --dir test-dir

# Manually edit install-config.yaml to add duplicate endpoints
# Add the same service endpoint twice:
serviceEndpoints:
- name: ec2
  url: https://ec2.us-gov-west-1.amazonaws.com
- name: ec2
  url: https://ec2.us-gov-west-1.amazonaws.com
```

### 2. Test Validation

```bash
# Try to create manifests (should fail)
openshift-install create manifests --dir test-dir
```

### 3. Expected Error

The installer should output an error similar to:
```
FATAL failed to fetch Master Machines: failed to load asset "Install Config": invalid "install-config.yaml" file: [platform.aws.serviceEndpoints[1].name: duplicate value "ec2"]
```

## Troubleshooting

### Common Issues

1. **Missing pull secret or SSH key**
   - Ensure both files exist and are readable
   - Check file paths are correct

2. **openshift-install not found**
   - Install openshift-install or use `--openshift-install` option
   - Ensure the binary is executable

3. **Test passes unexpectedly**
   - This indicates a potential validation bug
   - Check if the installer version supports this validation
   - Verify the install-config.yaml was created correctly

4. **Test fails with wrong error**
   - Check if the error message indicates duplicate endpoint issues
   - Verify the services being tested are valid

### Debug Mode

Use `--dry-run` to see what would be created without actually running the test:

```bash
./test-duplicate-endpoints.sh -p pull-secret.json -s ssh-key.pub --dry-run
```

### Preserve Test Files

Use `--no-cleanup` to keep test files for inspection:

```bash
./test-duplicate-endpoints.sh -p pull-secret.json -s ssh-key.pub --no-cleanup
```

## Dependencies

- **openshift-install**: OpenShift installer binary
- **Pull Secret**: Red Hat pull secret file
- **SSH Key**: SSH public key file

## Test Case Requirements

This script tests the following requirements from OCP-31378:

1. ✅ **Step 1**: Create install-config with duplicate service endpoints
2. ✅ **Step 2**: Trigger IPI install and expect validation error
3. ✅ **Expected Result**: Installer reports validation error

## Exit Codes

- `0`: Test passed - Installer correctly validated duplicate endpoints
- `1`: Test failed - Installer did not properly validate duplicate endpoints

## License

This script is part of the OpenShift testing framework and follows the same licensing terms.
