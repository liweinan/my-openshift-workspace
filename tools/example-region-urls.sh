#!/bin/bash

# Example usage of get-region-urls.sh script

echo "=== 获取不同区域的URL示例 ==="
echo ""

echo "1. 获取 us-west-2 区域的 AWS 服务端点："
./tools/get-region-urls.sh -r us-west-2 -s aws
echo ""

echo "2. 获取 us-gov-west-1 区域的 S3 端点（export 格式）："
./tools/get-region-urls.sh -r us-gov-west-1 -s s3 -f export
echo ""

echo "3. 获取 eu-west-1 区域的 OpenShift 镜像仓库 URL："
./tools/get-region-urls.sh -r eu-west-1 -s openshift
echo ""

echo "4. 获取 ap-southeast-1 区域的 RHCOS 镜像 URL："
./tools/get-region-urls.sh -r ap-southeast-1 -s rhcos
echo ""

echo "5. 获取所有服务类型的 URL（JSON 格式）："
./tools/get-region-urls.sh -r us-east-1 -s all -f json -q
echo ""

echo "6. 获取中国区域的 AWS 服务端点："
./tools/get-region-urls.sh -r cn-north-1 -s aws
echo ""

echo "=== 实际使用场景 ==="
echo ""

echo "场景1: 为 OpenShift 安装配置自定义服务端点"
echo "export \$(./tools/get-region-urls.sh -r us-gov-west-1 -s aws -f export -q)"
echo ""

echo "场景2: 获取特定区域的 S3 端点用于 VPC Endpoint 配置"
S3_ENDPOINT=\$(./tools/get-region-urls.sh -r us-west-2 -s s3 -f json -q | jq -r '.s3_urls.endpoint')
echo "S3 Endpoint for us-west-2: \$S3_ENDPOINT"
echo ""

echo "场景3: 为不同区域生成 install-config.yaml 的服务端点配置"
echo "生成 us-gov-west-1 区域的服务端点配置："
./tools/get-region-urls.sh -r us-gov-west-1 -s aws -f export -q | grep -E "(EC2|S3|IAM)" | sed 's/export //' | sed 's/=/:/' | sed 's/^/  /'
