#!/usr/bin/env bash

# SRE Deployment Automation Script for Linux Monitoring Platform
# Safe-guards deployment via dependency checking and config validation.

set -euo pipefail

# Determine directory paths relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Text formatting helper functions
info() { echo -e "\e[34m[INFO]\e[0m $*"; }
success() { echo -e "\e[32m[SUCCESS]\e[0m $*"; }
warn() { echo -e "\e[33m[WARNING]\e[0m $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }

# 1. Platform check (Must be Linux for Node Exporter to bind host metrics natively)
info "Checking system operating system..."
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    warn "This script is designed for Linux (Ubuntu). Running on non-Linux systems might result in inaccurate Node Exporter statistics."
fi

# 2. Prerequisites Check and Automatic Installation for Ubuntu/Debian
COMPOSE_CMD=""
if [[ "$OSTYPE" == "linux-gnu"* ]] && [ -f /etc/os-release ] && grep -qi "ubuntu\|debian" /etc/os-release; then
    info "Ubuntu/Debian system detected. Starting prerequisite installation check..."
    
    # Check/Install curl
    if ! command -v curl &> /dev/null; then
        info "Installing curl..."
        sudo apt-get update
        sudo apt-get install -y curl
    fi

    # Check/Install Docker
    if ! command -v docker &> /dev/null; then
        info "Docker is not installed. Installing Docker via apt..."
        sudo apt-get update
        sudo apt-get install -y docker.io
        sudo systemctl start docker
        sudo systemctl enable docker
        success "Docker installed successfully."
    else
        info "Docker is already installed."
    fi

    # Check/Install Docker Compose
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        info "Docker Compose is not installed. Installing docker-compose-v2 plugin..."
        sudo apt-get update
        if sudo apt-get install -y docker-compose-v2 &> /dev/null; then
            COMPOSE_CMD="docker compose"
        elif sudo apt-get install -y docker-compose &> /dev/null; then
            COMPOSE_CMD="docker-compose"
        else
            error "Failed to install Docker Compose automatically. Please install it manually."
        fi
        success "Docker Compose installed successfully."
    fi

    # Check/Install stress (for SRE dashboard alerts validation)
    if ! command -v stress &> /dev/null; then
        info "Installing stress test utility (for simulating high CPU/RAM alert thresholds)..."
        sudo apt-get install -y stress || warn "Could not install stress utility, but continuing deployment..."
    fi
else
    # Non-Ubuntu/Debian fallback: only check, do not install automatically
    warn "Non-Ubuntu/Debian system or non-Linux host. Skipping auto-installation."
    
    # Standard check for docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first: https://docs.docker.com/engine/install/"
    fi

    # Standard check for compose
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        error "Docker Compose (v2 or v1) is not found. Please install it first: https://docs.docker.com/compose/install/"
    fi
    success "Found Compose command: '$COMPOSE_CMD'"
fi

# 3. Starting the Agent Stack
info "Launching the Node Exporter metrics agent..."
$COMPOSE_CMD -f "$PROJECT_ROOT/docker-compose.yml" --project-directory "$PROJECT_ROOT" up -d

# 4. Post-deployment Health and Readiness Checks
info "Waiting for Node Exporter to become ready..."

check_endpoint() {
    local name=$1
    local url=$2
    local retries=12
    local wait_sec=5
    
    for ((i=1; i<=retries; i++)); do
        # Node Exporter returns 200 OK on its main endpoint
        if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -E "200" &> /dev/null; then
            success "$name is reachable and running!"
            return 0
        fi
        info "Waiting for $name... (attempt $i/$retries)"
        sleep $wait_sec
    done
    error "$name failed to start or is unreachable on $url after $((retries * wait_sec)) seconds."
}

# Check Node Exporter
check_endpoint "Node Exporter Telemetry Agent" "http://localhost:9100/metrics"

success "=========================================================="
success " Linux Telemetry Agent Deployed Successfully!            "
success "=========================================================="
info "Metrics URL:"
info " - Node Exporter Endpoint : http://localhost:9100/metrics"
info ""
info "To inspect active logs, run: '$COMPOSE_CMD -f $PROJECT_ROOT/docker-compose.yml --project-directory $PROJECT_ROOT logs -f'"
info "To tear down the agent, run: '$COMPOSE_CMD -f $PROJECT_ROOT/docker-compose.yml --project-directory $PROJECT_ROOT down'"

