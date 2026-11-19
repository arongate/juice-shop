provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = local.tags
  }
}

# Authentification Docker auprès d'ECR (token temporaire, 12 h)
data "aws_ecr_authorization_token" "this" {}

provider "docker" {
  registry_auth {
    address  = data.aws_ecr_authorization_token.this.proxy_endpoint
    username = data.aws_ecr_authorization_token.this.user_name
    password = data.aws_ecr_authorization_token.this.password
  }
}
