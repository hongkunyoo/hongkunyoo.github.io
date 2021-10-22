---
layout: post
title:  "kube-apiserver는 정말 그냥 API서버라구욧"
date:   2021-10-21 00:00:00
categories: kubernetes
image: /assets/images/apiserver/landing.png
permalink: /:title
---
쿠버네티스 API서버에 대해서 한층 더 가까워지는 시간을 가져봅시다.

kube-apiserver는 쿠버네티스 클러스터에서 있어서 가장 중추적인 역할을 담당합니다. 마스터 노드의 중심에서 모든 클라이언트, 컴포넌트로부터 오는 요청을 전부 받아내죠. 이렇게 중요한 역할을 수행하는 컴포넌트라서 복잡할 것이라 생각하기 쉽습니다.
저 또한 쿠버네티스를 처음 접했을 때, kube-apiserver 서버의 존재에 대해서는 알고 있었서도, 어떻게 호출하는지 잘 몰라서 직접 요청하는 경우는 거의 없었습니다. 대부분 `kubectl` CLI툴을 이용하여 클러스터에 요청을 보냈었죠.
하지만 쿠버네티스에 대해서 점점 알게 되면 될수록 kube-apiserver가 미지의 알 수 없는 복잡한 컴포넌트가 아닌 정말 단순한 API서버라는 것을 깨닫게 되었습니다.

오해하지 마세요. kube-apiserver가 만들기 쉽고 별것 없다는 얘기가 아닙니다. 적어도 표면적으로는 누구나 사용하기 쉽게 잘 만들어진, 우리에게 친근한 REST API서버라는 것입니다.
이번 짧은 포스트를 통해 kube-apiserver에 대해서 조금 더 가까워지는 시간을 가져보면 좋겠습니다.

---

## API서버 호출

제일 먼저 API서버의 주소를 찾아 한번 호출해 보겠습니다.

다음 명령을 실행해 봅시다.

```bash
kubectl cluster-info
# Kubernetes control plane is running at https://10.0.0.1:6443
```

`kubectl`이 바라보는 API서버의 주소를 출력합니다. (앞으로 예시의 API서버 주소는 `10.0.0.1:6443`으로 통일합니다. 실제로는 사용자마다 다릅니다.)

`kubectl`은 도대체 이 API서버 주소를 어떻게 알까요? 그것은 바로 `kubeconfig` 파일에 있습니다. 특별한 옵션이 없으면 `kubeconfig` 파일은 기본적으로 `$HOME/.kube/config`에 위치합니다. 위치를 변경하고 싶다면 환경변수 `KUBECONFIG`를 수정하면 됩니다.

```bash
export KUBECONFIG=/my/path/kubeconfig
```

`kubeconfig` 파일을 출력해 봅시다.

```bash
cat $HOME/.kube/config
# apiVersion: v1
# clusters:
# - cluster:
#     certificate-authority-data: xxxx
#     server: https://10.0.0.1:6443
#   name: cluster.local
# contexts:
# - context:
# ...
# ...
```

`clusters[0].cluster.server`가 API서버 주소를 나타냅니다. 그럼 바로 `curl`을 이용하여 해당 주소로 REST call을 해보죠.

```bash
curl https://10.0.0.1:6443
# curl: (60) SSL certificate problem: unable to get local issuer certificate
# ...
```

그러면 다음과 같은 에러가 발생할 것입니다. 이것은 API서버가 사용하는 서버 인증서가 공식 CA(Certificate Authority)에서 발급한 정식 인증서가 아니기 때문입니다. 그렇기 때문에 `kubeconfig`에서는 사용자가 서버 인증서를 검증할 수 있는 자체 CA 인증서를 제공해 줍니다. 그것이 바로 `kubeconfig`의 `certificate-authority-data` property입니다. 인증서에 대한 더 자세한 내용을 알고 싶으시다면 [커피고래의 X.509 인증서](https://coffeewhale.com/kubernetes/authentication/x509/2020/05/02/auth01/#x509-certificate) 포스트를 참고하시기 바랍니다. 그럼 쿠버네티스가 제공하는 자체 CA 인증서를 이용하여 다시 호출해 봅시다.

```bash
# kubeconfig 파일로부터 CA 인증서를 추출하는 방법
kubectl config view --minify --raw --output 'jsonpath={..cluster.certificate-authority-data}' | base64 -d > k8s-ca.cert

# --cacert 옵션으로 사용자가 명시적으로 CA 인증서를 제공합니다.
curl --cacert k8s-ca.cert https://10.0.0.1:6443
# {
#   "kind": "Status",
#   "apiVersion": "v1",
#   "metadata": {
    
#   },
#   "status": "Failure",
#   "message": "forbidden: User \"system:anonymous\" cannot get path \"/\"",
#   "reason": "Forbidden",
#   "details": {
    
#   },
#   "code": 403
# }
```

그럼 다음과 같이 API 결과가 나옵니다.(비록 403 Forbidden이긴 하지만)

한가지 팁은 curl로 하여금 서버 인증서 확인 자체를 건너뛰게 할 수 있습니다. 다음 옵션을 이용하면 CA 인증서 없이도 동일하게 서버에 요청할 수 있습니다.

```bash
# -k 혹은 --insecure (서버 인증서 확인 skip)
curl -k https://10.0.0.1:6443
# 위와 동일한 결과
```

## 사용자 인증

[403 status code](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/403)는 API 서버로부터 적절한 접근권한이 없을 경우 발생합니다. 쿠버네티스 API서버는 기본적으로 사용자 인증을 진행합니다.

### JWT

일반적으로 어떤 서버의 security를 설정하기 위해 간단하면서도 손쉬운 방법으로 JWT를 사용할 수 있습니다. JWT란 서버가 서명한 JSON object로써 JWT를 가지고 있다는 말은 서버가 인증한 비밀번호 같은 것을 가지고 있다는 것을 의미할 수 있습니다. 더 자세한 내용은 [커피고래의 JWT](https://coffeewhale.com/kubernetes/authentication/http-auth/2020/05/03/auth02#json-web-token-jwt) 부분을 참고하시기 바랍니다.

JWT를 이용하여 서버에 호출하는 방법은 간단합니다. "Authorization" 헤더에 JWT 값을 넣으면 됩니다.

```bash
curl -H "Authorization: Bearer $TOKEN" <어떤서버IP>:<PORT>
```

kube-apiserver도 여느 일반적인 API서버와 동일하다고 했죠? 그래서 이 친구도 동일하게 JWT 토큰을 헤더로 넣어서 사용자 인증을 받을 수 있습니다.

```bash
curl -k -H "Authorization: Bearer $TOKEN" https://10.0.0.1:6443
```

문제는 JWT Token 값을 어떻게 구하냐는 것입니다. 그 값은 바로 `ServiceAccount`에 있습니다. 쿠버네티스의 `ServiceAccount` 리소스는 API 호출을 위한 JWT 토큰값을 저장합니다. (정확히는 해당 `ServiceAccount`와 연결된 `Secret`에 저장됩니다.)

그럼 바로 JWT를 추출해 보겠습니다. 쿠버네티스는 기본적으로 `default`라는 이름의 `ServiceAccount`를 제공합니다.

```bash
kubectl get serviceaccount default
# NAME      SECRETS   AGE
# default   1         8d
```

default ServiceAccount에 연결된 `Secret`의 JWT값은 다음과 같이 찾을 수 있습니다.

```bash
TOKEN=$(kubectl get secret $(kubectl get sa default \
    -ojsonpath="{.secrets[0].name}") \
    -ojsonpath="{.data.token}" | base64 -d)
echo $TOKEN
# eyJhbxxxxx
```

복잡하게 보이지만 간단히 설명해서 `default`라는 이름의 `ServiceAccount`에 연결된 `Secret`을 찾아서 그 속에 들어있는 `data.token`값을 추출하여 `base64`로 디코딩하라 라는 뜻입니다.

이 `$TOKEN`값을 이용하여 다시 API서버에 호출해 봅시다.

```bash
curl -k -H "Authorization: Bearer $TOKEN" https://10.0.0.1:6443
# {
#   "kind": "Status",
#   "apiVersion": "v1",
#   "metadata": {
    
#   },
#   "status": "Failure",
#   "message": "forbidden: User \"system:serviceaccount:default:default\" cannot get path \"/\"",
#   "reason": "Forbidden",
#   "details": {
    
#   },
#   "code": 403
# }
```

예전히 403 에러가 발생하긴 하지만 자세히 `message`를 보면 이전에는 `system:anonymous`라고 표시가 되었었는데 이제는 `system:serviceaccount:default:default`라고 나옵니다. 뭔가 사용자 인증은 된거 같네요. 다만 사용자 인증은 받았지만 아직 `default`에는 API를 호출할 수 있는 권한이 없습니다.

### 권한부여

`default`라는 사용자(`ServiceAccount`)에 적절한 권한을 부여해 봅시다. 이번 포스트에서는 예제의 편의를 위해 `cluster-admin` 권한을 부여하도록 하겠습니다. 운영환경에서는 매우 위험한 행위니 적절한 권한을 부여해 주시기 바랍니다.

```bash
kubectl create clusterrolebinding default-cluster-admin --clusterrole cluster-admin --serviceaccount default:default
# clusterrolebinding.rbac.authorization.k8s.io/default-cluster-admin created
```

```bash
curl -k -H "Authorization: Bearer $TOKEN" https://10.0.0.1:6443
# {
#   "paths": [
#     "/api",
#     "/api/v1",
#     "/apis",
#     "/apis/",
#     ...
```

지금까지와는 다르게 굉장히 긴 JSON 객체와 함께 성공적으로 API를 호출하였습니다. 이제 쿠버네티스 API서버를 직접 호출하기 위한 기본적인 작업은 끝이 났습니다. 그럼 `kubectl` 명령과 대응되는 REST API를 호출해 보도록 해보겠습니다.

## Pod APIs

### Pod 생성

`Pod`를 먼저 생성해 보겠습니다. `Pod` 생성 URL을 확인하기 위해 `--dry-run` 옵션과 함께 `verbose`를 8로 설정하여 호출해 봅니다.

```bash
kubectl run mynginx --image nginx --restart Never --dry-run=client -oyaml > mynginx.yaml
kubectl apply -f mynginx.yaml -v 8 --dry-run=client
# ...
# ...
# .. round_trippers.go:420] GET https://10.0.0.1:6443/api/v1/namespaces/default/pods
# .. round_trippers.go:427] Request Headers:
# .. round_trippers.go:431]     User-Agent: kubectl/v1.17.7+k3s1 (linux/amd64) kubernetes/b0260b3
# .. round_trippers.go:431]     Accept: application/json
# .. round_trippers.go:431]     Content-Type: application/json
# ...
# ...
```

아래 쯤에 `https://10.0.0.1:6443/api/v1/namespaces/default/pods` 주소가 보이네요. 저 URL로 직접 API 서버로 호출해 보도록 하겠습니다.

- `-H "Authorization Bearer $TOKEN"`: 사용자 인증을 위해 토큰을 헤더로 보냅니다.
- `-H "Content-type: application/yaml"`: 전송하는 파일의 형식을 알립니다.
- `--data-binary @mynginx.yaml`: 실제 POST Body로 넘길 파일을 지정합니다.


```bash
curl -v -k \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-type: application/yaml" \
        --data-binary @mynginx.yaml \
        https://10.0.0.1:6443/api/v1/namespaces/default/pods
# Trying 10.0.0.1:6443...
# ...
# ...
# > POST /api/v1/namespaces/default/pods HTTP/1.1
# > Host: 127.0.0.1:6443
# ...
# > Authorization: Bearer eyJhbGxx
# > Content-type: application/yaml
# ...
# < HTTP/1.1 201 Created
# < Cache-Control: no-cache, private
# < Content-Type: application/json
# < Date: Wed, 20 Oct 2021 13:57:32 GMT
# < Content-Length: 1759
# < 
# {
#   "kind": "Pod",
#   "apiVersion": "v1",
#   "metadata": {
#     "name": "mynginx",
#     "namespace": "default",
#     "selfLink": "/api/v1/namespaces/default/pods/mynginx",
# ...
# ...
```

`201 Created` HTTP 코드가 반환된 것을 확인할 수 있습니다. 실제로 제대로 생성이 되었는지 확인해 봅시다.

### Pod 리스트

`default` 네임스페이스의 모든 `Pod`를 리스팅합니다.

```bash
curl -v -k \
        -H "Authorization: Bearer $TOKEN" \
        https://10.0.0.1:6443/api/v1/namespaces/default/pods
```

방금 생성한 `Pod`가 잘 나오는 것을 확인할 수 있습니다. (출력 결과는 전부 생략합니다.)

### Pod watch

단순한 리스팅 뿐만 아니라 Watch도 가능합니다. (`kubectl get pod --watch`) 해당 API를 호출한 이후 새로운 터미널을 띄워서 `Pod`를 삭제(아래 `Pod` 삭제 참조)해 봅시다. Watching하는 API에서 새로운 이벤트가 발생하는 것을 확인할 수 있습니다.

```bash
curl -v -k \
        -H "Authorization: Bearer $TOKEN" \
        https://10.0.0.1:6443/api/v1/namespaces/default/pods?watch=true
```

### 특정 Pod 확인

방금 생성한 mynginx `Pod`의 정보만 가져옵니다.

```bash
curl -v -k \
        -H "Authorization: Bearer $TOKEN" \
        https://10.0.0.1:6443/api/v1/namespaces/default/pods/mynginx
```

### Pod 로그 읽기

단순히 `Pod`를 확인하는 것 뿐만 아니라 해당 `Pod`의 로그도 읽을 수 있습니다.

```bash
curl -v -k \
        -H "Authorization: Bearer $TOKEN" \
        https://10.0.0.1:6443/api/v1/namespaces/default/pods/mynginx/log
```

### Pod 삭제

생성한 `Pod`를 삭제합니다.

```bash
curl -v -k \
        -X DELETE \
        -H "Authorization: Bearer $TOKEN" \
        https://10.0.0.1:6443/api/v1/namespaces/default/pods/mynginx
```


### Node 리스트

`Pod` 리소스 뿐만 아니라 다른 리소스도 동일하게 API로 호출할 수 있습니다. 예시에서는 노드 리스트를 가져오는 API입니다.

```bash
curl -v -k \
        -H "Authorization: Bearer $TOKEN" \
        https://10.0.0.1:6443/api/v1/nodes
```
### More API

사실 `kubectl`를 사용할 때 `-v 9` verbosity level을 주게 되면 수 많은 디버깅 로그 속에서 해당 API에 대한 `curl` 호출 방법이 나옵니다.

```bash
kubectl get service -v 9
# ...
# ... round_trippers.go:435] curl -v -XGET  -H "Accept: application/json;as=Table;application/json"
#                                           -H "User-Agent: kubectl/v1.22.1 (darwin/amd64) kubernetes/632ed30" 
#                                              'https://10.0.0.1:6443/api/v1/namespaces/default/services?limit=500'
# ... round_trippers.go:454] GET https://10.0.0.1:6443/api/v1/namespaces/default/services?limit=500 200 OK in ...
# ... round_trippers.go:460] Response Headers:
# ... round_trippers.go:463]     Date: Thu, 21 Oct 2021 12:34:39 GMT
# ... round_trippers.go:463]     Audit-Id: 40ec5ad6-18a5-43ec-b444-c9d6fe94ebb2
# ... round_trippers.go:463]     Cache-Control: no-cache, private
# ...
```

이 옵션을 이용하면 다른 API들도 손쉽게 찾을 수 있습니다.

이렇듯 쿠버네티스 API 서버도 우리가 많이 사용하는 HTTP verb를 이용하여 리소스별 CRUD 작업을 수행할 수 있습니다. 어떤가요? 단지 호출할 수 있는 API 개수가 많고 조금 복잡하긴 하지만 여느 API 서버와 별반 다르지 않다는 것을 느낄 수 있지 않나요?

## OpenAPI V2 API 스펙 문서

일반적으로 API는 API 스펙 문서를 제공합니다. 쿠버네티스도 OpenAPI V2 형식의 API 문서를 제공합니다. 그래서 이론상 `kubectl` 툴이 없다하더라도 이 API 스펙 문서만으로도 kube-apiserver를 전부 다룰 수 있습니다. (물론 간단하지는 않겠지만요.)

```bash
curl -k -H "Authorization: Bearer $TOKEN" https://10.0.0.1:6443/openapi/v2
# 엄청나게 긴 json 파일 출력
```

해당 json 파일을 저장하여 [OpenAPI Editor](https://editor.swagger.io)에 로드하면 kube-apiserver의 모든 API 명세를 다 볼 수 있습니다.(워낙 API가 많기 때문에 로딩하는데 시간이 굉장히 오래 걸리거나 브라우저가 죽을 수도 있습니다. API 스펙이 약 144000줄 정도 됩니다...)

![](/assets/images/kube-apiserver/openapi.png)

## 마치며

kube-apiserver는 정말 그냥 API서버입니다. 쿠버네티스 클러스터 내부에 여러 컴포넌트들이 존재하고 어떻게 동작하는지는 전부 다 알지 못하지만 적어도 사용자에게 노출되는 `kube-apiserver` 만큼은 여느 API 서버와 마찬가지로 사용하기 쉽게 설계되어 있습니다. 

사실 사람이 쿠버네티스를 사용할 때에는 대부분 `kubectl` 툴을 사용하겠지만 프로세스나 머신이 직접 쿠버네티스를 호출할 때에는 쿠버네티스에서 제공하는 [Kubernetes SDK](https://kubernetes.io/docs/reference/using-api/client-libraries/)를 사용할 수 있지만 여차하면 직접 REST API 호출로 쿠버네티스와 통신할 수 있습니다.
