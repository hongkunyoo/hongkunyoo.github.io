---
layout: post
title:  "Calico 라우팅 모드"
date:   2021-10-27 00:00:00
categories: network calico
image: /assets/images/sealedsecret/landing.png
permalink: /:title
---

원글: [Calico Routing Modes](https://octetz.com/docs/2020/2020-10-01-calico-routing-modes/)

Calico는 어떻게 트래픽을 라우팅할까요? 많은 이들은 Calico가 따로 가상 네트워크를 사용하지 않고 [BGP](https://en.wikipedia.org/wiki/Border_Gateway_Protocol)를 사용하기 때문의 빠른 네트워크 속도를 가진다고 말합니다. 이 말은 완벽히 틀린 말은 아닙니다. Calico는 이러한 모드로 동작 가능합니다. 하지만 이것이 기본 설정값은 아닙니다. 그리고 BGP를 이용하여 트래픽을 라우팅한다는 얘기는 흔한 오해 중 하나입니다. 물론 BGP를 이용하긴 하지만 오직 BGP만 있는 것은 아닙니다. [IP-in-IP](https://en.wikipedia.org/wiki/IP_in_IP)나 [VXLAN](https://en.wikipedia.org/wiki/Virtual_Extensible_LAN) 방법을 이용하여 트래픽을 라우팅할 수도 있습니다. 이번 포스트에서는 Calcio의 라우팅 모드에 대해서 설명하고 BGP 프로토콜이 어떻게 사용되는지 알아보겠습니다.

> 원작자가 유튜브로도 설명하는 영상이 있습니다: [유튜브 비디오 설명](https://www.youtube.com/watch?v=MpbIZ1SmEkU)

## 데모 네트워크 구조

데모를 보여드리기 위해, AWS 위에 어떤 구조로 구성하였는지 먼저 설명 드립니다. Terraform을 이용하여 [직접 구성](https://github.com/octetz/calico-routing/blob/master/servers.tf)하실 수도 있고 Calico 설정 방법도 [여기](https://raw.githubusercontent.com/octetz/calico-routing/master/calico.yaml)에 있습니다.

![](/assets/images/calico-routing-mode/01.png)

단순함을 위해 단일 마스터 클러스터를 사용합니다. 워커 노드들은 2개 가용 영역(availability zone)에 걸쳐 구성되어 있습니다. subnet 1에 2개의 워커가, subnet 2에 1개 워커가 있습니다. Calico 컨테이너는 모든 노드 위에 하나씩 실행 중입니다. 이번 포스트 전반에 걸쳐 다음과 같이 구성되어 있습니다.

|-----------|-------------|----------|
| Node      | IP          | subnet   |
|-----------|-------------|----------|
| master    | 10.30.0.136 | subnet 1 |
| worker-1  | 10.30.0.206 | subnet 1 |
| worker-2  | 10.30.0.56  | subnet 1 |
| worker-3  | 10.30.1.66  | subnet 2 |
|-----------|-------------|----------|



```bash
kubectl get nodes
# NAME       STATUS   ROLES    AGE     VERSION
# master     Ready    master   6m55s   v1.17.0
# worker-1   Ready    <none>   113s    v1.17.0
# worker-2   Ready    <none>   77s     v1.17.0
# worker-3   Ready    <none>   51s     v1.17.0
```

Pod의 이름들은 각각 `pod-1`, `pod-2` 그리고 `pod-3`으로 되어 있습니다.

```bash
kubectl get pod -no wide
# NAME    READY   STATUS    RESTARTS   AGE     NODE
# pod-1   1/1     Running   0          4m52s   worker-1
# pod-2   1/1     Running   0          3m36    worker-2
# pod-3   1/1     Running   0          3m23s   worker-3
```

## 라우팅 정보 공유

기본적으로, Calico는 호스트간 라우팅 정보를 공유하기 위해 BGP 프로토콜을 사용합니다. 이를 위해 `calico-node`라는 이름의 Pod가 모든 노드에서 실행됩니다. 각각의 `calico-node`는 서로 BGP peering되어 있습니다.

![](/assets/images/calico-routing-mode/02.png)

`calico-node`는 내부적으로 두가지 프로세스를 가집니다.

- `BIRD`: BGP를 이용하여 라우팅 정보를 공유하는 역할을 담당합니다.
- `Felix`: 호스트의 라우팅 테이블을 조작하는 역할을 담당합니다.

`BIRD`는 고급 BGP 설정으로 구성할 수 있습니다: route reflector를 사용한다던지, 클러스터 외부의 다른 BGP 라우터랑 peering을 맺는 것이 가능합니다. (역자주: route reflector란 자신의 라우팅 정보를 또 다시 다른 라우터에게 전달하는 역할만 핵심으로 수행하는 라우터를 말합니다. 이를 통해 full mesh peering이 아닌 거점 peering이 가능하게 해줍니다. [예전 네트워크 포스트](https://coffeewhale.com/packet-network2#bird-bgp)도 참고해 주시기 바랍니다.)

`calicoctl`을 이용하면 peering을 맺고 있는 노드들을 확인할 수 있습니다.

```bash
$master# sudo calicoctl node status 

Calico process is running.
IPv4 BGP status
+--------------+-------------------+-------+----------+-------------+
| PEER ADDRESS |     PEER TYPE     | STATE |  SINCE   |    INFO     |
+--------------+-------------------+-------+----------+-------------+
| 10.30.0.206  | node-to-node mesh | up    | 18:42:27 | Established |
| 10.30.0.56   | node-to-node mesh | up    | 18:42:27 | Established |
| 10.30.1.66   | node-to-node mesh | up    | 18:42:27 | Established |
+--------------+-------------------+-------+----------+-------------+

IPv6 BGP status
No IPv6 peers found.
```

각각의 호스트 IP는 peering하고 있는 상대 노드 주소를 나타냅니다. master 노드에서 실행한 결과입니다:

- `10.30.0.206`: worker-1
- `10.30.0.56` : worker-2
- `10.30.1.66` : worker-3

라우팅 정보가 공유되면 이것을 실제 route table에 적용하는 것은 `Felix`의 일입니다.

```bash
# run on master
$ route -n

Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         10.30.0.1       0.0.0.0         UG    100    0        0 ens5
10.30.0.0       0.0.0.0         255.255.255.0   U     0      0        0 ens5
10.30.0.1       0.0.0.0         255.255.255.255 UH    100    0        0 ens5
172.17.0.0      0.0.0.0         255.255.0.0     U     0      0        0 docker0
192.168.97.192  10.30.1.66      255.255.255.192 UG    0      0        0 tunl0
192.168.133.192 10.30.0.56      255.255.255.192 UG    0      0        0 tunl0
192.168.219.64  0.0.0.0         255.255.255.192 U     0      0        0 *
192.168.219.65  0.0.0.0         255.255.255.255 UH    0      0        0 cali50e69859f2f
192.168.219.66  0.0.0.0         255.255.255.255 UH    0      0        0 calif52892c3dce
192.168.226.64  10.30.0.206     255.255.255.192 UG    0      0        0 tunl0
```

위의 라우팅 정보는 IP-in-IP로 구성되어 있습니다. 각 호스트의 pod CIDR(Destination + Genmask)는 `tunl0`으로 향합니다. IP를 가진 Pod는 `cali*`라는 이름의 네트워크 인터페이스를 가집니다. 이것은 네트워크 정책을 부여하기 위해 존재합니다.

## 라우팅 모드

Calico는 3가지 라우팅 모드를 지원합니다.

- `IP-in-IP`: 기본값; encapsulated
- `Direct`: unencapsulated
- `VXLAN`: BGP 사용 안함; encapsulated

`IP-in-IP` 와 `VXLAN`는 패킷을 캡슐화 합니다. 캡슐화된 패킷은 본인이 가상 네트워크가 아닌 물리 네트워크 위에 있다고 착각하게 됩니다.(역자주: 캡슐화된 패킷 안에서 보면 자신이 캡슐화된지 모르기 때문에 자신이 일반적인 물리 네트워크에서 동작하는 것처럼 느껴질 것입니다.) 이를 통해 쿠버네티스는 호스트 네트워크와는 별개인 가상 Pod 네트워크를 운영할 수 있습니다.

### IP-in-IP

`IP-in-IP`는 IP를 또 다른 IP 안에 집어 넣음으로써 캡슐화를 수행합니다. 전송되는 패킷에는 외부 헤더(outer header)와 내부 헤더(inner header)가 있습니다. 외부 헤더에는 호스트 네트워크의 출발지와 목적지 IP가 들어 있으며 내부 헤더에는 Pod 네트워크의 출발지, 목적지 IP가 있습니다.

![](/assets/images/calico-routing-mode/03.png)


`IP-in-IP` 모드에서 worker-1의 라우팅 테이블은 다음과 같다고 생각해 봅시다:

```bash
# run on worker-1
sudo route
```

![](/assets/images/calico-routing-mode/04.png)

pod-1에서 pod-2로 패킷을 전달해 봅시다.

```bash
# sent from inside pod-1
curl 192.168.133.194
```

![](/assets/images/calico-routing-mode/05.png)

`IP-inIP` 모드 안에서도 두개의 옵션이 있습니다. subnet 내부의 통신이냐 외부의 통신이냐에 따라서 옵션을 선택할 수 있습니다. 뒤에서 다시 설명 드리겠습니다.

제가 생각했을 때 Calico에서 `IP-in-IP` 모드가 기본값인 이유는 이 모드는 어떤 상황에서 별 문제 없이 잘 동작하기 때문입니다. 예를 들어

IP-in-IP also features a selective mode. It is used when only routing between subnets requires encapsulation. I’ll explore this in the next section.

I believe IP-in-IP is Calico’s default as it often just works. For example, networks that reject packets without a host's IP as the destination or packets where routers between subnets rely on the destination IP for a host.

### Direct

Direct is a made up word I’m using for non-encapsulated routing. Direct sends packets as if they came directly from the pod. Since there is no encapsulation and de-capsulation overhead, direct is highly performant.

To route directly, the Calico IPPool must not have IP-in-IP enabled.

To modify the pool, download the default ippool.

```bash
calicoctl get ippool default-ipv4-ippool -o yaml > ippool.yaml 
```

Disable IP-in-IP by setting it to `Never`.

```yaml
apiVersion: projectcalico.org/v3
kind: IPPool
metadata:
  # remove creationTimestamp, resourceVersion,
  # and uid if present
  name: default-ipv4-ippool
spec:
  blockSize: 26
  cidr: 192.168.0.0/16
  ipipMode: Never
  natOutgoing: true
  nodeSelector: all()
  vxlanMode: Never
```

Apply the change.

```bash
calicoctl apply -f ippool.yaml 
```

On `worker-1`, the route table is updated.

```bash
route -n
```

![](/assets/images/calico-routing-mode/06.png)


2 important changes are:

1. The tunl0 interface is removed and all routes point to ens5.
2. worker-3's route points to the network gateway (10.30.0.1) rather than the host. This is because worker-3 is on a different subnet. With direct routing, requests from pod-1 to pod-2 fail.

```bash
# sent from pod-1
$ curl -v4 192.168.133.194 --max-time 10

*   Trying 192.168.133.194:80...
* TCP_NODELAY set
* Connection timed out after 10001 milliseconds
* Closing connection 0
curl: (28) Connection timed out after 10001 milliseconds
```

Packets are blocked because src/dst checks are enabled. To fix this, disable these checks on every host in AWS.

![](/assets/images/calico-routing-mode/07.png)


Traffic is now routable between pod-1 and pod-2. The wireshark output is as follows.

```bash
curl -v4 192.168.133.194
```

![](/assets/images/calico-routing-mode/08.png)

However, communication between pod-1 and pod-3 now fails.

```bash
# sent from pod-1 
$ curl 192.168.97.193 --max-time 10

curl: (28) Connection timed out after 10000 milliseconds
```

Do you remember the updated route table? On worker-1, traffic sent to worker-3 routes to the network gateway rather than to worker-3. This is because worker-3 lives on a different subnet. When the packet reaches the network gateway, it does not have a routable IP address, instead it only sees the pod-3 IP.

Calico supports a CrossSubnet setting for IP-in-IP routing. This setting tells Calico to only use IP-in-IP when crossing a subnet boundary. This gives you high-performance direct routing inside a subnet and still enables you to route across subnets, at the cost of some encapsulation.

![](/assets/images/calico-routing-mode/09.png)

To enable this, update the IPPool as follows.

```yaml
apiVersion: projectcalico.org/v3
kind: IPPool
metadata:
  name: default-ipv4-ippool
spec:
  blockSize: 26
  cidr: 192.168.0.0/16
  ipipMode: CrossSubnet
  natOutgoing: true
  nodeSelector: all()
  vxlanMode: Never
```

```bash
calicoctl apply -f ippool.yaml 
```

Now routing between all pods works! Examining worker-1's route table:

![](/assets/images/calico-routing-mode/10.png)


The tunl0 interface is reintroduced for routing to worker-3.

### VXLAN

VXLAN routing is supported in Calico 3.7+. Historically, to route traffic using VXLAN and use Calico policy enforcement, you’d need to deploy Flannel and Calico. This was referred to as Canal. Whether you use VXLAN or IP-in-IP is determined by your network architecture. VXLAN is feature rich way to create a virtualized layer 2 network. It fosters larger header sizes and likely requires more processing power to facilitate. VXLAN is great for networks that do not support IP-in-IP, such as Azure, or don’t support BGP, which is disabled in VXLAN mode.

Setting up Calico to use VXLAN fundamentally changes how routing occurs. Thus rather than altering the IPPool, I'll be redeploying on a new cluster.

To enable VXLAN, as of Calico 3.11, you need to make the following 3 changes to the Calico manifest.

1. Set the backend to vxlan.

```yaml
kind: ConfigMap 
apiVersion: v1 
metadata: 
  name: calico-config 
  namespace: kube-system 
data: 
  # Typha is disabled. 
  typha_service_name: “none” 
  # value changed from bird to vxlan 
  calico_backend: “vxlan” 
```

2 Set the CALICO_IPV4_IPIP pool to CALICO_IPV4_VXLAN.

```yaml
            # Enable VXLAN
            - name: CALICO_IPV4POOL_VXLAN
              value: "Always"
```

Disable BGP-related liveness and readiness checks.

```yaml
livenessProbe:
  exec:
    command:
    - /bin/calico-node
    - -felix-live
# disable bird liveness test
#    - -bird-live
  periodSeconds: 10
  initialDelaySeconds: 10
  failureThreshold: 6
readinessProbe:
  exec:
    command:
    - /bin/calico-node
    - -felix-ready
# disable bird readiness test
#    - -bird-ready
  periodSeconds: 10
```

Then apply the modified configuration.

```bash
kubectl apply -f calico.yaml 
```

With VXLAN enabled, you can now see changes to the route tables.

![](/assets/images/calico-routing-mode/11.png)

Inspecting the packets shows the VXLAN-style encapsulation and how it differs from IP-in-IP.

![](/assets/images/calico-routing-mode/12.png)

## Summary

Now that we've explored routing in Calico using IP-in-IP, Direct, and VXLAN, I hope you’re feeling more knowledgable about Calico’s routing options. Additionally, I hope these options demonstrate that Calico is a fantastic container networking plugin, extremely capable in most network environments.

