---
layout: post
title:  "GitOps에서의 Secret 관리"
date:   2021-11-15 00:00:00
categories: kubernetes security
image: /assets/images/sealedsecret/landing.png
permalink: /:title
---
GitOps에서 Secret 관리가 고민이시라구요? 그래서 준비했습니다, [SealedSecret](https://github.com/bitnami-labs/sealed-secrets)!

[GitOps](/kubernetes/gitops/argocd/2020/02/10/gitops-argocd/)는 우리의 삶을 편리하게 만들어 줍니다. 어플리케이션의 배포 상태를 완벽하게 반영해주어 Git에 저장된 배포 정의서(YAML manifest)만 보면 어떻게 배포되었는지 한눈에 알 수 있게 해줍니다. 또한 롤백을 해야 하는 경우에는 Git revert를 통해 금방 예전의 상태로 돌아갈 수 있습니다. CI/CD 파이프라인과 잘 연결하면 정말 편리하게 서비스를 배포할 수 있게 해주는 고마운 존재입니다.

하지만 한가지 문제가 있습니다. 민감 정보를 Secret에 넣어 Git 저장소에 저장하게 되면 민감정보가 노출됩니다. 물론 Git 저장소를 private으로 만들고 허가된 인원만 접근 권한을 준다면 간단하게 해결할 수도 있습니다. 하지만 여기에도 몇 가지 문제가 있는데요. 작업을 하다보면 꼭 외부의 인원에게도 Git 접근권한을 열어줘야 할 경우가 생깁니다. 또한 사용자가 Git 레포지토리를 개인 PC에 checkout하게 되면 그때부터는 해당 정보는 plain text로 컴퓨터에 저장됩니다. 혼자만 사용하는 PC라면 그나마 다행이지만 공용 PC에서 잘못 코드를 내려 받는 순간, 민감 정보가 유출되는건 시간 문제입니다.

이러한 문제점을 해결해 주는 `SealedSecret`을 소개합니다.

## SealedSecret

[SealedSecret](https://github.com/bitnami-labs/sealed-secrets)이 풀고자 하는 문제점은 간단합니다.

- 문제: 제 모든 K8s config를 Git으로 관리할 수 있습니다. Secret만 빼고요...
- 해결: `SealedSecret`으로 당신의 `Secret`을 암호화하세요!

## 동작방법

SealedSecret에서 제공하는 Public key(인증서)를 이용하여 Secret을 암호화하여 Git에 올려 놓으면 SealedSecret Controller가 알아서 복호화하여 쿠버네티스 Secret으로 만들어 줍니다.

![](/assets/images/sealedsecret/overview.png)

1. 사용자가 미리 SealedSecret의 인증서를 이용하여 Secret을 암호화합니다. (`SealedSecret` 생성)
2. 생성한 `SealedSecret`을 외부 git 저장소에 업로드합니다. 아무나 볼 순 있겠지만 복호화하진 못합니다.
3. GitOps Operator에 의해 `SealedSecret`이 쿠버네티스 클러스터로 배포됩니다.
4. SealedSecret Controller에 의해 `SealedSecret`이 일반 `Secret`으로 복호화됩니다. 그 이후에는 일반 `Secret`으로 기존과 동일하게 사용합니다.

## 설치방법

`SealedSecret`을 사용하기 위해 Client와 Server side를 각각 설치해야 합니다.

- Client side: `kubeseal`, 일반 `Secret`을 `SealedSecret`으로 암호화 해주는 툴입니다. 사용자가 수동으로 직접 SealedSecret의 인증서를 이용하여 암호화한 후, `SealedSecret`를 만들 수도 있지만, 손쉽게 자동화하기 위해 `kubeseal`라는 CLI를 설치합니다.
- Server side: SealedSecret Controller를 설치하는 K8s Manifest입니다. 

### Client side

- Linux x86_64:

```bash
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.16.0/kubeseal-linux-amd64 -O kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

- MacOS:

```bash
brew install kubeseal
```

### Server side

- Manifest:

```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.16.0/controller.yaml
```

- helm:

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets
```

## 사용방법

먼저 간단한 K8s `Secret`을 만들어 봅시다.

```bash
kubectl create secret generic mysecret --from-literal hello=world --dry-run=client -oyaml > mysecret.yaml

cat mysecret.yaml
# apiVersion: v1
# data:
#   hello: d29ybGQ=
# kind: Secret
# metadata:
#   creationTimestamp: null
#   name: mysecret
```

방금 만든 Secret을 `kubeseal` CLI를 이용하여 암호화된 `SealedSecret`을 생성합니다.

### Controller에 들어있는 인증서를 이용하는 방법

SealedSecret Controller가 설치된 쿠버네티스 클러스터와 바로 통신할 수 있는 경우, 아무런 옵션을 주지 않고도 SealedSecret을 만들 수 있습니다.

```bash
cat mysecret.yaml | kubeseal -oyaml > mysealed-secret.yaml

cat mysealed-secret.yaml
# apiVersion: bitnami.com/v1alpha1
# kind: SealedSecret
# metadata:
#   name: mysecret
#   namespace: default
# spec:
#   encryptedData:
#     hello: AgBNlDVFBZMNfNRM9SdgiSizpOngq8JUITxKoGaT1YTaKow/0SfwB5EMRQVK....==
#   template:
#     data: null
#     metadata:
#       name: mysecret
#       namespace: default
```

### Controller의 인증서를 추출하여 로컬에서 주입하는 방법

방화벽이나 권한 문제로 쿠버네티스 클러스터에 매번 접속되는 것이 어려울 때는 미리 인증서를 SealedSecret Controller로부터 추출하여 Controller와의 통신 없이 암호화를 수행할 수 있습니다.

```bash
# 먼저 인증서를 추출합니다.
kubeseal --fetch-cert > mycert.pem

# --cert 옵션을 이용하여 사용할 인증서를 제공합니다.
cat mysecret.yaml | kubeseal --cert mycert.pem -oyaml > mysealed-secret.yaml
# apiVersion: bitnami.com/v1alpha1
# kind: SealedSecret
# metadata:
#   name: mysecret
#   namespace: default
# spec:
#   encryptedData:
#     hello: AgBNlDVFBZMNfNRM9SdgiSizpOngq8JUITxKoGaT1YTaKow/0SfwB5EMRQVK....==
#   template:
#     data: null
#     metadata:
#       name: mysecret
#       namespace: default
```

---

`SealedSecret`의 `encryptedData` 값은 암호화된 정보로 SealedSecret Controller를 제외한 그 누구도(심지어 암호화를 수행한 사용자 조차도) 풀지 못합니다. 왜냐하면 복호화에 사용하는 private key는 오직 SealedSecret Controller만 가지고 있기 때문에 그 키를 가진 SealedSecret Controller만 복호화할 수 있습니다. (물론 SealedSecret Controller로부터 강제로 private key를 빼서 사용한다면 키를 가진 누구나 복호화할 수는 있습니다.)

이제 이 `SealedSecret`을 외부 git 저장소에 저장하여 민감정보 유출 걱정 없이 누구에게나 공유할 수 있습니다.

```bash
# 보통은 Git에 저장하여 GitOps로 배포하지만 예제에서는 직접 SealedSecret을 쿠버네티스로 배포해 봅니다.
kubectl apply -f mysealed-secret.yaml
# sealedsecret.bitnami.com/mysecret created

# sealedsecret이 만들어진 것을 확인합니다.
kubectl get sealedsecret mysecret
# NAME       AGE
# mysecret   11s

# controller에 의해 자동으로 sealedsecret이 복호화되어 secret으로 생성됩니다.
kubectl get secret mysecret
# NAME       TYPE     DATA   AGE
# mysecret   Opaque   1      42s
```

## 마무리

SealedSecret은 사용하기 무척 간단하고 편리합니다. 더군다나 어플리케이션 입장에서는 추가적인 소스코드 변경 없이 그대로 Secret 값을 참조할 수 있습니다. 보안이 점점 중요해지는 만큼 SealedSecret을 통해 민감정보를 안정하게 보호하시기 바랍니다.
