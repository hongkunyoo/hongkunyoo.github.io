---
layout: post
title:  "Headless Service를 이용하여 네임스페이스가 다른 서비스에 Ingress 연결하기"
date:   2020-01-22 00:00:00
categories: kubernetes service
---
본 글은 네임스페이스가 다른 Ingress에서 또다른 네임스페이스의 서비스로 연결해야 방법에 대하여 포스팅하였습니다. 제목에서 알 수 있듯이 Headless Service의 ExternalName을 이용하면 간단하게 해결할 수 있습니다.

쿠버네티스를 이용한 분석플랫폼 구축 중 네임스페이스가 다른 서비스에 Ingress를 연결해야 하는 상황이 발생하였습니다. cert-manager를 이용하여 특정 네임스페이스의 (예시에서는 namespace A) Ingress에 Issuer를 통해 tls 설정을 하였고 다른 네임스페이스의 (namespace B) 서비스에 Ingress를 연결할 필요가 생겼습니다. 여기서 제가 할 수 있는 방법들은 다음과 같았습니다.

1. namespace A Ingress에서 namespace B의 서비스로 연결하기
2. namespace B에 배포된 앱 전체를 namespace A로 옮기기
3. namespace B에 cert-manager Issuer를 생성하여 직접 Ingress 연결하기

### 1. namespace A Ingress에서 namespace B의 서비스로 연결하기

![](/assets/images/headless-svc/01.png)
(*저자주*: 실제 쿠버네티스에서는 패킷이 Service를 거치지 않고 바로 Pod로 전달됩니다. 개념 설명의 편리성을 위해 위와 같이 그렸습니다.)

처음 해결책을 고민해 봤을 때, 아래와 같이 k8s 내부 서비스를 참조하는 방식으로 네임스페이스가 다른 서비스를 Ingress에 연결하는 방법(<service>.<ns>.svc.cluster.local)을 생각했습니다만 이러한 방법으로는 작동하지 않는다는 사실을 깨닫게 되었습니다.
```yaml
    apiVersion: extensions/v1beta1
    kind: Ingress
    metadata:
      annotations:
        cert-manager.io/issuer: my-issuer
        kubernetes.io/ingress.class: nginx
      name: ingressC
      namespace: namespaceA
    spec:
      rules:
      - host: subdomain.host.com
        http:
          paths:
          - backend:
              serviceName: servceC.namespaceB.svc.cluster.local  # k8s style reference
              servicePort: 80
            path: /
```

### 2. namespace B에 배포된 앱 전체를 namespace A로 옮기기

![](/assets/images/headless-svc/02.png)

두번째 방법으로 namespace B에 배포되어 있는 앱 전체를 namespace A로 옮겨 Ingress부터 Service까지 동일한 namespace에서 연결하는 방법을 생각했었습니다. 가능한 방법이나, 앱 전체를 옮기는 작업이 만만치 않을 뿐더러 이렇게 되면 Ingress를 사용하는 모든 앱은 전부 동일한 네임스페이스를 사용해야 된다는 의미가 되었기 때문에 조금 더 나은 방법은 없을까 고민하였습니다.

### 3. namespace B에 cert-manager Issuer를 생성하여 직접 Ingress 연결하기

![](/assets/images/headless-svc/03.png)

사실 namespace B에 새로운 cert-manager Issuer를 생성하거나 ClusterIssuer를 생성하면 쉽게 해결될 일이 었습니다. 하지만 보안상, 관리 목적상 Ingress는 오직 namespace A에서만 존재하고 나머지 namespace에서는 외부로 노출되는 포인트가 없길 원했습니다. (namespace A를 마치 퍼블릭존과 같이 사용) 그렇기 때문에 마지막 방법도 일단은 보류하기로 하였습니다.

## 바로 너였어 Headless Service

![](/assets/images/headless-svc/04.png)

다시 1번으로 돌아와 정말 namespace A Ingress에서 namespace B 서비스로 연결하는 방법이 없을까 고민하던 도중 [다음과 같은 곳](https://github.com/kubernetes/kubernetes/issues/17088)에서 저와 비슷한 고민을 하는 것을 발견했고 Headless Service의 ExternalName을 이용한 해결책이 있다는 것을 확인했습니다. 방법은 다음과 같습니다.

1. namespace A에서 namespace B의 서비스를 가르키는 Headless Service를 namespace A에 생성
2. namespace A Ingress에서 namespace A의 Headless service 참조

```yaml
    apiVersion: v1
    kind: Service
    metadata:
      annotations:
      name: headless-to-serviceC
      namespace: namespaceA
    spec:
      clusterIP: None
      externalName: serviceC.namespaceB.svc.cluster.local # reference svc-C in ns-B
```

```yaml
    apiVersion: extensions/v1beta1
    kind: Ingress
    metadata:
      annotations:
        cert-manager.io/issuer: namespaceA-issuer
        kubernetes.io/ingress.class: nginx
      name: ingressC
      namespace: namespaceA
    spec:
      rules:
      - host: subdomain.host.com
        http:
          paths:
          - backend:
              serviceName: headless-to-serviceC
              servicePort: 80
            path: /
```

## 내부 서비스도 참조 가능한 ExternalName

지금까지 Headless Service의 ExternalName은 외부 Domain을 마치 k8s 서비스인 것처럼 참조할 수 있게 해주는 기능으로만 알고 있었는데 이번 기회를 통해 외부 서비스 뿐만 아니라 k8s 내부 서비스 또한 동일한 방법으로 또 다른 이름으로 참조할 수 있게 해주는 사실을 깨닫게 되었습니다. 오늘도 쿠린이는 작은 사실 하나를 배우고 갑니다.

