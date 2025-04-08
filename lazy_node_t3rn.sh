#!/bin/bash

# Function to handle the apt lock issue
handle_apt_lock() {
    local timeout=30  # Timeout in seconds to wait for the lock
    local interval=2  # Interval in seconds between checks
    local elapsed=0

    echo "Checking for apt lock..."
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        if [ $elapsed -ge $timeout ]; then
            echo "Timeout reached. Killing the process holding the lock..."
            # Get the PID of the process holding the lock and kill it
            local pid=$(sudo fuser -v /var/lib/dpkg/lock-frontend 2>/dev/null | awk '{print $1}')
            if [ -n "$pid" ]; then
                echo "Killing process $pid..."
                sudo kill -9 $pid
            fi
            sudo rm -f /var/lib/dpkg/lock-frontend
            sudo rm -f /var/lib/dpkg/lock
            break
        fi
        echo "Waiting for lock to be released..."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    echo "Apt lock cleared."
}

handle_apt_lock
sudo apt install -y curl bc figlet

# Check Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs)
if (( $(echo "$UBUNTU_VERSION < 22.04" | bc -l) )); then
    echo "Minimum required Ubuntu version is 22.04. Update your OS to proceed."
    exit 1
fi

# Read private key from private_key.txt
if [ ! -f private_key.txt ]; then
    echo "Error: private_key.txt not found. Please create this file with your private key."
    exit 1
fi
PRIVATE_KEY=$(cat private_key.txt)

# Download the latest t3rn executor binary
#LATEST_VERSION=$(curl -s https://api.github.com/repos/t3rn/executor-release/releases/latest | grep 'tag_name' | cut -d\" -f4)
LATEST_VERSION="v0.53.1"
EXECUTOR_URL="https://github.com/t3rn/executor-release/releases/download/${LATEST_VERSION}/executor-linux-${LATEST_VERSION}.tar.gz"
curl -L -o executor-linux-${LATEST_VERSION}.tar.gz $EXECUTOR_URL

# Extract the binary and clean up
tar -xzvf executor-linux-${LATEST_VERSION}.tar.gz
rm -rf executor-linux-${LATEST_VERSION}.tar.gz

# Create configuration file
USERNAME=$(whoami)
HOME_DIR=$(eval echo ~$USERNAME)
CONFIG_FILE="$HOME_DIR/executor/executor/bin/.t3rn"

mkdir -p $(dirname $CONFIG_FILE)
cat <<EOT > $CONFIG_FILE
NODE_ENV=testnet
export EXECUTOR_MAX_L3_GAS_PRICE=1500
EXECUTOR_PROCESS_ORDERS=true
ENVIRONMENT=testnet
PRIVATE_KEY_LOCAL=$PRIVATE_KEY
ENABLED_NETWORKS='arbitrum-sepolia,base-sepolia,optimism-sepolia,l2rn'
RPC_ENDPOINTS='{"l2rn": ["https://b2n.rpc.caldera.xyz/http"],"arbt": ["https://arbitrum-sepolia.drpc.org/", "https://sepolia-rollup.arbitrum.io/rpc"],"bast": ["https://base-sepolia-rpc.publicnode.com/", "https://base-sepolia.drpc.org/"],"opst": ["https://sepolia.optimism.io/", "https://optimism-sepolia.drpc.org/"],"unit": ["https://unichain-sepolia.drpc.org/", "https://sepolia.unichain.org/"]
}'
EXECUTOR_MAX_L3_GAS_PRICE=500
EXECUTOR_PROCESS_PENDING_ORDERS_FROM_API=false
EXECUTOR_PROCESS_ORDERS_API_ENABLED=false
EXECUTOR_PROCESS_BIDS_BATCH=true
EXECUTOR_ENABLE_BATCH_BIDDING=true
EOT

# Create systemd service for t3rn
sudo bash -c "cat <<EOT > /etc/systemd/system/t3rn.service
[Unit]
Description=t3rn Service
After=network.target

[Service]
EnvironmentFile=$CONFIG_FILE
ExecStart=$HOME_DIR/executor/executor/bin/executor
WorkingDirectory=$HOME_DIR/executor/executor/bin/
Restart=on-failure
User=$USERNAME

[Install]
WantedBy=multi-user.target
EOT"

# Reload systemd and start the service
sudo systemctl daemon-reload
sudo systemctl enable t3rn
sudo systemctl start t3rn

# Display logs command
echo "To check logs, use: sudo journalctl -u t3rn -f"
