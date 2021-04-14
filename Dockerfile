ARG TF_VERSION

FROM hashicorp/terraform:${TF_VERSION}

WORKDIR /app
COPY . .

CMD [ "terraform", "plan" ]