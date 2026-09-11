# The official upstream policy, downloaded as lbc-iam-policy.json rather
# than hand-transcribed, since it's long and getting even one action wrong
# causes confusing partial-failure behavior later.
resource "aws_iam_policy" "lbc" {
  name   = "${var.project_name}-lb-controller-policy"
  policy = file("${path.module}/lbc-iam-policy.json")
}

# IRSA: this role can only be assumed by the specific Kubernetes
# ServiceAccount named below, via the cluster's own OIDC provider — the
# same federated-identity pattern GitHub Actions used against its own
# OIDC provider back in the ECS phase, just scoped to a K8s ServiceAccount
# instead of a GitHub repo/branch.
resource "aws_iam_role" "lbc" {
  name = "${var.project_name}-lb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

output "lbc_role_arn" {
  description = "Paste this into the ServiceAccount annotation in the next step"
  value       = aws_iam_role.lbc.arn
}
