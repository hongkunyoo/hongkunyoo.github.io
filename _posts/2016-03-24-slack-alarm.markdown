---
layout: post
title:  "[기계학습] Slack을 이용한 Training 완료 알람 시계 만들기"
description: "slack을 이용하여 모델 학습 종료 알람을 받아봅시다"
date:   2016-03-24 18:18:00
categories: machine-learning ml slack
---

slack을 이용하여 모델학습이 끝난 이후에 알람을 받도록 해봅시다.

기계학습에서 모델 training을 할 때, 대용량 데이터를 학습 시켜야 하는 경우가 많고 필연적으로 처리하는 시간이 늘어납니다. 그러다 보니 학습을 시켜 놓고 딴 작업(이라 적어 놓고 딴 짓)을 하게 됩니다. 처음에는 완료가 되었는지 몇 번 확인하다가 나중에는 까먹고 다른 일에 빠져서 샛길로 가는 경우가 많게 됩니다. 또한 간혹 데이터 포맷이 깨져서 에러가 발생하는 경우도 생기지만 한참 후에나 발견하게 됩니다. 가슴 아픈 마음을 쓸어 담고 데이터를 수정하여 다시 학습을 시키지만 이제는 따른 작업을 하지도, 그렇다고 계속 검은 모니터를 마냥 지켜볼 수만은 없는 노릇입니다.

이것을 한방에 해결해 줄 간단한 방법을 소개합니다. <br>
바로 **Slack**을 이용한 방법입니다.

슬랙은 참 간단하면서도 강력한 기능이 많은 것 같습니다. 많은 슬랙 기능 중에 [Incomming Web hooks](https://api.slack.com/incoming-webhooks) 을 이용하여 알람을 맞춰 보겠습니다.

큰 그림은 다음과 같습니다.

1. 학습이 종료(혹은 exception)함에 따라 Web hook을 날려 준다.
2. 핸드폰에서 알림을 받아 결과를 인지한다.
![](/assets/images/slack_alarm.png)

간단하죠? 그럼 순서대로 따라 가보겠습니다.

1. 가장 먼저 [Slack.com](https://slack.com/)에 가셔서 Slack Team을 만들어야 합니다.
+ 그리고 Slack 개발자 페이지에 가셔서 개발자 등록을 해야 합니다.
https://api.slack.com/register
여기에 가셔서 몇 가지 정보들을 입력하고 등록하세요.
+ 그리고 난 후, 자신만의 Application을 생성해야 합니다.
https://api.slack.com/applications/new
여기서 어플리케이션을 생성할 때, 처음에 만들었던 Slack Team을 지정하시면 됩니다.
+ 이제 [Web-hook](https://my.slack.com/services/new/incoming-webhook/) 생성 페이지에 들어가셔서 알람을 받으실 채널을 지정해 주시고 Add Incomming Webhooks Integration 버튼을 누르시면 Webhook URL(https://hooks.slack.com/services/XXXXXX)이 보일 것입니다. 이제 해당 URL로 Request를 날리게 되면 핸드폰에서 알람이 오게 됩니다.

그럼 한번 테스트를 해보죠
```bash
curl -X POST -H 'Content-type: application/json' --data '{"text":"This is a line of text.\nAnd this is another one."}' https://hooks.slack.com/services/XXXXXXXXXXXXXXXXXXXXX
```
핸드폰에 Slack App이 깔려 있고, 앞서 발급 받았던 Webhook URL을 이용하여 curl을 호출하면 핸드폰에 알람이 오면 일단 성공입니다. 지금은 단순히 텍스트만 전송하지만 나중에 Slack [Incoming Web hook](https://api.slack.com/incoming-webhooks) 페이지를 참고하시면 좀 더 자세한 설정들을 할 수 있습니다.

그럼 이제 파이썬에 연결해 봅시다.

```python
import json
import urllib2
import time

def alarm(msg):
	payload = {"text": msg}
    url = "https://hooks.slack.com/services/XXXXXXXXXXXXX"
    req = urllib2.Request(url)
    req.add_header('Content-Type', 'application/json')
    urllib2.urlopen(req, json.dumps(payload))

def train():
    # Load Dataset
    # Build Model
    start = time.time()
    # Training
    # 기타 등등
    # Training 종료
    elapsed = time.time() - start
    # 알람 호출하기
    alarm(elapsed)

train()
```

모든 작업이 끝나고 해당 URL을 요청하게 되면 알람이 울리게 됩니다. 하지만 문제가 있습니다. 학습 작업 중 에러 발생에 대한 알람은 받지 못하게 됩니다. 그럼 에러 처리까지 한번 해볼까요?

```python
def train():
    try:
        # Load Dataset
        # Build Model
        start = time.time()
        # Training
        # 기타 등등
        # Training 종료
        elapsed = time.time() - start
        msg = elapsed
    except Exception as e:
        msg = e.message
    finally:
        alarm(msg)

```

이제 학습을 하다가 에러가 발생한 경우에도 알람을 받을 수 있게 되었습니다. 하지만 코드가 지저분해진 것 같습니다. 조금 더 예쁘게 바꿀 순 없을까요?

방법은 파이썬 decorator를 사용하는 것입니다. 저는 매번 decorator를 사용만 해봤지 직접 만들어 보긴 처음이였습니다. decorator를 사용해서 깔끔하게 고쳐 보겠습니다.

-------

####Python Decorator
Decorator란 간단하게 함수를 꾸며주는 친구라고 볼 수 있습니다. 어떻게 꾸며 주냐고요? 먼저 일반 케익을 만드는 함수를 만들고 거기에 데코레이팅을 해보겠습니다.
```python
# 케익 만드는 함수
def make_cake(name):
    return 'made a %s cake' % name

# 일반 초코 케익 만들기
print make_cake('chocolate')
>>> 'made a chocolate cake'

# 여기가 바로 케익을 어떻게 데코레이팅 할지 정하는 부분입니다.
# 저는 슈가 파우더로 꾸며 보겠습니다.
def decorate_cake(func):  # func은 기존의 함수
    def new_make_cake(name):
        return func(name) + " decorated with sugar powder"
    return new_make_cake  # 새롭게 만들어진 함수를 돌려줍니다.

# 데코레이팅 작업 (기존의 함수를 데코레이팅 시켜 줍니다.)
make_cake = decorate_cake(make_cake)

# 이제는 슈가 파우더가 뿌려진 케익을 얻을 수 있습니다!
print make_cake('chocolate')
>>> 'made a chocolate cake decorated with sugar powder'
```

마지막으로 파이썬에서는 decorating 작업을 조금 더 편하게 하기 위한 특별한 syntax를 제공합니다. 꾸미고 싶은 함수 위에 @표시와 함께 데코레이팅을 시켜주는 함수를 적으면 알아서 데코레이팅 시켜 줍니다.

```python
@decorate_cake
def make_cake(name):
    return 'made a %s cake' % name

# make_cake = decorate_cake(make_cake)  # 이제 이 코드를 생략해도 됩니다.
```
더 자세하고 정확한 내용은
[A guide to Python's function decorators](http://thecodeship.com/patterns/guide-to-python-function-decorators/)를 참고하시면 좋을 것 같습니다.

--------------

####최종 알람 시계 만들기

```python
# 기존의 알람 호출 함수
def alarm(msg):
	payload = {"text": msg}
    url = "https://hooks.slack.com/services/XXXXXXXXXXXXX"
    req = urllib2.Request(url)
    req.add_header('Content-Type', 'application/json')
    urllib2.urlopen(req, json.dumps(payload))


# decorating 해주는 함수
def alarmable(training_func):
    def wrapper(*args, **kargs):
        try:
            start = time.time()
            training_func(*args, **kargs)
            end = time.time()
            msg = end - start
        except Exception as e:
            msg = e.message

        alarm(msg)

    return wrapper

@alarmable
def train():    # train = alarmable(train)과 같습니다.
    # Load Dataset
    # Build Model
    # Training
    # 기타 등등
    # Training 종료

@alarmable
def other_train_model():
    ...
```

이제 모듈 형태로 ```alarm```함수와 ```alarmable```함수만 미리 만들어 놓으면
앞으로 시간이 많이 걸리는 함수 위에 ```@alarmable``` decorator만 달아 주면 어떤 함수든지 알아서 알람이 울리게 됩니다.

개인적으로 기계학습 모델을 training할 때, 어떻게 하면 낭비되는 시간을 줄일 수 있을까 고민하면서 시작했지만 문제도 해결했고 슬랙 API와 파이썬 decorator에 대해서도 공부해 보는 시간이 되었습니다.
