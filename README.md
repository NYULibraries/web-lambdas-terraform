# Web Lambdas Terraform

Terraform configs for building Lambdas in AWS and associating those with API Gateway or CloudWatch:



TODO:

- Add `aws_lambda_alias`:

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

- Manage environment variables to inject into Lambda dynamically 

- Finish this README