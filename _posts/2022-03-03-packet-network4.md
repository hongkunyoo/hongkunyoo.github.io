---
layout: post
title:  "[번역]쿠버네티스 패킷의 삶 - #4"
date:   2022-03-03 00:00:00
categories: kubernetes network
image: /assets/images/packet-life/landing04.png
permalink: /:title
---
쿠버네티스 패킷의 삶 마지막 편, #4에서는 Ingress 리소스에 대해서 살펴 봅니다.

## 쿠버네티스 패킷의 삶 시리즈

1. [컨테이너 네트워킹과 CNI](/packet-network1): 리눅스 네트워크 namespace와 CNI 기초
2. [Calico CNI](/packet-network2): CNI 구현체 중 하나인, Calico CNI 네트워킹
3. [Service 네트워킹](/packet-network3): Service, 클러스터 내/외부 네트워킹 설명
4. Ingress: Ingress Controller에 대한 설명([원글](https://dramasamy.medium.com/life-of-a-packet-in-kubernetes-part-4-4dbc5256050a))

---

쿠버네티스 패킷의 삶, 네번째 시리즈는 Ingress와 Ingress Controller에 대한 내용입니다. Ingress Controller란 쿠버네티스 API서버를 통해 Ingress 리소스의 변화를 추적하고 그에 맞게 L7 로드밸런서를 설정하는 역할을 담당합니다.

## Nginx Controller와 로드밸런서 (proxy)

Ingress Controller는 Ingress 리소스에 맞춰 로드밸런서를 요청대로 설정하는 역할을 수행하는데 이때 로드밸런서는 쿠버네티스 Pod 형태로 존재하는 소프트웨어 로드밸런서(Nginx Controller의 경우)로 구성할 수 있고 클라우드에서 제공하는 로드밸런서(AWS ALB Controller의 경우)로 구성할 수 있습니다. 각기 다른 로드밸런서에는 다른 Ingress Controller가 필요합니다.

![](/assets/images/packet-life/04-01.png)

Ingress의 가장 기본적인 역할은 L7 레벨의 요청에 대한 트래픽을 관리하는 역할을 담당합니다.(traffic management) 특히 HTTP(S)에 대해서 말이죠. Ingress를 사용하면 특정 서비스를 외부로 노출 시키기 위해 매번 로드밸런서를 생성할 필요 없이(역자주: 이때 얘기하는 로드밸런서는 `type: LoadBalancer`에 해당하는 L4 로드밸런서를 의미합니다.) 라이팅 규칙을 설정할 수 있습니다. 또한 특정 서비스에 외부에서 접근 가능한 URL을 부여하고 부하를 분산 시킬 수도 있으며 SSL/TLS termination, host-based 라우팅, content-based 라우팅 등 여러가지 규칙들을 적용할 수 있습니다. 


## 설정 방법 소개

Ingress controller는 L7 레벨의 규칙을 설정하기 위해 다른 리소스와 구분된 특별한 리소스를 사용하고 그것을 Ingress라 부릅니다. 

Ingress controller는 서로 다른 Ingress Controller들을 구분하기 위해 Ingress Class라는 값을 사용합니다. 이를 통해 서로 다른 Ingress Controller 구현체들이 한 클러스터 내에 동시에 존재할 수 있게 해줍니다. Ingress Controller들은 자신에게 해당하는 특정 Ingress Class에만 규칙을 처리합니다.

> 역자주: 쉽게 생각해서 A라는 Ingress Controller는 A ingress class에 해당하는 Ingress만 처리합니다.

### Prefix Based

`kubernetes.io/ingress.class` 부분이 특정 Ingress class를 나타내는 annotation 입니다. 쿠버네티스 v1.18부터는 `ingressClassName`라는 필드 이름을 사용합니다.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prefix-based
  annotations:
    kubernetes.io/ingress.class: "nginx-ingress-inst-1"
spec:
  rules:
  - http:
      paths:
      - path: /video
        pathType: Prefix
        backend:
          service:
            name: video
            port:
              number: 80
      - path: /store
        pathType: Prefix
        backend:
          service:
            name: store
            port:
              number: 80
```

`spec.rules[0].http.paths[0].path: /video` 부분이 prefix를 지정하는 필드입니다. 해당 prefix에 따라 video라는 Service로 트래픽이 라우팅됩니다.

```bash
curl $HOST/video
```

### Host-Based

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: host-based
  annotations:
    kubernetes.io/ingress.class: "nginx-ingress-inst-1"
spec:
  rules:
  - host: "video.example.com"
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: video
            port:
              number: 80
  - host: "store.example.com"
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: store
            port:
              number: 80
```

`spec.rules[0].host: video.example.com` 부분이 host를 지정하는 필드입니다. 해당 virtual host에 따라 video라는 Service로 트래픽이 라우팅됩니다.
물론 `video.example.com`에 해당하는 DNS query값이 Ingress controller의 IP로 향해 있어야 합니다. 기본적으로 쿠버네티스에서 DNS 설정까지 수행해주지 않습니다. 각 클라우드 프로바이더에서는 권한설정, annotation 설정에 따라 DNS를 자동으로 매핑시켜 주기도 합니다.

```bash
curl video.example.com
```

### Host + Prefix

```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: host-prefix-based
  annotations:
    kubernetes.io/ingress.class: "nginx-ingress-inst-1"
spec:
  rules:
  - host: foo.com
    http:
      paths:
      - backend:
          serviceName: foovideo
          servicePort: 80
        path: /video
      - backend:
          serviceName: foostore
          servicePort: 80
        path: /store
  - host: bar.com
    http:
      paths:
      - backend:
          serviceName: barvideo
          servicePort: 80
        path: /video
      - backend:
          serviceName: barstore
          servicePort: 80
        path: /store
```

위에서 살펴본 두가지 기능을 조합할 수도 있습니다.

```bash
curl foo.com/video
```

Ingress는 기본 내장된 Controller를 가지지 않는 쿠버네티스 기본 리소스 중에 하나입니다. (역자주: Deployment 리소스는 Deployment Controller가, DaemonSet은 Daemonset Controller가 기본적으로 내장되어 있지만 Ingress는 그렇지 않습니다.; 논리적으로 각 리소스마다 Controller가 있지만 구체적으로는 전부 `kube-controller-manager`에 하나의 binary로 포함되어 있습니다.)

그렇기 때문에 사용자가 직접 Ingress Controller를 설치해야 합니다. 이때 설치할 수 있는 Ingress controller는 다양하게 있지만 여기서는 Nginx와 Contour에 대해서 살펴 보겠습니다.

앞서 설명 드린대로 Ingress API는 Ingress 리소스와 Ingress Controller로 구성되어 있고 Ingress가 바라는 상태(desired state)를 나타내고 Ingress Controller가 그 바라는 상태에 맞게 실제로 L7 로드밸런서를 설정하는 역할을 수행합니다.

Ingress 리소스는 단순히 메타데이터(바라는 상태)만 가지고 있고 Ingress Controller가 힘든 역할을 다 수행합니다. (역자주: 사실 모든 Controller가 다 이러한 방식으로 동작합니다.) Ingress Controller는 다양한 구현체로 구성할 수 있고 종종 여러 Ingress Controller 구현체를 조합하여 사용하기도 합니다. 예를 들어, SSL 인증서 연결이 필요한 외부 트래픽 처리용 Ingress Controller와 별다른 TLS 설정이 필요없는 클러스터 내부용 Ingress Controller로 구분할 수 있습니다.


## 배포 설정

### Contour + Envoy

Contour Ingress Controller는 다음과 같은 컴포넌트로 구성되어 있습니다:

- Envoy: 고성능 reverse proxy로 사용됩니다. (실제 트래픽 처리 수행)
- Contour: Envoy를 컨트롤하는 관리 서버로 사용됩니다.

이들 컴포넌트들은 개별적으로 배포가 됩니다. Contour은 Deployment로 Envoy는 Daemonset으로 배포됩니다.(다른 방식으로도 배포가 가능하긴 합니다.) Contour 컴포넌트가 쿠버네티스 API를 이용하여 다음과 같은 리소스들을 추적합니다: Ingress, HTTP proxy, Secret, Service 그리고 Endpoint 이러한 리소스들을 지켜보고 있다가 설정값이 변경되었을 때 Envoy가 이해할 수 있는 JSON 형식으로 변환하는 역할을 수행합니다.

아래 예시가 host network(0.0.0.0:80)를 활성화한 EnvoyProxy를 도식화한 것입니다.

![](/assets/images/packet-life/04-02.png)

### Nginx

Nginx Ingress Controller의 목표는 설정 파일(nginx.conf)을 잘 작성하는 것입니다. 이 뜻은 새로운 변경 사항이 있을 때마다 nginx.conf 파일을 매번 reload해야 한다는 것을 의미합니다. 다행인 것은 upstream 서버(역자주: 여기서는 Pod를 의미합니다.)가 변경될 때마다 nginx.conf 파일을 reload해야 할 필요는 없다는 것입니다. (역자주: Pod가 재시작되면 Pod의 Endpoint가 바뀌게 되어 nginx 입장에서는 upstream 서버 설정이 바뀐 것으로 보입니다.) 이것이 가능한 이유는 바로 `lua-nginx-module`이라는 모듈을 사용하기 때문입니다.

Endpoint가 매번 바뀔 때마다, Nginx Controller는 바라보는 Service의 모든 Endpoint를 fetch하여 대응되는 backend 객체를 생성합니다. 그리고 이것을 nginx 내부에서 실행되고 있는 Lua handler로 전달합니다. Lua 코드는 이것을 shared memory 영역에 저장합니다. 그러면 매번 요청이 생길 때마다 `balancer_by_lua` 컨텍스트에서 실행되는 Lua 코드가 어떤 Endpoint로 트래픽을 보내야 할지 알게 됩니다. 그리고 나머지는 Nginx가 알아서 처리하게 됩니다. 바로 이런 방법을 이용하여 Endpoint 변경 시에 설정파일 reload 작업 없이 upstream 서버의 주소를 알 수 있게 되는 것입니다. 이러한 방식은 규모가 큰 클러스터에서 많은 어플리케이션들이 빈번하게 생성되었다가 삭제될 때, 많은 양의 reload 작업을 피하게 해주어서 응답성 및 부하분산 품질을 저해(reload 이후에 부하분산 state가 reset되기 때문에) 시키지 않고 Nginx Controller가 동작할 수 있게 해줍니다.

#### Nginx + Keepalived — 고가용성 구성

keepalived 데몬은 서비스나 시스템을 모니터링하거나 어떤 문제가 발생했을 때 standby가 동작할 수 있도록 만들어 줍니다. 또한 [floating IP](https://docs.digitalocean.com/products/networking/floating-ips/) 주소를 설정하여 고가용한 로드밸런서를 구성합니다. 특정 노드에 문제가 생겨서 동작하지 않을 때에 자동으로 다른 노드로 IP를 옮겨 장애 없이 트래픽을 처리하도록 할 수 있습니다.

![](/assets/images/packet-life/04-03.png)

#### MetalLB — LoadBalancer 타입을 가지는 Nginx

MetalLB는 Network(L4) 로드밸런서 구현체입니다. MetalLB를 이용하면 클라우드 서비스 위에서 동작하지 않는 Service에도 `LoadBalancer` 타입을 사용할 수 있게 해줍니다. 클라우드 서비스 위에서 `LoadBalancer` 타입 Service를 생성하면 클라우드가 알아서 자동으로 클라우드 로드밸런서를 하나 만들고 외부 접근 가능한 IP를 할당해 줍니다. 베어메탈 환경에서는 MetalLB가 바로 이 역할을 대신합니다. MetalLB가 Service에 외부 IP를 부여하게 되면, 해당 IP가 외부에서도 접근 가능하게 만들어야 합니다. MetalLB는 표준 라우팅 프로토콜을 이용하여 클러스터 외부에서도 일반적인 네트워크 프로토콜을 이용해서 해당 Service로 접근 가능하게 만들어 줍니다: ARP, NDP 혹은 BGP

이를 위해 MetalLB에서는 두가지 모드를 제공합니다. Layer 2 모드에서는 특정 서버 한대를 선택하여 해당 서버의 IP를 외부 접근 가능한 IP로 설정합니다.(역자주: 여기서 얘기하는 외부란, layer2이기 때문에 local network망 내에서만 접근이 가능합니다.): IPv4는 ARP, IPv6는 NDP. LAN 관점에서 해당 서버에 여러 개의 IP가 할당되어 있는 모습니다. (역자주: 원래 해당 서버의 IP 주소 + MetalLB가 부여한 IP 주소들)

BGP mode에서는 클러스터 내에 모든 노드들이 해당 네트워크에 있는 **연결 가능한** 외부 BGP 노드와 peering 세션을 맺습니다.(역자주: 여기서 "연결 가능한"이라는 뜻은, BGP 프로토콜을 동작하는 라우터를 직접 컨트롤 할 수 있거나 적어도 네트워크 관리자에게 요청하여 peering을 맺을 수 있는 경우를 의미합니다.) 이를 통해 클러스터 외부에서도 MetalLB가 부여한 IP에 대한 라우팅 정보를 공유 받을 수 있게 됩니다. BGP 모드를 사용하는 것이 사실상 진정한 의미의 로드밸런싱을 한다고 말할 수 있습니다.

MetalLB에는 두가지 컴포넌트가 있습니다:

- Controller: MetalLB의 controller입니다. IP 할당을 책임집니다. (Deployment 형태)
- Speaker: Controller가 IP를 할당하면 advertising 전략에 따라(layer2, BGP mode) 할당 받은 IP를 다른 네트워크 노드에 알리는(홍보) 역할을 담당합니다. (Daemonset 형태)

![](/assets/images/packet-life/04-04.png)


> 참고: Metal LB는 어느 클러스터에서든지 Service 타입을 `LoadBalancer`로 설정하면 사용할 수 있습니다. 다만 큰 public IP pool을 사용하는 경우에는 실용적이지 못할 수 있습니다.

Metal LB에 대한 소개로 조훈님의 발표도 참고해 주시기 바랍니다.

- [https://www.slideshare.net/JoHoon1/w-metallb](https://www.slideshare.net/JoHoon1/w-metallb)
- [https://www.youtube.com/watch?v=lqVaianMKA8](https://www.youtube.com/watch?v=lqVaianMKA8)


## References

- [https://kubernetes.io/docs/concepts/services-networking/ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [https://www.nginx.com/products/nginx-ingress-controller](https://www.nginx.com/products/nginx-ingress-controller)
- [https://www.keepalived.org](https://www.keepalived.org)
- [https://www.envoyproxy.io](https://www.envoyproxy.io)
- [https://projectcontour.io](https://projectcontour.io)
- [https://metallb.universe.tf](https://metallb.universe.tf)


### 밝히는 사실 (Disclaimer)

> 원작자가 밝히는 내용입니다.

이 글은 특정 기술에 대한 조언이나 추천을 하지 않습니다. 필자가 속한 회사와는 무관하게 개인적인 의견임을 밝힙니다.


## 마치며

사실 이번 블로그 원글 내용은 약간 용두사미로 흘러가서 번역을 하지 않을까도 생각했지만 그래도 기왕하는거 끝까지 번역하기로 하였습니다. 이 글을 읽고 Ingress에 대한 조금 더 자세한 내용이 궁금하시다면 [쿠버네티스 네트워킹 이해하기#3: Ingress 편](https://coffeewhale.com/k8s/network/2019/05/30/k8s-network-03/)도 참고해 보시길 바랍니다.

![](/assets/images/packet-life/04-05.jpeg)
