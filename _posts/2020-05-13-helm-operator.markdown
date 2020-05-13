---
layout: post
title:  "Helm Operator 소개"
date:   2020-05-13 00:00:00
categories: kubernetes gitops helm
image: /assets/images/helm-op/landing.jpg
---
[helm](https://helm.sh/)은 가장 많이 쓰이는 쿠버네티스 패키지 매니저 중 하나죠. 복잡한 어플리케이션도 helm chart 하나면은 뚝딱 쿠버네티스 위에 설치할 수 있습니다. 이 helm chart를 쿠버네티스 Operator 패턴으로 조금 더 편리하게 패키지를 관리해주는 방법은 없을까요? 바로 이번 시간에 알아볼 Helm Operator를 소개합니다.

본 포스트는 [GitOps](https://www.weave.works/blog/what-is-gitops-really)에 대한 사전 지식이 필요합니다. GitOps에 대해서 궁금하신 분들은 저의 포스트 [*GitOps와 ArgoCD*](/kubernetes/gitops/argocd/2020/02/10/gitops-argocd/)를 참고해 주시기 바랍니다.


### Helm이란?

![](/assets/images/helm-op/01.png)

Helm이란 쿠버네티스 패키지 매니저입니다. `apt`나 `yum`과 같이 필요한 패키지를 쿠버네티스 위에 편리하게 설치할 수 있게 도와주는 툴입니다. helm에서는 패키징된 아카이브를 helm chart라 부릅니다. helm chart에는 크게 빼대를 이루는 templates와 그 빼대에 살을 채우는 `values.yaml` 파일이 존재합니다. `values.yaml`파일에는 각 인프라 설정에 따라서 세부적으로 customization하는 부분입니다. 이 두개의 조합으로 하나의 패키지가 완성되어 쿠버네티스 위에 올라갑니다. 많은 쿠버네티스 사용자들이 이 helm chart를 이용하여 어플리케이션을 관리합니다.


![](/assets/images/helm-op/02.png)

helm chart만으로도 쿠버네티스를 효율적으로 운영하는데 굉장히 큰 도움이 됩니다. 하지만 서비스가 성장함에 따라 동일한 어플리케이션도 상황에 따라 조금씩 달라지는 경우가 발생하죠. 위의 그림과 같이 같은 NGINX 서버라 하더라도 운영과 개발을 나누기도 하고 웹서버로 사용하거나 proxy 서버로 사용하기도 합니다. 어플리케이션의 개수가 늘어나게 되면 자연스럽게 chart의 개수도 많아지게 되어 관리할 chart가 많아지게 됩니다. 하지만 조금만 생각해보면 nginx template은 상황에 따라 변하지 않는 공통부인 것을 알 수 있습니다. 그렇기 때문에 아래와 같이 공통부 template은 하나로 사용하고 구성에 따라 다른 `values.yaml` 파일을 사용하여 여러 어플리케이션을 생성할 수 있습니다.

더 나아가 `values.yaml` 파일만 따로 떼어다가 Operator로 관리하려는 시도들이 생겨 났고 그것이 바로 오늘 소개해 드릴 Flux 프로젝트의 일부인 **Helm Operator**입니다.

![](/assets/images/helm-op/033.png)

### Operator란?

Operator란 쿠버네티스 클러스터 위에서 동작하며 Custom Resource를 이용하여 쿠버네티스와 동일한 방법으로 리소스를 관리하는 소프트웨어를 말합니다. Operator를 이해하기 위해서는 먼저 쿠버네티스의 controller manager의 control loop을 이해할 필요가 있습니다. 쿠버네티스의 control loop은 지속적으로 current state와 desired state를 모니터링하며 새로운 리소스가 생성되어 desired state가 변경되었을 때 그것을 자동으로 감지하여 current state를 desired state와 sync되도록 동작합니다. 이런 control loop의 작업으로 인해 사용자가 새로운 리소스를 생성할 때 (예를 들어, `kubectl apply -f new_pod.yaml`) 그것이 쿠버네티스 클러스터에 반영이 됩니다. (실제로 Pod가 실행됨)

Operator란 쿠버네티스의 기본적인 쿠버네티스 리소스 이외에 Custom Resource 또한 쿠버네티스의 control loop 정책을 따라 동작하도록 만들어주는 주체이고 이러한 패턴을 따르는 것을 Operator 패턴이라고 부릅니다. 마치 custom controller manager 역할을 담당하는 것이죠. Operator 개발자가 Operator를 어떻게 개발하는가에 따라 새로운 Custom Resource가 생성될 때 동작하는 방법이 달라집니다.

### Helm Operator

Helm Operator란 Helm Chart를 Custom Resource처럼 관리할 수 있게 해주는 Operator입니다. Custom Resource가 생성될 때 helm chart를 설치해주고 (helm install) 리소스가 삭제될 때, helm list에서 삭제 (helm delete)합니다. Helm Operator에서 이 Custom Resource를 `HelmRelease`라고 부릅니다. 사용자가 `HelmRelease`라는 Custom Resource를 생성하게 되면 Helm Operator가 자체적으로 control loop를 살펴보다 변경된 것을 감지하여 새로운 helm release를 배포해 줍니다.

```bash
# 예시
kubectl apply -f myHelmRelease.yaml   # --> helm install myHelmRelease
```

위의 명령과 같이 `HelmRelease`라는 리소스를 하나 생성하게 되면 리소스의 값을 이용하여 helm chart를 하나 생성하게 됩니다. 이를 통해 helm chart를 쿠버네티스 리소스처럼 관리할 수 있게 됩니다.

### Flux

Flux는 GitOps라는 용어를 처음 사용한 Weaveworks라는 회사의 프로젝트 및 브랜드 이름입니다. GitOps 관련하여 도움을 줄 수 있는 여러 제품 및 소프트웨어의 집합입니다. Flux 아래에는 FluxCD, fluxctl 등 다양한 GitOps 관련된 제품들이 있고 Helm Operator도 그 중 하나입니다. 

### `HelmRelease` spec

그럼 이제 본격적으로 Helm Operator의 커스텀 리소스(CRD)인 `HelmRelease`가 어떻게 생겼는지 살펴보겠습니다. 아래에 보시는 YAML 파일이 가장 간단한 `HelmRelease` 리소스 정의입니다.

```yaml
apiVersion: helm.fluxcd.io/v1
kind: HelmRelease
metadata:
  name: rabbit
  namespace: default
spec:
  releaseName: rabbitmq
  chart:
    repository: https://kubernetes-charts.storage.googleapis.com/
    name: rabbitmq
    version: 3.3.6
  values:
    replicas: 1
```

- `apiVersion`, `kind`, `metadata`: 여느 리소스와 마찬가지로 가장 기본적인 리소스 정보를 입력합니다. 리소스의 버전, 종류, 이름 등을 설정합니다.
- `spec`: 여기서부터 `HelmRelease`에 특화된 세부 스펙이 정해집니다.
- `releaseName`: 배포된 helm chart의 이름을 지정합니다. (`helm install --name <RELEASE_NAME>` 부분)
- `chart`: chart의 공통부 template이 위치한 정보를 입력합니다. (helm repo, git repo 등)
- `values`: 상황에 따라 변경하는 `values.yaml` 파일의 정보를 해당 property에 입력합니다.

거창한 설명과는 다르게 `HelmRelease`의 정의는 굉장히 간단하고 명확한 것을 확인할 수 있습니다. 크게 3가지 부분,

- 쿠버네티스 리소스의 공통 정보 (`apiVersion`, `kind`, `metatdata`)
- chart template 위치 정보 (`chart`)
- 세부 설정 정보로 나뉩니다. (`values`)

결국 마지막 `values` property에 따라서 helm chart의 내용이 변경되기에 `values` 부분이 가장 중요한 정보를 담고 있다고 말할 수 있습니다.

그럼 이제 본격적으로 Helm Operator를 설치하고 사용해 봅시다.

### Helm Operator Install

Helm Operator를 설치하는 것은 비교적 간단합니다.
```bash
# CustomResourceDefinition 설정
kubectl apply -f https://raw.githubusercontent.com/fluxcd/helm-operator/1.0.1/deploy/crds.yaml
# 네임스페이스 생성
kubectl create ns flux
# helm repo 등록
helm repo add fluxcd https://charts.fluxcd.io
# helm-operator 설치
helm upgrade -i helm-operator fluxcd/helm-operator \
    --namespace flux \
    --set helm.versions=v3
```

flux 네임스페이스에 helm operator가 생성되었는지 확인합니다.

```bash
# 설치 확인
kubectl get pod -nflux
# NAME                READY   STATUS    RESTARTS
# helm-operator-xxx   1/1     Running   0       
```

helm-operator 라는 `Pod`가 Running하고 있다면 정상적으로 설치가 완료된 것 입니다.

### 첫 `HelmRelease` 생성하기

Jenkins 서비스를 설치하는 `HelmRelease` 리소스를 생성합니다. 이때 사용성에 따라서 운영용과 개발용 젠킨스를 생성합니다.

- 운영용 (prod)
```yaml
# jenkins-prod.yaml
apiVersion: helm.fluxcd.io/v1
kind: HelmRelease
metadata:
  name: jenkins-prod
  namespace: default
spec:
  releaseName: jenkins-prod
  chart:
    repository: https://kubernetes-charts.storage.googleapis.com
    name: jenkins
    version: 1.15.0
  values:
    master:
      resources:
        limits:
          cpu: "2"
          memory: "4Gi"
```

- 개발용 (dev)
```yaml
# jenkins-dev.yaml
apiVersion: helm.fluxcd.io/v1
kind: HelmRelease
metadata:
  name: jenkins-dev
  namespace: default
spec:
  releaseName: jenkins-dev
  chart:
    repository: https://kubernetes-charts.storage.googleapis.com
    name: jenkins
    version: 1.16.0
  values:
    master:
      resources:
        limits:
          cpu: "1"
          memory: "2Gi"
```

운영과 개발에 따라서 리소스 제한량과 젠킨스 버전을 다르게 설정합니다.
`HelmRelease` 리소스를 생성합니다.
```bash
kbuectl apply -f jenkins-prod.yaml

kubectl apply -f jenkins-dev.yaml
```

`HelmRelease`는 쿠버네티스 CRD 리소스이기 때문에 `apply` 명령 뿐만 아니라 `kubectl` 기본 명령이 전부 동일하게 작동합니다.

```bash
# HelmRelease list
kubectl get helmrelease

# Get resource detail
kubectl get hr jenkins-dev -oyaml

# Describe resource
kubectl describe hr jenkins-dev
```

실제로 helm chart가 배포되었는지 확인해 보겠습니다.

```bash
helm list
# NAME           NAMESPACE    REVISION    STATUS      CHART           APP VERSION
# jenkins-dev    default      1           deployed    jenkins-1.15.0  lts
# jenkins-prod   default      1           deployed    jenkins-1.16.0  lts

helm status jenkins-dev
# NAME: jenkins-dev
# ...
# REVISION: 1
# NOTES:
# 1. Get your 'admin' user password by running:
#   printf $(kubectl get secret --namespace default jenkins-dev -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode);echo
# 2. Get the Jenkins URL to visit by running these commands in the same shell:
#   export POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/component=jenkins-master" -l "app.kubernetes.io/instance=jenkins-dev" -o jsonpath="{.items[0].metadata.name}")
#   echo http://127.0.0.1:8080
#   kubectl --namespace default port-forward $POD_NAME 8080:8080
# 
# 3. Login with the password from step 1 and the username: admin
# 
# For more information on running Jenkins on Kubernetes, visit:
# https://cloud.google.com/solutions/jenkins-on-container-engine
```

사용자는 `HelmRelease` 리소스를 생성한 것이 전부지만 실제로 helm chart까지 완벽하게 서비스가 배포되는 것을 확인할 수 있습니다. 이렇게 helm operator를 잘 활용하면 복잡한 쿠버네티스 어플리케이션들도 `HelmRelease` YAML 파일들로만 컴팩트하게 관리할 수 있게 됩니다.

![](/assets/images/helm-op/05.png)

## 마치며

[GitOps와 ArgoCD](/kubernetes/gitops/argocd/2020/02/10/gitops-argocd/)에서는 단순히 기본 k8s 리소스만 이용한 어플리케이션 배포에 대해 설명 하였습니다. 물론 ArgoCD도 helm chart를 배포하는 것이 자체적으로 가능하지만 Helm Operator를 적절히 조합하여 사용한다면 복잡한 어플리케이션 구성도 한눈에 파악하기 쉬워집니다. 더불어 helm chart 배포 작업 자체를 쿠버네티스 리소스처럼 다룰 수 있기에 더욱이 GitOps 철학에 가깝게 서비스를 구성할 수 있어 보입니다. 여러분들도 Helm Operator를 이용하여 더 체계적이고 효율적인 방법으로 어플리케이션을 관리해 보시기 바랍니다.
