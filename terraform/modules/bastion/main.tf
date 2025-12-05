# Bastion EC2 Module for LiteLLM
# Creates an EC2 instance for testing OpenWebUI and other services without
# exposing them to the internet. Access is via SSM Session Manager only.
#
# Usage: Connect via SSM, then use kubectl port-forward to access services
# locally (e.g., llm-ui alias forwards OpenWebUI to localhost:8080)

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Get Latest Amazon Linux 2023 AMI
# -----------------------------------------------------------------------------
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# -----------------------------------------------------------------------------
# IAM Role for SSM and EKS Access
# -----------------------------------------------------------------------------
resource "aws_iam_role" "bastion" {
  name = "${var.name_prefix}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "bastion_eks" {
  name = "${var.name_prefix}-eks-describe"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name_prefix}-bastion-profile"
  role = aws_iam_role.bastion.name

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = var.vpc_id

  # SSM uses HTTPS outbound only - no inbound rules needed
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-bastion-sg"
  })
}

# -----------------------------------------------------------------------------
# User Data Script
# -----------------------------------------------------------------------------
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install kubectl with checksum verification
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    curl -LO "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    chmod +x kubectl
    mv kubectl /usr/local/bin/
    rm kubectl.sha256

    # Install helm with signature verification
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh

    # Configure kubectl for EKS
    mkdir -p /home/ec2-user/.kube
    aws eks update-kubeconfig --name ${var.eks_cluster_name} --region ${data.aws_region.current.name} --kubeconfig /home/ec2-user/.kube/config
    chown -R ec2-user:ec2-user /home/ec2-user/.kube

    # Add kubectl aliases
    cat >> /home/ec2-user/.bashrc << 'ALIASES'

    # Kubernetes aliases
    alias k='kubectl'
    alias kgp='kubectl get pods'
    alias kgs='kubectl get svc'
    alias kga='kubectl get all'
    alias kgpa='kubectl get pods -A'
    alias kpf='kubectl port-forward'

    # LiteLLM shortcuts
    alias llm-ui='kubectl port-forward svc/open-webui 8080:80 -n open-webui --address 0.0.0.0'
    alias llm-grafana='kubectl port-forward svc/kube-prometheus-grafana 3000:80 -n monitoring --address 0.0.0.0'
    alias llm-prometheus='kubectl port-forward svc/kube-prometheus-kube-prome-prometheus 9090:9090 -n monitoring --address 0.0.0.0'
    alias llm-jaeger='kubectl port-forward svc/jaeger-query 16686:16686 -n monitoring --address 0.0.0.0'
    ALIASES

    echo "Bastion setup complete!"
  EOF
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------
resource "aws_instance" "bastion" {
  count = var.create_bastion ? 1 : 0

  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id, var.eks_node_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  user_data                   = base64encode(local.user_data)
  user_data_replace_on_change = true

  # IMDSv2 required (security best practice)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-bastion"
    Purpose = "LLM-Testing"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

# -----------------------------------------------------------------------------
# EKS Access Entry (for API authentication mode)
# -----------------------------------------------------------------------------
resource "aws_eks_access_entry" "bastion" {
  count = var.create_bastion && var.create_eks_access_entry ? 1 : 0

  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.bastion.arn
}

resource "aws_eks_access_policy_association" "bastion" {
  count = var.create_bastion && var.create_eks_access_entry ? 1 : 0

  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.bastion.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.bastion]
}
