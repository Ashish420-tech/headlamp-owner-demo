output "ec2_instance_id" {
  value = aws_instance.gateway.id
}

output "elastic_ip" {
  value = aws_eip.gateway.public_ip
}

output "dashboard_url" {
  value = "https://${aws_eip.gateway.public_ip}.nip.io"
}

output "gateway_role_arn" {
  value = aws_iam_role.gateway.arn
}
