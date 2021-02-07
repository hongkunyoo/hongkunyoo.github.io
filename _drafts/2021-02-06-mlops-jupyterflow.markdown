---
layout: post
title:  "JupyterFlow - Better way to run your ML code"
date:   2021-02-06 00:00:00
categories: kubernetes mlops
image: /assets/images/jupyterflow/landing.png
---
Introducing JupyterFlow, a better way to run your ML code on Kubernetes.

I read this article "[Data Scientists Don't Care About Kubernetes](https://determined.ai/blog/data-scientists-dont-care-about-kubernetes)" and I totally agree with it. Using Kubernetes for training ML models is great but it is not quite easy to be familiar with. For those who haven't read the article, it can be summarized as follows.

- Kubernetes is a great tool for running ML model on multiple training server efficiently. There are many attempts to utilze Kubernetes in ML field(for example, Kubeflow)
- However, it is quite hard to use for data scientist because of Kubernetes's steep learning curve. Kubernetes are made for software engineer, not data scientist.
- To make data scientist focus on ML thoroughly, it is important to have a abstract ML tool that data scientist can easily utilze Kubernetes.

I also recognize the same problem and thought about a better way to run ML model on Kubernetes. Finally I came up with some idea, which might not be the best solution though. But I want to share it with you.

## Reason why Kubernetes based ML tools is hard to use.

As the article point out, the reason why Kubernetes based ML tools such as Kubeflow is hard to use is two fold.

- Data scientist needs to **containerize their ML code.**
- Data scientist needs to **write k8s manifest file(YAML).**

Let's first take a look at containerization problem. Writing one's ML model into source code is not hard for them. The problem starts when they want to deploy their code on Kubernetes for training & serving. To deploy a program onto Kubernetes, containerization needs to be done first. This process is for software engineer not for DS. It might be unnatural for them. Writing Kubernetes manifest file is also unfamiliar. Data scientist needs to know about unnecessary k8s resource properties. There are some solutions for this.

## Solutions

#### 1. Requesting developer support.

Software engineers can support containerizing data scientist's ML code for them. However each developer has their own role, this method is not sustainable and drags down the whole model development cycle. Moreover unlike software development, model development process has more fine-grained incremental cycle, such as "write code and run right away". It could be exhausting if there is a dependency everytime they change their code.

#### 2. Learning how to use k8s.

As the previous article point out, everyone can not be a unicorn. Also according to single-responsibility principle, it might be cost-efficient to focus on each of what they are good at.(of course, this principle is for programming, not person.)

#### 3. Providing abstract ML tool.

The Determined AI's approach is to provide a abstracted way to run on Kubernetes through ML tool. They introduced their own ML tool product.

## My proposal

I agree with Determined AI's approach and I have a similar approach but little bit different. What if I can to this?

### Removing containerization process at all

The biggest pain point for data scientis to use Kubernetes based ML tool is containerizing their ML code. Then what if I could remove this step?

![what-the-hell](/assets/images/jupyterflow/whatthehell.jpg)

You might be thinking. What on earth does he talking about. In [Kubernetes website](https://kubernetes.io) first page, it states Kubernetes as "Production-Grade Container Orchestration". How could you remove containerization step in the middle of using Kubernetes as a ML platform?

I think, **"it is possible"** in **one condition**.

### Programming inside the container in the first place

Let me explain in more detail. Current problem is that data scientis should build their container by themself. Then, what if we make a container first and provide that containerized environment to data scientist? If data scientist can write their code inside the container, it would be much easier to run this code on Kubernetes. But how?

**How can we provide a containerized environment easily to data scientist?**

### JupyterHub on Kubernetes

I find out [JupyterHub](https://jupyterhub.readthedocs.io) as a solution. JupyterHub is a platform that each user can launch their own jupyter notebook server respectively. There are many methods to setup JupyterHub but my approach only works on [JupyterHub on Kubernetes](https://zero-to-jupyterhub.readthedocs.io/en/latest/#setup-jupyterhub). From now on, I wil refer to JupyterHub as JupyterHub on Kubernetes.

The architecture of JupyterHub is following.

![JupyterHub](/assets/images/jupyterflow/jupyterhub-arch.png)

It might look complicated but you only need to know `Spawners` and `Pod`. Everytime users launch their notebook, `Spawners` spawns new `Pod` on Kubernetes. Each `Pod` represents jupyter notebook for each user. Each user writes their code in their notebook. Each `Pod` is connected to NAS(Network Attached Storage) server so every written code gathers to NAS server.

- `Pod` == Jupyter notebook server
- ML code location == NAS server

### Kubernetes based ML tool

Let's take a further look at Kubernetes based ML tool. After finishing model development, now is the time to deploy one's code on Kubernetes. There are three parts to run the code. "Model execute environment, ML code, Model hyper-parameter"

```bash
venv/bin/python train.py epoch=10 dropout=0.5
```

In this script, the three parts are followings

- Model execute env: `virtualenv` python environment(`venv`)
- ML code: `train.py`
- Model H.P.: `epoch=10 dropout=0.5`

If we could send these information to Kubernetes, data scientist can use k8s without any troublesome works. Suprisingly, you can get these information on JupyterHub. Using `Pod`'s meta data from jupyter notebook is the key.

- Model execute env: jupyter notebook container image (`Pod.spec.containers.image`)
- ML code: ML code located on NAS volume (`Pod.spec.volumes`)
- Model H.P.: parameter fetched from ML tool

![JupyterHub](/assets/images/jupyterflow/newpod.png)

What if there is a ML tool which is smart enough to find the container image, ML code and H.P. from jupyter notebook `Pod` and constructs a Kubernetes manifest file and send it to k8s master, data scientist can run their ML code without **containerization job & writing k8s manifest**.

**Is there really such a tool that can do this?**

---

## JupyterFlow

### Introducing JupyterFlow

Introducing [JupyterFlow (https://jupyterflow.com)](https://jupyterflow.com), a better way to run your ML code on Kubernetes.

![jupyterflow](/assets/images/jupyterflow/side.png)

JupyterFlow is an Machine Learning CLI tool installed in jupyter notebook that can run your code on Kubernetes without containerization.

For example, write your code(`hello.py`, `world.py`) as you wish, run your code with `jupyterflow` CLI and JupyterFlow will create a training pipeline(Argo Workflow) for you.

```bash
# write code. hello.py & wrold.py
echo "print('hello')" > hello.py
echo "print('world')" > world.py

# install jupyterflow.
pip install jupyterflow

# in jupyterflow `>>` directive expresses container dependencies similar to Airflow.
jupyterflow run -c "python hello.py >> python world.py"
```

The results look like followings.

![results](https://raw.githubusercontent.com/hongkunyoo/jupyterflow/main/docs/images/intro.png)

The model development cycle without JupyterFlow:

- Data scientist writes their code.
- Containerize their code.
- Write k8s manifest file.
- Submit job through `kubectl` CLI.

![](/assets/images/jupyterflow/painful.jpg)

On the otherhand, the model development cycle with JupyterFlow looks like this:

- Spawn jupyter notebook.
- Write one's code on notebook
- Run your ML pipeline through `jupyterflow`

![](/assets/images/jupyterflow/solved.jpg)

그러면 나머지는 JupyterFlow가 알아서 똑똑하게 일을 처리합니다. 어떤가요, 꽤나 간편하지 않나요?

Then JupyterFlow will do the rest. How about it, isn't it lit?

### JupyterFlow Architecture

This is the architecture of JupyterFlow.

![jupyterflow Architecture](/assets/images/jupyterflow/architecture.png)

To use JupyterFlow, you need two main components. JupyterHub and [Argo Workflow](https://argoproj.github.io/argo). Argo Workflow is a [custom controller](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources) which let user to define dependencies between containers to make a workflow. There is a CRD(CustomResourceDefinition) called `Workflow` when you install Argo Workflow. Simple `Workflow` looks like this:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: hello-world-
spec:
  entrypoint: whalesay
  templates:
  - name: whalesay
    container:
      image: docker/whalesay
      command: [cowsay]
      args: ["hello world"]
      resources:
        limits:
          memory: 32Mi
          cpu: 100m
```

If you write this manifest, custom controller(argo workflow controller) reads it and creates containers sequentially based on the instruction. Users can check the result from Argo Web UI (argo-ui) provided by Argo Workflow.

JupyterFlow's role is to fetch jupyter notebook's meta data(image, volume) and H.P. from user, and write `Workflow` manifest similar to this example. Then Kubernetes will run ML pipeline for you.

### Compare with Zeppelin & Spark

Let's think about Zeppelin and Spark to help you understand.

![zeppelin spark](/assets/images/jupyterflow/zeppelin-spark.png)

Data engineer can use `Zeppelin` for interactive programming and submit Spark job through `spark-submit` even if they do not know all the details of Spark & Hadoop cluster.

![zeppelin spark](/assets/images/jupyterflow/jupyterflow-k8s.png)

Likewise, data scientist can use `Jupyter` for interactive modeling and submit k8s job through `jupyterflow` even if they do not know all the details of Kubernetes cluster.

If there is a difference, Zeppelin & Spark has its own job submitting mechanism(`spark-submit` script) while Jupyter & K8S don't have. So JupyterFlow might fill this gap.


### JupyterFlow Docs

For more details, please refer to following JupyterFlow documentations.

- [JupyterFlow Installation](https://jupyterflow.com/scratch/)
- [JupyterFlow How it works](https://jupyterflow.com/how-it-works/)
- [JupyterFlow Examples](https://jupyterflow.com/examples/basic/)
- [JupyterFlow Configuration](https://jupyterflow.com/configuration/)

---

Now with **JupyterFlow**, data scientist can write their code, run **right away** without any worries. How cool is it? Try it out yourself!

## Conclusion

JupyterFlow is my personal opensource project. It is still in its early stage which is imperfect and has some bugs. However, I believe JupyterFlow has its own great opportunity to change the ML tool market.
I am investing my spare time to improve this project. I have known that there is no other similar appoach like JupyterFlow and the market still has no De Facto Standard ML tools.
If you are interesting about this project, feel free to contact me with various channels.

- email: hongkunyoo (at) gmail
- [Github issue](https://github.com/hongkunyoo/jupyterflow/issues/new)
- Blog comments

Any comments, questions, request for trouble shooting, feedbacks and joining the project are welcome!
