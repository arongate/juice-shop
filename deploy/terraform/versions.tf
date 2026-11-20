terraform {
  # >= 1.10 : verrouillage natif S3 (use_lockfile), sans table DynamoDB
  required_version = ">= 1.10.0"

  # Configuration partielle : les valeurs (bucket, région, profil) ne peuvent pas
  # être des variables. Elles sont dans backend.hcl, à passer à terraform init :
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}
