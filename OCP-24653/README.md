# OCP-24653 - [ipi-on-aws] bootimage override in install-config

## 测试目标
验证在install-config.yaml中指定自定义AMI ID时，OpenShift安装器能够正确使用指定的AMI创建集群节点。

## 测试步骤

### 1. 准备自定义AMI
```bash
# 从us-east-1复制RHCOS 4.19 AMI到us-east-2
aws ec2 copy-image \
  --region us-east-2 \
  --source-region us-east-1 \
  --source-image-id ami-0e8fd9094e487d1ff \
  --name "rhcos-4.19-custom-$(date +%Y%m%d)" \
  --description "Custom RHCOS 4.19 for OCP-24653 test"
```

### 2. 等待AMI复制完成
```bash
# 监控复制状态
aws ec2 describe-images --region us-east-2 --image-ids ami-0faab67bebd0fe719 --query 'Images[0].State' --output text
```

### 3. 配置install-config.yaml
```yaml
platform:
  aws:
    region: us-east-2
    amiID: ami-0faab67bebd0fe719  # 自定义AMI ID
```

### 4. 运行测试
```bash
./run-ocp24653-test.sh
```

## 预期结果
- 安装成功完成
- 所有worker节点使用自定义AMI: `ami-0faab67bebd0fe719`
- 所有master节点使用自定义AMI: `ami-0faab67bebd0fe719`

## 验证方法
测试脚本会自动验证：
1. AMI复制状态
2. 集群安装成功
3. Worker节点AMI ID匹配
4. Master节点AMI ID匹配

## 文件说明
- `install-config.yaml`: 包含自定义AMI ID的安装配置
- `run-ocp24653-test.sh`: 自动化测试脚本
- `README.md`: 本说明文档

## 注意事项
- 确保AWS凭证有足够权限
- 等待AMI复制完成后再开始安装
- 测试完成后记得清理资源
