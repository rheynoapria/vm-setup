#!/bin/bash
# Bootstrap script for VM setup
# This script can be used as part of cloud-init user-data or run directly after VM creation

set -eo pipefail

# Configuration
REPO_URL="https://github.com/yourusername/vm-setup.git"
INSTALL_DIR="/tmp/vm-setup"
TRIGGER_DIR="/etc/provisioning-pending"
CONFIG_DIR="/opt/scripts/config"
SSH_PUBLIC_KEY="$1"  # Optional: SSH public key can be passed as first argument

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Install git if not available
if ! command -v git &> /dev/null; then
    apt-get update
    apt-get install -y git
fi

# Clone the repository
echo "Cloning VM setup repository..."
rm -rf "${INSTALL_DIR}"
git clone "${REPO_URL}" "${INSTALL_DIR}"

# Create config directory if needed
mkdir -p "${CONFIG_DIR}"

# Add SSH key if provided
if [ -n "${SSH_PUBLIC_KEY}" ]; then
    echo "Adding provided SSH public key..."
    echo "${SSH_PUBLIC_KEY}" > "${CONFIG_DIR}/authorized_keys"
elif [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    echo "Using local SSH public key..."
    cp "$HOME/.ssh/id_rsa.pub" "${CONFIG_DIR}/authorized_keys"
fi

# Run the installer
echo "Running VM setup installer..."
cd "${INSTALL_DIR}"
bash install.sh

# Trigger the provisioning process
echo "Triggering provisioning process..."
mkdir -p "${TRIGGER_DIR}"

echo "Bootstrap complete! Provisioning will run automatically."
echo "Monitor progress with: journalctl -fu post-provision" 