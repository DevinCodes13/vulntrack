# The state bucket holds the RDS password and JWT signing key in plaintext, so
# it is the most sensitive object in the project. It was created by hand during
# the Phase 6 state migration with public access blocked and versioning on;
# these resources bring it under Terraform and close the remaining gaps:
# encryption with the customer-managed key (was SSE-S3, an AWS-owned key that
# cannot be audited or revoked) and a policy refusing plaintext HTTP.
#
# A DenyUnencryptedObjectUploads statement was tried and removed: with bucket
# default encryption set, S3 encrypts server-side without the client sending an
# x-amz-server-side-encryption header, so the condition denied Terraform's own
# state writes. Explicit Deny beats IAM Allow - it locked the backend out.

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = "vulntrack-tfstate-825990809758"

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.vulntrack.arn
    }
    # Caches a data key per bucket rather than calling KMS per object,
    # cutting KMS request costs on frequent state reads.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = "vulntrack-tfstate-825990809758"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::vulntrack-tfstate-825990809758",
          "arn:aws:s3:::vulntrack-tfstate-825990809758/*"
        ]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}
