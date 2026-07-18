# Linux Monitoring & Telemetry Platform (SRE Portfolio)

[![Orchestration: Docker Compose](https://img.shields.io/badge/Orchestration-Docker%20Compose-blue?logo=docker&logoColor=white)](https://docs.docker.com/)
[![Metrics: Prometheus](https://img.shields.io/badge/Metrics-Prometheus-orange?logo=prometheus&logoColor=white)](https://prometheus.io/)
[![Visualization: Grafana](https://img.shields.io/badge/Visualization-Grafana-orange?logo=grafana&logoColor=white)](https://grafana.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A production-grade, automated Linux Monitoring Platform designed to collect, store, and visualize host system metrics in real time. Built with **Docker Compose**, **Prometheus**, **Node Exporter**, and **Grafana**, this project is structured according to SRE (Site Reliability Engineering) observability standards.

---

## 💼 Business Case & Problem Statement

### The Problem
Modern enterprise systems face frequent unplanned downtime, high **MTTR (Mean Time to Resolution)**, and inflated cloud budgets due to a lack of infrastructure visibility. Key business challenges include:
- **Unexpected Outages**: Critical host resources (like memory, CPU, or disk) exhaust silently, causing user-facing services to crash and impacting business revenue.
- **High Operational Overhead**: During an incident, SRE and Operations teams waste valuable time manually logging into servers via SSH to run basic CLI tools (`top`, `df -h`, `free -m`) rather than focusing on root cause analysis.
- **Inefficient Capacity Planning**: Without historical trend analysis, teams either over-provision servers (wasted cloud budget) or under-provision them (leading to performance bottlenecks during high-traffic events).

### The Solution
This platform provides a centralized, automated, and containerized **telemetry pipeline** to solve these operational inefficiencies:
- **Proactive Alerting**: Automatically triggers alerts before services fail, using predictive PromQL analytics to forecast when disk space will exhaust (24 hours in advance).
- **Single Source of Truth**: Consolidates host performance data into a unified, rich Grafana dashboard, allowing engineers to identify bottlenecks instantly.
- **Repeatable & Scalable**: Deploys as Infrastructure-as-Code (IaC) via Docker Compose, eliminating configuration drift and manual setup errors.

---


## 🏗️ Architecture & Data Flow

Below is the telemetry data flow of the platform. Node Exporter running on the host system collects low-level kernel metrics, Prometheus scrapes Node Exporter via HTTP pull request, and Grafana reads Prometheus data to render a dynamic dashboard.

![SRE Telemetry Architecture](architecture_diagram.png)

### Mermaid Telemetry Workflow Diagram
```mermaid
flowchart TD
    subgraph "Linux Server (Host System)"
        A["Linux Kernel /proc, /sys"] -->|Exposes hardware stats| B["Node Exporter (Port 9100)"]
    end
    
    subgraph "Docker Containerized Monitoring Stack"
        B -->|Pull metric scrape (15s interval)| C[(Prometheus TSDB Port 9090)]
        C -->|Evaluates alerting rules| D["SRE Alerting Rules (alerts.yml)"]
        E["Grafana Dashboard (Port 3000)"] -->|Query PromQL| C
    end
    
    E -->|Renders SRE Golden Signals| F["SRE Dashboard Panel UI"]
    D -->|Fires| G["Pager/Slack Alerting Target (Extensible)"]
```

---

## 🛠️ Technology Stack

1. **Ubuntu Linux (Host OS)**: The system target to monitor.
2. **Node Exporter (v1.6.1)**: Telemetry collector designed to parse `/proc` and `/sys` to extract system performance details.
3. **Prometheus (v2.45.0 LTS)**: Multi-dimensional time-series database configured with rules engine to parse telemetry data and evaluate metrics.
4. **Grafana (v10.2.0)**: Visual Analytics and dashboard manager. Automatically provisioned with default metrics configurations.

---

## 📁 Repository Structure

```text
.
├── docker-compose.yml              # Multi-container orchestration definition
├── architecture_diagram.png        # Architecture visualization image
├── README.md                       # Comprehensive operations documentation
├── prometheus/
│   ├── prometheus.yml              # Scraping intervals and targets config
│   └── alerts.yml                  # SRE threshold & predictive alert definitions
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasource.yml      # Automated Prometheus datasource binding
│   │   └── dashboards/
│   │       └── dashboard.yml       # Automated dashboard loader mapping
│   └── dashboards/
│       └── linux_dashboard.json    # Polished 9-panel Grafana dashboard
└── scripts/
    └── deploy.sh                   # SRE automation script (Ubuntu setup & verification)
```

---

## 📈 SRE Golden Signals Monitored

SRE principles focus on monitoring the **Four Golden Signals**: Latency, Traffic, Errors, and Saturation. This platform measures these signals across primary subsystems:

| Signal | Target | PromQL Metric Source | Description |
|---|---|---|---|
| **Saturation** | CPU | `node_cpu_seconds_total` | Percentage of CPU cores running non-idle work. |
| **Saturation** | Memory | `node_memory_MemAvailable_bytes` | Real RAM consumption excluding reclaimable cache/buffer buffers. |
| **Saturation** | System Load | `node_load1`, `node_load5`, `node_load15` | Kernel process run queue length relative to CPU core availability. |
| **Saturation** | Disk Space | `node_filesystem_free_bytes` | Storage capacity depletion trends. |
| **Traffic** | Network | `node_network_receive_bytes_total` | Symmetrical ingress (Rx) / egress (Tx) network throughput. |
| **Errors** | Network Errors | `node_network_receive_errs_total` | Counter of physical packet transmission error rates. |
| **Latency** | Disk I/O | `rate(node_disk_read_time_seconds_total)` | Read and write operation roundtrip latency. |

---

## 🚀 Deployment Guide (Ubuntu Linux)

Follow these steps to deploy the platform on an Ubuntu Linux server.

### Prerequisites & Auto-Installation

If you are running on **Ubuntu** or **Debian**, the deployment script (`deploy.sh`) will automatically detect your OS, update packages, and install **Docker Engine**, **Docker Compose**, **curl**, and **stress** if they are missing.

If you are running on another Linux distribution, please verify you have these tools pre-installed:
- **Docker Engine** (v20.10+)
- **Docker Compose** (v2+)

### Installation Steps

1. **Clone or Copy Project Files** to your target Linux directory (e.g., `/opt/linux-sre`):
   ```bash
   cd /opt/linux-sre
   ```

2. **Grant Execution Permission to scripts**:
   ```bash
   chmod +x scripts/deploy.sh
   ```

3. **Run the Deployment Script**:
   Executing the deployment script will check for and auto-install any missing dependencies, perform a syntax validation check on Prometheus configurations, boot the Docker Compose stack, and check the health endpoints:
   ```bash
   sudo ./scripts/deploy.sh
   ```


4. **Verify Container Statuses**:
   Check if all containers are running successfully:
   ```bash
   docker compose ps
   ```

---

## 🔍 Validation & Verification Plan

An SRE deployment must be validated before handing over to operations.

### Step 1: Check Prometheus Scrape Targets
Open your browser and navigate to `http://<your-server-ip>:9090/targets`. You should see two targets in `UP` state:
- `prometheus`: Scrapes its internal telemetry (e.g., query latency).
- `node-exporter`: Scrapes host server metrics via the `host.docker.internal` gateway mapping.

### Step 2: Access the Grafana Dashboard
1. Navigate to `http://<your-server-ip>:3000`.
2. Login with default credentials:
   - **Username**: `admin`
   - **Password**: `admin`
3. Upon first login, Grafana will prompt you to set a strong password.
4. Navigate to **Dashboards** -> **SRE Platform** folder and open the **Linux SRE Performance & Telemetry Dashboard**.
5. The panels will automatically display live statistics from your Ubuntu server!

### Step 3: Trigger System Stress Test (Simulating alerts)
To test CPU and Memory alerting rules, run a stress utility on the Linux host:

```bash
# Install stress test utility
sudo apt install -y stress

# Run stress to occupy 4 CPU threads for 5 minutes
stress --cpu 4 --timeout 300
```
Within 15-30 seconds, watch the **CPU Usage %** panel in Grafana cross the warning threshold, and verify the alert state changes to `Pending`/`Firing` at `http://<your-server-ip>:9090/alerts`.

---

## 📊 PromQL Cheat Sheet (SRE Queries Used)

These are the primary PromQL queries powering the Grafana panels. Use these for debugging or creating additional alerts.

*   **Real CPU Utilization %**:
    ```promql
    100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)
    ```
*   **Memory Available %**:
    ```promql
    (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100
    ```
*   **System Load (5m avg)**:
    ```promql
    node_load5
    ```
*   **Network Read Rate (bytes/sec)**:
    ```promql
    rate(node_network_receive_bytes_total{device!~"lo|docker.*|veth.*"}[2m])
    ```
*   **Disk Read Latency (ms)**:
    ```promql
    rate(node_disk_read_time_seconds_total[5m]) / rate(node_disk_reads_completed_total[5m]) * 1000
    ```

---

## 🛡️ SRE Troubleshooting Reference

*   **Issue: "No Data" on panels**
    *   *Cause*: Prometheus is unable to scrape Node Exporter.
    *   *Solution*: Run `docker logs prometheus` to check for network connection timeouts. Ensure Node Exporter is running on port 9100 on the host (`ss -tulpn | grep 9100`).
*   **Issue: Disk Metrics missing in Table**
    *   *Cause*: Filesystem types are filtered out by the mount points exclusion list.
    *   *Solution*: Check `docker-compose.yml` `--collector.filesystem.mount-points-exclude` regex arguments.
*   **Issue: Docker logs are growing too large**
    *   *Solution*: Set log rotation configurations in `/etc/docker/daemon.json` or docker compose logging configs:
        ```yaml
        logging:
          driver: "json-file"
          options:
            max-size: "10m"
            max-file: "3"
        ```
