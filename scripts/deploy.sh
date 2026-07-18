#!/usr/bin/env bash

# SRE Deployment Script - Native Linux Systemd Daemon Installer
# Installs monitor.sh as a background systemd service with automated log rotation.

set -euo pipefail

# Text formatting helper functions
info() { echo -e "\e[34m[INFO]\e[0m $*"; }
success() { echo -e "\e[32m[SUCCESS]\e[0m $*"; }
warn() { echo -e "\e[33m[WARNING]\e[0m $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 1. Platform check (Must be Linux for systemd and /proc parsing)
info "Checking system operating system..."
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    error "This installer is designed strictly for Linux (Ubuntu/Debian) hosts using systemd."
fi

# 2. Check root privileges (Needed for systemd and logrotate setups)
info "Checking privilege levels..."
if [ "$EUID" -ne 0 ]; then
    error "Please run this installer as root (e.g., 'sudo ./scripts/deploy.sh')."
fi

# 3. Setup Telemetry Script
info "Copying monitor script to /usr/local/bin..."
cp "$SCRIPT_DIR/monitor.sh" /usr/local/bin/linux-monitor
chmod +x /usr/local/bin/linux-monitor
success "Copied and set execution rights on /usr/local/bin/linux-monitor"

# 4. Create Systemd Service File
info "Creating systemd daemon service definition..."
cat <<EOF > /etc/systemd/system/linux-monitor.service
[Unit]
Description=SRE Native Linux Monitoring Agent
After=network.target

[Service]
Type=simple
# Runs in loop mode appending telemetry JSON metrics to the system log file
ExecStart=/usr/local/bin/linux-monitor --log /var/log/linux-monitor.log
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
success "Registered /etc/systemd/system/linux-monitor.service"

# 5. Create Logrotate Configuration (SRE Practice: Avoid infinite disk bloating)
info "Configuring log rotation settings..."
cat <<EOF > /etc/logrotate.d/linux-monitor
/var/log/linux-monitor.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
success "Created log rotation rules at /etc/logrotate.d/linux-monitor"

# 6. Initialize and Boot Daemon
info "Reloading systemd and enabling service..."
systemctl daemon-reload
systemctl enable linux-monitor.service
systemctl restart linux-monitor.service

# 7. Verification check
info "Checking service status..."
sleep 2
if systemctl is-active linux-monitor.service &> /dev/null; then
    success "=========================================================="
    success " SRE Linux Monitoring Agent Service Deployed Successfully! "
    success "=========================================================="
    info "Service status: Active & Running"
    info "Log Location  : /var/log/linux-monitor.log"
    info ""
    info "Telemetry Commands:"
    info " - Check daemon status   : 'systemctl status linux-monitor'"
    info " - Follow JSON metric logs: 'tail -f /var/log/linux-monitor.log'"
    info " - Run interactive dashboard: '/usr/local/bin/linux-monitor --loop'"
else
    error "Service failed to start. Run 'journalctl -u linux-monitor -n 50' to debug."
fi
