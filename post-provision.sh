#!/bin/bash
set -eo pipefail

# Base configuration paths 
BASE_CONFIG_DIR="/opt/scripts/config"
BASE_UTILS_DIR="/opt/scripts/utils"
BASE_LOG_DIR="/var/log/post-provision"

# Create log directory if it doesn't exist
mkdir -p "${BASE_LOG_DIR}"
BASE_LOG_FILE="${BASE_LOG_DIR}/post-provision.log"

# Function for base logging (before config load)
base_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${BASE_LOG_FILE}"
}

# Function for error handling (before config load)
base_error_exit() {
    base_log "ERROR: $1"
    exit 1
}

# Load environment variables if available
if [ -f "${BASE_UTILS_DIR}/load-env.sh" ]; then
    base_log "Loading environment variables"
    source "${BASE_UTILS_DIR}/load-env.sh" || base_error_exit "Failed to load environment variables"
    # Config should now be loaded, but set defaults if not
else
    base_log "Environment loader not found, using default values"
fi

# Set defaults if not defined in environment
CONFIG_DIR=${CONFIG_DIR:-"${BASE_CONFIG_DIR}"}
LOG_DIR=${LOG_DIR:-"${BASE_LOG_DIR}"}
LOG_FILE=${LOG_FILE:-"${LOG_DIR}/post-provision.log"}
TRIGGER_DIR=${TRIGGER_DIR:-"/etc/provisioning-pending"}

# Default settings
NEW_USER=${NEW_USER:-"sysadmin"}
SSH_PORT=${SSH_PORT:-2222}
SSH_CONFIG=${SSH_CONFIG:-"/etc/ssh/sshd_config"}
DOCKER_INSTALL=${INSTALL_DOCKER:-true}
CONTAINER_USER=${DOCKER_USER:-"${NEW_USER}"}
CONTAINER_GROUP=${DOCKER_GROUP:-"docker"}
MAX_AUTH_TRIES=${MAX_AUTH_TRIES:-3}
SSH_CLIENT_ALIVE=${SSH_CLIENT_ALIVE_INTERVAL:-300}
FAIL2BAN_BAN_TIME=${FAIL2BAN_BAN_TIME:-86400}
INSTALL_MONITORING=${INSTALL_MONITORING:-true}
ENABLE_AUTO_UPDATES=${ENABLE_AUTO_UPDATES:-true}

# Create log directory if it doesn't exist (may be different from base)
mkdir -p "${LOG_DIR}"

# Function for logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function for error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Function to check required commands
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error_exit "Required command '$1' not found. Please install it."
    fi
}

# Check if script is running as root
if [ "$(id -u)" -ne 0 ]; then
    error_exit "This script must be run as root"
fi

log "Starting post-provisioning setup..."
log "Using configuration: User=${NEW_USER}, SSH Port=${SSH_PORT}, Docker=${DOCKER_INSTALL}"

# Check for required commands
check_command apt
check_command systemctl

# 1. Update the system
log "Updating system packages..."
apt update || error_exit "Failed to update package lists"
apt upgrade -y || error_exit "Failed to upgrade system packages"

# 2. Install essential packages
log "Installing essential packages..."
ESSENTIAL_PACKAGES="curl wget htop net-tools ufw fail2ban vim git unzip sudo apt-transport-https ca-certificates gnupg-agent software-properties-common"
apt install -y $ESSENTIAL_PACKAGES || error_exit "Failed to install essential packages"

# 3. Create new admin user
log "Creating new user: $NEW_USER"

# Check if user already exists
if id "$NEW_USER" &>/dev/null; then
    log "User $NEW_USER already exists. Skipping user creation."
else
    # Create user with home directory
    useradd -m -s /bin/bash "$NEW_USER" || error_exit "Failed to create user $NEW_USER"
    
    # Create .ssh directory for the new user
    USER_HOME="/home/$NEW_USER"
    SSH_DIR="$USER_HOME/.ssh"
    mkdir -p "$SSH_DIR" || error_exit "Failed to create $SSH_DIR"
    
    # Add public key for SSH access
    if [ -f "${CONFIG_DIR}/authorized_keys" ]; then
        cp "${CONFIG_DIR}/authorized_keys" "$SSH_DIR/authorized_keys"
        log "Using SSH key from config directory"
    else
        log "WARNING: No SSH key found in config directory. Creating a placeholder."
        echo "# Replace this with your actual public key" > "$SSH_DIR/authorized_keys"
        echo "ssh-rsa REPLACE_THIS_WITH_YOUR_ACTUAL_PUBLIC_KEY" >> "$SSH_DIR/authorized_keys"
    fi
    
    # Set correct permissions
    chmod 700 "$SSH_DIR" || error_exit "Failed to set permissions on $SSH_DIR"
    chmod 600 "$SSH_DIR/authorized_keys" || error_exit "Failed to set permissions on authorized_keys"
    chown -R "$NEW_USER:$NEW_USER" "$SSH_DIR" || error_exit "Failed to set ownership on $SSH_DIR"
    
    # Grant sudo privileges without password
    echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$NEW_USER"
    chmod 440 /etc/sudoers.d/"$NEW_USER" || error_exit "Failed to set permissions on sudoers file"
    
    log "User $NEW_USER created with SSH key and sudo privileges"
fi

# 3.1. Create user directory in /opt
log "Creating user directory in /opt/$NEW_USER"
if [ ! -d "/opt/$NEW_USER" ]; then
    mkdir -p "/opt/$NEW_USER" || error_exit "Failed to create directory /opt/$NEW_USER"
    chown -R "$NEW_USER:$NEW_USER" "/opt/$NEW_USER" || error_exit "Failed to set ownership on /opt/$NEW_USER"
    chmod 750 "/opt/$NEW_USER" || error_exit "Failed to set permissions on /opt/$NEW_USER"
    log "User directory /opt/$NEW_USER created successfully"
else
    log "Directory /opt/$NEW_USER already exists"
fi

# 4. Configure SSH security
log "Securing SSH..."

# Backup original SSH config if not already backed up
if [ ! -f "${SSH_CONFIG}.bak" ]; then
    cp "$SSH_CONFIG" "${SSH_CONFIG}.bak" || error_exit "Failed to backup SSH config"
fi

# Update SSH configuration
cat > "$SSH_CONFIG" << EOF
# SSH Server Configuration
# Generated by post-provision.sh on $(date)
Port $SSH_PORT
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication settings
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Restrict SSH access to specific users
AllowUsers $NEW_USER

# Security settings
ClientAliveInterval $SSH_CLIENT_ALIVE
ClientAliveCountMax 2
MaxAuthTries $MAX_AUTH_TRIES
MaxSessions 2

# Logging
SyslogFacility AUTH
LogLevel INFO

# Other security settings
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

# 5. Configure UFW (firewall)
log "Setting up firewall (UFW)..."
ufw default deny incoming || error_exit "Failed to set UFW default deny incoming"
ufw default allow outgoing || error_exit "Failed to set UFW default allow outgoing"
ufw allow $SSH_PORT/tcp comment "SSH on custom port" || error_exit "Failed to allow SSH port in UFW"
ufw --force enable || error_exit "Failed to enable UFW"

# 6. Configure fail2ban
log "Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
banaction = iptables-multiport

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = $FAIL2BAN_BAN_TIME  # Default: 24 hours
EOF

systemctl enable fail2ban || error_exit "Failed to enable fail2ban"
systemctl restart fail2ban || error_exit "Failed to restart fail2ban"

# 7. Install Docker if enabled
if [ "$DOCKER_INSTALL" = true ]; then
    log "Installing Docker..."
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        log "Docker is already installed, skipping installation"
    else
        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - || error_exit "Failed to add Docker GPG key"
        
        # Add Docker repository
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" || error_exit "Failed to add Docker repository"
        
        # Install Docker packages
        apt update || error_exit "Failed to update package lists"
        apt install -y docker-ce docker-ce-cli containerd.io || error_exit "Failed to install Docker"
        
        # Create docker group and add user if not already done
        if ! getent group docker > /dev/null; then
            groupadd docker || error_exit "Failed to create docker group"
        fi
        
        if id -nG "$CONTAINER_USER" | grep -qw "$CONTAINER_GROUP"; then
            log "User $CONTAINER_USER already in group $CONTAINER_GROUP"
        else
            usermod -aG docker "$CONTAINER_USER" || error_exit "Failed to add $CONTAINER_USER to docker group"
        fi
        
        # Enable and start Docker service
        systemctl enable docker || error_exit "Failed to enable Docker service"
        systemctl start docker || error_exit "Failed to start Docker service"
        
        log "Docker installed successfully"
    fi
fi

# 8. Additional Linux hardening measures
log "Applying additional system hardening..."

# Set up automatic security updates if enabled
if [ "$ENABLE_AUTO_UPDATES" = true ]; then
    log "Setting up automatic security updates..."
    apt install -y unattended-upgrades || error_exit "Failed to install unattended-upgrades"
    cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Package-Blacklist {
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
fi

# Disable unnecessary services
for service in avahi-daemon cups bluetooth; do
    if systemctl list-unit-files | grep -q "$service"; then
        systemctl disable "$service" || log "Warning: Failed to disable $service"
        systemctl stop "$service" 2>/dev/null || log "Warning: Failed to stop $service"
    fi
done

# Harden sysctl configuration
cat > /etc/sysctl.d/99-security.conf << EOF
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Block SYN attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Protect against TCP time-wait assassination hazards
net.ipv4.tcp_rfc1337 = 1

# Set IPv6 to prefer privacy addresses
net.ipv6.conf.all.use_tempaddr = 2
net.ipv6.conf.default.use_tempaddr = 2
EOF

sysctl -p /etc/sysctl.d/99-security.conf || log "Warning: Failed to apply sysctl settings"

# 9. Setup security auditing and monitoring
if [ "$INSTALL_MONITORING" = true ]; then
    log "Setting up system auditing..."
    apt install -y auditd || error_exit "Failed to install auditd"
    systemctl enable auditd || error_exit "Failed to enable auditd"
    systemctl start auditd || error_exit "Failed to start auditd"
fi

# 10. Restart updated services
log "Restarting services..."
systemctl restart ssh || error_exit "Failed to restart SSH (this might disconnect your session)"

# 11. Create a summary of the changes
mkdir -p /opt/scripts/provision-summary
cat > /opt/scripts/provision-summary/system-info.txt << EOF
Post-Provisioning Summary
------------------------
Date: $(date)
Hostname: $(hostname)
IP Address: $(hostname -I | awk '{print $1}')
User created: $NEW_USER
SSH port: $SSH_PORT
Docker installed: $DOCKER_INSTALL
Monitoring enabled: $INSTALL_MONITORING
Auto updates: $ENABLE_AUTO_UPDATES

Security measures applied:
- System updated
- Firewall enabled (ufw)
- SSH hardened (port $SSH_PORT)
- Fail2ban configured
- System hardening applied
EOF

# Create a basic script to check the system's security
cat > /opt/scripts/check-security.sh << 'EOF'
#!/bin/bash
echo "System Security Check"
echo "--------------------"

# Check if firewall is running
echo -n "Firewall status: "
if ufw status | grep -q "Status: active"; then
    echo "ACTIVE"
else
    echo "INACTIVE (WARNING)"
fi

# Check if fail2ban is running
echo -n "Fail2ban status: "
if systemctl is-active --quiet fail2ban; then
    echo "ACTIVE"
else
    echo "INACTIVE (WARNING)"
fi

# Check SSH configuration
echo -n "SSH root login: "
if grep -q "PermitRootLogin no" /etc/ssh/sshd_config; then
    echo "DISABLED"
else
    echo "ENABLED (WARNING)"
fi

echo -n "SSH password auth: "
if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
    echo "DISABLED"
else
    echo "ENABLED (WARNING)"
fi

# Check for unattended upgrades
echo -n "Auto updates: "
if dpkg -l | grep -q unattended-upgrades; then
    echo "ENABLED"
else
    echo "DISABLED (WARNING)"
fi

# Check Docker
echo -n "Docker: "
if command -v docker &> /dev/null; then
    echo "INSTALLED ($(docker --version))"
else
    echo "NOT INSTALLED"
fi

echo "--------------------"
echo "Recent auth failures (if any):"
grep "Failed password" /var/log/auth.log | tail -5
EOF
chmod +x /opt/scripts/check-security.sh

# Cleanup trigger folder and self-disable the systemd service
log "Cleaning up..."
rm -rf "${TRIGGER_DIR}"
systemctl disable post-provision.service || log "Warning: Failed to disable post-provision service"

log "Post-provisioning setup completed successfully."
log "SSH service is now running on port $SSH_PORT"
log "Please use the user '$NEW_USER' for future SSH connections"
log "You can check system security with: sudo /opt/scripts/check-security.sh"

# Set hostname if configured
if [ -n "${VM_HOSTNAME}" ]; then
    log "Setting hostname to ${VM_HOSTNAME}"
    hostname "${VM_HOSTNAME}" || log "Warning: Failed to set hostname immediately"
    echo "${VM_HOSTNAME}" > /etc/hostname || log "Warning: Failed to update /etc/hostname"
    
    # Update /etc/hosts
    if grep -q "127.0.1.1" /etc/hosts; then
        sed -i "s/127.0.1.1.*/127.0.1.1\t${VM_HOSTNAME}/" /etc/hosts || log "Warning: Failed to update hostname in /etc/hosts"
    else
        echo -e "127.0.1.1\t${VM_HOSTNAME}" >> /etc/hosts || log "Warning: Failed to add hostname to /etc/hosts"
    fi
    
    log "Hostname set, changes will be fully applied after reboot"
fi

exit 0 