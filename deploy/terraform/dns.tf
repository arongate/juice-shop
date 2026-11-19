data "aws_route53_zone" "this" {
  name         = var.route53_zone_name
  private_zone = false
}

resource "aws_route53_record" "alb" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.fqdn
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}
