# Web Lambdas Terraform

Terraform configs for building Lambdas in AWS and associating those with API Gateway or CloudWatch.

## Versioning this repos

We version this repository based on the Terraform version and the patch number based on our functionality changes. We document this in the `.env` file . So given the following `.env` file:

```
TF_VERSION='0.15.0'
PATCH='4'
```

We will manually create a release called `0.15.0-4` that will trigger the creation of an image called:

```
quay.io/nyulibraries/web-lambdas-terraform:v0.15.0-4
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

See [wiki](./wiki) for detailed usage examples.

## Debugging

When a lambda deploy fails, it may need to be manually resuscitated from an error state. The following are recipes using for clearing out these error states. Be sure to substitute the correct environment variables.

When a deploy fails after placing a lock but before clearing it, manually clear the lock from dynamodb:

```
aws dynamodb list-tables | jq '.TableNames[]'
aws dynamodb scan --table-name $LOCK_TABLE_NAME | jq '.Items[].LockID.S'
aws dynamodb delete-item --table-name $LOCK_TABLE_NAME --key='{"LockID":{"S": "$TF_STATE_BUCKET_NAME/lambdas/tf_state/$FUNCTION_NAME"}}'
```

When a tf state becomes corrupted, delete the corresponding tf state file in S3:

```
aws s3 ls s3://$TF_STATE_BUCKET_NAME
aws s3 rm s3://$TF_STATE_BUCKET_NAME/lambdas/tf_state/$FUNCTION_NAME
```

Additionally, after clearing the ft state, the old function and log group must be destroyed:

```
aws lambda list-functions | jq '.Functions[].FunctionName'
aws lambda delete-function --function-name web-lambdas-api-gateway-$FUNCTION_NAME
aws logs delete-log-group --log-group-name /aws/lambda/web-lambdas-api-gateway-$FUNCTION_NAME
```
