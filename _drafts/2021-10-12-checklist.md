---
layout: post
title:  "[번역]쿠버네티스 위에 프로덕션 레벨의 웹앱을 배포하기 위한 체크리스트"
date:   2021-10-12 00:00:00
categories: kubernetes checklist
image: /assets/images/scalenode/landing.png
permalink: /:title
---
PRODUCTION CHECKLIST FOR WEB APPS ON KUBERNETES

---

https://srcco.de/posts/web-service-on-kubernetes-production-checklist-2019.html


어플리케이션을 릴리즈 환경에서 운영하는 것은 쉽지 않은 일입니다. 이 포스트는 웹서비스(HTTP API)를 쿠버네티스 위에 운영환경으로 올리기 위한 나름의 체크리스트를 제안합니다.
이 체크리스트는 저희 Zalando사에서의 일부 제한된 경험을 바탕으로 나왔습니다. 그렇기 때문에 자신의 각 환경의 참고용 체크리스트로 활용하시기 바랍니다. 상황에 따라서 어떤 항목은 선택 가능하거나(optional) 현실에 적용하기 힘들 수도 있습니다.

### General

- 어플리케이션 이름, 설명, 목적, 팀이 명확히 문서화 되었는가 (위키 페이지 등)
- 어플리케이션의 중요도가 정의되었는가 (예를 들어, 비즈니스에 영향이 크다면 1th tier)
- 개발팀이 충분한 기술스택에 대한 이해가 있는가
- 24/7 온콜(on-call) 조직이 만들어졌는가
- 롤백 가능한 백업 플랜이 있는가

### 어플리케이션

- 코드 저장소(git)에 어플리케이션을 어떻게 개발하고 설정하고 변경하는지 명확하게 설명이 되어있는가
- 코드 버전들이 고정되어 있는가
- 모든 관련 코드들이 OpenTracking과 OpenTelemtry에 측정되는가
- OpenTracing/OpenTelemetry 시멘틱이 컨벤션을 따르는가
- 모든 outbound 요청 HTTP API는 timeout이 정의가 되어있는가
- HTTP 커넥션 풀이 트래픽 양에 맞춰 적절하게 설정되어 있는가
- 쓰레드 풀과 non-blocking async 코드가 적절하게 구현되어 있는가
- DB 풀이 적절하게 설정되어 있는가
- retry, 재시작 정책이 종속된 서비스에 적용되어 있는가
- 서킷 브레이커가 구축되어 있는가
- 비즈니스 요구사항에 맞게 서킷 브레이커 fallback이 구현되어 있는가
- 부하분산 / rate limit 메커니즘이 구현되어 있는가
- 모니터링을 위해 어플리케이션 메트릭이 노출되어 있는가 (Prometheus scrapping)
- 어플리케이션 로그 포맷이 정의되어 있는가
- 에러에 대해서 어플리케이션이 명시적으로 죽는가
- 동료들에 의해 코드가 리뷰되었는가


### 보안 & 컴플라이언스

- 어플리케이션이 non-root 유저로 동작하는가
- 컨테이너에 writable file system이 필요하지는 않는가
- HTTP 요청에 대해 AuthN & AuthZ이 되고 있는가
- DOS 공격에 대해 완화할 수 있는 메커니즘이 설계되어 있는가
- 보안 auditing이 수행되고 있는가
- 코드 & 패키지에 대해 자동 취약점 검사가 수행되고 있는가
- 처리된 데이터가 분류되고 문서화되고 있는가
- 위협 모델이 존재하고 리스크가 문서화 되는가
- 다른 조직의 컴플라이언스 규칙을 잘 따르고 있는가

### CI/CD

- 코드 변화에 대해 lint가 자동으로 수행되고 있는가
- 배포 과정에서 자동 테스트가 이루어지고 있는가
- 운영 배포에 사람이 개입하는 경우가 있는가
- 관련된 모든 팀 멤버가 배포하고 롤백할 수 있는가
- 운영에 배포된 어플리케이션에 대해 스모크 테스트가 존재하며 자동 롤백이 되는가


- Automated code linting is run on every change
- Automated tests are part of the delivery pipeline
- No manual operations are needed for production deployments
- All relevant team members can deploy and rollback
- Production deployments have smoke tests and optionally automatic rollbacks
- Lead time from code commit to production is fast (e.g. 15 minutes or less including test runs)

### Kubernetes
- Development team is trained in Kubernetes topics and knows relevant concepts
- Kubernetes manifests use the latest API version (e.g. apps/v1 for Deployment)
- Container runs as non-root and uses a read-only filesystem
- A proper Readiness Probe was defined, see blog post about Readiness/Liveness Probes
- No Liveness Probe is used, or there is a clear rationale to use a Liveness Probe, see blog post about Readiness/Liveness Probes
- Kubernetes deployment has at least two replicas
- A Pod Disruption Budget was defined (or is automatically created, e.g. by pdb-controller)
- Horizontal autoscaling (HPA) is configured if adequate
- Memory and CPU requests are set according to performance/load tests
- Memory limit equals memory requests (to avoid memory overcommit)
- CPU limits are not set or impact of CPU throttling is well understood
- Application is correctly configured for the container environment (e.g. JVM heap, single-threaded runtimes, runtimes not container-aware)
- Single application process runs per container
- Application can handle graceful shutdown and rolling updates without disruptions, see this blog post
- Pod Lifecycle Hook (e.g. "sleep 20" in preStop) is used if the application does not handle graceful termination
- All required Pod labels are set (e.g. Zalando uses "application", "component", "environment")
- Application is set up for high availability: pods are spread across failure domains (AZs, default behavior for cross-AZ clusters) and/or application is deployed to multiple clusters
- Kubernetes Service uses the right label selector for pods (e.g. not only matches the "application" label, but also "component" and "environment" for future extensibility)
- There are no anti-affinity rules defined, unless really required (pods are spread across failure domains by default)
- Optional: Tolerations are used as needed (e.g. to bind pods to a specific node pool)

See also this curated checklist of Kubernetes production best practices.

### Monitoring
- Metrics for The Four Golden Signals are collected
- Application metrics are collected (e.g. via Prometheus scraping)
- Backing data store (e.g. PostgreSQL database) is monitored
- SLOs are defined
- Monitoring dashboards (e.g. Grafana) exist (could be automatically set up)
- Alerting rules are defined based on impact, not potential causes

### Testing
- Breaking points were tested (system/chaos test)
- Load test was performed which reflects the expected traffic pattern
- Backup and restore of the data store (e.g. PostgreSQL database) was tested

### 24/7 On-Call
- All relevant 24/7 personnel is informed about the go-live (e.g. other teams, SREs, or other roles like incident commanders)
- 24/7 on-call team has sufficient knowledge about the application and business context
- 24/7 on-call team has necessary production access (e.g. kubectl, kube-web-view, application logs)
- 24/7 on-call team has expertise to troubleshoot production issues with the tech stack (e.g. JVM)
- 24/7 on-call team is trained and confident to perform standard operations (scale up, rollback, ..)
- Runbooks are defined for application-specific incident handling
- Runbooks for overload scenarios have pre-approved business decisions (e.g. what customer feature to disable to reduce load)
- Monitoring alerts to page the 24/7 on-call team are set up
- Automatic escalation rules are in place (e.g. page next level after 10 minutes without acknowledgement)
- Process for conducting postmortems and disseminating incident learnings exists
- Regular application/operational reviews are conducted (e.g. looking at SLO breaches)

Anything missing on this list? Do you disagree with something? Ping me on Twitter!