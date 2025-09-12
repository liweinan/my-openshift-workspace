# OpenShift 集群 metadata.json 生成器

- OCP-22168 - [ipi-on-aws] Destroy cluster without a metadata.json file

这个工具集用于在没有原始 `metadata.json` 文件的情况下，动态生成 `metadata.json` 文件来销毁 OpenShift 集群。基于 OCP-22168 测试用例的要求。

## 文件说明

- `generate-metadata-for-destroy.sh` - 完整功能版本，包含验证和错误处理
- `quick-generate-metadata.sh` - 简化版本，快速生成
- `README-metadata-generator.md` - 使用说明文档

## 使用方法

### 方法一：完整功能版本

```bash
./generate-metadata-for-destroy.sh -c "my-cluster" -r "us-east-1" -i "my-cluster-abc123" -u "12345678-1234-1234-1234-123456789012"
```

参数说明：
- `-c, --cluster-name`: 集群名称
- `-r, --region`: AWS 区域
- `-i, --infra-id`: 基础设施 ID
- `-u, --cluster-id`: 集群 UUID
- `-o, --output-dir`: 输出目录（可选，默认：./cleanup）

### 方法二：简化版本

```bash
./quick-generate-metadata.sh "my-cluster" "us-east-1" "my-cluster-abc123" "12345678-1234-1234-1234-123456789012"
```

## 如何获取必需参数

### 1. 从现有集群获取

如果你有现有的集群，可以通过以下方式获取参数：

```bash
# 从现有的 metadata.json 文件获取
CLUSTER_NAME=$(jq -r '.clusterName' existing-metadata.json)
REGION=$(jq -r '.aws.region' existing-metadata.json)
INFRA_ID=$(jq -r '.infraID' existing-metadata.json)
CLUSTER_ID=$(jq -r '.clusterID' existing-metadata.json)
```

### 2. 从 AWS 资源标签获取

```bash
# 获取区域
REGION="us-east-1"

# 通过 VPC 标签获取 infraID
INFRA_ID=$(aws --region $REGION ec2 describe-vpcs --filters "Name=tag:kubernetes.io/cluster/*,Values=owned" --query 'Vpcs[0].Tags[?Key==`kubernetes.io/cluster/*`].Key' --output text | cut -d'/' -f3)

# 通过资源标签获取 clusterID
CLUSTER_ID=$(aws --region $REGION resourcegroupstaggingapi get-tag-values --key openshiftClusterID --query 'TagValues[0]' --output text)

# 集群名称（通常可以从 infraID 推断）
CLUSTER_NAME=$(echo $INFRA_ID | sed 's/-[a-z0-9]\{5\}$//')
```

### 3. 从 OpenShift 集群内部获取

```bash
# 在集群内部运行
CLUSTER_ID=$(oc get clusterversion version -o jsonpath='{.spec.clusterID}')
INFRA_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
```

## 使用示例

### 完整示例

```bash
# 1. 生成 metadata.json
./generate-metadata-for-destroy.sh \
  -c "my-test-cluster" \
  -r "us-east-1" \
  -i "my-test-cluster-abc123" \
  -u "12345678-1234-1234-1234-123456789012" \
  -o "./cleanup"

# 2. 销毁集群
cd cleanup
openshift-install destroy cluster --dir . --log-level debug

# 3. 验证资源已清理
aws --region us-east-1 resourcegroupstaggingapi get-tag-values --key openshiftClusterID | grep "12345678-1234-1234-1234-123456789012"
aws --region us-east-1 resourcegroupstaggingapi get-tag-keys | grep "kubernetes.io/cluster/my-test-cluster-abc123"
```

### 快速示例

```bash
# 1. 快速生成
./quick-generate-metadata.sh "my-cluster" "us-east-1" "my-cluster-abc123" "12345678-1234-1234-1234-123456789012"

# 2. 销毁集群
cd cleanup
openshift-install destroy cluster --dir . --log-level debug
```

## 生成的 metadata.json 格式

脚本会生成符合 OpenShift 4.16+ 标准的 metadata.json 文件：

```json
{
  "clusterName": "my-cluster",
  "clusterID": "12345678-1234-1234-1234-123456789012",
  "infraID": "my-cluster-abc123",
  "aws": {
    "region": "us-east-1",
    "identifier": [
      {
        "kubernetes.io/cluster/my-cluster-abc123": "owned"
      },
      {
        "openshiftClusterID": "12345678-1234-1234-1234-123456789012"
      },
      {
        "sigs.k8s.io/cluster-api-provider-aws/cluster/my-cluster-abc123": "owned"
      }
    ]
  }
}
```

## 验证资源清理

销毁完成后，可以使用以下命令验证资源是否已完全清理：

```bash
# 检查 openshiftClusterID 标签
aws --region $REGION resourcegroupstaggingapi get-tag-values --key openshiftClusterID | grep "$CLUSTER_ID"

# 检查 kubernetes.io/cluster 标签
aws --region $REGION resourcegroupstaggingapi get-tag-keys | grep "kubernetes.io/cluster/$INFRA_ID"

# 检查所有相关资源
aws --region $REGION resourcegroupstaggingapi get-resources --tag-filters "Key=openshiftClusterID,Values=$CLUSTER_ID"
aws --region $REGION resourcegroupstaggingapi get-resources --tag-filters "Key=kubernetes.io/cluster/$INFRA_ID,Values=owned"
```

## 注意事项

1. **确保参数正确**：错误的参数可能导致无法正确识别和清理资源
2. **备份重要数据**：销毁操作是不可逆的，请确保已备份重要数据
3. **权限要求**：需要足够的 AWS 权限来删除集群资源
4. **网络连接**：确保网络连接稳定，销毁过程可能需要一些时间
5. **资源状态**：某些资源可能处于删除中状态，这是正常的

## 故障排除

### 常见问题

1. **找不到资源**：检查参数是否正确，特别是 infraID 和 clusterID
2. **权限不足**：确保 AWS 凭证有足够的权限删除资源
3. **资源被锁定**：某些资源可能被其他进程锁定，等待一段时间后重试
4. **网络问题**：检查网络连接和 AWS 服务状态

### 调试命令

```bash
# 启用详细日志
openshift-install destroy cluster --dir . --log-level debug

# 检查 AWS 凭证
aws sts get-caller-identity

# 检查区域
aws ec2 describe-regions --region-names us-east-1
```

## 相关文档

- [OCP-22168 测试用例](https://issues.redhat.com/browse/OCP-22168)
- [OpenShift 安装文档](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-installer.html)
- [AWS 资源标签文档](https://docs.aws.amazon.com/general/latest/gr/aws_tagging.html)
