variable "region" {
  description = "AWS region to deploy the VM"
  type        = string
  default     = "us-west-2"
}

variable "name_prefix" {
  description = "Prefix for naming resources"
  type        = string
  default     = "secure-vm"
}

variable "hostname" {
  description = "Hostname to set on the VM"
  type        = string
  default     = "secure-vm"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "admin_username" {
  description = "Username for the admin user"
  type        = string
  default     = "sysadmin"
}

variable "ssh_port" {
  description = "SSH port to configure"
  type        = number
  default     = 2222
}

variable "install_docker" {
  description = "Whether to install Docker"
  type        = bool
  default     = true
}

variable "install_monitoring" {
  description = "Whether to install monitoring tools"
  type        = bool
  default     = true
}

variable "ami_id" {
  description = "AMI ID to use for the instance"
  type        = string
  default     = "ami-0c65adc9a5c1b5d7c" # Ubuntu 20.04 LTS in us-west-2
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed to SSH to the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # WARNING: This allows SSH from anywhere, restrict in production
} 