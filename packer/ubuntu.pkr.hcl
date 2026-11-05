packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "1.8.4"
    }

    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "1.1.6"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-west-2"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "amazon-ebs" "ubuntu" {
  region        = var.region
  instance_type = "t3.micro"

  ami_name     = "cis-ubuntu2404-${local.timestamp}"
  ssh_username = "ubuntu"

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }

    owners      = ["099720109477"]
    most_recent = true
  }

  tags = {
    Name    = "cis-ubuntu2404-${local.timestamp}"
    BuiltBy = "packer"
  }
}

build {
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "ansible" {
    playbook_file = "../ansible/playbook.yml"
  }
}
