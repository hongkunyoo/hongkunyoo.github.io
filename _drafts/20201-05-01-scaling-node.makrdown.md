---
layout: post
title:  "[번역] 쿠버네티스 2,500개 노드 운영하기"
date:   2021-05-01 00:00:00
categories: kubernetes scale
image: /assets/images/?
---
[다음 블로그 포스트](https://openai.com/blog/scaling-kubernetes-to-2500-nodes/)를 통해 많은 내용들을 배웠고 일부는 공감하여 기록으로 남기고자 번역하였습니다. 해당 포스트는 2018년에 나온 글로 현재 시점에서 이미 문제가 해결되었거나 개선된 점이 있어 동일한 방법을 이용하여 문제를 해결할 필요는 없지만 그 과정에서 배울 점들이 분명 있어 보이기에 여전히 의미 있는 글이라고 생각합니다. 주된 내용으로 OpenAI에서 딥러닝 연구 플랫폼으로 쿠버네티스를 사용하면서 노드를 늘렸을 때 발생할 수 있는 문제에 대해서 해결한 과정을 상세히 설명합니다.

우리는 2년 동안 딥러닝 연구용으로 쿠버네티스를 사용해 왔습니다. 우리의 가장 큰 작업(workload)은 클라우드에서 VM을 직접 사용하지만 쿠버네티스는 빠른 개발 주기를 제공하고 합리적인 확장성 그리고 적은 공수로 학습 작업을 수행할 수 있어 우리가 사용하는 대부분의 딥러닝 실험에 적합합니다. 현재는 몇몇의 클러스터를 운영하고 있고(어떤 것은 클라우드에서, 어떤 것은 베어메탈에서 운영합니다.) 가장 큰 클러스터는 2500대의 노드를 가지고 있습니다. 이 클러스터는 Azure 위에서 D15v2와 NC24 VM으로 이루어져있습니다.

이 정도의 클러스터로 규모를 키우기까지 많은 시스템 컴포논트에서 장애가 발생하였습니다. etcd, kube master, 도커 이미지 pull, 네트워크 KubeDSN 그리고 호스트서버의 ARP cache에서도 문제가 발생했습니다. 우리가 경험한 이슈들과 해결 방법들이 많은 이들에게 도움이 될 것 같아 내용을 공유하고자 합니다.


## etcd

500 노드를 넘기자, 쿠버네티스를 사용하는 리서처분들이 `kubectl`를 사용할때 잦은 timeout이 발생한다는 보고를 들었습니다. 이를 해결하기 위해 `kube-apiserver`를 더 추가하였지만 이것은 일시적인 해결책이었습니다. api 서버가 10대를 넘어가지 이러한 조치는 근본적인 문제를 해결하지 못한다는 것을 깨닫게 되었습니다.(비교하자면, GKE에서는 32 코어 1개 VM으로 500 노드를 관리합니다.)

우리는 쿠버네티스 마스터 서버의 상태 정보를 저장하는 etcd 클러스터를 의심하기 시작하였습니다. Datadog를 통해 etcd가 동작하는 DS15v2 서버에서 5,000 IOPS를 지원하는 P30 SSD를 사용하는데도 불구하고 "쓰기" 동작에서 몇백 밀리세컨드의 튀는 현상(spiking)을 확인하였습니다.

![](https://openai.com/content/images/2018/01/disk-latency-alt-1.png)
이 latency가 전체 클러스터의 응답 시간을 늦췄습니다.

fio를 통해 성능 벤치마크를 한 결과, etcd가 가용한 IOPS 중 단지 10%만 사용 가능한 것을 확인하였습니다. 왜냐하면 쓰기 지연시간은 약 2ms였고 etcd는 순차적인 I/O를 수행했기 때문에 latency-bound한 작업이 되었습니다.

그래서 etcd 디렉토리를 네트워크에 연결된 디스크에서 직접 로컬 디스크에 연결된 SSD로 옮겼습니다. 로컬 디스크로 디렉토리를 옮기자 지연시간이 200us로 줄어 들었고 etcd가 다시 정사적으로 동작하기 시작하였습니다!

이 클러스터는 1,000대 노드를 지나기까지 아무런 문제 없이 동작하였습니다. 1,000대가 지난 이후 시점부터 다시 etcd에서 높은 지연시간이 걸리는 것을 확인했습니다. 이번에는 `kube-apiserver`가 etcd로부터 500MB/s가 넘는 데이터를 읽어 들이는 것을 확인했습니다. Prometheus를 설정하고 audit log(`--audit-log-path`, `--audit-log-maxbackup`)를 추가하여 확인해 보니, 몇가지 슬로우 쿼리와 `Events` API를 LIST하는 api 콜이 엄청나다는 것을 확인하였습니다.

근본적인 원인은 FluentD와 Datadog의 기본 설정값에 있었습니다. 이들의 설정은 클러스터의 모든 노드로부터 API서버로 모니터링 값을 질의하도록 되어 있었습니다.(해당 이슈는 이제 수정되었습니다.) 우리는 이들의 시스템이 조금 덜 공격적이게(aggressive) 질의하도록 수정한 후, API서버가 정상으로 돌아오는 것을 확인할 수 있었습니다.

![](https://openai.com/content/images/2018/01/network-traffic--1-.png)
etcd egress 트래픽이 500MB/s 이상에서 거의 0으로 떨어지는 것을 확인하였습니다.(음수는 egress 트래픽을 의미합니다.)

한가지 팁으로, 쿠버네티스의 `Event`를 etcd 클러스터와 분리하여 저장하는 것을 추천 드립니다. 이것은 Event 생성 spike로 인한 부하가 메인 etcd 클러스터 성능에 영향을 미치지 않게 해줍니다. 이것은 단지 `--etcd-servers-overrides`라는 옵션을 수정하기만 하면 됩니다. 예를 들어 다음과 같습니다: `--etcd-servers-overrides=/events#https://0.example.com:2381;https://1.example.com:2381;https://2.example.com:2381`

노드 1,000대 이후의 또 다른 클러스터 장애로 etcd의 hard 저장용량 한도(hard storage limit: 기본 2GB)에 도달한 사건입니다. etcd의 저장용량 한도에 도달하게 되면 "쓰기"를 할 수 없게 되고 이것은 연쇄적인 장애를 일으킵니다. 모든 노드에서 health check가 실패하게 되고 autoscaler가 이것을 보고 모든 워커 노드들을 삭제하게 되었습니다.(역자주: 클라우드에서 동작하는 cluster autoscaler는 직접 노드를 추가/삭제할 수 있습니다.) 우리는 `--quota-backend-bytes`라는 설정값을 이용하여 etcd 최대 사이즈를 늘렸고 autoscaler로 하여금 클러스터의 노드 중 50% 이상 삭제해야 하는 경우에는 실제로 동작하지 않도록 안전장치를 추가하였습니다.

## Kube masters

우리는 `kube-apiserver`, `kube-controller-manager` 그리고 `kube-scheduler`를 같은 서버에 동작하도록 구성하였습니다. 그리고 고가용성을 위해 최소 2대 이상의 마스터를 운영하였습니다. 마지막으로 Prometheus가 마스터 노드의 개수를 헷갈려하지 않게 하기 위해 `--apiserver-count`라는 설정값을 마스터 노드의 개수와 동일하게 맞췄습니다.

우리는 쿠버네티스 클러스터를 배치 시스템으로 주로 사용하였고 주로 autoscaler를 통해 동적으로 노드의 개수를 추가하고 제거하도록 하였습니다. 이를 통해 노는 노드를 없애어 획기적으로 비용을 줄일 수 있었고 그와 동시에 적은 지연시간으로 빠르게 작업을 반복할 수 있었습니다. `kube-scheduler`의 기본 스케줄링 정책은 최대한 워크로드를 넓게 흩트려 놓게 설정되어 있었지만 우리는 그 반대로 최대한 작업들이 한곳으로 모아(역자주: binpacking scheduling 정책을 말합니다.) 사용되지 않는 노드는 제거하고 큰 리소스가 필요한 `Pod`를 빠르게 스케줄링하도록 설정하고 싶었습니다. 이를 달성하고자 `kube-scheduler`의 스케줄링 정책을 다음과 같이 수정하였습니다.

```json
{
  "kind" : "Policy",
  "apiVersion" : "v1",
  "predicates" : [
    {"name" : "GeneralPredicates"},
    {"name" : "MatchInterPodAffinity"},
    {"name" : "NoDiskConflict"},
    {"name" : "NoVolumeZoneConflict"},
    {"name" : "PodToleratesNodeTaints"}
  ],
  "priorities" : [
    {"name" : "MostRequestedPriority", "weight" : 1},
    {"name" : "InterPodAffinityPriority", "weight" : 2}
  ]
}
```

우리는 KubeDNS를 서비스 탐색(service discovery)용으로 많이 사용하였습니다. 하지만 새로운 스케줄링 정책을 적용한 이후부터 안정성 문제가 발생하기 시작하였습니다. 우리는 이러한 문제가 특정 KubeDNS Pod에서만 발생하는 것을 확인하였습니다. 새로운 정책으로 인해 특정 노드에서는 10개 이상의 KubeDNS Pod가 생성되어 모든 요청이 이곳으로 집중되어 Azure VM이 허용하는 도메인 질의에 200QPS를 넘어서게 되었습니다. 해결책으로 KubeDNS Pod에는 `anti-affinity` 설정을 적용하여 명시적으로 서로 떨어트려 집중되는 문제를 해결하였습니다.

```yaml
affinity:
 podAntiAffinity:
   requiredDuringSchedulingIgnoredDuringExecution:
   - weight: 100
     labelSelector:
       matchExpressions:
       - key: k8s-app
         operator: In
         values:
         - kube-dns
     topologyKey: kubernetes.io/hostname
```

## 도커 이미지 pulls

[Dota 프로젝트](https://openai.com/blog/more-on-dota-2/)는 쿠버네티스 위에서 진행되었습니다. 노드의 개수가 증가함에 따라 `Pod`가 `Pending` 상태로 머물러 있는 것을 발견하였습니다. 게임의 이미지가 17GB가 넘었기에 새로운 노드에 이미지를 다운로드하기 위해서는 약 30분이 걸리곤 하였습니다. Dota 이미지는 컸기 때문에 해당 상황에 대해서 이해하고 있었습니다. 하지만 다른 컨테이너에서도 동일한 현상이 발생하였습니다. 자세히 조사해 본 결과 `kubelet`에는 `--serialize-image-pulls`라는 옵션이 기본값으로 `true`로 설정되어 있는 것을 알게 되었습니다. 이 설정 때문에 Dota 이미지가 다른 컨테이너들의 이미지 pulling을 막고 있었던 것입니다. 해당 설정을 `false`로 변경하기 위해서는 도커 스토리지 드라이버가 AUFS가 아닌 overlay2로 설정되어야 합니다. 또한 이미지 pull 속도를 올리기 위해서 도커 root 디렉토리도 etcd 디렉토리처럼 직접 로컬 디바이스로 연결된 SSD 아래로 옮겼습니다.

pull 속도를 개선한 이후에도 다음과 같은 이상한 에러 메세지를 출력하면 `Pod` 실행이 실패하는 것을 알게 되었습니다: `rpc error: code = 2 desc = net/http: request canceled`. `kubelet`과 `docker` 로그에서도 작업이 진행되지 않아 이미지 pull 작업이 취소되었다는 메세지가 출력되는 것을 확인하였습니다. 이러한 현상은 너무 큰 이미지를 다운로드 받을 때 발생한다는 것을 알게 되었습니다. 이 문제를 해결하기 위해 `kubelet`의 `--image-pull-progress-deadline` 옵션을 30분으로 늘렸고 docker daemon 프로세스의 max-concurrent-download 옵션을 10으로 설정하였습니다.(해당 옵션은 큰 이미지 다운로드 속도에 영향을 주진 않았지만 병렬로 이미지를 다운로드 받을 수 있게 만들었습니다.)

또 다른 도커 이미지 pull 이슈는 Google Container Registry 때문에 발생하였습니다. 기본적으로 `kubelet`이 `gcr.io`로부터 특정 이미지를 pull 받습니다. 이것은 `--pod-infra-container-image` 옵션으로 설정 가능합니다 (역자주: `kube-apiserver`, `kube-scheduler`, `pause`, `kubeDNS` 이미지 등 대부분의 쿠버네티스 코어 컴포넌트가 이에 해당합니다.) 만약 무슨 일에 의해서든 (예를 들어 quota 제약에 걸리는 경우) 이미지가 정상적으로 다운로드 되지 않는 경우 `Pod`가 정상적으로 실행되지 못하게 됩니다. 클러스터 내에 모든 노드들은 직접 외부 인터넷과 연결되는 것이 아니라 NAT를 거쳐서 나가기 때문에 모든 노드의 IP가 외부에서는 동일하게 나타나게 되고 이로 인해 IP당 이미지 pull 한계에 도달할 수도 있습니다. 이를 해결하기 위해서 `docker image save`와 `load` 명령을 이용하여 미리 모든 노드에 해당 이미지를 preload하는 방법이 있습니다. 성능을 향상 시키기 위해 쿠버네티스 코어 이미지 뿐만 아니라 자주 사용하는 내부 이미지들도 동일한 방식으로 미리 이미지를 준비해 둘 수 있습니다.

역자주: `docker image save/load` 명령을 이용할 수도 있지만 registry mirror 서버를 두고 docker daemon의 `registry-mirrors` 설정을 직접 구축한 mirror 서버로 변경하는 방법도 있습니다. (참고: [https://docs.docker.com/registry/recipes/mirror/#configure-the-docker-daemon](https://docs.docker.com/registry/recipes/mirror/#configure-the-docker-daemon))

## 네트워킹

As our experiments grow larger, they also become increasingly complex distributed systems which rely heavily on the network for their operation. When we first started running distributed experiments, it became immediately obvious that our networking wasn’t configured well. Directly between machines we got 10-15Gbit/s of throughput, but our Kube pods using Flannel were maxing out at ~2Gbit/s. Machine Zone’s public benchmarks show similar numbers, meaning the issue wasn’t likely to just be bad config, but instead something inherent to our environment. (By contrast, Flannel does not add this overhead on our physical machines.)
To work around this, users can add two different settings to disable Flannel for their pod: hostNetwork: true and dnsPolicy: ClusterFirstWithHostNet. (Though read the warnings in the Kubernetes documentation before doing this.)


## ARP Cache

Despite our DNS tuning, we still saw intermittent issues with DNS resolution. One day an engineer reported that nc -v to their Redis server was taking over 30 seconds to print that the connection was established. We tracked the issue to the kernel’s ARP stack. Initial investigation of the Redis pod’s host showed something seriously wrong with the network: communication on any port was hanging for multiple seconds, and no DNS names could be resolved via the local dnsmasq daemon, with dig just printing a cryptic failure message: socket.c:1915: internal_send: 127.0.0.1#53: Invalid argument. The dmesg log was more informative: neighbor table overflow! which meant that the ARP cache had run out of space. ARP is used for mapping a network address such as an IPv4 address, to a physical address, such as a MAC address. Fortunately, this was easy to fix by setting a few options in /etc/sysctl.conf:

```bash
net.ipv4.neigh.default.gc_thresh1 = 80000
net.ipv4.neigh.default.gc_thresh2 = 90000
net.ipv4.neigh.default.gc_thresh3 = 100000
```

It’s common to tune this setting in HPC clusters, and is particularly relevant in Kubernetes clusters since every pod has its own IP address which consumes space in the ARP cache.

Our Kubernetes clusters have been incident-free for about 3 months now, and we’re planning to scale to even larger clusters in 2018. We recently upgraded to version 1.8.4, and are excited to see that it now officially supports 5,000. If you’re interested in building large scale compute clusters.