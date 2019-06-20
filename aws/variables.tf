variable "ami" {
  type = map(
    object({
      owner = string
      name  = string
    })
  )

  default = {
    rancheros = {
      owner = "605812595337"
      name  = "rancheros-*-hvm-*"
    },
    ubuntu = {
      owner = "099720109477"
      name  = "*ubuntu-bionic-18.04-*"
    }
  }
}

variable "aws_profile" {
  type        = string
  default     = "default"
  description = "aws cli profile"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "domain" {
  type        = string
  description = "domain name"
}

variable "iam_profile" {
  type        = string
  description = "IAM profile ec2 instances"
}

variable "instance_type" {
  type        = string
  default     = "t3.large"
  description = "EC2 instance type"
}

variable "name" {
  type        = string
  description = "unique resource identifyer and dns node name"
}

variable "os" {
  default = "ubuntu"
}