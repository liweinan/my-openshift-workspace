# OCP-25784 - [ipi-on-aws] Create private clusters with no public endpoints and access from internet

## 测试目标
验证在AWS上创建私有OpenShift集群，确保集群没有公共端点，只能通过VPC内的实例访问。

## 前置条件
- AWS CLI已配置
- OpenShift安装工具已准备
- 网络代理设置（如需要）

## 测试步骤

### Step 1: 创建VPC和Bastion主机

#### 1.1 创建VPC堆栈
```bash
# 使用私有集群VPC模板创建VPC
../tools/create-vpc-stack.sh -s <vpc-stack-name> -t ../tools/vpc-template-private-cluster.yaml \
  --parameter-overrides VpcCidr=10.0.0.0/16 AvailabilityZoneCount=2
```

**预期结果**: VPC堆栈创建成功，输出包含：
- VPC ID
- 私有子网ID列表
- 公共子网ID列表

#### 1.2 创建Bastion主机
```bash
# 设置代理（如需要）
export http_proxy=http://squid.corp.redhat.com:3128
export https_proxy=http://squid.corp.redhat.com:3128

# 创建bastion主机
../tools/create-bastion-host.sh <vpc-id> <public-subnet-id> <bastion-name>
```

**预期结果**: Bastion主机创建成功，获得：
- 公共IP地址
- SSH连接信息

#### 1.3 标记子网
```bash
# 为OpenShift安装标记子网
../tools/tag-subnets.sh <vpc-stack-name> <cluster-name> <aws-region>
```

**预期结果**: 子网成功标记，包含：
- `kubernetes.io/cluster/<cluster-name>=shared`
- `kubernetes.io/role/elb=1` (公共子网)
- `kubernetes.io/role/internal-elb=1` (私有子网)

### Step 2: 准备安装工具

#### 2.1 下载OpenShift CLI
```bash
# 下载oc工具
./download-oc.sh --version 4.20.0-rc.2
tar -xzf openshift-client-linux-4.20.0-rc.2-x86_64.tar.gz
chmod +x oc kubectl
```

#### 2.2 传输工具和凭证到Bastion主机
```bash
# 传输oc工具到bastion主机
scp oc core@<bastion-public-ip>:~/

# 传输OpenShift pull-secret
scp ~/.openshift/pull-secret core@<bastion-public-ip>:~/

# 传输AWS凭证
scp -r ~/.aws core@<bastion-public-ip>:~/

# 传输认证文件（如需要）
scp <auth-file> core@<bastion-public-ip>:~/
```

#### 2.3 在Bastion主机上提取安装工具
```bash
# SSH到bastion主机
ssh core@<bastion-public-ip>

# 提取openshift-install工具
./oc adm release extract --tools quay.io/openshift-release-dev/ocp-release:4.20.0-rc.2-x86_64 -a auth.json
tar zxvf openshift-install-linux-4.20.0-rc.2.tar.gz
chmod +x openshift-install
```

### Step 3: 创建install-config.yaml

#### 3.1 生成基础配置
```bash
# 在bastion主机上运行
./openshift-install create install-config

# 或者手动创建install-config.yaml文件
cat > install-config.yaml << EOF
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
metadata:
  name: <cluster-name>
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
    vpc:
      subnets:
        - id: <private-subnet-1>
        - id: <private-subnet-2>
publish: Internal
pullSecret: '$(cat ~/pull-secret)'
EOF
```

#### 3.2 配置私有集群
编辑`install-config.yaml`，确保包含以下关键配置：

```yaml
apiVersion: v1
baseDomain: qe.devcluster.openshift.com
metadata:
  name: <cluster-name>
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1
    vpc:
      subnets:
        - id: <private-subnet-1>
        - id: <private-subnet-2>
publish: Internal  # 关键：设置为Internal
pullSecret: '{"auths":{"registry.redhat.io":{"auth":"..."}}}'  # 从本地pull-secret文件复制
```

**预期结果**: `install-config.yaml`创建成功，`publish`字段设置为`Internal`

### Step 4: 执行IPI安装

#### 4.1 启动集群安装
```bash
# 在bastion主机上运行
./openshift-install create cluster
```

**预期结果**: 
- 安装过程正常进行
- 出现`WARNING process cluster-api-provider-aws exited with error: signal: killed`（正常）
- 最终显示`Install complete!`
- 提供kubeadmin密码和console URL

#### 4.2 验证安装结果
```bash
# 设置kubeconfig
export KUBECONFIG=/var/home/core/auth/kubeconfig

# 检查节点状态
./oc get nodes

# 检查集群操作员状态
./oc get clusteroperators
```

**预期结果**:
- 所有节点状态为`Ready`
- 所有集群操作员状态为`Available`

### Step 5: 验证私有集群访问

#### 5.1 在VPC内访问应用
```bash
# 在bastion主机上测试console访问
curl -v -k console-openshift-console.apps.<cluster-name>.qe.devcluster.openshift.com
```

**预期结果**: 
- 能够成功连接到console URL
- 返回HTTP 302重定向响应

#### 5.2 在VPC外验证无法访问
```bash
# 在VPC外的机器上测试
curl -v -k console-openshift-console.apps.<cluster-name>.qe.devcluster.openshift.com
```

**预期结果**: 
- 无法解析主机名
- 连接失败

### Step 6: 清理资源

#### 6.1 销毁集群
```bash
# 在bastion主机上运行
./openshift-install destroy cluster
```

**预期结果**: 
- 集群资源成功删除
- 显示`Uninstallation complete!`

#### 6.2 清理VPC和Bastion
```bash
# 删除bastion主机堆栈
aws cloudformation delete-stack --stack-name <bastion-stack-name>

# 删除VPC堆栈
aws cloudformation delete-stack --stack-name <vpc-stack-name>
```

## 验证要点

### 网络隔离验证
1. **VPC内访问**: 从bastion主机能够访问OpenShift console
2. **VPC外访问**: 从VPC外无法访问任何集群端点
3. **DNS解析**: 集群域名只在VPC内可解析

### 安全配置验证
1. **私有子网**: 所有worker和master节点部署在私有子网
2. **内部负载均衡器**: 使用内部负载均衡器
3. **Route53私有区域**: 使用私有托管区域

### 功能验证
1. **集群健康**: 所有节点和操作员状态正常
2. **应用部署**: 能够部署和访问应用
3. **网络策略**: 网络隔离策略生效

## 故障排除

### 常见问题
1. **凭证问题**: 确保pull-secret和AWS凭证已正确传输到bastion主机
2. **子网标记问题**: 确保子网正确标记了Kubernetes标签
3. **网络连接问题**: 检查安全组和路由表配置
4. **DNS解析问题**: 验证Route53私有区域配置

### 调试命令
```bash
# 检查凭证文件
ls -la ~/.aws/
ls -la ~/pull-secret

# 检查VPC配置
aws ec2 describe-vpcs --vpc-ids <vpc-id>

# 检查子网标记
aws ec2 describe-subnets --subnet-ids <subnet-id>

# 检查安全组
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<vpc-id>"

# 验证AWS凭证
aws sts get-caller-identity
```

## 测试通过标准
- [ ] VPC和bastion主机创建成功
- [ ] 子网正确标记
- [ ] 私有集群安装成功
- [ ] 所有节点和操作员状态正常
- [ ] VPC内能够访问集群
- [ ] VPC外无法访问集群
- [ ] 集群资源成功清理
