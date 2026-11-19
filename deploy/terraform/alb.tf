# --- Certificat ACM public, validé par DNS (zone Route 53 existante) ---

resource "aws_acm_certificate" "alb" {
  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${local.name}-cert" }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.alb.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Bloque la création du listener HTTPS tant que le certificat n'est pas émis
resource "aws_acm_certificate_validation" "alb" {
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# --- ALB publique ---

resource "aws_lb" "app" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  drop_invalid_header_fields = true

  tags = { Name = "${local.name}-alb" }
}

resource "aws_lb_target_group" "app" {
  name                 = "${local.name}-tg"
  port                 = var.container_port
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    path                = "/rest/admin/application-version"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${local.name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = { Name = "${local.name}-http" }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.alb.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = { Name = "${local.name}-https" }
}
