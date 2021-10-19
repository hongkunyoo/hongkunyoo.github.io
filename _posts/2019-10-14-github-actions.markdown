---
layout: post
title:  "GitHub Actions & Package Registry 사용기"
date:   2019-10-14 00:00:00
categories: cicd github
image: /assets/images/github-action/landing.png
---
얼마 전에 깃허브에서 자체적으로 CI/CD 플랫폼인 GitHub Actions를 Beta 공개하였죠. 그 동안 GitHub는 "나는 소스코드만 신경써서 관리해줄꺼야" 라는 입장을 취해왔는데 MS사가 깃허브를 인수한 이후로 조금 더 공격적으로 오픈소스 생태계를 장악하려고 하는게 아닌가 생각이 됩니다. 그것을 잘 보여주는 사례로 CI/CD 플랫폼 제공뿐만 아니라 소스코드를 빌드하고 난 artifact들을 저장하고 관리하고 배포할 수 있는 GitHub Package Registry라는 저장소까지 제공하기 시작했습니다. 이번 포스트에서 GitHub Actions & Package Registry가 어떤 서비스이고 어떻게 사용하는지 살펴보도록 하겠습니다.

![GitHub Actions](/assets/images/github-action/01.png)

GitHub Actions & Package Registry를 발표한 이후, 제 개인적인 입장에서는 동일한 서비스 위에서 소스코드 관리부터 최종 빌드된 결과물까지 한번에 관리할 수 있다는 점에서 반기는 일이지만 다른 CI/CD 및 패키지 관리 서비스들에게는 강력한 경쟁자가 나타난 것으로 보입니다. 물론 기존 서비스 및 툴들은 풍부한 생태계를 가지고 있고 성숙한 문화 및 Best practice 사용법들이 있기 때문에 당장 존폐의 위기에 처하지는 않겠지만 이제는 도커라는 기술로 인해 점점 CI/CD 워크플로우가 단순해지고 표준화되고 있어 오픈소스 레포지토리 생태계를 잡고 있는 GitHub로써 그 기능을 수평확장하는 것은 그렇게 어렵지 않다고 생각됩니다. 저만 하더라도 빌드에 필요한 세부적인 명령들과 conf값 설정들을 전부 `Dockerfile` 안에서 해결하기 때문에 외부에서 빌드 명령어를 바라본다면 `docker build` 가 전부인 경우가 많습니다. 물론 몇 가지 빌드 파라미터로 넘기는 값들이 있긴하지만 해당값들은 특정 OS나 라이브러리가 필요하기보단 간단한 bash script로도 충분히 해결할 수 있었습니다. \(저는 파이썬을 많이 사용하기 때문에 `Dockerfile` 로도 충분히 해결할 수 있었을 수도 있습니다. 다른 언어나 플랫폼은 다를 수 있다는 점 말씀드립니다.\)

### GitHub Actions 살펴보기

그렇다면 본격적으로 GitHub Actions에 대해서 먼저 살펴보도록 하겠습니다. 해당 기능을 테스트해보고 싶으신 분은 먼저 [https://github.com/features/actions](https://github.com/features/actions) 페이지에 가셔서 beta 사용 신청을 하셔야 합니다.  신청 이후에 기다리면 아래와 같이 본인이 관리하고 있는 레포지토리에 Actions라는 탭이 생깁니다.

![](/assets/images/github-action/03.png)

Actions를 테스트해보고 싶으신 분들은 지금 바로 신청하시기 바랍니다. Actions는 Linux, macOS, Windows 세가지 플랫폼을 제공합니다. 또한 다른 CI/CD툴들과 마찬가지로 병렬로 워크플로우를 실행할 수 있는 기능을 제공합니다. \(GitHub Actions에서는 이를 Matrix라 부릅니다.\) 마지막으로 GitHub Actions에서는 사용자들에게 직접 도커 컨테이너로 custom한 Step을 만들수 있게 열어 놓았기 때문에 사실상 어떠한 언어나 라이브러리, 프레임워크를 사용할 수 있습니다. 벌써 [GitHub marketplace](https://github.com/marketplace?type=actions)에는 slack notify와 같이 대체로 사람들이 즐겨 많이 사용하는 step들이 많이 올라와있습니다. 

![Github Actions](/assets/images/github-action/02.png)

### GitHub Actions 핵심 개념

CI/CD 워크플로우를 만들기에 앞써 먼저 몇 가지 개념들을 정리하고 가겠습니다.

#### Workflow

소스코드를 내려받고 빌드를 하고 최종적으로 빌드 결과물을 저장하거나 배포하는 등 자동화된 전체 프로세스를 나타낸 순서도입니다. GitHub에게 나만의 동작을 정의한 workflow file를 만들어 전달하면 GitHub Actions이 그것을 보고 그대로 실행 시켜줍니다.

#### Job

잡은 여러 step을 그룹 지어주는 역할을 하며 단일한 가상 환경을 제공해 줍니다. 각 잡에 서로 다른 가상 환경을 부여할 수 있고 잡끼리의 디펜던시를 설정하거나 병렬로 실행할 수 있는 기능을 제공합니다.

#### Step

step은 Job안에서 sequential하게 실행되는 프로세스 단위이며 파일시스템을 통하여 서로 정보를 공유할 수 있습니다. step에서 명령을 내리거나 action을 실행할 수 있습니다.

#### Action

step에서는 단순히 OS에서 지원하는 명령을 내리는 것 뿐만 아니라 미리 제공된 action 혹은 사용자가 직접 customizing한 action을 호출할 수 있는 매커니즘을 제공하고 이를 action이라 부릅니다. action은 내부적으로 도커 컨테이너 혹은 javascript를 통해서 실행되며 도커를 사용할 경우 사용자는 `Dockerfile`을 제공함으로써 action을 커스텀화할 수 있습니다. 

#### Event

정의한 workflow를 언제 실행 시킬지 알려줍니다. 기본적으로 cron잡과 같이 시간 based로 실행시킬 수도 있으며 보통 많이 사용하듯이 `push`, `PR` 등 소스코드 레포지토리의 이벤트를 기준으로 실행시킬 수 있습니다.

### Workflow 만들어 보기

그렇다면 이제 나만의 workflow를 만들어 보도록 해봅시다.

```yaml
# .github/
#      workflows/
#              main.yml
name: my first workflow              # workflow 이름
on: push                             # event trigger on push

jobs:
  build:                             # job id
    name: Hello world action         # job 이름
    runs-on: ubuntu-latest           # 가상 환경
    steps:
    - name: checkout source code     # step 01 이름
      uses: actions/checkout@master  # 소스코드 checkout
    - name: say hello                # step 02 이름
      run: echo "hello world"        # linux command 실행
```

다음 파일을 `.github/workflows` 디렉토리 밑에 `main.yml`이라는 이름으로 저장해 봅시다. 가장 기본이 되는 workflow 모습입니다. 기존에는 HCL syntax로 구성이 되었지만 지금은 YAML형식으로 구성이 됩니다. 해당 workflow는 간단하게 ubuntu 환경 아래에서 해당되는 깃허브 레포지토리를 checkout 받고 hello world를 출력하는 예시입니다. 그럼 이제 한번 깃허브에 푸시해보도록 하겠습니다.

```bash
git add .github/workflows/main.yml
git commit -m "my first actions workflow"
git push origin master
```

GitHub 사이트의 Actions 페이지에 가보면 나만의 첫 Actions workflow가 실행된 것을 확인하실 수 있습니다.

![1.checkout code / 2. echo &quot;hello world&quot;](/assets/images/github-action/04.png)

보시다시피 결국 모든 것은 workflow file을 어떻게 만드느냐에 달려있습니다. 자세한 workflow configuration에 대해서는 [다음 문서](https://help.github.com/en/articles/configuring-workflows)를 확인해 보시면 좋습니다. 그럼 이제 나만의 커스텀화된 action은 어떻게 만드는지 살펴보도록 하겠습니다.

### 나만의 action 만들기

먼저 `hello-world-docker-action` 라는 github 퍼블릭 레포지토리를 하나 생성합시다. 그리고 해당 레포지토리를 내려받습니다.

```bash
git clone https://github.com/$USERNAME/hello-github-actions.git
cd hello-github-actions
```

해당 디렉토리 밑에 `entrypoint.sh`, `Dockerfile`, `action.yml` 총 3개 파일을 만들 예정입니다. 하나씩 알아보죠. 먼저 가장 중요한 action의 동작을 결정 지을 `entrypoint.sh`을 만들어 보겠습니다.

```bash
#!/bin/sh -l

who=${1:-world}
echo "Hello" $who
```

사용자로부터 파라미터를 받아서 콘솔로 출력하는 간단한 action 입니다. 이것을 실행 가능한 스크립트로 변환해 줍니다.

`chmod +x entrypoint.sh` 

그리고 난 뒤, 이 스크립트를 도커 컨테이너로 실행할 수 있게 `Dockerfile`을 만들어 줍니다.

```Dockerfile
FROM alpine:3.10

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
```

이제 어디서든 실행 가능한 도커 이미지를 만들기에 필요한 모든 재료들을 준비하였습니다. 다음은 GitHub Actions에서 해당 도커 이미지를 step에서 활용할 수 있게 해주는 `action.yml` 파일을 만들어 봅시다.

```yaml
name: 'Hello World'               # action 이름
description: 'Greet someone'      # 간단한 설명
inputs:
  who-to-greet:                   # id of input    
    description: 'Who to greet'
    required: true
    default: 'World'
runs:
  using: 'docker'                 # 도커 사용 명시
  image: 'Dockerfile'             # Dockerfile을 이용하여 이미지 생성
  args:                           # docker run 에서 넘길 파라미터
    - ${{ inputs.who-to-greet }}
```

지금까지 작성한 파일의 디렉토리 구조는 다음과 같습니다.

```bash
hello-github-actions/
              entrypoint.sh
              Dockerfile
              action.yml
```

action을 만들기 위한 모든 작업을 완료했습니다. 해당 action을 workflow에서 접근할 수 있도록 작성한 파일들을 깃허브에 올리겠습니다.

```bash
git add .
git commit -m "Testing my first GitHub Action"
git push origin master
```

이제 `hello-github-actions` 레포지토리를 포함 어느 GitHub Action Workflow에서 방금 만든 Action을 참조하여 사용하실 수 있습니다.

```yaml
on: push

jobs:
  hello_world_job:
    runs-on: ubuntu-latest
    name: A job to say hello
    steps:
    - name: Hello world action step
      id: hello
      uses: $USERNAME/hello-world-docker-action@master
      with:
        who-to-greet: 'Mona the Octocat'
```

### GitHub Package Registry에 빌드 결과물 저장하기

지금까지 workflow를 작성하는 방법, 나만의 커스텀 action을 만드는 방법에 대해 살펴보았습니다. 그렇다면 workflow를 통해 빌드한 결과물을 GitHub Package Registry라는 깃헙 artifact 저장소에 저장하는 방법에 대해 알아보도록 하겠습니다.

GitHub Package Registry는 사실 별개 없습니다. Docker, npm, Maven, RubyGem 등 기존의 패키지 매니저에서 리모트 레포지토리 주소만 GitHub Package Registry 쪽으로 바꿔주기만 하면 되기 때문입니다. 저는 도커 이미지로 주로 배포하기 때문에 도커 이미지를 만들어서 깃헙 도커 이미지 저장소에 업로드하는 방법에 대해서 설명 드리도록 하겠습니다.

GitHub Package Registry에 이미지를 업로드하기 위해서는 아래의 3줄이 전부입니다.

1. 깃헙에서 제공하는 도커 레포지토리에 로그인을 합니다.  
   `$PERSONAL_ACCESS_TOKEN`는 `github 프로필` - `settings` - `Developer Settings` - `Personal access token`에서 생성하실 수 있으며  `read:packages`_, `repo`, `write:packages`_ 권한이 있어야 합니다.  


   ```bash
   docker login docker.pkg.github.com --username $USERNAME -p $PERSONAL_ACCESS_TOKEN
   ```

2. 다음으로 원하는 깃헙 레포지토리의 이름으로 이미지 이름을 지정합니다. 여기서 주의하셔야 할 점은 최하위 이미지의 이름이 \(여기서는 app\) 레포지토리 네임스페이스에 제한되지 않고 \($REPO\_NAME\) 사용자 전체 네임스페이스 \($USERNAME\) 안에서 unique해야 합니다.  


   ```bash
   docker build . -t docker.pkg.github.com/$USERNAME/$REPO_NAME/app:1.0
   ```

   docker.pkg.github.com/$USERNAME/A-repo/app:1.0  
   docker.pkg.github.com/$USERNAME/B-repo/app:1.0  
   아무리 A-repo, B-repo 레포지토리가 달라도 이미지 이름이 app으로 동일하므로 이미지 업로드시 에러가 남.  
   저는 이 사실을 모르고 한참을 해매다가 겨우 알게 되었습니다. \(에러 로그가 친절하지 않습니다.\)  

3. 마지막으로 지정한 이름으로 빌드한 이미지를 깃헙 이미지 저장소에 업로드합니다.  


   ```bash
   docker push docker.pkg.github.com/$USERNAME/$REPO_NAME/app:1.0.0
   ```

그리고 난 뒤 깃헙의 package 탭에 가보시면 이렇게 app이라는 도커 이미지가 생성된 것을 확인하실 수 있습니다.

![](/assets/images/github-action/05.png)

지금까지 알아본 기능들을 이용하여 소스코드를 깃헙 레포지토리에 푸시 시점에 이미지를 빌드하고 깃헙 이미지 저장소로 업로드하는 workflow를 다음과 같이 만들 수 있습니다.

```yaml
name: build N push
on: push

jobs:
  build:
    name: Hello world action
    runs-on: ubuntu-latest    
    steps:
    - name: checkout source code
      uses: actions/checkout@master

    - name: Build the Docker image
      run: docker build . -t docker.pkg.github.com/$USERNAME/$REPO_NAME/app:${{ github.sha }}

    - name: Test image
      run: docker run --entrypoint pytest docker.pkg.github.com/$USERNAME/$REPO_NAME/app:${{ github.sha }}

    - name: login
      run: docker login docker.pkg.github.com -u ${{ secrets.DOCKER_USER }} -p ${{ secrets.DOCKER_PASSWORD }}

    - name: push
      run: docker push docker.pkg.github.com/$USERNAME/$REPO_NAME/app:${{ github.sha }}
```

### 마무리하며

2019년 10월 현재 아직 beta 서비스 기간인 시점에서 아직까지 서비스가 약간 불안정하고[^1] 편의 기능들이 조금 부족하고[^2] 에러 로그가 불친절하지만[^3] GitHub 이라는 멋진 서비스 안에서 소스코드 관리 뿐만 아니라 CI/CD 관리, Artifact 관리까지 할 수 있다는 점은 분명 저에게는 엄청나게 매력적으로 다가 왔습니다. 앞으로 서비스가 안정화되고 문화가 성숙해진다면 많은 오픈소스 진영에서 잘 사용하지 않을까 기대합니다.


[^1]: 원인을 알 수 없는 빌드 fail이 발생하는 경우가 있었습니다.

[^2]: workflow 재실행 기능, 자동 UI 업데이트 등

[^3]: 앞써 말씀 드렸다시피, 이미지 이름이 중복되어 에러가 났음에도 관련한 에러 로그가 제대로 출력되지 않아 문제를 해결하는데 애를 먹었습니다. 이와는 별개로 레포지토리별로 네임스페이스가 제한되어야 한다고 생각합니다.

