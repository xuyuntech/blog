---
title: 使用 CNS (Container Native Storage) 作为容器存储 - 第三部分
date: 2018-01-10 13:04:59
tags:
- Container Native Storage
- 容器存储
---
![](https://keithtenzer.files.wordpress.com/2017/03/storage_article_008.jpg?w=880)

## 概览
在这篇文章里我们将介绍一个容器存储的新领域 -- Container Native Storage。这篇文章是由 Daniel Messer (Technical Marketing Manager Storage @RedHat) 和 Keith Tenzer (Sr. Solutions Architect @RedHat) 合作完成的。

那么什么是 Container Native Storage ?

本质上，Container Native Storage 是在容器的上下文里存储和计算的一种超融合方式。每一个提供计算和存储资源的容器主机或者节点机允许存储能够完全集成或者融合进平台本身当中。一个在平台上容器里运行的软件化的存储系统，能够在消耗节点机所提供的硬盘的同时也能提供集群化的存储抽象层，并且能够提供一些像高可用、动态绑定和一般存储管理的能力。这将使得存储层面的 DevOps 成为可能，也将让存储随着容器平台的增长而增长并且拥有很高的效率。

## Container Native Storage 概览
CNS 由容器化的 GlusterFS 实现，部署在 OpenShift 或者 Kubernetes 集群上并使用平台提供的容器编排功能。为了集成存储绑定框架，这里使用了一个额外的管理模块叫 heketi 。它提供 API 和前台 CLI 来操作存储生命周期。另外它还提供多部署情景。Heketi 容器跟 GlusterFS 一起跑在 OpenShift 或者 Kubernetes 集群当中。它的所有部署过程都使用 cns-deploy 来完成。

## Container Native Storage 先决条件
目前有很多容器编排技术比如：Docker Swarm, Marathon (Mesos), Diego (CloudFoundry) 和 Kubernetes (OpenShift) 等。Container Native Storage 使用 Kubernetes 和 OpenShift 是因为 Kubernetes 同时支持有状态和无状态应用。你需要一个 OpenShift 集群才能使用 CNS 。[这篇文章](https://keithtenzer.com/2017/03/13/openshift-enterprise-3-4-all-in-one-lab-environment/) 介绍了如何安装 OpenShift 。由于文章关注点在 all-in-one 设置上，所以你只需要一个 VM 做一些小的更改就可以了。

#### 创建 3 个 VMs 的最小集群
每个 VM 应该拥有如下配置：
* RHEL 7.2 or 7.3
* 2 vCPUs
* 4GB RAM
* 30 GB Root Disk
* 25 GB Docker Disk
* 3 x 20GB CNS Disks

#### 更新 OpenShift
由于这篇文章只应用了单个 VM，所以我们需要将节点机扩展到 3 个。
```
...
# host group for masters
[masters]
ose3-master.lab.com

# host group for nodes, includes region info
[nodes]
ose3-master.lab.com openshift_schedulable=True
ose3-node1.lab.com
ose3-node2.lab.com
...
```
一旦 OpenShift 部署成功，你将看到 3 个节点机是 ready 状态。
```
# oc get nodes
NAME STATUS AGE
ose3-master.lab.com Ready 5m
ose3-node1.lab.com Ready 5m
ose3-node2.lab.com Ready 5m
```
## 安装并配置 Container Native Storage
以下这些步骤应该在 OpenShift 的 master 和 node 上都运行。
#### 开启 CNS 仓库
```
subscription-manager repos --enable=rh-gluster-3-for-rhel-7-server-rpms
```
#### 安装 CNS 工具
```
yum install cns-deploy heketi-client
```
#### 更新防火墙规则
在 OpenShift 的所有节点机上。
```
# vi /etc/sysconfig/iptables
...
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 24007 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 24008 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 2222 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m multiport --dports 49152:49664 -j ACCEPT
...
```
```
# systemctl reload iptables
```
#### 在 OpenShift 上创建 CNS 项目
```
oc new-project storage-project
```
#### 开启容器 priviledged 权限
```
# oadm policy add-scc-to-user privileged -z default
```
```
# oadm policy add-scc-to-user privileged -z router
```
```
# oadm policy add-scc-to-user privileged -z default
```
#### 更新路由 dnsmasq
在 OpenShift 主节点上我们需要设置通往 node 节点的外部解决方案。如果你有一个真实的 DNS 服务器，应该在这里处理。
```
# vi /etc/dnsmasq.conf
...
address=/.apps.lab.com/192.168.122.61
...
```
```
# systectl restart dnsmasq
```
#### 增加 localhost nameserver
```
# vi /etc/resolv.conf
...
nameserver 127.0.0.1
...
```
#### 创建 CNS 的配置模板
模板里指明了 CNS 集群里的所有节点，也指定了所使用到的 devices 。CNS 至少需要 3 个节点。数据会默认复制 3 份。
```
# cp /usr/share/heketi/topology-sample.json vi /usr/share/heketi/topology.json
```
```
# vi /usr/share/heketi/topology.json
{
    "clusters": [
        {
            "nodes": [
                {
                    "node": {
                        "hostnames": {
                            "manage": [
                                "ose3-master.lab.com"
                            ],
                            "storage": [
                                "192.168.122.61"
                            ]
                        },
                        "zone": 1
                    },
                    "devices": [
                        "/dev/vdc",
                        "/dev/vdd",
                        "/dev/vde"
                    ]
                },
                {
                    "node": {
                        "hostnames": {
                            "manage": [
                                "ose3-node1.lab.com"
                            ],
                            "storage": [
                                "192.168.122.62"
                            ]
                        },
                        "zone": 2
                    },
                    "devices": [
                        "/dev/vdc",
                        "/dev/vdd",
                        "/dev/vde"
                    ]
                },
                {
                    "node": {
                        "hostnames": {
                            "manage": [
                                "ose3-node2.lab.com"
                            ],
                            "storage": [
                                "192.168.122.63"
                            ]
                        },
                        "zone": 2
                    },
                    "devices": [
                        "/dev/vdc",
                        "/dev/vdd",
                        "/dev/vde"
                    ]
                }
            ]
        }
    ]
}
```
#### 部署 Container Native Storage
```
# cns-deploy -n storage-project -g /usr/share/heketi/topology.json
 Welcome to the deployment tool for GlusterFS on Kubernetes and OpenShift.

Before getting started, this script has some requirements of the execution
 environment and of the container platform that you should verify.

The client machine that will run this script must have:
 * Administrative access to an existing Kubernetes or OpenShift cluster
 * Access to a python interpreter 'python'
 * Access to the heketi client 'heketi-cli'

Each of the nodes that will host GlusterFS must also have appropriate firewall
 rules for the required GlusterFS ports:
 * 2222 - sshd (if running GlusterFS in a pod)
 * 24007 - GlusterFS Daemon
 * 24008 - GlusterFS Management
 * 49152 to 49251 - Each brick for every volume on the host requires its own
 port. For every new brick, one new port will be used starting at 49152. We
 recommend a default range of 49152-49251 on each host, though you can adjust
 this to fit your needs.

In addition, for an OpenShift deployment you must:
 * Have 'cluster_admin' role on the administrative account doing the deployment
 * Add the 'default' and 'router' Service Accounts to the 'privileged' SCC
 * Have a router deployed that is configured to allow apps to access services
 running in the cluster

Do you wish to proceed with deployment?

[Y]es, [N]o? [Default: Y]: Y
 Multiple CLI options detected. Please select a deployment option.
 [O]penShift, [K]ubernetes? [O/o/K/k]: O
 Using OpenShift CLI.
 NAME STATUS AGE
 storage-project Active 4m
 Using namespace "storage-project".
 template "deploy-heketi" created
 serviceaccount "heketi-service-account" created
 template "heketi" created
 template "glusterfs" created
 node "ose3-master.lab.com" labeled
 node "ose3-node1.lab.com" labeled
 node "ose3-node2.lab.com" labeled
 daemonset "glusterfs" created
 Waiting for GlusterFS pods to start ... OK
 service "deploy-heketi" created
 route "deploy-heketi" created
 deploymentconfig "deploy-heketi" created
 Waiting for deploy-heketi pod to start ... OK
 % Total % Received % Xferd Average Speed Time Time Time Current
 Dload Upload Total Spent Left Speed
 100 17 100 17 0 0 864 0 --:--:-- --:--:-- --:--:-- 894
 Creating cluster ... ID: 4bfec05e6fa80e5178c4314bec238786
 Creating node ose3-master.lab.com ... ID: f95eabc360cddd6f5c6419094c1ae085
 Adding device /dev/vdc ... OK
 Adding device /dev/vdd ... OK
 Adding device /dev/vde ... OK
 Creating node ose3-node1.lab.com ... ID: 82fa6bf3a37dffa4376c77935f37d44a
 Adding device /dev/vdc ... OK
 Adding device /dev/vdd ... OK
 Adding device /dev/vde ... OK
 Creating node ose3-node2.lab.com ... ID: c26872fc64f2408f2ddea664698e3964
 Adding device /dev/vdc ... OK
 Adding device /dev/vdd ... OK
 Adding device /dev/vde ... OK
 Saving heketi-storage.json
 secret "heketi-storage-secret" created
 endpoints "heketi-storage-endpoints" created
 service "heketi-storage-endpoints" created
 job "heketi-storage-copy-job" created
 deploymentconfig "deploy-heketi" deleted
 route "deploy-heketi" deleted
 service "deploy-heketi" deleted
 pod "deploy-heketi-1-z8ite" deleted
 job "heketi-storage-copy-job" deleted
 secret "heketi-storage-secret" deleted
 service "heketi" created
 route "heketi" created
 deploymentconfig "heketi" created
 Waiting for heketi pod to start ... OK
 % Total % Received % Xferd Average Speed Time Time Time Current
 Dload Upload Total Spent Left Speed
 100 17 100 17 0 0 2766 0 --:--:-- --:--:-- --:--:-- 2833
 heketi is now running.
 ```
 列出所有存储节点

 一旦部署完成，你将看到 3 个 GlusterFS 节点 pod ，heketi pod （CNS 管理节点）作为路由。

 ```
 # oc get pods -o wide
 NAME READY STATUS RESTARTS AGE IP NODE
 glusterfs-eedk4 1/1 Running 0 4m 192.168.122.63 ose3-node2.lab.com
 glusterfs-kyrz1 1/1 Running 0 4m 192.168.122.62 ose3-node1.lab.com
 glusterfs-y6w8n 1/1 Running 0 4m 192.168.122.61 ose3-master.lab.com
 heketi-1-zq0ie 1/1 Running 0 2m 10.129.0.10 ose3-master.lab.com
 storage-project-router-1-nnobe 1/1 Running 0 8m 192.168.122.61 ose3-master.lab.com
```
#### 设置 Heketi CLI
Heketi 是 CNS 的管理工具。需要 export path 来使用 CLI。
```
# export HEKETI_CLI_SERVER=$(oc describe svc/heketi | grep "Endpoints:" | awk '{print "http://"$2}')
```
```
# echo $HEKETI_CLI_SERVER
http://10.129.0.10:8080
```
#### CNS 拓扑结构
```
# heketi-cli topology info

Cluster Id: 4bfec05e6fa80e5178c4314bec238786

Volumes:

Name: heketidbstorage
 Size: 2
 Id: e64a8b64f58bf5248afdb1db34ba420f
 Cluster Id: 4bfec05e6fa80e5178c4314bec238786
 Mount: 192.168.122.61:heketidbstorage
 Mount Options: backup-volfile-servers=192.168.122.62,192.168.122.63
 Durability Type: replicate
 Replica: 3
 Snapshot: Disabled

Bricks:
 Id: 2504dbb5b0b9fd38c3c8eaa25c19e6e0
 Path: /var/lib/heketi/mounts/vg_4b315e3d01f3398ea371cc3ec44a46ab/brick_2504dbb5b0b9fd38c3c8eaa25c19e6e0/brick
 Size (GiB): 2
 Node: f95eabc360cddd6f5c6419094c1ae085
 Device: 4b315e3d01f3398ea371cc3ec44a46ab

Id: 30fea25c05c3c7b252590b81c3f38369
 Path: /var/lib/heketi/mounts/vg_001e9e13cf06727862b157283b22051d/brick_30fea25c05c3c7b252590b81c3f38369/brick
 Size (GiB): 2
 Node: c26872fc64f2408f2ddea664698e3964
 Device: 001e9e13cf06727862b157283b22051d

Id: d7c2b9e7b80ed2726309ad516dd253cf
 Path: /var/lib/heketi/mounts/vg_4f8745833e2577ff9a1eb302d9811551/brick_d7c2b9e7b80ed2726309ad516dd253cf/brick
 Size (GiB): 2
 Node: 82fa6bf3a37dffa4376c77935f37d44a
 Device: 4f8745833e2577ff9a1eb302d9811551
 Nodes:

Node Id: 82fa6bf3a37dffa4376c77935f37d44a
 State: online
 Cluster Id: 4bfec05e6fa80e5178c4314bec238786
 Zone: 2
 Management Hostname: ose3-node1.lab.com
 Storage Hostname: 192.168.122.62
 Devices:
 Id:26333a53457037df86243d164d280f07 Name:/dev/vdc State:online Size (GiB):29 Used (GiB):0 Free (GiB):29
 Bricks:
 Id:4f8745833e2577ff9a1eb302d9811551 Name:/dev/vde State:online Size (GiB):29 Used (GiB):2 Free (GiB):27
 Bricks:
 Id:d7c2b9e7b80ed2726309ad516dd253cf Size (GiB):2 Path: /var/lib/heketi/mounts/vg_4f8745833e2577ff9a1eb302d9811551/brick_d7c2b9e7b80ed2726309ad516dd253cf/brick
 Id:c1520ae2b0adbf0fec0b0ffd5fd5a0f7 Name:/dev/vdd State:online Size (GiB):29 Used (GiB):0 Free (GiB):29
 Bricks:

Node Id: c26872fc64f2408f2ddea664698e3964
 State: online
 Cluster Id: 4bfec05e6fa80e5178c4314bec238786
 Zone: 2
 Management Hostname: ose3-node2.lab.com
 Storage Hostname: 192.168.122.63
 Devices:
 Id:001e9e13cf06727862b157283b22051d Name:/dev/vde State:online Size (GiB):29 Used (GiB):2 Free (GiB):27
 Bricks:
 Id:30fea25c05c3c7b252590b81c3f38369 Size (GiB):2 Path: /var/lib/heketi/mounts/vg_001e9e13cf06727862b157283b22051d/brick_30fea25c05c3c7b252590b81c3f38369/brick
 Id:705d793971aeb2c3315ea674af0aace1 Name:/dev/vdd State:online Size (GiB):29 Used (GiB):0 Free (GiB):29
 Bricks:
 Id:cc542ecd46d872a8db41819f2f9f69fe Name:/dev/vdc State:online Size (GiB):29 Used (GiB):0 Free (GiB):29
 Bricks:

Node Id: f95eabc360cddd6f5c6419094c1ae085
 State: online
 Cluster Id: 4bfec05e6fa80e5178c4314bec238786
 Zone: 1
 Management Hostname: ose3-master.lab.com
 Storage Hostname: 192.168.122.61
 Devices:
 Id:4b315e3d01f3398ea371cc3ec44a46ab Name:/dev/vdd State:online Size (GiB):29 Used (GiB):2 Free (GiB):27
 Bricks:
 Id:2504dbb5b0b9fd38c3c8eaa25c19e6e0 Size (GiB):2 Path: /var/lib/heketi/mounts/vg_4b315e3d01f3398ea371cc3ec44a46ab/brick_2504dbb5b0b9fd38c3c8eaa25c19e6e0/brick
 Id:dc37c4b891c0268f159f1b0b4b21be1e Name:/dev/vde State:online Size (GiB):29 Used (GiB):0 Free (GiB):29
 Bricks:
 Id:fab4c9f1f82010164a26ba162411211a Name:/dev/vdc State:online Size (GiB):29 Used (GiB):0 Free (GiB):29
 Bricks:
 ```
 ## 在 OpenShift 里使用 CNS
 使用 storage class 来创建 persistent volumes。Storage Class 为 Kubernetes（OpenShift）提供访问存储系统的权限。

 #### 创建 Storage Class
 Storage Class 就想 Kubernetes 其他的对象一样由 YAML 或 JSON 定义：
 ```
 # vi /root/glusterfs-storage-class.yaml

apiVersion: storage.k8s.io/v1beta1
 kind: StorageClass
 metadata:
 name: glusterfs-container
 provisioner: kubernetes.io/glusterfs
 parameters:
 resturl: "http://10.129.0.10:8080"
 restuser: "admin"
 secretNamespace: "default"
 secretName: "heketi-secret"
 ```
 用 oc 命令从 YAML 创建 Storage Class
 ```
 # oc create -f /root/glusterfs-storage-class.yaml
 ```
 #### 设置 Secret
 Secret 在 OpenShift 中为 Services 提供访问权限。

 创建密码
 ```
 # echo -n "mypassword" | base64
bXlwYXNzd29yZA==
```
为 CNS 创建 Secret
```
# vi /root/glusterfs-secret.yaml

apiVersion: v1
 kind: Secret
 metadata:
 name: heketi-secret
 namespace: default
 data:
 key: bXlwYXNzd29yZA==
 type: kubernetes.io/glusterfs
 ```
 使用 YAML 创建
 ```
 # oc create -f glusterfs-secret.yaml
 ```
 #### 使用 CLI 创建 Persistent Volume Claim
 Persistent volume claim 是开发者在使用存储的时候需要交互的对象。它将 persistent volume 绑定到 pod 上。在这里，由于 CNS 支持动态存储供应，所以创建一个 claim 的同时也会创建一个供应存储的卷。

 ```
 #vi /root/glusterfs-pvc-1.yaml
{
  "kind": "PersistentVolumeClaim",
  "apiVersion": "v1",
  "metadata": {
    "name": "claim1",
    "annotations": {
        "volume.beta.kubernetes.io/storage-class": "glusterfs-container"
    }
  },
  "spec": {
    "accessModes": [
      "ReadWriteOnce"
    ],
    "resources": {
      "requests": {
        "storage": "4Gi"
      }
    }
  }
}
```
展示  Persistent Volume Claim
```
# oc get pvc
NAME STATUS VOLUME CAPACITY ACCESSMODES AGE
claim1 Bound pvc-6b4599fa-0813-11e7-a395-525400c9c97e 4Gi RWO 13s
```
展示 Persistent Volume
```
# oc get pv
NAME CAPACITY ACCESSMODES RECLAIMPOLICY STATUS CLAIM REASON AGE
pvc-6b4599fa-0813-11e7-a395-525400c9c97e 4Gi RWO Delete Bound storage-project/claim1 2m
```
使用 Persistent Volume Claim

开发者一旦拥有了 claim，就只需要将 ClaimName 添加到 POD 的 YAML 文件里。
```
apiVersion: v1
kind: Pod
metadata:
  name: busybox
spec:
  containers:
    - image: busybox
      command:
        - sleep
        - "3600"
      name: busybox
      volumeMounts:
        - mountPath: /usr/share/busybox
          name: mypvc
  volumes:
    - name: mypvc
      persistentVolumeClaim:
        claimName: claim1
```
#### 使用 GUI 创建 Persistent Volume Claim
在 OpenShift 里的项目下面，选择最右边的 Storage 和 Create Storage 按钮。填写 name, access mode 和 size 。点击 create ，OpenShift 将会创建 persistent volume 和 persistent volume claim。

![](https://keithtenzer.files.wordpress.com/2017/03/ose_prov_storage.png?w=880)

一旦 persistent volume claim 创建好了，在 storage tab 下面将会显示。

![](https://keithtenzer.files.wordpress.com/2017/03/ose_storage.png?w=880)

这时你就可以将这个 persistent volume claim 使用到任何 pod 中了。

另一种方式就是使用预定义模板。这里我们将使用 ‘mariadb-persistent’部署一个 mariadb .

创建新项目 ‘mariadb’。

![](https://keithtenzer.files.wordpress.com/2017/03/mariadb_project.png?w=880)

目录搜索框中输入 'mariadb' ，选择 'MariadDB (Persistent)'

![](https://keithtenzer.files.wordpress.com/2017/03/mariadb_1.png?w=880)

下一屏中选择默认配置启动 pod 。 这时由于持久卷还没有被映射到 storage class 中，所以 pod 就一直是 pending 状态。当然这里就由 storage class 来控制。为了指定一个默认的集群维度的 storage class，需要更新 storage class 的 annotations。
```
...
annotations:
  storageclass.beta.kubernetes.io/is-default-class: true
...
```
![](https://keithtenzer.files.wordpress.com/2017/03/mariadb_2.png)

在 storage 标签下面选择 persistent volume claim ‘mariadb’。在右下方的动作条里选择 edit yaml 。然后编辑 persistent volume claim yaml 文件。
```
...
annotations:
 volume.beta.kubernetes.io/storage-class: glusterfs-container
...
```
![](https://keithtenzer.files.wordpress.com/2017/03/mariadb_4.png?w=880)

点击 save 按钮之后，可以看到一会儿数据卷就会成为 bound 状态。这就表示 OpenShift 从 CNS 中供应了一个持久卷。
![](https://keithtenzer.files.wordpress.com/2017/03/mariadb_51.png?w=880)

最后 mariadb pod 也应该跑起来了。

![](https://keithtenzer.files.wordpress.com/2017/03/mariadb_6.png)

## 深入研究 CNS
现在我们能看到 OpenShift 能让我们近距离了解存储本身并且理解持久卷是如何映射到 GlusterFS 卷上的 。

#### 获得 Glusterfs 卷

如果我们查看 persistent volume (pv) 的 yaml 文件，我们可以看到 GlusterFS 卷。

```
# oc get pv pvc-acbade81-0818-11e7-a395-525400c9c97e -o yaml
 apiVersion: v1
 kind: PersistentVolume
 metadata:
 annotations:
 pv.beta.kubernetes.io/gid: "2001"
 pv.kubernetes.io/bound-by-controller: "yes"
 pv.kubernetes.io/provisioned-by: kubernetes.io/glusterfs
 volume.beta.kubernetes.io/storage-class: glusterfs-container
 creationTimestamp: 2017-03-13T18:12:59Z
 name: pvc-acbade81-0818-11e7-a395-525400c9c97e
 resourceVersion: "10271"
 selfLink: /api/v1/persistentvolumes/pvc-acbade81-0818-11e7-a395-525400c9c97e
 uid: b10085a3-0818-11e7-a395-525400c9c97e
 spec:
 accessModes:
 - ReadWriteOnce
 capacity:
 storage: 1Gi
 claimRef:
 apiVersion: v1
 kind: PersistentVolumeClaim
 name: mariadb
 namespace: my-ruby
 resourceVersion: "10262"
 uid: acbade81-0818-11e7-a395-525400c9c97e
 glusterfs:
 endpoints: gluster-dynamic-mariadb
 path: vol_094f7fc95d623fdc88c72aa5cb303b24
 persistentVolumeReclaimPolicy: Delete
 status:
 phase: Bound
 ```
 #### 链接 Glusterfs 节点

 在项目 storage-project 中，我们可以获得 GlusterFS 的 pod。这些是 cns-deploy 初始化安装的时候创建的 pod 。他们是带有 node selector 的 Kubernetes DaemonSet 。所有拥有 storagenode=glusterfs selector 的节点都属于 DearmonSet ，也因此会跑一个 GlusterFS pod 。这也方便后期扩充额外的 pod。

 ```
 # oc project storage-project
 Already on project "storage-project" on server "https://ose3-master2.lab.com:8443".
 ```
 ```
 # oc get pods
NAME READY STATUS RESTARTS AGE
glusterfs-eedk4 1/1 Running 0 1h
glusterfs-kyrz1 1/1 Running 0 1h
glusterfs-y6w8n 1/1 Running 0 1h
heketi-1-zq0ie 1/1 Running 0 1h
storage-project-router-1-nnobe 1/1 Running 0 1h
```

使用 oc 命令链接 glusterfs 节点上的 pod 。

```
# oc exec -ti glusterfs-eedk4 /bin/sh
```

#### 列出 Gluster Volumes

在一个 GlusterFS 节点上，我们可以列出所有的卷。我们可以在下面的高亮处看到卷的名称和挂载点。

```
sh-4.2# gluster volume info all

Volume Name: heketidbstorage
 Type: Replicate
 Volume ID: 17779abc-870d-4f4f-9e29-60eea6d5e01e
 Status: Started
 Number of Bricks: 1 x 3 = 3
 Transport-type: tcp
 Bricks:
 Brick1: 192.168.122.63:/var/lib/heketi/mounts/vg_001e9e13cf06727862b157283b22051d/brick_30fea25c05c3c7b252590b81c3f38369/brick
 Brick2: 192.168.122.61:/var/lib/heketi/mounts/vg_4b315e3d01f3398ea371cc3ec44a46ab/brick_2504dbb5b0b9fd38c3c8eaa25c19e6e0/brick
 Brick3: 192.168.122.62:/var/lib/heketi/mounts/vg_4f8745833e2577ff9a1eb302d9811551/brick_d7c2b9e7b80ed2726309ad516dd253cf/brick
 Options Reconfigured:
 performance.readdir-ahead: on

Volume Name: vol_094f7fc95d623fdc88c72aa5cb303b24
 Type: Replicate
 Volume ID: e29be8b3-b733-4c2e-a536-70807d948fd6
 Status: Started
 Number of Bricks: 1 x 3 = 3
 Transport-type: tcp
 Bricks:
 Brick1: 192.168.122.63:/var/lib/heketi/mounts/vg_cc542ecd46d872a8db41819f2f9f69fe/brick_818bd64213310df8f7fa6b05734d882d/brick
 Brick2: 192.168.122.62:/var/lib/heketi/mounts/vg_c1520ae2b0adbf0fec0b0ffd5fd5a0f7/brick_be228a22ac79112b7474876211e0686f/brick
 Brick3: 192.168.122.61:/var/lib/heketi/mounts/vg_fab4c9f1f82010164a26ba162411211a/brick_635253e7ef1e8299b993a273fa808cf6/brick
 Options Reconfigured:
 performance.readdir-ahead: on

Volume Name: vol_e462bd9fa459d0ba088198892625e00d
 Type: Replicate
 Volume ID: 9272b326-bf9c-4a6a-b570-d43c6e2cba83
 Status: Started
 Number of Bricks: 1 x 3 = 3
 Transport-type: tcp
 Bricks:
 Brick1: 192.168.122.63:/var/lib/heketi/mounts/vg_705d793971aeb2c3315ea674af0aace1/brick_165ecbfd4e8923a8efcb8d733a601971/brick
 Brick2: 192.168.122.62:/var/lib/heketi/mounts/vg_c1520ae2b0adbf0fec0b0ffd5fd5a0f7/brick_4008026414bf63a9a7c26ac7cd09cf16/brick
 Brick3: 192.168.122.61:/var/lib/heketi/mounts/vg_fab4c9f1f82010164a26ba162411211a/brick_003626574ffc4c9c96f22f7cda5ea8af/brick
 Options Reconfigured:
 performance.readdir-ahead: on

Look for local mount usi
 sh-4.2# mount | grep heketi
 /dev/mapper/rhel-root on /var/lib/heketi type xfs (rw,relatime,seclabel,attr2,inode64,noquota)
 /dev/mapper/vg_001e9e13cf06727862b157283b22051d-brick_30fea25c05c3c7b252590b81c3f38369 on /var/lib/heketi/mounts/vg_001e9e13cf06727862b157283b22051d/brick_30fea25c05c3c7b252590b81c3f38369 type xfs (rw,noatime,seclabel,nouuid,attr2,inode64,logbsize=256k,sunit=512,swidth=512,noquota)
 /dev/mapper/vg_705d793971aeb2c3315ea674af0aace1-brick_165ecbfd4e8923a8efcb8d733a601971 on /var/lib/heketi/mounts/vg_705d793971aeb2c3315ea674af0aace1/brick_165ecbfd4e8923a8efcb8d733a601971 type xfs (rw,noatime,seclabel,nouuid,attr2,inode64,logbsize=256k,sunit=512,swidth=512,noquota)
 /dev/mapper/vg_cc542ecd46d872a8db41819f2f9f69fe-brick_818bd64213310df8f7fa6b05734d882d on /var/lib/heketi/mounts/vg_cc542ecd46d872a8db41819f2f9f69fe/brick_818bd64213310df8f7fa6b05734d882d type xfs (rw,noatime,seclabel,nouuid,attr2,inode64,logbsize=256k,sunit=512,swidth=512,noquota)
 ```
 #### 列出挂载点内容
 可以使用 ls 来列出挂点在的内容。这里我们可以看到 mariadb 的文件。
 ```
 sh-4.2# ls /var/lib/heketi/mounts/vg_cc542ecd46d872a8db41819f2f9f69fe/brick_818bd64213310df8f7fa6b05734d882d/brick/
aria_log.00000001 aria_log_control ib_logfile0 ib_logfile1 ibdata1 mariadb-1-wwuu4.pid multi-master.info mysql performance_schema sampledb tc.log test
```

## 总结
本文我们主要关注 Container Native Storage (CNS). 我们讨论了需要使用 CNS 来讲存储集成到 DevOps 里。令人兴奋的是，通过 CNS 使得存储能够成为 DevOps 里的头等公民，而不是采用传统的存储方式以某种方式来插拔使用。我们探索了 CNS 在 OpenShift 上的先决条件，并且安装并配置。通过 CLI 和 GUI 我们看到开发者如果在 OpenShift 上通过 CNS 来管理存储。最后我们进一步探讨了 CNS 如何在 OpenShift 中映射到 pvc 上。希望你能喜欢这篇文章并从中学到有用的东西。

Container Native Storaging 愉快！
