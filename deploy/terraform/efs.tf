# EFS monté sur /juice-shop/logs.
# Note : juice-shop recrée sa base SQLite à chaque démarrage (sequelize.sync force:true)
# et la lit dans data/juiceshop.sqlite ; monter l'EFS sur data/ masquerait data/static.
resource "aws_efs_file_system" "app" {
  creation_token = "${local.name}-efs"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = { Name = "${local.name}-efs" }
}

resource "aws_efs_mount_target" "app" {
  count = 2

  file_system_id  = aws_efs_file_system.app.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "app" {
  file_system_id = aws_efs_file_system.app.id

  # Utilisateur non-root de l'image distroless (65532)
  posix_user {
    uid = 65532
    gid = 0
  }

  root_directory {
    path = "/logs"
    creation_info {
      owner_uid   = 65532
      owner_gid   = 0
      permissions = "0775"
    }
  }

  tags = { Name = "${local.name}-efs-ap" }
}
