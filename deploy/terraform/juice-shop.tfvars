# Valeurs par défaut. Non chargé automatiquement (nom != terraform.tfvars / *.auto.tfvars).
# Usage : terraform plan -var-file=juice-shop.tfvars

aws_region         = "eu-central-1"
availability_zones = ["eu-central-1a", "eu-central-1b"]
aws_profile        = "sandbox-frontieragents-1"

# Subnets dérivés : publics  = cidrsubnet(cidr, 8, 0..1) -> 10.20.0.0/24, 10.20.1.0/24
#                   privés   = cidrsubnet(cidr, 8, 10..11) -> 10.20.10.0/24, 10.20.11.0/24
vpc_cidr = "10.20.0.0/16"

project_name = "juice-shop"
environment  = "lab"

tags = {
  Project   = "aws-security-agent"
  Owner     = "ocb"
  ManagedBy = "terraform"
}

route53_zone_name = "frontiers.ocbawspractice.com"
alb_alias_name    = "juice-shop-01"

# Application volontairement vulnérable : restreindre à tes IP dès que possible.
allowed_ingress_cidrs = ["0.0.0.0/0"]

container_port = 3000
task_cpu       = 512
task_memory    = 1024

# 1 seule tâche : sessions et état des challenges sont en mémoire du processus.
desired_count = 1

# Proxy de la machine de build (équivalent du bloc proxies de ~/.docker/config.json).
# Passer docker_build_proxy_enabled à false si la machine accède directement à Internet.
docker_build_proxy_enabled = true
docker_build_proxy         = "http://10.242.191.81:80"
docker_build_no_proxy      = "localhost,127.0.0.1"

image_tag          = "latest"
log_retention_days = 30
