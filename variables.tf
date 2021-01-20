# To be defined by the context
variable "lambda_exec_arn" {
	type = string
}
variable "apigw_id" {
	type = string
}
variable "apigw_root_resource_id" {
	type = string
}
variable "apigw_execution_arn" {
	type = string
}
variable "lambda_s3_bucket" {
	type = string
}
variable "aws_username" {
	type = string
}
variable "apigw_stage" {
	type = string
}

# To be defined per application
variable "lambda_version" {
	type = string
}
variable "lambda_function_name" {
	type = string
}
variable "lambda_handler" {
	type = string
}
variable "lambda_runtime" {
	type = string
}
variable "lambda_method" {
	type = string
}
variable "lambda_memory_size" {
	type = number
  default = 128
}
variable "environment_variables" {
  type        = map
  description = "Environment variables for the lambda"
  default     = {}
}
variable "lambda_cw_schedule_expression" {
	type = string
	default = ""
}

