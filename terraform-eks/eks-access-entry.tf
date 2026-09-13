# AWS IAM permissions (what we've been granting all night) only control
# what an identity can do against the AWS API — they say nothing about
# what that identity can do *inside* the Kubernetes cluster itself. EKS
# Access Entries are the separate, modern mechanism that maps an IAM
# principal to real Kubernetes RBAC permissions, replacing the legacy
# aws-auth ConfigMap approach.
resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::825990809758:role/github-actions-vulntrack-deploy"
  type          = "STANDARD"
}

# Scoped to only the default namespace (where VulnTrack runs) with edit
# permissions — enough to restart a deployment, not cluster-admin.
resource "aws_eks_access_policy_association" "github_actions_edit" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.github_actions.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["default"]
  }
}
