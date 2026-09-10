resource "random_password" "db_password" {
  length  = 24
  special = false # avoids characters that need extra escaping in connection strings
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
  instance_class = "db.t3.micro" # smallest size, free-tier eligible on new accounts

  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  skip_final_snapshot = true # acceptable for a dev/portfolio project; a real
                              # production setup would set this false and
                              # configure a final snapshot identifier instead

  backup_retention_period = 1

  tags = {
    Name = "${var.project_name}-db"
  }
}
