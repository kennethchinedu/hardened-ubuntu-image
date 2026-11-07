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

variable "git_sha" {
  type    = string
  default = "unknown"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

hcp_packer_registry {
  bucket_name = "cis-ubuntu2404"
  description = "CIS Level 1 hardened Ubuntu 24.04 Server image"

  bucket_labels = {
    os         = "ubuntu"
    os_version = "24.04"
    benchmark  = "cis-l1-server"
  }

  build_labels = {
    git_sha = var.git_sha
  }
}

source "amazon-ebs" "ubuntu" {
  region                                    = var.region
  instance_type                             = "t3.micro"
  temporary_security_group_source_public_ip = true
  encrypt_boot                              = true

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
    GitSha  = var.git_sha
  }

  run_tags = {
    BuiltBy = "packer"
    GitSha  = var.git_sha
  }

  run_volume_tags = {
    BuiltBy = "packer"
    GitSha  = var.git_sha
  }

  snapshot_tags = {
    BuiltBy = "packer"
    GitSha  = var.git_sha
  }
}

build {

  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/playbook.yml"
  }

  post-processor "manifest" {
    output      = "${path.root}/manifest.json"
    strip_path  = true
    custom_data = { git_sha = var.git_sha }
  }
}