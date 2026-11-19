resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "ALB : HTTP et HTTPS depuis les CIDR autorises"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = toset(var.allowed_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = toset(var.allowed_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Vers les taches ECS"
  referenced_security_group_id = aws_security_group.ecs.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "ecs" {
  name        = "${local.name}-ecs-sg"
  description = "Taches ECS : trafic depuis ALB uniquement"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-ecs-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Depuis ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_vpce" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Vers les endpoints VPC (ECR, logs)"
  referenced_security_group_id = aws_security_group.vpce.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

# Le endpoint S3 (gateway) est joint via une prefix list (layers ECR sur S3)
data "aws_prefix_list" "s3" {
  prefix_list_id = aws_vpc_endpoint.s3.prefix_list_id
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_s3" {
  security_group_id = aws_security_group.ecs.id
  description       = "Vers S3 (layers des images ECR)"
  prefix_list_id    = data.aws_prefix_list.s3.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_efs" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Vers EFS (NFS)"
  referenced_security_group_id = aws_security_group.efs.id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "efs" {
  name        = "${local.name}-efs-sg"
  description = "EFS : NFS depuis les taches ECS"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-efs-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_ecs" {
  security_group_id            = aws_security_group.efs.id
  description                  = "NFS depuis ECS"
  referenced_security_group_id = aws_security_group.ecs.id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "vpce" {
  name        = "${local.name}-vpce-sg"
  description = "Endpoints VPC : HTTPS depuis les taches ECS"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-vpce-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_ecs" {
  security_group_id            = aws_security_group.vpce.id
  description                  = "HTTPS depuis ECS"
  referenced_security_group_id = aws_security_group.ecs.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}
