#!/bin/bash
set -e # Exit immediately on error

# --- CORPORATE PROXY BYPASS ---
# On Google-managed corporate Macs, context-aware proxy settings can interfere with
# Workstations API endpoints. We disable them for this script to ensure reliable API routing.
export CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE=false
export CLOUDSDK_CONTEXT_AWARE_USE_ECP_HTTP_PROXY=false
export CLOUDSDK_CONTEXT_AWARE_USE_MTLS_FOR_GRPC=false
export GOOGLE_API_CERTIFICATE_CONFIG=""


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

# --- PARSE COMMAND LINE ARGUMENTS ---
MODE="both"
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --cli|-c) MODE="cli" ;;
        --ide|-i) MODE="ide" ;;
        *) echo -e "${RED}❌ Unknown argument: $1${NC}"; exit 1 ;;
    esac
    shift
done

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
    --format="value(state)" 2>/dev/null || true)

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

# 2. Check if a tunnel is already running and active
TUNNEL_ACTIVE=false
if nc -z 127.0.0.1 $LOCAL_PORT >/dev/null 2>&1; then
    TUNNEL_ACTIVE=true
fi

if [ "$TUNNEL_ACTIVE" = "true" ]; then
    echo -e "✅ Secure tunnel already active on port ${BOLD}$LOCAL_PORT${NC}."
else
    # 2. Clean up old tunnels
    pkill -f "start-tcp-tunnel.*$LOCAL_PORT" >/dev/null 2>&1 || true

    # 3. Start Tunnel
    echo -n -e "Opening tunnel on port ${BOLD}$LOCAL_PORT${NC}..."

    TUNNEL_LOG=$(mktemp)
    # We start this in background manually because we need the PID to stay alive
    gcloud workstations start-tcp-tunnel \
      --project=$PROJECT_ID --region=$REGION --cluster=$CLUSTER_ID --config=$CONFIG_ID \
      --local-host-port=:$LOCAL_PORT \
      $WORKSTATION_ID 22 >"$TUNNEL_LOG" 2>&1 &
    TUNNEL_PID=$!

    # Automatically kill tunnel and clean up log file on exit/interrupt
    trap 'kill $TUNNEL_PID 2>/dev/null || true; rm -f "$TUNNEL_LOG" 2>/dev/null' EXIT INT TERM

    # 4. Wait for bridge (Custom Spinner Loop)
    TIMEOUT=30
    COUNT=0
    spinstr='|/-\'

    # FIX: Added >/dev/null 2>&1 to silence 'Connection succeeded!' output
    while ! nc -z 127.0.0.1 $LOCAL_PORT >/dev/null 2>&1; do
        # Check if the tunnel process is still running
        if ! ps -p $TUNNEL_PID >/dev/null; then
            echo -e "\r❌ ${RED}Tunnel process terminated unexpectedly.${NC}"
            echo "-------------------------------------------------------"
            echo -e "${YELLOW}Tunnel Log:${NC}"
            cat "$TUNNEL_LOG"
            echo "-------------------------------------------------------"
            exit 1
        fi

        temp=${spinstr#?}
        # This overwrites the 'Opening tunnel...' line creates a smooth animation
        printf "\r${BLUE}[%c]${NC} Waiting for tunnel bridge..." "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        
        sleep 1
        
        # FIX: Use Pre-increment (++COUNT) to avoid exit code 1 when count is 0
        ((++COUNT))
        
        if [ $COUNT -ge $TIMEOUT ]; then
            echo -e "\r❌ ${RED}Timed out waiting for tunnel.${NC}"
            exit 1
        fi
    done
    echo -e "\r✅ Tunnel Connected!             "
    rm -f "$TUNNEL_LOG"
fi


# 5. Launch Session
if [ "$MODE" = "cli" ]; then
    echo -e "Connecting to remote CLI session via ${BOLD}tmux${NC}..."
    echo -e "Press ${BOLD}Ctrl+D${NC} or exit tmux to close session."
    echo ""
    
    # Establish pseudo-terminal and start/attach remote tmux session with agy and zsh
    ssh -t "$SSH_HOST_ALIAS" "
        cd /home/user 2>/dev/null;
        tmux has-session -t workstation 2>/dev/null && tmux attach-session -t workstation || {
            tmux new-session -d -s workstation -n 'antigravity' -c /home/user && \
            tmux send-keys -t workstation:0 'selected=\$(find /home/user/projects /home/user -mindepth 1 -maxdepth 1 -type d ! -name ".*" 2>/dev/null | sort -u | fzf --prompt=\"Select a Project > \" --height=40% --reverse --border); [ -n \"\$selected\" ] && cd \"\$selected\"; agy' C-m && \
            tmux split-window -h -t workstation:0 -c /home/user && \
            tmux send-keys -t workstation:0 'zsh' C-m && \
            tmux select-pane -t workstation:0.1 && \
            tmux attach-session -t workstation
        }
    "
elif [ "$MODE" = "ide" ]; then
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
else
    # MODE="both"
    # 1. Launch VS Code in the background
    run_step "Launching Visual Studio Code" code --remote ssh-remote+$SSH_HOST_ALIAS $REMOTE_FOLDER

    # 2. Spawning native terminal window for Tmux
    echo -e "Spawning native Mac terminal attaching to Tmux..."
    
    # Use AppleScript to open a new Terminal window, change to the current directory, and run the script with --cli
    CURRENT_DIR=$(pwd)
    osascript -e "tell application \"Terminal\" to do script \"echo; cd '$CURRENT_DIR' && ./connect-workstation.sh --cli\"" >/dev/null 2>&1

    echo ""
    echo "-------------------------------------------------------"
    echo -e "🎉 ${GREEN}${BOLD}Double Session Active!${NC}"
    echo "-------------------------------------------------------"
    echo -e "💻 IDE Path:     $REMOTE_FOLDER (VS Code Remote)"
    echo -e "📟 CLI Session:  tmux (agy + zsh) opened in a new terminal window"
    echo -e "🔌 Tunnel Port:  ${BOLD}$LOCAL_PORT${NC}"
    echo "-------------------------------------------------------"
    echo -e "${YELLOW}⚠️  KEEP THIS PARENT TERMINAL OPEN.${NC}"
    echo "   Closing it will kill the secure background tunnel."
    echo "-------------------------------------------------------"

    # Wait for tunnel process so the script doesn't exit
    if [ -n "$TUNNEL_PID" ]; then
        wait $TUNNEL_PID
    else
        # If the tunnel was already active, we don't have a parent TUNNEL_PID to wait for in this process
        # so we can just wait indefinitely on a sleep or wait on user interaction
        echo "Press Enter or Ctrl+C to disconnect local session."
        read -r
    fi
fi
