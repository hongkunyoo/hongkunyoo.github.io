---
layout: post
title:  "[번역] 쿠버네티스 7,500개 노드 운영하기"
date:   2021-05-11 00:00:00
categories: kubernetes scale
image: /assets/images/scalenode/landing.png
permalink: /:title
---
지난 포스트 ["[번역] 쿠버네티스 2,500대 노드 운영하기"](/scaling-node01)에 이어 OpenAI에서 7,500대의 노드를 운영한 경험을 공유한 글을 번역하였습니다.

저희는 GPT-3, CLIP 그리고 DALL·E와 같은 큰 모델을 학습 시키기 위해 7,500대의 노드로 쿠버네티스 클러스터를 확장하였습니다. 뿐만 아니라 [Scaling Laws for Neural Language Models](https://arxiv.org/abs/2001.08361) 처럼 작은 규모의 리서치도 지원하였습니다. 단일 클러스터로 이 정도 규모까지 노드를 확장 시킨 일은 흔하지 않고 특별한 설정이 필요합니다. 하지만 그 장점으로는 인프라가 간단해 지고 ML팀이 특별한 코드 수정 없이 빠르게 대규모 기계학습을 수행할 수 있게 해줍니다.

![](/assets/images/scalenode/01.png)

지난 포스트 2,500대 노드 운영하기에 이어 리서처들의 오구사항을 만족하기 위해 인프라를 지속적으로 늘려왔고 이를 통해 많은 교훈들을 얻을 수 있었습니다. 이번 포스트를 통해 쿠버네티스 커뮤니티의 많은 사람들에게 도움이 되었으면 좋겠고 현재 저희가 가진 문제들을 같이 고민해 보는 시간을 가졌으면 좋겠습니다.

## Our workload

글을 이어가지 전에 우리가 하는 작업을 설명하는 것이 좋을 것 같습니다. 저희가 쿠버네티스 위에서 운영하는 어플리케이션과 하드웨어는 일반적인 회사와는 조금 다른 부분이 있습니다. 저희가 직면했던 문제와 그 해결책이 다른 회사에서 동일하게 적용될지는 모르겠습니다.

큰 기계학습 작업은 각 노드의 모든 하드웨어 자원을 사용할 수 있을 때에 가장 효율적으로 동작할 수 있습니다. 이것은 NVLink를 통한 GPU의 노드간 통신을 가능하게 하거나 GPU가 GPUDirect을 통해 직접적으로 네트워크 인터페이스와 통신하게 해줍니다. 지금까지 대부분은 한개 `Pod`가 노드 전체를 선점하는 방식으로 실행되어 왔습니다. NUMA, CPU나 PCIE 자원이 스케줄링의 중요한 기준이 되지 않았습니다. Bin-packing이나 fragmentation은 일반적이지 않은 문제입니다. 현재 저희 클러스터는 모든 노드 간 bandwidth이 동일하기 때문에(full bisection bandwidth) 노드의 랙 위치나 네트워크 토폴로지에 대해서는 고려하지 않습니다. 이러한 이유로 저희가 많은 수의 노드를 운영하더라도 비교적 스케줄러에는 부담이 적습니다.

이것은 `kube-scheduler`의 부하가 한번씩 튄다는(spiky) 것을 말합니다. 예를 들어, 한번씩 새로운 작업을 시작할 때 수백개의 `Pod`가 한번에 생성되고 그 이후로는 비교적 낮은 부하를 유지합니다.(역자주: 기계학습 프로세스의 특징이죠.)

![](/assets/images/scalenode/02.png)



Our biggest jobs run MPI, and all pods within the job are participating in a single MPI communicator. If any of the participating pods die, the entire job halts and needs to be restarted. The job checkpoints regularly, and when restarted it resumes from the last checkpoint. Thus we consider the pods to be semi-stateful—killed pods can be replaced and work can continue, but doing so is disruptive and should be kept to a minimum.

We don’t rely on Kubernetes load balancing all that much. We have very little HTTPS traffic, with no need for A/B testing, blue/green, or canaries. Pods communicate directly with one another on their pod IP addresses with MPI via SSH, not service endpoints. Service “discovery” is limited; we just do a one-time lookup for which pods are participating in MPI at job startup time.

Most jobs interact with some form of blob storage. They usually either stream some shards of a dataset or checkpoint directly from blob storage, or cache it to a fast local ephemeral disk. We have a few PersistentVolumes for cases where POSIX semantics are useful, but blob storage is far more scalable and doesn’t require slow detach/attach operations.

Lastly, the nature of our work is fundamentally research, which means the workloads themselves are ever-changing. While the Supercomputing team strives to provide what we’d consider a “production” quality level of compute infrastructure, the applications that run on that cluster are short-lived and their developers iterate quickly. New usage patterns may emerge at any time that challenge our assumptions about trends and appropriate tradeoffs. We need a sustainable system that also allows us to respond quickly when things change.

## Networking


As the number of nodes and pods within our clusters increased, we found that Flannel had difficulties scaling up the throughput required. We switched to using the native pod networking technologies for our IP Configurations for Azure VMSSes and the relevant CNI plugins. This allowed us to get host level network throughput on our pods.

Another reason we’ve switched to using alias-based IP addressing is that on our largest clusters, we could possibly have approximately 200,000 IP addresses in use at any one time. When we tested route-based pod networking, we found there were significant limitations in the number of routes we could effectively use.

Avoiding encapsulation increases the demands on the underlying SDN or routing engine, but it keeps our networking setup simple. Adding VPN or tunneling can be done without any additional adapters. We don’t need to worry about packet fragmentation due to some portion of the network having a lower MTU. Network policies and traffic monitoring is straightforward; there’s no ambiguity about the source and destination of packets.

We use iptables tagging on the host to track network resource usage per Namespace and pod. This lets researchers visualize their network usage patterns. In particular, since a lot of our experiments have distinct Internet and intra-pod communication patterns, it’s often useful to be able to investigate where any bottlenecks might be occurring.

iptables mangle rules can be used to arbitrarily mark packets that match particular criteria. Here are our rules to detect whether traffic is internal or internet-bound. The FORWARD rules cover traffic from pods, vs INPUT and OUTPUT traffic from the host:

```bash
iptables -t mangle -A INPUT ! -s 10.0.0.0/8 -m comment --comment "iptables-exporter openai traffic=internet-in"
iptables -t mangle -A FORWARD ! -s 10.0.0.0/8 -m comment --comment "iptables-exporter openai traffic=internet-in"
iptables -t mangle -A OUTPUT ! -d 10.0.0.0/8 -m comment --comment "iptables-exporter openai traffic=internet-out"
iptables -t mangle -A FORWARD ! -d 10.0.0.0/8 -m comment --comment "iptables-exporter openai traffic=internet-out"
```

Once marked, iptables will start counters to track the number of bytes and packets that match this rule. You can eyeball these counters by using iptables itself:

```bash
iptables -t mangle -L -v
# Chain FORWARD (policy ACCEPT 50M packets, 334G bytes)
#  pkts bytes target     prot opt in     out     source               destination
# ....
# 1253K  555M            all  --  any    any     anywhere            !10.0.0.0/8           /* iptables-exporter openai traffic=internet-out */
# 1161K 7937M            all  --  any    any    !10.0.0.0/8           anywhere             /* iptables-exporter openai traffic=internet-in */
```

We use an open-source Prometheus exporter called iptables-exporter to then get these tracked into our monitoring system. This a simple way to track packets matching a variety of different types of conditions.

![](/assets/images/scalenode/03.png)

One somewhat unique aspect of our network model is that we fully expose the node, pod, and service network CIDR ranges to our researchers. We have a hub and spoke network model, and use the native node and pod CIDR ranges to route that traffic. Researchers connect to the hub, and from there have access to any of the individual clusters (the spokes). But the clusters themselves cannot talk to one another. This ensures that clusters remain isolated with no cross-cluster dependencies that can break failure isolation.

We use a “NAT” host to translate the service network CIDR range for traffic coming from outside of the cluster. This setup allows our researchers significant flexibility in choosing how and what kinds of network configurations they are able to choose from for their experiments.

## API Servers

Kubernetes API Servers and etcd are critical components to a healthy working cluster, so we pay special attention to the stress on these systems. We use the Grafana dashboards provided by kube-prometheus, as well as additional in-house dashboards. We’ve found it useful to alert on the rate of HTTP status 429 (Too Many Requests) and 5xx (Server Error) on the API Servers as a high-level signal of problems.

![](/assets/images/scalenode/04.png)


While some folks run API Servers within kube, we’ve always run them outside the cluster itself. Both etcd and API servers run on their own dedicated nodes. Our largest clusters run 5 API servers and 5 etcd nodes to spread the load and minimize impact if one were to ever go down. We’ve had no notable trouble with etcd since splitting out Kubernetes Events into their own etcd cluster back in our last blog post. API Servers are stateless and generally easy to run in a self-healing instance group or scaleset. We haven’t yet tried to build any self-healing automation of etcd clusters because incidents have been extremely rare.

API Servers can take up a fair bit of memory, and that tends to scale linearly with the number of nodes in the cluster. For our cluster with 7,500 nodes we observe up to 70GB of heap being used per API Server, so fortunately this should continue to be well-within hardware capabilities into the future.

![](/assets/images/scalenode/05.png)

One big strain on API Servers was WATCHes on Endpoints. There are a few services, such as ‘kubelet’ and ‘node-exporter’ of which every node in the cluster is a member. When a node would be added or removed from the cluster, this WATCH would fire. And because typically each node itself was watching the kubelet service via kube-proxy, the # and bandwidth required in these responses would be N^2N 2 and enormous, occasionally 1GB/s or more. EndpointSlices, launched in Kubernetes 1.17, were a huge benefit that brought this load down 1000x.

![](/assets/images/scalenode/06.png)

In general we are very mindful of any API Server requests that scale with the size of the cluster. We try to avoid having any DaemonSets interact with the API Server. In cases where you do need each node to watch for changes, introducing an intermediary caching service, such as the Datadog Cluster Agent, seems to be a good pattern to avoid cluster-wide bottlenecks.

As our clusters have grown, we do less actual autoscaling of our clusters. But we have run into trouble occasionally when autoscaling too much at once. There are many requests generated when a new node joins a cluster, and adding hundreds of nodes at once can overload API server capacity. Smoothing this out, even just by a few seconds, has helped avoid outages.

## Time-series metrics with Prometheus and Grafana


We use Prometheus to collect time-series metrics and Grafana for graphs, dashboards, and alerts. We started with a deployment of kube-prometheus that collects a wide variety of metrics and good dashboards for visualization. Over time we’ve added many of our own dashboards, metrics, and alerts.

As we added more and more nodes, we struggled with the sheer amount of metrics being collected by Prometheus. While kube-prometheus exposes a lot of useful data, some of it we weren’t actually ever looking at, and some was just too granular to collect, store, and query effectively. We use Prometheus rules to “drop” some of these metrics from being ingested.

For a while we struggled with a problem where Prometheus would consume more and more memory until eventually crashing the container in an Out-Of-Memory error (OOM). This seemed to occur even after throwing enormous amounts of memory capacity at the application. What’s worse was, when it did crash, it would take many hours on startup replaying write-ahead-log files before it was usable again.

Eventually we tracked down the source of these OOMs to be an interaction between Grafana and Prometheus, where Grafana would use the /api/v1/series API on Prometheus with a query of {le!=""} (Basically, “give me all the histogram metrics”). The implementation of /api/v1/series was unbounded in both time and space—for a query with a lot of results, this would continue to consume ever-more memory and time. It also continues to grow even after the requester has given up and closed the connection. For us, there was never enough memory, and Prometheus would eventually crash. We patched Prometheus to contain this API within a Context to enforce a timeout, which fixed it entirely.

While Prometheus crashed far less often, in times when we did need to restart it, WAL replay remained an issue. It would often take many hours to replay through all WAL logs before Prometheus was up collecting new metrics and servicing queries. With help from Robust Perception, we found that applying a GOMAXPROCS=24 had a big improvement. Prometheus tries to use all cores when during WAL replay, and for servers with a large number of cores, the contention kills all performance.

We’re exploring new options to increase our monitoring capacity, described in the “Unsolved problems” section below.

## Healthchecks


With a cluster this large, we of course rely on automation to detect and remove misbehaving nodes from the cluster. Over time we have built up a number of healthcheck systems.

### Passive healthchecks

Some healthchecks are passive, always running on all nodes. These monitor basic system resources such as network reachability, bad or full disks, or GPU errors. GPUs exhibit problems a number of different ways, but an easy common one is an “Uncorrectable ECC error.” Nvidia’s Data Center GPU Manager (DCGM) tools make it easy to query for this and a number of other “Xid” errors. One way we track these errors is via dcgm-exporter to ingest the metrics into Prometheus, our monitoring system. This will appear as the DCGM_FI_DEV_XID_ERRORS metric and be set to the error code that has most recently occurred. Additionally, the NVML Device Query API exposes more detailed information about the health and operation of a GPU.

Once we detect an error, they can often be fixed by resetting the GPU or system, though in some cases it does lead to the underlying GPU needing to be physically replaced.

Another form of healthcheck tracks maintenance events from the upstream cloud provider. Each of the major cloud providers expose a way to know if the current VM is due for an upcoming maintenance event that will eventually cause a disruption. The VM may need to be rebooted so an underlying hypervisor patch can be applied or the physical node swapped out for other hardware.

These passive healthchecks run constantly in the background on all nodes. If a healthcheck starts failing, the node is automatically cordoned so no new pods are to be scheduled on the node. For more serious healthcheck failures, we will also attempt a pod eviction to request all currently-running pods to exit immediately. It’s still up to the pod itself, configurable via a Pod Disruption Budget, to decide if it wants to allow this eviction to occur. Eventually, either after all pods have terminated, or 7 days has elapsed (part of our SLA), we will forcibly terminate the VM.

### Active GPU tests

Unfortunately not all GPU problems manifest as error codes visible through DCGM. We’ve built up our own library of tests that exercise GPUs to catch additional problems and ensure that the hardware and driver is behaving as expected. These tests can’t be run in the background—they require exclusive use of a GPU for several seconds or minutes to run.

We first run these tests on nodes upon boot, in a system we call “preflight.” All nodes join the cluster with a “preflight” taint and label applied. This taint prevents normal pods from being scheduled on the node. A DaemonSet is configured to run preflight test pods on all nodes with this label. Upon successful completion of the test, the test itself removes the taint and label and the node is then available for general use.

We also then run these tests periodically during the lifetime of a node. We run this as a CronJob, allowing it to land on any available node in the cluster. This is admittedly a bit random and uncontrolled about which nodes get tested, but we’ve found that over time it provides sufficient coverage with minimal coordination or disruption.

## Quotas & resource usage

As we scaled up our clusters, researchers started to find themselves having difficulty getting all of the capacity that they were allocated. Traditional job scheduling systems have a lot of different features available to fairly run work between competing teams, which Kubernetes does not have. Over time, we took inspiration from those job scheduling systems and build several capabilities in a Kubernetes-native way.

### Team taints
We have a service in each cluster, “team-resource-manager” that has multiple functions. Its data source is a ConfigMap that specifies tuples of (node selector, team label to apply, allocation amount) for all of the research teams that have capacity in a given cluster. It reconciles this with the current nodes in the cluster, tainting the appropriate number of nodes with openai.com/team=teamname:NoSchedule.

“team-resource-manager” also has an admission webhook service, such that as each job is submitted, a corresponding toleration is applied based on the submitter’s team membership. Using taints allows us to constrain the Kubernetes pod scheduler flexibly, such as allowing a “any” toleration for lower priority pods, which allows teams to borrow each other’s capacity without requiring heavyweight coordination.

### CPU & GPU balloons
In addition to using cluster-autoscaler to dynamically scale our VM-backed clusters, we use it to remediate (remove & re-add) unhealthy members within the cluster. We do this by setting the “min size” of the cluster to zero, and the “max size” of the cluster to the capacity available. However, cluster-autoscaler, if it sees idle nodes, will attempt to scale down to only needed capacity. For multiple reasons (VM spin up latency, pre-allocated costs, the API server impacts mentioned above) this idle-scaling isn’t ideal.

So, we introduced a balloon Deployment for both our CPU-only and GPU hosts. This Deployment contains a ReplicaSet with “max size” number of low-priority pods. These pods occupy resources within a node, so the autoscaler doesn’t consider them as idle. However since they’re low priority, the scheduler can evict them immediately to make room for actual work. (We chose to use a Deployment instead of a DaemonSet, to avoid the DaemonSet being considered idle workload on a node.)

One thing of note, we use pod anti-affinity to ensure the pods would evenly distribute across the nodes. Earlier versions of the Kubernetes scheduler had an O(N^2)O(N 2) performance issue with pod anti-affinity. This has been corrected since Kubernetes 1.18.

## Gang scheduling

Our experiments often involve one or more StatefulSets, each operating a different portion of the training effort. For Optimizers, researchers need all members of the StatefulSet to be scheduled, before any training can be done (as we often use MPI to coordinate between optimizer members, and MPI is sensitive to group membership changes).

However, Kubernetes by default won’t necessarily prioritize fulfilling all requests from one StatefulSet over another. For example if two experiments each requested 100% of the cluster’s capacity, instead of scheduling all of one experiment or the other, Kubernetes might schedule only half of each experiment’s pods, leading to a deadlock where neither experiment can make progress.

We tried a few things needing a custom scheduler, but ran into edge cases that caused conflicts with how normal pods were scheduled. Kubernetes 1.18 introduced a plugin architecture for the core Kubernetes scheduler, making it much easier to add features like this natively. We recently landed on the Coscheduling plugin as a good way to solve this problem.

## Unsolved problems

There are many problems still to address as we scale up our Kubernetes clusters. A few of them include:

### Metrics

At our scale we’ve had many difficulties with Prometheus’s built-in TSDB storage engine being slow to compact, and needing long times needed to replay the WAL (Write-Ahead-Log) any time it restarts. Queries also tend to result in “query processing would load too many samples” errors. We’re in the process of migrating to a different Prometheus-compatible storage and query engine. Look forward to a future blog post about how it goes!

### Pod network traffic shaping

As we scale up our clusters, each pod is calculated to have a certain amount of Internet bandwidth available. The aggregate Internet bandwidth requirements per person have become substantial, and our researchers now have the ability to unintentionally put a significant resource strain on other locations on the Internet, such as datasets for download and software packages to install.

## Conclusions

We’ve found Kubernetes to be an exceptionally flexible platform for our research needs. It has the ability to scale up to meet the most demanding workloads we’ve put on it. There are many areas yet though where it needs improvement, and the Supercomputing team at OpenAI will continue to explore how Kubernetes can scale. If this kind of work seems interesting, you should consider applying at OpenAI!

