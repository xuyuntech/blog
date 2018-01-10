---
title: Kubernetes 的 service mesh -- 第六部分：轻松预发布微服务
date: 2018-01-10 12:56:13
tags:
- Kubernetes
- Service mesh
---

在将新代码发布到生产环境之前， 预发布操作是构建一个可靠的、低宕机时间的软件系统的关键组成部分。但是，在微服务体系下，由于拆分出来的许许多多的微服务之间的依赖关系随着微服务数量成指数倍增长，从而增加了预发布操作的复杂性。在这篇文章里，我们将为您介绍 linkerd 的最强大的功能之一，单个请求路由（per-request routing），通过它，您将可以非常轻松的处理这个问题。

注意：这是关于Linkerd、Kubernetes和service mesh的系列文章其中一篇，其余部分包括：

* Top-line service metrics
* Pods are great, until they’re not
* Encrypting all the things
* Continuous deployment via traffic shifting
* Dogfood environments, ingress, and edge routing
* Staging microservices without the tears (本文)
* Distributed tracing made easy
* Linkerd as an ingress controller
gRPC for fun and profit
* The Service Mesh API
* Egress
* Retry budgets, deadline propagation, and failing gracefully
* Autoscaling by top-line metrics

本文所阐述的概念也可通过观看视频来了解，具体请查看 [Alex Leong](https://twitter.com/adlleong) 的 meetup 博客 [Microservice Staging without the Tears.](https://youtu.be/y0D5EAXvUpg)

Linkerd 是云原生应用的一种服务网格（service mesh）。它作为对应用透明的网络代理层通过封装服务间的调用为应用提供如：低延迟负载均衡（latency-aware load balancing）、链接重试（retry budgets）及终止（deadlines）、熔断机制（circuit breaking）等特性来提高应用的适应性（application resilience）。

除了能够提高应用的适应性，linkerd 也能够提供强大的路由语言来改变服务在运行时请求流的方式。这篇文章我们将为您展示 linkerd 如何做到这一点，不仅仅是全局范围，更精细到每一个基础请求。也将为您展示每一个请求路由如何被用来创建临时的预发布环境，从而允许在生产环境上下文中测试新代码而不用真正将其发布到生产环境里。最后，将为您介绍（in contrast to staging with a dedicated staging environment）临时的预发布环境如何做到既不需要与其他团队的协调工作，也不需要花费时间精力来同时保持多个部署环境。

# 为什么要预发布

为什么预发布如此重要？在现代软件开发当中，代码需要经过一系列预先设计好的实践路线来保证正确性：代码走查（code review），单元测试（unit tests），集成测试（integration tests）等等。经过这些流程之后，需要开始估算代码的表现了：新代码运行的速度如何？高负载下的表现如何？在运行时与其他服务以及相关依赖的交互表现如何？

预发布系统就可以回答这些问题。预发布的基本原则就是越接近生产环境，系统就越切实可行。因此，就像测试环节中的 mocks 和 stub 一样，对于预发布，我们期望能够运行真实的服务。最好的预发布环境就是和生产环境完全一样。

# 为什么微服务的预发布很难？

如果你的应用由许多微服务构成，那么微服务之间的通信交互就会变成像端到端应用行为一样的重要组成部分。其实，应用拆分的越细，那么在运行时应用之间的交互就会越复杂，而此时应用的表现已经不仅仅是每个微服务自己的问题了，很大程度上取决于微服务之间的交互。

实际上，增加微服务的数量不仅仅增加了正确预发布的重要性，也同时增加了实现这一点的难度。我们来看几个常用的预发布方法，以及为什么在微服务环境下这些方法都会变得比较困难。

预发布的常规方法是共享预发布集群，而在这个集群里，除了你的预发布服务之外其他人的预发布服务也在这里。这种方式的弊端就是没有隔离。如下图展示，如果 Alex 把他的服务发布了上去但是出了点问题，整个链条中就很难判断出问题源的所在--因为问题可能出现在 Alex、Alice 或者 Bob 的服务上，又或者干醋就是数据库里的数据有问题。这样预发布环境与生产环境的同步就会非常困难，尤其是当服务、团队以及发行版本数量庞大的时候。

![](https://buoyant.io/wp-content/uploads/2017/07/buoyant-1_everyone.png)

另一种共享环境成为“私人”或者单个开发者的预发布集群，可以解决隔离的问题。在这个例子中，每一个开发者可以根据需要来操作预发布集群。预发布一个服务需要同时预发布这个服务的上游以及下游服务也包括相关的依赖，从而可以保证预发布的有效性。（比如，在下图中，Alex 必须先发布 Web FE 和 API 服务来保证他的 Foo 服务可以正常运行。）然而，根据需要来维护以及部署部分应用拓扑结构会非常复杂，尤其是当应用拓扑结构非常大而且服务又有独立的部署模型。

![](https://buoyant.io/wp-content/uploads/2017/07/buoyant-2_personal.png)

上面说的是一种极其简单的部署新代码到生产环境并且有问题时可以回滚的方式。当然了，这种方式很有风险，而且不能处理部分应用类型，比如：金融事务。虽然还有很多其他的部署方法，但是本文我们将介绍一种直接的、轻松的方式。

# 一种更好的方式

使用 Linkerd 创建临时的预发布环境，就可以很好的避免以上提到的弊端。实际上，在 Twitter 里 Finagle 路由层作为linkerd 的底层，  他的主要动机就是解决这个问题。

我们来看一下 Alex 的 Foo 服务。如果，我们不另外部署一个隔离的环境，而是仅仅使用 Foo 的预发布版本替代 Foo 的生产版本，然后通过一个特殊的请求来访问它呢？针对生产环境，这将能够确保 Foo 的预发布版本的安全性，而且除了 Foo 预发布版本之外也不需要部署其他的任何东西。这就是临时预发布环境的本质。而此时，开发者身上的任务一下就轻松了：Alex 只需要预发布他的新代码，然后在 ingress 请求的 header 上设置一个标记就可以了，就这么简单！

![](https://buoyant.io/wp-content/uploads/2017/07/buoyant-3_request_path.png)

Linkered 的单个请求路由可以帮助我们实现这种方式。通过 linkerd 的请求代理，可以给特定的请求上设置一个 `l5d-dtab` 的 header 。这个 header 可以允许你设置路由规则（叫做  in Finagle parlance, “[Dtabs](https://linkerd.io/in-depth/dtabs/?__hstc=9342122.3f969c5b28d43c74b3d9bc02ae83d261.1507297530327.1507297530327.1507297530327.1&__hssc=9342122.2.1507297530327&__hsfp=1136196569)”）。比如，dtab 规则 `/s/foo => /srv/alex-foo` 可以覆盖 Foo 服务生产环境的规则。给单个请求添加这个可以使得请求直接到达 Alex 的 Foo 服务，也仅仅作用与这一个请求。Linkerd 可以拦截这个规则，所以生产环境里任何使用 Alex 的 Foo 服务的地方都可以正确的处理。

![](https://buoyant.io/wp-content/uploads/2017/07/buoyant-4_override.png)

# 试一下这个功能吧

[Service Mesh for Kubernetes](https://buoyant.io/a-service-mesh-for-kubernetes-part-i-top-line-service-metrics/) 系列文章的读者应该已经知道我们有一个 demo [our dogfood blog post](https://buoyant.io/a-service-mesh-for-kubernetes-part-v-dogfood-environments-ingress-and-edge-routing/)。我们部署过一个 `world-v2` 服务，并且可以通过设置重定向路由规则发送单个的 dogfood 请求。现在我们可以使用相同机制来做些别的事情：创建一个临时的预发布环境。

部署一个服务的两个版本，再使用 linkerd 的路由功能在部署到生产环境之前来测试新服务。我们先部署 `hello` 和 `world-v1` 服务来作为我们的生产环境服务，然后再创建一个临时的预发布环境来测试 world 服务的新版本 `world-v2`。

## 第一步：部署 LINKERD 和 HELLO-WORLD 服务

我们使用前一篇文章里部署的 hello world 服务。它由 hello 服务调用 world 服务组成。这些应用通过通过 [Kubernetes downward API ](https://kubernetes.io/docs/tasks/inject-data-application/downward-api-volume-expose-pod-information/) 提供的根据 nodeName 来找到 Linkerd 。如果你不确定你的集群是否支持 nodeName, 你可以运行如下命令：
```
kubectl apply -f https://raw.githubusercontent.com/linkerd/linkerd-examples/master/k8s-daemonset/k8s/node-name-test.yml
```

然后查看一下日志：
```
kubectl logs node-name-test
```

如果你看到了 ip 就表示成功了。然后再通过如下命令部署 hello world 应用：
```
kubectl apply -f https://raw.githubusercontent.com/linkerd/linkerd-examples/master/k8s-daemonset/k8s/hello-world.yml
```

如果你看到了 “server can’t find …” 错误，那就部署 hello-world 的 legacy 版本，这个版本依赖 hostIP 而不是 nodeName：
```
kubectl apply -f https://raw.githubusercontent.com/linkerd/linkerd-examples/master/k8s-daemonset/k8s/hello-world-legacy.yml
```

然后我们来部署生产环境（linkerd 和 hellow 以及 world 服务）:
```
$ kubectl apply -f https://raw.githubusercontent.com/linkerd/linkerd-examples/master/k8s-daemonset/k8s/linkerd-ingress.yml
```

再来部署 linkerd 和预发布版本的服务 world-v2 ,这个服务会返回 "earth" 而不是 “world”。
```
$ kubectl apply -f https://raw.githubusercontent.com/linkerd/linkerd-examples/master/k8s-daemonset/k8s/linkerd-ingress.yml
$ kubectl apply -f https://raw.githubusercontent.com/linkerd/linkerd-examples/master/k8s-daemonset/k8s/world-v2.yml
```

## 第二步：在临时预发布环境里使用单个请求覆盖功能

现在，我们运行了 world-v2 服务，来测试一下是否通了。我们期望的是请求到达的是 `world-v2` 而不是 `world-v1`。首先，先运行一个没有更改的请求，这个请求会走默认的路径。（你可能需要等待 l5d 的 external IP 出现）：
```
$ INGRESS_LB=$(kubectl get svc l5d -o jsonpath="{.status.loadBalancer.ingress[0].*}")
$ curl -H "Host: www.hello.world" $INGRESS_LB
Hello (10.196.2.232) world (10.196.2.233)!!
```

如果外部负载均衡不起作用，可以使用 hostIP：
```
INGRESS_LB=$(kubectl get po -l app=l5d -o jsonpath="{.items[0].status.hostIP}"):$(kubectl get svc l5d -o 'jsonpath={.spec.ports[0].nodePort}')
$ curl -H "Host: www.hello.world" $INGRESS_LB
Hello (10.196.2.232) world (10.196.2.233)!!
```

如我们所料，返回了 `Hello (......) World (.....)`，这说明走的是生产环境。

那如何来请求预发布环境呢？我们需要做的就是发送给一个带有覆盖 header 的请求到生产环境中去，它就会访问到 `world-v2` 服务！由于 header 的设置，请求会走 `/srv/world-v2` 而不是 `/host/world`。
```
$ curl -H "Host: www.hello.world" -H "l5d-dtab: /host/world => /srv/world-v2;" $INGRESS_LB
Hello (10.196.2.232) earth (10.196.2.234)!!
```

我们看到了 "earch" 而不是 “world”! 这个请求已经成功的到达了 world-v2 服务，而且是在生产环境里，并且没有任何代码变更或者额外的部署工作。就是这样，预发布就变的 so easy 了。

Linkerd 的 [Dtabs](https://linkerd.io/in-depth/dtabs/?__hstc=9342122.3f969c5b28d43c74b3d9bc02ae83d261.1507297530327.1507297530327.1507297530327.1&__hssc=9342122.2.1507297530327&__hsfp=1136196569) 和 [routing](https://linkerd.io/in-depth/routing/?__hstc=9342122.3f969c5b28d43c74b3d9bc02ae83d261.1507297530327.1507297530327.1507297530327.1&__hssc=9342122.2.1507297530327&__hsfp=1136196569) 的文档非常健全。在开发中，你可以使用 linkerd 的 “dtab playground” `http://$INGRESS_LB:9990/delegator`。By going to the “outgoing” router and testing a request name like /http/1.1/GET/world, you can see linkerd’s routing policy in action.

# 实践

在实践中，这种方式有一些需要注意的地方。首先，往生产环境的数据库里写东西时必须要小心。相同的 dtab 覆盖机制可以用来发送任何写预发布数据库的请求，或者在一些应用级别里直接 /dev/null。强烈建议，这些覆盖规则不能手动生成，以免发生不必要的错误，毕竟是在生产环境里！

其次，你的应用需要参考 [linkerd's context headers](https://linkerd.io/features/routing/?__hstc=9342122.3f969c5b28d43c74b3d9bc02ae83d261.1507297530327.1507297530327.1507297530327.1&__hssc=9342122.2.1507297530327&__hsfp=1136196569#per-request-routing)。

最后非常重要的一点，避免外界可以设置 `l5d-dtab` 请求头。[setting up a dogfood environment in Kubernetes](https://buoyant.io/a-service-mesh-for-kubernetes-part-v-dogfood-environments-ingress-and-edge-routing/) 这篇文章里我们阐述了一个 nginx 的 ingress 样例配置，可以有效的去掉不认识的请求头。

# 结尾

我们举例了如何通过 linkerd 设置单个请求路由规则来达到创建临时预发布环境的问题。通过这种方式，我们可以在生产环境里预发布服务，而不需要更改现有代码，也不需要其他额外的预发布环境资源（当然除了预发布服务自己），同时也不需要处理预发布与生产这两个平行环境。对于微服务众多的应用来说，这种方式提供了一种发布到生产环境之前的简单、高效的预发布方式。
Note: 还有许多种支持不同特性的不同环境来部署 Kubernetes，想要了解更多点击[这里](https://discourse.linkerd.io/t/flavors-of-kubernetes?__hstc=9342122.3f969c5b28d43c74b3d9bc02ae83d261.1507297530327.1507297530327.1507297530327.1&__hssc=9342122.2.1507297530327&__hsfp=1136196569)。

关于更多在 Kubernetes 里运行 linkerd 或者你有任何问题，可以访问我们的 [linkerd community Slack](https://slack.linkerd.io/?__hstc=9342122.3f969c5b28d43c74b3d9bc02ae83d261.1507297530327.1507297530327.1507297530327.1&__hssc=9342122.2.1507297530327&__hsfp=1136196569)，也可以在 [Discourse](https://discourse.linkerd.io/?__hstc=9342122.3f969c5b28d43c74b3d9bc02ae83d261.1507297530327.1507297530327.1507297530327.1&__hssc=9342122.2.1507297530327&__hsfp=1136196569) 上提问，或者直接 [联系我们](https://linkerd.io/overview/help/?__hstc=9342122.3f969c5b28d43c74b3d9bc02ae83d261.1507297530327.1507297530327.1507297530327.1&__hssc=9342122.2.1507297530327&__hsfp=1136196569)!