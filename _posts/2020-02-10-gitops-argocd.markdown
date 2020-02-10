---
layout: post
title:  "GitOps와 ArgoCD"
date:   2020-02-10 00:00:00
categories: kubernetes gitops argocd
---
오늘은 GitOps가 무엇인가에 대해서 알아보고 그 구현체인 ArgoCD에 대해서 살펴보는 시간을 가져보겠습니다.

## What is GitOps?

GitOps란 [Weaveworks](https://www.weave.works/)라는 회사에서 처음 쓰기 시작하였고 CI/CD 파이프라인 중 특별히 Delivery에 초점을 가지고 탄생한 개념입니다.

GitOps을 설명하기 전에 "Single source of truth" (SSOT), 직역하자면 단일 진실의 원천에 대해서 먼저 짚고 넘어가면 좋을 것 같습니다. 단일 진실의 원천을 풀어서 설명하자면, 어떠한 진실(결과)의 원인이 오직 단일한 원천(이유)에서 나왔다는 것을 의미합니다.

![01.png](/assets/images/gitops-argocd/01.png)

 쉽게 예를 들자면, 어떤 아이가 울고 있으면(결과) 그것은 오직 아이스크림을 땅바닥에 떨어뜨렸기 때문(이유)이라고 가정해 봅시다. 넘어져서 우는 것도 아니고 혼나서 우는 것도 아니라 오직 아이스크림을 땅바닥에 떨어뜨렸기 때문에 우는 것입니다. 반대로 아이스크림을 제대로 들고 있으면 항상 웃고 그 아이가 웃는다면 이유는 칭찬을 받아서도 아니고 과자를 먹어서도 아니고 오직 아이스크림을 떨어뜨리지 않았기 때문입니다.

![02.png](/assets/images/gitops-argocd/02.png)

이것이 단일 진실의 원천입니다. 오직 그 진실(결과)이 오직 한가지의 원천(이유)에서 비롯된다는 것입니다. 이것을 소프트웨어 Delivery (Deployment)에 적용해 보겠습니다. 소프트웨어 배포 관점에서 단일 진실의 원천을 얘기할 때 크게 두가지에 대해서 얘기해 보겠습니다.

### 단일한 방법으로의 소프트웨어 배포

우리가 어떤 소프트웨어를 개발하여 그것을 운영 환경에 반영할때 다양한 방법을 통해서 배포할 수 있습니다. 예를 들어, 자바 WAR 파일을 운영 환경의 Tomcat 서버에 배포를 한다고 했을 때, scp를 이용하여 파일을 배포할 수도 있고 S3에 파일을 올려놓고 운영 서버에서 그것을 다운 받을 수도 있습니다. 조금 더 체계적으로 배포를 하고 싶으면 ansible이나 chef 같은 툴을 이용하여 소프트웨어를 배포할 수도 있습니다. 소프트웨어를 배포 방법하는 방법이 다양하면 쉽게 문제가 발생할 소지가 많아지게 됩니다. 사람마다 배포하는 방법이 달라 human error가 증가하게 될 수 있고 다양한 배포 방법이 서로 충돌할 여지가 생길 수 있습니다. 이러한 문제 때문에 GitOps에서는 소프트웨어 배포 과정을 조금 더 체계적으로 관리하고 자동화하기 위해 모든 배포 정의를 한 곳에서 관리하고 오직 한가지 방법으로 배포하는 것을 추구합니다.

### 항상 원천의 상태를 완벽히 반영하는 배포

앞서 설명한 아이스크림과 아이의 예시에서 아이가 아이스크림의 상태를 완벽하게 반영한다고 볼 수 있습니다. 아이스크림을 들고 있으면 아이는 울지 않고 아이스크림을 떨어뜨리면 아이가 울기 때문이죠. 이것을 소프트웨어 배포 관점에서 보자면, 아이스크림은 배포 작업 정의서 (어떻게 소프트웨어를 배포할지 기술한 문서)를 의미하고 아이는 실제 배포된 상태를 나타냅니다. GitOps에서는 배포상태의 모습을 항상 원천과 동일하게 맞출려고 노력합니다.

"단일 진실의 원천" 방법을 통해 얻을 수 있는 장점은 다음과 같습니다.

1. 현재 배포환경의 상태를 쉽게 파악할 수 있습니다. 배포환경에 들어가서 상태를 파악할 필요 없이 원천(배포 작업서)만 살펴보면 되기 때문입니다.
2. 빠르게 배포할 수 있게 됩니다. 단일한 방법으로 소프트웨어를 배포하여 표준화 시켰기 때문에 쉽게 배포 자동화를 할 수 있고 이것은 더 빠르고 지속적인 배포를 가능케 합니다.
3. 안정적으로 운영 환경에 배포할 수 있습니다. 사람의 손을 거치지 않기 때문에 운영 반영에 발생할 수 있는 human error를 최소화 할 수 있습니다. 배포를 관장하는 사람은 원천의 상태만 잘 확인하면 됩니다.

지금까지 SSOT, 단일 진실의 원천에 대해서 설명 드렸는데 GitOps에서는 이름에서 알 수 있듯이 Git 저장소를 (단일 진실의) "원천"으로 사용합니다.

![03.png](/assets/images/gitops-argocd/03.png)

GitOps에서는 소프트웨어를 배포할 때, Git 저장소에 배포를 위한 작업 정의서를 기술하여 repository에 저장하면 GitOps의 구현체가 (이 글에서는 ArgoCD가) 배포상태를 원천과 맞추기 위해 Git repository에 저장된 배포 정의서를 읽어와서 운영 환경에 변경 사항을 반영합니다. 특히 쿠버네티스와 같이 선언형 (declarative description) 명령와 같은 배포 형태인 경우, Git 저장소에 원하는 배포 형태를 선언하기만 하면 그것을 운영에 반영하는 것은 굉장히 쉽습니다.

![04.png](/assets/images/gitops-argocd/04.png)

(출처: [https://www.weave.works/technologies/gitops/](https://www.weave.works/technologies/gitops/))

## GitOps의 구현체 ArgoCD

GitOps는 특정 소프트웨어나 프로덕트가 아닌 철학 혹은 방법론에 더 가깝습니다. GitOps에서 요구하는 원칙들은 다음과 같습니다.

#### 1. 선언형 배포 작업 정의서

배포 방법이 명령형 방식으로 정의된 것이 아니라 배포된 상태가 어떤 모양을 가져야 할지 선언되어 있는 방식으로 정의가 되어 있어야 합니다. 이것은 사용자가 배포의 원하는 상태 (desired state)를 선언적으로 정의하였다는 것을 의미합니다. 이를 통해 Git 저장소에 단일 진실의 원천 조건을 만족할 수 있습니다. 배포 작업 정의서가 선언형으로 되어 있으면 더 쉽게 배포할 수 있으며 문제 발생시, 롤백하기도 쉽습니다. 또한 장애 등으로 인해 손상된 배포 환경을 자가 치유하기 유리합니다.

#### 2. Git을 이용한 배포 버전 관리

Git에 모든 배포에 관련된 정보가 정의되어 있어야 하며, 각 버전이 Git 저장소에 기록이 되어 있어야 합니다. 이를 통해 사용자는 쉽게 예전 버전으로 롤백을 하거나 새로운 버전으로 업그레이드를 할 수 있게 됩니다.

#### 3. 변경 사항 운영 반영 자동화

사용자는 Git 저장소에 선언형 정의서를 저장하게 되면 실제 배포가 일어나는 작업은 자동으로 이루어져야 합니다. 이것을 책임지는 주체가 ArgoCD와 같은 배포 주체(deploy operator)가 됩니다. 이를 통해 human error를 줄이고 지속적 빌드/배포를 가능하게 만듭니다.

#### 4. 자가 치유 및 이상 탐지

사용자가 원하는 배포 상태 (desired state)를 작성하게 되면 실제 배포 환경이 그에 맞게 유지되고 있는지 책임지는 것 또한 배포 주체(deploy operator)가 됩니다. 배포를 관장하는 소프트웨어가 주체가 되어 현재 배포 상태를 확인하고 Git 저장소의 변경 사항 등이 없는지를 체크하여 운영 환경에 반영하는 역할을 합니다.

이러한 원칙들을 가지고 소프트웨어를 배포하는 모든 Agent를 우리는 GitOps의 구현체 (Deploy Operator)라 부를 수 있습니다. 현재 GitOps의 구현체로 ArgoCD 뿐만 아니라 Weaveworks flux, Codefresh, Jenkins X 등 다양한 소프트웨어들이 존재합니다.

이번 포스트에서는 ArgoCD에 대해서 설명 드립니다.

### ArgoCD 설치하기
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
Ingress 설정 및 비밀번호 설정 등은 공식 홈페이지에서 참고 하시기 바랍니다.

[https://argoproj.github.io/argo-cd/getting_started/](https://argoproj.github.io/argo-cd/getting_started/)

### ArgoCD 둘러보기

ArgoCD를 설치하여 로그인하면 가장 먼저 볼 수 있는 화면은 아래와 같습니다. 지금까지 생성한 배포 App의 리스트를 보여주는 화면입니다. 새로운 배포를 관장하는 App을 생성해 보기 위해 `New App` 버튼을 눌러보겠습니다.
![05.png](/assets/images/gitops-argocd/05.png)

새로운 배포을 책임지는 App을 생성하는 화면입니다.

![06.png](/assets/images/gitops-argocd/06.png)

- Application Name: App의 이름을 적습니다.
- Project: 프로젝트를 선택하는 필드입니다. 쿠버네티스의 namespace와 비슷한 개념으로 여러  App을 논리적인 project로 구분하여 관리할 수 있습니다.
- Sync Policy: Git 저장소의 변경 사항을 어떻게 sync할지 결정합니다. Auto는 자동으로 Git 저장소의 변경사항을 운영에 반영하고 Manual은 사용자가 버튼 클릭을 통해 직접 운영 반영을 해줘야 합니다.
- Repository URL: ArgoCD가 바라볼 Git 저장소를 의미합니다.
- Revision: Git의 어떤 revision (HEAD, master branch 등)을 바라 볼지 결정합니다.
- Path: Git 저장소에서 어떤 디렉토리를 바라 볼지 결정합니다. (dot(.)인 경우 root path를, 디렉토리 이름을 적으면 해당 디렉토리의 배포 정의서만 tracking 합니다.)
- Cluster: 쿠버네티스의 어느 클러스터에 배포할지를 결정합니다.
- Namespace: 쿠버네티스 클러스터의 어느 네임스페이스에 배포할지를 결정합니다.
- Directory Recurse: path아래의 디렉토리를 재귀적으로 모니터링하여 변경 사항을 반영합니다.

### ArgoCD를 통한 운영 배포해보기

아래의 깃헙 레포지토리를 예시로 배포해 보겠습니다. 간단하게 nginx 컨테이너를 생성하고 서비스를 붙여주는 앱입니다.

GitOps repository 예시: [https://github.com/hongkunyoo/gitops-argocd.git](https://github.com/hongkunyoo/gitops-argocd.git)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mynginx
spec:
  replicas: 1
  selector:
    matchLabels:
      run: mynginx
  template:
    metadata:
      labels:
        run: mynginx
    spec:
      containers:
      - image: nginx
        name: mynginx
        ports:
        - containerPort: 80
```
```yaml
apiVersion: v1
kind: Service
metadata:
  name: mynginx
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    run: mynginx
```

- Application Name: gitops-argocd
- Project: default
- Sync Policy: manual
- Repository URL: [https://github.com/hongkunyoo/gitops-argocd.git](https://github.com/hongkunyoo/gitops-argocd.git)
- Revision: HEAD
- Path: .
- Cluster: in-cluster
- Namespace: default
- Directory Recurse: Unchecked

위와 같이 값을 설정해주고 `Create` 버튼을 클릭합니다.

`SYNC` 버튼을 눌러 ArgoCD가 변경 사항을 확인하여 단일원천의 진실에 따라 운영 환경을 그에 맞게 변경하도록 하겠습니다. 아래와 같이 Service 리소스와 nginx pod가 생성된 것을 UI로 확인하실 수 있습니다.

![07.png](/assets/images/gitops-argocd/07.png)

`App Details` 버튼을 누르거나 각 리소스UI를 클릭하시면 더 자세한 내용들을 직접 확인할 수 있습니다.

![08.png](/assets/images/gitops-argocd/08.png)

앞써 App을 설정할때 `sync-policy`를 `manual` 설정하였습니다. 아래에 `Auto-Sync` 버튼을 활성화하게 되면 `Automatic`이 되어 매번 사람이 직접 변경사항을 ArgoCD에게 알릴 필요 없이 ArgoCD가 주기적으로 Git 레포지터리의 변경사항을 확인하여 변경된 부분을 적용하게 됩니다. 이때 두가지 옵션을 추가적으로 줄 수 있습니다.

- Prune Resources: 변경 사항에 따라 리소스를 업데이터할 때, 기존의 리소스를 삭제하고 새로운 리소스를 생성합니다. Job 리소스처럼 매번 새로운 작업을 실행해야 하는 경우 이 옵션을 사용합니다.
- Self Heal: 해당 옵션을 활성화 시키면 ArgoCD가 지속적으로 git repository의 설정값과 운영 환경의 값의 싱크를 맞출려고 합니다. 기본적으로 5초마다 계속해서 sync를 시도하게 됩니다. (default timeout)

해당 예시에서는 `Auto-sync`만 활성화 시켜보겠습니다. 그런 다음, 이제 git repository의 deployment replica 값을 2로 고쳐서 push하게 되면 ArgoCD가 자동으로 변경한 값을 운영 환경에 반영하는지 확인해 보겠습니다.
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mynginx
spec:
  replicas: 2         # <-- 기존 1에서 2로 수정
  selector:
    matchLabels:
      run: mynginx
  template:
    metadata:
      labels:
        run: mynginx
    spec:
      containers:
      - image: nginx
        name: mynginx
        ports:
        - containerPort: 80
```
```bash
git commit -am "Change deployment replica to 2"
git push origin master
```
아래 그래프와 같이 기존 1개 pod에서 2개로 늘어난 것을 확인할 수 있습니다.

![09.png](/assets/images/gitops-argocd/09.png)

## 마치며

개인적으로 GitOps 스타일로 쿠버네티스 앱 배포를 하게 되면서 정말 배포 작업이 간결해지고 명확해졌습니다. 배포하는 작업이 편해지게 되니 스트레스 없이 더 자주, 더 빠르게 새로운 버전을 운영에 반영할 수 있게 되어 진정한 CI/CD를 이룩하게 된 것 같습니다. 여러분도 굳이 ArgoCD가 아니더라도 GitOps 스타일로 앱을 배포하여 손쉬운 소프트웨어 배포 프로세스를 정립해 나가시길 권해 드립니다. 그리고 아직 어떤 GitOps 구현체를 사용할지 결정하지 않으셨다면 ArgoCD가 제격이라고 생각합니다.
