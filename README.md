# Web Lambdas Terraform

Terraform configs for building Lambdas in AWS and associating those with API Gateway or CloudWatch.

## Versioning this repos

We version this repository based on the Terraform version we're using and the patch number based on our functionality changes. We document this in the `.env` file. So given the following `.env` file:

```
TF_VERSION='0.15.0'
PATCH='0'
```

We will manually create a release called `v0.15.0-0` that will trigger the creation of an image called:

```
quay.io/nyulibraries/web-lambdas-terraform:v0.15.0-0
```

### API Gateway (i.e. REST API)

The presence of a `TF_VAR_apigw_id` variable here will trigger the creation of an API Gateway resource for this Lambda. You will also need to specify `TF_VAR_apigw_root_resource_id` and `TF_VAR_apigw_execution_arn` for the terraform to create this association successfully.

### CloudWatch Events (i.e. cron job)

The presence of a `TF_VAR_lambda_cw_schedule_expression` variable here will trigger the creation of a CloudWatch event-triggered cronjob.

## Service User

The Lambda service username is `web-lambdas-api-gateway` and the permissions are based on this naming scheme, so all new Lambda functions will have the following naming convention:

```
web-lambdas-api-gateway-{FUNCTION_NAME}
```

## Usage

To manage Lambda with this config add the following files to your function repository:

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

**Note:** Make sure you edit this to be specific to your lambda function files, e.g. a Ruby Lambda would have a `handler.rb` instead of a `handler.js` and a `Gemfile` instead of a `package.json`, etc.

### `.tf_env_vars`

This should include a [Terraform object](https://www.terraform.io/docs/configuration/types.html#object-) of application-level variables. They are [formatted for command-line injection](https://www.terraform.io/docs/commands/environment-variables.html#tf_var_name) (hence they look like POJOs). You can include interpolated variable secrets from the CircleCI env, etc.:

```
{"WORLDCAT_API_KEY":"$WORLDCAT_API_KEY","VAR2":"$VAR2",...}
```

### `deploy.yml`

Create a `deploy.yml` config file that specifies the function-specific environment vars. You can also use this file to specify multiple functions from the same codebase:

```
default_function:
  BACKEND_KEY: lambdas/tf_state/{FUNCTION_NAME}
  TF_VAR_lambda_function_name: {FUNCTION_NAME}
  TF_VAR_lambda_description: "A brief description of this lambda"
  TF_VAR_lambda_handler: handler.{function}
  TF_VAR_lambda_runtime: nodejs12.x|ruby2.5|etc
  TF_VAR_lambda_method: GET|POST
  TF_VAR_lambda_memory_limit: 128
  # Optional if you are using cron trigger instead of 
  # API Gateway to call the Lambda
  TF_VAR_lambda_cw_schedule_expression: "rate(10 minutes)"
  ...
  # Additional function-specific variables can be injected here and included in 
  # the Lambda by inclusino in the .tf_env_vars
  VAR1: ...
```

### `Dockerfile.node` or `Dockerfile.build` (naming depending on your config)

Make sure the Lambda function Dockerfile has some way to build a production-only version (see the PRODUCTION build_arg below as an example) so that the build image only has the production node modules for packaging into Lambda. **This is important for keeping the packages small**. Also install the `zip` utility:

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

### `Dockerfile.deploy`

Create a container that starts from our `web-lambdas-terraform` terraform modules and copies in the local config files:

```
FROM quay.io/nyulibraries/web-lambdas-terraform:v0.15.0-0

COPY .tf_env_vars deploy.yml ./
```

### `docker-compose.deploy.yml`

Pass through all the necessary default variables to a reusable yaml module in your `docker-compose` and create services for building, creating and destroying functions.

**Note:** The environment variables in `x-environment` are all defined in a CircleCI context or directly in the `docker-compose` but are relevant for all functions in the repository as opposed to the `deploy.yml` variables, which are function specific.

```
version: "3.7"

x-environment: &x-environment
  BACKEND_BUCKET: 
  BACKEND_REGION: 
  BACKEND_DYNAMODB_TABLE: 
  AWS_ACCESS_KEY_ID: 
  AWS_SECRET_ACCESS_KEY: 
  AWS_DEFAULT_REGION: 
  SLACK_URL:
  TF_VAR_lambda_exec_arn: 
  TF_VAR_lambda_s3_bucket: 
  TF_VAR_aws_username: 
  TF_VAR_lambda_version:
  TF_VAR_environment_variables:
  # Optional
  TF_VAR_lambda_parent_function_name: {FUNCTION_NAME}

services:

  fn_create:
    image: {FUNCTION_NAME}-create
    build:
      context: .
      dockerfile: Dockerfile.deploy
    environment:
      <<: *x-environment
    entrypoint: ["./create.sh"]
  
  fn_destroy:
    image: {FUNCTION_NAME}-destroy
    build:
      context: .
      dockerfile: Dockerfile.deploy
    environment:
      <<: *x-environment
    entrypoint: ["./destroy.sh"]

  build_lambda:
    image: {FUNCTION_NAME}-build
    build: 
      context: .
      dockerfile: Dockerfile.node
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
    command: docker-compose -f docker-compose.deploy.yml run build_lambda

get_lambda_zip: &get_lambda_zip
  run:
    name: Retrieve zipped lambda from container
    command: |
      docker cp $(docker ps -aq --filter 'label=nyulibraries.app={FUNCTION_NAME}'):/app/dist .

terraform_deploy: &terraform_deploy
  run:
    name: Deploy the Lambda to AWS via Terraform
    command: |
      export TF_VAR_lambda_version=${CIRCLE_SHA1}
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
      # Replicated for production with production contexts
```

**Note:** That before deploy we set the following variable inline:

```
export TF_VAR_lambda_version=${CIRCLE_SHA1}
```

The version sha matches the uploaded zip in S3 to the lambda we want to deploy.

### Multiple functions from the same repos

If you have multiple functions from a single Lambda code repository you just need to make a few changes:

#### Add a parent function name

To `docker-compose` under `x-environment` add:

```
TF_VAR_lambda_parent_function_name: {PARENT_FUNCTION_NAME}
```

#### Change your `build_lambda` function in `docker-compose`

```
  build_lambda:
    image: {PARENT_FUNCTION_NAME}-build
    build: 
      context: .
      dockerfile: Dockerfile.node
      args:
        production: "true"
    command: sh -c 'mkdir dist; cat .lambdafiles | xargs zip -r -9 -q ./dist/{PARENT_FUNCTION_NAME}.zip'
    labels:
      - 'nyulibraries.app={PARENT_FUNCTION_NAME}'
```

#### Change your `.circleci` config

```
s3_deploy: &s3_deploy
  aws-s3/sync:
    from: dist
    to: 's3://${TF_VAR_lambda_s3_bucket}/{PARENT_FUNCTION_NAME}/${CIRCLE_SHA1}'
    arguments: |
      --exclude "*" \
      --include "{PARENT_FUNCTION_NAME}.zip" \
      --delete
    overwrite: true

get_lambda_zip: &get_lambda_zip
  run:
    name: Retrieve zipped lambda from container
    command: |
      docker cp $(docker ps -aq --filter 'label=nyulibraries.app={PARENT_FUNCTION_NAME}'):/app/dist .
```

#### Add multiple entries to your `deploy.yml`

```
func1:
  BACKEND_KEY: lambdas/tf_state/{FUNCTION_NAME}
  TF_VAR_lambda_function_name: {FUNCTION_NAME}
  TF_VAR_lambda_description: "A brief description of this lambda"
  TF_VAR_lambda_handler: handler.{function}
  TF_VAR_lambda_runtime: nodejs12.x|ruby2.5|etc
  TF_VAR_lambda_method: GET|POST
  TF_VAR_lambda_memory_limit: 128
  # Optional if you are using cron trigger instead of 
  # API Gateway to call the Lambda
  TF_VAR_lambda_cw_schedule_expression: "rate(10 minutes)"
func2:
  ...
func3:
  ...
```

## TODO:

- Add configuration for Lambda@Edge functions and integration with CloudFront
