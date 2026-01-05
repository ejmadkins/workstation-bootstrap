#!/bin/bash
set -e # Exit immediately on error

# Default path to config
CONFIG_FILE="./workstation.conf"
REBUILD_IMAGE=false

# --- COLORS & STYLING ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- HELP FUNCTION ---
show_help() {
    echo -e "${BOLD}Cloud Workstation Provisioner${NC}"
    echo "-----------------------------"
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -r, --rebuild    Force a rebuild of the custom Docker image"
    echo "  -c, --config     Specify a custom config file (default: ./workstation.conf)"
    echo ""
}

# --- ARGUMENT PARSING ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--rebuild)
            REBUILD_IMAGE=true
            shift
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

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
        # \r moves cursor to start of line. We reprint the message + spinner.
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
if [ -f "$CONFIG_FILE" ]; then
    echo -e "📄 Loading configuration from ${BOLD}$CONFIG_FILE${NC}..."
    source "$CONFIG_FILE"
else
    echo -e "${RED}❌ Error: Config file '$CONFIG_FILE' not found.${NC}"
    exit 1
fi

# Construct derived variable (Full Image Tag)
FULL_IMAGE_TAG="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:latest"

# --- CALCULATE SERVICE ACCOUNT ---
# We use a subshell to capture output without showing it, unless it fails
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)" 2>/dev/null) || { echo -e "${RED}❌ Failed to get project number.${NC}"; exit 1; }
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo -e "🤖 Service Account: ${BOLD}$COMPUTE_SA${NC}"

echo -e "${BLUE}🚀 Starting Provisioning for '$PROJECT_ID'...${NC}"

# 1. Enable Core APIs
run_step "Enabling Core APIs" gcloud services enable workstations.googleapis.com compute.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com

# ---------------------------------------------------------
# FUNCTION: Build Custom Image (Dynamic Variables)
# ---------------------------------------------------------
build_image() {
    echo -e "\n${BLUE}--- 🔨 Starting Image Build Process ---${NC}"

    # 1. Setup Build Context
    BUILD_DIR="$(mktemp -d)"
    
    if [ ! -d "./resources" ]; then
        echo -e "${RED}❌ Error: './resources' folder missing.${NC}"
        rm -rf "$BUILD_DIR"
        exit 1
    fi
    cp -r ./resources "$BUILD_DIR/"
    
    # 2. Generate Dockerfile
    cat <<EOF > "$BUILD_DIR/Dockerfile"
FROM $BASE_IMAGE
ENV DEBIAN_FRONTEND=noninteractive

# --- DYNAMIC GIT CONFIG ---
ENV GIT_NAME="$GIT_NAME"
ENV GIT_EMAIL="$GIT_EMAIL"
ENV GITLAB_GROUP="$GITLAB_GROUP"

# --- SYSTEM TOOLS ---
RUN apt-get update && apt-get install -y \
    zsh git curl jq wget unzip python3-pip \
    && rm -rf /var/lib/apt/lists/*

# --- GITLAB CLI ---
RUN curl -LO https://gitlab.com/gitlab-org/cli/-/releases/v1.49.0/downloads/glab_1.49.0_linux_amd64.deb && \
    dpkg -i glab_1.49.0_linux_amd64.deb && \
    rm glab_1.49.0_linux_amd64.deb

# --- FZF SETUP ---
RUN git clone --depth 1 https://github.com/junegunn/fzf.git /etc/skel/.fzf
RUN /etc/skel/.fzf/install --all --no-bash --no-fish --no-update-rc

# --- ZSH SETUP ---
ENV ZSH=/etc/skel/.oh-my-zsh
RUN sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
RUN git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \${ZSH}/custom/themes/powerlevel10k
RUN git clone https://github.com/zsh-users/zsh-autosuggestions \${ZSH}/custom/plugins/zsh-autosuggestions
RUN git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \${ZSH}/custom/plugins/zsh-syntax-highlighting

COPY resources/zsh/.zshrc /etc/skel/.zshrc
COPY resources/zsh/.p10k.zs* /etc/skel/.p10k.zsh

# --- WORKSPACE SETUP ---
RUN mkdir -p /etc/skel/projects
RUN mkdir -p /etc/skel/.vscode
COPY resources/code/tasks.json /etc/skel/.vscode/tasks.json

# --- VS CODE SETTINGS ---
RUN mkdir -p /etc/skel/.codeoss-cloudworkstations/data/Machine
COPY resources/code/settings.json /etc/skel/.codeoss-cloudworkstations/data/Machine/settings.json

# --- GEMINI CONFIG ---
RUN mkdir -p /etc/skel/.config/gemini
COPY resources/gemini/settings.json /etc/skel/.config/gemini/settings.json

ENV SHELL=/usr/bin/zsh

# --- EXTENSIONS INSTALLATION ---
COPY resources/code/extensions.txt /tmp/extensions.txt

# 1. Install to /opt/code-oss/extensions (Global Location)
RUN grep -v '^#' /tmp/extensions.txt | grep -v '^$' | grep -v ' ' | \\
    xargs -I {} sh -c 'echo "Installing {}..."; /opt/code-oss/bin/codeoss-cloudworkstations --extensions-dir /opt/code-oss/extensions --install-extension {} --force || echo "⚠️ Failed to install {}"'

# --- INJECT SYMLINK LOGIC ---
RUN echo '\n# --- VS Code SSH Extension Auto-Fix ---\n\
if [[ -n "\$SSH_CONNECTION" ]]; then\n\
    mkdir -p \$HOME/.vscode-server/extensions\n\
    for ext in google.geminicodeassist google.gemini-cli-vscode-ide-companion; do\n\
        if [ -d "/opt/code-oss/extensions/\$ext" ] && [ ! -d "\$HOME/.vscode-server/extensions/\$ext" ]; then\n\
            echo "🔧 Linking global extension: \$ext..."\n\
            ln -sf "/opt/code-oss/extensions/\$ext" "\$HOME/.vscode-server/extensions/\$ext"\n\
        fi\n\
    done\n\
fi' >> /etc/skel/.zshrc

EOF

    # 3. Infrastructure Prep
    run_step "Setting Logging Permissions" gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$COMPUTE_SA" --role="roles/logging.logWriter"

    if ! gcloud artifacts repositories describe $REPO_NAME --project=$PROJECT_ID --location=$REGION >/dev/null 2>&1; then
        run_step "Creating Artifact Registry" gcloud artifacts repositories create $REPO_NAME --project=$PROJECT_ID --repository-format=docker --location=$REGION --description="Custom workstation images"
    fi
    
    run_step "Granting Registry Writer Access" gcloud artifacts repositories add-iam-policy-binding $REPO_NAME --project=$PROJECT_ID --location=$REGION --member="serviceAccount:$COMPUTE_SA" --role="roles/artifactregistry.writer"

    STAGING_BUCKET="${PROJECT_ID}-build-staging"
    if ! gcloud storage buckets describe "gs://$STAGING_BUCKET" --project=$PROJECT_ID >/dev/null 2>&1; then
        run_step "Creating Staging Bucket" gcloud storage buckets create "gs://$STAGING_BUCKET" --project=$PROJECT_ID --location=$REGION --uniform-bucket-level-access
        run_step "Granting Bucket Access" gcloud storage buckets add-iam-policy-binding "gs://$STAGING_BUCKET" --member="serviceAccount:$COMPUTE_SA" --role="roles/storage.objectViewer"
    fi

    # 4. Submit Build
    run_step "Building Docker Image (This takes time)" gcloud builds submit "$BUILD_DIR" --project=$PROJECT_ID --region=$REGION --tag "$FULL_IMAGE_TAG" --gcs-source-staging-dir="gs://$STAGING_BUCKET/source"

    rm -rf "$BUILD_DIR"
}

# ---------------------------------------------------------
# LOGIC: Check if we need to build
# ---------------------------------------------------------
IMAGE_EXISTS=$(gcloud artifacts docker images list \
    "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME" \
    --include-tags --filter="tags:latest" \
    --format="value(package)" 2>/dev/null || true)

if [ "$REBUILD_IMAGE" = true ]; then
    echo -e "${YELLOW}⚠️  Force rebuild requested...${NC}"
    build_image
elif [ -z "$IMAGE_EXISTS" ]; then
    echo -e "${YELLOW}⚠️  Custom image not found. Building for the first time...${NC}"
    build_image
else
    echo -e "✅ Custom image exists. Skipping build."
fi

# ---------------------------------------------------------
# INFRASTRUCTURE PROVISIONING
# ---------------------------------------------------------

echo -e "\n${BLUE}--- 🏗️  Infrastructure Setup ---${NC}"

# 2. Cluster Setup
if ! gcloud workstations clusters describe $CLUSTER_ID --region=$REGION >/dev/null 2>&1; then
    run_step "Creating Cluster '$CLUSTER_ID' (approx 15-20m)" gcloud workstations clusters create $CLUSTER_ID --region=$REGION --network=$NETWORK_FULL --subnetwork=$SUBNET_FULL --async

    # Custom loop for waiting with spinner
    echo -n -e "Waiting for Cluster IP..."
    local spinstr='|/-\'
    
    while true; do
        IP=$(gcloud workstations clusters describe $CLUSTER_ID --region=$REGION --format="value(controlPlaneIp)" 2>/dev/null || true)
        if [ -n "$IP" ]; then
            break
        fi
        
        # Spinner animation
        local temp=${spinstr#?}
        printf "\r${BLUE}[%c]${NC} Waiting for Cluster IP..." "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep 1
    done
    echo -e "\r✅ Cluster Ready! IP: $IP        "
else
    echo -e "✅ Cluster '$CLUSTER_ID' exists."
fi

# GRANT READER PERMISSION
run_step "Granting Workstation Read Access" gcloud artifacts repositories add-iam-policy-binding $REPO_NAME --project=$PROJECT_ID --location=$REGION --member="serviceAccount:$COMPUTE_SA" --role="roles/artifactregistry.reader"

# 3. Configuration (Create or Update)
COMMON_FLAGS=(
    --region=$REGION
    --cluster=$CLUSTER_ID
    --machine-type=$MACHINE_TYPE
    --idle-timeout=$IDLE_TIMEOUT
    --running-timeout=$RUNNING_TIMEOUT
    --pd-disk-size=200
    --pd-disk-type=pd-ssd
    --pool-size=$POOL_SIZE
    --container-custom-image="$FULL_IMAGE_TAG"
    --service-account="$COMPUTE_SA"
)

if gcloud workstations configs describe $CONFIG_ID --region=$REGION --cluster=$CLUSTER_ID >/dev/null 2>&1; then
    run_step "Updating Config '$CONFIG_ID'" gcloud beta workstations configs update $CONFIG_ID "${COMMON_FLAGS[@]}"
else
    # Try creating with retention policy first
    if ! run_step "Creating Config '$CONFIG_ID'" gcloud beta workstations configs create $CONFIG_ID "${COMMON_FLAGS[@]}" --pd-reclaim-policy="retain"; then
         echo -e "${YELLOW}   ⚠️ Retrying without retention policy...${NC}"
         run_step "Creating Config (Retry)" gcloud beta workstations configs create $CONFIG_ID "${COMMON_FLAGS[@]}"
    fi
fi

# 4. Workstation (Create Only)
if gcloud workstations describe $WORKSTATION_ID --region=$REGION --cluster=$CLUSTER_ID --config=$CONFIG_ID >/dev/null 2>&1; then
    echo -e "✅ Workstation '$WORKSTATION_ID' exists."
    if [ "$REBUILD_IMAGE" = true ]; then
         echo -e "${YELLOW}🔔 NOTE: Image rebuilt. STOP and START the workstation to apply changes.${NC}"
    fi
else
    run_step "Creating Workstation '$WORKSTATION_ID'" gcloud workstations create $WORKSTATION_ID --region=$REGION --cluster=$CLUSTER_ID --config=$CONFIG_ID
fi

# 5. Grant Access (IAM)
CURRENT_USER=$(gcloud config get-value account 2>/dev/null)
echo -e "\n${BLUE}--- 🔑 IAM Access Setup ---${NC}"

# FIX: Check access first using 'get-iam-policy'. Only grant if missing.
# We silence errors for the check in case user permissions are strict.
POLICY_FILE="iam_policy.json"
HAS_ACCESS=false

if gcloud workstations get-iam-policy $WORKSTATION_ID --region=$REGION --cluster=$CLUSTER_ID --config=$CONFIG_ID --format=json > $POLICY_FILE 2>/dev/null; then
    if grep -q "$CURRENT_USER" $POLICY_FILE; then
        HAS_ACCESS=true
    fi
fi
rm -f $POLICY_FILE

if [ "$HAS_ACCESS" = true ]; then
    echo -e "✅ User $CURRENT_USER already has access."
else
    # Fallback: Grant access on the CONFIG level (supported by CLI) if check failed
    echo -e "${YELLOW}⚠️  Explicit access missing. Granting 'Workstation User' on Config...${NC}"
    run_step "Granting IAM to $CURRENT_USER" gcloud workstations configs add-iam-policy-binding $CONFIG_ID \
        --region=$REGION --cluster=$CLUSTER_ID \
        --member="user:$CURRENT_USER" \
        --role="roles/workstations.user"
fi

# --- SUMMARY ---
echo ""
echo "-------------------------------------------------------"
echo -e "🎉 ${GREEN}${BOLD}Provisioning Complete!${NC}"
echo "-------------------------------------------------------"
echo -e "🌍 Region:       ${BOLD}$REGION${NC}"
echo -e "🖥️  Workstation:  ${BOLD}$WORKSTATION_ID${NC}"
echo -e "⚙️  Config:       $CONFIG_ID"
echo "-------------------------------------------------------"
echo -e "👉 To connect, run:"
echo -e "   ${BOLD}./connect-workstation.sh${NC}"
echo "-------------------------------------------------------"
