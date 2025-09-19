# OCP-23394 手动测试指南

## 测试用例对应步骤

### Step 1: 设置 SSH Agent
**测试用例步骤**: `set up the ssh-agent`
```bash
# 设置 SSH Agent
eval `ssh-agent -s`
ssh-add ~/.ssh/id_rsa

# 验证设置
ssh-add -l
```

**期待结果**: SSH Agent 成功启动，SSH 密钥已添加

### Step 2: 启动集群安装
**测试用例步骤**: `launch a cluster`
```bash
# 创建工作目录
mkdir test-bootstrap-failure
cd test-bootstrap-failure

# 生成 install-config.yaml
openshift-install create install-config --dir .

# 启动集群安装
openshift-install create cluster --dir .
```

**期待结果**: 集群安装开始，可以看到安装进度输出

### Step 3: 中断安装过程
**测试用例步骤**: `enter 'ctrl-c' to break openshift-install when the condition is satisfied`

#### 方法 A: 监控日志消息中断
**关键时机**: 当看到以下消息时，立即按 `Ctrl+C` 中断：
```
added bootstrap-success: Required control plane pods have been created
```

#### 方法 B: 分阶段中断
```bash
# 等待 bootstrap 完成
openshift-install wait-for bootstrap-complete --dir .

# 然后在 install-complete 阶段中断
openshift-install wait-for install-complete --dir .
# 按 Ctrl+C 中断
```

**期待结果**: 安装过程被成功中断，bootstrap 节点已创建但集群安装未完成

### Step 4: 收集引导日志
**测试用例步骤**: `use the sub-command 'gather' to collect information`

#### 方法 1: 使用目录参数
```bash
openshift-install gather bootstrap --dir .
```

#### 方法 2: 使用具体 IP 地址
```bash
openshift-install gather bootstrap \
  --bootstrap <BOOTSTRAP_IP> \
  --master "<MASTER1_IP> <MASTER2_IP> <MASTER3_IP>"
```

**期待结果**: 输出类似以下信息：
```
INFO Use the following commands to gather logs from the cluster
INFO ssh -A core@<BOOTSTRAP_IP> '/usr/local/bin/installer-gather.sh <MASTER1_IP> <MASTER2_IP> <MASTER3_IP>'
INFO scp core@<BOOTSTRAP_IP>:~/log-bundle.tar.gz .
```

### Step 5: 执行日志收集命令
**测试用例步骤**: `Following the guide to gather debugging data`

```bash
# 执行日志收集脚本
ssh -A core@<BOOTSTRAP_IP> '/usr/local/bin/installer-gather.sh <MASTER1_IP> <MASTER2_IP> <MASTER3_IP>'

# 下载日志包
scp core@<BOOTSTRAP_IP>:~/log-bundle.tar.gz .
```

**期待结果**: 
- SSH 连接成功，日志收集脚本执行完成
- 输出: `Log bundle written to ~/log-bundle.tar.gz`
- 日志包成功下载到本地

### Step 6: 验证日志内容
**测试用例步骤**: `check the contents of the logs to verify that at least one of the control-plane sub-directories has a journal log and the resources/nodes.list to exist`

```bash
# 解压日志包
tar xvf log-bundle.tar.gz

# 检查日志目录结构
ls -la

# 检查控制平面节点日志
find . -name "journal" -type d
ls -la */journal/

# 检查节点列表
find . -name "nodes.list"
cat */resources/nodes.list
```

**期待结果**:
- 至少包含一个控制平面子目录的 journal 日志
- `resources/nodes.list` 文件存在并包含预期节点列表
- 日志文件大小合理，内容完整

### Step 7: 验证串行日志 (OpenShift 4.11+)
**测试用例步骤**: `Check the content of log-bundle directory, the bootstrap and all available control-plane nodes' serial logs should be gathered under [log-bundle directory]/serial`

```bash
# 检查串行日志目录
find . -name "serial" -type d
ls -la */serial/

# 验证 bootstrap 节点串行日志
ls -la */serial/bootstrap/

# 验证控制平面节点串行日志
ls -la */serial/master-*/
```

**期待结果** (4.11+):
- bootstrap 和所有可用控制平面节点的串行日志被收集
- 串行日志位于 `[log-bundle directory]/serial` 目录下
- 日志文件包含系统启动和运行信息

## 获取IP地址

### Bootstrap节点IP
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=<CLUSTER_NAME>-bootstrap" \
  --query 'Reservations[*].Instances[*].PublicIpAddress' \
  --output text
```

### Master节点IP
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=<CLUSTER_NAME>-master-*" \
  --query 'Reservations[*].Instances[*].PrivateIpAddress' \
  --output text
```

## 测试结果验证

### 成功标准检查清单
**测试用例期待结果**: 验证日志收集功能在安装失败时正常工作

✅ **必须满足的条件**:
1. **日志收集成功**: 能够成功收集到引导节点的日志
2. **Journal日志存在**: 至少包含一个控制平面子目录的journal日志
3. **节点列表存在**: `resources/nodes.list`文件存在并包含预期节点列表
4. **串行日志收集** (4.11+): bootstrap和所有可用控制平面节点的串行日志被收集

### 验证命令
```bash
# 检查日志包完整性
tar -tf log-bundle.tar.gz | head -20

# 验证必要文件存在
find . -name "journal" -type d | wc -l  # 应该 > 0
find . -name "nodes.list" | wc -l       # 应该 > 0
find . -name "serial" -type d | wc -l   # 4.11+ 应该 > 0

# 检查日志文件大小
du -sh */journal/ 2>/dev/null
du -sh */serial/ 2>/dev/null  # 4.11+

# 验证节点列表内容
cat */resources/nodes.list
```

### 测试结果判定
- **✅ PASS**: 所有必须条件都满足
- **❌ FAIL**: 缺少任何必须条件

## 清理步骤
```bash
# 销毁集群
openshift-install destroy cluster --dir .

# 清理目录
cd ..
rm -rf test-bootstrap-failure
```

## 故障排除

### SSH连接问题
```bash
# 检查SSH Agent
ssh-add -l

# 测试连接
ssh -A core@<BOOTSTRAP_IP> 'echo "Connection OK"'
```

### 找不到IP地址
```bash
# 检查所有实例
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=<CLUSTER_NAME>-*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' \
  --output table
```

### 日志收集失败
```bash
# 手动执行
ssh -A core@<BOOTSTRAP_IP>
sudo /usr/local/bin/installer-gather.sh <MASTER1_IP> <MASTER2_IP> <MASTER3_IP>
```

## 测试用例总结

**OCP-23394**: `[ipi-on-aws] collect logs from a cluster that failed to bootstrap running installer on linux`

**测试目标**: 验证在OpenShift集群安装过程中，当引导失败时能够正确收集调试日志和故障排除信息。

**关键测试点**:
1. **中断时机**: 在bootstrap成功但安装未完成时中断
2. **日志收集**: 验证`openshift-install gather bootstrap`命令功能
3. **日志完整性**: 确保收集的日志包含必要的调试信息
4. **故障排除**: 验证日志收集工具在异常情况下正常工作

**实际应用价值**: 这个测试验证的功能对于生产环境的故障诊断和问题排查非常重要，确保在集群安装失败时能够收集到足够的调试信息。
