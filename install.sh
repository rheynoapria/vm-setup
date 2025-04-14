#!/bin/bash
set -eo pipefail

# Configuration - Move to a separate .env file in a production environment
SCRIPTS_DIR="/opt/scripts"
SERVICE_NAME="post-provision"
LOG_DIR="/var/log/${SERVICE_NAME}"
CONFIG_DIR="${SCRIPTS_DIR}/config"
UTILS_DIR="${SCRIPTS_DIR}/utils"

# Check if script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Create necessary directories
mkdir -p ${SCRIPTS_DIR}
mkdir -p ${LOG_DIR}
mkdir -p ${CONFIG_DIR}
mkdir -p ${UTILS_DIR}

# Copy post-provisioning script and related files
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
cp "${SCRIPT_DIR}/post-provision.sh" ${SCRIPTS_DIR}/
chmod +x ${SCRIPTS_DIR}/post-provision.sh

# Copy configuration files if they exist in the source
if [ -d "${SCRIPT_DIR}/config" ]; then
    cp -r "${SCRIPT_DIR}/config/"* ${CONFIG_DIR}/
    echo "Configuration files copied to ${CONFIG_DIR}"
fi

# Copy utility scripts if they exist in the source
if [ -d "${SCRIPT_DIR}/scripts" ]; then
    cp -r "${SCRIPT_DIR}/scripts/"* ${UTILS_DIR}/
    chmod +x ${UTILS_DIR}/*.sh 2>/dev/null || true
    echo "Utility scripts copied to ${UTILS_DIR}"
fi

# Install systemd service
cp "${SCRIPT_DIR}/post-provision.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service
systemctl start ${SERVICE_NAME}.service

# Create a simple status checker
cat > ${SCRIPTS_DIR}/check-provision-status.sh << 'EOF'
#!/bin/bash
SERVICE="post-provision.service"
if systemctl is-active --quiet "$SERVICE"; then
    echo "Post-provisioning service is active and waiting for trigger"
    
    # Check if the trigger directory exists
    if [ -d "/etc/provisioning-pending" ]; then
        echo "Trigger directory exists - provisioning should start soon"
    else
        echo "Waiting for trigger directory: /etc/provisioning-pending"
    fi
else
    echo "Post-provisioning service is not running"
    journalctl -u "$SERVICE" --no-pager -n 20
fi

# Check if provisioning already completed
if [ -f "/opt/scripts/provision-summary/system-info.txt" ]; then
    echo "Provisioning has already completed."
    cat "/opt/scripts/provision-summary/system-info.txt"
fi
EOF
chmod +x ${SCRIPTS_DIR}/check-provision-status.sh

# Create a simple script to trigger provisioning
cat > ${SCRIPTS_DIR}/trigger-provision.sh << 'EOF'
#!/bin/bash
TRIGGER_DIR="/etc/provisioning-pending"

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

if [ -f "/opt/scripts/provision-summary/system-info.txt" ]; then
    echo "Provisioning has already completed. Force re-run? (y/N)"
    read answer
    if [[ "${answer,,}" != "y" ]]; then
        echo "Aborted."
        exit 0
    fi
    echo "Removing previous provisioning record..."
    rm -f "/opt/scripts/provision-summary/system-info.txt"
fi

echo "Creating trigger directory: ${TRIGGER_DIR}"
mkdir -p "${TRIGGER_DIR}"
echo "Provisioning has been triggered. Monitor progress with:"
echo "journalctl -fu post-provision"
EOF
chmod +x ${SCRIPTS_DIR}/trigger-provision.sh

echo "Post-provisioning setup installed successfully!"
echo "The system will execute post-provisioning when /etc/provisioning-pending directory is detected."
echo "Run '${SCRIPTS_DIR}/check-provision-status.sh' to check status"
echo "Run '${SCRIPTS_DIR}/trigger-provision.sh' to manually trigger provisioning" 