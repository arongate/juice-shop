locals {
  name = "${var.project_name}-${var.environment}"

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
  })

  fqdn = "${var.alb_alias_name}.${var.route53_zone_name}"

  # Index 0..1 pour les subnets publics, 10..11 pour les privés
  public_subnet_cidrs  = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i + 10)]

  # Racine du dépôt juice-shop = contexte de build Docker
  build_context = abspath("${path.module}/../..")
}
