# Cluster Destroy Status Check Scripts

这些脚本用于检查OpenShift集群销毁后的状态，确保没有遗留的AWS资源。

## 脚本说明

### 1. check-cluster-destroy-status.sh
完整的集群销毁状态检查脚本，提供详细的检查报告。

**功能：**
- 从metadata.json提取集群信息（clusterName, clusterID, infraID）
- 检查AWS资源标签
- 验证CloudFormation栈状态
- 检查VPC状态
- 检查Route53记录
- 提供详细的资源状态信息

**使用方法：**
```bash
# 使用默认区域（us-east-1）
./check-cluster-destroy-status.sh ./work1

# 指定AWS区域
./check-cluster-destroy-status.sh ./work1 us-east-2
```

### 2. quick-check-destroy-status.sh
快速检查脚本，提供简洁的状态报告。

**功能：**
- 快速检查集群标签资源
- 检查CloudFormation栈
- 提供简洁的输出

**使用方法：**
```bash
# 使用默认区域
./quick-check-destroy-status.sh ./work1

# 指定AWS区域
./quick-check-destroy-status.sh ./work1 us-east-2
```

## 使用场景

### 测试用例场景
根据测试用例要求，在集群销毁后需要验证：

1. **记录集群UUID**
   ```bash
   oc get clusterversion -o jsonpath='{.spec.clusterID}{"\n"}' version
   ```

2. **记录infraID**
   ```bash
   cat work1/metadata.json | jq -r '.infraID'
   ```

3. **检查AWS资源标签**
   ```bash
   aws --region us-east-2 resourcegroupstaggingapi get-tag-keys | grep "kubernetes.io/cluster/<infraID>"
   ```

4. **验证无遗留资源**
   ```bash
   aws --region us-east-2 resourcegroupstaggingapi get-resources --tag-filters "Key=kubernetes.io/cluster/<infraID>,Values=owned"
   ```

### 使用脚本替代手动检查
```bash
# 完整检查
./check-cluster-destroy-status.sh ./work1 us-east-2

# 快速检查
./quick-check-destroy-status.sh ./work1 us-east-2
```

## 输出说明

### 正常情况（集群完全销毁）
```
✅ No resources found with cluster tag.
✅ No CloudFormation stacks found.
✅ No VPC found with name '<infraID>-vpc'.
✅ No hosted zone found for domain '<cluster-domain>'.
```

### 异常情况（有遗留资源）
```
⚠️  WARNING: Found resources with cluster tag:
"kubernetes.io/cluster/<infraID>"

Resources still tagged with cluster ownership:
- arn:aws:ec2:us-east-2:123456789012:instance/i-1234567890abcdef0 (Tags: 5)
- arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/app/test-lb/1234567890abcdef0 (Tags: 3)
```

## 故障排除

### 如果发现遗留资源
1. **等待几分钟**：某些资源可能处于"deleting"状态
2. **重新运行脚本**：验证资源是否已被删除
3. **检查AWS控制台**：手动验证资源状态
4. **报告问题**：如果资源不在"deleted"或"terminated"状态，可能是bug

### 常见资源状态
- `deleted` - 已删除（正常）
- `terminated` - 已终止（正常）
- `deleting` - 删除中（需要等待）
- `active` - 活跃状态（异常，需要调查）

## 依赖要求

- `jq` - JSON处理工具
- `aws` CLI - AWS命令行工具
- 有效的AWS凭证和权限

## 权限要求

脚本需要以下AWS权限：
- `resourcegroupstaggingapi:GetTagKeys`
- `resourcegroupstaggingapi:GetResources`
- `cloudformation:ListStacks`
- `cloudformation:DescribeStacks`
- `ec2:DescribeVpcs`
- `ec2:DescribeInstances`
- `elasticloadbalancing:DescribeLoadBalancers`
- `route53:ListHostedZones`
- `route53:GetHostedZone`
- `route53:ListResourceRecordSets`
