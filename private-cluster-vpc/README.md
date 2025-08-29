# openshift-install配置私有子网

好的，这是一个非常关键的步骤。要让 `openshift-install` 使用您通过 CloudFormation 创建的现有 VPC 环境，您需要在 `install-config.yaml` 文件中详细指定 VPC 的各项资源 ID。

`openshift-install` 不会自动检测已有的 VPC，您必须明确地告诉它使用哪些子网。

**核心步骤如下：**

1. **获取 VPC 资源信息**: 在您的 CloudFormation 堆栈创建成功后，您需要从其 “Outputs” (输出) 标签页中获取以下关键信息：
    * `VpcId`: 您的 VPC 的 ID。
    * `PublicSubnetIds`: 公有子网的 ID 列表。
    * `PrivateSubnetIds`: 私有子网的 ID 列表。

2. **修改 `install-config.yaml`**: 在运行 `openshift-install create cluster` 之前，您需要先运行 `openshift-install create install-config` 生成一个基础的 `install-config.yaml` 文件。然后，手动编辑这个文件，添加或修改 `platform.aws` 部分，如下所示：

**`install-config.yaml` 修改示例:**

```yaml
apiVersion: v1
baseDomain: your.base.domain.com
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 3
metadata:
  name: my-private-cluster
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16 # 这个应该和您的 VPC CIDR 匹配
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1 # 您的区域
    # --- 这是您需要添加或修改的关键部分 ---
    subnets:
    - subnet-0123456789abcdef0 # 第一个私有子网 ID
    - subnet-fedcba9876543210f # 第二个私有子网 ID
    # 如果有更多私有子网，继续添加...
    vpcID: vpc-abcdef0123456789 # 您的 VPC ID
publish: Internal # 对于私有集群，这里必须是 Internal
pullSecret: '{"auths":...}'
sshKey: ssh-rsa AAAA...
```

**关键点解释:**

* **`platform.aws.subnets`**: 这是一个**列表**，您需要在这里填入所有希望 OpenShift 使用的**私有子网 (Private Subnets)** 的 ID。安装程序会将 Master 和 Worker 节点都部署在这些私有子网中。
* **`platform.aws.vpcID`**: 这里填入您的 CloudFormation 堆栈创建的 VPC 的 ID。
* **`networking.machineNetwork`**: 这里的 CIDR 必须与您 VPC 的 CIDR (`VpcCidr` 参数) 相匹配。
* **`publish: Internal`**: 这是私有集群的关键设置。它告诉安装程序，集群的 API 端点和应用路由都应该是私有的，不能从公网直接访问。
* **公有子网去哪了？**: 您可能会问为什么没有填公有子网的 ID。`openshift-install` 会自动发现与您提供的私有子网在同一可用区 (Availability Zone) 的公有子网，并使用它们来创建面向公众的资源，例如负载均衡器 (ELB/NLB)。这就是为什么我们的 CloudFormation 模板需要同时创建公有和私有子网的原因。

**总结**:

整个过程是“先创建网络，再安装集群”。您通过 CloudFormation 模板预置好网络基础设施，然后通过修改 `install-config.yaml` 文件，将网络信息“喂”给 OpenShift 安装程序，引导它在您指定的、已存在的 VPC 环境中完成集群的部署。

---

example output:

```bash
❯ ./get-vpc-outputs.sh weli-private-cluster-vpc
Querying stack 'weli-private-cluster-vpc' in region 'us-east-1' for outputs...
----------------------------------------------------------------
Copy the following block and paste it under 'platform.aws' in your install-config.yaml
----------------------------------------------------------------
    vpcID: vpc-0439f81b789b415f4
    subnets:
    - subnet-02115a41d6cbeb8b8
    - subnet-0eb73e4781c6dad39
----------------------------------------------------------------
```

---

`openshift-install` 已经将您的集群名称截断为 `weli-test-private-clu`。为了保持一致，我们在创建堡垒机时也应该使用这个截断后的名称。

我现在将使用以下信息执行 `create-bastion-host.sh` 脚本：

- __VPC ID__: `vpc-0439f81b789b415f4`
- __Public Subnet ID__: `subnet-029dcd0c8f4949a2c`
- __Cluster Name__: `weli-test-private-clu`

---

