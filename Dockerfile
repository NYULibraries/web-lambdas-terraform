FROM hashicorp/terraform:light

WORKDIR /app
COPY . .

CMD [ "terraform", "plan" ]