#!/bin/bash
# Script to run the VM setup in a Docker container for testing
# This allows testing of the VM setup process in a container environment

set -eo pipefail

# Configuration
REPO_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
IMAGE_NAME="vm-setup-test"
CONTAINER_NAME="vm-setup-test"
LOG_DIR="${REPO_DIR}/logs"
DOCKERFILE="${REPO_DIR}/Dockerfile.test"
mkdir -p "${LOG_DIR}"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -b, --build     Build the Docker image"
    echo "  -r, --run       Run the container"
    echo "  -e, --exec      Execute bash in the running container"
    echo "  -s, --status    Check container status and show provisioning logs"
    echo "  -c, --clean     Clean up containers and images"
    echo "  -a, --all       Build, run, and show status"
    echo "  -h, --help      Display this help message"
    exit 1
}

# Function to check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker first."
        echo "Visit https://docs.docker.com/get-docker/ for installation instructions."
        exit 1
    fi

    # Check if Docker is running
    if ! docker info &> /dev/null; then
        echo "Error: Docker daemon is not running. Please start Docker and try again."
        exit 1
    fi
}

# Function to build the Docker image
build_image() {
    echo "Building Docker image..."
    cat > "${DOCKERFILE}" << EOF
FROM ubuntu:20.04

# Set non-interactive mode
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    sudo \
    systemd \
    openssh-server \
    ufw \
    git \
    curl \
    wget \
    vim \
    gnupg \
    lsb-release \
    ca-certificates \
    apt-transport-https \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Enable systemd
RUN cd /lib/systemd/system/sysinit.target.wants/ && \
    rm -f \$(ls | grep -v systemd-tmpfiles-setup) && \
    rm -f /lib/systemd/system/multi-user.target.wants/* && \
    rm -f /etc/systemd/system/*.wants/* && \
    rm -f /lib/systemd/system/local-fs.target.wants/* && \
    rm -f /lib/systemd/system/sockets.target.wants/*udev* && \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl* && \
    mkdir -p /etc/systemd/system/sshd.service.d

# Setup work directory
WORKDIR /vm-setup

# Copy scripts
COPY . /vm-setup/

# Create test SSH key if not exists
RUN mkdir -p /opt/scripts/config && \
    if [ ! -f "/vm-setup/config/authorized_keys" ]; then \
    echo "ssh-rsa TEST_SSH_KEY_FOR_DOCKER_TESTING" > /opt/scripts/config/authorized_keys; \
    fi

# Set entrypoint
ENTRYPOINT ["/sbin/init"]
EOF

    docker build -t "${IMAGE_NAME}" -f "${DOCKERFILE}" "${REPO_DIR}" | tee "${LOG_DIR}/docker-build.log"
    echo "Docker image built successfully."
}

# Function to run the container
run_container() {
    echo "Running container..."
    
    # Check if container already exists
    if docker ps -a | grep -q "${CONTAINER_NAME}"; then
        echo "Container ${CONTAINER_NAME} already exists. Removing..."
        docker rm -f "${CONTAINER_NAME}" > /dev/null 2>&1 || true
    fi
    
    # Run the container with systemd
    docker run -d --privileged \
        --name "${CONTAINER_NAME}" \
        -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
        --tmpfs /tmp \
        --tmpfs /run \
        --tmpfs /run/lock \
        "${IMAGE_NAME}"
    
    echo "Container is running. Container ID: $(docker ps -q -f name=${CONTAINER_NAME})"
    echo ""
    echo "To access the container, use one of these commands:"
    echo "  $0 -e         # Execute bash in the container"
    echo "  $0 -s         # Check container status"
    echo ""
    echo "To run setup inside container:"
    echo "  docker exec -it ${CONTAINER_NAME} bash -c 'cd /vm-setup && bash install.sh'"
    echo ""
    echo "To create trigger directory:"
    echo "  docker exec -it ${CONTAINER_NAME} mkdir -p /etc/provisioning-pending"
    echo ""
    
    # Wait a few seconds for container to initialize
    sleep 3
    
    # Optional: Automatically run the setup
    if [ "$AUTO_RUN" = "true" ]; then
        echo "Automatically running setup..."
        docker exec -it ${CONTAINER_NAME} bash -c 'cd /vm-setup && bash install.sh'
        echo "Creating trigger directory..."
        docker exec -it ${CONTAINER_NAME} mkdir -p /etc/provisioning-pending
        echo "Setup initiated. Checking status..."
        sleep 5
        check_status
    fi
}

# Function to execute bash in the container
exec_bash() {
    if ! docker ps -q -f name=${CONTAINER_NAME} &> /dev/null; then
        echo "Container ${CONTAINER_NAME} is not running."
        echo "Start it with: $0 -r"
        exit 1
    fi
    
    echo "Executing bash in container ${CONTAINER_NAME}..."
    docker exec -it ${CONTAINER_NAME} bash
}

# Function to check status
check_status() {
    if ! docker ps -q -f name=${CONTAINER_NAME} &> /dev/null; then
        echo "Container ${CONTAINER_NAME} is not running."
        echo "Start it with: $0 -r"
        exit 1
    fi
    
    echo "Container status:"
    docker ps -f name=${CONTAINER_NAME}
    
    echo ""
    echo "Checking for post-provision service status..."
    docker exec ${CONTAINER_NAME} bash -c 'systemctl status post-provision' || true
    
    echo ""
    echo "Recent logs:"
    docker exec ${CONTAINER_NAME} bash -c 'journalctl -u post-provision -n 20' || true
    
    echo ""
    echo "Checking if provisioning completed:"
    docker exec ${CONTAINER_NAME} bash -c 'if [ -f "/opt/scripts/provision-summary/system-info.txt" ]; then cat /opt/scripts/provision-summary/system-info.txt; else echo "Provisioning not yet completed"; fi'
}

# Function to clean up
clean_up() {
    echo "Cleaning up..."
    
    # Stop and remove container if it exists
    if docker ps -a | grep -q "${CONTAINER_NAME}"; then
        echo "Removing container ${CONTAINER_NAME}..."
        docker rm -f "${CONTAINER_NAME}" > /dev/null 2>&1 || true
    fi
    
    # Remove image if it exists
    if docker images | grep -q "${IMAGE_NAME}"; then
        echo "Removing image ${IMAGE_NAME}..."
        docker rmi "${IMAGE_NAME}" > /dev/null 2>&1 || true
    fi
    
    # Remove Dockerfile
    if [ -f "${DOCKERFILE}" ]; then
        rm -f "${DOCKERFILE}"
    fi
    
    echo "Clean up complete."
}

# Function to do everything
do_all() {
    AUTO_RUN="true"
    build_image
    run_container
    # Status check is called by run_container
}

# Parse command line arguments
if [ $# -eq 0 ]; then
    usage
fi

# Check docker installation
check_docker

while [ $# -gt 0 ]; do
    case "$1" in
        -b|--build)
            build_image
            shift
            ;;
        -r|--run)
            run_container
            shift
            ;;
        -e|--exec)
            exec_bash
            shift
            ;;
        -s|--status)
            check_status
            shift
            ;;
        -c|--clean)
            clean_up
            shift
            ;;
        -a|--all)
            do_all
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