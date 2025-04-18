# Secure VM Setup - Infrastructure as Code

A comprehensive toolkit for automated, secure VM provisioning that follows Infrastructure as Code (IaC) best practices. This repository contains scripts and configurations to harden Ubuntu VMs automatically across multiple cloud providers and deployment models.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Overview

This toolkit solves the challenge of consistently applying security hardening to virtual machines by providing multiple automation methods that can fit into various deployment workflows. Once applied, your VM will have:

- Secure SSH configuration with key-only authentication
- Custom configured admin user with appropriate permissions
- Properly configured firewall with sensible defaults
- Fail2ban protection against brute force attacks
- Docker securely installed (optional)
- Automatic security updates
- System auditing and monitoring

## Features

- **Multi-Platform Support**: Works on AWS, GCP, Azure, and on-premise VMs
- **Multiple Deployment Methods**: Terraform, Ansible, Packer, Cloud-init, or manual
- **Secure by Default**: Implements infrastructure security best practices
- **Highly Configurable**: Customize any aspect via environment variables or config files
- **Idempotent Design**: Safely run multiple times without breaking things
- **Comprehensive Logging**: Detailed logs for troubleshooting
- **Testing Support**: Docker-based testing environment included
- **Infrastructure as Code**: Everything defined as code for consistency

## Quick Start

### Option 1: One-line Bootstrap (for existing VM)

Standard installation:
```bash
curl -sSL https://raw.githubusercontent.com/rheynoapria/vm-setup/main/scripts/bootstrap.sh | sudo bash
```

With custom hostname:
```bash
curl -sSL https://raw.githubusercontent.com/rheynoapria/vm-setup/main/scripts/bootstrap.sh | sudo bash -s -- --hostname custom-host
```

With custom admin user:
```bash
curl -sSL https://raw.githubusercontent.com/rheynoapria/vm-setup/main/scripts/bootstrap.sh | sudo bash -s -- --user custom-admin
```

With SSH key and hostname:
```bash
curl -sSL https://raw.githubusercontent.com/rheynoapria/vm-setup/main/scripts/bootstrap.sh | sudo bash -s -- --ssh-key "ssh-rsa AAA..." --hostname custom-host
```

With all options combined:
```bash
curl -sSL https://raw.githubusercontent.com/rheynoapria/vm-setup/main/scripts/bootstrap.sh | sudo bash -s -- --user custom-admin --ssh-key "ssh-rsa AAA..." --hostname custom-host
```

### Option 2: Terraform Deployment (for new AWS VM)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars  # Edit with your values
terraform init
terraform apply
```

### Option 3: Cloud-init (for cloud platforms)

Use the [cloud-init/user-data.yml](cloud-init/user-data.yml) file when launching a new instance.

## Detailed Installation Methods

### 1. Manual Installation

For direct installation on an existing server:

```bash
# Clone repository
git clone https://github.com/rheynoapria/vm-setup.git
cd vm-setup

# Configure SSH key (optional but recommended)
sudo mkdir -p /opt/scripts/config
sudo cp ~/.ssh/id_rsa.pub /opt/scripts/config/authorized_keys

# Set custom hostname (optional)
echo 'VM_HOSTNAME="your-custom-hostname"' | sudo tee -a /opt/scripts/config/settings.env

# Run installer
sudo bash install.sh

# Trigger provisioning (or let it happen automatically)
sudo /opt/scripts/trigger-provision.sh
```

### 2. Terraform Deployment

For creating a new hardened VM on AWS:

```bash
cd terraform
# Edit variables in terraform.tfvars including hostname
terraform init
terraform plan  # Review changes
terraform apply
```

The Terraform configuration:
- Creates a new VPC with proper networking
- Deploys a VM with encrypted storage
- Sets the specified hostname
- Applies all hardening automatically via cloud-init
- Outputs SSH connection details

### 3. Cloud-Init Integration

For automated provisioning during VM creation:

1. Copy the [cloud-init/user-data.yml](cloud-init/user-data.yml) file
2. Modify the SSH public key and hostname settings as needed
3. Provide this as user-data when launching a new VM

Works with AWS, GCP, Azure, DigitalOcean, and other cloud providers supporting cloud-init.

### 4. Packer Image Building

For creating hardened VM images:

```bash
# Install HashiCorp Packer first
# Then build the image for your platform:

# AWS AMI
./scripts/packer-build.sh --aws

# GCP Image
./scripts/packer-build.sh --gcp

# Vagrant Box
./scripts/packer-build.sh --vagrant
```

The resulting images have all security measures pre-applied, making deployment even faster.

### 5. Ansible Automation

For applying to existing servers:

```bash
cd ansible
# Edit inventory.ini to add your servers
# Hostnames in inventory will be used as VM hostnames by default
ansible-playbook -i inventory.ini playbook.yml

# Or override hostname for specific servers
ansible-playbook -i inventory.ini playbook.yml -e "vm_hostname=custom-hostname"
```

Ansible allows for mass-deployment to multiple servers and includes:
- Configuration verification
- Parallel deployment support
- Detailed progress reporting

### 6. Docker Testing

For testing the setup in a controlled environment:

```bash
# Build test container
./scripts/run-in-docker.sh --build

# Run the container
./scripts/run-in-docker.sh --run

# Connect to container
docker exec -it vm-setup-test bash

# Clean up when done
./scripts/run-in-docker.sh --clean
```

This creates a Docker container simulating a fresh Ubuntu VM and applies the hardening process.

## Configuration

### Core Settings

Key settings that can be configured:

| Setting | Description | Default |
|---------|-------------|---------|
| `NEW_USER` | Admin username to create | `sysadmin` |
| `SSH_PORT` | Custom SSH port | `2222` |
| `VM_HOSTNAME` | Hostname to set on the VM | `secure-vm` |
| `CREATE_USER_DIR` | Whether to create user directory in /opt | `true` |
| `INSTALL_DOCKER` | Whether to install Docker | `true` |
| `INSTALL_MONITORING` | Install monitoring tools | `true` |
| `ENABLE_AUTO_UPDATES` | Configure automatic updates | `true` |

### Configuration Methods

1. **Environment Variables**: Set before running install.sh
2. **Config File**: Create `/opt/scripts/config/settings.env`
3. **Deployment Parameters**: Pass to Terraform/Ansible/Packer

See [config/settings.env](config/settings.env) for a complete list of configurable options.

## Security Measures

This toolkit implements the following security measures:

- **SSH Hardening**:
  - Custom port (default: 2222)
  - Key-only authentication
  - Disabled root login
  - Strict ciphers and MAC algorithms
  - Fail2ban protection against brute force

- **System Hardening**:
  - Firewall (UFW) with deny-by-default policy
  - Kernel parameter hardening via sysctl
  - Automatic security updates
  - Disabled unnecessary services
  - Regular security audit logging

- **User Management**:
  - Creation of non-root admin user
  - Proper sudo configuration
  - SSH authorized keys management
  - User directory in /opt/{username} with proper permissions

- **Docker Security** (when enabled):
  - Proper user group configuration
  - Default security practices
  - Limited container privileges

## Directory Structure

```
├── ansible/            # Ansible playbooks for deployment
├── cloud-init/         # Cloud-init templates
├── config/             # Configuration files
├── scripts/            # Utility scripts
├── terraform/          # Terraform configurations
├── install.sh          # Main installer script
├── post-provision.sh   # Core provisioning script
└── README.md           # This documentation
```

## Troubleshooting

### Checking Status

```bash
# View provisioning status
sudo /opt/scripts/check-provision-status.sh

# Check service status
sudo systemctl status post-provision

# View logs
sudo journalctl -u post-provision
cat /var/log/post-provision/post-provision.log

# Check security status
sudo /opt/scripts/check-security.sh
```

### Common Issues

| Issue | Solution |
|-------|----------|
| SSH key not working | Check `/opt/scripts/config/authorized_keys` permissions (should be 0600) |
| Service not starting | Verify with `journalctl -u post-provision` |
| Firewall blocking connections | Use `sudo ufw status` and adjust rules as needed |
| Hostname not changing | Ensure `/etc/hostname` is writable and reboot if needed |

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by various security benchmarks including CIS Ubuntu Benchmarks
- Built following Infrastructure as Code best practices
- Developed with security and automation as primary goals

## Implementation Details

### User Management
- The setup creates a non-root admin user with the username specified in `NEW_USER`
- Configures sudo access with password requirement
- Sets up SSH authorized keys for the new user
- When `CREATE_USER_DIR` is enabled, creates a directory at `/opt/${NEW_USER}` owned by the user
- Removes unnecessary default users

### System Hardening
- **SSH Hardening**:
  - Custom port configuration (default: 2222)
  - Disables root login completely
  - Enables key-only authentication (disables password auth)
  - Restricts SSH access to the specified admin user
  - Sets appropriate session timeouts (ClientAliveInterval: 300s)
  - Limits authentication attempts to prevent brute force attacks
  - Creates backup of original SSH configuration

- **Firewall Configuration**:
  - Configures UFW with deny-by-default policy for incoming traffic
  - Allows outgoing connections by default
  - Opens only the necessary custom SSH port
  - Implements strict IPv4/IPv6 packet filtering

- **Brute Force Protection**:
  - Installs and configures fail2ban
  - Sets ban time to 24 hours by default (configurable)
  - Monitors SSH authentication logs
  - Implements automatic IP blocking after 3 failed attempts

- **System Security Controls**:
  - Hardens kernel parameters via sysctl configuration
  - Protects against IP spoofing, ICMP broadcast requests
  - Disables source packet routing
  - Configures TCP/SYN attack protection
  - Enables Martian packet logging
  - Implements IPv6 privacy extensions

- **Service Management**:
  - Disables unnecessary services (avahi-daemon, cups, bluetooth)
  - Implements automatic security updates when enabled
  - Configures unattended-upgrades for critical patches

- **Monitoring and Auditing**:
  - Installs auditd for system call auditing when monitoring is enabled
  - Creates security status checking tool at `/opt/scripts/check-security.sh`
  - Generates detailed provisioning summary report
