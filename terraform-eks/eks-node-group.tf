# The worker nodes' own IAM role — separate from the cluster's role above.
# This is what each EC2 instance in the node group assumes.
resource "aws_iam_role" "eks_nodes" {
  name = "${var.project_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# A minimal user-data override — nodeadm automatically merges this with
# the cluster connection details (API endpoint, CA, service CIDR) that EKS
# generates on its own, since we're not supplying a custom AMI. We only
# need to specify the one field we're actually overriding.
resource "aws_launch_template" "eks_nodes" {
  name_prefix = "${var.project_name}-node-"

  # Built from explicit, zero-indentation string literals joined with real
  # newlines rather than a heredoc. nodeadm's YAML parser is whitespace-
  # sensitive enough that even a heredoc's "stripped" indentation can leave
  # it malformed, causing nodes to silently fail to join the cluster (this
  # is exactly what happened on the first attempt — see troubleshooting log).
  user_data = base64encode(join("\n", [
    "MIME-Version: 1.0",
    "Content-Type: multipart/mixed; boundary=\"BOUNDARY\"",
    "",
    "--BOUNDARY",
    "Content-Type: application/node.eks.aws",
    "",
    "---",
    "apiVersion: node.eks.aws/v1alpha1",
    "kind: NodeConfig",
    "spec:",
    "  kubelet:",
    "    config:",
    "      maxPods: 30",
    "--BOUNDARY--",
    ""
  ]))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-node"
    }
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  instance_types = var.node_instance_types
  ami_type       = "AL2023_x86_64_STANDARD"

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
  ]
}
