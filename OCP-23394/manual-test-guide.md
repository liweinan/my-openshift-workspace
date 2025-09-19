# OCP-23394 手动测试指南

## 快速开始

### 1. 准备工作
```bash
# 设置 SSH Agent
eval `ssh-agent -s`
ssh-add ~/.ssh/id_rsa

# 创建工作目录
mkdir test-bootstrap-failure
cd test-bootstrap-failure
```

### 2. 生成安装配置
```bash
# 生成 install-config.yaml
openshift-install create install-config --dir .
```

### 3. 启动安装并监控
```bash
# 启动集群安装
openshift-install create cluster --dir .
```

**关键时机**: 当看到以下消息时，立即按 `Ctrl+C` 中断：
```
added bootstrap-success: Required control plane pods have been created
```

### 4. 收集日志
```bash
# 方法1: 使用目录
openshift-install gather bootstrap --dir .

# 方法2: 使用具体IP (如果方法1失败)
openshift-install gather bootstrap \
  --bootstrap <BOOTSTRAP_IP> \
  --master "<MASTER1_IP> <MASTER2_IP> <MASTER3_IP>"
```

### 5. 执行日志收集
```bash
# 执行收集脚本
ssh -A core@<BOOTSTRAP_IP> '/usr/local/bin/installer-gather.sh <MASTER1_IP> <MASTER2_IP> <MASTER3_IP>'

# 下载日志包
scp core@<BOOTSTRAP_IP>:~/log-bundle.tar.gz .
```

### 6. 验证日志
```bash
# 解压日志
tar xvf log-bundle.tar.gz

# 检查内容
ls -la
find . -name "journal" -type d
find . -name "nodes.list"
find . -name "serial" -type d  # 4.11+
```

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

## 验证成功标准

✅ **测试通过条件**:
- 成功收集到引导节点日志
- 至少包含一个控制平面子目录的journal日志
- `resources/nodes.list`文件存在
- 串行日志收集成功 (4.11+)

## 清理
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
