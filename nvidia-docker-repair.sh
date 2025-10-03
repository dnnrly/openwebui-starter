#!/usr/bin/env bash

# =======================================================================================
# NVIDIA Docker Deep Repair Script
#
# Purpose:
#   This script performs a comprehensive repair of Docker + NVIDIA GPU integration
#   on Ubuntu. It is intended for use when containers cannot access the GPU due to
#   issues such as:
#     - "nvml error: driver not loaded"
#     - stale runc/containerd state
#     - AppArmor denials
#     - misconfigured runtime settings
#
# Actions performed:
#   - Stops Docker and containerd services
#   - Kills stale runtime processes (runc, containerd-shim)
#   - Backs up and sanitises containerd and Docker configs
#   - Resets AppArmor profiles to complain mode for debugging
#   - Clears stale runtime state directories
#   - Reloads NVIDIA kernel modules (nvidia, nvidia_uvm, etc.)
#   - Validates driver and device node availability
#   - Restarts services (double cycle for stability)
#   - Tests both low-level (nvidia-container-cli) and high-level (CUDA container) checks
#   - Provides a detailed diagnostic report if the container test fails
#
# Use this script if GPU-enabled containers consistently fail to start or
# report driver/runtime errors.
#
# =======================================================================================

set -euo pipefail

echo "--- NVIDIA Docker Repair Script (v8 - Aggressive State Cleanup) ---"
echo "This script will reconfigure containerd, Docker, and perform aggressive cleanups."
echo ""

# --- Dependency & Prerequisite Checks (Same as v7) ---

echo "[1/18] Checking and installing dependencies..."
if ! command -v jq &> /dev/null; then sudo apt-get update && sudo apt-get install -y jq; fi
if ! dpkg-query -W -f='${Status}' nvidia-container-toolkit 2>/dev/null | grep -q "ok installed"; then sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit; else echo "[*] 'nvidia-container-toolkit' is already installed."; fi
if ! dpkg-query -W -f='${Status}' apparmor-utils 2>/dev/null | grep -q "ok installed"; then sudo apt-get update && sudo apt-get install -y apparmor-utils; else echo "[*] 'apparmor-utils' is already installed."; fi
if ! command -v nvidia-ctk &> /dev/null; then echo "[!] FATAL: 'nvidia-ctk' command is missing. Cannot proceed." && exit 1; fi

echo "[2/18] Backing up existing configs..."
if [ -f "/etc/containerd/config.toml" ]; then sudo cp /etc/containerd/config.toml "/etc/containerd/config.toml.bak.$(date +%s)"; fi
if [ -f "/etc/docker/daemon.json" ]; then sudo cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%s)"; fi

# --- Service & Configuration Management ---

echo "[3/18] Stopping services (Docker, containerd) for safe configuration..."
sudo systemctl stop docker.socket || true
sudo systemctl stop docker || true
sudo systemctl stop containerd || true

echo "[4/18] Killing any stale container runtime processes..."
sudo killall -q -9 containerd-shim runc || true

echo "[5/18] Relaxing AppArmor profiles for diagnosis..."
if command -v aa-complain &> /dev/null; then
    echo "[*] Switching container profiles to complain mode."
    sudo aa-complain /etc/apparmor.d/docker-default || true
    sudo aa-complain /usr/bin/containerd || true
else
    echo "[!] WARNING: AppArmor tools not found. Proceeding with caution."
fi

echo "[6/18] Configuring and Validating Containerd for the NVIDIA Runtime..."
if [ ! -f "/etc/containerd/config.toml" ]; then
    echo "[!] Containerd config not found. Generating default."
    sudo mkdir -p /etc/containerd
    sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
fi
echo "[*] Applying NVIDIA runtime configuration to containerd..."
if ! sudo nvidia-ctk runtime configure --runtime=containerd --set-as-default; then
    echo "[!] FATAL: 'nvidia-ctk runtime configure' for containerd failed."
    exit 1
fi

echo "[7/18] Validating containerd config..."
if sudo grep -q '^\s*disabled_plugins\s*=\s*\["cri"\]' /etc/containerd/config.toml; then
    sudo sed -i 's/^\(\s*disabled_plugins\s*=\s*\["cri"\]\)/# \1/' /etc/containerd/config.toml
    echo "[*] Containerd config repaired."
fi

echo "[8/18] Simplifying Docker Daemon configuration (Removing conflicting runtimes)..."
DAEMON_JSON="/etc/docker/daemon.json"
if [ ! -f "${DAEMON_JSON}" ] || ! sudo jq empty "${DAEMON_JSON}" 2>/dev/null; then echo "{}" | sudo tee "${DAEMON_JSON}" >/dev/null; fi
TEMP_DAEMON_JSON=$(mktemp)
# Delete conflicting runtime entries
sudo jq 'del(.runtimes) | del(."default-runtime")' "${DAEMON_JSON}" > "${TEMP_DAEMON_JSON}"
sudo mv "${TEMP_DAEMON_JSON}" "${DAEMON_JSON}"

echo "[9/18] AGGRESSIVE: Clearing stale runc/containerd internal state caches."
# The goal here is to force the services to rebuild the runtime environment from the fresh config
sudo rm -rf /var/lib/docker/containerd/daemon/io.containerd.runtime.v1.linux/* || true
sudo rm -rf /run/containerd/runc/moby/* || true
sudo rm -rf /var/lib/docker/runtimes/nvidia-container-runtime/* || true

echo "[10/18] Reloading systemd daemon..."
sudo systemctl daemon-reload
sleep 1

# --- Host Driver & Kernel Module Health Check ---

echo "[11/18] Checking NVIDIA driver/kernel compatibility and forcing module reload..."
DRIVER_PKG=$(dpkg -l | awk '/nvidia-driver-[0-9]+/ {print $2}' | head -n1 || true)
if [[ -z "${DRIVER_PKG}" ]]; then echo "[!] No NVIDIA driver package found. Please install a driver and reboot." && exit 1; fi
echo "[*] Detected driver package: ${DRIVER_PKG}"

sudo systemctl stop nvidia-persistenced || true
sudo rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia 2>/dev/null || true
sleep 2 # Give 2 seconds for the kernel to fully release the modules
sudo modprobe nvidia
sudo modprobe nvidia_uvm || true
sudo modprobe nvidia_modeset || true
sudo modprobe nvidia_drm || true

echo "[12/18] Verifying NVIDIA device node creation and availability (Critical Wait)..."
MAX_TRIES=20; COUNT=0
while [ $COUNT -lt $MAX_TRIES ]; do
    if [ -c /dev/nvidiactl ] && sudo nvidia-container-cli info > /dev/null 2>&1; then
        echo "[*] NVIDIA device nodes and low-level CLI check passed."
        break
    fi
    echo "[*] Waiting for NVIDIA device nodes and CLI to be ready... (Attempt $((COUNT+1))/$MAX_TRIES)"
    sleep 0.5; COUNT=$((COUNT+1))
done

if [ $COUNT -eq $MAX_TRIES ]; then
    echo "[!] FATAL: NVIDIA device node /dev/nvidiactl and/or 'nvidia-container-cli info' did not become ready."
    exit 1
fi

echo "[13/18] Updating dynamic linker cache (ldconfig)..."
sudo ldconfig

# --- Double Restart for Stability ---

echo "[14/18] Restarting services (Cycle 1)..."
sudo systemctl restart nvidia-persistenced || true
sudo systemctl restart containerd
sudo systemctl restart docker

echo "[15/18] Restarting services (Cycle 2 - Aggressive refresh)..."
sudo systemctl restart containerd
sudo systemctl restart docker

# --- Final Verification ---

echo "[16/18] Waiting for Docker daemon to become fully available..."
MAX_WAIT=20; WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if sudo docker info >/dev/null 2>&1; then break; fi
    sleep 1; WAIT_COUNT=$((WAIT_COUNT+1))
done
if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
    echo "[!] FATAL: Docker daemon failed to start."
    exit 1
fi

echo "[17/18] Testing NVIDIA Container Toolkit (Low-level check)..."
if ! sudo nvidia-container-cli info > /dev/null 2>&1; then
    echo "[!] Low-level 'nvidia-container-cli info' test failed (This check must pass)."
    exit 1
fi

echo "[18/18] Testing CUDA container (High-level check)..."
# Use a common, stable CUDA image for the final test
if sudo docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi ; then
    echo ""
    echo "################################################################"
    echo "    [*] Success! Docker and NVIDIA GPU integration repaired.    "
    echo "################################################################"
    echo "[*] NOTE: AppArmor profiles were set to 'complain' mode for diagnosis."
    echo "[*] To re-enforce them, run: sudo aa-enforce /etc/apparmor.d/*"
    exit 0
else
    echo ""
    echo "[!] CRITICAL FAILURE: The CUDA container test failed."
    echo "    (The error was likely due to the runtime failing to find the device.)"
    echo ""
    echo "================================================================"
    echo "========= DIAGNOSTIC REPORT START (PASTE THIS BLOCK) ==========="
    echo "================================================================"

    echo ""; echo "--- 1. Host 'nvidia-smi' output ---"
    sudo nvidia-smi || echo "[!] nvidia-smi command failed."

    echo ""; echo "--- 2. Docker Daemon Configuration (/etc/docker/daemon.json) ---"
    sudo cat /etc/docker/daemon.json || echo "[!] Could not read /etc/docker/daemon.json"

    echo ""; echo "--- 3. Containerd Configuration (/etc/containerd/config.toml) ---"
    sudo cat /etc/containerd/config.toml | grep -A 10 -B 2 '\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes\]' || sudo cat /etc/containerd/config.toml || echo "[!] Could not read /etc/containerd/config.toml"

    echo ""; echo "--- 4. AppArmor Status ---"
    sudo aa-status || echo "[!] Could not run aa-status. AppArmor may not be installed."

    echo ""; echo "--- 5. NVIDIA Container CLI Info ---"
    sudo nvidia-container-cli info || echo "[!] nvidia-container-cli info failed."

    echo ""; echo "--- 6. System Journal for Containerd (last 2 minutes) ---"
    sudo journalctl -u containerd.service -n 50 --no-pager --since "2 minutes ago" || echo "[!] Could not retrieve containerd logs."

    echo ""; echo "--- 7. System Journal for Docker (last 5 minutes) ---"
    sudo journalctl -u docker.service -n 50 --no-pager --since "2 minutes ago" || echo "[!] Could not retrieve docker logs."

    echo ""; echo "--- 8. Audit Logs for Denied Operations (last 2 minutes) ---"
    sudo journalctl --since "2 minutes ago" | grep -i "audit" | grep -i "denied" || echo "[!] No audit-denied messages found in journal."

    echo ""; echo "================================================================"
    echo "========== DIAGNOSTIC REPORT END (PASTE THIS BLOCK) ============"
    echo "================================================================"

    exit 1
fi
