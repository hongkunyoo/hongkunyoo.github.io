---
layout: post
title:  "[번역]쿠버네티스는 단순히 컨테이너를 관리하는 툴이 아닙니다."
date:   2022-03-14 00:00:00
categories: kubernetes network
image: /assets/images/k8s-api.jpeg
permalink: /:title
---
나름 조회수가 잘 나왔던 저의 블로그 글 중 하나인 [쿠버네티스 API서버는 정말 그냥 API서버라구욧](https://coffeewhale.com/apiserver)에서 쿠버네티스 API 서버가 일반적인 API 서버와 크게 다르지 않다는 점을 강조한 내용으로 글을 작성하였었습니다. 이와 연관되어 쿠버네티스의 API가 가지는 중요성에 대해 [잘 소개한 글](https://blog.joshgav.com/posts/kubernetes-isnt-about-containers)이 있어서 번역해 보았습니다.

---

쿠버네티스는 API에 관한 것입니다. 그 이유에 대해 짧게 설명해 보겠습니다.

## 최초에 컨테이너가 존재하였습니다.

도커는 컨테이너를 위해 만들어졌습니다. 2013년, 복잡한 postgres 명령을 간단한 도커 명령으로 쉽게 프로그램을 실행할 수 있는 점은 많은 개발자들에게 혁신과 같았습니다. 그들이 그동안 잘 알지 못했던 애자일한 DevOps에 눈을 뜨기 시작한 것이였죠. 그리고 기쁘게도 점점 더 많은 개발자들이 도커를 빌드 & 운영 표준으로 채택함에 따라 단순히 한 컴퓨터에서만 잘 되는 것이 아니라 여러 클러스터 시스템에서도 똑같이 잘 동작한다는 사실을 깨닫기 시작했습니다. 그리고 이것은 쿠버네티스, 아파치 메소스와 같은 제품들을 나오게 만들었죠. 이들 제품은 주로 컨테이너가 가장 중요한 부분을 차지합니다. 하지만 제목에서 알 수 있듯이 쿠버네티스의 가장 큰 의의는 컨테이너를 잘 실행 시키는 것에 있지 않습니다.

또한 쿠버네티스를 어떠한 프로세스도 다 잘 실행 시킬 수 있는 general workload [스케줄러](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/)라고도 정의할 수 없습니다. 물론 다양한 워크로드를 효율적으로 스케줄링 할 수 있는 능력은 쿠버네티스의 중요한 기능 중 하나이지만 이것 하나만으로는 쿠버네티스의 성공을 말할 수 없습니다.

## 그리고 API가 나왔습니다.

쿠버네티스가 성공할 수 있었던 가장 큰 이유는 소프트웨어 정의 인프라(컴퓨팅, 네트워킹, 스토리지 등, 쉽게 말해서 클라우드 서비스)서비스를 이용할 때 표준화된 프로그래밍 인터페이스를 제공했다는 점입니다. 쿠버네티스는 여러가지 모양과 크기의 워크로드들을 동일한 구조와 표현방법(YAML)으로 소프트웨어를 설계 & 구현하고 운영할 수 있게, 명세(spec)와 구현(implement)이 포함된 완벽한 프레임워크를 제공하였습니다. 바로 선언형으로 정의된 리소스와 그것을 관리하는 컨트롤러로 말이죠.

쿠버네티스 이전의 상황을 생각해 볼까요? 각기 다른 클라우드에서 제공하는 다양한 API들과 그것을 표현하는 방법 그리고 사용 패턴들이 전부 달랐습니다. 하나의 클라우드 플랫폼에서 컴퓨팅 엔진, 블록 스토리지, 네트워크와 object 스토리지를 구성하였더라도 또 다른 클라우드에서 동일한 작업을 다른 방식으로 구성했어야만 했습니다. 그래서 Terraform과 같은 제품이 이러한 차이점을 극복하고자 나오기도 하였습니다. 하지만 여전히 근본적인 구조는 각기 달랐기 때문에 AWS를 타게팅한 Terraform의 구조로 Azure에서 그대로 사용할 수 없었습니다.

반대로 쿠버네티스가 처음부터 제공한 가치가 무엇인지를 생각해 봅시다:

- Pod라는 객체를 통해 컴퓨팅 자원을 표준화 하였습니다.
- Service와 Ingress를 통해 가상 네트워킹을 표준화 하였습니다.
- Persistent Volume을 통해 스토리지를, Service Account를 통해 실행 주체(Identity)를 표준화 하였습니다.

각 객체의 표현방법과 규약은 다양한 배포판(EKS, AKS, GKE, on-prem 등)에서 동일하게 동작합니다. 내부적으로는 자기들만의 클라우드 API를 제각각 사용하지만(implementation) 외부적으로는 전부 동일한 표준(specification)을 지킵니다. (역자주: AWS에서 `LoadBalancer` 타입 `Service`를 생성하면 ELB가 하나 생성되고 GCP에서는 Network Load Balancer가 생성됩니다.)

쿠버네티스는 소프트웨어로 정의된 인프라를 표준 인터페이스로 사용할 수 있게 제공합니다. 다시 말해, 클라우드 서비스들의 표준 API가 된 것입니다.

## 그리고 더 많은 API들이 나오기 시작하였습니다.

잘 정의되고 표준화된 API들을 제공한 것이 쿠버네티스 성공의 핵심이 되었습니다. 이것에 끝나지 않고 쿠버네티스는 어떠한 인프라 리소스도 사용할 수 있게 확장 가능합니다. [Custom Resource Definitions](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) (`CRD`)라는 리소스가 쿠버네티스 1.7 버전에 나왔습니다. 이것을 통해 사용자가 정의한 리소스도 쿠버네티스의 시스템에서 활용할 수 있게 되었습니다. `CRD`를 이용하면 단순히 쿠버네티스에 미리 정의된 API(computing, network, storage 등)뿐만 아니라 database, 배치 작업, 메세지 버스, 디지털 인증서 등, 상상할 수 있는 모든 리소스를 표준화하여 사용할 수 있습니다.

점점 더 많은 서비스 제공자들이 CRD를 통해 다양한 서비스들을 제공하려는 움직임이 많아짐에 따라, [Operator Framework](https://operatorframework.io/)와 [SIG API Machinery](https://github.com/kubernetes/community/tree/master/sig-api-machinery)와 같은 프로젝트들이 최소한의 노력으로 최대한의 결과를 내기 위해 합쳐지게 되었습니다. 또한 [Crossplane](https://crossplane.io)와 같이, 쿠버네티스 API를 다양한 리소스들(RDS, SQS 등)과 매핑 시키는 작업을 수행하는 프로젝트도 생겨나기 시작하였습니다. 그리고 Google과 Red Hat과 같은 쿠버네티스 배포판에서는 점점 더 자신들의 리소스를 쿠버네티스 API로 제공하기 시작하였습니다.

이 모든 것은 쿠버네티스 API가 완벽하다는 것을 말할려고 하는 것이 아닙니다. 단지 이미 사실상 표준(de facto standard)이 되었기 때문에 그것과는 상관 없이 많은 곳에서 사용된다는 것입니다. 많은 개발자들이 사용할 줄 알고 많은 툴들이 지원하며 많은 클라우드 업체들이 제공합니다. 비록 단점도 존재하지만 이미 많은 곳에서 사용하기에 그 단점을 상쇄시킵니다.

쿠버네티스 리소스 모델이 점점 더 퍼져감에 따라 이미 컴퓨팅 환경을 전부 쿠버네티스 리소스로 표현하는 것이 가능해졌습니다. 간단한 프로그램을 `docker run`을 통해 손쉽게 실행할 수 있듯이, `kubectl apply -f`를 이용하여 분산 어플리케이션을 손쉽게 배포할 수 있게 되었습니다. 그리고 많은 클라우드 제공자가 쿠버네티스를 지원하기 때문에 더 많은 곳에서 쿠버네티스 API가 잘 동작하게 될 것입니다.

쿠버네티스는 단순히 컨테이너를 잘 관리하는 툴이 아닙니다. 쿠버네티스는 API에 관한 것입니다.

---

## 마치며

쿠버네티스가 리소스의 표현방식을 표준화하고 더 나아가 클라우드 서비스들의 API를 표준화한 점은 정말 대단한 일이었습니다. 다양한 쿠버네티스 생태계 프로젝트가 풍성하게 생겨날 수 있는 이유가 되었죠.
쿠버네티스의 장점과 가능성은 무궁무진한 것 같습니다. 여러분이 생각하시는 쿠버네티스의 장점과 성공원인은 무엇이라 생각하시나요?