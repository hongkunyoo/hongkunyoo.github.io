---
layout: post
title:  "AWS Batch를 이용한 분산 병렬 딥러닝 학습 #2"
date:   2018-05-18 16:21:00
categories: deep-learning AWS Batch docker
---

지난번 포스트에서 AWS Batch가 어떤 서비스인지에 대해 알아봤습니다. 이번에는 실제 코드와 함께 어떻게 분산 병렬 학습을 할 수 있을지에 대해 알아봅시다.

먼저 hyper parameter를 이용하여 모델을 만드는 간단한 코드부터 시작하겠습니다.
```python
from __future__ import print_function

import keras
from keras.datasets import mnist
from keras.models import Sequential
from keras.layers import Dense, Dropout
from keras.optimizers import RMSprop
from keras.callbacks import ModelCheckpoint

NUM_CLASSES = 10

def build_model(paramset):
    # Hyper parameter setting
    batch_size = paramset['batch_size']
    epochs = paramset['epochs']
    hidden_nodes = paramset['hidden_nodes']
    dropout_rate = paramset['dropout_rate']
    activate_fn = paramset['activate_fn']
    optimizer = paramset['optimizer']
    model_path = paramset['model_path']

    # building model
    model = Sequential()
    model.add(Dense(512, activation='relu', input_shape=(784,)))
    for hidden_node in hidden_nodes:
        model.add(Dropout(dropout_rate))
        model.add(Dense(hidden_node, activation=activate_fn))
    model.add(Dropout(0.2))
    model.add(Dense(NUM_CLASSES, activation='softmax'))

    model.summary()
    model.compile(loss='categorical_crossentropy',
                  optimizer=optimizer,
                  metrics=['accuracy'])
    return model


paramset = {}
paramset['batch_size'] = 128
paramset['epochs'] = 20
paramset['hidden_nodes'] = [10, 20, 30]
paramset['dropout_rate'] = 0.5
paramset['activate_fn'] = 'relu'
paramset['optimizer'] = 'rmsprop'
model_path = 'model.h5'

model = build_model(paramset)
train(model, paramset, model_path)
```

이제 paramset을 이용하여 다양한 모델을 만들 수 있게 되었습니다. 그럼 다음으로 S3에서 hyper parameter들을 가져올 수 있게 만들어 보겠습니다.

```yaml
# hyperparam_list.yml
- batch_size: 128
  epochs: 20
  hidden_nodes: [10, 20, 30]
  dropout_rate: 0.2
  activate_fn: relu
  optimizer: rmsprop

- batch_size: 128
  epochs: 20
  hidden_nodes: [30, 50, 70]
  dropout_rate: 0.7
  activate_fn: tanh
  optimizer: rmsprop
```


```python
import boto3
import yaml
import os

BUCKET_NAME = 'my_bucket'
KEY = 'hyperparam_list.yml'

s3 = boto3.resource('s3')
s3.Bucket(BUCKET_NAME).download_file(KEY, 'hyperparam_list.yml')
index = int(os.environ['AWS_BATCH_JOB_ARRAY_INDEX'])
with open(KEY) as f:
    hyperparam_list = yaml.load(f)
    paramset = hyperparam_list[index]
    print(paramset)
    model = build_model(paramset)
    model_path = 'model_%s.h5' % index
    train(model, paramset, model_path)
```
이제 해당 코드를 병렬로 수행하면서 index값만 다르게만 여러 hyper parameter 중 하나의 param set을 가지고 와서 학습해 볼 수 있게 되었습니다.
그렇다면 indexing하는 `index` 변수는 어디서 가지고 오면 될까요? 바로 지난번 포스트에서 설명한 AWS Batch 환경에서 제공해주는 `AWS_BATCH_JOB_ARRAY_INDEX` 환경 변수를 활용하겠습니다.

그럼 이제 해당 코드를 docker image로 묶어 보도록 하겠습니다.

```python
# 전체 코드: train_model.py
from __future__ import print_function
import boto3
import yaml
import os

import keras
from keras.datasets import mnist
from keras.models import Sequential
from keras.layers import Dense, Dropout
from keras.optimizers import RMSprop
from keras.callbacks import ModelCheckpoint

NUM_CLASSES = 10

def build_model(paramset):
    # Hyper parameter setting
    batch_size = paramset['batch_size']
    epochs = paramset['epochs']
    hidden_nodes = paramset['hidden_nodes']
    dropout_rate = paramset['dropout_rate']
    activate_fn = paramset['activate_fn']
    optimizer = paramset['optimizer']
    model_path = paramset['model_path']

    # building model
    model = Sequential()
    model.add(Dense(512, activation='relu', input_shape=(784,)))
    for hidden_node in hidden_nodes:
        model.add(Dropout(dropout_rate))
        model.add(Dense(hidden_node, activation=activate_fn))
    model.add(Dropout(0.2))
    model.add(Dense(NUM_CLASSES, activation='softmax'))

    model.summary()
    model.compile(loss='categorical_crossentropy',
                  optimizer=optimizer,
                  metrics=['accuracy'])
    return model


def train(model, paramset, model_path):
    epochs = paramset['epochs']
    batch_size = paramset['batch_size']

    # the data, split between train and test sets
    (x_train, y_train), (x_test, y_test) = mnist.load_data()

    x_train = x_train.reshape(60000, 784)
    x_test = x_test.reshape(10000, 784)
    x_train = x_train.astype('float32')
    x_test = x_test.astype('float32')
    x_train /= 255
    x_test /= 255

    x_train = x_train[:10000]
    y_train = y_train[:10000]

    x_test = x_test[:10000]
    y_test = y_test[:10000]

    print(x_train.shape[0], 'train samples')
    print(x_test.shape[0], 'test samples')

    # convert class vectors to binary class matrices
    y_train = keras.utils.to_categorical(y_train, NUM_CLASSES)
    y_test = keras.utils.to_categorical(y_test, NUM_CLASSES)

    chkpt = ModelCheckpoint(model_path, monitor='val_acc', \
              verbose=1, save_best_only=True, mode='max')
    history = model.fit(x_train, y_train,
                        batch_size=batch_size,
                        epochs=epochs,
                        verbose=1,
                        callbacks=[chkpt],
                        validation_data=(x_test, y_test))
    score = model.evaluate(x_test, y_test, verbose=0)
    print(score)


BUCKET_NAME = 'my_bucket'
KEY = 'hyperparam_list.yml'

s3 = boto3.resource('s3')
s3.Bucket(BUCKET_NAME).download_file(KEY, 'hyperparam_list.yml')
index = int(os.environ['AWS_BATCH_JOB_ARRAY_INDEX'])
with open(KEY) as f:
    hyperparam_list = yaml.load(f)
    paramset = hyperparam_list[index]
    print(paramset)
    model = build_model(paramset)
    model_path = 'model_%s.h5' % index
    train(model, paramset, model_path)
```

```Dockerfile
# keras Dockerfile을 그대로 가져와서 조금 수정하였습니다.
ARG cuda_version=9.0
ARG cudnn_version=7
FROM nvidia/cuda:${cuda_version}-cudnn${cudnn_version}-devel

# Install system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
      bzip2 \
      g++ \
      git \
      graphviz \
      libgl1-mesa-glx \
      libhdf5-dev \
      openmpi-bin \
      wget && \
    rm -rf /var/lib/apt/lists/*

# Install conda
ENV CONDA_DIR /opt/conda
ENV PATH $CONDA_DIR/bin:$PATH

RUN wget --quiet --no-check-certificate https://repo.continuum.io/miniconda/Miniconda3-4.2.12-Linux-x86_64.sh && \
    echo "c59b3dd3cad550ac7596e0d599b91e75d88826db132e4146030ef471bb434e9a *Miniconda3-4.2.12-Linux-x86_64.sh" | sha256sum -c - && \
    /bin/bash /Miniconda3-4.2.12-Linux-x86_64.sh -f -b -p $CONDA_DIR && \
    rm Miniconda3-4.2.12-Linux-x86_64.sh && \
    echo export PATH=$CONDA_DIR/bin:'$PATH' > /etc/profile.d/conda.sh

ARG python_version=3.6

RUN conda install -y python=${python_version} && \
    pip install --upgrade pip && \
    pip install \
      sklearn_pandas \
      tensorflow-gpu && \
    pip install https://cntk.ai/PythonWheel/GPU/cntk-2.1-cp36-cp36m-linux_x86_64.whl && \
    conda install \
      bcolz \
      h5py \
      matplotlib \
      mkl \
      nose \
      notebook \
      Pillow \
      pandas \
      pygpu \
      pyyaml \
      scikit-learn \
      six \
      boto3 \
      theano && \
    git clone git://github.com/keras-team/keras.git /src && pip install -e /src[tests] && \
    pip install git+git://github.com/keras-team/keras.git && \
    conda clean -yt

ENV PYTHONPATH='/src/:$PYTHONPATH'

ADD train_model.py .
CMD python train_model.py
```

해당 이미지를 ECR에 upload까지 하면 모든 준비가 완료되었습니다. AWS Batch 서비스를 사용해 보도록 합시다.





#### What is AWS Batch?

![](/assets/images/aws_batch/aws-batch.png)

[AWS 공식 홈페이지](https://aws.amazon.com/batch/)에 가보면 '개발자, 과학자 및 엔지니어가 AWS에서 수많은 배치 컴퓨팅 작업을 효율적으로 실행할 수 있다'고 나와있습니다.
배치 컴퓨팅 작업은 비단 AWS만의 특별한 개념이 아닙니다. 우리가 흔히 배치 작업이라고 한다면, _미리 정의된 작업_ 을 _어떤 컴퓨팅 환경_ 위에서 원하는 순서와 수량을 _스케줄링_ 할 수 있으며
그 작업이 성공적으로 완료하였는지 _현황 확인_ 하는 것을 말합니다.

AWS Batch에서도 각각 동일한 개념을 사용합니다.
- Job Definition: 작업을 어떻게 실행할지 미리 정의를 합니다.
- Job: 미리 정의한 작업이 실제로 어떻게 동작할지를 정하고 (scheduling) 작업 결과를 보여줍니다. (monitoring)
- Job Queue: 실행할 작업을 잡 큐에 적재합니다. 각 Queue는 Compute Environment와 연결되어 있습니다.
- Compute Environment: 실제 작업이 이루어지는 환경입니다. (내부적으로 ECS를 사용합니다.)

![](/assets/images/aws_batch/aws_batch500.png)

먼저 Job Definition부터 보겠습니다.

##### Job Definition
AWS Batch 위에서 어떤 작업을 실행할지 정의하는 곳입니다.
많은 파라미터들이 있지만 몇가지 중요하게 생각하는 부분에 대해서 얘기하겠습니다.
더 자세한 내용은 [Job Definition 도큐먼트](https://docs.aws.amazon.com/batch/latest/userguide/job_definition_parameters.html)를 참고 바랍니다.
<!-- ![](/assets/images/aws_batch/jobdef.png) -->
- Job definition name: 작업 정의 이름을 넣습니다. 저는 `train`이라고 적겠습니다.
- Container image: 모델 학습을 하는 도커 이미지를 넣습니다.
- vCPUs: 해당 작업을 실행하기 위해 어느 정도의 CPU가 필요한지 명시적으로 적습니다. 여기서 중요한 것은 한 서버당 한개의 training만을 돌리고 싶으시면 해당 서버의 CPU만큼 적으시면 됩니다.(e.g. p2.xlarge 타입 경우 vCPU 4)
아직까지 GPU 자원을 명시적으로 요구하는 파라미터는 없는 것 같습니다.
- Environment variables: container에 정보를 넘길 때 사용합니다. AWS Batch에서는 한개의 Job definition을 이용하여 여러개의 job을 병렬로 실행할 수 있는데 이때 `AWS_BATCH_JOB_ARRAY_INDEX` env variable을 이용하여 해당 작업이 몇번째 Job으로 실행되고 있는지 알 수 있습니다. 이 변수를 이용하면 hyper parameter 리스트를 S3와 같은 원격 스토리지에 저장해 놓고 각각의 Job에서 index 순에 맞게 모델 파라미터들을 들고와서 병렬로 학습을 수행할 수 있게 됩니다. [Array Job 참고](https://docs.aws.amazon.com/batch/latest/userguide/array_jobs.html)
- Volumes & Mount points: 학습한 모델 파일 (checkpoint, h5 등)을 Host에서 접근할 수 있게 volume을 만듭니다. 이때 각각의 host에서 volume을 mount시키는 것이 아니라 `ssh volume`을 이용하여 원격 저장소에 바로 저장하려고 합니다. 참고 [docker ssh volume](https://github.com/vieux/docker-volume-sshfs)

##### Compute Environment
그 다음으로 작업이 실행될 환경을 생성해 봅시다. AWS Batch의 compute environment는 내부적으로 ECS를 사용합니다. 그래서 compute environment를 하나 생성하면 ECS cluster가 자동적으로 생성됩니다.
도커 컨테이너에서 컴퓨터의 GPU 자원을 이용하려면 몇가지 수정이 필요합니다. 매번 instance를 만들어서 수정할 필요 없이 custom AMI를 생성하여 사용하시면 편리합니다. 저의 [예전 포스트]({% post_url 2018-05-13-docker-based-ecs-ami %})를 참고하여 custom AMI를 생성하시기 바랍니다.
- Compute environment type: `Managed`
- Compute environment name: 컴퓨트 환경의 이름을 적습니다. 저는 `deeplearning_cluster` 라고 적겠습니다.
- Allowed instance types: 돈이 많이 없으므로 `p2.xlarge`를 선택하겠습니다.
- Minimum vCPUs: 실행하지 않을 때에는 instance를 전부 내리기 위해 `0`을 넣겠습니다. 자주 사용한다면 어느정도 유지하는게 나을 것 같습니다.
- Maximum vCPUs: 최대 5대가 넘지 않게 `20` (4 vCPU X 5 instance)이라고 설정하겠습니다.
- Enable user-specified Ami ID: `checked`
- AMI ID: 도커 컨테이너에서 Host의 GPU를 사용할 수 있게 수정한 AMI ID 입력

##### Job Queue
Job Queue는 Job Definition과 Compute Environment를 연결해 주는 통로라고 생각하시면 됩니다. 작업을 하나 정의하고 그것을 어떠한 컴퓨트 환경에서 실행 시키고 싶을 때, 해당하는 Job Queue의 대기열에 집어 넣으시면 됩니다.
일반적으로도 배치 작업을 병렬로 돌리고 싶을 때, 여러개의 worker를 생성하여 하나의 queue를 바라보게 하고 실행 시키고 싶은 작업을 대기열에 넣으면 놀고 있는 worker 중에 하나가 작업을 처리하는 것과 동일하다고 보시면 됩니다. 한가지 특정이 있다면 AWS Batch Job Queue에는 priority 설정을 할 수 있어서 여러 Job queue에 연결된 컴퓨트 환경 중에 해당 Job queue에 연결된 작업을 먼저 컴퓨터 환경에서 처리할 수 있도록 해줍니다.

##### Job
마지막으로 Job에 대해서 설명 드리자면, Job은 Job Definition의 instantiate된 객체라고 생각하시면 편합니다. Job Definition을 실제로 실행할 때, 몇개의 Job을 어느 정도의 cpu와 memory를 사용하여 어떤 Job Queue에 넣을 지를 결정하여 생성된 객체입니다. 또한 Job은 현재 실행되고 있는 작업의 상태를 보여줍니다. (running, failed, succeeded 등) job id를 이용하여 running하고 있는 작업을 취소할 수도 있습니다.

---

지금까지 AWS Batch 서비스에 대해서 알아봤습니다. 이제 어떻게 AWS Batch 서비스를 이용하여 효율적으로 분산 병렬 처리할 수 있을지 코드와 함께 살펴 보겠습니다.
