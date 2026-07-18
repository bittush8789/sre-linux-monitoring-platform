#!/usr/bin/env bash

# SRE Native Linux Monitoring Agent
# Collects CPU, memory, disk, network, load, uptime, and process count by parsing /proc filesystem directly.
# Output modes: --loop (Dashboard), --once (Single Print), --json (Structured Output)

set -euo pipefail

# ANSI color codes for premium terminal aesthetics
RESET="\e[0m"
BOLD="\e[1m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
CYAN="\e[36m"
MAGENTA="\e[35m"
WHITE="\e[37m"

# Default configuration
MODE="loop"
LOG_FILE=""

show_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --once      Collect and print metrics once, then exit."
    echo "  --loop      Run in an interactive loop (default)."
    echo "  --json      Output metrics in structured JSON format once."
    echo "  --log <file> Append metrics in JSON format to a log file."
    echo "  -h, --help  Show this help message."
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --once)
            MODE="once"
            shift
            ;;
        --loop)
            MODE="loop"
            shift
            ;;
        --json)
            MODE="json"
            shift
            ;;
        --log)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}[ERROR]${RESET} --log requires a file path."
                exit 1
            fi
            LOG_FILE="$2"
            MODE="log"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo -e "${RED}[ERROR]${RESET} Unknown option: $1"
            show_usage
            ;;
    esac
done

# 1. Collect System Uptime from /proc/uptime
get_uptime() {
    if [ -f /proc/uptime ]; then
        read -r uptime_seconds _ < /proc/uptime
        # Convert to float to integer
        uptime_seconds=${uptime_seconds%.*}
        
        local days=$((uptime_seconds / 86400))
        local hours=$(( (uptime_seconds % 86400) / 3600 ))
        local mins=$(( (uptime_seconds % 3600) / 60 ))
        local secs=$(( uptime_seconds % 60 ))
        
        if [ "$days" -gt 0 ]; then
            echo "${days}d ${hours}h ${mins}m"
        elif [ "$hours" -gt 0 ]; then
            echo "${hours}h ${mins}m ${secs}s"
        else
            echo "${mins}m ${secs}s"
        fi
    else
        echo "Unknown"
    fi
}

# 2. Calculate CPU Usage % from /proc/stat
get_cpu_usage() {
    # Read /proc/stat twice with a 1 second delay to calculate CPU delta
    read -r _ user nice system idle iowait irq softirq steal guest guest_nice < <(grep '^cpu ' /proc/stat)
    
    local prev_idle=$((idle + iowait))
    local prev_non_idle=$((user + nice + system + irq + softirq + steal))
    local prev_total=$((prev_idle + prev_non_idle))
    
    sleep 1
    
    read -r _ user nice system idle iowait irq softirq steal guest guest_nice < <(grep '^cpu ' /proc/stat)
    
    local idle=$((idle + iowait))
    local non_idle=$((user + nice + system + irq + softirq + steal))
    local total=$((idle + non_idle))
    
    local total_d=$((total - prev_total))
    local idle_d=$((idle - prev_idle))
    
    if [ "$total_d" -eq 0 ]; then
        echo "0.00"
        return
    fi
    
    # Calculate CPU percentage using bc or basic bash arithmetic
    # Usage % = (Total - Idle) / Total * 100
    local cpu_perc
    cpu_perc=$(awk "BEGIN {print (($total_d - $idle_d) / $total_d) * 100}")
    printf "%.2f" "$cpu_perc"
}

# 3. Collect Memory Metrics from /proc/meminfo
get_memory_metrics() {
    local mem_total=0
    local mem_free=0
    local mem_available=0
    
    while read -r name value unit; do
        case "$name" in
            MemTotal:) mem_total=$value ;;
            MemFree:) mem_free=$value ;;
            MemAvailable:) mem_available=$value ;;
        esac
    done < /proc/meminfo
    
    # MemAvailable includes buffer/cache reclaimable space, matching free command
    local mem_used=$((mem_total - mem_available))
    local mem_used_mb=$((mem_used / 1024))
    local mem_total_mb=$((mem_total / 1024))
    local mem_usage_pct
    mem_usage_pct=$(awk "BEGIN {print ($mem_used / $mem_total) * 100}")
    
    echo "$mem_used_mb $mem_total_mb $(printf "%.2f" "$mem_usage_pct")"
}

# 4. Collect System Load Average from /proc/loadavg
get_load_average() {
    if [ -f /proc/loadavg ]; then
        read -r load1 load5 load15 _ < /proc/loadavg
        echo "$load1 $load5 $load15"
    else
        echo "0.00 0.00 0.00"
    fi
}

# 5. Count Running Processes by counting numeric folders in /proc
get_process_count() {
    # Count directories starting with digits in /proc
    find /proc -maxdepth 1 -name '[0-9]*' | wc -l
}

# 6. Collect Disk Space Metrics using df command
get_disk_usage() {
    # Returns percentage and used/total GB on root mount
    local disk_info
    disk_info=$(df -B1 / | tail -n 1)
    local total_bytes
    total_bytes=$(echo "$disk_info" | awk '{print $2}')
    local used_bytes
    used_bytes=$(echo "$disk_info" | awk '{print $3}')
    
    local total_gb
    total_gb=$(awk "BEGIN {print $total_bytes / 1073741824}")
    local used_gb
    used_gb=$(awk "BEGIN {print $used_bytes / 1073741824}")
    local usage_pct
    usage_pct=$(awk "BEGIN {print ($used_bytes / $total_bytes) * 100}")
    
    echo "$(printf "%.2f" "$used_gb") $(printf "%.2f" "$total_gb") $(printf "%.2f" "$usage_pct")"
}

# 7. Collect Network Traffic from /proc/net/dev (ignoring loopback)
get_network_traffic() {
    # Reads stats twice to compute bytes per second rate
    local active_iface=""
    # Find primary non-loopback interface
    active_iface=$(awk '{print $1}' /proc/net/dev | grep -v -E 'lo|face|Inter' | head -n 1 | tr -d ':')
    
    if [ -z "$active_iface" ]; then
        echo "0 0 $active_iface"
        return
    fi
    
    local prev_rx
    prev_rx=$(grep "$active_iface:" /proc/net/dev | awk '{print $2}')
    local prev_tx
    prev_tx=$(grep "$active_iface:" /proc/net/dev | awk '{print $10}')
    
    sleep 1
    
    local curr_rx
    curr_rx=$(grep "$active_iface:" /proc/net/dev | awk '{print $2}')
    local curr_tx
    curr_tx=$(grep "$active_iface:" /proc/net/dev | awk '{print $10}')
    
    local rx_rate=$((curr_rx - prev_rx))
    local tx_rate=$((curr_tx - prev_tx))
    
    echo "$rx_rate $tx_rate $active_iface"
}

# Threshold coloring helper
color_threshold() {
    local val=$1
    local warn=$2
    local crit=$3
    
    if (( $(echo "$val >= $crit" | bc -l) )); then
        echo -e "${RED}${val}%${RESET}"
    elif (( $(echo "$val >= $warn" | bc -l) )); then
        echo -e "${YELLOW}${val}%${RESET}"
    else
        echo -e "${GREEN}${val}%${RESET}"
    fi
}

# Render terminal dashboard
render_dashboard() {
    # Clear screen using ANSI codes
    printf "\033[H\033[2J"
    
    local host_name
    host_name=$(hostname)
    local curr_time
    curr_time=$(date +"%Y-%m-%d %H:%M:%S")
    local uptime_str
    uptime_str=$(get_uptime)
    
    echo -e "${CYAN}=========================================================================${RESET}"
    echo -e " ${BOLD}${WHITE}SRE NATIVE LINUX SYSTEM MONITOR${RESET}   |  Target Host: ${GREEN}${host_name}${RESET}"
    echo -e " Local Time: ${CYAN}${curr_time}${RESET}      |  Uptime: ${CYAN}${uptime_str}${RESET}"
    echo -e "${CYAN}=========================================================================${RESET}"
    
    # 1. CPU & Load
    info "Calculating CPU Telemetry..."
    local cpu
    cpu=$(get_cpu_usage)
    local load
    load=$(get_load_average)
    read -r load1 load5 load15 <<< "$load"
    local procs
    procs=$(get_process_count)
    
    echo -e " ${BOLD}SYSTEM STATE:${RESET}"
    echo -e "  CPU Usage        : $(color_threshold "$cpu" 75 90)"
    echo -e "  Load Averages    : 1m: ${CYAN}${load1}${RESET} | 5m: ${CYAN}${load5}${RESET} | 15m: ${CYAN}${load15}${RESET}"
    echo -e "  Total Processes  : ${CYAN}${procs}${RESET}"
    echo ""
    
    # 2. Memory
    read -r mem_used mem_total mem_pct <<< "$(get_memory_metrics)"
    echo -e " ${BOLD}MEMORY SATURATION:${RESET}"
    echo -e "  RAM Usage        : $(color_threshold "$mem_pct" 80 95) (${mem_used}MB / ${mem_total}MB)"
    
    # Simple ASCII Bar indicator
    local bar_size=30
    local filled=$(( (mem_pct * bar_size) / 100 ))
    local empty=$(( bar_size - filled ))
    printf "  Memory Bar       : ["
    for ((i=0; i<filled; i++)); do printf "#"; done
    for ((i=0; i<empty; i++)); do printf " "; done
    printf "] %s%%\n" "$mem_pct"
    echo ""
    
    # 3. Disk Space
    read -r disk_used disk_total disk_pct <<< "$(get_disk_usage)"
    echo -e " ${BOLD}DISK CAPACITY:${RESET}"
    echo -e "  Root Filesystem  : $(color_threshold "$disk_pct" 85 95) (${disk_used}GB / ${disk_total}GB)"
    echo ""
    
    # 4. Network Ingress/Egress
    read -r rx tx iface <<< "$(get_network_traffic)"
    local rx_kb
    rx_kb=$(awk "BEGIN {print $rx / 1024}")
    local tx_kb
    tx_kb=$(awk "BEGIN {print $tx / 1024}")
    
    echo -e " ${BOLD}NETWORK TRAFFIC (${iface:-None}):${RESET}"
    echo -e "  Receive (Rx)     : ${GREEN}$(printf "%.2f" "$rx_kb") KB/s${RESET}"
    echo -e "  Transmit (Tx)    : ${YELLOW}$(printf "%.2f" "$tx_kb") KB/s${RESET}"
    echo -e "${CYAN}=========================================================================${RESET}"
    echo -e " Press [Ctrl+C] to exit the monitoring loop."
}

# Generate metrics in JSON format
generate_json() {
    local host_name
    host_name=$(hostname)
    local cpu
    cpu=$(get_cpu_usage)
    read -r load1 load5 load15 <<< "$(get_load_average)"
    local procs
    procs=$(get_process_count)
    read -r mem_used mem_total mem_pct <<< "$(get_memory_metrics)"
    read -r disk_used disk_total disk_pct <<< "$(get_disk_usage)"
    read -r rx tx iface <<< "$(get_network_traffic)"
    
    # Structured SRE Log Entry JSON
    cat <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "hostname": "$host_name",
  "uptime": "$(get_uptime)",
  "metrics": {
    "cpu_usage_percent": $cpu,
    "load_average": {
      "1m": $load1,
      "5m": $load5,
      "15m": $load15
    },
    "process_count": $procs,
    "memory": {
      "total_mb": $mem_total,
      "used_mb": $mem_used,
      "usage_percent": $mem_pct
    },
    "disk": {
      "total_gb": $disk_total,
      "used_gb": $disk_used,
      "usage_percent": $disk_pct
    },
    "network": {
      "interface": "$iface",
      "rx_bytes_sec": $rx,
      "tx_bytes_sec": $tx
    }
  }
}
EOF
}

# Execution modes execution
case "$MODE" in
    once)
        render_dashboard
        ;;
    loop)
        # Traps interrupt to restore terminal settings cleanly
        trap "exit 0" SIGINT SIGTERM
        while true; do
            render_dashboard
            sleep 3
        done
        ;;
    json)
        generate_json
        ;;
    log)
        # Verify write permissions
        if touch "$LOG_FILE" 2>/dev/null; then
            generate_json >> "$LOG_FILE"
            echo "Metrics successfully logged to $LOG_FILE"
        else
            echo -e "${RED}[ERROR]${RESET} Cannot write to log file $LOG_FILE"
            exit 1
        fi
        ;;
esac
