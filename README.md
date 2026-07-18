# Linux Telemetry Agent (SRE Portfolio)

[![Orchestration: Docker Compose](https://img.shields.io/badge/Orchestration-Docker%20Compose-blue?logo=docker&logoColor=white)](https://docs.docker.com/)
[![Metrics Exporter: Node Exporter](https://img.shields.io/badge/Metrics-Node%20Exporter-orange?logo=prometheus&logoColor=white)](https://github.com/prometheus/node_exporter)
[![Target OS: Linux](https://img.shields.io/badge/Target%20OS-Linux-green?logo=linux&logoColor=white)](https://www.kernel.org/)

A production-ready Linux telemetry exporter deployment script built with **Docker Compose** and **Node Exporter**. Designed to collect, expose, and serve low-level system metrics from a target Linux host on port `9100` to be scraped by centralized monitoring platforms (like Prometheus & Grafana).

---

## 💼 Business Case & Problem Statement

### The Problem
Monitoring production clusters requires collecting telemetry from dozens of separate Linux target servers. Running full Prometheus databases and Grafana servers on every target host:
- **Wastes Host Resources**: Consumes CPU, RAM, and disk storage that should be allocated to core business applications.
- **Fragments Visibility**: Forces operators to visit separate URLs rather than viewing metrics in a centralized dashboard.
- **Creates Setup Inefficiencies**: Manual telemetry agent setups introduce configuration drift and inconsistency across host groups.

### The Solution
This project deploys a lightweight, standalone host metrics exporter:
- **Minimal Footprint**: Deploys only Node Exporter, using less than 15MB of RAM, leaving the host system resources untouched.
- **Standardized Exposure**: Automatically exposes raw system metrics on port `9100/metrics` in a standard format ready for scraping.
- **Zero Config Drift**: Declared as Infrastructure-as-Code via Docker Compose for easy deployment across Ubuntu/Debian server groups.

---

## 🏗️ Architecture & Telemetry Pipeline

```mermaid
flowchart TD
    subgraph "Linux Server (Host Target Node)"
        A["Linux Kernel /proc, /sys"] -->|Exposes hardware stats| B["Node Exporter Container (Port 9100)"]
    end
    
    subgraph "Centralized Monitoring (Separate Cluster)"
        C[("Central Prometheus TSDB")] -->|Pulls metrics (HTTP GET /metrics)| B
        D["Central Grafana Dashboard"] -->|Queries PromQL| C
    end
```

*Data Flow: Linux Host Node Kernel -> Node Exporter (HTTP Port 9100) -> Central Prometheus Scraper -> Central Grafana Visualizer.*

---

## 📁 Repository Structure

```text
.
├── docker-compose.yml              # Container orchestration for Node Exporter agent
├── architecture_diagram.png        # Telemetry pipeline architecture diagram
├── README.md                       # Core documentation
├── LICENSE                         # MIT License
└── scripts/
    └── deploy.sh                   # Ubuntu auto-installer and launch script
```

---

## 🚀 Deployment Guide (Ubuntu/Debian Target)

### Run Deployment Script
On Ubuntu or Debian, the deployment script automatically installs Docker, Docker Compose, curl, and stress tools if they are missing, then launches Node Exporter:

```bash
# Clone the repository and navigate inside
cd /opt/linux-sre

# Make script executable
chmod +x scripts/deploy.sh

# Run with sudo to enable auto-installation of Docker if missing
sudo ./scripts/deploy.sh
```

*Note: For other Linux distributions, pre-install Docker and Docker Compose, then execute `./scripts/deploy.sh`.*

---

## 🔍 Verification & Testing

1. **Verify Metrics Exposure**: Query the metrics endpoint from your terminal or browser:
   ```bash
   curl http://localhost:9100/metrics
   ```
   You should see a clean response listing all metrics starting with `node_` (e.g. `node_cpu_seconds_total`, `node_memory_MemFree_bytes`).

2. **Simulate Alerting Load**: Run a stress test on your host server to verify that the metrics reflect real-time workload changes:
   ```bash
   sudo apt install -y stress
   stress --cpu 4 --timeout 300
   ```

---

## 📊 Core PromQL Metrics Exposed

These are the primary metrics exposed by this agent to be queried by Prometheus:

- **CPU Core Idle Rate**:
  `rate(node_cpu_seconds_total{mode="idle"}[2m])` (Collects idle cpu cycles per core)
- **Active Memory**:
  `node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes` (Real host RAM usage)
- **Filesystem Free Capacity (Bytes)**:
  `node_filesystem_free_bytes{fstype=~"ext4|xfs"}`
- **Ingress Network Traffic (Bytes/sec)**:
  `rate(node_network_receive_bytes_total{device!~"lo|docker.*|veth.*"}[2m])`
- **Disk IO Read Time Rate**:
  `rate(node_disk_read_time_seconds_total[2m])`
