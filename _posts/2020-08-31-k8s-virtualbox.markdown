---
layout: post
title:  "나만의 k8s 클러스터 구축하기 - #1 VirtualBox편"
date:   2020-08-31 00:00:00
categories: kubernetes cluster virtualbox
image: /assets/images/k8s-cluster/landing.png
---
쿠버네티스 클러스터를 만드는 방법은 다양합니다. Minikube을 이용하는 방법, 클라우드 플랫폼의 VM을 이용하여 구축하는 방법, 라즈베리파이 보드를 구매하여 클러스터를 만드는 방법 등 다양한 방법들이 있습니다. "나만의 k8s 클러스터 구축하기" 시리즈에서 이러한 방법들을 하나씩 살펴 볼까합니다. 첫 포스트에서는 원도우 PC위에 VirtualBox를 이용하여 나만의 쿠버네티스 클러스터를 구축하는 방법에 대해서 살펴보겠습니다.

클러스터 구축에 사용할 스택은 다음과 같습니다.

- Windows10 (64bit): 윈도우10을 기준으로 설명하나 VirtualBox가 설치되는 어떤 호스트도 가능합니다.
- VirtualBox: 오라클에서 만든 오픈소스 하이퍼바이저로 가상머신을 띄울 수 있게 해줍니다. 나의 윈도우PC 위에 두개의 우분투 서버를 생성하기 위해 설치합니다.
- Ubuntu 20.04: 우분트 서버를 기준으로 쿠버네티스 클러스터를 생성해보겠습니다.
- k3s: 적은 리소스로도 쿠버네티스 컴포넌트를 실행할 수 있도록 경량화한 쿠버네티스 배포판입니다. IoT & Edge 디바이스 위에서 돌릴 수 있도록 가볍게 만들어졌습니다.


## 나만의 쿠버네티스 클러스터 아키텍처

클러스터 구조는 다음과 같습니다.

![](/assets/images/k8s-cluster/01.png)

나의 윈도우PC 위에 Oracle VirtualBox를 설치하고 Ubuntu 20.04 VM 2대를 생성합니다. 이 때 master와 worker가 서로 통신할 수 있고 NAT로 외부와 통신할 수 있는 `k8s-network`라는 네트워크 서브넷을 만듭니다. 이 네트워크는 `10.0.1.0/24`의 범위를 가집니다. master와 worker는 해당 네트워크 안에서 각각 `10.0.1.5`, `10.0.1.6`의 IP를 가지고 default gateway(`Virtual NAT`)는 `10.0.1.1`의 IP를 가집니다.


## Ubuntu 20.04 Desktop 다운로드

VM에서 사용할 우분트 `iso` 이미지를 다운로드 받습니다. 다음 사이트를 접속하여 Desktop image를 선택합니다.

`https://releases.ubuntu.com/20.04/`

![](/assets/images/k8s-cluster/01-02.png)

## VirtualBox 설치

이미지를 다운 받는 동안 VirtualBox를 설치합니다. 다음 사이트를 접속하여 `VirtualBox platform packages` > `Windows hosts`에서 VirtualBox 설치 파일을 다운 받습니다. 윈도우가 아닌 다른 운영체제에서 구축하는 경우, 그에 맞는 플랫폼을 선택하시기 바랍니다.

`https://www.virtualbox.org/wiki/Downloads`

설치 방법

- 설치 파일 더블 클릭 > Welcome 메세지 (Next) 
- 설치 위치 정하기 (Next) > 옵션 정하기 (Next) 
- Warning Network Interfaces (Yes) > Ready to Install (Install) 
- 앱 디바이스 변경 허용 (예) > 이 장치 소프트웨어를 설치하시겠습니까? (설치) 
- Finish

설치가 완료되면 다음과 같은 VirtualBox 프로그램 화면을 볼 수 있습니다. 이제 본격적으로 네트워크 및 노드를 구성해보겠습니다.

![](/assets/images/k8s-cluster/01-03.png)

## 네트워크 및 노드 설정

### NAT 네트워크 구성

노드끼리 서로 통신하고 인터넷과 연결하기 위해서 NAT 네트워크를 먼저 구성해야 합니다.

1. `CTRL + G`를 눌러 환경 설정에 들어갑니다. (`파일-환경 설정`으로도 들어갈 수 있습니다.)
2. `네트워크` 클릭
3. 새 NAT 네트워크를 추가합니다.
4. 추가된 `NatNetwork` 더블클릭
5. 다음과 같이 설정합니다.
  - 네트워크 이름: k8s-network
  - 네트워크 CIDR: 10.0.1.0/24
  - 네트워크 옵션: DHCP 지원 (체크)
6. 확인

`확인`을 누르면 가상의 NAT 네트워크가 생성된 것입니다. 이 네트워크 안에 우분투 노드 2대를 생성해보겠습니다.

## master 노드 설치

### VM 생성

1. `CTRL + N` (새로 만들기)를 눌러 VM을 생성합니다.
2. 다음과 같이 설정합니다.
  - 이름: `master`
  - 머신 폴더: 디스크 용량이 넉넉한 드라이버를 선택해 주세요.
  - 종류: Linux
  - 버전: Ubuntu (64-bit)
3. 메모리 크기: 4,096 MB (k3s 스펙상 512 MB도 가능하나 원활한 테스트를 위해 최소 4GB를 잡습니다.)
4. 지금새 가상 하드 디스크 만들기
5. VDI(VirtualBox 디스크 이미지)
6. 하드 디스크: 고정 크기
7. 하드 디스크 크기: `20 GB`
8. 만들기

생성이 완료되면 다음과 같은 VM 하나가 생성된 것을 볼 수 있습니다.

![](/assets/images/k8s-cluster/01-04.png)

### VM 설정

설정 (`CTRL + S`)를 누릅니다.

- 일반
  - 고급
  - 클립보드 공유: `양방향`
- 네트워크
  - 어댑터 1
  - 네트워크 어댑터 사용하기 (체크)
  - 다음에 연결됨: `NAT 네트워크` (`NAT`라고만 적혀 있는 것은 다른 네트워크입니다.)
  - 네트워크 이름: k8s-network
- 확인

### VM 시작 및 우분투 설치

master VM을 더블클릭하여 서버를 구동합니다.

- 시동 디스크 선택: 다운로드 받은 우분투 20.04 이미지를 선택합니다.
- 시작
- English > Install Ubuntu (사용자의 취향에 맞게 설정합니다.)
- Keyboard layout: English > English(US) (사용자의 취향에 맞게 설정합니다.) > Continue
- Minimal installation > Download updates (체크 해제) > Continue
- Erase disk and install Ubuntu (사용자의 취향에 맞게 설정합니다.) > Install Now
- Write the changes to disk? > Continue
- Where are you? (Seoul) > Continue
- Who are you?
  - Your name: ubuntu
  - Your computer's name: master
  - Pick a username: ubuntu
  - Password: (사용자 지정)
- Installation Complete > Restart Now
- Please remove the installation medium, then press ENTER > ENTER

### 네트워크 설정

우분투 서버를 접속하여 네트워크를 설정합니다.

![](/assets/images/k8s-cluster/01-05.png)

- 우측 상단, 네트워크 아이콘 클륵
- Settings 클릭
- 톱니바퀴 아이콘 클릭
- 이미 `10.0.1.4`로 IP가 자동으로 잡혀져있는 것을 확인할 수 있지만 IP를 명시적으로 고정시키기 위해 IPv4 수동 설정을 합니다.
- IPv4 탭 클릭 > Manual 선택
  - Address: 10.0.1.4
  - Netmask: 255.255.255.0
  - Gateway: 10.0.1.1
  - DNS: 8.8.8.8
- Apply 버튼 클릭
- 네트워크 반영을 위해 토클 버튼을 눌러 잠깐 껐다가 다시 켜줍니다.

`CTRL + ALT + T`를 눌러 터미널을 엽니다. 네트워크 설정이 정상적으로 동작하는지 확인해 보기 위해 다음 명령을 수행합니다.

```bash
sudo apt update
```

인터넷이 정상적으로 작동하면 VM 복제를 위해 종료합니다.

```bash
sudo shutdown now
```

## worker 노드 설치

### worker 복제
worker 노드를 설치하는 것은 조금 더 쉽습니다. 이미 생성한 master 노드를 복제하면 되기 때문입니다. 종료된 master 노드를 우클릭하여 복제 메뉴를 클릭합니다.

![](/assets/images/k8s-cluster/01-06.png)

- 이름: worker
- 경로: master VM을 저장한 위치에 저장합니다.
- MAC 주소 정책: 모든 네트워크 어댑터의 새 MAC 주소 생성
- 나머지 전부 체크 해제 > 다음
- 복제 방식: 완전한 복제 > 복제

복제가 완료되면 master, worker 노드 둘다 시작합니다.

### Host명 변경 및 네트워크 설정

worker 노드로 접속하여 Host명 변경 및 네트워크 설정을 합니다. master 노드를 복제했기 때문에 Host명이 `master`로 설정되어 있습니다. 이것을 `worker` 수정합니다. `CTRL + ALT + T`를 눌러 터미널을 열어 다음과 같은 명령을 수행합니다.

```bash
sudo hostname worker
sudo sh -c 'echo worker > /etc/hostname'
sudo sed -i 's/master/worker/g' /etc/hosts

# 터미널을 종료합니다.
exit
```

Host명 변경 후 네트워크 세팅으로 들어가 다음과 같이 설정합니다. 

- IPv4 탭 클릭 > Manual 선택
  - Address: 10.0.1.5
  - Netmask: 255.255.255.0
  - Gateway: 10.0.1.1
  - DNS: 8.8.8.8
- Apply 버튼 클릭
- 네트워크 반영을 위해 토클 버튼을 눌러 잠깐 껐다가 다시 켜줍니다.


## 쿠버네티스 클러스터 구축

VM 생성은 완료되었습니다. 이제 이 VM 위에 직접 k3s 클러스터를 구축해봅시다.


### k3s master 설정

master 노드로 접속합니다.

```bash
sudo apt update
sudo apt install -y docker.io nfs-common dnsutils curl

# k3s master 설치
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="\
    --disable traefik \
    --disable metrics-server \
    --node-name master --docker" \
    INSTALL_K3S_VERSION="v1.18.6+k3s1" sh -s -

# master 통신을 위한 설정
mkdir ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown -R $(id -u):$(id -g) ~/.kube
echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
source ~/.bashrc

# 설치 확인
kubectl cluster-info
# Kubernetes master is running at https://127.0.0.1:6443
# CoreDNS is running at https://127.0.0.1:6443/api/v1/namespaces...
# 
# To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.

kubectl get node -o wide
# NAME     STATUS   ROLES    AGE   VERSION        INTERNAL-IP    ...
# master   Ready    master   27m   v1.18.6+k3s1   10.0.1.1       ...
```

kubectl get node라는 명령으로 master가 보이고 STATUS가 READY로 확인할 수 있다면 일단 master 노드는 정상적으로 설치가 완료된 것입니다.

이제 클러스터에 worker 노드를 추가하기 위해 master 노드에서 NODE_TOKEN값과 MASTER_IP를 다음과 같이 확인합니다.


```bash
# master 노드 토큰 확인
NODE_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
echo $NODE_TOKEN
# K10e6f5a983710a836b9ad21ca4a99fcxx::server:c8ae61726384c19726022879xx

MASTER_IP=$(kubectl get node master -ojsonpath="{.status.addresses[0].address}")
echo $MASTER_IP
# 10.0.1.4
```

master 노드에서 확인한 값들을 복사해 주시기 바랍니다. worker 노드에서 사용할 예정입니다.

### k3s worker 설정

master 서버에서 나와 worker로 사용할 서버에 접속하여 다음과 같이 명령을 실행합니다. master 노드에서 확인한 NODE_TOKEN과 MASTER_IP를 변수에 입력합니다.

```bash

NODE_TOKEN=<master에서 확인한 토큰 입력>
MASTER_IP=<master에서 얻은 내부IP 입력>

sudo apt update
sudo apt install -y docker.io nfs-common curl

# k3s worker 노드 설치
curl -sfL https://get.k3s.io | K3S_URL=https://$MASTER_IP:6443 \
    K3S_TOKEN=$NODE_TOKEN \
    INSTALL_K3S_EXEC="--node-name worker --docker" \
    INSTALL_K3S_VERSION="v1.18.6+k3s1" sh -s -
```

worker 노드에서 설치가 완료된 이후에 worker 노드를 나와 다시 master 노드로 접속합니다. 다음 명령을 실행하여 worker 노드가 추가된 것을 볼 수 있고 STATUS가 READY로 나온다면 정상적으로 쿠버네티스 클러스터를 완성한 것입니다. (worker 노드가 정상적으로 클러스터에 추가되려면 시간이 조금 걸립니다.)

```bash
kubectl get node
# NAME      STATUS    ROLES    AGE   VERSION
# master    Ready     master   40m   v1.18.6+k3s1
# worker    Ready     <none>   17m   v1.18.6+k3s1
```

## 마치며

VirtualBox 위에 우분투 데스크탑과 k3s를 이용하여 나만의 쿠버네티스 클러스터를 구축하는 방법에 대해서 살펴봤습니다. 우분투 데스크탑을 이용하여 클러스터를 만든 경우, 웹 브라우저에서 localhost로 바로 결과물을 볼 수 있는 장점이 있습니다. 이제 즐겁게 가지고 놀 수 있는 나만 k8s 클러스터가 내 손안에 생겼습니다! 즐쿠 바랍니다.
