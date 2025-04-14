provider "aws" {
  region = var.region
}

# Read the SSH public key file
locals {
  ssh_public_key = file(var.ssh_public_key_path)
  user_data = templatefile("${path.module}/templates/cloud-init.tpl", {
    ssh_public_key = local.ssh_public_key
    vm_settings = {
      new_user = var.admin_username
      ssh_port = var.ssh_port
      install_docker = var.install_docker
      install_monitoring = var.install_monitoring
    }
  })
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  
  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

# Create a subnet
resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "${var.name_prefix}-subnet"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# Create route table
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = {
    Name = "${var.name_prefix}-rt"
  }
}

# Associate route table with subnet
resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# Create security group
resource "aws_security_group" "main" {
  name        = "${var.name_prefix}-sg"
  description = "Allow SSH and other necessary traffic"
  vpc_id      = aws_vpc.main.id
  
  # SSH on custom port
  ingress {
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr
  }
  
  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.name_prefix}-sg"
  }
}

# Create EC2 instance
resource "aws_instance" "main" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.main.key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.main.id]
  user_data              = local.user_data
  
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }
  
  tags = {
    Name = "${var.name_prefix}-instance"
  }
}

# Create SSH key pair
resource "aws_key_pair" "main" {
  key_name   = "${var.name_prefix}-key"
  public_key = local.ssh_public_key
}

# Output instance IP and connection details
output "instance_public_ip" {
  value = aws_instance.main.public_ip
}

output "ssh_connection" {
  value = "ssh ${var.admin_username}@${aws_instance.main.public_ip} -p ${var.ssh_port}"
} 