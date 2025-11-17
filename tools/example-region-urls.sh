#!/bin/bash

# Example usage of get-region-urls.sh script

echo "=== Examples of getting URLs for different regions ==="
echo ""

echo "1. Get AWS service endpoints for us-west-2 region:"
./tools/get-region-urls.sh -r us-west-2 -s aws
echo ""

echo "2. Get S3 endpoints for us-gov-west-1 region (export format):"
./tools/get-region-urls.sh -r us-gov-west-1 -s s3 -f export
echo ""

echo "3. Get OpenShift image registry URL for eu-west-1 region:"
./tools/get-region-urls.sh -r eu-west-1 -s openshift
echo ""

echo "4. Get RHCOS image URL for ap-southeast-1 region:"
./tools/get-region-urls.sh -r ap-southeast-1 -s rhcos
echo ""

echo "5. Get URLs for all service types (JSON format):"
./tools/get-region-urls.sh -r us-east-1 -s all -f json -q
echo ""

echo "6. Get AWS service endpoints for China regions:"
./tools/get-region-urls.sh -r cn-north-1 -s aws
echo ""

echo "=== Real-world usage scenarios ==="
echo ""

echo "Scenario 1: Configure custom service endpoints for OpenShift installation"
echo "export \$(./tools/get-region-urls.sh -r us-gov-west-1 -s aws -f export -q)"
echo ""

echo "Scenario 2: Get S3 endpoints for specific regions for VPC Endpoint configuration"
S3_ENDPOINT=\$(./tools/get-region-urls.sh -r us-west-2 -s s3 -f json -q | jq -r '.s3_urls.endpoint')
echo "S3 Endpoint for us-west-2: \$S3_ENDPOINT"
echo ""

echo "Scenario 3: Generate service endpoint configurations for install-config.yaml for different regions"
echo "Generate service endpoint configuration for us-gov-west-1 region:"
./tools/get-region-urls.sh -r us-gov-west-1 -s aws -f export -q | grep -E "(EC2|S3|IAM)" | sed 's/export //' | sed 's/=/:/' | sed 's/^/  /'
