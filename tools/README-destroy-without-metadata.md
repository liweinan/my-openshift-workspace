# 无metadata.json的集群销毁脚本

这些脚本用于在没有原始metadata.json文件的情况下销毁OpenShift集群，遵循OCP-22168测试用例的流程。

## 脚本说明

### 1. destroy-cluster-without-metadata.sh
完整的自动化销毁脚本，包含所有步骤。

**功能：**
- 自动从AWS获取集群信息
- 生成metadata.json文件
- 验证集群资源存在
- 执行集群销毁
- 验证无遗留资源

**使用方法：**
```bash
# 基本用法
./destroy-cluster-without-metadata.sh <cluster-name> <aws-region>

# 指定输出目录
./destroy-cluster-without-metadata.sh <cluster-name> <aws-region> <output-directory>

# 示例
./destroy-cluster-without-metadata.sh qe-jialiu3 us-east-2
./destroy-cluster-without-metadata.sh my-cluster us-west-2 ./destroy-work
```

### 2. generate-metadata-for-destroy.sh
仅生成metadata.json文件的脚本。

**功能：**
- 从AWS获取集群信息
- 生成metadata.json文件
- 提供使用说明

**使用方法：**
```bash
# 基本用法
./generate-metadata-for-destroy.sh <cluster-name> <aws-region>

# 指定输出文件
./generate-metadata-for-destroy.sh <cluster-name> <aws-region> <output-file>

# 示例
./generate-metadata-for-destroy.sh qe-jialiu3 us-east-2
./generate-metadata-for-destroy.sh my-cluster us-west-2 ./cleanup/metadata.json
```

## 测试用例流程 (OCP-22168)

### 步骤1: 准备环境
```bash
# 创建测试目录
mkdir test1 test2 cleanup

# 生成install-config
openshift-install create install-config
```

### 步骤2: 安装集群
```bash
# 复制配置并安装
cp ./install-config.yaml ./test1/
openshift-install create cluster --dir ./test1
```

### 步骤3: 记录集群信息
```bash
# 查看metadata.json
cat test1/metadata.json
```

### 步骤4: 验证集群资源存在
```bash
export AWS_REGION="us-east-2"
export CLUSTER_ID="622e8b4b-242d-4741-a8a0-94f4c084767f"
export INFRA_ID="qe-jialiu3-x5rjl"

# 检查openshiftClusterID
aws --region ${AWS_REGION} resourcegroupstaggingapi get-tag-values \
    --key openshiftClusterID | grep "${CLUSTER_ID}"

# 检查集群标签
aws --region ${AWS_REGION} resourcegroupstaggingapi get-tag-keys | \
    grep "kubernetes.io/cluster/${INFRA_ID}"
```

### 步骤5: 生成metadata.json (使用脚本)
```bash
# 使用自动化脚本
./generate-metadata-for-destroy.sh qe-jialiu3 us-east-2 ./cleanup/metadata.json

# 或手动生成
export CLUSTER_NAME="qe-jialiu3"
INFRA_ID=$(aws --region "${AWS_REGION}" ec2 describe-vpcs | \
    jq -c '.Vpcs[] | .Tags | select(. != null) | from_entries | 
    ."name" = (keys[] | select(. | startswith("kubernetes.io/cluster/")) | 
    sub("^kubernetes.io/cluster/"; "")) | .name | 
    select(. | startswith("${CLUSTER_NAME}"))')

echo "{\"aws\":{\"region\":\"${AWS_REGION}\",\"identifier\":[{\"kubernetes.io/cluster/${INFRA_ID}\":\"owned\"}]}}" > ./cleanup/metadata.json
```

### 步骤6: 销毁集群
```bash
# 使用生成的metadata.json销毁集群
openshift-install destroy cluster --dir ./cleanup
```

### 步骤7: 验证无遗留资源
```bash
# 检查openshiftClusterID
aws --region ${AWS_REGION} resourcegroupstaggingapi get-tag-values \
    --key openshiftClusterID | grep "${CLUSTER_ID}"

# 检查集群标签
aws --region ${AWS_REGION} resourcegroupstaggingapi get-tag-keys | \
    grep "kubernetes.io/cluster/${INFRA_ID}"

# 获取详细资源信息
aws --region ${AWS_REGION} resourcegroupstaggingapi get-resources \
    --tag-filters "Key=openshiftClusterID,Values=${CLUSTER_ID}"

aws --region ${AWS_REGION} resourcegroupstaggingapi get-resources \
    --tag-filters "Key=kubernetes.io/cluster/${INFRA_ID},Values=owned"
```

### 步骤8: 测试新安装
```bash
# 使用相同集群名称测试新安装
cp ./install-config.yaml ./test2/
openshift-install create cluster --dir ./test2
```

## 使用场景

### 场景1: 完全自动化销毁
```bash
# 一键完成所有步骤
./destroy-cluster-without-metadata.sh my-cluster us-east-2
```

### 场景2: 分步执行
```bash
# 步骤1: 生成metadata.json
./generate-metadata-for-destroy.sh my-cluster us-east-2 ./cleanup/metadata.json

# 步骤2: 手动销毁
openshift-install destroy cluster --dir ./cleanup

# 步骤3: 验证
./check-cluster-destroy-status.sh ./cleanup us-east-2
```

### 场景3: 批量处理
```bash
# 处理多个集群
for cluster in cluster1 cluster2 cluster3; do
    ./destroy-cluster-without-metadata.sh $cluster us-east-2
done
```

## 生成的metadata.json结构

### 4.16及以上版本
```json
{
  "clusterName": "qe-jialiu3",
  "clusterID": "622e8b4b-242d-4741-a8a0-94f4c084767f",
  "infraID": "qe-jialiu3-x5rjl",
  "aws": {
    "region": "us-east-2",
    "identifier": [
      {
        "kubernetes.io/cluster/qe-jialiu3-x5rjl": "owned"
      },
      {
        "openshiftClusterID": "622e8b4b-242d-4741-a8a0-94f4c084767f"
      },
      {
        "sigs.k8s.io/cluster-api-provider-aws/cluster/qe-jialiu3-x5rjl": "owned"
      }
    ],
    "clusterDomain": "qe-jialiu3.qe.devcluster.openshift.com"
  }
}
```

## 依赖要求

- `aws` CLI - AWS命令行工具
- `jq` - JSON处理工具
- `openshift-install` - OpenShift安装工具

## 权限要求

脚本需要以下AWS权限：
- `ec2:DescribeVpcs`
- `resourcegroupstaggingapi:GetTagKeys`
- `resourcegroupstaggingapi:GetTagValues`
- `resourcegroupstaggingapi:GetResources`

## 故障排除

### 找不到集群资源
```bash
# 检查AWS区域是否正确
aws --region us-east-2 ec2 describe-vpcs --query 'Vpcs[?Tags[?Key==`kubernetes.io/cluster/*`]]'

# 检查集群名称是否匹配
aws --region us-east-2 resourcegroupstaggingapi get-tag-keys | grep "kubernetes.io/cluster"
```

### 权限错误
```bash
# 检查AWS凭证
aws sts get-caller-identity

# 检查权限
aws --region us-east-2 ec2 describe-vpcs
```

### 销毁失败
```bash
# 检查metadata.json格式
cat cleanup/metadata.json | jq .

# 手动验证资源
./check-cluster-destroy-status.sh cleanup us-east-2
```

## 注意事项

1. **集群名称匹配**: 脚本通过集群名称模式匹配VPC标签，确保名称正确
2. **区域一致性**: 确保指定的AWS区域与集群实际部署区域一致
3. **权限验证**: 确保有足够的AWS权限访问和删除资源
4. **资源状态**: 某些资源可能处于"deleting"状态，需要等待
5. **最终验证**: 建议在销毁后等待几分钟再次验证

## 与现有脚本的配合

```bash
# 生成metadata.json
./generate-metadata-for-destroy.sh my-cluster us-east-2

# 销毁集群
openshift-install destroy cluster --dir .

# 验证销毁状态
./check-cluster-destroy-status.sh . us-east-2

# 清理本地文件
./cleanup-openshift-files.sh
```
