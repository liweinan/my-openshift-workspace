# OCP-23394: 收集引导失败集群的日志

## 测试用例描述
**OCP-23394**: `[ipi-on-aws] collect logs from a cluster that failed to bootstrap running installer on linux`

这个测试用例验证在 OpenShift 集群安装过程中，当引导失败时能够正确收集调试日志和故障排除信息。

## 测试目标
- 验证在安装失败时能够收集引导节点的日志
- 确保日志收集工具在异常情况下正常工作
- 验证收集的日志包含必要的调试信息

## 前置条件
- Linux 环境
- 已配置 AWS 凭证
- 已安装 `openshift-install` 工具
- 已配置 SSH 密钥

## 详细测试步骤

### 步骤 1: 设置 SSH Agent
```bash
# 启动 SSH Agent
eval `ssh-agent -s`

# 添加 SSH 密钥
ssh-add ~/.ssh/id_rsa
# 或者添加您的 SSH 密钥文件
ssh-add /path/to/your/ssh-key
```

**验证 SSH Agent 设置**:
```bash
# 检查 SSH Agent 状态
ssh-add -l
```

### 步骤 2: 启动集群安装
```bash
# 创建工作目录
mkdir -p test-bootstrap-failure
cd test-bootstrap-failure

# 生成 install-config.yaml
openshift-install create install-config --dir .

# 启动集群安装
openshift-install create cluster --dir .
```

**重要**: 保持终端窗口打开，监控安装输出。

### 步骤 3: 监控安装过程并选择中断时机

#### 方法 A: 监控日志消息中断
在安装过程中，监控以下关键消息：

```bash
# 当看到以下消息时，立即按 Ctrl+C 中断：
"added bootstrap-success: Required control plane pods have been created"
```

#### 方法 B: 分阶段中断
```bash
# 在另一个终端窗口中，等待 bootstrap 完成
openshift-install wait-for bootstrap-complete --dir .

# 然后在 install-complete 阶段中断
openshift-install wait-for install-complete --dir .
# 按 Ctrl+C 中断安装过程
```

### 步骤 4: 收集引导日志

#### 方法 1: 使用目录参数
```bash
# 使用工作目录收集日志
openshift-install gather bootstrap --dir .
```

#### 方法 2: 使用具体 IP 地址
```bash
# 从 AWS 控制台获取以下信息：
# - Bootstrap 节点公网 IP
# - Master 节点内网 IP 地址

# 使用具体 IP 地址收集日志
openshift-install gather bootstrap \
  --bootstrap <BOOTSTRAP_PUBLIC_IP> \
  --master "<MASTER1_IP> <MASTER2_IP> <MASTER3_IP>"
```

**示例**:
```bash
openshift-install gather bootstrap \
  --bootstrap 54.238.178.100 \
  --master "10.0.134.134 10.0.148.230 10.0.166.246"
```

### 步骤 5: 执行日志收集命令
根据步骤 4 的输出，执行相应的 SSH 命令：

```bash
# 执行日志收集脚本
ssh -A core@<BOOTSTRAP_IP> '/usr/local/bin/installer-gather.sh <MASTER1_IP> <MASTER2_IP> <MASTER3_IP>'

# 下载日志包
scp core@<BOOTSTRAP_IP>:~/log-bundle.tar.gz .
```

**示例**:
```bash
ssh -A core@54.238.178.100 '/usr/local/bin/installer-gather.sh 10.0.134.134 10.0.148.230 10.0.166.246'
scp core@54.238.178.100:~/log-bundle.tar.gz .
```

### 步骤 6: 解压并检查日志内容
```bash
# 解压日志包
tar xvf log-bundle.tar.gz

# 检查日志目录结构
ls -la

# 检查控制平面节点日志
ls -la */journal/

# 检查节点列表
cat */resources/nodes.list
```

### 步骤 7: 验证日志内容 (OpenShift 4.11+)
```bash
# 检查串行日志 (4.11 新功能)
ls -la */serial/

# 验证 bootstrap 节点串行日志
ls -la */serial/bootstrap/

# 验证控制平面节点串行日志
ls -la */serial/master-*/
```

## 预期结果

### 成功标准
1. **日志收集成功**: 能够成功收集到引导节点的日志
2. **日志内容完整**: 至少包含一个控制平面子目录的 journal 日志
3. **节点列表存在**: `resources/nodes.list` 文件存在并包含预期节点列表
4. **串行日志收集** (4.11+): bootstrap 和所有可用控制平面节点的串行日志被收集

### 验证检查点
```bash
# 检查日志包是否包含必要文件
find . -name "journal" -type d
find . -name "nodes.list"
find . -name "serial" -type d  # 4.11+

# 检查日志文件大小
du -sh */journal/
du -sh */serial/  # 4.11+
```

## 故障排除

### 常见问题

#### 1. SSH 连接失败
```bash
# 检查 SSH Agent
ssh-add -l

# 重新添加密钥
ssh-add ~/.ssh/id_rsa

# 测试 SSH 连接
ssh -A core@<BOOTSTRAP_IP> 'echo "SSH connection successful"'
```

#### 2. 无法找到 Bootstrap 节点 IP
```bash
# 从 AWS 控制台获取
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=<CLUSTER_NAME>-bootstrap" \
  --query 'Reservations[*].Instances[*].[PublicIpAddress,PrivateIpAddress]' \
  --output table
```

#### 3. 日志收集脚本执行失败
```bash
# 手动执行收集脚本
ssh -A core@<BOOTSTRAP_IP>
sudo /usr/local/bin/installer-gather.sh <MASTER1_IP> <MASTER2_IP> <MASTER3_IP>
```

### 调试命令
```bash
# 检查集群状态
openshift-install wait-for bootstrap-complete --dir . --log-level debug

# 检查节点状态
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=<CLUSTER_NAME>-*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
  --output table
```

## 清理步骤
```bash
# 销毁集群
openshift-install destroy cluster --dir .

# 清理工作目录
cd ..
rm -rf test-bootstrap-failure
```

## 注意事项
1. **时机选择**: 确保在 bootstrap 成功但安装未完成时中断
2. **网络访问**: 确保能够访问 bootstrap 节点的公网 IP
3. **SSH 密钥**: 确保 SSH 密钥已正确配置并添加到 agent
4. **日志大小**: 日志包可能较大，确保有足够的磁盘空间
5. **时间窗口**: 中断时机很关键，需要快速响应

## 相关文档
- [OpenShift 安装文档](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-installer.html)
- [故障排除指南](https://docs.openshift.com/container-platform/latest/support/troubleshooting/troubleshooting-installations.html)
