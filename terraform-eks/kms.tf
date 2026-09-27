# Customer-managed KMS key for VulnTrack data at rest.
#
# AWS encrypts EBS and RDS with its own keys by default, but those are opaque:
# they can't be audited per-use, rotated on demand, or revoked. A customer-managed
# key makes every Encrypt/Decrypt call visible in CloudTrail and gives us a kill
# switch - disable the key and the data becomes unreadable immediately.

resource "aws_kms_key" "vulntrack" {
  description             = "VulnTrack data at rest (EBS node volumes, RDS storage)"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = {
    Name    = "${var.project_name}-key"
    Project = var.project_name
  }
}

resource "aws_kms_alias" "vulntrack" {
  name          = "alias/${var.project_name}"
  target_key_id = aws_kms_key.vulntrack.key_id
}

output "kms_key_arn" {
  value = aws_kms_key.vulntrack.arn
}
