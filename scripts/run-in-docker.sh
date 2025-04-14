#!/bin/bash
# Script to run the VM setup in a Docker container for testing

set -eo pipefail

# Configuration
REPO_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
IMAGE_NAME="vm-setup-test"
CONTAINER_NAME="vm-setup-test"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -b, --build     Build the Docker image"
    echo "  -r, --run       Run the container"
    echo "  -c, --clean     Clean up containers and images"
    echo "  -h, --help      Display this help message"
    exit 1
}

# Function to build the Docker image
build_image() {
    echo "Building Docker image..."
    cat > "${REPO_DIR}/Dockerfile" << EOF
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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Enable systemd
RUN cd /lib/systemd/system/sysinit.target.wants/ && \
    rm -f $(ls | grep -v systemd-tmpfiles-setup) && \
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

# Create trigger directory
RUN mkdir -p /etc/provisioning-pending

# Set entrypoint
ENTRYPOINT ["/sbin/init"]
EOF

    docker build -t "${IMAGE_NAME}" "${REPO_DIR}"
    echo "Docker image built successfully."
}

# Function to run the container
run_container() {
    echo "Running container..."
    
    # Check if container already exists
    if docker ps -a | grep -q "${CONTAINER_NAME}"; then
        echo "Container ${CONTAINER_NAME} already exists. Removing..."
        docker rm -f "${CONTAINER_NAME}"
    fi
    
    # Run the container with systemd
    docker run -d --privileged \
        --name "${CONTAINER_NAME}" \
        -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
        --tmpfs /tmp \
        --tmpfs /run \
        --tmpfs /run/lock \
        "${IMAGE_NAME}"
    
    echo "Container is running. To access it:"
    echo "docker exec -it ${CONTAINER_NAME} bash"
    echo ""
    echo "To run setup inside container:"
    echo "docker exec -it ${CONTAINER_NAME} bash -c 'cd /vm-setup && bash install.sh'"
    echo ""
    echo "To check logs:"
    echo "docker exec -it ${CONTAINER_NAME} bash -c 'journalctl -fu post-provision'"
}

# Function to clean up
clean_up() {
    echo "Cleaning up..."
    
    # Stop and remove container if it exists
    if docker ps -a | grep -q "${CONTAINER_NAME}"; then
        docker rm -f "${CONTAINER_NAME}"
    fi
    
    # Remove image if it exists
    if docker images | grep -q "${IMAGE_NAME}"; then
        docker rmi "${IMAGE_NAME}"
    fi
    
    # Remove Dockerfile
    if [ -f "${REPO_DIR}/Dockerfile" ]; then
        rm -f "${REPO_DIR}/Dockerfile"
    fi
    
    echo "Clean up complete."
}

# Parse command line arguments
if [ $# -eq 0 ]; then
    usage
fi

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
        -c|--clean)
            clean_up
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