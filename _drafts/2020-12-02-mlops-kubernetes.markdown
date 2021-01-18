---
layout: post
title:  "[번역]데이터 과학자들은 쿠버네티스에 관심이 없습니다"
date:   2020-07-15 00:00:00
categories: kubernetes gitops helm
image: /assets/images/?
---

Data Scientists dont care about Kubernetes

https://determined.ai/blog/data-scientists-dont-care-about-kubernetes


이 글은 다음 포스트를 읽고 비슷한 고민을

쿠버네티스는 지난 몇 십년간 나온 제품들 중 가장 중요한 소프트웨어이자 영향력있는 오픈소스입니다. 쿠버네티스는 어플리케이션이 어떻게 개발되고 운영환경에 배포가 되어야 하는지에 대해 혁신적인 변화를 이끌어 냈습니다.

쿠버네티스의 폭발적인 성장으로 더 많은 하드웨어가 쿠버네티스에 의해 관리되어 집니다. 이 흐름은 딥러닝의 인기에 맞물려 같이 성장하고 있습니다. 딥러닝은 엄청 나게 많은 컴퓨팅 연산이 필요로 하는 기술로 데이터 과학자 한명이 여러 GPU 머신을 오랜 기간동안 차지합니다. 이러한 특징으로 인해 다음과 같은 개발 방법론들이 나타나기 시작했습니다.

**쿠버네티스에 의해 하드웨어들이 관리되는 분석 도구들이 나타났습니다.**

이로인해 데이터 과학자들이 더 많은 하드웨어를 손쉽게 접근할 수 있기에 훌륭한 방법입니다. 단지 한가지 문제가 있습니다.

**이러한 툴들은 데이터 과학자로 하여금 쿠버네티스를 이해 해야지만 사용할 수 있게 만들어졌습니다.**

비슷하게 들릴지 모르지만 그렇지 않습니다. 더 많은 하드웨어에 접근할 수 있게 하는 것은 좋지만 반드시 쿠버네티스를 이해 해야지만 사용할 수 있게 만드는 것은 좋지 못합니다. **쿠버네티스는 개발자들에 의해, 개발자들을 위해 만들어졌습니다.**

![](https://determined.ai/assets/images/blogs/kubernetes-bad/kubeflow-unicorns.png)

당신이 만약 유니콘이라면 축하드립니다! 당신의 능력으로 쿠버네티스와 딥러닝 기술을 합쳐서 멋진 무언가를 만드시길 바랍니다. 그 외 다른 사람들은 (대부분의 사람들이 여기에 해당 되죠.) ML 모델을 개발하지도 전에 컴퓨터 공학 스킬을 배워야 한다는 사실에 꽤나 귀찮게 생각할 수 있습니다. 하지만 다행인 것은 이러한 문제를 해결할 수 있다는 점입니다. 단지 분석 도구들을 개발자들을 위해서 만드는 것이 아니라 데이터 과학자들을 위해 만들면 됩니다.


## ML 도구들의 문제

Let’s take a quick look at Kubeflow to understand what I mean about data science tools that are built for software engineers. Kubeflow started as an adaptation of how Google was running TensorFlow internally, as a tool that allowed TensorFlow to run on Kubernetes. This technology was very impactful, creating a much simpler way to use hardware managed by Kubernetes to do deep learning.

That initial version of Kubeflow is now the Kubeflow component called TFJob. Without TFJob, running TensorFlow on Kubernetes would be miserable — you would need to specify a complex topology of containers, networking, and storage before you could even start writing your ML code. With TFJob, this is simplified, but, crucially, it is not nearly simple enough. To use TFJob, you need to:

**Wrap your ML code up neatly in a container.** This will be a clunky experience that will require you to package your code and upload it if you want to make changes. Docker is great, but this will slow down your development cycle significantly.

**Write a Kubernetes TFJob manifest.** This might not sound that intimidating, but for a data scientist not fluent in Kubernetes it can be a daunting task. To do this well, you’ll need to learn a lot about Kubernetes — a far cry from the Python that these scientists are used to. Let’s look at the most simple version of this, from the Kubeflow docs:





