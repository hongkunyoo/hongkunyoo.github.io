---
layout: post
title:  "[Tensorflow] r0.12 ver 기준 설치 가이드 Best Practice"
date:   2017-01-22 21:10:00
categories: machine-learning ml tensorflow
---

작성날짜: 2017년 1월 기준 tensorflow 설치방법

그 동안 텐서플로우가 발전하면서 설치하는 방법이 점점 쉬워지고 있습니다.
예전에는 GPU supported 버젼을 설치하려면 bazel을 이용해서 소스코드부터 설치를 해야 했다면 이제는 pip install로도 바로 설치를 할 수 있게 되었습니다. 그럼에도 불구하고 한방에 NVIDIA Drive 및 CUDA를 깔끔하게 설치하는게 쉽지 않아 제가 시도해본 설치 방법 중 **Best Practice**를 적어 두었습니다.

#### 설치 사양
- Ubuntu 16.04 LTS
- Anaconda3 (python 3)
- CUDA v8.0
- CUDNN v5.1
- Tensorflow Ubuntu GPU version v0.12


----------------------------------------------------
#### 설치 방법
Tensorflow GPU 버젼을 사용하려면 NVIDIA Driver와 CUDA Library를 설치해야 하는데 만약 기존에 NVIDIA 드라이버가 깔린 경우 완전히 지우고 처음부터 다시 설치하는게 제 경우에는 가장 깔끔했습니다. 그렇게 하지 않으면, NVIDIA driver 버전과 CUDA 버전이 mismatch 한다는 error가 발생하였기 때문입니다.

###### 먼저 기존의 NVIDIA Driver가 깔려있다면 지워줍니다.
```
# 복붙
sudo apt-get remove --purge nvidia-*
sudo apt-get install ubuntu-desktop
sudo rm /etc/X11/xorg.conf
sudo nvidia-uninstall
```
그리고 나서 꼭 재부팅 시켜줍니다. 
```
sudo shutdown -r now
```
----------------------------------------------------
###### NVIDA Develop site에 들어가셔서 CUDA 설치 파일을 받아줍니다.
https://developer.nvidia.com/cuda-downloads

이때 Installer Type으로 꼭 **runfile (local)**을 다운 받습니다. 그 이유로는 runfile을 통해 설치해야 자동으로 NVIDIA Driver까지 알아서 설치 되기 때문입니다. (그렇지 않은 경우, 직접 서로 버전이 호환되는 NVIDIA Driver를 설치해야합니다.)

![](/assets/images/nvidia_install_pic-1.png)


----------------------------------------------------
###### CUDA를 설치하기 전에 미리 다음과 같은 패키지들을 설치합니다.
```
# 복붙
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y opencl-headers build-essential protobuf-compiler \
   libprotoc-dev libboost-all-dev libleveldb-dev hdf5-tools libhdf5-serial-dev \
   libopencv-core-dev libopencv-highgui-dev libsnappy-dev libsnappy1 \
   libatlas-base-dev cmake libstdc++6-4.8-dbg libgoogle-glog0 libgoogle-glog-dev \
   libgflags-dev liblmdb-dev git python-pip gfortran
sudo apt-get clean
sudo apt-get install -y linux-image-extra-`uname -r` linux-headers-`uname -r` linux-image-`uname -r`
```
----------------------------------------------------
###### 이제 CUDA를 설치합니다. 그전에 꼭 X-server를 꺼줍니다.
```
# NVIDIA Driver 설치를 위해 X server를 꺼준다.
sudo service lightdm stop
```
NVIDIA 사이트에서 받은 run file을 실행합니다.
```
# cd /path/to/downloaded/cuda_run_file
sudo sh cuda_8.0.44_linux.run
```
설치 가이드에 따라 진행을 하시면 됩니다.

----------------------------------------------------
###### 이번에는 NVIDIA Developer site에 가셔서 CuDNN 라이브러리를 다운 받습니다.
https://developer.nvidia.com/cudnn

Download > login > Download cuDNN v5.1 (August 10, 2016), for CUDA 8.0 > cuDNN v5.1 Library for Linux)

`wget`으로 바로 받으시려면 
```
# CUDA v8.0 / cudnn v5.1
wget https://developer.nvidia.com/compute/machine-learning/cudnn/secure/v5.1/prod/8.0/cudnn-8.0-linux-x64-v5.1-tgz
```
그리고 난 후 압축을 풀고 
```
tar -xvf cudnn-8.0-linux-x64-v5.1-tgz
```
압축 푼 파일을 `/usr/local/cuda`에 넣어 줍니다.
```
sudo cp cuda/include/* /usr/local/cuda/include/.
sudo cp cuda/lib64/* /usr/local/cuda/lib64/.
```

그리고 .bashrc를 열어서 CUDA HOME을 path에 추가 시킵니다.
```
vi ~/.bashrc
export CUDA_HOME=/usr/local/cuda
export PATH=${CUDA_HOME}/bin:$PATH 
export LD_LIBRARY_PATH=${CUDA_HOME}/lib64
```
다시 한번 재부팅을 해줍니다. `sudo shutdown -r now`

이제 제대로 설치되었는지 확인해 봅시다. `nvidia-smi`

GPU에 관한 status가 나온다면 제대로 설치 완료!!

지금까지 NVIDIA Driver 및 CUDA & CuDNN 라이브러리를 설치하였습니다.

-------------------------------------------------------------------

#####Anaconda 및 tensorflow 설치하기

여기 까지 오셨으면 거의 다했습니다. 이제 anaconda 및 tensorflow를 설치해 보겠습니다.

###### Anaconda 다운받기 (Optional)
아나콘다 설치는 하셔도 되고 생략하셔도 무방합니다.
다만 시스템 path에 텐서플로우를 설치하였는데 나중에 버전 문제로 꼬이게 되면 머리가 아프기 때문에 저는 애초에 아나콘다를 설치하겠습니다.

아나콘다 공식 사이트에 가셔서 다운을 받습니다. https://www.continuum.io/downloads

파이썬2 혹은 파이썬3 아무거나 다운 받으셔도 상관 없습니다.
저는 파이썬3 64비트를 사용합니다.
```
# wget으로 받으시려면 (python3, 64bit)
wget https://repo.continuum.io/archive/Anaconda3-4.2.0-Linux-x86_64.sh
```
다운 받으신 이후에, 실행을 시켜줍니다.
```
# path/to/downloaded/anaconda_install_file
bash Anaconda3-4.2.0-Linux-x86_64.sh
```

아나콘다 설치 마지막에 `~/.bashrc`에 아나콘다를 사용자 path에 삽입할 건지 묻는 질문에 `yes`를 해줍니다. 그리고
`source ~/.bashrc`를 입력하셔서 path를 업데이트 시켜주시고
마지막으로 tensorflow를 설치합니다.
```
pip install tensorflow-gpu
```
설치가 완료되면 tensorflow가 제대로 설치되었는지 import 시켜봅니다.
```
python -c 'import tensorflow'
```
`successfully opened CUDA library` 와 같은 문구가 뜬다면 설치 성공!

이제 즐겁게 딥러닝을 시작해 봅시다!
