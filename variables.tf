variable "region" {
  default = "ap-south-1"
}

variable "cluster_name" {
  default = "eks-arm64-platform"
}

variable "vpc_id" {
  default = "vpc-0f1f4651b2947cf30"
}

variable "subnet_id" {
  default = "subnet-01227ca9b0cf9546a"
}

variable "cluster_security_group_id" {
  default = "sg-04fab17836826d07d"
}

variable "dashboard_password" {
  description = "Strong password for the public Headlamp gateway"
  type        = string
  sensitive   = true
}

variable "dashboard_username" {
  default = "projectowner"
}
