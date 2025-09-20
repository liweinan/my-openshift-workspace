# OCP-25784 - [ipi-on-aws] Create private clusters with no public endpoints and access from internet

## 概述

OCP-25784测试用例验证在AWS上创建私有OpenShift集群的能力，确保集群没有公共端点，只能通过VPC内的实例访问。

## 测试目标

- 验证私有OpenShift集群的创建
- 确保集群端点不可从互联网访问
- 验证通过VPC内bastion主机访问集群的功能
- 测试集群的完整生命周期管理

## 文件结构

```
OCP-25784/
├── README.md                           # 本文档
├── OCP-25784_TEST_PROCEDURE.md        # 详细测试步骤
├── run-ocp25784-test.sh               # 自动化测试脚本
└── install-config-template.yaml       # 安装配置模板（运行时生成）
```

## 快速开始

### 1. 运行自动化测试脚本

```bash
# 使用默认配置
./run-ocp25784-test.sh

# 使用自定义配置
./run-ocp25784-test.sh --cluster-name my-private-cluster --region us-west-2

# 启用代理设置
./run-ocp25784-test.sh --proxy

# 跳过清理（保留资源用于手动测试）
./run-ocp25784-test.sh --skip-cleanup
```

### 2. 手动执行测试步骤

参考 `OCP-25784_TEST_PROCEDURE.md` 文件中的详细步骤。

## 配置选项

### 命令行参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `-v, --vpc-stack-name` | VPC CloudFormation堆栈名称 | `weli-vpc-priv` |
| `-c, --cluster-name` | OpenShift集群名称 | `weli-priv-test` |
| `-r, --region` | AWS区域 | `us-east-1` |
| `-b, --bastion-name` | Bastion主机名称 | `weli-test` |
| `-d, --vpc-cidr` | VPC CIDR块 | `10.0.0.0/16` |
| `-p, --proxy` | 启用代理设置 | `false` |
| `-s, --skip-cleanup` | 跳过清理 | `false` |

### 环境变量

| 变量名 | 描述 |
|--------|------|
| `VPC_STACK_NAME` | VPC堆栈名称 |
| `CLUSTER_NAME` | 集群名称 |
| `AWS_REGION` | AWS区域 |
| `BASTION_NAME` | Bastion主机名称 |
| `VPC_CIDR` | VPC CIDR块 |

## 测试流程

1. **基础设施准备**
   - 创建VPC和子网
   - 创建bastion主机
   - 标记子网

2. **工具准备**
   - 下载OpenShift CLI工具
   - 传输工具到bastion主机

3. **集群安装**
   - 创建install-config.yaml
   - 执行IPI安装
   - 验证安装结果

4. **功能验证**
   - 验证VPC内访问
   - 验证VPC外无法访问
   - 测试集群功能

5. **清理资源**
   - 销毁集群
   - 清理基础设施

## 关键配置

### install-config.yaml 关键设置

```yaml
publish: Internal  # 关键：设置为Internal创建私有集群
platform:
  aws:
    vpc:
      subnets:
        - id: <private-subnet-1>  # 使用私有子网
        - id: <private-subnet-2>
```

### 网络配置

- **VPC CIDR**: 10.0.0.0/16
- **集群网络**: 10.128.0.0/14
- **服务网络**: 172.30.0.0/16
- **网络类型**: OVNKubernetes

## 验证要点

### 成功标准

- [ ] VPC和bastion主机创建成功
- [ ] 子网正确标记Kubernetes标签
- [ ] 私有集群安装成功
- [ ] 所有节点和操作员状态正常
- [ ] VPC内能够访问集群console
- [ ] VPC外无法访问集群端点
- [ ] 集群资源成功清理

### 网络隔离验证

```bash
# VPC内访问（应该成功）
curl -v -k console-openshift-console.apps.<cluster-name>.qe.devcluster.openshift.com

# VPC外访问（应该失败）
curl -v -k console-openshift-console.apps.<cluster-name>.qe.devcluster.openshift.com
```

## 故障排除

### 常见问题

1. **子网标记问题**
   ```bash
   # 检查子网标签
   aws ec2 describe-subnets --subnet-ids <subnet-id>
   ```

2. **网络连接问题**
   ```bash
   # 检查安全组配置
   aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<vpc-id>"
   ```

3. **DNS解析问题**
   ```bash
   # 检查Route53私有区域
   aws route53 list-hosted-zones
   ```

### 调试命令

```bash
# 检查集群状态
oc get nodes
oc get clusteroperators

# 检查网络配置
oc get network.config/cluster -o yaml

# 检查路由
oc get routes -A
```

## 依赖工具

- AWS CLI
- OpenShift CLI (oc)
- OpenShift Installer (openshift-install)
- jq (JSON处理)
- curl (网络测试)

## 注意事项

1. **代理设置**: 如果在企业网络环境中，可能需要设置HTTP代理
2. **资源清理**: 测试完成后务必清理AWS资源以避免费用
3. **权限要求**: 需要足够的AWS权限创建和管理资源
4. **网络配置**: 确保VPC配置符合企业网络策略

## 相关文档

- [OpenShift IPI安装文档](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-private.html)
- [AWS VPC配置指南](https://docs.aws.amazon.com/vpc/latest/userguide/)
- [OpenShift网络配置](https://docs.openshift.com/container-platform/latest/networking/understanding-networking.html)
