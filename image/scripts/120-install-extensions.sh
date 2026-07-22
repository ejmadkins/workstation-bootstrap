#!/bin/sh
# Install extensions during startup

runuser user -- /opt/code-oss/bin/codeoss-cloudworkstations \
    --install-extension hashicorp.terraform \
    --install-extension vscode-icons-team.vscode-icons \
    --install-extension redhat.vscode-yaml \
    --install-extension esbenp.prettier-vscode \
    --install-extension ms-python.python \
    --install-extension Google.gemini-cli-vscode-ide-companion \
    --install-extension golang.Go \
    --install-extension charliermarsh.ruff \
    --install-extension dracula-theme.theme-dracula \
    --install-extension humao.rest-client \
    --install-extension PKief.material-icon-theme &
