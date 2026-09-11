resource "random_password" "db_password" {
  length  = 24
  special = false
}

# Allows Postgres traffic only from EKS-managed resources. EKS attaches its
# cluster security group to node ENIs automatically, so referencing it here
# (rather than the node group's own SG) covers pod traffic correctly.
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound Postgres traffic only from the EKS cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from EKS cluster security group"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = "vulntrack"
  username = "vulntrack"
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  skip_final_snapshot     = true
  backup_retention_period = 1

  tags = {
    Name = "${var.project_name}-db"
  }
}

# Kept in Secrets Manager for parity with the ECS setup and as the source
# of truth/audit trail — the actual pods read these values from a
# Kubernetes Secret (created manually, see README), not from Secrets
# Manager directly. A more production-grade setup would sync this
# automatically via External Secrets Operator or the Secrets Store CSI
# Driver rather than a manual kubectl step — noted as a Phase 5+ item.
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "vulntrack-eks/db-credentials"
  description             = "PostgreSQL connection details for VulnTrack on EKS"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "vulntrack"
    password = random_password.db_password.result
    host     = aws_db_instance.main.address
    port     = 5432
    dbname   = "vulntrack"
  })
}

output "rds_endpoint" {
  value     = aws_db_instance.main.address
  sensitive = true
}

resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "jwt_key" {
  name                    = "vulntrack-eks/jwt-signing-key"
  description             = "HMAC signing key for VulnTrack JWTs on EKS"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt_key" {
  secret_id     = aws_secretsmanager_secret.jwt_key.id
  secret_string = random_password.jwt_secret.result
}
