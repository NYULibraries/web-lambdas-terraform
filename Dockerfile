ARG TF_VERSION

FROM hashicorp/terraform:${TF_VERSION}

WORKDIR /app
COPY main.tf variables.tf ./

CMD [ "terraform", "plan" ]