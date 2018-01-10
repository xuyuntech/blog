
IMAGE_TAG=${shell git describe --tags --long}
IMAGE_NAME=index.boxlinker.com/xuyuntech/blog:${IMAGE_TAG}

all: push

container:
	git pull
	hexo generate
	docker build -t ${IMAGE_NAME} .

push: container
	docker push ${IMAGE_NAME}