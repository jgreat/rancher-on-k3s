data "aws_ami" "ami" {
  most_recent = true
  owners      = [var.ami[var.os]["owner"]]

  filter {
    name   = "name"
    values = [var.ami[var.os]["name"]]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}


data "aws_route53_zone" "dns_zone" {
  name = var.domain
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "available" {
  vpc_id = data.aws_vpc.default.id
}