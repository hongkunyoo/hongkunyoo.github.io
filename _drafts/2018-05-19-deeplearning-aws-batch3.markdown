---
layout: post
title:  "AWS Batch를 이용한 분산 병렬 딥러닝 학습 #3"
description: "개별 host에서 학습한 모델 파일을 효율적으로 관리할 수 있는 방법에 대해 알아보겠습니다."
date:   2018-05-19 16:21:00
categories: deep-learning AWS Batch docker
---
개별 host에서 학습한 모델 파일을 효율적으로 관리할 수 있는 방법에 대해 알아보겠습니다.

#### 현재 문제점
개별 host 서버에 접속하여 모델 학습 결과들을 확인해야 합니다. host 서버가 적을 때는 조금만 수고하면 그리 어렵지 않게 각 host를 순회하며 결과 파일을 한 곳으로 옮길 수 있습니다.
혹은 ssh의 remote command를 사용한다던지 ansible과 같은 툴을 이용하면 조금 더 편리하게 결과 파일을 관리할 수 있을 것입니다.
하지만 매번 학습 결과에 대해서 추가적인 작업을 할 필요 없이 자동적으로 한 곳으로 모이게는 할 수 없을까요?

---

#### 제안
Docker volume driver를 활용해 보는 것은 어떨까요? 도커에는 각 feature마다 driver 인터페이스를 열어 놓아 custom plugin을 할 수 있게 열어 놓았습니다. (log driver, volume driver 등)
제가 제안하는 방법은, volume driver 중에 [docker-volume-sshfs](https://github.com/vieux/docker-volume-sshfs) 라는 오픈소스 plugin이 있습니다. sshfs을 통해 remote에 있는 파일 시스템을 마운트해주는 plugin입니다.
이를 통해 volume을 연결 시키면 컨테이너 내부의 프로세스에서는 로직의 변경 없이 기존대로 모델 파일을 생성 시, 자연스럽게 remote에 있는 중앙 저장소에 파일이 생성됩니다.
이렇게 되면 더 이상 각 host의 모델 파일에 대해 고민할 필요 없이 한 곳에서 모델을 관리, 평가, 저장할 수 있게 됩니다.
![](/assets/images/volume_driver/volume_driver.png)

---

#### How to?
직접 어떻게 설정하면 되는지 같이 살펴보겠습니다.
1. 중앙 저장소로 활용할 instance를 하나 생성하고 /opt/host 라는 디렉토리를 만들어줍니다.
`mkdir -p /opt/host`
2. sshfs volume driver를 학습 환경으로 사용할 instance에 설치합니다. `docker plugin install vieux/sshfs`
3. volume을 새롭게 생성합니다. 이때 sshfs volume driver를 이용하여 중앙 저장소의 /opt/host에 매핑 시켜줍니다.
volume의 이름을 sshvolume이라고 짓습니다.
`docker volume create -d vieux/sshfs -o sshcmd={user}@{host}:/opt/host sshvolume`
4. 새롭게 job definition을 만들겠습니다. 기존과 설정이 동일하나 volume을 새롭게 연결해 보겠습니다. 이름은 미리 정한대로 sshvolume이라 하고 `source path`는 `/storage/`와 연결하겠습니다.<br/>
> 자세한 설치 및 설정 방법은 [docker-volume-sshfs](https://github.com/vieux/docker-volume-sshfs)에 잘 나와있습니다.

5. 모델 저장 방식을 제안한 대로 수정합니다. `train_model.py`
```python
s3 = boto3.resource('s3')
s3.Bucket(BUCKET_NAME).download_file(KEY, 'hyperparam_list.yml')
index = int(os.environ['AWS_BATCH_JOB_ARRAY_INDEX'])
with open(KEY) as f:
    hyperparam_list = yaml.load(f)
    paramset = hyperparam_list[index]
    print(paramset)
    model = build_model(paramset)
    model_path = '/storage/%s/model/' % index    # 기존, 'model_%s.h5' % index
    os.makedirs(model_path, exist_ok=True)       # 새롭게 추가
    model_path = os.path.join(model_path, 'model.h5')
    train(model, paramset, model_path)
```

6. (optional) 새로운 instance를 생성할 때마다 sshfs volume driver를 설치할 필요 없이 AMI로 만들어서 관리하면 편리합니다.

모든 것이 완료되었습니다. 이제 Job submit을 통해 제대로 저장이 되는지 확인해 보겠습니다.
