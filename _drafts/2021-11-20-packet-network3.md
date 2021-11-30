---
layout: post
title:  "[번역]쿠버네티스 패킷의 삶 - #3"
date:   2021-11-15 00:00:00
categories: kubernetes network
image: /assets/images/packet-life/landing03.png
permalink: /:title
---
[쿠버네티스 패킷의 삶 #1](/packet-network1)에서 살펴 봤듯이, CNI plugin은 쿠버네티스 네트워킹에서 중요한 역할을 차지합니다. 현재 많은 CNI plugin 구현체들이 존재합니다. 그 중 Calico를 소개합니다. 많은 엔지니어들은 Calico를 선호합니다. 그 이유는 Calico는 네트워크 구성을 간단하게 만들어 주기 때문입니다.

## 쿠버네티스 패킷의 삶 시리즈

1. [컨테이너 네트워킹과 CNI](/packet-network1): 리눅스 네트워크 namespace와 CNI 기초
2. Calico CNI: CNI 구현체 중 하나인, Calico CNI 네트워킹
3. Pod 네트워킹: Pod간, 클러스터 내/외부 네트워킹 설명
4. Ingress: Ingress Controller에 대한 설명

---


This is part 3 of the series on Life of a Packet in Kubernetes. We’ll be tackling how Kubernetes’s kube-proxy component uses iptables to control the traffic. It’s important to know the role of kube-proxy in Kubernetes environment and how it uses iptables to control the traffic.

Note: There are many other plugins/tools to control the traffic flow, but in this article will look at the kube-proxy + iptables combo.

We’ll start with various communication models provided by Kubernetes and their implementation. If you are already aware of the magic words ‘Service, ClusterIP and NodePort’ concept, please jump to the kube-proxy/iptables section.