ARG TF_VERSION

FROM hashicorp/terraform:${TF_VERSION}

# Get the latest yq v4 from the edge mirror per https://mikefarah.gitbook.io/yq/#alpine-linux
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

RUN apk update && \
    apk upgrade && \
    apk add --no-cache gettext curl yq~=4

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
        unzip awscliv2.zip && \
        ./aws/install

WORKDIR /app
COPY main.tf variables.tf scripts/ ./
RUN chmod a+x ./*.sh

ENTRYPOINT ["./plan.sh"]
