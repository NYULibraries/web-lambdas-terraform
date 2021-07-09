terraform {
  required_version = ">= 0.13"
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }

  # Backend for TF state is S3
  backend "s3" {
  }
}