---
layout: post
title:  "[번역]Calico 라우팅 모드"
date:   2022-03-29 00:00:00
categories: network calico
image: /assets/images/calico-routing-mode/landing.png
permalink: /:title
---
Calico는 간단하면서도 다양한 네트워킹 모드들을 제공하기 때문에 쿠버네티스 네트워킹에서 단골 소재로 나오는 CNI입니다. 이번 포스트는 컨테이너 네트워크 namespace나 CNI의 인터페이스가 동작하는 방법(서버 내에서 컨테이너 레벨의 네트워크)보다는 리눅스 네트워크 레벨(리눅스 서버간 패킷을 주고 받는 과정)에서 패킷이 어떻게 라우팅되는지를 집중적으로 소개하는 글입니다.

원글: [Calico Routing Modes](https://octetz.com/docs/2020/2020-10-01-calico-routing-modes/)

---

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
$ sudo calicoctl node status 

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

![](/assets/images/calico-routing-mode/03.jpeg)


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

제가 생각했을 때 Calico에서 `IP-in-IP` 모드가 기본값인 이유는 이 모드는 어떤 상황에서 별 문제 없이 잘 동작하기 때문입니다. 예를 들어 목적지 IP가 호스트 네트워크의 IP가 아닌 경우 패킷을 차단하는 네트워크 환경(역자주: AWS와 같은 환경에서 체크하는 옵션이 있습니다.)에서나 subnet간 패킷 라우팅을 위해 호스트 네트워크 IP가 필요한 경우에도 잘 동작합니다.

### Direct

`Direct`라는 용어는 제가 만들어낸 용어입니다. 이것은 단지 캡슐화되지 않는(non-encapsulated) 라우팅을 의미합니다. `Direct` 모드에서는 패킷을 캡슐화하지 않고 Pod에서 바로 패킷을 보낸 것처럼 동작합니다.(역자주: 호스트 네트워크를 라우팅할 때 Pod IP가 그대로 노출되어 라우팅됩니다.) 이 모드에서는 캡슐화, 디캡슐화 오버헤드가 없기 때문에 성능상 이점이 있습니다.

`Direct`를 사용하기 위해서 [Calico IPPool](https://projectcalico.docs.tigera.io/reference/resources/ippool#ip-pool-definition)의 IP-in-IP 기능이 활성화되어 있으면 안됩니다. 이 IPPool을 수정하기 위해 다음과 같이 기본 IPPool 설정을 추출합니다.

```bash
calicoctl get ippool default-ipv4-ippool -o yaml > ippool.yaml 
```

`IP-in-IP` 세팅을 `Never`로 수정합니다.

```yaml
apiVersion: projectcalico.org/v3
kind: IPPool
metadata:
  name: default-ipv4-ippool
spec:
  blockSize: 26
  cidr: 192.168.0.0/16
  ipipMode: Never     # 수정 부분
  natOutgoing: true
  nodeSelector: all()
  vxlanMode: Never
```

변경 사항을 적용합니다.

```bash
calicoctl apply -f ippool.yaml 
```

`worker-1`의 라우팅 테이블을 다시 살펴 봅시다.

```bash
route -n
```

![](/assets/images/calico-routing-mode/06.png)


중요한 두가지 변경을 살펴 봅시다:

1. `tunl0` 인터페이스가 사라지고 모든 라우팅 경로가 `ens5`를 바라보게 되었습니다.
2. `worker-3` 라우트 정보가 기존 호스트에서 게이트웨이를 바라보게 되었습니다.(`10.30.0.1`) `worker-3` 노드가 다른 subnet에 있기 때문입니다. 

`Direct` 모드에서는 `pod-1`에서 `pod-2`로의 요청이 실패하게 됩니다.

```bash
# sent from pod-1
$ curl -v4 192.168.133.194 --max-time 10

*   Trying 192.168.133.194:80...
* TCP_NODELAY set
* Connection timed out after 10001 milliseconds
* Closing connection 0
curl: (28) Connection timed out after 10001 milliseconds
```

이것은 AWS의 `src/dst` IP 체크 기능 때문입니다. IP 통신을 가능하게 만들기 위해 해당 기능을 AWS에서 끕니다.

![](/assets/images/calico-routing-mode/07.png)

이제 `pod-1`에서 `pod-2`로 통신이 잘 됩니다.

```bash
curl -v4 192.168.133.194
```

wireshark의 결과는 다음과 같습니다:

![](/assets/images/calico-routing-mode/08.png)

However, communication between pod-1 and pod-3 now fails.

하지만 `src/dst`의 기능을 비활성화 했음에도 불구하고 `pod-1`에서 `pod-3`으로의 통신은 실패합니다.

```bash
# sent from pod-1 
$ curl 192.168.97.193 --max-time 10

curl: (28) Connection timed out after 10000 milliseconds
```

위에서의 라우팅 테이블 정보가 기억 나시나요? `worker-3`으로의 트래픽은 곧 바로 `worker-3`으로 전달되기 보다는 게이트웨이로 트래픽이 전달됩니다. 그 이유는 `worker-3` 노드는 다른 subnet에 위치하기 때문입니다. 패킷이 네트워크 게이트웨이에 도달하게 되면 게이트웨이는 해당 IP를 어디로 전달해야 할지 모르는 상황이 됩니다.(역자주: `Direct`이기 때문에 Pod IP가 그대로 게이트웨이로 전달되는데 게이트웨이는 해당 IP가 호스트 네트워크 IP가 아니기 때문에 어디로 전달해야 할지 알 수 없습니다.)

Calico에서는 이러한 문제점을 막기 위해 subnet간 통신에서만 `IP-in-IP` 기능을 활성화 시키는 옵션인 `CrossSubnet` 기능을 제공합니다. 이 기능을 활성화하면 다른 subnet으로 패킷이 라우팅 될 때에는 자동으로 `IP-in-IP` 모드로 동작하게 됩니다. 이를 통해 subnet 안에서는 direct로 빠른 속도로 통신할 수 있고 subnet간 통신도 캡슐화를 활용하여 전송 가능하게 만들 수 있습니다.

![](/assets/images/calico-routing-mode/09.png)

`CrossSubnet`을 활성화하기 위해서는 다음과 같이 설정합니다.

```yaml
apiVersion: projectcalico.org/v3
kind: IPPool
metadata:
  name: default-ipv4-ippool
spec:
  blockSize: 26
  cidr: 192.168.0.0/16
  ipipMode: CrossSubnet  # Never --> CrossSubnet
  natOutgoing: true
  nodeSelector: all()
  vxlanMode: Never
```

```bash
calicoctl apply -f ippool.yaml 
```

Now routing between all pods works! Examining worker-1's route table:

이제 subnet간 통신도 가능하게 되었습니다. `worker-1`의 라우팅 테이블을 살펴 봅시다:

![](/assets/images/calico-routing-mode/10.png)

`worker-3`으로 가는 패킷에 한하여 `ens5` 인터페이스가 사라지고 `tunl0` 인터페이스가 다시 생겼습니다.

### VXLAN

`VXLAN` 라우팅은 Calico 3.7 이상부터 지원합니다. 역사적으로 `VXLAN` 기능을 사용하고 Calico의 네트워크 정책 기능을 사용하기 위해 Calico와 Flannel을 동시에 사용하였습니다. 이것을 주로 Canal이라고 불렀습니다. `VXLAN`과 `IP-in-IP`는 네트워크 구조에 따라 선택하였습니다. `VXLAN`은 가상 layer 2 네트워크를 구성하기 위해 사용됩니다. 그래서 일반적인 패킷보다 조금 더 큰 헤더 사이즈를 가지게 되고 약간의 성능 저하가 발생합니다. `VXLAN`은 Azure와 같이 `IP-in-IP` 기능이 지원되지 않는 환경이나 BGP를 지원하지 않는 환경에서 사용하기 용이합니다.

`VXLAN`은 Calico가 동작하는 근본적인 방법과 다르기 때문에 `IPPool` 설정값을 바꾸는 선에서 해결할 수는 없고 Calico를 클러스터에 새롭게 재배포해야 합니다.
`VXLAN`을 활성화 하기 위해서 다음과 같이 Calico manifest 파일을 수정해야 합니다.


1. `calico_backend`를 `vxlan`으로 수정합니다.

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

2 `CALICO_IPV4_IPIP`값을 `CALICO_IPV4_VXLAN`로 수정합니다.

```yaml
            # Enable VXLAN
            - name: CALICO_IPV4POOL_VXLAN
              value: "Always"
```

BGP를 사용하는 `bird` health 체크를 비활성화합니다.

```yaml
livenessProbe:
  exec:
    command:
    - /bin/calico-node
    - -felix-live 
#   - -bird-live     <-- 주석처리
  periodSeconds: 10
  initialDelaySeconds: 10
  failureThreshold: 6
readinessProbe:
  exec:
    command:
    - /bin/calico-node
    - -felix-ready
#    - -bird-ready   <-- 주석처리
  periodSeconds: 10
```

Calico를 다시 배포합니다.

```bash
kubectl apply -f calico.yaml 
```

`VXLAN`을 활성화하며 다음과 같이 라우팅 테이블 정보가 변경된 것을 확인할 수 있습니다.

![](/assets/images/calico-routing-mode/11.png)

`VXLAN`을 이용하면 IP 레벨이 아닌 MAC 레벨에서 캡슐화가 이루어지는 것을 확인할 수 있습니다.

![](/assets/images/calico-routing-mode/12.png)

## 마무리하며

이번 포스트를 통해 Calico가 동작하는 모드에 대해서 각각 살펴 봤습니다. 이를 통해 Calico CNI가 대부분의 네트워크에서 동작 가능한 매우 매력적인 CNI 프로젝트라는 것을 알게 되었길 바랍니다.

