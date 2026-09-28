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

# A KMS key has its own resource policy, separate from IAM, and BOTH must allow
# an action. The default policy names only the account root, so the Auto Scaling
# service-linked role could not use the key - EC2 failed to create encrypted root
# volumes and the new nodes never joined ("Client.InvalidKMSKey.InvalidState",
# which reports a key-state problem even though the key is enabled and healthy).
data "aws_caller_identity" "current" {}

resource "aws_kms_key_policy" "vulntrack" {
  key_id = aws_kms_key.vulntrack.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIAMUserPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowAutoScalingUseOfTheKey"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowAutoScalingToCreateGrants"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        }
        Action    = "kms:CreateGrant"
        Resource  = "*"
        Condition = { Bool = { "kms:GrantIsForAWSResource" = "true" } }
      }
    ]
  })
}

resource "aws_kms_alias" "vulntrack" {
  name          = "alias/${var.project_name}"
  target_key_id = aws_kms_key.vulntrack.key_id
}

output "kms_key_arn" {
  value = aws_kms_key.vulntrack.arn
}
