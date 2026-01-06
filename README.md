# Cloud Workstation Provisioner

A fully automated, Bash-based toolkit to provision, configure, and connect to a custom **Google Cloud Workstation**.

This project builds a custom Docker image (based on `code-oss`) with a pre-configured "battery-included" development environment, infrastructure-as-code provisioning, and a seamless local connection script.

---

## 🚀 Features

* **Automated Infrastructure:** One script (`provision-workstation.sh`) handles enabling APIs, creating Artifact Registries, Clusters, Workstation Configs, and the Workstation itself.
* **Custom Development Environment:**
    * **Shell:** Zsh + Oh My Zsh + Powerlevel10k (configured).
    * **Tools:** `glab` (GitLab CLI), `fzf` (Fuzzy Finder), `bat` (improved cat), `jq`, `wget`.
    * **AI:** Google Gemini Code Assist & Gemini CLI installed and enabled.
* **Dynamic Configuration:** Git identity (`user.name`, `user.email`) and project settings are injected via `workstation.conf`—no hardcoding in dotfiles.
* **Persistent Extensions Fix:** Solves the common "Split Brain" issue where extensions installed during Docker builds disappear when Persistent Disks are mounted.
* **Visual CLI:** Scripts feature spinners, color-coded status updates, and robust error handling.

---

## 🛠️ Prerequisites

1.  **Google Cloud SDK (`gcloud`)**: Installed and authenticated locally.
2.  **Visual Studio Code**: Installed locally.
3.  **Local SSH Config**: You must have an entry in your local `~/.ssh/config` that matches the alias in the connection script (default: `my-cloud-workstation`).

    **Add this to your local `~/.ssh/config`:**
    ```text
    Host my-cloud-workstation
        HostName 127.0.0.1
        Port 1025
        User user
        IdentityFile ~/.ssh/google_compute_engine
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
    ```

4.  **GitLab Personal Access Token**: Needed for `glab` CLI and custom GitLab helper functions (e.g., `ginit`, `gmr`). Create one [here](https://gitlab.com/-/user_settings/personal_access_tokens) and ensure you add the `write_repository` and `api` scopes.

---

## ⚙️ Setup

1.  **Clone the repository:**
    ```bash
    git clone <your-repo-url>
    cd <your-repo-folder>
    ```

2.  **Create your configuration:**
    Copy the example file to create your local config (which is ignored by Git).
    ```bash
    cp workstation.conf.example workstation.conf
    ```

3.  **Edit `workstation.conf`:**
    Open the file and update the variables:
    * `PROJECT_ID` & `REGION`
    * `GIT_NAME` & `GIT_EMAIL` (These are injected into your remote `.gitconfig`)
    * `GITLAB_GROUP` (Used by the custom `ginit` helper)

---

## 🖥️ Usage

### 1. Provisioning (Build & Deploy)
This script builds the Docker image, pushes it to the Artifact Registry, and creates/updates the Cloud Workstation infrastructure.

```bash
./provision-workstation.sh

```

**Options:**

* `-r` or `--rebuild`: Forces a rebuild of the Docker image (useful if you changed files in `resources/`).
* `-c <file>`: Use a specific config file.

> **Note:** The first run can take 15-20 minutes to provision the Workstation Cluster. Subsequent runs are much faster.

### 2. Connecting

This script starts the workstation (if stopped), opens an SSH tunnel, and launches your local VS Code connected to the remote session.

```bash
./connect-workstation.sh

```

---

## 📂 Project Structure

```text
.
├── provision-workstation.sh   # Main infrastructure & build script
├── connect-workstation.sh     # Connection & tunnel helper
├── workstation.conf           # Local config (ignored by git)
├── workstation.conf.example   # Template config
├── resources/                 # Assets injected into the Docker image
│   ├── code/                  # VS Code settings, tasks, and extension list
│   ├── gemini/                # Gemini CLI settings
│   └── zsh/                   # .zshrc and p10k configurations

```

---

## 🔧 Under the Hood

### The "Persistent Disk" Fix

Cloud Workstations mount a persistent disk at `/home/user`. This normally hides any VS Code extensions installed in the home directory during the Docker build.

**Our Solution:**

1. **Build Time:** Extensions are installed globally to `/opt/code-oss/extensions`.
2. **Runtime:** A script injected into `.zshrc` runs on login, checks if the extensions exist in your session, and **symlinks** them from `/opt` to your home directory.
3. **Result:** Extensions persist across rebuilds and are available immediately upon connection.

### Dynamic Zsh

The `.zshrc` file in `resources/zsh` is not hardcoded. It uses environment variables (`GIT_EMAIL`, `GITLAB_GROUP`) passed from `workstation.conf` during the Docker build. This allows you to share the Dockerfile/scripts without leaking personal info.

### Custom Helper Functions



The image includes several custom Zsh functions and aliases (defined in `.zshrc`):
* `ginit <name>`: Initializes a repo, creates a GitLab project, and pushes the first commit.
* `gcommit` (alias `gca`): Asks Gemini to write a Git commit message for staged changes, then allows the user to confirm and commit.
* `gmr`: Automatically creates a GitLab Merge Request for the current branch with an AI-generated title and description based on the changes.
* `gclean`: Switches to the `main` branch, pulls the latest changes, and deletes locally merged branches.
* `gsave`: Stages all changes, uses Gemini to create a commit message (via `gcommit`), and pushes the changes.
* `ask`: Uses Gemini CLI to explain the last command or specific history items (alias for `explain-history`).
* `browse`: A fuzzy-finder file browser with AI summaries in the preview window (alias for `gemini-browse`).
* `review <filename>` (alias `check`): Sends the content of a specified file to Gemini for a code review, highlighting potential bugs, security issues, or performance improvements.