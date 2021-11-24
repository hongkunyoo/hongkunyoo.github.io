---
layout: post
title:  "[번역]쿠버네티스 패킷의 삶 - #2"
date:   2021-11-15 00:00:00
categories: kubernetes network
image: /assets/images/packet-life/landing02.png
permalink: /:title
---
[쿠버네티스 패킷의 삶 #1](/packet-network1)에서 살펴 봤듯이, CNI plugin은 쿠버네티스 네트워킹에서 중요한 역할을 차지합니다. 현재 많은 CNI plugin 구현체들이 존재합니다. 그 중 Calico를 소개합니다. 많은 엔지니어들은 Calico를 선호합니다. 그 이유는 Calico는 네트워크 구성을 간단하게 만들어 주기 때문입니다.

## 쿠버네티스 패킷의 삶 시리즈

1. [컨테이너 네트워킹과 CNI](): 리눅스 네트워크 namespace와 CNI 기초
2. Calico CNI: CNI 구현체 중 하나인, Calico CNI 네트워킹
3. [Pod 네트워킹](): Pod간, 클러스터 내/외부 네트워킹 설명
4. [Ingress](): Ingress Controller에 대한 설명

---

Calico는 다양한 플랫폼들을 지원합니다. 쿠버네티스, 오픈시프트, 도커EE, 오픈스택 그리고 베어메탈 서비스들을 지원합니다. Calico node는 쿠버네티스의 마스터 노드와 워커 노드에 각각 컨테이너로 실행되어 동작합니다. `calico-cni` plugin은 컨테이너가 각 노드에 생성될 때, 쿠버네티스 kubelet과 직접적으로 연결되어 동작합니다. 

이번 포스트에서 Calico를 설치하는 방법, Calico의 모듈들(Felix, BIRD, and Confd)과 라우팅 모드에 대해서 알아보도록 하겠습니다. Calico에는 네트워크 정책(Network Policy)을 적용하는 기능도 있지만 이번 포스트에서는 넘어가고 다음 포스트에서 다루도록 하겠습니다.

- CNI 요구사항
- Calico 모듈과 그 기능들
- 라우팅 모드
- 라우팅 모드별 설정 방법

## CNI 요구사항

1. veth 페어 생성 및 컨테이너 네트워크 인터페이스와 연결
2. Pod 네트워크 대역 확인 후 IP 설정
3. CNI 설정 파일 작성
4. IP 설정 및 관리
5. 컨테이너 내 기본 라우팅 정보 삽입 (default route rule)
6. 동료 노드들에게 IP 라우팅 정보 전달(advertising the routes)
7. 호스트 서버에 라우팅 정보 삽입
8. 네트워크 정책에 따라 트래픽 처리

사실 이 외에도 더 많은 요구사항들이 있지만 기본적인 요구사항들에 대해서 위와 같이 살펴 볼 수 있습니다. 이제 마스터와 워커 노드의 라우팅 테이블을 살펴 보겠습니다. 각 노드에는 컨테이너마다 저마다의 IP주소와 default route가 있습니다.

![](/assets/images/packet-life/02-01.png)

라우팅 테이블을 살펴 보면, 각각의 라우팅 테이블의 라우트 정보가 완벽하기 때문에 `Pod`가 특별한 지원 없이 L3 네트워크를 타고 서로 통신할 수 있다는 것을 확인할 수 있습니다. 어떤 모듈이 이런 라우팅 정보를 각 라우팅 테이블에 삽입하는 책임을 가졌을까요? 그리고 더 중요한 것은 어떻게 다른 노드에 들어 있는 라우팅 정보를 알아서 삽입할 수 있을까요? 마지막으로 디폴트 라우트는 왜 `169.254.1.1`라는 IP를 가진 G/W로 설정되어 있을까요? 하나씩 확인해 봅시다.

먼저 Calico의 핵심 컴포넌트들은 다음과 같습니다: Bird, Felix, ConfD, Etcd 그리고 쿠버네티스 API서버입니다. Calico의 데이터 저장소는 ip-pools, endpoint 정보, 네트워크 정책 정보들을 저장하는데 사용합니다. Calico의 데이터 저장소로 직접 외부 Etcd를 구성하거나 쿠버네티스를 데이터 저장소로 활용할 수 있습니다. 이번 예시에서는 쿠버네티스를 Calico의 데이터 저장소로 사용하겠습니다.

## Calico 모듈과 그 기능들

### BIRD (BGP)

BIRD는 각 노드마다 존재하는 BGP 데몬입니다. 이 데몬은 다른 노드에 있는 BGP 데몬들과 라우팅 정보를 교환합니다. 대표적인 네트워크 구성(topology)으로는 노드별 full mesh가 있습니다. 이 구성은 각 노드끼리 모두 BGP peer를 가집니다.

![](/assets/images/packet-life/02-02.png)

더 큰 규모의 클러스터에서는 이러한 방법에 한계를 가집니다. 그런 경우에는 Route Reflector 방법을 사용하여 일부 노드에서만 라우팅 정보를 전파하는 방법을 사용할 수 있습니다. 모든 노드끼리 peer를 구성하는게 아니라 특정 노드만 Route Reflector(RR)로 구성하여 RR로 설정된 노드와만 통신하여 라우팅 정보를 주고 받는 것입니다. 라우팅 정보를 전파해야 하는 경우 RR로만 전달하면 RR이 자신과 peer를 맺고 있는 BGP로 전파를 합니다. 더 자세한 내용은 RFC4456 문서를 참고하시기 바랍니다.

![](/assets/images/packet-life/02-03.png)

BIRD 데몬은 다른 BIRD 데몬에 라우팅 정보를 전파하는 책임을 가집니다. 그리고 가장 기본적인 설정이 BGP full mesh입니다. 이것은 작은 규모의 클러스터에 적합합니다. 더 큰 규모의 클러스터에서는 Route Reflector 모드로 구성하는 것을 추천드립니다. 한개 이상의 RR을 두어서 가용성을 높힐 수 있고 BIRD 데몬 대신에 외부 물리 장비를 이용하는 방법도 있습니다. (역자주: 외부 물리 장비란, BGB 프로토콜을 수행하는 일반적인 라우터 장비를 의미합니다. 이것을 소프트웨어로 구현한 것이 BIRD라고 생각할 수 있습니다.)

### ConfD

ConfD는 calico-node 컨테이너 안에서 동작하는 간단한 설정관리 툴입니다. 데이터 저장소로부터 BIRD 설정값을 읽어들이고 디스크 파일로 쓰기 작업도 수행합니다. 네트워크와 서브네트워크에 설정값을 반영하고(CIDR 값) BIRD 데몬이 이해할 수 있도록 설정값들을 변환합니다. 그래서 네트워크에 어떠한 변화가 생겼을 때, BIRD가 그 변화를 감지하여 라우팅 정보를 다른 peer로 전파할 수 있는 것입니다.

### Felix

Felix 데몬도 calico-node 컨테이너 안에서 동작하며 다음과 같은 동작을 수행합니다:

- 쿠버네티스 etcd로부터 정보를 읽습니다.
- 라우팅 테이블을 만듭니다.
- iptable을 조작합니다.(kube-proxy가 iptables 모드인 경우)
- ipvs을 조작합니다.(kube-proxy가 ipvs 모드인 경우)

이번에는 Calico 모듈들과 함께 앞서 살펴 본 클러스터 네트워크를 확인해 봅시다.

![](/assets/images/packet-life/02-04.png)

**이번에는 뭔가 다른게 보이나요?**


Something looks different? Yes, the one end of the veth is dangling, not connected anywhere; It is in kernel space.

How the packet gets routed to the peer node?

1. Pod in master tries to ping the IP address 10.0.2.11
2. Pod sends an ARP request to the gateway.
3. Get’s the ARP response with the MAC address.
4. Wait, who sent the ARP response?

What’s going on? How can a container route at an IP that doesn't exist? Let’s walk through what’s happening. Some of you reading this might have noticed that 169.254.1.1 is an IPv4 link-local address. The container has a default route pointing at a link-local address. The container expects this IP address to be reachable on its directly connected interface, in this case, the containers eth0 address. The container will attempt to ARP for that IP address when it wants to route out through the default route.

If we capture the ARP response, it will show the MAC address of the other end of the veth (cali123). So you might be wondering how on earth the host is replying to an ARP request for which it doesn’t have an IP interface. The answer is proxy-arp. If we check the host side VETH interface, we’ll see that proxy-arp is enabled.

```bash
master $ cat /proc/sys/net/ipv4/conf/cali123/proxy_arp
# 1
```

> “Proxy ARP is a technique by which a proxy device on a given network answers the ARP queries for an IP address that is not on that network. The proxy is aware of the location of the traffic’s destination, and offers its own MAC address as the (ostensibly final) destination.[1] The traffic directed to the proxy address is then typically routed by the proxy to the intended destination via another interface or via a tunnel. The process, which results in the node responding with its own MAC address to an ARP request for a different IP address for proxying purposes, is sometimes referred to as publishing”

Let’s take a closer look at the worker node,

![](/assets/images/packet-life/02-05.png)

Once the packet reaches the kernel, it routes the packet based on routing table entries.

#### Incoming traffic

1. The packet reaches the worker node kernel.
2. Kernel puts the packet into the cali123.



## 라우팅 모드

Calico supports 3 routing modes; in this section, we will see the pros and cons of each method and where we can use them.

- IP-in-IP: default; encapsulated
- Direct/NoEncapMode: unencapsulated (Preferred)
- VXLAN: encapsulated (No BGP)

### IP-in-IP (Default)

IP-in-IP is a simple form of encapsulation achieved by putting an IP packet inside another. A transmitted packet contains an outer header with host source and destination IPs and an inner header with pod source and destination IPs.
Azure doesn’t support IP-IP (As far I know); therefore, we can’t use IP-IP in that environment. It’s better to disable IP-IP to get better performance.

### NoEncapMode

In this mode, send packets as if they came directly from the pod. Since there is no encapsulation and de-capsulation overhead, direct is highly performant.

Source IP check must be disabled in AWS to use this mode.

### VXLAN

VXLAN routing is supported in Calico 3.7+.

> VXLAN stands for Virtual Extensible LAN. VXLAN is an encapsulation technique in which layer 2 ethernet frames are encapsulated in UDP packets. VXLAN is a network virtualization technology. When devices communicate within a software-defined Datacenter, a VXLAN tunnel is set up between those devices. Those tunnels can be set up on both physical and virtual switches. The switch ports are known as VXLAN Tunnel Endpoints (VTEPs) and are responsible for the encapsulation and de-encapsulation of VXLAN packets. Devices without VXLAN support are connected to a switch with VTEP functionality. The switch will provide the conversion from and to VXLAN.

VXLAN is great for networks that do not support IP-in-IP, such as Azure or any other DC that doesn’t support BGP.

![](/assets/images/packet-life/02-06.png)


## 라우팅 모드별 설정 방법


### IPIP and UnEncapMode

Check the cluster state before the Calico installation.

```bash
master $ kubectl get nodes
# NAME           STATUS     ROLES    AGE   VERSION
# controlplane   NotReady   master   40s   v1.18.0
# node01         NotReady   <none>   9s    v1.18.0

master $ kubectl get pods --all-namespaces
# NAMESPACE     NAME                                   READY   STATUS    RESTARTS   AGE
# kube-system   coredns-66bff467f8-52tkd               0/1     Pending   0          32s
# kube-system   coredns-66bff467f8-g5gjb               0/1     Pending   0          32s
# kube-system   etcd-controlplane                      1/1     Running   0          34s
# kube-system   kube-apiserver-controlplane            1/1     Running   0          34s
# kube-system   kube-controller-manager-controlplane   1/1     Running   0          34s
# kube-system   kube-proxy-b2j4x                       1/1     Running   0          13s
# kube-system   kube-proxy-s46lv                       1/1     Running   0          32s
# kube-system   kube-scheduler-controlplane            1/1     Running   0          33s
```

Check the CNI bin and conf directory. There won’t be any configuration file or the calico binary as the calico installation would populate these via volume mount.

```bash
master $ cd /etc/cni
-bash: cd: /etc/cni: No such file or directory
master $ cd /opt/cni/bin
master $ ls
bridge  dhcp  flannel  host-device  host-local  ipvlan  loopback  macvlan  portmap  ptp  sample  tuning  vlan
```

Check the IP routes in the master/worker node.

```bash
master $ ip route
# default via 172.17.0.1 dev ens3
# 172.17.0.0/16 dev ens3 proto kernel scope link src 172.17.0.32
# 172.18.0.0/24 dev docker0 proto kernel scope link src 172.18.0.1 linkdown

curl https://docs.projectcalico.org/manifests/calico.yaml -O

# Download and apply the calico.yaml based on your environment.
curl https://docs.projectcalico.org/manifests/calico.yaml -O
kubectl apply -f calico.yaml
```

Let’s take a look at some useful configuration parameters,

```bash
cni_network_config: |-
    {
      "name": "k8s-pod-network",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "calico", >>> Calico's CNI plugin
          "log_level": "info",
          "log_file_path": "/var/log/calico/cni/cni.log",
          "datastore_type": "kubernetes",
          "nodename": "__KUBERNETES_NODE_NAME__",
          "mtu": __CNI_MTU__,
          "ipam": {
              "type": "calico-ipam" >>> Calico's IPAM instaed of default IPAM
          },
          "policy": {
              "type": "k8s"
          },
          "kubernetes": {
              "kubeconfig": "__KUBECONFIG_FILEPATH__"
          }
        },
        {
          "type": "portmap",
          "snat": true,
          "capabilities": {"portMappings": true}
        },
        {
          "type": "bandwidth",
          "capabilities": {"bandwidth": true}
        }
      ]
    }
# Enable IPIP
- name: CALICO_IPV4POOL_IPIP
    value: "Always" >> Set this to 'Never' to disable IP-IP
# Enable or Disable VXLAN on the default IP pool.
- name: CALICO_IPV4POOL_VXLAN
    value: "Never"
```

Check POD and Node status after the calico installation.

```bash
master $ kubectl get pods --all-namespaces
# NAMESPACE     NAME                                       READY   STATUS              RESTARTS   AGE
# kube-system   calico-kube-controllers-799fb94867-6qj77   0/1     ContainerCreating   0          21s
# kube-system   calico-node-bzttq                          0/1     PodInitializing     0          21s
# kube-system   calico-node-r6bwj                          0/1     PodInitializing     0          21s
# kube-system   coredns-66bff467f8-52tkd                   0/1     Pending             0          7m5s
# kube-system   coredns-66bff467f8-g5gjb                   0/1     ContainerCreating   0          7m5s
# kube-system   etcd-controlplane                          1/1     Running             0          7m7s
# kube-system   kube-apiserver-controlplane                1/1     Running             0          7m7s
# kube-system   kube-controller-manager-controlplane       1/1     Running             0          7m7s
# kube-system   kube-proxy-b2j4x                           1/1     Running             0          6m46s
# kube-system   kube-proxy-s46lv                           1/1     Running             0          7m5s
# kube-system   kube-scheduler-controlplane                1/1     Running             0          7m6s

master $ kubectl get nodes
# NAME           STATUS   ROLES    AGE     VERSION
# controlplane   Ready    master   7m30s   v1.18.0
# node01         Ready    <none>   6m59s   v1.18.0
```

Explore the CNI configuration as that’s what Kubelet needs to set up the network.

```bash
master $ cd /etc/cni/net.d/
master $ ls
10-calico.conflist  calico-kubeconfig
master $
master $
master $ cat 10-calico.conflist
{
  "name": "k8s-pod-network",
  "cniVersion": "0.3.1",
  "plugins": [
    {
      "type": "calico",
      "log_level": "info",
      "log_file_path": "/var/log/calico/cni/cni.log",
      "datastore_type": "kubernetes",
      "nodename": "controlplane",
      "mtu": 1440,
      "ipam": {
          "type": "calico-ipam"
      },
      "policy": {
          "type": "k8s"
      },
      "kubernetes": {
          "kubeconfig": "/etc/cni/net.d/calico-kubeconfig"
      }
    },
    {
      "type": "portmap",
      "snat": true,
      "capabilities": {"portMappings": true}
    },
    {
      "type": "bandwidth",
      "capabilities": {"bandwidth": true}
    }
  ]
}
```

Check the CNI binary files,

```bash
master $ ls
# bandwidth  bridge  calico  calico-ipam dhcp  flannel  host-device  host-local  install  ipvlan  loopback  macvlan  portmap  ptp  sample  tuning  vlan
```


Let’s install the calicoctl to give good information about the calico and let us modify the Calico configuration.

```bash
master $ cd /usr/local/bin/
master $ curl -O -L  https://github.com/projectcalico/calicoctl/releases/download/v3.16.3/calicoctl
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   633  100   633    0     0   3087      0 --:--:-- --:--:-- --:--:--  3087
100 38.4M  100 38.4M    0     0  5072k      0  0:00:07  0:00:07 --:--:-- 4325k
master $ chmod +x calicoctl
master $ export DATASTORE_TYPE=kubernetes
master $ export KUBECONFIG=~/.kube/config
# Check endpoints - it will be empty as we have't deployed any POD
master $ calicoctl get workloadendpoints
WORKLOAD   NODE   NETWORKS   INTERFACE
master $
```

Check BGP peer status. This will show the ‘worker’ node as a peer.

```bash
master $ calicoctl node status
# Calico process is running.
# IPv4 BGP status
# +--------------+-------------------+-------+----------+-------------+
# | PEER ADDRESS |     PEER TYPE     | STATE |  SINCE   |    INFO     |
# +--------------+-------------------+-------+----------+-------------+
# | 172.17.0.40  | node-to-node mesh | up    | 00:24:04 | Established |
# +--------------+-------------------+-------+----------+-------------+
```

Create a busybox POD with two replicas and master node toleration.

```bash
cat > busybox.yaml <<"EOF"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: busybox-deployment
spec:
  selector:
    matchLabels:
      app: busybox
  replicas: 2
  template:
    metadata:
      labels:
        app: busybox
    spec:
      tolerations:
      - key: "node-role.kubernetes.io/master"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: busybox
        image: busybox
        command: ["sleep"]
        args: ["10000"]
EOF
master $ kubectl apply -f busybox.yaml
# deployment.apps/busybox-deployment created
```

Get Pod and endpoint status,

```bash
master $ kubectl get pods -o wide
# NAME                                 READY   STATUS    RESTARTS   AGE   IP                NODE           NOMINATED NODE   READINESS GATES
# busybox-deployment-8c7dc8548-btnkv   1/1     Running   0          6s    192.168.196.131   node01         <none>           <none>
# busybox-deployment-8c7dc8548-x6ljh   1/1     Running   0          6s    192.168.49.66     controlplane   <none>           <none>

master $ calicoctl get workloadendpoints
# WORKLOAD                             NODE           NETWORKS             INTERFACE
# busybox-deployment-8c7dc8548-btnkv   node01         192.168.196.131/32   calib673e730d42
# busybox-deployment-8c7dc8548-x6ljh   controlplane   192.168.49.66/32     cali9861acf9f07
```

Get the details of the host side veth peer of master node busybox POD.

```bash
master $ ifconfig cali9861acf9f07
# cali9861acf9f07: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1440
#         inet6 fe80::ecee:eeff:feee:eeee  prefixlen 64  scopeid 0x20<link>
#         ether ee:ee:ee:ee:ee:ee  txqueuelen 0  (Ethernet)
#         RX packets 0  bytes 0 (0.0 B)
#         RX errors 0  dropped 0  overruns 0  frame 0
#         TX packets 5  bytes 446 (446.0 B)
#         TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
```

Get the details of the master Pod’s interface,

```bash
master $ kubectl exec busybox-deployment-8c7dc8548-x6ljh -- ifconfig
# eth0      Link encap:Ethernet  HWaddr 92:7E:C4:15:B9:82
#           inet addr:192.168.49.66  Bcast:192.168.49.66  Mask:255.255.255.255
#           UP BROADCAST RUNNING MULTICAST  MTU:1440  Metric:1
#           RX packets:5 errors:0 dropped:0 overruns:0 frame:0
#           TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
#           collisions:0 txqueuelen:0
#           RX bytes:446 (446.0 B)  TX bytes:0 (0.0 B)
# lo        Link encap:Local Loopback
#           inet addr:127.0.0.1  Mask:255.0.0.0
#           UP LOOPBACK RUNNING  MTU:65536  Metric:1
#           RX packets:0 errors:0 dropped:0 overruns:0 frame:0
#           TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
#           collisions:0 txqueuelen:1000
#           RX bytes:0 (0.0 B)  TX bytes:0 (0.0 B)
master $ kubectl exec busybox-deployment-8c7dc8548-x6ljh -- ip route
# default via 169.254.1.1 dev eth0
# 169.254.1.1 dev eth0 scope link
master $ kubectl exec busybox-deployment-8c7dc8548-x6ljh -- arp
```

Get the master node routes,

```bash
master $ ip route
# default via 172.17.0.1 dev ens3
# 172.17.0.0/16 dev ens3 proto kernel scope link src 172.17.0.32
# 172.18.0.0/24 dev docker0 proto kernel scope link src 172.18.0.1 linkdown
# blackhole 192.168.49.64/26 proto bird
# 192.168.49.65 dev calic22dbe57533 scope link
# 192.168.49.66 dev cali9861acf9f07 scope link
# 192.168.196.128/26 via 172.17.0.40 dev tunl0 proto bird onlink
```

Let’s try to ping the worker node Pod to trigger ARP.

```bash
master $ kubectl exec busybox-deployment-8c7dc8548-x6ljh -- ping 192.168.196.131 -c 1
# PING 192.168.196.131 (192.168.196.131): 56 data bytes
# 64 bytes from 192.168.196.131: seq=0 ttl=62 time=0.823 ms

master $ kubectl exec busybox-deployment-8c7dc8548-x6ljh -- arp
# ? (169.254.1.1) at ee:ee:ee:ee:ee:ee [ether]  on eth0
```

The MAC address of the gateway is nothing but the cali9861acf9f07. From now, whenever the traffic goes out, it will directly hit the kernel; And, the kernel knows that it has to write the packet into the tunl0 based on the IP route.

Proxy ARP configuration,

```bash
master $ cat /proc/sys/net/ipv4/conf/cali9861acf9f07/proxy_arp
# 1
```
**How the destination node handles the packet?**

```bash
node01 $ ip route
# default via 172.17.0.1 dev ens3
# 172.17.0.0/16 dev ens3 proto kernel scope link src 172.17.0.40
# 172.18.0.0/24 dev docker0 proto kernel scope link src 172.18.0.1 linkdown
# 192.168.49.64/26 via 172.17.0.32 dev tunl0 proto bird onlink
# blackhole 192.168.196.128/26 proto bird
# 192.168.196.129 dev calid4f00d97cb5 scope link
# 192.168.196.130 dev cali257578b48b6 scope link
# 192.168.196.131 dev calib673e730d42 scope link
```

Upon receiving the packet, the kernel sends the right veth based on the routing table.

We can see the IP-IP protocol on the wire if we capture the packets. Azure doesn’t support IP-IP (As far I know); therefore, we can’t use IP-IP in that environment. It’s better to disable IP-IP to get better performance. Let’s try to disable and see what’s the effect.


### Disable IP-IP

Update the ipPool configuration to disable IPIP.

```bash
master $ calicoctl get ippool default-ipv4-ippool -o yaml > ippool.yaml
master $ vi ippool.yaml
```

Open the ippool.yaml and set the IPIP to ‘Never,’ and apply the yaml via calicoctl.

```bash
master $ calicoctl apply -f ippool.yaml
# Successfully applied 1 'IPPool' resource(s)
```

Recheck the IP route,

```bash
master $ ip route
# default via 172.17.0.1 dev ens3
# 172.17.0.0/16 dev ens3 proto kernel scope link src 172.17.0.32
# 172.18.0.0/24 dev docker0 proto kernel scope link src 172.18.0.1 linkdown
# blackhole 192.168.49.64/26 proto bird
# 192.168.49.65 dev calic22dbe57533 scope link
# 192.168.49.66 dev cali9861acf9f07 scope link
# 192.168.196.128/26 via 172.17.0.40 dev ens3 proto bird
```

The device is no more tunl0; it is set to the management interface of the master node.

Let’s ping the worker node POD and make sure all works fine. From now, there won’t be any IPIP protocol involved.

```bash
master $ kubectl exec busybox-deployment-8c7dc8548-x6ljh -- ping 192.168.196.131 -c 1
# PING 192.168.196.131 (192.168.196.131): 56 data bytes
# 64 bytes from 192.168.196.131: seq=0 ttl=62 time=0.653 ms
# --- 192.168.196.131 ping statistics ---
# 1 packets transmitted, 1 packets received, 0% packet loss
# round-trip min/avg/max = 0.653/0.653/0.653 ms
```

Note: Source IP check should be disabled in AWS environment to use this mode.

### VXLAN

Re-initiate the cluster and download the calico.yaml file to apply the following changes,

1. Remove bird from livenessProbe and readinessProbe
```yaml
		  livenessProbe:
            exec:
              command:
              - /bin/calico-node
              - -felix-live
              - -bird-live >> Remove this
            periodSeconds: 10
            initialDelaySeconds: 10
            failureThreshold: 6
          readinessProbe:
            exec:
              command:
              - /bin/calico-node
              - -felix-ready
              - -bird-ready >> Remove this
```

2. Change the calico_backend to ‘vxlan’ as we don’t need BGP anymore.

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: calico-config
  namespace: kube-system
data:
  # Typha is disabled.
  typha_service_name: "none"
  # Configure the backend to use.
  calico_backend: "vxlan"
3. Disable IPIP
# Enable IPIP
- name: CALICO_IPV4POOL_IPIP
    value: "Never" # --> Set this to 'Never' to disable IP-IP
# Enable or Disable VXLAN on the default IP pool.
- name: CALICO_IPV4POOL_VXLAN
    value: "Never"
```

Let’s apply this new yaml.

```bash
master $ ip route
# default via 172.17.0.1 dev ens3
# 172.17.0.0/16 dev ens3 proto kernel scope link src 172.17.0.15
# 172.18.0.0/24 dev docker0 proto kernel scope link src 172.18.0.1 linkdown
# 192.168.49.65 dev calif5cc38277c7 scope link
# 192.168.49.66 dev cali840c047460a scope link
# 192.168.196.128/26 via 192.168.196.128 dev vxlan.calico onlink
# vxlan.calico: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1440
#         inet 192.168.196.128  netmask 255.255.255.255  broadcast 192.168.196.128
#         inet6 fe80::64aa:99ff:fe2f:dc24  prefixlen 64  scopeid 0x20<link>
#         ether 66:aa:99:2f:dc:24  txqueuelen 0  (Ethernet)
#         RX packets 0  bytes 0 (0.0 B)
#         RX errors 0  dropped 0  overruns 0  frame 0
#         TX packets 0  bytes 0 (0.0 B)
#         TX errors 0  dropped 11 overruns 0  carrier 0  collisions 0
```

Get the POD status,

```bash
master $ kubectl get pods -o wide
# NAME                                 READY   STATUS    RESTARTS   AGE   IP                NODE           NOMINATED NODE   READINESS GATES
# busybox-deployment-8c7dc8548-8bxnw   1/1     Running   0          11s   192.168.49.67     controlplane   <none>           <none>
# busybox-deployment-8c7dc8548-kmxst   1/1     Running   0          11s   192.168.196.130   node01         <none>           <none>
```
Ping the worker node POD from

```bash
master $ kubectl exec busybox-deployment-8c7dc8548-8bxnw -- ip route
# default via 169.254.1.1 dev eth0
# 169.254.1.1 dev eth0 scope link
```

Trigger the ARP request,

```bash
master $ kubectl exec busybox-deployment-8c7dc8548-8bxnw -- arp
master $ kubectl exec busybox-deployment-8c7dc8548-8bxnw -- ping 8.8.8.8
# PING 8.8.8.8 (8.8.8.8): 56 data bytes
# 64 bytes from 8.8.8.8: seq=0 ttl=116 time=3.786 ms
# ^C
master $ kubectl exec busybox-deployment-8c7dc8548-8bxnw -- arp
# ? (169.254.1.1) at ee:ee:ee:ee:ee:ee [ether]  on eth0
```

The concept is as the previous modes, but the only difference is that the packet reaches the vxland, and it encapsulates the packet with node IP and its MAC in the inner header and sends it. Also, the UDP port of the vxlan proto will be 4789. The etcd helps here to get the details of available nodes and their supported IP range so that the vxlan-calico can build the packet.

Note: VxLAN mode needs more processing power than the previous modes.

![](/assets/images/packet-life/02-07.png)

### Disclaimer

This article does not provide any technical advice or recommendation; if you feel so, it is my personal view, not the company I work for.

### References

- https://docs.projectcalico.org/
- https://www.openstack.org/videos/summits/vancouver-2018/kubernetes-networking-with-calico-deep-dive
- https://kubernetes.io/
- https://www.ibm.com/support/knowledgecenter/en/SSBS6K_3.1.2/manage_network/calico.html
- https://github.com/coreos/flannel


## 마치며
