---
layout: post
title:  "AWS Batch를 이용한 분산 병렬 딥러닝 학습 #3"
description: "개별 host에서 학습한 모델 파일을 효율적으로 관리할 수 있는 방법에 대해 알아보겠습니다."
date:   2018-05-19 16:21:00
categories: deep-learning AWS Batch docker
---
개별 host에서 학습한 모델 파일을 통합적으로 관리할 수 있는 방법에 대해 알아보겠습니다.

#### 현재 문제점
현재 각 서버에서 병렬로 학습을 실행 시키기 때문에 학습된 모델들이 각각의 서버에 생성됩니다. 그렇기 때문에 학습된 모델들을 이용하기 위해서는 개별 서버에 접속하여 모델 학습 결과들을 확인하거나 직접 한 곳으로 옮겨줘야합니다. host 서버가 적을 때는 조금만 수고하면 그리 어렵지 않게 각 서버들을 순회하며 결과 파일을 한 곳으로 옮길 수 있습니다.
혹은 ssh remote command를 사용하거나 ansible과 같은 툴을 이용하면 조금 더 편리하게 학습 결과를 한 곳으로 옮길 수 있습니다.
하지만 매번 학습 결과에 대해서 추가적인 작업을 할 필요 없이 자동적으로 한 곳으로 모이게는 할 수 없을까요?

---

#### 제안
애초부터 원격 저장소를 학습 서버에 직접 마운트 시켜서 학습 결과가 생성되는 즉시 중앙 저장소로 모이게하는 건 어떨까요? 바로 NAS서버를 이용하여 각 서버에 Network File System으로 마운트하는 방법이 되겠습니다. 이를 통해 학습 서버에서는 기존과 마찬가지로 마치 로컬 디렉토리에 파일을 저장하는 것처럼 보이나 실제로는 원격 저장소로 모델 파일들일 모이게 됩니다. 방법도 그리 어렵지 않습니다.
![](/assets/images/volume_driver/efs.png)

---

#### How to?
원격 저장소로 AWS에서 제공하는 NAS 서비스인 EFS를 사용하도록 하겠습니다.
AWS에서 이미 EFS를 ECS의 스토리지로 활용할 수 있게 가이드를 제공하고 있습니다.
해당 문서를 참고하셔도 좋습니다.
[Amazon ECS에 Amazon EFS 파일 시스템 사용](https://docs.aws.amazon.com/ko_kr/AmazonECS/latest/developerguide/using_efs.html)

##### AWS EFS 서비스 생성
가장 먼저 EFS 서비스를 생성해야 합니다.
AWS > Storage > EFS 서비스에 들어가셔서
1. Create file system 버튼을 클릭합니다.
2. 속할 VPC와 subnet을 선택합니다. (특별히 세팅을 안하면 default VPC 선택), Next 클릭
- Performance mode
	- General purpose: 기본 성능 모드, latency가 중요한 경우
	- Max I/O: 많은 머신이 동신에 접속해야 할 경우, latency가 약간 높다고 함.
- Throughput mode
	- Bursting: 기본 throughput 모드
	- Provisioned: provisioned 모드, EFS 같은 경우 저장된 용량에 따라 throughput이 결정되는데 작은 용량의 파일이 여러개 있을 경우, 느려지는 현상이 있는데 이럴 경우 throughput을 provision 시켜 처리량을 일정 수준 유지 시켜줄 수 있습니다.

performance에 관한 더 자세한 사항은 [AWS 공식 문서](https://docs.aws.amazon.com/efs/latest/ug/performance.html)를 참고.

##### 학습 서버에 EFS 연결
이제 만들어진 NAS 서버를 학습 서버에 mount 시켜 보겠습니다.
1. 학습 서버에 ssh 접속을 합니다.
2. EFS를 mount 시킬 디렉토리를 /efs 라는 이름으로 만듭니다.
	`sudo mkdir /efs`
3. NFS client 소프트웨어를 설치합니다.
	- CentOS / Amazon Linux: `sudo yum install -y nfs-utils`
	(참고: ECS 전용 instance는 Amazon Linux를 base로 합니다)
	- Ubuntu: `sudo apt-get install -y nfs-common`
4. /efs에 EFS를 마운트 시킵니다.
아래의 명령어에서 `${REPLACE_HERE}` 부분을 EFS 서비스의 DNS name으로 바꿔서 실행하시기 바랍니다.
`sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 ${REPLACE_HERE}:/ /efs`


sshfs volume driver를 학습 환경으로 사용할 instance에 설치합니다. `docker plugin install vieux/sshfs`
6. volume을 새롭게 생성합니다. 이때 sshfs volume driver를 이용하여 중앙 저장소의 /opt/host에 매핑 시켜줍니다.
volume의 이름을 sshvolume이라고 짓습니다.
`docker volume create -d vieux/sshfs -o sshcmd={user}@{host}:/opt/host sshvolume`
7. 새롭게 job definition을 만들겠습니다. 기존과 설정이 동일하나 volume을 새롭게 연결해 보겠습니다. 이름은 미리 정한대로 sshvolume이라 하고 `source path`는 `/storage/`와 연결하겠습니다.<br/>
> 자세한 설치 및 설정 방법은 [docker-volume-sshfs](https://github.com/vieux/docker-volume-sshfs)에 잘 나와있습니다.

8. 모델 저장 방식을 제안한 대로 수정합니다. `train_model.py`
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
    ```

9. (optional) 새로운 instance를 생성할 때마다 sshfs volume driver를 설치할 필요 없이 AMI로 만들어서 관리하면 편리합니다.

모든 것이 완료되었습니다. 이제 Job submit을 통해 제대로 저장이 되는지 확인
