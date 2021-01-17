---
layout: post
title:  "Kubernetes-NGINX Ingress 인증 - OAuth"
date:   2021-01-17 00:00:00
categories: kubernetes authentication
image: /assets/images/landing/nginx-oauth2.png
---
Kubernetes-NGINX Ingress 사용 시, 간편하게 OAuth 인증을 설정하는 방법에 대해 정리한 내용입니다. 

해당 내용은 다음 링크를 참고하여 공부하면서 정리한 내용입니다. 

- [https://kubernetes.github.io/ingress-nginx/examples/auth/oauth-external-auth/](https://kubernetes.github.io/ingress-nginx/examples/auth/oauth-external-auth/)

이번 포스트에서는 다음과 같은 내용들을 알아볼 예정입니다.

1. NGINX에서 외부 인증을 설정하는 방법
2. OAuth 2.0에 대한 간단한 이해
3. oauth2-proxy를 이용한 OAuth 인증 구현

## Ingress 외부인증 설정

`Ingress`란 Layer 7 레벨 요청에 대해 처리하는 쿠버네티스 리소스입니다. `Ingress`를 이용하여 도메인 기반 라우팅, TLS 설정 등을 할 수도 있지만 API Gateway처럼 요청에 대한 인증도 `Ingress` 리소스를 통해 처리할 수 있습니다. 바로 Kubernetes-NGINX Ingress의 `nginx.ingress.kubernetes.io/auth-url`(앞으로 줄여서 `auth-url`로 표기) 라는 annotations을 이용하여 외부 인증을 수행할 수 있습니다. `Ingress`는 `auth-url`이 바라보는 인증서버로 요청을 보내어`200`(OK) 혹은 `202`(Accepted)을 반환 받으면 인증을 통과하였다고 판단하고 `401`(Unauthorization) 코드를 반환 받으면 아직 인증을 받지 못하였다고 판단하여 인증을 받기 위해 `nginx.ingress.kubernetes.io/auth-signin` URL로 리다이렉트합니다.

- `nginx.ingress.kubernetes.io/auth-url`: 인증 여부를 판단하기 위한 URL
- `nginx.ingress.kubernetes.io/auth-signin`: 인증을 받기 위해 접속해야 하는 URL

## OAuth2 Proxy

`Ingress`가 외부인증을 요청할 때 직접 OAuth IdP(Identity Provider: 구글, 페이스, 깃헙과 같은 업체)에 OAuth 프로토콜을 이용하여 인증을 받는 것이 아니라 **다른 누군가**를 통하여 대리 인증을 받습니다. 그 누군가가 바로 [OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/)입니다.

![그림1](/assets/images/nginx-auth/01.png)

그림에서 볼 수 있듯이 `Ingress`는 단순히 `auth-url`을 통하여 인증 여부만 확인할 뿐 실제 OAuth 인증을 위한 정보를 가지고 있거나 인증 프로세스를 수행하거나 하지 않습니다. 실제로 OAuth 인증을 하는 주체는 `oauth2-proxy`입니다. `oauth2-proxy`도 다른 컴포넌트와 마찬가지로 쿠버네티스의 `Service`와 `Pod`로 이루어져 있습니다.

## OAuth 개념 및 flow

저는 예전부터 OAuth에 대해 어느 정도는 알고 있었지만 완벽히 이해하지는 못하였습니다. 주로 구글느님이 시키는대로 안드로이드(혹은 웹 프론트) 코드를 복붙하여 인증 메커니즘을 구현했습니다. 기초 개념이 약하다보니 조금만 상황이 바뀌면 어떻게 코드를 수정해야 하는지 알기 어려웠고 코드를 수정한다고해서 제대로 적용이 되었는지 자신있게 말하기 어려웠습니다. 이번 기회에 확실히 OAuth에 대해 제대로 알고 넘어가자는 생각으로 공부하던 중 굉장히 좋은 유투브 영상을 발견하게 되었습니다. 

[OAuth 2.0 and OpenID Connect(영어)](https://www.youtube.com/watch?v=996OiexHze0)

해당 영상에서는 다음과 같은 내용들을 다룹니다.

- OAuth 2.0에 나오는 용어정리
- OAuth 2.0 개념 및 flow 설명
- OAuth 2.0과 OpenID Connect 관계 설명

비록 영어로 설명하긴 하지만 잘 만들어진 장표만 따라 천천히 들어도 많은 내용들을 이해할 수 있으리라 생각합니다.

### OpenID Connect flow 설명

우리의 목적은 NGINX Ingress를 이용하여 인증을 처리하는 것이기 때문에 사실 정확히는 OAuth가 아니라 OpenID Connect를 이용합니다. 자세한 둘의 관계는 제가 소개한 유투브 영상에서 자세하게 나오지만 간단하게 설명하자면, OpenID Connect는 사용자 인증을 위해 OAuth 2.0 기술을 활용합니다.

![그림3](/assets/images/nginx-auth/03.png)

OpenID Connect의 흐름을 간략하게 설명하면 다음과 같습니다. 간략화한 흐름도로 정확한 내용은 위의 유투브 영상을 통해 꼭 이해하시고 넘어가시길 추천 드립니다.

![그림2](/assets/images/nginx-auth/02.png)

큰 흐름은 다음과 같습니다. 우리의 목표는 `ID token`을 획득하는 것입니다. 해당 token에는 사용자의 정보가 들어있습니다. `oauth2-proxy` 서버는 `ID token`에 들어있는 사용자의 정보를 기준으로 인증을 허가할지 말지 결정합니다.

1. `Ingress`에서 `auth-url`로 인증여부를 확인하고 미인증시, `auth-signin`에 지정된 URL로 리다이렉션 시킵니다.
2. Authorization Server(ex. 구글서버)에 인증 요청을 합니다. 이때 사용자 동의 후, 리다이렉트할 URL을 함께 전송합니다.
3. 사용자 로그인 화면 전달(ex. 구글 로그인 페이지를 사용자가 봅니다.)
4. 사용자는 로그인 및 사용자 동의를 수행합니다.
5. Authorization Server에서 `oauth2-proxy` 서버로 authorization code와 함께 사용자가 지정한 URL로 리다이렉션 시킵니다.
6. `oauth2-proxy`서버가 authorization code를 이용하여 `ID token`을 획득합니다.
7. 획득한 `ID token`을 이용하여 `oauth2-proxy` 서버가 허용 여부를 결정합니다.


## oauth2-proxy를 이용한 인증 체계 구축

이제 본격적으로 `oauth2-proxy`를 설치해보고 IdP 세팅을 해보겠습니다. IdP로는 NGINX Ingress에도 소개한 것처럼 GitHub를 사용하겠습니다.


### 1. GitHub OAuth Application 설정

[https://github.com/settings/developers](https://github.com/settings/developers)에 가셔서 새로운 OAuth 어플리케이션을 생성합니다.

![그림4](/assets/images/nginx-auth/04.png)

- `Applicatoin name`: 이름을 지정합니다. 예시에서는 `ingress-oauth2`로 설정했습니다.
- `Homepage URL`: 어플리케이션의 URL을 설정합니다. 어떤 값을 입력하든 크게 상관없습니다. (`http://localhost`도 가능)
- `Application description`: 간단한 어플리케이션 설명을 적습니다.
- `Authorization callback URL`: **중요** 콜백할 URL을 지정합니다. Ingress에서 사용할 호스트 + `/oauth2`으로 설정합니다.

예를 들어, 인증을 추가할 본래의 서비스 이름이 `http://abc.mydomain.com` 이라고 한다면 `http://abc.mydomain.com/oauth2`을 기입합니다. 예시에서는 `http://nginx.coffeewhale.com/oauth2`을 사용합니다. 생성 후, GitHub에서 제공하는 Client ID, Client secret을 복사해 놓습니다.


![그림5](/assets/images/nginx-auth/05.png)

### 2. 서비스 구축

먼저 인증 메커니즘을 적용할 서비스를 생성합니다. `Ingress` 리소스에 다음과 같은 값들을 설정합니다. 예시에서는 간단한 NGINX 서버를 띄웁니다. 이때 `Ingress`에 다음과 같은 설정을 해줍니다.

- `annotations`:
	- `nginx.ingress.kubernetes.io/auth-url`: `https://$host/oauth2/auth`
	- `nginx.ingress.kubernetes.io/auth-signin`: `https://$host/oauth2/start?rd=$escaped_request_uri`
- `spec.rules[0].host`: 서비스에서 사용할 host. 예시에서는 `nginx.coffeewhale.com`를 사용합니다.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-nginx
spec:
  selector:
    matchLabels:
      run: my-nginx
  replicas: 1
  template:
    metadata:
      labels:
        run: my-nginx
    spec:
      containers:
      - name: my-nginx
        image: nginx
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: my-nginx
  labels:
    run: my-nginx
spec:
  ports:
  - port: 80
    protocol: TCP
  selector:
    run: my-nginx
---
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/auth-url: "https://$host/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://$host/oauth2/start?rd=$escaped_request_uri"
  name: external-auth-oauth2
spec:
  rules:
  - host: nginx.coffeewhale.com
    http:
      paths:
      - backend:
          serviceName: my-nginx
          servicePort: 80
        path: /
```

### 3. oauth2-proxy 설정

`oauth2-proxy`를 설치하기 위해서 다음과 같은 값들을 설정해야 합니다.

- `OAUTH2_PROXY_CLIENT_ID`: IdP에서 제공하는 OAuth client ID입니다. GitHub에서 복사한 Client ID를 기입합니다.
- `OAUTH2_PROXY_CLIENT_SECRET`: IdP에서 제공하는 OAuth secret key입니다. GitHub에서 복사한 Client secret을 기입합니다.
- `OAUTH2_PROXY_COOKIE_SECRET`: cookie를 암호화할 때 사용되는 seed 값입니다. 다음 명령을 이용하여 랜덤값을 생성합니다.

```bash
# OAUTH2_PROXY_COOKIE_SECRET
docker run -ti --rm python:3-alpine python -c 'import secrets,base64; print(base64.b64encode(base64.b64encode(secrets.token_bytes(16))));'
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    k8s-app: oauth2-proxy
  name: oauth2-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: oauth2-proxy
  template:
    metadata:
      labels:
        k8s-app: oauth2-proxy
    spec:
      containers:
      - args:
        - --provider=github
        - --email-domain=*
        - --upstream=file:///dev/null
        - --http-address=0.0.0.0:4180
        - --cookie-secure=false
        env:
        - name: OAUTH2_PROXY_CLIENT_ID
          value: <Client ID>
        - name: OAUTH2_PROXY_CLIENT_SECRET
          value: <Client Secret>
        - name: OAUTH2_PROXY_COOKIE_SECRET
          value: <Cookie Secret>
        image: quay.io/oauth2-proxy/oauth2-proxy:latest
        imagePullPolicy: Always
        name: oauth2-proxy
        ports:
        - containerPort: 4180
          protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  labels:
    k8s-app: oauth2-proxy
  name: oauth2-proxy
spec:
  ports:
  - name: http
    port: 4180
    protocol: TCP
    targetPort: 4180
  selector:
    k8s-app: oauth2-proxy
---
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: oauth2-proxy
spec:
  rules:
  - host: nginx.coffeewhale.com
    http:
      paths:
      - backend:
          serviceName: oauth2-proxy
          servicePort: 4180
        path: /oauth2
```

이로써 모든 설정이 완료되었습니다. 이제 `nginx.coffeewhale.com`을 방문하여 GitHub OAuth 인증을 진행해 보시기 바랍니다.

![그림6](/assets/images/nginx-auth/06.png)

![그림7](/assets/images/nginx-auth/07.png)

## 마치며

쿠버네티스를 이용하면 micro service들을 운영하기에 용이합니다. 하지만 여러 작은 서비스들의 인증 체계를 일일이 구현하는 일은 손이 많이 갑니다. NGINX Ingress의 OAuth 인증 메커니즘을 이용하여 API Gateway처럼 앞단에서 모든 인증을 처리하게 된다면 손쉽게 micro service들의 인증 및 권한 체계를 구축할 수 있으리라 기대합니다.
