# VM Setup - Post-Provisioning Automation

This repository contains automation scripts for secure post-provisioning setup of Ubuntu virtual machines following Infrastructure as Code (IaC) best practices.

## Features

- **Secure System Configuration**: Comprehensive hardening with best security practices
- **SSH Hardening**: Custom port, key-only authentication, and fail2ban integration
- **Secure Admin User**: Creates a non-root admin user with sudo privileges
- **Firewall Setup**: Configures UFW with secure defaults
- **Docker Support**: Optional Docker installation with proper user permissions
- **Automatic Updates**: Configures unattended security updates
- **System Monitoring**: Sets up basic system auditing
- **Idempotent Design**: Can be safely run multiple times
- **Error Handling**: Robust error checking and logging
- **Multi-Environment Compatible**: Works across dev, test, and production

## Installation Methods

### 1. Manual Installation

To install the post-provisioning automation manually:

```bash
# Create configuration directory first (optional)
sudo mkdir -p /opt/scripts/config

# If you want to use your own SSH key, copy it before installation
sudo cp ~/.ssh/id_rsa.pub /opt/scripts/config/authorized_keys

# Run the installer
sudo bash install.sh
```

### 2. Terraform Deployment

Deploy a secure VM on AWS with all hardening automatically:

```bash
cd terraform
terraform init
terraform apply
```

### 3. Cloud-Init Integration

Use cloud-init to automatically set up a newly provisioned cloud VM:

```bash
# Create a VM with this user-data
cloud-config-path=cloud-init/user-data.yml
```

### 4. Packer Image Building

Build custom hardened VM images for various platforms:

```bash
# Build AWS AMI
./scripts/packer-build.sh --aws

# Build GCP image
./scripts/packer-build.sh --gcp

# Build Vagrant box
./scripts/packer-build.sh --vagrant
```

### 5. Ansible Automation

Deploy to existing servers using Ansible:

```bash
# Edit inventory.ini to add your servers
cd ansible
ansible-playbook playbook.yml
```

### 6. Docker Testing

Test the setup in a Docker container:

```bash
./scripts/run-in-docker.sh --build
./scripts/run-in-docker.sh --run
```

### 7. Bootstrap Script

Quick one-liner for new VMs:

```bash
curl -sSL https://raw.githubusercontent.com/yourusername/vm-setup/main/scripts/bootstrap.sh | sudo bash
```

## Usage

### Automatic Trigger

The post-provisioning will automatically run when it detects a trigger directory:

```bash
# To trigger the post-provisioning process
sudo mkdir -p /etc/provisioning-pending
```

### Manual Execution

To run the post-provisioning script manually:

```bash
sudo bash /opt/scripts/post-provision.sh
```

### Checking Status

The installer creates a status checking script:

```bash
sudo /opt/scripts/check-provision-status.sh
```

## Configurations

Default settings can be modified by:

1. Editing the script variables directly
2. Creating a proper configuration file in `/opt/scripts/config/` (preferred)
3. Using environment variables with the deployment methods

## Important Security Changes

After the post-provisioning completes:

- **SSH Port**: Changed from default 22 to port 2222
- **Root Login**: Direct root login is disabled
- **Admin User**: A new user 'sysadmin' will be created with sudo privileges
- **SSH Authentication**: Only key-based authentication is allowed
- **Firewall**: UFW is enabled with restrictive rules
- **Fail2ban**: Protects against brute force attacks

A summary report is created in `/opt/scripts/provision-summary/` for reference.

## Customization

Before using in production:

- Replace the placeholder SSH keys with your actual public keys
- Review the hardening settings to match your security requirements
- Modify Docker installation settings if needed
- Update system user names if required

## Troubleshooting

Check the logs for detailed information about the provisioning process:

```bash
cat /var/log/post-provision/post-provision.log
journalctl -u post-provision
```

## Security Best Practices

This setup implements:
- SSH key-only authentication
- Firewall protections
- Regular security updates
- System hardening 
- Least privilege principles
- Service minimization

## License

MIT
