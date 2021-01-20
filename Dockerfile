FROM hashicorp/terraform:light

WORKDIR /app
COPY . .

ENTRYPOINT [ "./docker-entrypoint.sh" ]

CMD [ "terraform", "plan" ]