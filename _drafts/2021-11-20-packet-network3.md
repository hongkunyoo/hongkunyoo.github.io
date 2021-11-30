---
layout: post
title:  "[번역]쿠버네티스 패킷의 삶 - #3"
date:   2021-11-15 00:00:00
categories: kubernetes network
image: /assets/images/packet-life/landing03.png
permalink: /:title
---
쿠버네티스 패킷의 삶 #3 시작합니다.

## 쿠버네티스 패킷의 삶 시리즈

1. [컨테이너 네트워킹과 CNI](/packet-network1): 리눅스 네트워크 namespace와 CNI 기초
2. [Calico CNI](/packet-network2): CNI 구현체 중 하나인, Calico CNI 네트워킹
3. Pod 네트워킹: Pod간, 클러스터 내/외부 네트워킹 설명
4. Ingress: Ingress Controller에 대한 설명

---

쿠버네티스 패킷의 삶 3번째 시리즈입니다. 이번 글에서는 `kube-proxy`가 어떻게 `iptables`를 이용하여 트래픽을 전달하는지 낱낱히 살펴 보는 시간을 가져 보겠습니다. 쿠버네티스 네트워킹을 이해하기 위해서 `kube-proxy`와 `iptables`의 역할을 잘 아는 것이 중요합니다.

참고: 트래픽을 컨트롤하는 플러그인/툴은 많이 있습니다만 이번 글에서는 주로 `kube-proxy` + `iptables` 조합에 대해서 설명 드립니다.

쿠버네티스에서 제공하는 다양한 커뮤니케이션 모델에 대해서 먼저 살펴 보겠습니다. 혹시 `Service`, `ClusterIP` 그리고 `NodePort`에 대한 내용을 이미 알고 있다면 바로 `kube-proxy`/`iptables` 셕센으로 넘어가길 바랍니다.

## Pod - Pod 통신

`kube-proxy`는 `Pod` to `Pod` 통신에는 관여하지 않습니다. CNI와 노드에서 `Pod` 통신간 필요한 라우팅 정보를 설정합니다. 모든 컨테이너는 NAT 없이 다른 컨테이너와 통신할 수 있습니다. 또한 모든 노드는 NAT 없이 모든 컨테이너와 통신할 수 있습니다.(반대로도 성립합니다.)

참고: `Pod`의 IP는 고정적이지 않습니다. (고정된 IP를 할당 받는 방법은 있지만 기본적으로는 고정 IP를 보장 받지 않습니다.) `Pod` 재시작 시, CNI는 새로운 IP를 해당 `Pod`에 할당합니다. 왜냐하면 CNI가 따로 IP와 `Pod` 간에 매핑 정보를 관리하지 않기 때문입니다. 또한 이미 알고 있듯이 `Deployment` 리소스를 사용하는 경우 `Pod` 이름 조차도 고정적이지 않습니다.

![](/assets/images/packet-life/03-01.png)

Practically, the Pods in a Deployment should use a Load-Balancer type of entity to expose the application as the app is stateless, and there will be more than one Pod hosting the application. Load-Balancer type of entity is called ‘Service’ in Kubernetes.

## Pod-to-external

For the traffic that goes from pod to external addresses, Kubernetes uses [SNAT](). What it does is replace the pod’s internal source IP:port with the host’s IP:port. When the return packet comes back to the host, it rewrites the pod’s IP:port as the destination and sends it back to the original pod. The whole process is transparent to the original pod, who doesn’t know the address translation.

## Pod-to-Service


### ClusterIP
Kubernetes has a concept called “service,” which is simply an L4 load balancer in front of pods. There are several different types of services. The most basic type is called ClusterIP. This type of service has a unique VIP address that is only routable inside the cluster.

It would not be easy to send traffic to a particular application using just pod IPs. The dynamic nature of a Kubernetes cluster means pods can be moved, restarted, upgraded, or scaled in and out of existence. Additionally, some services will have many replicas, so we need some way to load balance between them.

Kubernetes solves this problem with Services. A Service is an API object that maps a single virtual IP (VIP) to a set of pod IPs. Additionally, Kubernetes provides a DNS entry for each service’s name and virtual IP so that services can be easily addressed by name.

The mapping of virtual IPs to pod IPs within the cluster is coordinated by the kube-proxy process on each node. This process sets up either iptables or IPVS to automatically translate VIPs into pod IPs before sending the packet out to the cluster network. Individual connections are tracked, so packets can be properly de-translated when they return. IPVS and iptables can load balancing of a single service virtual IP into multiple pod IPs, though IPVS has much more flexibility in the load balancing algorithms it can use. Virtual IP doesn’t actually exist in the system interface; it lives in iptable.

![](/assets/images/packet-life/03-02.png)

> ‘Service’ definition from the Kubernetes document — An abstract way to expose an application running on a set of Pods as a network service. With Kubernetes you don’t need to modify your application to use an unfamiliar service discovery mechanism. Kubernetes gives Pods their own IP addresses and a single DNS name for a set of Pods, and can load-balance across them.

- FrontEnd Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  labels:
    app: webapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
```

- Backend Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth
  labels:
    app: auth
spec:
  replicas: 2
  selector:
    matchLabels:
      app: auth
  template:
    metadata:
      labels:
        app: auth
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
```

- Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  ports:
  - port: 80
    protocol: TCP
  type: ClusterIP
  selector:
    app: webapp
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  labels:
    app: backend
spec:
  ports:
  - port: 80
    protocol: TCP
  type: ClusterIP
  selector:
    app: auth
```

Now the FrontEnd Pod can connect to the backend via the ClusterIP or the DNS entry added by the Kubernetes. A cluster-aware DNS server, such as CoreDNS, watches the Kubernetes API for new Services and creates a set of DNS records for each one. If DNS has been enabled throughout your cluster, all Pods should automatically resolve Services by their DNS name.

![](/assets/images/packet-life/03-03.png)

### NodePort (External-to-Pod)

Now we have the DNS that can be used to communicate between the services in the cluster. However, the external requests can’t reach the service that lives inside the cluster as the IP address are virtual and Private.

Let’s try to reach the frontEnd Pod IP address from the external server. (Note: At this point, no service has been created for the FrontEnd service)

![](/assets/images/packet-life/03-04.png)

Can’t reach the Pod IP as it is a private IP address that can’t be routable.

Let’s create a NodePort service to expose the FrontEnd service to the external world. If you set the type field to NodePort, the Kubernetes control plane allocates a port from a range specified by --service-node-port-range flag (default: 30000-32767). Each node proxies that port (the same port number on every Node) into your Service. Your Service reports the allocated port in its `.spec.ports[*].nodePort` field.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: NodePort
  selector:
    app: webapp
  ports:
      # By default and for convenience, the `targetPort` is set to the same value as the `port` field.
    - port: 80
      targetPort: 80
      # Optional field
      # By default and for convenience, the Kubernetes control plane will allocate a port from a range (default: 30000-32767)
      nodePort: 31380
...
```

![](/assets/images/packet-life/03-05.png)

Now we can access the frontend service via `<anyClusterNode>:<nodePort>`. If you want a specific port number, you can specify a value in the nodePort field. The control plane will either allocate you that port or report that the API transaction failed. This means that you need to take care of possible port collisions yourself. You also have to use a valid port number, one that's inside the range configured for NodePort use.

## External Traffic Policy

> ExternalTrafficPolicy denotes if this Service desires to route external traffic to node-local or cluster-wide endpoints. “Local” preserves the client source IP and avoids a second hop for NodePort type services, but risks potentially imbalanced traffic spreading. “Cluster” obscures the client source IP and may cause a second hop to another node, but should have good overall load-balancing


### Cluster Traffic Policy

This is the default external traffic policy for Kubernetes Services. The assumption here is that you always want to route traffic to all pods (across all the nodes) running a service with equal distribution.

One of the caveats of using this policy is that you may see unnecessary network hops between nodes as you ingress external traffic. For example, if you receive external traffic via a NodePort, the NodePort SVC may (randomly) route traffic to a pod on another host when it could have routed traffic to a pod on the same host, avoiding that extra hop out to the network.

Packet flow in Cluster traffic policy is as follows,

- client sends the packet to node2:31380
- node2 replaces the source IP address (SNAT) in the packet with its own IP address
- node2 replaces the destination IP on the packet with the pod IP
- packet is routed to node 1 or 3, and then to the endpoint
- the pod’s reply is routed back to node2
- the pod’s reply is sent back to the client

![](/assets/images/packet-life/03-06.png)


### Local Traffic Policy

With this external traffic policy, kube-proxy will add proxy rules on a specific NodePort (30000–32767) only for pods that exist on the same node (local) instead of every pod for a service regardless of where it was placed.

You’ll notice that if you try to set externalTrafficPolicy: Local on your Service, the Kubernetes API will require you are using the LoadBalancer or NodePort type. This is because the “Local” external traffic policy is only relevant for external traffic, which only applies to those two types.

If you set service.spec.externalTrafficPolicy to the value Local, kube-proxy only proxies proxy requests to local endpoints and does not forward traffic to other nodes. This approach preserves the original source IP address. If there are no local endpoints, packets sent to the node are dropped, so you can rely on the correct source-ip in any packet processing rules you might apply a packet that makes it through to the endpoint.

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: NodePort
  externalTrafficPolicy: Local
  selector:
    app: webapp
  ports:
      # By default and for convenience, the `targetPort` is set to the same value as the `port` field.
    - port: 80
      targetPort: 80
      # Optional field
      # By default and for convenience, the Kubernetes control plane will allocate a port from a range (default: 30000-32767)
      nodePort: 31380
...
```

Packet flow in Local traffic policy as follows,

- client sends the packet to node1:31380, which does have endpoints
- node1 routes packet to the endpoint with the correct source IP
- node1 won’t route the packet to node3 as the policy is Local
- the client sends a packet to node2:31380, which doesn't have any endpoints
- packet is dropped

![](/assets/images/packet-life/03-07.png)

![](/assets/images/packet-life/03-08.png)

### Local traffic policy in LoadBalancer Service type

If you’re running on Google Kubernetes Engine/GCE, setting the same service.spec.externalTrafficPolicy field to Local forces nodes without Service endpoints to remove themselves from the list of nodes eligible for load-balanced traffic by deliberately failing health checks. So there won’t be any traffic drops. This model is great for applications that ingress a lot of external traffic and avoid unnecessary hops on the network to reduce latency. We can also preserve true client IPs since we no longer need SNAT traffic from a proxying node! However, the biggest downsides to using the “Local” external traffic policy, as mentioned in the Kubernetes docs, is that traffic to your application may be imbalanced.

![](/assets/images/packet-life/03-09.png)


## Kube-Proxy (iptable mode)

The component in Kubernetes that implements ‘Service’ is called kube-proxy. It sits on every node and programs complicated iptables rules to do all kinds of filtering and NAT between pods and services. If you go to a Kubernetes node and type iptables-save, you’ll see the rules inserted by Kubernetes or other programs. The most important chains are `KUBE-SERVICES`, `KUBE-SVC-*` and `KUBE-SEP-*`.

- `KUBE-SERVICES` is the entry point for service packets. What it does is that match the destination IP:port and dispatch the packet to the corresponding `KUBE-SVC-*` chain.
`KUBE-SVC-*` chain acts as a load balancer and distributes the packet to `KUBE-SEP-*chain` equally. Each `KUBE-SVC-*` has the same number of `KUBE-SEP-*` chains as the number of - endpoints behind it.
- `KUBE-SEP-*` chain represents a Service EndPoint. It simply does DNAT, replacing service IP:port with pod's endpoint IP:Port.

For DNAT, conntrack kicks in and tracks the connection state using a state machine. The state is needed because it needs to remember the destination address it changed to, and changed it back when the returning packet came back. Iptables could also rely on the conntrack state (ctstate) to decide the destiny of a packet. Those 4 conntrack states are especially important:

- `NEW`: conntrack knows nothing about this packet, which happens when the SYN packet is received.
- `ESTABLISHED`: conntrack knows the packet belongs to an established connection, which happens after the handshake is complete.
- `RELATED`: The packet doesn’t belong to any connection, but it is affiliated to another connection, which is especially useful for protocols like FTP.
- `INVALID`: Something is wrong with the packet, and conntrack doesn’t know how to deal with it. This state plays a centric role in this Kubernetes issue.

This is how the TCP connection works between pod and service; The sequence of events is:

- Client pod from the left-hand side sends a packet to a service: 2.2.2.10:80
- The packet is going through iptables rules in the client node, and the destination is changed to pod IP, 1.1.1.20:80
- Server pod handles the packet and sends back a packet with destination 1.1.1.10
- The packet is going back to the client node, conntrack recognizes the packet and rewrites the source address back to 2.2.2.10:80
- Client pod receives the response packet

GIF visualization:

![](/assets/images/packet-life/03-10.png)


## iptables

In the Linux operating system, the firewalling is taken care of using netfilter. Which is a kernel module that decides what packets are allowed to come in or to go outside.iptables are just the interface to netfilter. The two might often be thought of as the same thing. A better perspective would be to think of it as a backend (netfilter) and a frontend (iptables).

### chains

Each chain is responsible for a specific task,

- `PREROUTING`: This chain decides what happens to a packet as soon as it arrives at the network interface. We have different options, such as altering the packet (for NAT probably), dropping a packet, or doing nothing at all and letting it slip and be handled elsewhere along the way.
- `INPUT`: This is one of the popular chains as it almost always contains strict rules to avoid some evildoers on the internet harming our computer. If you want to open/block a port, this is where you’d do it.
- `FORWARD`: This chain is responsible for packet forwarding. Which is what the name suggests. We may want to treat a computer as a router, and this is where some rules might apply to do the job.
- `OUTPUT`: This chain is the one responsible for all your web browsing among many others. You can’t send a single packet without this chain allowing it. You have a lot of -  options, whether you want to allow a port to communicate or not. It’s the best place to limit your outbound traffic if you’re not sure what port each application is communicating through.
- `POSTROUTING`: This chain is where packets leave their trace last, before leaving our computer. This is used for routing among many other tasks just to make sure the packets are treated the way we want them to.

![](/assets/images/packet-life/03-11.png)


**FORWARD** chain only works if the ip_forward enabled in the Linux server, that’s the reason the following command is important while setting up and debugging the Kubernetes cluster.

```bash
node-1# sysctl -w net.ipv4.ip_forward=1
# net.ipv4.ip_forward = 1
node-1# cat /proc/sys/net/ipv4/ip_forward
# 1
```

The above change is not persistent. To permanently enable the IP forwarding on your Linux system, edit `/etc/sysctl.conf` and add the following line:

```bash
net.ipv4.ip_forward = 1
```


## tables

We are going to focus on the NAT table, but the following are the available tables.

- `Filter`: This is the default table. In this table, you would decide whether a packet is allowed in/out of your computer. If you want to block a port to stop receiving anything, this is your stop.
- `Nat`: This table is the second most popular table and is responsible for creating a new connection. Which is shorthand for Network Address Translation. And if you’re not - familiar with the term, don’t worry. I’ll give you an example below.
- `Mangle`: For specialized packets only. This table is for changing something inside the packet either before coming in or leaving out.
- `Raw`: This table is dealing with the raw packet, as the name suggests. Mainly this is for tracking the connection state. We’ll see examples of this below when we want to allow success packets from SSH connection.
- `Security`: It is responsible for securing your computer after the filter table. Which consists of SELinux. If you’re not familiar with the term, it’s a powerful security tool on modern Linux distributions.

> Please read THIS article for more detailed info on iptables.

## iptable configuration in Kubernetes

Let’s deploy an Nginx application with replica count two in minikube and dump the iptable rules.

ServiceType: `NodePort`

```bash
master# kubectl get svc webapp
NAME TYPE CLUSTER-IP EXTERNAL-IP PORT(S) AGE
webapp NodePort 10.103.46.104 <none> 80:31380/TCP 3d13h
master# kubectl get ep webapp 
NAME ENDPOINTS AGE
webapp 10.244.120.102:80,10.244.120.103:80 3d13h
master# 
```

The ClusterIP doesn’t exist anywhere, its a virtual IP exists in iptable Kubernetes adds a DNS entry in CoreDNS.

```bash
master# kubectl exec -i -t dnsutils -- nslookup webapp.default
# Server:  10.96.0.10
# Address: 10.96.0.10#53
# Name: webapp.default.svc.cluster.local
# Address: 10.103.46.104
```

To hook into packet filtering and NAT, Kubernetes will create a custom chain KUBE-SERVICES from iptables; it will redirect all PREROUTING AND OUTPUT traffic to custom chain KUBE-SERVICES, refer to below,

```bash
$ sudo iptables -t nat -L PREROUTING | column -t
Chain            PREROUTING  (policy  ACCEPT)                                                                    
target           prot        opt      source    destination                                                      
cali-PREROUTING  all         --       anywhere  anywhere     /*        cali:6gwbT8clXdHdC1b1  */                 
KUBE-SERVICES    all         --       anywhere  anywhere     /*        kubernetes             service   portals  */
DOCKER           all         --       anywhere  anywhere     ADDRTYPE  match                  dst-type  LOCAL
```

After using KUBE-SERVICES chain hook into packet filtering and NAT, Kubernetes can inspect traffics to its services and apply SNAT/DNAT accordingly. At the end of the KUBE-SERVICES chain, it will install another custom chain KUBE-NODEPORTS to handle traffics for a specific service type NodePort.

If the traffic is for ClusterIP, the KUBE-SVC-2IRACUALRELARSND chain will process the traffic; else, the next chain will process the traffic, that is KUBE-NODEPORTS.

```bash
$ sudo iptables -t nat -L KUBE-SERVICES | column -t
Chain                      KUBE-SERVICES  (2   references)                                                                                                                                                                             
target                     prot           opt  source          destination                                                                                                                                                             
KUBE-MARK-MASQ             tcp            --   !10.244.0.0/16  10.103.46.104   /*  default/webapp                   cluster  IP          */     tcp   dpt:www                                                                          
KUBE-SVC-2IRACUALRELARSND  tcp            --   anywhere        10.103.46.104   /*  default/webapp                   cluster  IP          */     tcp   dpt:www                                                                                                                                             
KUBE-NODEPORTS             all            --   anywhere        anywhere        /*  kubernetes                       service  nodeports;  NOTE:  this  must        be  the  last  rule  in  this  chain  */  ADDRTYPE  match  dst-type  LOCAL
```

Let’s check what the chains are part of KUBE-NODEPORTS,

```bash
$ sudo iptables -t nat -L KUBE-NODEPORTS | column -t
Chain                      KUBE-NODEPORTS  (1   references)                                            
target                     prot            opt  source       destination                               
KUBE-MARK-MASQ             tcp             --   anywhere     anywhere     /*  default/webapp  */  tcp  dpt:31380
KUBE-SVC-2IRACUALRELARSND  tcp             --   anywhere     anywhere     /*  default/webapp  */  tcp  dpt:31380
```

From this point, the processing is the same for ClusterIP and NodePort. Please take a look at the iptable flow diagram as follows.

```bash
# statistic  mode  random -> Random load-balancing between endpoints.
$ sudo iptables -t nat -L KUBE-SVC-2IRACUALRELARSND | column -t
Chain                      KUBE-SVC-2IRACUALRELARSND  (2   references)                                                                             
target                     prot                       opt  source       destination                                                                
KUBE-SEP-AO6KYGU752IZFEZ4  all                        --   anywhere     anywhere     /*  default/webapp  */  statistic  mode  random  probability  0.50000000000
KUBE-SEP-PJFBSHHDX4VZAOXM  all                        --   anywhere     anywhere     /*  default/webapp  */

$ sudo iptables -t nat -L KUBE-SEP-AO6KYGU752IZFEZ4 | column -t
Chain           KUBE-SEP-AO6KYGU752IZFEZ4  (1   references)                                               
target          prot                       opt  source          destination                               
KUBE-MARK-MASQ  all                        --   10.244.120.102  anywhere     /*  default/webapp  */       
DNAT            tcp                        --   anywhere        anywhere     /*  default/webapp  */  tcp  to:10.244.120.102:80

$ sudo iptables -t nat -L KUBE-SEP-PJFBSHHDX4VZAOXM | column -t
Chain           KUBE-SEP-PJFBSHHDX4VZAOXM  (1   references)                                               
target          prot                       opt  source          destination                               
KUBE-MARK-MASQ  all                        --   10.244.120.103  anywhere     /*  default/webapp  */       
DNAT            tcp                        --   anywhere        anywhere     /*  default/webapp  */  tcp  to:10.244.120.103:80

$ sudo iptables -t nat -L KUBE-MARK-MASQ | column -t
Chain   KUBE-MARK-MASQ  (24  references)                         
target  prot            opt  source       destination            
MARK    all             --   anywhere     anywhere     MARK  or  0x4000
```

Note: Trimmed the output to show only the required rules for readability.

### ClusterIP:

KUBE-SERVICES → KUBE-SVC-XXX → KUBE-SEP-XXX

### NodePort:

KUBE-SERVICES → KUBE-NODEPORTS → KUBE-SVC-XXX → KUBE-SEP-XXX

Note: The NodePort service will have a ClusterIP assigned to handle internal and external traffic.

Visual representation of above iptable rules,

![](/assets/images/packet-life/03-12.png)


### ExtrenalTrafficPolicy: Local

As discussed before, using “externalTrafficPolicy: Local” will preserve source IP and drop packets from the agent node has no local endpoint. Let’s take a look at the iptable rules in the node with no local endpoint.

```bash
master # kubectl get nodes
# NAME           STATUS   ROLES    AGE    VERSION
# minikube       Ready    master   6d1h   v1.19.2
# minikube-m02   Ready    <none>   85m    v1.19.2
```

Deploy Nginx with externalTrafficPolicy Local.

```bash
master # kubectl get pods nginx-deployment-7759cc5c66-p45tz -o wide
# NAME                                READY   STATUS    RESTARTS   AGE   IP               NODE       NOMINATED NODE   READINESS GATES
# nginx-deployment-7759cc5c66-p45tz   1/1     Running   0          29m   10.244.120.111   minikube   <none>           <none>
```

Check externalTrafficPolicy,

```bash
master # kubectl get svc webapp -o wide -o jsonpath={.spec.externalTrafficPolicy}
# Local
```

Get the service,

```bash
master # kubectl get svc webapp -o wide
NAME     TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE   SELECTOR
webapp   NodePort   10.111.243.62   <none>        80:30080/TCP   29m   app=webserver
```

Let’s check the iptable rules in node minikube-m02; there should be a DROP rule to drop the packets as there is no local endpoint.

```bash
$ sudo iptables -t nat -L KUBE-NODEPORTS
# Chain KUBE-NODEPORTS (1 references)
# target prot opt source destination
# KUBE-MARK-MASQ tcp — 127.0.0.0/8 anywhere /* default/webapp */ tcp dpt:30080
# KUBE-XLB-2IRACUALRELARSND tcp — anywhere anywhere /* default/webapp */ tcp dpt:30080
```

Check KUBE-XLB-2IRACUALRELARSND chain,

```bash
$ sudo iptables -t nat -L KUBE-XLB-2IRACUALRELARSND
Chain KUBE-XLB-2IRACUALRELARSND (1 references)
target prot opt source destination
KUBE-SVC-2IRACUALRELARSND all — 10.244.0.0/16 anywhere /* Redirect pods trying to reach external loadbalancer VIP to clusterIP */
KUBE-MARK-MASQ all — anywhere anywhere /* masquerade LOCAL traffic for default/webapp LB IP */ ADDRTYPE match src-type LOCAL
KUBE-SVC-2IRACUALRELARSND all — anywhere anywhere /* route LOCAL traffic for default/webapp LB IP to service chain */ ADDRTYPE match src-type LOCAL
KUBE-MARK-DROP all — anywhere anywhere /* default/webapp has no local endpoints */
```

If you take a closer look, there is no issue with the Cluster level traffic; only the nodePort traffic will be dropped on this node.

‘minikube’ node iptable rules,

```bash
$ sudo iptables -t nat -L KUBE-NODEPORTS
Chain KUBE-NODEPORTS (1 references)
target prot opt source destination
KUBE-MARK-MASQ tcp — 127.0.0.0/8 anywhere /* default/webapp */ tcp dpt:30080
KUBE-XLB-2IRACUALRELARSND tcp — anywhere anywhere /* default/webapp */ tcp dpt:30080
$ sudo iptables -t nat -L KUBE-XLB-2IRACUALRELARSND
Chain KUBE-XLB-2IRACUALRELARSND (1 references)
target prot opt source destination
KUBE-SVC-2IRACUALRELARSND all — 10.244.0.0/16 anywhere /* Redirect pods trying to reach external loadbalancer VIP to clusterIP */
KUBE-MARK-MASQ all — anywhere anywhere /* masquerade LOCAL traffic for default/webapp LB IP */ ADDRTYPE match src-type LOCAL
KUBE-SVC-2IRACUALRELARSND all — anywhere anywhere /* route LOCAL traffic for default/webapp LB IP to service chain */ ADDRTYPE match src-type LOCAL
KUBE-SEP-5T4S2ILYSXWY3R2J all — anywhere anywhere /* Balancing rule 0 for default/webapp */
$ sudo iptables -t nat -L KUBE-SVC-2IRACUALRELARSND
Chain KUBE-SVC-2IRACUALRELARSND (3 references)
target prot opt source destination
KUBE-SEP-5T4S2ILYSXWY3R2J all — anywhere anywhere /* default/webapp */
```

## Headless Services

-Copied from Kubernetes documentation-

Sometimes you don’t need load-balancing and a single service IP. In this case, you can create what is termed “headless” Services by explicitly specifying "None" for the cluster IP (.spec.clusterIP).

You can use a headless Service to interface with other service discovery mechanisms without being tied to Kubernetes’ implementation.

For headless Services, a cluster IP is not allocated, kube-proxy does not handle these Services, and there is no load balancing or proxying done by the platform. How DNS is automatically configured depends on whether the Service has selectors defined:

### With selectors

For headless services that define selectors, the endpoints controller creates Endpoints records in the API, and modifies the DNS configuration to return records (addresses) that point directly to the Pods backing the Service.

```bash
master # kubectl get svc webapp-hs
NAME        TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
webapp-hs   ClusterIP   None         <none>        80/TCP    24s
master # kubectl get ep webapp-hs
NAME        ENDPOINTS                             AGE
webapp-hs   10.244.120.109:80,10.244.120.110:80   31s
```

### Without selectors

For headless services that do not define selectors, the endpoints controller does not create Endpoints records. However, the DNS system looks for and configures either:

- CNAME records for ExternalName-type Services.
- A records for any Endpoints that share a name with the Service for all other types.

If there are external IPs that route to one or more cluster nodes, Kubernetes Services can be exposed on those externalIPs. Traffic that ingresses into the cluster with the external IP (as the destination IP) on the Service port will be routed to one of the Service endpoints. externalIPsare not managed by Kubernetes and are the responsibility of the cluster administrator.


## Network Policy

By now, you might have got an idea of how the network policy is implemented in Kubernetes. Yes, the iptables again; this time, the CNI takes care of implementing the network policy, not the kube-proxy. This section should have been added to the Calico (Part 2); however, I feel this is the right place to have the network policy details.

Let’s create three services — frontend, backend, and db.

By default, pods are non-isolated; they accept traffic from any source.

![](/assets/images/packet-life/03-13.png)

However, there should be a traffic policy to isolate the DB pods from the FrontEnd pods to avoid any traffic flow between them.

![](/assets/images/packet-life/03-14.png)

I would suggest you read THIS article to understand the Network Policy configuration. This section will focus on how the network policy is implemented in Kubernetes instead of configuration deep dive.

I have applied a network policy to isolate db from the frontend pods; this results in no connection between the frontend and db pods.

Note: Above picture shows the ‘service’ symbol instead of the ‘pod’ symbol to make life easier as there can be many pods in a given service. But, the actual rules are applied per Pod.

```bash
master # kubectl exec -it frontend-8b474f47-zdqdv -- /bin/sh
# curl backend
backend-867fd6dff-mjf92
# curl db
curl: (7) Failed to connect to db port 80: Connection timed out
```

However, the backend can reach the db service without any issue.


```bash
master # kubectl exec -it backend-867fd6dff-mjf92 -- /bin/sh
# curl db
db-8d66ff5f7-bp6kf
```

Let’s take a look at the NetworkPolicy — Allow ingress from the service if it has a label ‘allow-db-access’ set to ‘true.’


```yaml
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-db-access
spec:
  podSelector:
    matchLabels:
      app: "db"
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          networking/allow-db-access: "true"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  labels:
    app: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
        networking/allow-db-access: "true"
    spec:
      volumes:
      - name: workdir
        emptyDir: {}
      containers:
      - name: nginx
        image: nginx:1.14.2
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
        volumeMounts:
        - name: workdir
          mountPath: /usr/share/nginx/html
      initContainers:
      - name: install
        image: busybox
        imagePullPolicy: IfNotPresent
        command: ['sh', '-c', "echo $HOSTNAME > /work-dir/index.html"]
        volumeMounts:
        - name: workdir
          mountPath: "/work-dir"
...
```

Calico converts the Kubernetes network policy into Calico’s native format,

```bash
master # calicoctl get networkPolicy --output yaml
apiVersion: projectcalico.org/v3
items:
- apiVersion: projectcalico.org/v3
  kind: NetworkPolicy
  metadata:
    creationTimestamp: "2020-11-05T05:26:27Z"
    name: knp.default.allow-db-access
    namespace: default
    resourceVersion: /53872
    uid: 1b3eb093-b1a8-4429-a77d-a9a054a6ae90
  spec:
    ingress:
    - action: Allow
      destination: {}
      source:
        selector: projectcalico.org/orchestrator == 'k8s' && networking/allow-db-access
          == 'true'
    order: 1000
    selector: projectcalico.org/orchestrator == 'k8s' && app == 'db'
    types:
    - Ingress
kind: NetworkPolicyList
metadata:
  resourceVersion: 56821/56821
```

The iptables rule plays an important role in enforcing the policy by using the ‘filter’ table. It’s hard to do reverse engineering as the Calico uses advanced concepts like ipset. From the iptables rules, I see that the packets are allowed to db pod only if the packets are from the backend, and that’s exactly our network policy is.

Get the workload endpoint details from the calicoctl.

```bash
master # calicoctl get workloadEndpoint
WORKLOAD                         NODE       NETWORKS        INTERFACE         
backend-867fd6dff-mjf92          minikube   10.88.0.27/32   cali2b1490aa46a   
db-8d66ff5f7-bp6kf               minikube   10.88.0.26/32   cali95aa86cbb2a   
frontend-8b474f47-zdqdv          minikube   10.88.0.24/32   cali505cfbeac50
```

cali95aa86cbb2a — Host side end of veth pair that is in use by db pod.

Let’s get the iptables rules related to this interface.

```bash
$ sudo iptables-save | grep cali95aa86cbb2a
:cali-fw-cali95aa86cbb2a - [0:0]
:cali-tw-cali95aa86cbb2a - [0:0]
-A cali-from-wl-dispatch -i cali95aa86cbb2a -m comment --comment "cali:R489GtivXlno-SCP" -g cali-fw-cali95aa86cbb2a
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:3XN24uu3MS3PMvfM" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:xyfc0rlfldUi6JAS" -m conntrack --ctstate INVALID -j DROP
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:wG4_76ot8e_QgXek" -j MARK --set-xmark 0x0/0x10000
-A cali-fw-cali95aa86cbb2a -p udp -m comment --comment "cali:Ze6pH1ZM5N1pe76G" -m comment --comment "Drop VXLAN encapped packets originating in pods" -m multiport --dports 4789 -j DROP
-A cali-fw-cali95aa86cbb2a -p ipencap -m comment --comment "cali:3bjax7tRUEJ2Uzew" -m comment --comment "Drop IPinIP encapped packets originating in pods" -j DROP
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:0pCFB_VsKq1qUOGl" -j cali-pro-kns.default
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:mbgUOxlInVlwb2Ie" -m comment --comment "Return if profile accepted" -m mark --mark 0x10000/0x10000 -j RETURN
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:I7GVOQegh6Wd9EMv" -j cali-pro-ksa.default.default
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:g5ViWVLiyVrKX91C" -m comment --comment "Return if profile accepted" -m mark --mark 0x10000/0x10000 -j RETURN
-A cali-fw-cali95aa86cbb2a -m comment --comment "cali:RBmQDo38EoPmxJ0I" -m comment --comment "Drop if no profiles matched" -j DROP
-A cali-to-wl-dispatch -o cali95aa86cbb2a -m comment --comment "cali:v3sEoNToLYUOg7M6" -g cali-tw-cali95aa86cbb2a
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:eCrqwxNk3cKw9Eq6" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:_krp5nzavhAu5avJ" -m conntrack --ctstate INVALID -j DROP
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:Cu-tVtfKKu413YTT" -j MARK --set-xmark 0x0/0x10000
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:leBL64hpAXM9y4nk" -m comment --comment "Start of policies" -j MARK --set-xmark 0x0/0x20000
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:pm-LK-c1ra31tRwz" -m mark --mark 0x0/0x20000 -j cali-pi-_tTE-E7yY40ogArNVgKt
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:q_zG8dAujKUIBe0Q" -m comment --comment "Return if policy accepted" -m mark --mark 0x10000/0x10000 -j RETURN
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:FUDVBYh1Yr6tVRgq" -m comment --comment "Drop if no policies passed packet" -m mark --mark 0x0/0x20000 -j DROP
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:X19Z-Pa0qidaNsMH" -j cali-pri-kns.default
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:Ljj0xNidsduxDGUb" -m comment --comment "Return if profile accepted" -m mark --mark 0x10000/0x10000 -j RETURN
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:0z9RRvvZI9Gud0Wv" -j cali-pri-ksa.default.default
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:pNCpK-SOYelSULC1" -m comment --comment "Return if profile accepted" -m mark --mark 0x10000/0x10000 -j RETURN
-A cali-tw-cali95aa86cbb2a -m comment --comment "cali:sMkvrxvxj13WlTMK" -m comment --comment "Drop if no profiles matched" -j DROP
$ sudo iptables-save -t filter | grep cali-pi-_tTE-E7yY40ogArNVgKt
:cali-pi-_tTE-E7yY40ogArNVgKt - [0:0]
-A cali-pi-_tTE-E7yY40ogArNVgKt -m comment --comment "cali:M4Und37HGrw6jUk8" -m set --match-set cali40s:LrVD8vMIGQDyv8Y7sPFB1Ge src -j MARK --set-xmark 0x10000/0x10000
-A cali-pi-_tTE-E7yY40ogArNVgKt -m comment --comment "cali:sEnlfZagUFRSPRoe" -m mark --mark 0x10000/0x10000 -j RETURN
```

By checking the ipset, it is clear that the ingress to db pod allowed only from the backend pod IP 10.88.0.27

```bash
[root@minikube /]# ipset list
Name: cali40s:LrVD8vMIGQDyv8Y7sPFB1Ge
Type: hash:net
Revision: 6
Header: family inet hashsize 1024 maxelem 1048576
Size in memory: 408
References: 3
Number of entries: 1
Members:
10.88.0.27
```

I’ll update Part 2 of this series with more detailed steps to decode the calico iptables rules.

## References:

- https://kubernetes.io
- https://www.projectcalico.org/
- https://rancher.com/ 
- http://www.netfilter.org/


## 마치며








