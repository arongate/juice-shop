resource "aws_ecr_repository" "app" {
  name                 = local.name
  image_tag_mutability = "MUTABLE"
  force_delete         = true # lab : permet le destroy même avec des images

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${local.name}-ecr" }
}

# Build local avec le provider kreuzwerker/docker.
# Le Dockerfile racine est autonome : `npm install` déclenche le postinstall
# qui compile le frontend Angular et le serveur TypeScript.
resource "docker_image" "app" {
  name = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"

  build {
    context    = local.build_context
    dockerfile = "Dockerfile"
    platform   = "linux/amd64" # correspond à la tâche Fargate X86_64

    # Le provider appelle l'API Docker directement : il n'applique pas le bloc
    # "proxies" de ~/.docker/config.json (seul le CLI docker le fait).
    # HTTP(S)_PROXY sont des ARG prédéfinis : non conservés dans l'historique de l'image.
    build_args = var.docker_build_proxy_enabled ? {
      HTTP_PROXY  = var.docker_build_proxy
      HTTPS_PROXY = var.docker_build_proxy
      http_proxy  = var.docker_build_proxy
      https_proxy = var.docker_build_proxy
      NO_PROXY    = var.docker_build_no_proxy
      no_proxy    = var.docker_build_no_proxy
    } : {}
  }

  triggers = {
    dockerfile   = filesha1("${local.build_context}/Dockerfile")
    package_json = filesha1("${local.build_context}/package.json")
    server       = filesha1("${local.build_context}/server.ts")
    # Jeton de vérification de domaine AWS Security Agent (servi par /.well-known)
    domain_verification = filesha1("${local.build_context}/.well-known/aws/securityagent-domain-verification.json")
  }
}

resource "docker_registry_image" "app" {
  name          = docker_image.app.name
  keep_remotely = true

  triggers = {
    image_id = docker_image.app.image_id
  }
}
