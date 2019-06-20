output "rancher_url" {
  value = "https://${var.name}.${var.domain}"
}

output "get_kubeconfig_cmd" {
  value = "ssh -i ${path.module}/outputs/id_rsa ubuntu@${data.aws_instances.asg.public_ips[0]} sudo cat /var/lib/rancher/k3s/kubeconfig.yaml | sed 's/localhost/${var.name}.${var.domain}/g'"
}