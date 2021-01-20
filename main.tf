terraform {
  # Use AWS
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.24.1"
    }
  }

  # Backend for TF state is S3
  backend "s3" {
  }
}

# Some local variables for reuse
locals {
	lambda_function_name = var.lambda_function_name
  lambda_s3_bucket = var.lambda_s3_bucket
  lambda_full_name = "${var.aws_username}-${local.lambda_function_name}"
  lambda_version = var.lambda_version
  lambda_zip = "${local.lambda_function_name}.zip"
  lambda_handler = var.lambda_handler
  lambda_runtime = var.lambda_runtime
  lambda_exec_arn = var.lambda_exec_arn
  lambda_method = var.lambda_method
  apigw_id = var.apigw_id
  apigw_root_resource_id = var.apigw_root_resource_id
  apigw_execution_arn = var.apigw_execution_arn
  apigw_stage = var.apigw_stage
  lambda_memory_size = var.lambda_memory_size
  lambda_cw_schedule_expression = var.lambda_cw_schedule_expression
}

# The Lambda Function itself
resource "aws_lambda_function" "lambda_fn" {
  function_name = local.lambda_full_name

  # The bucket name as created previously
  s3_bucket = local.lambda_s3_bucket
  s3_key    = "${local.lambda_function_name}/${local.lambda_version}/${local.lambda_zip}"

  # "main" is the filename within the zip file (main.js) and "handler"
  # is the name of the property under which the handler function was
  # exported in that file.
  handler = local.lambda_handler
  runtime = local.lambda_runtime

  role = local.lambda_exec_arn

  memory_size = local.lambda_memory_size

  environment {
    variables = merge(var.environment_variables, map("ManagedBy", "Terraform"))
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_fn_log_group,
  ]
}

# The CloudWatch group for the Lambda function
resource "aws_cloudwatch_log_group" "lambda_fn_log_group" {
  name              = "/aws/lambda/${local.lambda_full_name}"
  retention_in_days = 14
}

# The API Gateway Resource
resource "aws_api_gateway_resource" "apigw_res" {
  count = (local.apigw_id != "" ? 1 : 0)
  rest_api_id = local.apigw_id
  parent_id   = local.apigw_root_resource_id
  path_part   = local.lambda_function_name

  depends_on = [
    aws_lambda_function.lambda_fn,
  ]
}

# The API Gateway resource method
resource "aws_api_gateway_method" "apigw_method" {
  count = (local.apigw_id != "" ? 1 : 0)
  rest_api_id   = local.apigw_id
  resource_id   = aws_api_gateway_resource.apigw_res[0].id
  http_method   = local.lambda_method
  # Assuming these are all open APIs for now
  authorization = "NONE"

  depends_on = [
    aws_lambda_function.lambda_fn,
  ]
}

# The API Gatway resource method integration
resource "aws_api_gateway_integration" "apigw_integration" {
  count = (local.apigw_id != "" ? 1 : 0)
  rest_api_id = local.apigw_id
  resource_id = aws_api_gateway_method.apigw_method[0].resource_id
  http_method = aws_api_gateway_method.apigw_method[0].http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_fn.invoke_arn

  depends_on = [
    aws_lambda_function.lambda_fn,
    aws_api_gateway_method.apigw_method[0]
  ]
}

# Redeploy the API Gateway for the new method/integration to take effect
resource "aws_api_gateway_deployment" "apigw_deploy" {
  count = (local.apigw_id != "" ? 1 : 0)
  rest_api_id = local.apigw_id
  stage_name  = local.apigw_stage

  variables = {
    deployed_at = timestamp()
  }

  depends_on = [
    aws_api_gateway_method.apigw_method[0],
    aws_api_gateway_integration.apigw_integration[0]
  ]
}

# Gives an external source (like a CloudWatch Event Rule) permission to access the Lambda function.
resource "aws_lambda_permission" "lambda_apigw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_fn.function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${local.apigw_execution_arn}/*/*"

  depends_on = [
    aws_lambda_function.lambda_fn,
  ]
}

resource "aws_cloudwatch_event_rule" "cw_rule" {
  count = (local.lambda_cw_schedule_expression != "") ? 1 : 0
  name = "${local.lambda_full_name}-Cron-Trigger"
  schedule_expression = local.lambda_cw_schedule_expression
}

resource "aws_cloudwatch_event_target" "cw_target" {
  count = (local.lambda_cw_schedule_expression != "") ? 1 : 0
  rule = aws_cloudwatch_event_rule.cw_rule[0].name
  arn = aws_lambda_function.lambda_fn.arn

  depends_on = [
    aws_lambda_function.lambda_fn,
    aws_cloudwatch_event_rule.cw_rule[0],
  ]
}

resource "aws_lambda_permission" "lambda_cw_permission" {
  count = (local.lambda_cw_schedule_expression != "") ? 1 : 0
  statement_id = "AllowExecutionFromCloudWatch"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_fn.function_name
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.cw_rule[0].arn

  depends_on = [
    aws_lambda_function.lambda_fn,
    aws_cloudwatch_event_rule.cw_rule[0],
  ]
}