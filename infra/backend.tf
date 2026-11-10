terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "tfstate-zero-to-prod-875412454941"
    key          = "ec2/terraform.tfstate"
    region       = "ap-southeast-3"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.region
}
