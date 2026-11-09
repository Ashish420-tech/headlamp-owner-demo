provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "headlamp" {
  name        = "headlamp-owner-demo-sg"
  description = "HTTPS access to Headlamp demo gateway"
  vpc_id      = var.vpc_id

  ingress {
    description = "Public HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "headlamp-owner-demo-sg"
    Project   = "headlamp-owner-demo"
    ManagedBy = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "eks_from_gateway" {
  security_group_id            = var.cluster_security_group_id
  referenced_security_group_id = aws_security_group.headlamp.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Headlamp EC2 gateway to private EKS API"
}

resource "aws_iam_role" "gateway" {
  name = "HeadlampOwnerDemoGatewayRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.gateway.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "eks_describe" {
  name = "DescribeExistingEKSCluster"
  role = aws_iam_role.gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster"]
      Resource = "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
    }]
  })
}

resource "aws_iam_instance_profile" "gateway" {
  name = "HeadlampOwnerDemoInstanceProfile"
  role = aws_iam_role.gateway.name
}

resource "aws_eks_access_entry" "gateway" {
  cluster_name      = var.cluster_name
  principal_arn     = aws_iam_role.gateway.arn
  type              = "STANDARD"
  kubernetes_groups = ["headlamp-gateway"]
}

resource "aws_instance" "gateway" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.small"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.headlamp.id]
  iam_instance_profile        = aws_iam_instance_profile.gateway.name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/gateway.sh.tftpl", {
    region       = var.region
    cluster_name = var.cluster_name
    username     = var.dashboard_username
    password     = var.dashboard_password
  })

  user_data_replace_on_change = true

  tags = {
    Name      = "headlamp-demo-server"
    Project   = "headlamp-owner-demo"
    ManagedBy = "Terraform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_iam_role_policy.eks_describe,
    aws_eks_access_entry.gateway
  ]
}

resource "aws_eip" "gateway" {
  domain   = "vpc"
  instance = aws_instance.gateway.id

  tags = {
    Name    = "headlamp-demo-eip"
    Project = "headlamp-owner-demo"
  }
}
