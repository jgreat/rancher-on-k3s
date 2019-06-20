
# Cluster secret
resource "random_string" "cluster_secret" {
  length = 36
}

data "template_file" "helm_rancher" {
  template = file("${path.module}/manifests/helm-rancher.yaml")

  vars = {
    hostname = "${var.name}.${var.domain}"
  }
}

# Template cloud-config.yaml
data "template_file" "cloud_config" {
  template = file("${path.module}/cloud-config/${var.os}-cloud-config.yaml")

  vars = {
    cluster_secret     = random_string.cluster_secret.result
    crd_cert_manager   = base64gzip(file("${path.module}/manifests/crd-cert-manager.yaml"))
    helm_cert_manager  = base64gzip(file("${path.module}/manifests/helm-cert-manager.yaml"))
    helm_nginx_ingress = base64gzip(file("${path.module}/manifests/helm-nginx-ingress.yaml"))
    helm_rancher       = base64gzip(data.template_file.helm_rancher.rendered)
  }
}

resource "aws_launch_template" "rancher" {
  name_prefix                          = var.name
  image_id                             = data.aws_ami.ami.id
  instance_type                        = var.instance_type
  instance_initiated_shutdown_behavior = "terminate"
  key_name                             = aws_key_pair.ssh.key_name
  user_data                            = base64encode(data.template_file.cloud_config.rendered)
  ebs_optimized                        = true

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_type = "gp2"
      volume_size = 50
    }
  }

  iam_instance_profile {
    name = var.iam_profile
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.rancher.id]
    delete_on_termination       = true
  }

}

# (╯°□°)╯︵ ┻━┻ Why can't I just add rolling update policy with an asg resource?
resource "aws_cloudformation_stack" "rancher" {
  name          = var.name
  template_body = file("${path.module}/cf-asg.yaml")

  parameters = {
    LaunchTemplateId      = aws_launch_template.rancher.id
    LaunchTemplateVersion = aws_launch_template.rancher.latest_version
    LoadBalancerNames     = aws_elb.rancher.name
    MinSize               = 1
    MaxSize               = 1
    Name                  = var.name
    VPCZoneId             = join(",", data.aws_subnet_ids.available.ids)
  }
}

data "aws_instances" "asg" {
  depends_on = [ "aws_cloudformation_stack.rancher" ]
  
  instance_tags = {
    Name = var.name
  }
}

