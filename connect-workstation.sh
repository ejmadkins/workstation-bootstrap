#!/bin/bash
set -e # Exit immediately on error

# --- COLORS & STYLING ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- VISUAL HELPERS ---

# Wrapper: Runs command quietly with a spinner, handles errors
run_step() {
    local msg="$1"
    shift
    local log_file
    log_file=$(mktemp)

    # Run command in background, redirecting output
    "$@" > "$log_file" 2>&1 &
    local pid=$!
    
    # Spinner Loop
    local delay=0.1
    local spinstr='|/-\'
    
    # While the process is running...
    while ps -p $pid > /dev/null; do
        local temp=${spinstr#?}
        printf "\r${BLUE}[%c]${NC} %s..." "$spinstr" "$msg"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done

    # FIX: Initialize exit_code and use || to prevent 'set -e' from crashing script on error
    local exit_code=0
    wait $pid || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        # Success: Clear line with \r, print checkmark, then newline
        printf "\r✅ %s... Done!       \n" "$msg"
        rm "$log_file"
        return 0
    else
        # Failure: Clear line, print X, keep log
        printf "\r❌ ${RED}%s Failed!${NC}       \n" "$msg"
        echo "-------------------------------------------------------"
        echo -e "${YELLOW}Error Output:${NC}"
        cat "$log_file"
        echo "-------------------------------------------------------"
        rm "$log_file"
        return 1
    fi
}

# --- LOAD CONFIGURATION ---
CONFIG_FILE="./workstation.conf"

# Ensure we print before checking config to prove script is running
echo -e "${BLUE}🚀 Initializing Connection...${NC}"

if [ -f "$CONFIG_FILE" ]; then
    echo -e "📄 Loading configuration from ${BOLD}$CONFIG_FILE${NC}..."
    source "$CONFIG_FILE"
else
    echo -e "${RED}❌ Error: Config file '$CONFIG_FILE' not found.${NC}"
    exit 1
fi

# --- LOCAL SETTINGS ---
LOCAL_PORT=1025
SSH_HOST_ALIAS="my-cloud-workstation" # Must match your ~/.ssh/config Host
REMOTE_FOLDER="/home/user"            # Folder to open in VS Code

# --- SSH CONFIGURATION CHECK ---
# Ensures the SSH alias exists so VS Code can resolve the hostname
echo -n -e "Verifying SSH configuration..."
SSH_CONFIG="$HOME/.ssh/config"
mkdir -p "$HOME/.ssh"
touch "$SSH_CONFIG"

if ! grep -q "Host $SSH_HOST_ALIAS" "$SSH_CONFIG"; then
    cat <<EOF >> "$SSH_CONFIG"

# --- Cloud Workstation Alias (Added by script) ---
Host $SSH_HOST_ALIAS
  HostName 127.0.0.1
  Port $LOCAL_PORT
  User user
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF
    echo -e "\r✅ SSH configuration... Updated!     "
else
    echo -e "\r✅ SSH configuration... OK!          "
fi

echo -e "Target: ${BOLD}$WORKSTATION_ID${NC} ($REGION)"

# 1. Check and Start Workstation
echo -n -e "Checking workstation status..."
STATE=$(gcloud workstations describe $WORKSTATION_ID \
    --project=$PROJECT_ID --region=$REGION --cluster=$CLUSTER_ID --config=$CONFIG_ID \
    --format="value(state)" 2>/dev/null)

if [[ "$STATE" == *"RUNNING"* ]]; then
    echo -e "\r✅ Workstation is already RUNNING.    "
else
    # Use run_step to wrap the long startup process with a spinner
    run_step "Starting Workstation (this may take 1-2 mins)" gcloud workstations start $WORKSTATION_ID \
        --project=$PROJECT_ID --region=$REGION --cluster=$CLUSTER_ID --config=$CONFIG_ID
    
    # Wait a bit for OS to settle
    echo -n "Waiting for OS initialization..."
    sleep 5
    echo -e "\r✅ OS Initialization... Done!       "
fi

# 2. Clean up old tunnels
# We run this quietly (no spinner needed for instant commands)
pkill -f "start-tcp-tunnel.*$LOCAL_PORT" >/dev/null 2>&1 || true

# 3. Start Tunnel
echo -n -e "Opening tunnel on port ${BOLD}$LOCAL_PORT${NC}..."

# We start this in background manually because we need the PID to stay alive
gcloud workstations start-tcp-tunnel \
  --project=$PROJECT_ID --region=$REGION --cluster=$CLUSTER_ID --config=$CONFIG_ID \
  --local-host-port=:$LOCAL_PORT \
  $WORKSTATION_ID 22 >/dev/null 2>&1 &
TUNNEL_PID=$!

# 4. Wait for bridge (Custom Spinner Loop)
TIMEOUT=30
COUNT=0
spinstr='|/-\'

# FIX: Added >/dev/null 2>&1 to silence 'Connection succeeded!' output
while ! nc -z 127.0.0.1 $LOCAL_PORT >/dev/null 2>&1; do
    temp=${spinstr#?}
    # This overwrites the 'Opening tunnel...' line creates a smooth animation
    printf "\r${BLUE}[%c]${NC} Waiting for tunnel bridge..." "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    
    sleep 1
    
    # FIX: Use Pre-increment (++COUNT) to avoid exit code 1 when count is 0
    ((++COUNT))
    
    if [ $COUNT -ge $TIMEOUT ]; then
        echo -e "\r❌ ${RED}Timed out waiting for tunnel.${NC}"
        kill $TUNNEL_PID
        exit 1
    fi
done
echo -e "\r✅ Tunnel Connected!             "

# 5. Launch VS Code
run_step "Launching Visual Studio Code" code --remote ssh-remote+$SSH_HOST_ALIAS $REMOTE_FOLDER

echo ""
echo "-------------------------------------------------------"
echo -e "🎉 ${GREEN}${BOLD}Session Active!${NC}"
echo "-------------------------------------------------------"
echo -e "🔌 Port:         ${BOLD}$LOCAL_PORT${NC}"
echo -e "📂 Remote Path:  $REMOTE_FOLDER"
echo "-------------------------------------------------------"
echo -e "${YELLOW}⚠️  KEEP THIS TERMINAL OPEN.${NC}"
echo "   Closing it will kill the tunnel."
echo "-------------------------------------------------------"

# Wait for tunnel process so the script doesn't exit
wait $TUNNEL_PID
