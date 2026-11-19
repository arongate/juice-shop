# Aucune valeur par défaut ici : elles sont dans juice-shop.tfvars,
# à passer explicitement avec -var-file=juice-shop.tfvars.

variable "aws_region" {
  description = "Région AWS de déploiement"
  type        = string
}

variable "aws_profile" {
  description = "Profile AWS de déploiement"
  type        = string
}

variable "availability_zones" {
  description = "Exactement 2 zones de disponibilité (doivent appartenir à aws_region)"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Il faut exactement 2 zones de disponibilité."
  }
}

variable "vpc_cidr" {
  description = "CIDR du VPC (/16 à /20 : les subnets /24 sont dérivés avec cidrsubnet)"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr doit être un CIDR valide de préfixe /20 ou plus large."
  }
}

variable "project_name" {
  description = "Nom du projet, utilisé comme préfixe des ressources"
  type        = string
}

variable "environment" {
  description = "Nom de l'environnement (tag)"
  type        = string
}

variable "tags" {
  description = "Tags additionnels appliqués à toutes les ressources"
  type        = map(string)
}

variable "route53_zone_name" {
  description = "Zone Route 53 existante qui héberge l'alias de l'ALB"
  type        = string
}

variable "alb_alias_name" {
  description = "Nom (sans la zone) de l'alias DNS de l'ALB"
  type        = string
}

variable "allowed_ingress_cidrs" {
  description = "CIDR autorisés à joindre l'ALB en HTTP/HTTPS"
  type        = list(string)
}

variable "container_port" {
  description = "Port d'écoute de l'application"
  type        = number
}

variable "task_cpu" {
  description = "CPU de la tâche Fargate (unités)"
  type        = number
}

variable "task_memory" {
  description = "Mémoire de la tâche Fargate (MiB)"
  type        = number
}

variable "desired_count" {
  description = "Nombre de tâches ECS. Garder 1 : l'état applicatif est en mémoire."
  type        = number
}

variable "image_tag" {
  description = "Tag de l'image Docker poussée dans ECR"
  type        = string
}

variable "docker_build_proxy_enabled" {
  description = "Active l'utilisation du proxy pendant docker build"
  type        = bool
}

variable "docker_build_proxy" {
  description = "Proxy HTTP(S) utilisé pendant docker build (npm install). Ignoré si docker_build_proxy_enabled = false."
  type        = string
}

variable "docker_build_no_proxy" {
  description = "Hôtes exclus du proxy pendant docker build"
  type        = string
}

variable "log_retention_days" {
  description = "Rétention des logs CloudWatch (jours)"
  type        = number
}
