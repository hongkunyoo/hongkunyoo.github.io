---
layout: post
title:  "helm subchart 파헤치기"
date:   2019-06-05 00:00:00
categories: k8s helm
tags: k8s kubernetes helm subchart
---
이번 포스트에서는 여러 `chart`를 하나의 패키지로 관리할 수 있는 `helm subchart`라는 것에 대해서 알아보고 그 사용법에 대해서 알아보겠습니다.

저는 업무에 많이 사용하는 컴포넌트들을 helm 패키지 매니저를 이용하여 관리하였습니다. 기존에 설치 방법이 복잡한 소프트웨어도 `helm install` 하나면 설치가 뚝딱 되는 것을 보고 격한 감동을 받아 그 이후로 필요한 패키지들을 helm으로 설치하여 유용하게 잘 사용하였습니다.
 
#### helm 패키지 매니저란?
[helm](https://helm.sh/)이란 쿠버네티스 패키지 매니저입니다. 쉽게 생각해서 Debian계열의 패키지 매니저인 [apt](https://en.wikipedia.org/wiki/APT_(Package_Manager))이나 RedHat 계정의 [yum](https://en.wikipedia.org/wiki/Yum_(software)) 패키지 매니저의 쿠버네티스 버전이라고 생각하시면 됩니다. 패키지 설치에 필요한 설정들이 쿠버네티스의 YAML Resource 파일의 조합으로 구성되며 이것을 `chart`라고 부릅니다. 마지막으로 가장 중요한 파일인 `values.yaml`파일이 있는데 이것을 각 쿠버네티스 환경에 따라 설정값들을 변경할 수 있게 만들어 놓은 사용자 설정 파일입니다.


#### 패키지 개수의 증가, 그로 인한 관리의 복잡성 증가

시간이 지나 사용하는 패키지가 많아지게 되었고 그에 더하여 안정적인 운영을 위해 쿠버네티스 스택까지 나누게 되다보니 총 **helm 패키지 개수 X 쿠버네티스 스택 개수 (dev, staging, prod)** 만큼 설정값들을 관리해야 되게 되었습니다. 처음에는 각 스택별 각 패키지의 `values.yaml` 파일을 일일이 관리하였는데 설치하는 패키지의 수가 점점 많아지다 보니 이것을 스택별로 한곳에서 통합적으로 설정값을 관리하고 싶다는 생각을 하게 되었습니다. 처음에는 [helmfile](https://github.com/roboll/helmfile)이라는 것을 사용해볼까 생각하다가 이건 너무 over engineering인 것 같아 포기하였고 한때는 직접 탬플릿 엔진을 이용하여 하나의 파일을 가지고 각 chart의 `values.yaml` 파일을 생성하는 오픈소스를 만들어볼까도 생각했었는데 알고보니 helm 툴 자체에서 제가 딱 원하는 기능을 지원하는 것을 알게 되었습니다. (역시 공식 document를 잘 읽어야 됩니다. 그래야 저처럼 돌아돌아 오지 않죠ㅋ) 그것이 바로 `subchart`라는 것이였습니다.

#### 현재 구조 
* prod는 생략

```bash
dev/
 ├─redis/values.yaml        # dev redis 설정
 └─jenkins/values.yaml      # dev jenkins 설정

staging/
 ├─redis/values.yaml        # staging redis 설정
 └─jenkins/values.yaml      # staging jenkins 설정
```

#### 원하는 방법
* 각 stack에 연관되는 설정값을 한곳에서 통합 관리
* stack과 상관 없이 동일한 설정은 각 패키지에서 관리

```bash
charts/
 | values.yaml.dev           # dev 관련 통합 관리 (redis, jenkins)
 | values.yaml.staging       # staging 관련 통합 관리 (redis, jenkins)
 |
 ├── redis/values.yaml       # redis 공통 설정 - 스택별 변경 사항 없음
 └── jenkins/values.yaml     # jenkins 공통 설정 - 스택별 변경 사항 없음
```
---

###  subchart
subchart는 말그대로 chart 안에 chart를 만들어주는 기능입니다. 기능이랄 것도 없는게 단순히 chart 안에 또다른 chart를 만들면 subchart가 되는 것입니다.
예를 들어,
```bash
helm create parent
```
라고 chart를 하나 만들게 되면
다음과 같은 디렉토리 구조가 생기게 됩니다.
```bash
parent/
 | Chart.yaml      # chart 기본 정보 (이름, 버전, 설명)
 | values.yaml     # chart 설정 파일
 | templates/      # YAML resource 파일들이 위치하는 폴더
 | charts/         # subchart들이 들어갈 폴더
```
여기서 `charts` 디렉토리에 또 다른 chart를 만들게 되면 바로 subchart 기능을 사용하게 되는 것입니다.
```python
cd parent/charts
helm create child
```
그러면 최종적으로 아래와 같은 `subchart` 디렉토리 구조를 가지게 됩니다.

```bash
parent/
 | Chart.yaml      # chart 기본 정보 (이름, 버전, 설명)
 | values.yaml     # chart 설정 파일
 | templates/      # YAML resource 파일들이 위치하는 폴더
 | charts/
    └── child
         ├── Chart.yaml
         ├── values.yaml
         ├── templates/
         └── charts/ 
```

```yaml
parent/
 | Chart.yaml      # chart 기본 정보 (이름, 버전, 설명)
 | values.yaml     # chart 설정 파일
 | templates/      # YAML resource 파일들이 위치하는 폴더
 | charts/
    └── child
         ├── Chart.yaml
         ├── values.yaml
         ├── templates/
         └── charts/ 
```

```javascript
parent/
 | Chart.yaml      # chart 기본 정보 (이름, 버전, 설명)
 | values.yaml     # chart 설정 파일
 | templates/      # YAML resource 파일들이 위치하는 폴더
 | charts/
    └── child
         ├── Chart.yaml
         ├── values.yaml
         ├── templates/
         └── charts/ 
```

이렇게 구성한 다음 기본적인 각 패키지 설정은 `child/value.yaml`에서 하고 스택별로 변경이 일어나는 값들만 `parent/values.yaml`에서 관리하면 됩니다.

### how to



### 그 결과

