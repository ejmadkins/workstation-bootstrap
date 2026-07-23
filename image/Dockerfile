FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

RUN echo customising image... && \
    # install firebase-tools
    npm install -g firebase-tools && \
    # install agy cli
    curl -fsSL https://antigravity.google/cli/install.sh | bash && \
    # install hashicorp tools
    wget -O - https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && apt-get install packer terraform && \
    # install k9s
    wget https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb && \
    dpkg -i k9s_linux_amd64.deb && \
    # add github cli apt repo
	mkdir -p -m 755 /etc/apt/keyrings && \
	out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg && \
	cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
	chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
	mkdir -p -m 755 /etc/apt/sources.list.d && \
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    # install Azure cli
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash && \
    # install AWS cli
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    # Install the Pulumi SDK, including the cli and language runtimes.
    curl -fsSL https://get.pulumi.com/ | bash && \
    mv ~/.pulumi/bin/* /usr/bin && \
    # update and upgrade any system packages
    apt-get update && apt-get -y upgrade && \
    # install packages
    apt-get install -y \
        btop \
        curl \
        wget \
        gnupg2 \
        software-properties-common \
        unzip \
        gnupg \
        direnv \
        jq \
        yq \
        yamllint \
        keychain \
        tcpdump \
        stow \
        zstd \
        zsh \
        python-is-python3 \
        xz-utils \
        shellcheck \
        htop \
        moreutils \
        gettext-base \
        gh \
        tmux \
        && apt-get remove --purge --auto-remove -y \
        && rm -rf /var/lib/apt/lists/* \
        && \
    # install ollama (must come after ztsd installation)
    curl -fsSL https://ollama.com/install.sh | sh && \
    # install uv (--break-system-packages required as there is no debian package for uv yet)
    pip install --break-system-packages uv && \
    # install kustomize
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash && \
    mv kustomize /usr/local/bin/ && \
    # Install bun
    wget https://github.com/oven-sh/bun/releases/latest/download/bun-linux-x64.zip -O bun.zip && unzip bun.zip bun-linux-x64/bun && mv bun-linux-x64/bun /usr/local/bin/ && chmod +x /usr/local/bin/bun && rm bun.zip && rmdir bun-linux-x64

# Copy runtime config (extensions, shell scripts, etc)
COPY scripts/*.sh /etc/workstation-startup.d/

# --- FZF SETUP ---
RUN git clone --depth 1 https://github.com/junegunn/fzf.git /etc/skel/.fzf
RUN /etc/skel/.fzf/install --all --no-bash --no-fish --no-update-rc

# --- ZSH SETUP ---
ENV ZSH=/etc/skel/.oh-my-zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
RUN git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH}/custom/themes/powerlevel10k
RUN git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH}/custom/plugins/zsh-autosuggestions
RUN git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH}/custom/plugins/zsh-syntax-highlighting

COPY resources/zsh/.zshrc /etc/skel/.zshrc
COPY resources/zsh/.p10k.zs* /etc/skel/.p10k.zsh

# --- WORKSPACE SETUP ---
RUN mkdir -p /etc/skel/projects
RUN mkdir -p /etc/skel/.vscode
COPY resources/code/tasks.json /etc/skel/.vscode/tasks.json

# --- VS CODE SETTINGS ---
RUN mkdir -p /etc/skel/.codeoss-cloudworkstations/data/Machine
COPY resources/code/settings.json /etc/skel/.codeoss-cloudworkstations/data/Machine/settings.json

ENV SHELL=/usr/bin/zsh

