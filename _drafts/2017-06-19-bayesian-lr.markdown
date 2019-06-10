---
layout: post
title:  "Linear Regression Bayesians vs Frequentists"
date:   2019-06-19 00:00:00
categories: bayesian linear regression
---

[From both sides now: the math of linear
regression](http://katbailey.github.io/post/from-both-sides-now-the-math-of-linear-regression/)

이 글은 다음과 같은 글을 읽고 frequentist와 bayesian 관점에서의 Regression을 잘 정리한 것 같아
번역해 보았습니다.

---

Linear regression은 기계학습에서 가장 기본적이고 널리 쓰이는 기술입니다. 그렇지만 간단한 기술임에도
불구하고 통계학에서 아주 중요한 개념들을 배울 수 있습니다.

만약 당신이 \\(\hat y = \theta\_0 + \theta\_1X\\)와 같은 식의 기본적인 이해가 있지만 Ridge
Regression이 사실은 zero-mean Gaussian prior을 가진 MAP(Maximum A Posteriori) 추정치와 상등하다는
말을 잘 이해하지 못한다면, 이 글이 딱 당신에게 맞을 것입니다. (저 또한 마찬가지로 얼마전까지는 이
둘의 차이를 이해하지 못했었습니다.) 방금 얘기한 이 문장을 이해하기 위해 우리는 가장 기본적인 Linear
Regression부터 시작하여 확률론적 접근 관점(Probabilistic approach)에 대해서 얘기해 보고(maximum
likelihood formulation) 마지막으로는 Bayesian linear regression에 대해서도 얘기해 볼 예정입니다.

먼저 \\(\theta\\)를 앞으로 regression 모델의 가중치라고 표기하겠습니다. 간혹 명확히
\\(\theta\_0\\)와 \\(\theta\_1\\)를 분리하여 기울기와 절편으로 나누어서 설명하기도 하고 전체 합쳐서
\\(\theta\\)를 모델의 가중치 벡터라고도 표현하겠습니다. 또한 주로 \\(\theta^Tx\_i\\)를 \\(x\_i\\)가
주어졌을 때의 모델의 예측값으로 표기하겠습니다. 이는 y 절편이 \\(\theta\\)안에 포함되어 있다는
가정입니다.

## 선에서 무엇을 알 수 있나요?
#### (What's in a line?)
![](/assets/images/least_squares_sm.jpg)

단변량 Linear regression인 경우, 우리는 최소 승자법(least squares)에 들어맞는 선이 실측값과 예측값의
차이의 합을 최소화 한다는 것을 알고 있습니다. 
Residual Sum of Squares: 

$$\underset{\theta}{\arg\min}\sum_{i=1}^n(y\_i-\hat{y\_i})^2$$
이때, 
$$\hat{y\_i} = \theta\_0 + \theta\_1x\_i$$
가 i번째 입력의 예측값인 것을 알 수 있습니다. 그리고 우리는 i번째 입력의 실제값을 다음과 같이 정의할
수 있습니다.
$$y\_i = \theta\_0 + \theta\_1x\_i + \epsilon\_i$$
여기서 \\(\epsilon\_i\\)을 잔차 (residual), 혹은 오차라고 할 수 있습니다. 이것은 예측값
\\(\hat{y\_i}\\)과 실제값 \\(y\_i\\)와의 차이라고 생각할 수 있습니다.

이 잔차는 앞으로 우리의 모델을 설계할 때 중요한 요소가 될 것입니다. 지금으로서는 잔차의 정의로서
평균값이 (Expected value)가 0이 되어야 한다고만 생각하시면 됩니다.

우리가 이 선에서 어떤 것을 더 알아 볼 수 있을까요? 바로 이 선이 예측치와 결과값간에 특별한 관계를
정의하는 것을 알 수 있습니다. 특히 선의 기울기가 예측값과 결과값과의 상관관계를 결정합니다. 그렇기
때문에 우리는 데이터를 통해 \\(\theta\_1\\)를 계산할 수 있습니다. \\(\theta\_0\\)의 경우에는 어떻게
할까요? 먼저 우리는 이 선이 \\(\bar{x}, \bar{y}\\)의 점을 지난다는 것을 압니다. 그렇기 때문에 우리가
선의 기울기만 알면 \\(\theta\_0 = \bar{y} - \theta\_1\bar{x}\\)와 같은 식을 통해 절편을 알 수
있습니다.

p개의 변수를 가지는 다변량 선형 회귀 모델인 경우, 우리는 다음과 같이 모델링 할 수 있습니다.
\\(\hat{y\_i} = \theta\_0 + \theta\_1x\_1 + \theta\_2x\_2 + … + \theta\_px\_p\\)

이러한 경우에는 단변량 선형 회귀 모델처럼 단순하게 모델의 계수를 찾기 쉽지 않습니다. 그 대신, 우리는
미적분학을 통해 다변량 모델의 목적 함수의 partial derivative를 구한 다음 그것을 0으로 놓고 계수의
해를 구하면 됩니다.

## 최적문제: 극대화에서부터 최소화로
#### (From minimization to maximization)

If we ever want to understand linear regression from a Bayesian perspective we need to start
thinking probabilistically. We need to flip things over and instead of thinking about the line
minimizing a cost, think about it as maximizing the likelihood of the observed data. As we’ll see,
this amounts to the exact same thing - mathematically speaking - it’s just a different way of
looking at it.

To get the likelihood of our data given our assumptions about how it was generated, we must get the
probability of each data point y and multiply them together.



$$\theta$$

\\[\theta\\]

\\(\theta\\)

\\(H\_0: \mu\_{A} = \mu\_{B}\\)


```python
def log_likelihood(x, y, theta0, theta1, stdev):
    # Get the likelihood of y given the least squares model described
    # by theta0, theta1 and the standard deviation of the error term.
    for i, x_val in enumerate(x):
        mu = theta0 + (theta1*x_val)
        # This is just plugging our observed y value into the normal
        # density function.
        lk = stats.norm(mu, stdev).pdf(y[i])
        res = lk if i == 0 else lk * res
    return Decimal(res).ln()
```
