# OCPBUGS-66941: AWS gp3 Root Volume Throughput/IOPS Ratio Validation

## 问题描述

**OCPBUGS-66941**: `aws: throughput/iops validation for machine pools`

**PR #10222**: `OCPBUGS-66941: aws: throughput/iops validation for machine pools`

AWS gp3 卷有一个约束：throughput (MiBps) / iops <= 0.25（最大 0.25 MiBps per iops）。当 IOPS 未设置时，AWS 默认使用 3000 IOPS。此 PR 添加了对该比率的验证，确保在 `create manifests` 阶段就能捕获违反此约束的配置。

## 修复说明

此修复实现了以下功能：
- 验证 gp3 卷的 throughput (MiBps) 与 IOPS 的比率不能超过 0.25
- 当 IOPS 未设置时，使用 AWS 默认值 3000 IOPS 进行验证
- 当比率超过限制时，提供清晰的错误消息，包括建议的最小 IOPS 值
- 所有验证在 `create manifests` 阶段完成（无需实际安装集群）

## 前置要求

- `openshift-install` 二进制文件路径（必须通过 `-i` 参数指定）
- （可选）`yq-go` 或 `yq` 命令用于合并 YAML 文件（如果没有，脚本会使用基本方法）

## 使用方法

### 基本用法

```bash
cd /Users/weli/works/oc-swarm/my-openshift-workspace/OCPBUGS-66941
./validate-throughput-iops-ratio.sh -i /path/to/openshift-install
```

### 指定工作目录

```bash
./validate-throughput-iops-ratio.sh -i /path/to/openshift-install -w /tmp/my-test-dir
```

### 查看帮助信息

```bash
./validate-throughput-iops-ratio.sh -h
```

### 命令行参数

| 参数 | 说明 | 必需 | 默认值 |
|------|------|------|--------|
| `-i, --installer PATH` | openshift-install 二进制文件路径 | 是 | - |
| `-w, --work-dir DIR` | 工作目录 | 否 | `/tmp/test-gp3-throughput-iops-ratio` |
| `-h, --help` | 显示帮助信息 | 否 | - |

## 测试用例

脚本包含以下 8 个测试用例：

1. **有效配置 - 显式 IOPS**：1200 throughput / 4800 iops = 0.25（边界值）
2. **有效配置 - 默认 IOPS**：750 throughput / 3000 默认 iops = 0.25（边界值）
3. **无效配置 - 默认 IOPS**：1200 throughput / 3000 默认 iops = 0.4 > 0.25
4. **无效配置 - 显式 IOPS**：1000 throughput / 3000 iops = 0.333 > 0.25
5. **有效配置 - 边界值**：500 throughput / 2000 iops = 0.25
6. **无效配置 - 略超边界**：751 throughput / 3000 默认 iops = 0.2503 > 0.25
7. **控制平面无效配置**：验证控制平面的 throughput/iops 比率验证
8. **计算节点无效配置**：验证计算节点的 throughput/iops 比率验证

## 预期结果

- 有效配置应该成功通过验证（`openshift-install create manifests` 成功）
- 无效配置应该失败并显示包含 "throughput.*iops ratio.*too high" 或类似信息的错误消息
- 错误消息应包含建议的最小 IOPS 值

## 注意事项

- 此脚本仅进行配置验证，不会实际创建集群
- 脚本使用临时的 install-config.yaml 文件进行测试
- 所有测试完成后会显示通过/失败的统计信息
- 当 IOPS 未设置时，AWS 默认使用 3000 IOPS
- 验证提供清晰的错误消息，包括建议的最小 IOPS 值
- 所有验证在 `create manifests` 阶段完成（无需实际安装集群）

## 相关文件

- `validate-throughput-iops-ratio.sh` - 自动化验证脚本

## 文件结构

```
OCPBUGS-66941/
├── README.md                           # 本文档
└── validate-throughput-iops-ratio.sh  # Throughput/IOPS 比率验证脚本
```
