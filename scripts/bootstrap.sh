#!/bin/bash
# Bootstrap script for VM setup
# This script automates the secure VM setup process
# Usage: curl -sSL https://raw.githubusercontent.com/rheynoapria/vm-setup/main/scripts/bootstrap.sh | sudo bash
# or with custom hostname: curl -sSL https://raw.githubusercontent.com/rheynoapria/vm-setup/main/scripts/bootstrap.sh | sudo bash -s -- --hostname custom-host
# or with SSH key and hostname: curl -sSL https://raw.githubusercontent.com/rheynoapria/vm-setup/main/scripts/bootstrap.sh | sudo bash -s -- --ssh-key "ssh-rsa AAA..." --hostname custom-host

set -eo pipefail

# Configuration
REPO_URL="https://github.com/rheynoapria/vm-setup.git"
INSTALL_DIR="/tmp/vm-setup"
TRIGGER_DIR="/etc/provisioning-pending"
CONFIG_DIR="/opt/scripts/config"
LOG_FILE="/tmp/bootstrap.log"
SSH_PUBLIC_KEY=""
VM_HOSTNAME=""

# Function for logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function for error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --hostname HOSTNAME   Set the VM hostname"
    echo "  --ssh-key KEY         SSH public key to use"
    echo "  -h, --help            Display this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --hostname)
            VM_HOSTNAME="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_PUBLIC_KEY="$2"
            shift 2
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

log "Starting bootstrap process..."

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    error_exit "This script must be run as root"
fi

# Check OS compatibility
if [ -f /etc/os-release ]; then
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        error_exit "This script is designed for Ubuntu. Detected OS: $ID"
    fi
    log "OS: $PRETTY_NAME"
else
    log "Warning: Unable to determine OS, assuming Ubuntu compatible"
fi

# Install git if not available
if ! command -v git &> /dev/null; then
    log "Installing git..."
    apt-get update || error_exit "Failed to update package lists"
    apt-get install -y git || error_exit "Failed to install git"
fi

# Clone the repository
log "Cloning VM setup repository..."
rm -rf "${INSTALL_DIR}"
git clone "${REPO_URL}" "${INSTALL_DIR}" || error_exit "Failed to clone repository"

# Create config directory if needed
mkdir -p "${CONFIG_DIR}" || error_exit "Failed to create config directory"

# Add SSH key if provided
if [ -n "${SSH_PUBLIC_KEY}" ]; then
    log "Adding provided SSH public key..."
    echo "${SSH_PUBLIC_KEY}" > "${CONFIG_DIR}/authorized_keys"
elif [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    log "Using local SSH public key..."
    cp "$HOME/.ssh/id_rsa.pub" "${CONFIG_DIR}/authorized_keys"
else
    log "No SSH key provided. You'll need to add one manually."
    echo "# Add your public SSH key here" > "${CONFIG_DIR}/authorized_keys"
fi

# Set proper permissions on SSH key
chmod 644 "${CONFIG_DIR}/authorized_keys" || log "Warning: Failed to set permissions on authorized_keys"

# Create settings file if hostname was provided
if [ -n "${VM_HOSTNAME}" ]; then
    log "Setting hostname to ${VM_HOSTNAME}"
    mkdir -p "${CONFIG_DIR}"
    cat > "${CONFIG_DIR}/settings.env" << EOF
# VM Post-Provisioning Settings
VM_HOSTNAME="${VM_HOSTNAME}"
EOF
fi

# Run the installer
log "Running VM setup installer..."
cd "${INSTALL_DIR}" || error_exit "Failed to change to installation directory"
bash install.sh || error_exit "Installation failed"

# Trigger the provisioning process
log "Triggering provisioning process..."
mkdir -p "${TRIGGER_DIR}" || error_exit "Failed to create trigger directory"

# Check if we have a trigger script
if [ -f "/opt/scripts/trigger-provision.sh" ]; then
    log "Running trigger script..."
    bash /opt/scripts/trigger-provision.sh || log "Warning: Trigger script failed, but provisioning may still occur"
fi

log "Bootstrap complete! Provisioning will run automatically."
log "Monitor progress with: journalctl -fu post-provision"
log "When provisioning completes, check status with: /opt/scripts/check-provision-status.sh"

# Display connection information
if [ -f "${CONFIG_DIR}/settings.env" ]; then
    source "${CONFIG_DIR}/settings.env"
    SSH_PORT=${SSH_PORT:-2222}
    NEW_USER=${NEW_USER:-sysadmin}
    HOSTNAME_INFO=${VM_HOSTNAME:-$(hostname -f)}
    echo ""
    echo "================================================================"
    echo "When provisioning completes, connect with:"
    echo "ssh -p ${SSH_PORT} ${NEW_USER}@$(hostname -I | awk '{print $1}')"
    echo "Hostname has been set to: ${HOSTNAME_INFO}"
    echo "================================================================"
fi

exit 0 