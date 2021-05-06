ARG TF_VERSION

FROM hashicorp/terraform:${TF_VERSION}

# Get the latest yq v4 from the edge mirror per https://mikefarah.gitbook.io/yq/#alpine-linux
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

RUN apk update && \
    apk upgrade && \
    apk add --no-cache gettext yq~=4

WORKDIR /app
COPY main.tf variables.tf scripts/ ./
RUN chmod a+x ./*.sh

ENTRYPOINT ["./plan.sh"]
