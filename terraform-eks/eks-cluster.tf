# The cluster's own IAM role — what EKS uses to manage AWS resources
# (ENIs, load balancers, etc.) on the cluster's behalf.
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "main" {
  name     = var.project_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)

    # Public access so you can run kubectl from your own machine without a
    # VPN/bastion; a stricter production setup would disable this and
    # require a bastion host or VPN into the private subnets instead.
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# The OIDC identity provider for this specific cluster — required later so
# Kubernetes ServiceAccounts (like the AWS Load Balancer Controller's) can
# assume IAM roles directly (IRSA), the same pattern GitHub Actions used
# via its own OIDC provider back in the ECS phase.
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
}
