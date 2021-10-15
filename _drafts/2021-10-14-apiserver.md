---
layout: post
title:  "kube-apiserver는 정말 그냥 API서버입니다."
date:   2021-10-14 00:00:00
categories: kubernetes apiserver
image: /assets/images/scalenode/landing.png
permalink: /:title
---
kube-apiserver는 쿠버네티스 클러스터에서 있어서 가장 중추적인 역할을 담당합니다. 마스터 노드의 중심에서 모든 클라이언트, 컴포넌트로부터 오는 요청을 전부 받아내죠. 이렇게 중요한 역할을 수행하는 컴포넌트라서 복잡할 것이라 생각하기 쉽습니다.
저 또한 쿠버네티스를 처음 접했을 때, kube-apiserver 서버의 존재에 대해서는 알고 있었서도, 어떻게 사용하는지 잘 몰라서 직접 요청하는 경우는 거의 없었습니다. 대부분 `kubectl` CLI툴을 이용하여 클러스터에 요청을 보냈었죠.
하지만 쿠버네티스에 대해서 점점 알게 되면 될수록 kube-apiserver가 미지의 알 수 없는 복잡한 컴포넌트가 아닌 정말 단순한 API서버라는 것을 깨닫게 되었습니다.

오해하지 마세요. kube-apiserver가 만들기 쉽고 별것 없다는 얘기가 아닙니다. 적어도 표면적으로는 누구나 사용하기 쉽게 잘 만들어진, 우리에게 친근한 REST API서버라는 것입니다.
이번 짧은 포스트를 통해 kube-apiserver에 대해서 조금 더 가까워지는 시간을 가져보면 좋겠습니다.

---

## API서버 주소

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
#     cluster: cluster.local
#     user: admin
#   name: kubernetes
# current-context: kubernetes
# kind: Config
# preferences: {}
# users:
# - name: admin
#   user:
#     client-certificate-data: xxxx
#     client-key-data: xxxx
```

`clusters[0].cluster.server`가 API서버 주소를 나타냅니다. 그럼 바로 해당 주소로 REST call을 해보죠.

```bash

```