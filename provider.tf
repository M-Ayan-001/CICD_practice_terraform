terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# setting backend
terraform {
  backend "s3" {
    bucket       = "s3-terraform-backend-config-001"
    key          = "cicd/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
