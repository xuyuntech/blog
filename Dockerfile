FROM index.boxlinker.com/library/nginx:latest

# Set a working directory
WORKDIR /usr/share/nginx/html

COPY ./public .
