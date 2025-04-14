#!/bin/bash
# Script to build VM image with HashiCorp Packer

set -eo pipefail

# Configuration
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
PACKER_DIR="${REPO_DIR}/packer"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -a, --aws       Build AWS AMI"
    echo "  -g, --gcp       Build GCP image"
    echo "  -v, --vagrant   Build Vagrant box"
    echo "  -h, --help      Display this help message"
    exit 1
}

# Function to check if packer is installed
check_packer() {
    if ! command -v packer &> /dev/null; then
        echo "Error: Packer is not installed."
        echo "Please install Packer: https://www.packer.io/downloads"
        exit 1
    fi
}

# Function to create packer directory if not exists
create_packer_dir() {
    mkdir -p "${PACKER_DIR}"
}

# Function to build AWS AMI
build_aws_ami() {
    check_packer
    create_packer_dir
    
    echo "Creating AWS Packer template..."
    cat > "${PACKER_DIR}/aws-ubuntu.pkr.hcl" << 'EOF'
variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "ssh_username" {
  type    = string
  default = "ubuntu"
}

source "amazon-ebs" "ubuntu" {
  ami_name      = "secure-ubuntu-{{timestamp}}"
  instance_type = "t3.micro"
  region        = var.aws_region
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/*ubuntu-focal-20.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical
  }
  ssh_username = var.ssh_username
}

build {
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    inline = ["mkdir -p /tmp/vm-setup"]
  }

  provisioner "file" {
    source      = "."
    destination = "/tmp/vm-setup"
  }

  provisioner "shell" {
    inline = [
      "cd /tmp/vm-setup",
      "sudo bash install.sh",
      "sudo mkdir -p /etc/provisioning-pending",
      "sleep 30", # Give time for provisioning to start
      "sudo journalctl -fu post-provision"
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
EOF

    echo "Building AWS AMI with Packer..."
    cd "${REPO_DIR}"
    packer build "${PACKER_DIR}/aws-ubuntu.pkr.hcl"
}

# Function to build GCP image
build_gcp_image() {
    check_packer
    create_packer_dir
    
    echo "Creating GCP Packer template..."
    cat > "${PACKER_DIR}/gcp-ubuntu.pkr.hcl" << 'EOF'
variable "project_id" {
  type    = string
  default = "your-project-id"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

source "googlecompute" "ubuntu" {
  project_id   = var.project_id
  source_image_family = "ubuntu-2004-lts"
  zone         = var.zone
  image_name   = "secure-ubuntu-{{timestamp}}"
  ssh_username = "ubuntu"
  machine_type = "e2-standard-2"
}

build {
  sources = ["source.googlecompute.ubuntu"]

  provisioner "shell" {
    inline = ["mkdir -p /tmp/vm-setup"]
  }

  provisioner "file" {
    source      = "."
    destination = "/tmp/vm-setup"
  }

  provisioner "shell" {
    inline = [
      "cd /tmp/vm-setup",
      "sudo bash install.sh",
      "sudo mkdir -p /etc/provisioning-pending",
      "sleep 30", # Give time for provisioning to start
      "sudo journalctl -fu post-provision"
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
EOF

    echo "Building GCP image with Packer..."
    cd "${REPO_DIR}"
    packer build "${PACKER_DIR}/gcp-ubuntu.pkr.hcl"
}

# Function to build Vagrant box
build_vagrant_box() {
    check_packer
    create_packer_dir
    
    echo "Creating Vagrant Packer template..."
    cat > "${PACKER_DIR}/vagrant-ubuntu.pkr.hcl" << 'EOF'
source "vagrant" "ubuntu" {
  source_path = "ubuntu/focal64"
  provider    = "virtualbox"
  box_name    = "secure-ubuntu"
}

build {
  sources = ["source.vagrant.ubuntu"]

  provisioner "shell" {
    inline = ["mkdir -p /tmp/vm-setup"]
  }

  provisioner "file" {
    source      = "."
    destination = "/tmp/vm-setup"
  }

  provisioner "shell" {
    inline = [
      "cd /tmp/vm-setup",
      "sudo bash install.sh",
      "sudo mkdir -p /etc/provisioning-pending",
      "sleep 30", # Give time for provisioning to start
      "sudo journalctl -fu post-provision"
    ]
  }

  post-processor "vagrant" {
    output = "secure-ubuntu-{{timestamp}}.box"
  }
}
EOF

    echo "Building Vagrant box with Packer..."
    cd "${REPO_DIR}"
    packer build "${PACKER_DIR}/vagrant-ubuntu.pkr.hcl"
}

# Parse command line arguments
if [ $# -eq 0 ]; then
    usage
fi

while [ $# -gt 0 ]; do
    case "$1" in
        -a|--aws)
            build_aws_ami
            shift
            ;;
        -g|--gcp)
            build_gcp_image
            shift
            ;;
        -v|--vagrant)
            build_vagrant_box
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

exit 0 