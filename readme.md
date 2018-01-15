这是一个基于 hexo 的 blog，具体使用方法如下
---

## 自行安装 nodejs 
  官网：`https://nodejs.org`
  安装文件地址：`https://nodejs.org/dist/v8.9.4/node-v8.9.4.pkg`

## 安装 hexo
  官网地址 `https://hexo.io/`，文档可做这里找到
``` bash
$ npm install hexo-cli -g
```

## clone 本项目, 并安装 nodejs 依赖包
``` bash
$ git clone https://github.com/xuyuntech/blog.git
$ cd blog
$ npm install
```

## 新建 blog

``` bash
# hexo new $TITLE
$ hexo new "This is a blog title, a space is valid"
```

## 开启本地服务

``` bash
$ hexo server #默认 :4000 端口, http://localhost:4000 即可访问
```

标题可以包含空格，`new` 完之后，会在根目录下的 source/_posts 目录里出现对应的 `.md` 文件，blog 的内容写在这里 md 文件里即可

## 构建/推送 docker 容器

因为都是静态文件所以容器就是一个 nginx，可执行如下命令构建以及推送镜像文件：
>
  注意每次 `make push` 的时候要 `git pull` 一下，不然构建出来的镜像会把别人的覆盖掉

``` bash
#镜像地址可以在 Makefile 里的 IMAGE_NAME 看到，或者修改为您自己的镜像地址
$ make container  #构建镜像
$ make push       #推送镜像
$ make            #同 make 命令
```
