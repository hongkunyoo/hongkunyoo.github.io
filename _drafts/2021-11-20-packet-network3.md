---
layout: post
title:  "[번역]쿠버네티스 패킷의 삶 - #3"
date:   2021-11-15 00:00:00
categories: kubernetes network
image: /assets/images/packet-life/landing03.png
permalink: /:title
---
쿠버네티스 패킷의 삶 #3 시작합니다.

## 쿠버네티스 패킷의 삶 시리즈

1. [컨테이너 네트워킹과 CNI](/packet-network1): 리눅스 네트워크 namespace와 CNI 기초
2. [Calico CNI](/packet-network2): CNI 구현체 중 하나인, Calico CNI 네트워킹
3. Pod 네트워킹: Pod간, 클러스터 내/외부 네트워킹 설명
4. Ingress: Ingress Controller에 대한 설명

---

쿠버네티스 패킷의 삶 3번째 시리즈입니다. 이번 글에서는 `kube-proxy`가 어떻게 `iptables`를 이용하여 트래픽을 전달하는지 낱낱히 살펴 보는 시간을 가져 보겠습니다. 쿠버네티스 네트워킹을 이해하기 위해서 `kube-proxy`와 `iptables`의 역할을 잘 아는 것이 중요합니다.

참고: 트래픽을 컨트롤하는 플러그인/툴은 많이 있습니다만 이번 글에서는 주로 `kube-proxy` + `iptables` 조합에 대해서 설명 드립니다.

쿠버네티스에서 제공하는 다양한 커뮤니케이션 모델에 대해서 먼저 살펴 보겠습니다. 혹시 `Service`, `ClusterIP` 그리고 `NodePort`에 대한 내용을 이미 알고 있다면 바로 `kube-proxy`/`iptables` 셕센으로 넘어가길 바랍니다.

## Pod - Pod 통신

`kube-proxy`는 `Pod` to `Pod` 통신에는 관여하지 않습니다. CNI와 노드에서 `Pod` 통신간 필요한 라우팅 정보를 설정합니다. 모든 컨테이너는 NAT 없이 다른 컨테이너와 통신할 수 있습니다. 또한 모든 노드는 NAT 없이 모든 컨테이너와 통신할 수 있습니다.(반대로도 성립합니다.)

참고: `Pod`의 IP는 고정적이지 않습니다. (고정된 IP를 할당 받는 방법은 있지만 기본적으로는 고정 IP를 보장 받지 않습니다.) `Pod` 재시작 시, CNI는 새로운 IP를 해당 `Pod`에 할당합니다. 왜냐하면 CNI가 따로 IP와 `Pod` 간에 매핑 정보를 관리하지 않기 때문입니다. 또한 이미 알고 있듯이 `Deployment` 리소스를 사용하는 경우 `Pod` 이름 조차도 고정적이지 않습니다.

![](/assets/images/packet-life/03-01.png)

실무에서는 `Deployment`를 사용할 때, 앞단에 로드밸런서를 두고 어플리케이션을 노출 시킵니다. 그리고 한개 이상의 `Pod`를 사용하죠. 쿠버네티스에서 이 로드밸런서를 `Service`라고 부릅니다.

## Pod - 외부 통신

`Pod`로부터 외부로 나가는 트래픽에 쿠버네티스는 [SNAT](https://en.wikipedia.org/wiki/Network_address_translation)를 사용합니다. 바로 `Pod`의 내부 IP:PORT를 호스트 서버의 IP:PORT로 치환하는 일을 수행하죠. 요청에 대해 응답이 오는 경우 그것을 다시 `Pod`의 IP:PORT로 바꿔서 원래의 `Pod`로 트래픽을 전달해 줍니다. `Pod` 입장에서는 이 모든 프로세스가 수행된지 전혀 모릅니다.

## Pod- Service 통신

### ClusterIP

쿠버네티스에는 "Service"라는 개념이 있습니다. 이것은 간단히 말해 `Pod` 앞단에 위치하는 L4 로드밸런서입니다. 몇 가지 종류의 `Service`가 있습니다. 그 중 가장 기본적인 종류로 `ClusterIP`가 있습니다. 이 서비스는 클러스터 내부에서 라우팅 가능한 고유의 VIP(가상 IP)를 가집니다.

`Pod` IP만으로는 특정 어플리케이션에 트래픽을 보내는 것은 쉽지 않습니다. 왜냐하면 쿠버네티스 환경에서는 `Pod`가 쉽게 이동하고, 재시작되고, 업그레이드되고 확장되고 사라지기 때문에 굉장히 동적입니다. 또한 `replicas`의 개수를 늘리게 되면 한개 이상의 `Pod`가 생성됨으로 이들간에 트래픽을 분산할 수 있는 방법이 있어야 합니다.

그래서 쿠버네티스에서는 `Service`라는 객체를 두어 이 문제를 해결했습니다. `Service`는 단일 가상IP(VIP)를 특정 `Pod`들로 트래픽을 전달해 주는 끝점(엔드포인트)입니다. 또한 쿠버네티스는 `Service`의 이름을 이용하여 DNS 서비스를 제공합니다. 그렇기 때문에 각 서비스들은 이름으로 쉽게 찾을 수 있습니다.

VIP를 `Pod` IP로 매핑해 주는 작업은 각 노드의 `kube-proxy`에 의해 수행됩니다. `kube-proxy`는 `iptables`나 `IPVS`를 이용하여 트래픽이 호스트 노드를 떠나기 전에 VIP를 `Pod` IP로 매핑 시키는 작업을 수행합니다. 개별 커넥션들은 트래킹이 됩니다. 그렇기에 패킷들이 리턴될 때 적절하게 재변환되어 돌아옵니다. `IPVS` 혹은 `iptables`를 이용하여 VIP를 여러 `Pod` IP로 부하를 분산합니다. 참고로 부하 분산을 위한 다양한 알고리즘을 사용하기에는 `IPVS`가 더 좋습니다. 가상IP (VIP)는 살제로 시스템 네트워크 인터페이스에 존재하지 않습니다. 단지 `iptable` 안에서만 존재합니다.

![](/assets/images/packet-life/03-02.png)

> 쿠버네티스 공식 페이지의 `Service` 정의: `Service`는 `Pod`를 네트워크 서비스로 어플리케이션을 노출 시키기 위한 추상화된 방법을 제공합니다. 쿠버네티스에서는 서비스 탐색(역자주: 서비스의 끝점을 알아내기 위한 방법)을 위해 특별한 방법을 사용하지 않아도 됩니다. 단지 서비스의 이름만 알고 있으면 됩니다. 쿠버네티스는 각 `Pod`마다 고유의 IP주소를 제공하고 그곳들을 묶어서 단일한 DNS 이름을 부여하여 로드를 분산 시킵니다.

- FrontEnd Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  labels:
    app: webapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
```

- Backend Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth
  labels:
    app: auth
spec:
  replicas: 2
  selector:
    matchLabels:
      app: auth
  template:
    metadata:
      labels:
        app: auth
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
```

- Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  ports:
  - port: 80
    protocol: TCP
  type: ClusterIP
  selector:
    app: webapp
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  labels:
    app: backend
spec:
  ports:
  - port: 80
    protocol: TCP
  type: ClusterIP
  selector:
    app: auth
```

위와 같이 쿠버네티스 manifest를 생성하면 FrontEnd Pod들이 BackEnd Pot들을 ClusterIP나 DNS 이름으로 접근할 수 있게 됩니다. 클러스터 내에 존재하는 DNS 서버가 (예를 들어, CoreDNS) 쿠버네티스 API를 통해 `Service`를 관찰하고 있다가 새로운 `Service`가 생기게 되면 그에 해당하는 DNS record를 생성합니다. 클러스터 전체에 DNS가 활성화되어 있다면 모든 `Pod`들이 자동으로 `Service`를 이름으로 DNS 주소를 얻을 수 있습니다.

![](/assets/images/packet-life/03-03.png)

### NodePort (외부 - Pod 통신)

이제 쿠버네티스 내부적으로 DNS를 통해 서로 통신할 수 있는 메커니즘을 살펴 보았습니다. 하지만 클러스터 외부에서는 클러스터 내부에 존재하는 `Service`로 접근하지는 못합니다. 왜냐하면 `Service`가 제공하는 VIP는 가상IP이고 내부IP이기 때문입니다.

외부 서버에서 frontEnd `Pod` IP로 접근을 시도해 봅시다.

![](/assets/images/packet-life/03-04.png)

보시다시피, 클라이언트에서는 내부 IP주소인 FrontEnd 주소로 접근하지 못합니다.

그럼 FrontEnd를 외부 세계에 노출 시키기 위해 `NodePort` 타입의 서비스를 생성해 봅시다. `type` 필드를 `NodePort`라고 수정하면 쿠버네티스는 `--service-node-port-range` 옵션에 의해 정해진 포트 대역대 안에서(기본적인 대역대: `30000`-`32767`) 특정 포트를 하나 할당합니다. 그러면 모든 노드에서 해당 포트에 대해 `Service`로 트래픽을 라우팅합니다. `Service`는 해당 포트의 이름을 `nodePort`라 부르며 `.spec.ports[*].nodePort` 필드에 정의됩니다.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: NodePort
  selector:
    app: webapp
  ports:
    - port: 80
      targetPort: 80
      # 기본적으로 생략하면 쿠버네티스가 대신 포트를 하나 할당해주고 사용자가 직접 할당할 수도 있습니다.
      nodePort: 31380
```

![](/assets/images/packet-life/03-05.png)

이제 FrontEnd 서비스를 `<아무 NodeIP>:<nodePort>`로 접근할 수 있게 되었습니다.(역자주: `<아무 NodeIP>`란 쿠버네티스 클러스터를 구성하고 있는 노드(마스터, 워커 노드 둘다) 중 아무 호스트 IP를 의미합니다.) 특정 포트를 지정하고 싶다면 `nodePort` 필드의 값을 직접 지정하면 됩니다. 쿠버네티스 마스터가 해당 포트를 할당해주거나 실패하면 에러 리포트를 줄 것입니다. 이 뜻은 포트 충돌을 유념해야 한다는 것입니다. 또한 `NodePort`에 사용되는 허용 가능한 포트 대역 안에서 포트 번호를 선택해야 합니다.(`--service-node-port-range`)

## 외부 트래픽 정책(ExternalTrafficPolicy)

> 외부 트래픽 정책(ExternalTrafficPolicy)이란 외부 트래픽에 대한 응답으로 `Service`가 노드 안(Local)에서만 응답할지 Cluster 전체(Cluster)로 나아가서 응답할지 결정하는 옵션입니다. "Local" 타입은 client 소스IP를 유지하고 네트워크 hop이 길어지지 않게 막아줍니다. 하지만 잠재적으로 트래픽 분산에 대한 불균형을 가져 올 수 있습니다.  "Cluster" 타입은 client의 소스IP를 가리고 네트워크 hop을 길게 만들지만 전체적으로 부하가 분산되도록 해줍니다.

더 자세한 내용을 이어서 말씀 드리겠습니다.

### Cluster Traffic Policy

이 옵션은 `Service`의 기본 옵션입니다. 이 옵션은 당신이 트래픽을 모든 노드 전반에 걸쳐 보내고 싶어한다는 것을 전제로 합니다. 그렇기에 부하가 고르게 분산됩니다.

이 옵션의 한가지 단점은 불필요한 네트워크 hop을 증가시킨다는 것에 있습니다. 예를 들어, `NodePort`를 통해 외부 트래픽을 받게 될 때, 운 없게도 `NodePort` 서비스의 트래픽을 전달 받는 `Pod`가 없는 노드로 요청이 갈 수 있습니다. 이런 경우에는 해당 노드에는 전달 받을 `Pod`가 없기 때문에 추가적인 hop을 걸쳐 다른 노드에 위치한 `Pod`로 트래픽이 전달되게 됩니다.

Cluster 타입에서의 패킷 흐름은 다음과 같습니다:

- 사용자가 `node2_IP:31380`으로 패킷을 보냅니다.
- `node2`는 출발지 IP주소를 자신의 노드 IP로 변경합니다.(SNAT)
- `node2`는 목적지 IP주소를 전달 받을 `Pod` IP로 변경합니다.
- (`node2`에 전달 받을 `Pod`이 없을 경우) `node1`이나 `node3`으로 hop을 건너게 됩니다.
- 패킷을 전달 받은 `Pod`는 `node2`로 다시 패킷을 응답합니다.
- `node2`를 통해서 사용자에게 패킷이 응답됩니다.

![](/assets/images/packet-life/03-06.png)


### Local Traffic Policy

이 옵션에서는 `kube-proxy`가 전달 받을 `Pod`가 있는 노드에만 `NodePort`를 엽니다. (역자주: 예를 들어 `node1`, `node2`에만 전달 받을 `Pod`가 있는 경우, 해당 노드에만 `NodePort`를 엽니다. Cluster 모드에서는 모든 노드에 `NodePort`가 열립니다.)

`externalTrafficPolicy`를 `Local`는 `Service` 타입이 `NodePort`이거나 `LoadBalancer` 일 때만 동작합니다. 외부 트래픽을 받을 때만 의미 있기 때문입니다.

이 옵션을 사용하게 되면 `kube-proxy`는 `Pod`가 있는 노드에만 포트를 열고 그 외에는 트래픽을 전달하지 않고 drop 시킵니다. 이로써, client의 소스IP가 보존될 수 있습니다.(역자주: 다른 노드로 네트워크 hop을 건너지 않기 때문에 클라이언트 IP가 보존됩니다.)

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: NodePort
  externalTrafficPolicy: Local   # <-- 기본적으로는 Cluster이지만 사용자의 요구에 따라서 Local로 변경 가능합니다.
  selector:
    app: webapp
  ports:
    - port: 80
      targetPort: 80
      nodePort: 31380
```

Local 타입에서의 패킷 흐름은 다음과 같습니다:

- 사용자가 `Pod` endpoint가 존재하는 `node1` 서버의 `31380` 포트로 패킷을 전송합니다.
- `node1` 서버는 해당 트래픽을 클라이언트의 소스 IP를 유지한채 `Pod`로 전달합니다. 
- `node1`은 해당 트래픽을 다른 곳으로 라우팅하지 않습니다. (`Local`로 설정했기 때문에)
- 사용자가 `node2:31380`(Pod endpoint가 없는 노드)로 보내게 되는 경우에는
- 해당 패킷이 버려집니다.(dropped)

![](/assets/images/packet-life/03-07.png)

![](/assets/images/packet-life/03-08.png)

### Local traffic policy와 LoadBalancer type과의 조합

만약 GCP나 AWS와 같이 클라우드 서비스 위에서 쿠버네티스를 운영하는 경우, `externalTrafficPolicy`값을 `Local`로 설정하면 클라우드에서 제공하는 로드밸런서의 health check가 실패하게 되어 고의적으로 해당 노드로 트래픽이 전달되지 않게 됩니다.(역자주: 전달 받을 `Pod`가 없는 노드인 경우 패킷이 drop됨으로 해당 노드의 health check가 실패하게 됩니다.) 그렇기 때문에 실제적으로는 트래픽 drop이 발생하지 않게 됩니다.(그전에 로드밸런서에서 트래픽을 해당 노드로 보내지 않기 때문에) 이런 구조는 외부 트래픽이 많은 어플리케이션에서 불필요한 네트워크 hop을 없애서 지연시간(latency)를 줄여줍니다. 또한 실제 사용자의 소스 IP를 보존해주고 노드에서 SNAT 수행을 필요하지 않아도 되게 만들어 줍니다.(네트워크 hop을 거치지 않기 때문에) 하지만 외부 트래픽 정책을 `Local`로 설정할 경우, 가장 큰 단점은, 앞서 말씀 드린 것처럼 트래픽을 고르게 분산하지 못한다는 점이 있습니다.

![](/assets/images/packet-life/03-09.png)


## Kube-Proxy (iptable mode)

The component in Kubernetes that implements ‘Service’ is called kube-proxy. It sits on every node and programs complicated iptables rules to do all kinds of filtering and NAT between pods and services. If you go to a Kubernetes node and type iptables-save, you’ll see the rules inserted by Kubernetes or other programs. The most important chains are `KUBE-SERVICES`, `KUBE-SVC-*` and `KUBE-SEP-*`.

- `KUBE-SERVICES` is the entry point for service packets. What it does is that match the destination IP:port and dispatch the packet to the corresponding `KUBE-SVC-*` chain.
`KUBE-SVC-*` chain acts as a load balancer and distributes the packet to `KUBE-SEP-*chain` equally. Each `KUBE-SVC-*` has the same number of `KUBE-SEP-*` chains as the number of - endpoints behind it.
- `KUBE-SEP-*` chain represents a Service EndPoint. It simply does DNAT, replacing service IP:port with pod's endpoint IP:Port.

For DNAT, conntrack kicks in and tracks the connection state using a state machine. The state is needed because it needs to remember the destination address it changed to, and changed it back when the returning packet came back. Iptables could also rely on the conntrack state (ctstate) to decide the destiny of a packet. Those 4 conntrack states are especially important:

- `NEW`: conntrack knows nothing about this packet, which happens when the SYN packet is received.
- `ESTABLISHED`: conntrack knows the packet belongs to an established connection, which happens after the handshake is complete.
- `RELATED`: The packet doesn’t belong to any connection, but it is affiliated to another connection, which is especially useful for protocols like FTP.
- `INVALID`: Something is wrong with the packet, and conntrack doesn’t know how to deal with it. This state plays a centric role in this Kubernetes issue.

This is how the TCP connection works between pod and service; The sequence of events is:

- Client pod from the left-hand side sends a packet to a service: 2.2.2.10:80
- The packet is going through iptables rules in the client node, and the destination is changed to pod IP, 1.1.1.20:80
- Server pod handles the packet and sends back a packet with destination 1.1.1.10
- The packet is going back to the client node, conntrack recognizes the packet and rewrites the source address back to 2.2.2.10:80
- Client pod receives the response packet

GIF visualization:

![](/assets/images/packet-life/03-10.gif)


## iptables

In the Linux operating system, the firewalling is taken care of using netfilter. Which is a kernel module that decides what packets are allowed to come in or to go outside.iptables are just the interface to netfilter. The two might often be thought of as the same thing. A better perspective would be to think of it as a backend (netfilter) and a frontend (iptables).

### chains

Each chain is responsible for a specific task,

- `PREROUTING`: This chain decides what happens to a packet as soon as it arrives at the network interface. We have different options, such as altering the packet (for NAT probably), dropping a packet, or doing nothing at all and letting it slip and be handled elsewhere along the way.
- `INPUT`: This is one of the popular chains as it almost always contains strict rules to avoid some evildoers on the internet harming our computer. If you want to open/block a port, this is where you’d do it.
- `FORWARD`: This chain is responsible for packet forwarding. Which is what the name suggests. We may want to treat a computer as a router, and this is where some rules might apply to do the job.
- `OUTPUT`: This chain is the one responsible for all your web browsing among many others. You can’t send a single packet without this chain allowing it. You have a lot of -  options, whether you want to allow a port to communicate or not. It’s the best place to limit your outbound traffic if you’re not sure what port each application is communicating through.
- `POSTROUTING`: This chain is where packets leave their trace last, before leaving our computer. This is used for routing among many other tasks just to make sure the packets are treated the way we want them to.

![](/assets/images/packet-life/03-11.png)


**FORWARD** chain only works if the ip_forward enabled in the Linux server, that’s the reason the following command is important while setting up and debugging the Kubernetes cluster.

```bash
node-1# sysctl -w net.ipv4.ip_forward=1
# net.ipv4.ip_forward = 1
node-1# cat /proc/sys/net/ipv4/ip_forward
# 1
```

The above change is not persistent. To permanently enable the IP forwarding on your Linux system, edit `/etc/sysctl.conf` and add the following line:

```bash
net.ipv4.ip_forward = 1
```


## tables

We are going to focus on the NAT table, but the following are the available tables.

- `Filter`: This is the default table. In this table, you would decide whether a packet is allowed in/out of your computer. If you want to block a port to stop receiving anything, this is your stop.
- `Nat`: This table is the second most popular table and is responsible for creating a new connection. Which is shorthand for Network Address Translation. And if you’re not - familiar with the term, don’t worry. I’ll give you an example below.
- `Mangle`: For specialized packets only. This table is for changing something inside the packet either before coming in or leaving out.
- `Raw`: This table is dealing with the raw packet, as the name suggests. Mainly this is for tracking the connection state. We’ll see examples of this below when we want to allow success packets from SSH connection.
- `Security`: It is responsible for securing your computer after the filter table. Which consists of SELinux. If you’re not familiar with the term, it’s a powerful security tool on modern Linux distributions.

> Please read THIS article for more detailed info on iptables.

## iptable configuration in Kubernetes

Let’s deploy an Nginx application with replica count two in minikube and dump the iptable rules.

ServiceType: `NodePort`

```bash
master# kubectl get svc webapp
NAME TYPE CLUSTER-IP EXTERNAL-IP PORT(S) AGE
webapp NodePort 10.103.46.104 <none> 80:31380/TCP 3d13h
master# kubectl get ep webapp 
NAME ENDPOINTS AGE
webapp 10.244.120.102:80,10.244.120.103:80 3d13h
master# 
```

The ClusterIP doesn’t exist anywhere, its a virtual IP exists in iptable Kubernetes adds a DNS entry in CoreDNS.

```bash
master# kubectl exec -i -t dnsutils -- nslookup webapp.default
# Server:  10.96.0.10
# Address: 10.96.0.10#53
# Name: webapp.default.svc.cluster.local
# Address: 10.103.46.104
```

To hook into packet filtering and NAT, Kubernetes will create a custom chain KUBE-SERVICES from iptables; it will redirect all PREROUTING AND OUTPUT traffic to custom chain KUBE-SERVICES, refer to below,

```bash
$ sudo iptables -t nat -L PREROUTING | column -t
Chain            PREROUTING  (policy  ACCEPT)                                                                    
target           prot        opt      source    destination                                                      
cali-PREROUTING  all         --       anywhere  anywhere     /*        cali:6gwbT8clXdHdC1b1  */                 
KUBE-SERVICES    all         --       anywhere  anywhere     /*        kubernetes             service   portals  */
DOCKER           all         --       anywhere  anywhere     ADDRTYPE  match                  dst-type  LOCAL
```

After using KUBE-SERVICES chain hook into packet filtering and NAT, Kubernetes can inspect traffics to its services and apply SNAT/DNAT accordingly. At the end of the KUBE-SERVICES chain, it will install another custom chain KUBE-NODEPORTS to handle traffics for a specific service type NodePort.

If the traffic is for ClusterIP, the KUBE-SVC-2IRACUALRELARSND chain will process the traffic; else, the next chain will process the traffic, that is KUBE-NODEPORTS.

```bash
$ sudo iptables -t nat -L KUBE-SERVICES | column -t
Chain                      KUBE-SERVICES  (2   references)                                                                                                                                                                             
target                     prot           opt  source          destination                                                                                                                                                             
KUBE-MARK-MASQ             tcp            --   !10.244.0.0/16  10.103.46.104   /*  default/webapp                   cluster  IP          */     tcp   dpt:www                                                                          
KUBE-SVC-2IRACUALRELARSND  tcp            --   anywhere        10.103.46.104   /*  default/webapp                   cluster  IP          */     tcp   dpt:www                                                                                                                                             
KUBE-NODEPORTS             all            --   anywhere        anywhere        /*  kubernetes                       service  nodeports;  NOTE:  this  must        be  the  last  rule  in  this  chain  */  ADDRTYPE  match  dst-type  LOCAL
```

Let’s check what the chains are part of KUBE-NODEPORTS,

```bash
$ sudo iptables -t nat -L KUBE-NODEPORTS | column -t
Chain                      KUBE-NODEPORTS  (1   references)                                            
target                     prot            opt  source       destination                               
KUBE-MARK-MASQ             tcp             --   anywhere     anywhere     /*  default/webapp  */  tcp  dpt:31380
KUBE-SVC-2IRACUALRELARSND  tcp             --   anywhere     anywhere     /*  default/webapp  */  tcp  dpt:31380
```

From this point, the processing is the same for ClusterIP and NodePort. Please take a look at the iptable flow diagram as follows.

```bash
# statistic  mode  random -> Random load-balancing between endpoints.
$ sudo iptables -t nat -L KUBE-SVC-2IRACUALRELARSND | column -t
Chain                      KUBE-SVC-2IRACUALRELARSND  (2   references)                                                                             
target                     prot                       opt  source       destination                                                                
KUBE-SEP-AO6KYGU752IZFEZ4  all                        --   anywhere     anywhere     /*  default/webapp  */  statistic  mode  random  probability  0.50000000000
KUBE-SEP-PJFBSHHDX4VZAOXM  all                        --   anywhere     anywhere     /*  default/webapp  */

$ sudo iptables -t nat -L KUBE-SEP-AO6KYGU752IZFEZ4 | column -t
Chain           KUBE-SEP-AO6KYGU752IZFEZ4  (1   references)                                               
target          prot                       opt  source          destination                               
KUBE-MARK-MASQ  all                        --   10.244.120.102  anywhere     /*  default/webapp  */       
DNAT            tcp                        --   anywhere        anywhere     /*  default/webapp  */  tcp  to:10.244.120.102:80

$ sudo iptables -t nat -L KUBE-SEP-PJFBSHHDX4VZAOXM | column -t
Chain           KUBE-SEP-PJFBSHHDX4VZAOXM  (1   references)                                               
target          prot                       opt  source          destination                               
KUBE-MARK-MASQ  all                        --   10.244.120.103  anywhere     /*  default/webapp  */       
DNAT            tcp                        --   anywhere        anywhere     /*  default/webapp  */  tcp  to:10.244.120.103:80

$ sudo iptables -t nat -L KUBE-MARK-MASQ | column -t
Chain   KUBE-MARK-MASQ  (24  references)                         
target  prot            opt  source       destination            
MARK    all             --   anywhere     anywhere     MARK  or  0x4000
```

Note: Trimmed the output to show only the required rules for readability.

### ClusterIP:

KUBE-SERVICES → KUBE-SVC-XXX → KUBE-SEP-XXX

### NodePort:

KUBE-SERVICES → KUBE-NODEPORTS → KUBE-SVC-XXX → KUBE-SEP-XXX

Note: The NodePort service will have a ClusterIP assigned to handle internal and external traffic.

Visual representation of above iptable rules,

![](/assets/images/packet-life/03-12.png)


### ExtrenalTrafficPolicy: Local

As discussed before, using “externalTrafficPolicy: Local” will preserve source IP and drop packets from the agent node has no local endpoint. Let’s take a look at the iptable rules in the node with no local endpoint.

```bash
master # kubectl get nodes
# NAME           STATUS   ROLES    AGE    VERSION
# minikube       Ready    master   6d1h   v1.19.2
# minikube-m02   Ready    <none>   85m    v1.19.2
```

Deploy Nginx with externalTrafficPolicy Local.

```bash
master # kubectl get pods nginx-deployment-7759cc5c66-p45tz -o wide
# NAME                                READY   STATUS    RESTARTS   AGE   IP               NODE       NOMINATED NODE   READINESS GATES
# nginx-deployment-7759cc5c66-p45tz   1/1     Running   0          29m   10.244.120.111   minikube   <none>           <none>
```

Check externalTrafficPolicy,

```bash
master # kubectl get svc webapp -o wide -o jsonpath={.spec.externalTrafficPolicy}
# Local
```

Get the service,

```bash
master # kubectl get svc webapp -o wide
NAME     TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE   SELECTOR
webapp   NodePort   10.111.243.62   <none>        80:30080/TCP   29m   app=webserver
```

Let’s check the iptable rules in node minikube-m02; there should be a DROP rule to drop the packets as there is no local endpoint.

```bash
$ sudo iptables -t nat -L KUBE-NODEPORTS
# Chain KUBE-NODEPORTS (1 references)
# target prot opt source destination
# KUBE-MARK-MASQ tcp — 127.0.0.0/8 anywhere /* default/webapp */ tcp dpt:30080
# KUBE-XLB-2IRACUALRELARSND tcp — anywhere anywhere /* default/webapp */ tcp dpt:30080
```

Check KUBE-XLB-2IRACUALRELARSND chain,

```bash
$ sudo iptables -t nat -L KUBE-XLB-2IRACUALRELARSND
Chain KUBE-XLB-2IRACUALRELARSND (1 references)
target prot opt source destination
KUBE-SVC-2IRACUALRELARSND all — 10.244.0.0/16 anywhere /* Redirect pods trying to reach external loadbalancer VIP to clusterIP */
KUBE-MARK-MASQ all — anywhere anywhere /* masquerade LOCAL traffic for default/webapp LB IP */ ADDRTYPE match src-type LOCAL
KUBE-SVC-2IRACUALRELARSND all — anywhere anywhere /* route LOCAL traffic for default/webapp LB IP to service chain */ ADDRTYPE match src-type LOCAL
KUBE-MARK-DROP all — anywhere anywhere /* default/webapp has no local endpoints */
```

If you take a closer look, there is no issue with the Cluster level traffic; only the nodePort traffic will be dropped on this node.

‘minikube’ node iptable rules,

```bash
$ sudo iptables -t nat -L KUBE-NODEPORTS
Chain KUBE-NODEPORTS (1 references)
target prot opt source destination
KUBE-MARK-MASQ tcp — 127.0.0.0/8 anywhere /* default/webapp */ tcp dpt:30080
KUBE-XLB-2IRACUALRELARSND tcp — anywhere anywhere /* default/webapp */ tcp dpt:30080
$ sudo iptables -t nat -L KUBE-XLB-2IRACUALRELARSND
Chain KUBE-XLB-2IRACUALRELARSND (1 references)
target prot opt source destination
KUBE-SVC-2IRACUALRELARSND all — 10.244.0.0/16 anywhere /* Redirect pods trying to reach external loadbalancer VIP to clusterIP */
KUBE-MARK-MASQ all — anywhere anywhere /* masquerade LOCAL traffic for default/webapp LB IP */ ADDRTYPE match src-type LOCAL
KUBE-SVC-2IRACUALRELARSND all — anywhere anywhere /* route LOCAL traffic for default/webapp LB IP to service chain */ ADDRTYPE match src-type LOCAL
KUBE-SEP-5T4S2ILYSXWY3R2J all — anywhere anywhere /* Balancing rule 0 for default/webapp */
$ sudo iptables -t nat -L KUBE-SVC-2IRACUALRELARSND
Chain KUBE-SVC-2IRACUALRELARSND (3 references)
target prot opt source destination
KUBE-SEP-5T4S2ILYSXWY3R2J all — anywhere anywhere /* default/webapp */
```

## Headless Services

-Copied from Kubernetes documentation-

Sometimes you don’t need load-balancing and a single service IP. In this case, you can create what is termed “headless” Services by explicitly specifying "None" for the cluster IP (.spec.clusterIP).

You can use a headless Service to interface with other service discovery mechanisms without being tied to Kubernetes’ implementation.

For headless Services, a cluster IP is not allocated, kube-proxy does not handle these Services, and there is no load balancing or proxying done by the platform. How DNS is automatically configured depends on whether the Service has selectors defined:

### With selectors

For headless services that define selectors, the endpoints controller creates Endpoints records in the API, and modifies the DNS configuration to return records (addresses) that point directly to the Pods backing the Service.

```bash
master # kubectl get svc webapp-hs
NAME        TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
webapp-hs   ClusterIP   None         <none>        80/TCP    24s
master # kubectl get ep webapp-hs
NAME        ENDPOINTS                             AGE
webapp-hs   10.244.120.109:80,10.244.120.110:80   31s
```

### Without selectors

For headless services that do not define selectors, the endpoints controller does not create Endpoints records. However, the DNS system looks for and configures either:

- CNAME records for ExternalName-type Services.
- A records for any Endpoints that share a name with the Service for all other types.

If there are external IPs that route to one or more cluster nodes, Kubernetes Services can be exposed on those externalIPs. Traffic that ingresses into the cluster with the external IP (as the destination IP) on the Service port will be routed to one of the Service endpoints. externalIPsare not managed by Kubernetes and are the responsibility of the cluster administrator.


## Network Policy

By now, you might have got an idea of how the network policy is implemented in Kubernetes. Yes, the iptables again; this time, the CNI takes care of implementing the network policy, not the kube-proxy. This section should have been added to the Calico (Part 2); however, I feel this is the right place to have the network policy details.

Let’s create three services — frontend, backend, and db.

By default, pods are non-isolated; they accept traffic from any source.

![](/assets/images/packet-life/03-13.png)

However, there should be a traffic policy to isolate the DB pods from the FrontEnd pods to avoid any traffic flow between them.

![](/assets/images/packet-life/03-14.png)

I would suggest you read THIS article to understand the Network Policy configuration. This section will focus on how the network policy is implemented in Kubernetes instead of configuration deep dive.

I have applied a network policy to isolate db from the frontend pods; this results in no connection between the frontend and db pods.

Note: Above picture shows the ‘service’ symbol instead of the ‘pod’ symbol to make life easier as there can be many pods in a given service. But, the actual rules are applied per Pod.

```bash
master # kubectl exec -it frontend-8b474f47-zdqdv -- /bin/sh
# curl backend
backend-867fd6dff-mjf92
# curl db
curl: (7) Failed to connect to db port 80: Connection timed out
```

However, the backend can reach the db service without any issue.


```bash
master # kubectl exec -it backend-867fd6dff-mjf92 -- /bin/sh
# curl db
db-8d66ff5f7-bp6kf
```

Let’s take a look at the NetworkPolicy — Allow ingress from the service if it has a label ‘allow-db-access’ set to ‘true.’


```yaml
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-db-access
spec:
  podSelector:
    matchLabels:
      app: "db"
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          networking/allow-db-access: "true"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  labels:
    app: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
        networking/allow-db-access: "true"
    spec:
      volumes:
      - name: workdir
        emptyDir: {}
      containers:
      - name: nginx
        image: nginx:1.14.2
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
        volumeMounts:
        - name: workdir
          mountPath: /usr/share/nginx/html
      initContainers:
      - name: install
        image: busybox
        imagePullPolicy: IfNotPresent
        command: ['sh', '-c', "echo $HOSTNAME > /work-dir/index.html"]
        volumeMounts:
        - name: workdir
          mountPath: "/work-dir"
...
```

Calico converts the Kubernetes network policy into Calico’s native format,

```bash
master # calicoctl get networkPolicy --output yaml
apiVersion: projectcalico.org/v3
items:
- apiVersion: projectcalico.org/v3
  kind: NetworkPolicy
  metadata:
    creationTimestamp: "2020-11-05T05:26:27Z"
    name: knp.default.allow-db-access
    namespace: default
    resourceVersion: /53872
    uid: 1b3eb093-b1a8-4429-a77d-a9a054a6ae90
  spec:
    ingress:
    - action: Allow
      destination: {}
      source:
        selector: projectcalico.org/orchestrator == 'k8s' && networking/allow-db-access
          == 'true'
    order: 1000
    selector: projectcalico.org/orchestrator == 'k8s' && app == 'db'
    types:
    - Ingress
kind: NetworkPolicyList
metadata:
  resourceVersion: 56821/56821
```

The iptables rule plays an important role in enforcing the policy by using the ‘filter’ table. It’s hard to do reverse engineering as the Calico uses advanced concepts like ipset. From the iptables rules, I see that the packets are allowed to db pod only if the packets are from the backend, and that’s exactly our network policy is.

Get the workload endpoint details from the calicoctl.

```bash
master # calicoctl get workloadEndpoint
WORKLOAD                         NODE       NETWORKS        INTERFACE         
backend-867fd6dff-mjf92          minikube   10.88.0.27/32   cali2b1490aa46a   
db-8d66ff5f7-bp6kf               minikube   10.88.0.26/32   cali95aa86cbb2a   
frontend-8b474f47-zdqdv          minikube   10.88.0.24/32   cali505cfbeac50
```

cali95aa86cbb2a — Host side end of veth pair that is in use by db pod.

Let’s get the iptables rules related to this interface.

```bash
$ sudo iptables-save | grep cali95aa86cbb2a
:cali-fw-cali95aa86cbb2a - [0:0]
:cali-tw-cali95aa86cbb2a - [0:0]
-A cali-from-wl-dispatch -i cali95aa86cbb2a -m comment --comment "cali:R489GtivXlno-SCP" -g cali-fw-cali95aa86cbb2a
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:3XN24uu3MS3PMvfM" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:xyfc0rlfldUi6JAS" -m conntrack --ctstate INVALID -j DROP
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:wG4_76ot8e_QgXek" -j MARK --set-xmark 0x0/0x10000
-A cali-fw-cali95aa86cbb2a -p udp -m comment --comment "cali:Ze6pH1ZM5N1pe76G" -m comment --comment "Drop VXLAN encapped packets originating in pods" -m multiport --dports 4789 -j DROP
-A cali-fw-cali95aa86cbb2a -p ipencap -m comment --comment "cali:3bjax7tRUEJ2Uzew" -m comment --comment "Drop IPinIP encapped packets originating in pods" -j DROP
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:0pCFB_VsKq1qUOGl" -j cali-pro-kns.default
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:mbgUOxlInVlwb2Ie" -m comment --comment "Return if profile accepted" -m mark --mark 0x10000/0x10000 -j RETURN
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:I7GVOQegh6Wd9EMv" -j cali-pro-ksa.default.default
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:g5ViWVLiyVrKX91C" -m comment --comment "Return if profile accepted" -m mark --mark 0x10000/0x10000 -j RETURN
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:RBmQDo38EoPmxJ0I" -m comment --comment "Drop if no profiles matched" -j DROP
-A cali-to-wl-dispatch -o cali95aa86cbb2a -m comment --comment "cali:v3sEoNToLYUOg7M6" -g cali-tw-cali95aa86cbb2a
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:eCrqwxNk3cKw9Eq6" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:_krp5nzavhAu5avJ" -m conntrack --ctstate INVALID -j DROP
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:Cu-tVtfKKu413YTT" -j MARK --set-xmark 0x0/0x10000
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:leBL64hpAXM9y4nk" -m comment --comment "Start of policies" -j MARK --set-xmark 0x0/0x20000
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:pm-LK-c1ra31tRwz" -m mark --mark 0x0/0x20000 -j cali-pi-_tTE-E7yY40ogArNVgKt
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:q_zG8dAujKUIBe0Q" -m comment --comment "Return if policy accepted" -m mark --mark 0x10000/0x10000 -j RETURN
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:FUDVBYh1Yr6tVRgq" -m comment --comment "Drop if no policies passed packet" -m mark --mark 0x0/0x20000 -j DROP
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:X19Z-Pa0qidaNsMH" -j cali-pri-kns.default
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:Ljj0xNidsduxDGUb" -m comment --comment "Return if profile accepted" -m mark --mark 0x10000/0x10000 -j RETURN
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:0z9RRvvZI9Gud0Wv" -j cali-pri-ksa.default.default
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:pNCpK-SOYelSULC1" -m comment --comment "Return if profile accepted" -m mark --mark 0x10000/0x10000 -j RETURN
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:sMkvrxvxj13WlTMK" -m comment --comment "Drop if no profiles matched" -j DROP
$ sudo iptables-save -t filter | grep cali-pi-_tTE-E7yY40ogArNVgKt
:cali-pi-_tTE-E7yY40ogArNVgKt - [0:0]
-A cali-pi-_tTE-E7yY40ogArNVgKt -m comment --comment "cali:M4Und37HGrw6jUk8" -m set --match-set cali40s:LrVD8vMIGQDyv8Y7sPFB1Ge src -j MARK --set-xmark 0x10000/0x10000
-A cali-pi-_tTE-E7yY40ogArNVgKt -m comment --comment "cali:sEnlfZagUFRSPRoe" -m mark --mark 0x10000/0x10000 -j RETURN
```

By checking the ipset, it is clear that the ingress to db pod allowed only from the backend pod IP 10.88.0.27

```bash
[root@minikube /]# ipset list
Name: cali40s:LrVD8vMIGQDyv8Y7sPFB1Ge
Type: hash:net
Revision: 6
Header: family inet hashsize 1024 maxelem 1048576
Size in memory: 408
References: 3
Number of entries: 1
Members:
10.88.0.27
```

I’ll update Part 2 of this series with more detailed steps to decode the calico iptables rules.

## References:

- https://kubernetes.io
- https://www.projectcalico.org/
- https://rancher.com/ 
- http://www.netfilter.org/


## 마치며








