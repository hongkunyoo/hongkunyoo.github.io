---
layout: post
title:  "Custom HPA 만들기"
date:   2021-10-27 00:00:00
categories: kubernetes hpa
image: /assets/images/sealedsecret/landing.png
permalink: /:title
---
GitOps

GitOps에서 Secret 관리가 고민이시라구요? 그래서 준비했습니다, SealedSecret!


쿠버네티스 Secret은 

![](/assets/images/sealedsecret/landing.png)


https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/
https://kubernetes.io/docs/concepts/configuration/secret/#security-properties
https://cloudkul.com/blog/data-encryption-at-rest-and-in-transit-protect-your-data/
https://www.sealpath.com/blog/protecting-the-three-states-of-data/


- Data at Rest: 데이터가 저장 되었을 때
- Data in Transit: 데이터가 전송 중일 때
- Data in Use: 데이터를 사용할 때

