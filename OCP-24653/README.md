# OCP-24653 - [ipi-on-aws] bootimage override in install-config

## Test Objectives
Verify that when a custom AMI ID is specified in install-config.yaml, the OpenShift installer can correctly use the specified AMI to create cluster nodes.

## Test Steps

### 1. Prepare Custom AMI
```bash
# Copy RHCOS 4.19 AMI from us-east-1 to us-east-2
aws ec2 copy-image \
  --region us-east-2 \
  --source-region us-east-1 \
  --source-image-id ami-0e8fd9094e487d1ff \
  --name "rhcos-4.19-custom-$(date +%Y%m%d)" \
  --description "Custom RHCOS 4.19 for OCP-24653 test"
```

### 2. Wait for AMI Copy to Complete
```bash
# Monitor copy status
aws ec2 describe-images --region us-east-2 --image-ids ami-0faab67bebd0fe719 --query 'Images[0].State' --output text
```

### 3. Configure install-config.yaml
```yaml
platform:
  aws:
    region: us-east-2
    amiID: ami-0faab67bebd0fe719  # Custom AMI ID
```

### 4. Run Test
```bash
./run-ocp24653-test.sh
```

## Expected Results
- Installation completes successfully
- All worker nodes use custom AMI: `ami-0faab67bebd0fe719`
- All master nodes use custom AMI: `ami-0faab67bebd0fe719`

## Verification Methods
The test script will automatically verify:
1. AMI copy status
2. Cluster installation success
3. Worker node AMI ID matching
4. Master node AMI ID matching

## File Descriptions
- `install-config.yaml`: Installation configuration containing custom AMI ID
- `run-ocp24653-test.sh`: Automated test script
- `README.md`: This documentation file

## Notes
- Ensure AWS credentials have sufficient permissions
- Wait for AMI copy to complete before starting installation
- Remember to clean up resources after testing