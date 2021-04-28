# Web Lambdas Terraform

Terraform configs for building Lambdas in AWS and associating those with API Gateway or CloudWatch.

### API Gateway

The presence of a `TF_VAR_apigw_id` variable here will trigger the creation of an API Gateway resource for this Lambda. You will also need to specify `TF_VAR_apigw_root_resource_id` and `TF_VAR_apigw_execution_arn` for the terraform to create this association successfully.

### CloudWatch

The presence of a `TF_VAR_schedule_expression` variable here will trigger the creation of a CloudWatch event-triggered cronjob.

## Service User

The Lambda service username is `web-lambdas-api-gateway` and the permissions are based on this naming scheme, so all new Lambda functions will have the following naming convention:

```
web-lambdas-api-gateway-{FUNCTION_NAME}
```

## Usage

To manage Lambda with this config add the following files:

### `.lambdafiles`

This should include a list of the files/folders you want to include in the Lambda function:
```
common/
config/
node_modules/
handler.js
package.json
yarn.lock
```

### `.tf_env_vars`

This should include a [Terraform object](https://www.terraform.io/docs/configuration/types.html#object-) of application level variables. They are [formatted for command-line injection](https://www.terraform.io/docs/commands/environment-variables.html#tf_var_name) (hence they look like JSON). You can include interpolated variable secrets from the CircleCI env, etc.:
```
{"WORLDCAT_API_KEY":"$WORLDCAT_API_KEY"}
```

### `Dockerfile`

Make sure the Lambda function Dockerfile has some way to build a production-only version (see the PRODUCTION build_arg below as an example) so that the build image only has the production node modules for packaging into Lambda. Also install the `zip` utility:

```
FROM node:12-alpine

ARG production

ENV INSTALL_PATH /app

WORKDIR $INSTALL_PATH

COPY package.json yarn.lock /tmp/
RUN cd /tmp && yarn install --frozen-lockfile --ignore-optional $(if [[ ! -z $production ]]; then echo "--production"; fi) \
  && mkdir -p $INSTALL_PATH \
  && cd $INSTALL_PATH \
  && cp -R /tmp/node_modules $INSTALL_PATH \
  && rm -rf /tmp/* \
  && apk add zip
COPY . .
```

### `deploy/`

Create two files in a `deploy/` directory:

#### `Dockerfile`

Create a container that starts from our `web-lambdas-terraform` terraform modules and copies in a local entrypoint to configure the backend for this specific function:

```
FROM quay.io/nyulibraries/web-lambdas-terraform:master

COPY docker-entrypoint.sh .
RUN chmod a+x ./docker-entrypoint.sh

ENTRYPOINT [ "./docker-entrypoint.sh" ]

CMD ["terraform", "plan"]
```

#### `docker-entrypoint.sh`

The Docker entrypoint sets up the backend with variables from the CircleCI context:

```
#!/bin/sh
set -e

terraform init -backend-config="bucket=${BACKEND_BUCKET}" \
               -backend-config="key=${BACKEND_KEY}" \
               -backend-config="region=${BACKEND_REGION}" \
               -backend-config="dynamodb_table=${BACKEND_DYNAMODB_TABLE}"

exec "$@"
```

### `docker-compose.yml`

Pass through all the necessary default variables to a reusable yaml module in your docker-compose.yml:

**Note:** These are all defined in a CircleCI context.

```
x-environment: &x-environment
  BACKEND_BUCKET: 
  BACKEND_REGION: 
  BACKEND_DYNAMODB_TABLE: 
  AWS_ACCESS_KEY_ID: 
  AWS_SECRET_ACCESS_KEY: 
  AWS_DEFAULT_REGION: 
  TF_VAR_lambda_exec_arn: 
  TF_VAR_apigw_id: 
  TF_VAR_apigw_root_resource_id: 
  TF_VAR_apigw_execution_arn: 
  TF_VAR_lambda_s3_bucket: 
  TF_VAR_aws_username: 
  TF_VAR_apigw_stage:
  TF_VAR_lambda_version:
  TF_VAR_environment_variables:
```

Create services for building and deploying the lambda:

**Note:** These env vars need to be defined per function.

```
services:
...
  terraform_deploy:
    build:
      context: deploy/
    command: ["terraform", "apply", "-auto-approve"]
    environment:
      <<: *x-environment
      BACKEND_KEY: lambdas/tf_state/{FUNCTION_NAME}
      TF_VAR_lambda_function_name: {FUNCTION_NAME}
      TF_VAR_lambda_description: {USEFUL_DESCRIPTION_OF_FUNCTION}
      TF_VAR_lambda_handler: handler.persistent
      TF_VAR_lambda_runtime: nodejs12.x
      TF_VAR_lambda_method: GET
      TF_VAR_lambda_memory_limit: 1024

  build_lambda:
    image: {FUNCTION_NAME}-build
    build: 
      context: .
      dockerfile: Dockerfile
      args:
        production: "true"
    command: sh -c 'mkdir dist; cat .lambdafiles | xargs zip -r -9 -q ./dist/{FUNCTION_NAME}.zip'
    labels:
      - 'nyulibraries.app={FUNCTION_NAME}'
  ```

### `.circleci/config.yml`

Add circle jobs for building the lambda function with zip and deploying with terraform:

```
...
s3_deploy: &s3_deploy
  aws-s3/sync:
    from: dist
    to: 's3://${TF_VAR_lambda_s3_bucket}/{FUNCTION_NAME}/${CIRCLE_SHA1}'
    arguments: |
      --exclude "*" \
      --include "{FUNCTION_NAME}.zip" \
      --delete
    overwrite: true

zip: &zip
  run:
    name: Zip Lambda files
    command: docker-compose run build_lambda

get_lambda_zip: &get_lambda_zip
  run:
    name: Retrieve zipped lambda from container
    command: |
      docker cp $(docker ps -aq --filter 'label=nyulibraries.app={FUNCTION_NAME}'):/app/dist .

terraform_deploy: &terraform_deploy
  run:
    name: Deploy the Lambda to AWS via Terraform
    command: |
      apk add gettext
      export TF_VAR_lambda_version=${CIRCLE_SHA1}
      export TF_VAR_environment_variables=$(envsubst < .tf_env_vars)
      docker-compose run terraform_deploy

version: 2.1
orbs:
  aws-s3: circleci/aws-s3@1.0.11
jobs:
  build-lambda:
    <<: *docker-defaults
    steps:
      - checkout
      - setup_remote_docker:
          version: 19.03.13
      - <<: *build_docker
      - <<: *zip
      - <<: *get_lambda_zip
      - <<: *s3_deploy
  
  # Replacement Lambda logic
  deploy-lambda:
    <<: *docker-defaults
    steps:
      - checkout
      - setup_remote_docker:
          version: 19.03.13
      - <<: *auth_quay
      - <<: *terraform_deploy
...
workflows:
  version: 2
  build-test-and-deploy:
    jobs:
      - test
      - build-lambda:
          context: web-lambdas-api-gateway-dev
          filters:
            branches:
              ignore: master
          requires:
            - test
      - deploy-lambda:
          context: web-lambdas-api-gateway-dev
          filters:
            branches:
              ignore: master
          requires:
            - build-lambda
```

**Note:** That before deploy we set the following two variables inline:

```
export TF_VAR_lambda_version=${CIRCLE_SHA1}
export TF_VAR_environment_variables=$(envsubst < .tf_env_vars)
```

The version sha matches the uploaded zip in S3 to the lambda we want to deploy. The usage of `envsubst` here allows us to interpolate CircleCI secrets into the terraform object.

## TODO:

- Add `aws_lambda_alias` for versioning, e.g.:

```
resource "aws_lambda_alias" "test_lambda_alias" {
  name             = "my_alias"
  description      = "a sample description"
  function_name    = aws_lambda_function.lambda_function_test.arn
  function_version = "1"

  routing_config {
    additional_version_weights = {
      "2" = 0.5
    }
  }
}
```

- Add configuration for Lambda@Edge functions and integration with CloudFront
