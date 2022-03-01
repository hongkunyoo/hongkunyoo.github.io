---
layout: post
title:  "[번역]쿠버네티스 패킷의 삶 - #2"
date:   2021-12-01 00:00:00
categories: kubernetes network
image: /assets/images/packet-life/landing02.png
permalink: /:title
---
[쿠버네티스 패킷의 삶 #1](/packet-network1)에서 살펴 봤듯이, CNI plugin은 쿠버네티스 네트워킹에서 중요한 역할을 차지합니다. 현재 많은 CNI plugin 구현체들이 존재합니다. 그 중 Calico를 소개합니다. 많은 엔지니어들은 Calico를 선호합니다. 그 이유는 Calico는 네트워크 구성을 간단하게 만들어 주기 때문입니다.

## 쿠버네티스 패킷의 삶 시리즈

1. [컨테이너 네트워킹과 CNI](/packet-network1): 리눅스 네트워크 namespace와 CNI 기초
2. Calico CNI: CNI 구현체 중 하나인, Calico CNI 네트워킹 ([원글](https://dramasamy.medium.com/life-of-a-packet-in-kubernetes-part-2-a07f5bf0ff14))
3. [Service 네트워킹](/packet-network3): Service, 클러스터 내/외부 네트워킹 설명
4. [Ingress](/packet-network4): Ingress Controller에 대한 설명

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

**뭔가 이상한게 보이시나요?** 네, 맞습니다. veth(`cali123`)이 어디에도 연결되어 있지 않습니다(dangling). 커널공간(kernel space)에 있습니다.

그렇다면 패킷이 어떻게 다른 노드로 라우팅이 될까요?

1. 마스터 노드(왼쪽)에 있는 `Pod`가 `10.0.2.11`로 ping을 시도해 봅니다.
2. `Pod`가 ARP 요청을 gateway로 보냅니다.
3. 이를 통해 MAC 주소와 함께 ARP 응답을 받습니다.
4. 잠깐만요, 누가 ARP 응답을 `Pod`로 보내나요?

도대체 어떻게 된 일인가요? 어떻게 있지도 않는 IP에 대해서 패킷을 전송할 수 있는 것인가요?(역자주: 마스터 노드 입장에서 생각하자면 `10.0.2.11` IP는 워커 노드 내부에 존재하는 IP입니다. 호스트 네트워크의 IP도 아니기 때문에 워커 노드에 해당 IP가 존재하는지 조차도 모르는 상황입니다.) 찬찬히 다시 생각해 봅시다. 어떤 분들은 `169.254.1.1`가 IPv4 link-local 주소라는 것을 눈치챘을 수도 있습니다. 컨테이너의 기본 게이트웨이가 link-local 주소를 가리키고 있습니다. 컨테이너는 자신이 연결된 네트워크 인터페이스를 통해 해당 IP주소가 외부와 통신 가능하리라 기대합니다. 이 경우에는 컨테이너 내부에 있는 `eth0` 인터페이스가 되겠죠. 컨테이너는 외부로 통신하려고 할 때 해당 주소로 ARP 요청을 보낼 것입니다.(default gateway가 해당 인터페이스로 설정되어 있기 때문이죠.)

이 때, ARP 응답을 확인해 보면 반대편 네트워크 인터페이스의 MAC주소가 보일 것입니다(`cali123`). 여기서 문제가 생기는데요, 도대체 연결된 인터페이스도 없는 녀석이(`calico`) 어떻게 ARP 요청에 응답할 수 있을까요? 정답은 **proxy-arp**에 있습니다. 호스트쪽 `veth` 인터페이스(`cali123`)를 확인해 보면 해당 인터페이스에 `proxy-arp` 설정이 활성화(enabled)되어 있는 것을 볼 수 있습니다.

```bash
master $ cat /proc/sys/net/ipv4/conf/cali123/proxy_arp
# 1
```

> "[Proxy ARP란](https://en.wikipedia.org/wiki/Proxy_ARP), 해당 네트워크에 존재하지 않는 proxy device가 ARP 요청을 대리하여 응답하는 기술을 말합니다. Proxy는 목적지의 실제 위치를 알고 있습니다(역자주: 예시에서는 proxy가 `10.0.2.11`의 위치를 이미 알고 있다는 뜻입니다.). 그렇기에 ARP 요청이 왔을 때, 본인의 MAC주소를 대신 전달해주어 ARP 요청자로 하여금 자신에게 패킷이 전달되도록 응답합니다. Proxy로 전달된 트래픽은 Proxy에 의해 실제 목적지로 전달됩니다. 이때 사용되는 인터페이스가 tunnel입니다. 이렇게 프록싱을 목적으로 ARP 요청에 대해 자신의 MAC 주소를 대신 응답하는 프로세스를 퍼블리싱(publishing)이라고도 부릅니다."

이번에는 워커노드를 자세히 살펴 봅시다.

![](/assets/images/packet-life/02-05.png)

패킷이 커널에 도달하게 되면 라우팅 테이블에 따라 패킷이 라우팅됩니다.

#### Incoming 트래픽

1. 패킷이 워커노드의 커널에 도달합니다.
2. 커널이 `cali123` 인터페이스로 패킷을 보냅니다.


## 라우팅 모드

Calico는 3가지 라우팅 모드를 지원합니다. 이번 섹션에서는 각각의 모드의 장단점에 대해서 살펴 보겠습니다.

- **IP-in-IP 모드**: 기본설정, encapsulated
- **Direct / NoEncapMode 모드**: unencapsulated (추천모드)
- **VXLAN 모드**: encapsulated (No BGP)

### IP-in-IP (Default)

IP-in-IP 모드는 IP 패킷을 다른 IP 패킷에 집어 넣음으로써 간단하게 캡슐화하는 방법입니다. 바깥의 IP 패킷에는 호스트 서버의 출발지, 목적지 IP가 들어있고 안쪽 IP 패킷에는 `Pod`의 출발지, 목적지 정보가 들어 있습니다. Azure 클라우드는 IP-IP 모드를 지원하지 않기 때문에 해당 클라우드에서는 이 모드를 사용할 수 없습니다. 더 나은 성능을 위해 IP-IP 모드를 비활성화할 수 있습니다.

### NoEncapMode

이 모드에서는 마치 `Pod`로부터 직접 전송된 것처럼 패킷을 전달합니다. 캡슐화와 디캡슐화가 수행되지 않기 때문에 성능면에서 우수한 장점을 가집니다. AWS에서는 Source IP check 기능을 반드시 비활성화 해야 합니다. (역자주: AWS EC2에는 패킷의 source IP가 패킷을 전송하는 호스트 IP와 동일한지 확인하는 기능이 있습니다. `NoEncapMode`에서는 source IP가 호스트 IP가 아닌 전송하는 `Pod` IP로 찍히기 때문에 해당 기능을 비활성화 하지 않으면 패킷이 전달되지 않습니다.)

### VXLAN

VXLAN 라우팅 모드는 Calico 3.7 이상부터 지원됩니다.

> VXLAN은 Virtual Extensible LAN의 약자입니다. VXLAN은 네트워크 layer 2의 이더넷 프레임이 UDP 패킷으로 캡슐화되는 기술입니다. VXLAN은 네트워크 가상화 기술입니다. 네트워크 장비들이 소프트웨어 정의 데이터센터(software defined datacenter)에서 통신할 때, VXLAN tunnel이 이들 장비 사이에 위치하게 됩니다. 이 tunnel들은 물리 혹은 가상 스위치에 연결될 수 있습니다. 스위치 포트들은 VXLAN tunnel Endpoints(VTEPs)라고 불립니다. 이것은 VXLAN 패킷을 캡슐화 / 디캡슐화하는 기능을 담당합니다. VXLAN을 지원하지 않는 장비들을 VTEP 기능을 가진 스위치 포트에 연결하면 스위치가 알아서 VXLAN 기능을 수행합니다.

VXLAN은 Azure나 BGP 프로토콜을 지원하지 않는 데이터센터와 같이 IP-in-IP 모드를 지원하지 않는 네트워크에서 잘 사용될 수 있습니다.

![](/assets/images/packet-life/02-06.png)


## 라우팅 모드별 설정 방법

### IPIP와 UnEncapMode

Calico를 설치하기 전에 클러스터의 상태를 확인해 봅니다.

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

CNI 실행파일과 설정파일 디렉토리를 확인합니다. Calico가 아직 설치되지 않았기 때문에 기본적인 실행파일 외엔 별다른 파일들이 보이지 않습니다.

```bash
master $ cd /etc/cni
-bash: cd: /etc/cni: No such file or directory
master $ cd /opt/cni/bin
master $ ls
# bridge  dhcp  flannel  host-device  host-local  ipvlan  loopback  macvlan  portmap  ptp  sample  tuning  vlan
```

마스터와 워커 노드의 IP 라우팅 테이블 정보를 확인합니다.

```bash
master $ ip route
# default via 172.17.0.1 dev ens3
# 172.17.0.0/16 dev ens3 proto kernel scope link src 172.17.0.32
# 172.18.0.0/24 dev docker0 proto kernel scope link src 172.18.0.1 linkdown

# Download and apply the calico.yaml based on your environment.
curl https://docs.projectcalico.org/manifests/calico.yaml -O

kubectl apply -f calico.yaml
```

`calico.yaml` 파일에서 몇 가지 중요한 설정값들을 확인해 봅시다.

```bash
# vim calico.yaml
cni_network_config: |-
    {
      "name": "k8s-pod-network",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "calico", # calico CNI plugin을 사용합니다.
          "log_level": "info",
          "log_file_path": "/var/log/calico/cni/cni.log",
          "datastore_type": "kubernetes",
          "nodename": "__KUBERNETES_NODE_NAME__",
          "mtu": __CNI_MTU__,
          "ipam": {
              "type": "calico-ipam" # default ipam이 아닌, calico에서 제공하는 ipam을 사용합니다.
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
    value: "Always" # IP-IP 모드를 비활성화하고 싶으면 Never라고 설정하면 됩니다.
# Disable VXLAN
- name: CALICO_IPV4POOL_VXLAN
    value: "Never"  # VXLAN은 비활성화하였습니다.
```

Calico 설치 이후 `Pod`와 `Node`의 상태를 확인합니다.

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

CNI 설정을 살펴 봅니다. kubelet이 이 설정파일을 참고합니다.

```bash
master $ cd /etc/cni/net.d/
master $ ls
# 10-calico.conflist  calico-kubeconfig
master $
master $ cat 10-calico.conflist
# {
#   "name": "k8s-pod-network",
#   "cniVersion": "0.3.1",
#   "plugins": [
#     {
#       "type": "calico",
#       "log_level": "info",
#       "log_file_path": "/var/log/calico/cni/cni.log",
#       "datastore_type": "kubernetes",
#       "nodename": "controlplane",
#       "mtu": 1440,
#       "ipam": {
#           "type": "calico-ipam"
#       },
#       "policy": {
#           "type": "k8s"
#       },
#       "kubernetes": {
#           "kubeconfig": "/etc/cni/net.d/calico-kubeconfig"
#       }
#     },
#     {
#       "type": "portmap",
#       "snat": true,
#       "capabilities": {"portMappings": true}
#     },
#     {
#       "type": "bandwidth",
#       "capabilities": {"bandwidth": true}
#     }
#   ]
# }
```

CNI 실행파일을 다시 확인합니다. 아까와는 다르게 calico 관련한 실행파일들이 추가되었습니다.

```bash
master $ ls
# bandwidth  bridge  calico  calico-ipam dhcp  flannel  host-device  host-local  install  ipvlan  loopback  macvlan  portmap  ptp  sample  tuning  vlan
```

Let’s install the calicoctl to give good information about the calico and let us modify the Calico configuration.

Calico 설정을 변경하기 위해 `calicoctl`을 설치해 봅시다.

```bash
master $ cd /usr/local/bin/
master $ curl -O -L  https://github.com/projectcalico/calicoctl/releases/download/v3.16.3/calicoctl
#   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
#                                  Dload  Upload   Total   Spent    Left  Speed
# 100   633  100   633    0     0   3087      0 --:--:-- --:--:-- --:--:--  3087
# 100 38.4M  100 38.4M    0     0  5072k      0  0:00:07  0:00:07 --:--:-- 4325k
master $ chmod +x calicoctl
master $ export DATASTORE_TYPE=kubernetes
master $ export KUBECONFIG=~/.kube/config
# endpoint를 확인합니다. 아직 Pod를 생성하지 않았기 때문에 빈칸으로 보입니다.
master $ calicoctl get workloadendpoints
# WORKLOAD   NODE   NETWORKS   INTERFACE
```

BGP peer 상태를 확인합니다. 워커 노드가 peer로 보입니다.

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

busybox `Pod` 두개를 생성합니다. 마스터와 워커 노드에 각각 생성되기 위해 마스터 노드 `toleration`도 설정해 줍니다.

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

`Pod`와 endpoint 상태를 확인합니다.

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

마스터 노드에 있는 busybox `Pod`의 호스트쪽 인터페이스(veth peer)를 확인합니다. (`cali9861acf9f07` 인터페이스의 MAC 주소가 `ee:ee:ee:ee:ee:ee`인 것을 기억해주세요.)

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

이번에는 `Pod` 내부쪽 인터페이스를 확인합니다.

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

마스터 노드의 라우팅 정보를 확인합니다.

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

마스터 노드에 있는 `Pod` 안에서 워커노드에 있는 `Pod`로 ARP를 수행하기 위해 ping을 날려봅니다.

```bash
master $ kubectl exec busybox-deployment-8c7dc8548-x6ljh -- ping 192.168.196.131 -c 1
# PING 192.168.196.131 (192.168.196.131): 56 data bytes
# 64 bytes from 192.168.196.131: seq=0 ttl=62 time=0.823 ms

master $ kubectl exec busybox-deployment-8c7dc8548-x6ljh -- arp
# ? (169.254.1.1) at ee:ee:ee:ee:ee:ee [ether]  on eth0
```

게이트웨이의 MAC 주소가 `ee:ee:ee:ee:ee:ee`로 `cali9861acf9f07` 인터페이스를 가리킵니다. 이제부터 `Pod` 내부에서 트래픽이 밖으로 나갈 때마다 `cali9861acf9f07`를 통해 커널로 전달되고 커널에서는 IP 라우팅 테이블에 따라 해당 패킷을 `tunl0`으로 보내게 됩니다.

`cali9861acf9f07`의 Proxy ARP 설정을 확인해 봅니다.

```bash
master $ cat /proc/sys/net/ipv4/conf/cali9861acf9f07/proxy_arp
# 1
```

이번에는 목적지 노드(예시에서는 워커노드)에서는 전달 받은 패킷을 어떻게 처리하는지 알아 봅시다.

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

워커노드의 라우팅 정보를 살펴 보면, 커널이 `Pod` IP(`192.168.196.xxx`)에 따라 적절하게 해당하는 veth(`calixxx`)로 보내는 것을 알 수 있습니다.

만약 지나가는 패킷을 열어 보면 IP-IP 프로토콜로 통신하는 것을 확인할 수 있을 것입니다. 더 나은 성능을 위해 이번에는 IP-IP 모드를 비활성화해보고 어떤 영향이 있는지 확인해 보겠습니다.

### IP-IP 모드 비활성화

IP-IP 모드를 비활성화하기 위해서 ipPool 설정을 업데이트합니다.

```bash
master $ calicoctl get ippool default-ipv4-ippool -o yaml > ippool.yaml
master $ vi ippool.yaml
```

앞서 설명 드린 것과 같이 `CALICO_IPV4POOL_IPIP` 값을 `Never`로 수정하여 apply 합니다.

```bash
master $ calicoctl apply -f ippool.yaml
# Successfully applied 1 'IPPool' resource(s)
```

다시 라우팅 정보를 확인합니다.

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

`tunl0`이라는 디바이스가 더 이상 보이지 않고 마스터노드의 물린 인터페이스(`ens3`)로 설정되어 있습니다. 워커노드의 `Pod`에 ping을 보내어 정상적으로 작동하는지 확인해 봅니다. 이제는 더 이상 IP-IP 프로토콜로 동작하지 않을 것입니다.

```bash
master $ kubectl exec busybox-deployment-8c7dc8548-x6ljh -- ping 192.168.196.131 -c 1
# PING 192.168.196.131 (192.168.196.131): 56 data bytes
# 64 bytes from 192.168.196.131: seq=0 ttl=62 time=0.653 ms
# --- 192.168.196.131 ping statistics ---
# 1 packets transmitted, 1 packets received, 0% packet loss
# round-trip min/avg/max = 0.653/0.653/0.653 ms
```

> 참고: AWS 환경에서 해당 모드를 사용하려면 `Source IP check`이 비활성화 되었는지 확인하기 바랍니다.

### VXLAN

VXLAN을 테스트해 보기 위한 가장 깔끔한 방법은 클러스터를 다시 구성하는 것입니다. 클러스터를 재설치하고 `calico.yaml` 파일을 다시 받아 봅시다.


#1. `livenessProbe`와 `readinessProbe`에서 Bird를 삭제합니다.

```yaml
          livenessProbe:
            exec:
              command:
              - /bin/calico-node
              - -felix-live
              - -bird-live # --> 이 부분을 삭제합니다.
            periodSeconds: 10
            initialDelaySeconds: 10
            failureThreshold: 6
          readinessProbe:
            exec:
              command:
              - /bin/calico-node
              - -felix-ready
              - -bird-ready # --> 이 부분을 삭제합니다.
```

#2. calico_backend를 `vxlan`으로 변경합니다.

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: calico-config
  namespace: kube-system
data:
  # Typha is disabled.
  typha_service_name: "none"
  # 여기를 vxlan으로 수정합니다.
  calico_backend: "vxlan"
```

#3. IP-IP 모드를 비활성화합니다.

```yaml
# Enable IPIP
- name: CALICO_IPV4POOL_IPIP
    value: "Never" # IP-IP 모드 비활성화
- name: CALICO_IPV4POOL_VXLAN
    value: "Always"
```

이 YAML 파일을 적용하고 라우팅 정보를 확인합니다.

```bash
master $ kubectl apply -f calico.yaml

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

`Pod` 정보를 확인합니다.

```bash
master $ kubectl get pods -o wide
# NAME                                 READY   STATUS    RESTARTS   AGE   IP                NODE           NOMINATED NODE   READINESS GATES
# busybox-deployment-8c7dc8548-8bxnw   1/1     Running   0          11s   192.168.49.67     controlplane   <none>           <none>
# busybox-deployment-8c7dc8548-kmxst   1/1     Running   0          11s   192.168.196.130   node01         <none>           <none>
```

마스터 노드에 있는 `Pod`의 라우팅 정보를 확인합니다.

```bash
master $ kubectl exec busybox-deployment-8c7dc8548-8bxnw -- ip route
# default via 169.254.1.1 dev eth0
# 169.254.1.1 dev eth0 scope link
```

외부로 ping을 날리고 ARP 테이블을 다시 확인합니다.

```bash
master $ kubectl exec busybox-deployment-8c7dc8548-8bxnw -- arp

master $ kubectl exec busybox-deployment-8c7dc8548-8bxnw -- ping 8.8.8.8
# PING 8.8.8.8 (8.8.8.8): 56 data bytes
# 64 bytes from 8.8.8.8: seq=0 ttl=116 time=3.786 ms
# ^C
master $ kubectl exec busybox-deployment-8c7dc8548-8bxnw -- arp
# ? (169.254.1.1) at ee:ee:ee:ee:ee:ee [ether]  on eth0
```

이전 방식과 전체적으로는 비슷해 보입니다. 다른 점은 패킷이 vxlan에 도달한다는 것이고 도달하게 되면 노드의 IP와 MAC 주소를 안쪽 헤더에 캠슐화하여 전송한다는 것입니다. 그리고 vxlan 프로토콜의 UDP 포트는 4789이라는 점입니다. vxlan-calico가 패킷을 캡슐화하기 위해 라우팅 가능한 노드 정보와 할당 가능한 IP 대역 등에 대한 정보는 etcd를 통해 얻습니다.

> 참고: VXLAN은 이전 모드보다 더 많은 프로세싱 파워가 필요합니다.

![](/assets/images/packet-life/02-07.png)

### 밝히는 사실 (Disclaimer)

> 다음 글은 원저자가 밝히는 내용입니다.

이 글은 특정 기술에 대한 조언이나 추천을 하지 않습니다. 필자가 속한 회사와는 무관하게 개인적인 의견임을 밝힙니다.

### References

- [https://docs.projectcalico.org/](https://docs.projectcalico.org/)
- [https://www.openstack.org/videos/summits/vancouver-2018/kubernetes-networking-with-calico-deep-dive](https://www.openstack.org/videos/summits/vancouver-2018/kubernetes-networking-with-calico-deep-dive)
- [https://www.ibm.com/support/knowledgecenter/en/SSBS6K_3.1.2/manage_network/calico.html](https://www.ibm.com/support/knowledgecenter/en/SSBS6K_3.1.2/manage_network/calico.html)
- [https://github.com/coreos/flannel](https://github.com/coreos/flannel)


## 마치며

이번 포스트에서는 많이 사용되는 CNI 구현체 중에 하나인 Calico CNI가 구체적으로 어떻게 동작하는지에 대해서 살펴 보았습니다. 다음 포스트에서는 쿠버네티스 네트워킹의 중요한 축을 담당하는 `kube-proxy`와 `iptables`에 대해서 집중적으로 알아보겠습니다.
  