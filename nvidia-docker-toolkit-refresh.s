#!/bin/bash

echo "--- NVIDIA Repository Fix and Final Installation ---"
echo "This script re-adds the NVIDIA Container Toolkit repository and performs the installation."
echo ""

# Define critical variables
DAEMON_JSON="/etc/docker/daemon.json"
TEST_IMAGE="nvidia/cuda:12.2.0-base-ubuntu22.04"

# --- 1. Re-add NVIDIA Container Toolkit Repository ---
echo "[1/6] Setting up official NVIDIA Container Toolkit repository..."
# Download and install the GPG key
if ! curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg; then
    echo "[!] ERROR: Failed to download GPG key. Check internet connection or curl installation."
    exit 1
fi

# Add the repository source list
# Using 'stable' debian/ubuntu path
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

# Fix the deb line format for apt security warnings
sudo sed -i 's/^deb /deb [signed-by=\/usr\/share\/keyrings\/nvidia-container-toolkit-keyring.gpg] /' /etc/apt/sources.list.d/nvidia-container-toolkit.list
echo "[*] Repository sources successfully updated."

# --- 2. Update Package Lists ---
echo "[2/6] Running apt update..."
sudo apt-get update

# --- 3. Reinstall Toolkit ---
echo "[3/6] Installing nvidia-container-toolkit..."
sudo apt-get install -y nvidia-container-toolkit

# --- 4. Configure Containerd and Docker ---
echo "[4/6] Configuring containerd (Setting 'nvidia' as default runtime for CRI)..."
if ! sudo nvidia-ctk runtime configure --runtime=containerd --set-as-default; then
    echo "[!] WARNING: 'nvidia-ctk runtime configure' failed. The system may need a reboot."
fi

# We already configured Docker daemon.json in the previous script, just need to ensure services are fresh.
sudo systemctl daemon-reload

# --- 5. Restart Services ---
echo "[5/6] Restarting Docker and Containerd services..."
sudo systemctl restart containerd
sudo systemctl restart docker

# Wait for Docker to be ready
sleep 5

# --- 6. Rerun the container test ---
echo "--- [6/6] Final CUDA container test ---"
TEST_COMMAND="docker run --rm --gpus all $TEST_IMAGE nvidia-smi"
echo "Command: $TEST_COMMAND"

if $TEST_COMMAND; then
    echo "================================================================"
    echo "[*] SUCCESS: The NVIDIA container runtime is now working!"
    echo "================================================================"
else
    EXIT_CODE=$?
    echo "================================================================"
    echo "[!] FAILURE: The container test failed again (Exit code $EXIT_CODE)."
    echo "[!] CRITICAL NEXT STEP: You must reboot your system now to finalize the driver links."
    echo "    >>> sudo reboot <<<"
    echo "================================================================"
fi
