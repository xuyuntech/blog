
IMAGE_TAG=${shell git describe --tags --long}
IMAGE_NAME=index.boxlinker.com/xuyuntech/blog:${IMAGE_TAG}

all: push

container:
	hexo generate
	docker build -t ${IMAGE_NAME} .

push: container
	docker push ${IMAGE_NAME}

test: container
	docker run -it --rm -p 4000:80 ${IMAGE_NAME}