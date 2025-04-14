#cloud-config
# Cloud-init configuration for secure Ubuntu VM

# Set hostname
hostname: ${vm_settings.hostname}
manage_etc_hosts: true

# Update and install dependencies
package_update: true
package_upgrade: true
packages:
  - git
  - curl
  - wget

# Create a trigger directory for post-provision
bootcmd:
  - mkdir -p /etc/provisioning-pending

# SSH public keys
ssh_authorized_keys:
  - ${ssh_public_key}

# Configure user
users:
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']

# Run setup script
runcmd:
  - export DEBIAN_FRONTEND=noninteractive
  - cd /tmp
  - git clone https://github.com/rheynoapria/vm-setup.git
  - cd vm-setup
  - mkdir -p /opt/scripts/config
  - cp /tmp/vm-setup/config/* /opt/scripts/config/ || true
  - bash install.sh
  - rm -rf /tmp/vm-setup

# Write files
write_files:
  - path: /opt/scripts/config/settings.env
    content: |
      # VM Post-Provisioning Settings
      NEW_USER="${vm_settings.new_user}"
      SSH_PORT=${vm_settings.ssh_port}
      VM_HOSTNAME="${vm_settings.hostname}"
      INSTALL_DOCKER=${vm_settings.install_docker}
      INSTALL_MONITORING=${vm_settings.install_monitoring}
      ENABLE_AUTO_UPDATES=true
    permissions: '0644'
  
  - path: /opt/scripts/config/authorized_keys
    content: |
      ${ssh_public_key}
    permissions: '0644'

# Output all cloud-init logs to the serial console
output: {all: '| tee -a /var/log/cloud-init-output.log'}

# Report cloud-init status to systemd
final_message: "VM setup is complete after $UPTIME seconds" 