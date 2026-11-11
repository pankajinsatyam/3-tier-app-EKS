
# Create the EKS Cluster
resource "aws_eks_cluster" "eks_cluster" {
  name = "Three-tier-cloud"

  role_arn = aws_iam_role.cluster_role.arn

  vpc_config {
    subnet_ids = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
  }
  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
  ]
}
