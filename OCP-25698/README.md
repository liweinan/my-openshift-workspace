# OCP-25698 - [ipi-on-aws] create multiple clusters using the same subnets from an existing VPC

## 测试概述

这个测试用例验证在AWS上使用现有VPC的相同子网创建多个OpenShift集群的能力。测试确保：

1. 多个集群可以共享同一VPC的子网
2. 集群销毁后子网标签能正确清理
3. 子网可以在不同集群间重复使用
4. Machine API扩缩容功能正常工作

## 测试步骤

### 步骤1: 创建VPC和子网
创建VPC，获取其子网（包括私有和公共子网）

### 步骤2: 创建install-config.yaml
创建安装配置文件，在install-config.yaml中指定从步骤1获取的子网：
```yaml
platform:
  aws:
    region: us-east-2
    subnets:
    - subnet-0fff91886b6abc830
    - subnet-0eb40a0b8ef183641
    - subnet-0a9699835fa8193fd
    - subnet-0d8cb2cfaeff3128e
```

### 步骤3: 安装集群A
使用install-config.yaml在AWS上触发IPI安装，获得集群A

### 步骤4: 集群A健康检查
安装完成后，对集群A进行健康检查

### 步骤5: 安装集群B
使用相同的install-config.yaml但不同的集群名称，在AWS上触发IPI安装，获得集群B

### 步骤6: 集群B健康检查
安装完成后，对集群B进行健康检查

### 步骤7: 集群A扩缩容
通过Machine API成功为集群A扩展一个新的工作节点

### 步骤8: 集群B扩缩容
通过Machine API成功为集群B扩展一个新的工作节点

### 步骤9: 销毁集群A
销毁集群A，确保整个集群A（包括扩展的工作节点）被移除

**预期结果：**
```
DEBUG search for untaggable resources              
DEBUG Search for and remove tags in us-east-2 matching kubernetes.io/cluster/jialiu43-bz-gckbt: shared
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-gckbt: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-0d452b3ad90f1ce64"
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-gckbt: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-01e1cd2de0d7882bc"
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-gckbt: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-0f59af3f18571734c"
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-gckbt: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-023cac778b5464173"
```

### 步骤10: 集群B再次扩缩容
通过Machine API成功为集群B扩展一个新的工作节点

### 步骤11: 集群B健康检查
安装完成后，对集群B进行健康检查

### 步骤12: 销毁集群B
销毁集群B，确保整个集群B（包括扩展的工作节点）被移除

**预期结果：**
```
DEBUG search for untaggable resources              
DEBUG Search for and remove tags in us-east-2 matching kubernetes.io/cluster/jialiu43-bz-priv-z6hld : shared
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-priv-z6hld: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-0d452b3ad90f1ce64"
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-priv-z6hld: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-01e1cd2de0d7882bc"
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-priv-z6hld: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-0f59af3f18571734c"
INFO Removed tag kubernetes.io/cluster/jialiu43-bz-priv-z6hld: shared  arn="arn:aws:ec2:us-east-2:301721915996:subnet/subnet-023cac778b5464173"
```

### 步骤13: 验证子网状态
确保步骤1中创建的子网仍然存在，且没有 `kubernetes.io/cluster/${INFRA_ID}: shared` 标签

### 步骤14: 清理VPC
手动删除VPC以确保没有依赖资源残留

## 自动化脚本

### setup-ocp-25698-test.sh

这个脚本自动化了测试的准备工作：

#### 功能
- 创建VPC和子网（公共+私有）
- 生成两个集群的install-config.yaml模板
- 为子网添加共享标签
- 提供完整的测试步骤说明

#### 使用方法
```bash
# 基本用法（使用默认参数）
./setup-ocp-25698-test.sh

# 自定义参数
./setup-ocp-25698-test.sh \
  --region us-east-2 \
  --stack-name my-shared-vpc \
  --vpc-cidr 10.0.0.0/16 \
  --az-count 2

# 使用已存在的VPC（跳过VPC创建）
./setup-ocp-25698-test.sh \
  --region us-east-2 \
  --stack-name existing-vpc-stack \
  --skip-vpc
```

#### 参数说明
- `-r, --region`: AWS区域（默认：us-east-2）
- `-s, --stack-name`: VPC堆栈名称（默认：ocp-25698-shared-vpc）
- `-c, --vpc-cidr`: VPC CIDR（默认：10.0.0.0/16）
- `-a, --az-count`: 可用区数量（默认：2）
- `--skip-vpc`: 跳过VPC创建，使用已存在的VPC
- `-h, --help`: 显示帮助信息

## 手动执行步骤

### 1. 准备环境
```bash
# 确保已安装必要工具
aws --version
openshift-install version
oc version

# 设置AWS凭证
aws configure
```

### 2. 运行设置脚本
```bash
cd OCP-25698
./setup-ocp-25698-test.sh --region us-east-2
```

### 3. 更新配置文件
编辑生成的install-config文件，添加您的pull-secret和SSH密钥：
```bash
# 编辑集群A配置
vim install-config-cluster-a.yaml

# 编辑集群B配置
vim install-config-cluster-b.yaml
```

### 4. 安装集群A
```bash
mkdir cluster-a
cp install-config-cluster-a.yaml cluster-a/install-config.yaml
openshift-install create cluster --dir cluster-a
```

### 5. 集群A健康检查
```bash
export KUBECONFIG=cluster-a/auth/kubeconfig
oc get nodes
oc get clusteroperators
oc get machinesets
```

### 6. 安装集群B
```bash
mkdir cluster-b
cp install-config-cluster-b.yaml cluster-b/install-config.yaml
openshift-install create cluster --dir cluster-b
```

### 7. 集群B健康检查
```bash
export KUBECONFIG=cluster-b/auth/kubeconfig
oc get nodes
oc get clusteroperators
oc get machinesets
```

### 8. 扩缩容测试

#### 获取MachineSet名称
```bash
# 查看所有MachineSet
oc get machinesets -n openshift-machine-api

# 查看MachineSet详细信息
oc describe machineset <machineset-name> -n openshift-machine-api
```

#### 执行扩缩容
```bash
# 集群A扩缩容
export KUBECONFIG=cluster-a/auth/kubeconfig
oc get machinesets -n openshift-machine-api
oc scale machineset <machineset-name> -n openshift-machine-api --replicas=4

# 集群B扩缩容
export KUBECONFIG=cluster-b/auth/kubeconfig
oc get machinesets -n openshift-machine-api
oc scale machineset <machineset-name> -n openshift-machine-api --replicas=4
```

#### 验证扩缩容结果
```bash
# 查看MachineSet状态
oc get machinesets -n openshift-machine-api

# 查看Machine状态
oc get machines -n openshift-machine-api

# 查看节点状态
oc get nodes

# 等待新节点就绪
oc get nodes -w
```

### 9. 销毁集群A
```bash
openshift-install destroy cluster --dir cluster-a
```

### 10. 集群B再次扩缩容
```bash
export KUBECONFIG=cluster-b/auth/kubeconfig
oc get machinesets -n openshift-machine-api
oc scale machineset <machineset-name> -n openshift-machine-api --replicas=4

# 验证扩缩容结果
oc get nodes
oc get machines -n openshift-machine-api
```

### 11. 销毁集群B
```bash
openshift-install destroy cluster --dir cluster-b
```

### 12. 验证子网清理
```bash
# 检查子网标签
aws ec2 describe-subnets --subnet-ids <subnet-id> --query 'Subnets[0].Tags'

# 应该没有 kubernetes.io/cluster/ 标签
```

### 13. 清理VPC
```bash
aws cloudformation delete-stack --stack-name ocp-25698-shared-vpc
```

## 验证要点

### 子网标签验证
在集群销毁过程中，应该看到以下日志：
```
DEBUG search for untaggable resources              
DEBUG Search for and remove tags in us-east-2 matching kubernetes.io/cluster/<INFRA_ID>: shared
INFO Removed tag kubernetes.io/cluster/<INFRA_ID>: shared  arn="arn:aws:ec2:us-east-2:<ACCOUNT>:subnet/<SUBNET-ID>"
```

### 子网重用验证
- 集群A和集群B应该能够使用相同的子网
- 集群A销毁后，集群B应该仍然正常工作
- 子网标签应该正确清理，允许后续重用

### Machine API验证
- 扩缩容操作应该成功
- 新节点应该正确加入集群
- 节点应该获得正确的网络配置

### MachineSet名称格式
MachineSet名称通常遵循以下格式：
- `weli-clus-a-<random-string>-worker-<az>` (集群A)
- `weli-clus-b-<random-string>-worker-<az>` (集群B)

例如：
- `weli-clus-a-abc123-worker-us-east-2a`
- `weli-clus-a-abc123-worker-us-east-2b`
- `weli-clus-b-def456-worker-us-east-2a`
- `weli-clus-b-def456-worker-us-east-2b`

### 完整的扩缩容流程示例
```bash
# 1. 切换到集群A
export KUBECONFIG=/path/to/cluster-a/auth/kubeconfig

# 2. 查看MachineSet
oc get machinesets -n openshift-machine-api

# 3. 扩缩容（假设MachineSet名称是 weli-clus-a-abc123-worker-us-east-2a）
oc scale machineset weli-clus-a-abc123-worker-us-east-2a -n openshift-machine-api --replicas=4

# 4. 等待新节点就绪
oc get nodes -w

# 5. 切换到集群B
export KUBECONFIG=/path/to/cluster-b/auth/kubeconfig

# 6. 对集群B执行相同操作
oc get machinesets -n openshift-machine-api
oc scale machineset <machineset-name> -n openshift-machine-api --replicas=4
```

## 故障排除

### 常见问题

1. **子网标签冲突**
   - 确保使用 `tag-subnets.sh` 脚本正确标记子网
   - 检查标签值是否为 `shared`

2. **集群安装失败**
   - 验证子网ID是否正确
   - 检查VPC和子网配置
   - 确认AWS权限充足

3. **扩缩容失败**
   - 检查MachineSet配置
   - 验证子网容量
   - 查看Machine API日志

4. **销毁后标签残留**
   - 检查openshift-install日志
   - 手动清理残留标签
   - 验证子网状态

### 调试命令
```bash
# 检查子网标签
aws ec2 describe-subnets --subnet-ids <subnet-id> --query 'Subnets[0].Tags'

# 检查VPC状态
aws ec2 describe-vpcs --vpc-ids <vpc-id>

# 检查集群状态
oc get nodes -o wide
oc get machinesets -n openshift-machine-api
oc get machines -n openshift-machine-api

# 检查MachineSet详细信息
oc describe machineset <machineset-name> -n openshift-machine-api

# 检查Machine状态
oc describe machine <machine-name> -n openshift-machine-api

# 检查节点标签和污点
oc get nodes --show-labels
oc describe node <node-name>
```

## 依赖要求

### 必需工具
- `aws` CLI - AWS命令行工具
- `openshift-install` - OpenShift安装工具
- `oc` - OpenShift客户端工具
- `jq` - JSON处理工具

### AWS权限
- EC2权限（VPC、子网、实例管理）
- CloudFormation权限（堆栈管理）
- IAM权限（角色和策略管理）

### 网络要求
- 子网必须支持多可用区
- 子网CIDR不能重叠
- 必须包含公共和私有子网

## 相关文档

- [OpenShift IPI安装文档](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-installer.html)
- [AWS VPC和子网文档](https://docs.aws.amazon.com/vpc/)
- [OpenShift Machine API文档](https://docs.openshift.com/container-platform/latest/machine_management/)
- [OCP-25698 JIRA](https://issues.redhat.com/browse/OCP-25698)
