# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  git 
  z 
  sudo 
  #fzf 
  zsh-autosuggestions 
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Ask Gemini about the last command's output
explain() {
  fc -ln -1 | gemini "Explain this command and its likely output"
}

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Search your history with fzf and send the selected command to Gemini for an explanation
explain-history() {
  local cmd=$(history | fzf | sed 's/^[ ]*[0-9]*[ ]*//')
  [ -n "$cmd" ] && echo "Explaining: $cmd" && gemini "Explain exactly what this command does: $cmd"
}
alias ask='explain-history'

# Custom fzf appearance: 40% height, pop-up style with a border
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline'

# Specifically for history search (Ctrl+R), make it a centered pop-up
export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window down:3:hidden:wrap --bind '?:toggle-preview'"

# Preview files using 'bat' when using Ctrl+T
export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always --line-range :500 {}'"

# Browse files and have Gemini explain the highlighted one in the preview pane
gemini-browse() {
  fzf --preview "echo '--- AI EXPLANATION ---'; gemini 'Explain what this file does in 2 short sentences:' {} 2>/dev/null | head -n 5; echo '--- CODE CONTENT ---'; batcat --style=numbers --color=always {}" \
      --preview-window=right:60%:wrap \
      --bind "enter:execute(code {})" \
      --header "Select a file to explain. Press ENTER to open in VS Code."
}
alias browse='gemini-browse'
export PATH="$HOME/.local/bin:$PATH"

# Ask Gemini to write a git commit message for staged changes
gcommit() {
  local changes=$(git diff --cached)
  if [ -z "$changes" ]; then
    echo "No changes staged. Run 'git add' first."
    return
  fi
  
  echo "Asking Gemini for a commit message..."
  local msg=$(echo "$changes" | gemini "Write a professional, one-line git commit message for these changes. Do not include quotes or any preamble.")
  
  echo "Suggested message: $msg"
  echo -n "Commit with this message? (y/n): "
  read -r response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    git commit -m "$msg"
  else
    echo "Commit cancelled."
  fi
}
alias gca='gcommit'

# Have Gemini review a specific file for improvements or bugs
review() {
  if [ -z "$1" ]; then
    echo "Usage: review <filename>"
    return
  fi

  echo "--- AI Code Review for: $1 ---"
  # Use bat to show the file name then pipe content to Gemini
  cat "$1" | gemini "Review this code for potential bugs, security issues, or performance improvements. Be concise and use bullet points."
}
alias check='review'

# Create a new GitLab repo from the current directory
# Usage: ginit my-new-project
ginit() {
  local REPO_NAME=$1
  
  # DYNAMIC VARIABLES (Loaded from Docker ENV)
  local FULL_PATH="${GITLAB_GROUP}"
  local USER_EMAIL="${GIT_EMAIL}"
  local USER_NAME="${GIT_NAME}"
  
  if [ -z "$REPO_NAME" ]; then
    echo "❌ Usage: ginit <project-name>"
    return 1
  fi

  if [ -z "$FULL_PATH" ]; then
     echo "❌ Error: GITLAB_GROUP not set in environment."
     return 1
  fi

  # 1. Initialize Git (Safety check)
  if [ -d ".git" ]; then
    echo "⚠️  Git is already initialized here."
  else
    git init -b main
  fi

  # 2. Generate Content
  echo "🤖 Asking Gemini for description..."
  local DESC=$(echo "One-line description for '$REPO_NAME'." | gemini 2>/dev/null | grep -v "\[STARTUP\]")
  [ -z "$DESC" ] && DESC="Project $REPO_NAME"

  echo "# $REPO_NAME\n\n$DESC" > README.md
  echo "Generating .gitignore..."
  echo "Generate a .gitignore for a generic coding project. Output ONLY content." | gemini 2>/dev/null | grep -v "\[STARTUP\]" > .gitignore

  # 3. Configure Remote & Identity
  local REPO_URL="https://gitlab.com/$FULL_PATH/$REPO_NAME.git"
  git remote remove origin 2>/dev/null
  git remote add origin "$REPO_URL"
  
  git config user.email "$USER_EMAIL"
  git config user.name "$USER_NAME"

  # 4. Commit and Push
  echo "📦 Pushing to create project..."
  git add .
  git commit -m "Initial commit"
  
  git push --set-upstream origin main

  echo "-------------------------------------------------------"
  echo "✅ Sent! If the permissions are correct, your repo is now here:"
  echo "$REPO_URL"
  echo "-------------------------------------------------------"
}

# 1. SHIP: Auto-create a GitLab Merge Request with AI description
gmr() {
  local BRANCH=$(git branch --show-current)
  
  # Ensure remote is up to date
  echo "⬆️  Pushing changes to GitLab..."
  git push origin "$BRANCH"

  echo "🤖 Analyzing changes for Merge Request..."
  # Get the difference between main and this branch
  local DIFF=$(git diff main...$BRANCH)
  
  if [ -z "$DIFF" ]; then
    echo "⚠️  No differences found between $BRANCH and main."
    return
  fi

  # Ask Gemini to write the MR description and title
  local DESC=$(echo "$DIFF" | gemini "Write a markdown description for a GitLab Merge Request based on these code changes. Include a 'Summary' and 'Key Changes' section. Be concise.")
  local TITLE=$(echo "$DIFF" | gemini "Write a strict, under 50 char title for this merge request. No quotes.")

  echo "🚀 Opening Merge Request: $TITLE..."
  glab mr create \
    --title "$TITLE" \
    --description "$DESC" \
    --source-branch "$BRANCH" \
    --target-branch "main" \
    --remove-source-branch \
    --web
}

# 2. CLEAN: Switch to main, pull, and delete merged branches
unalias gclean 2>/dev/null
gclean() {
  local CURRENT=$(git branch --show-current)
  
  if [ "$CURRENT" != "main" ]; then
    echo "🔄 Switching to main..."
    git checkout main
  fi

  echo "⬇️  Pulling latest..."
  git pull origin main --prune

  echo "🧹 Cleaning up merged branches..."
  # List merged branches, exclude main, and delete them
  git branch --merged | grep -v "\*" | grep -v "main" | xargs -r git branch -d
  
  echo "✨ Workspace clean."
}

# 3. SAVE: Add all, AI commit, and push
gsave() {
  git add .
  
  # Reuse your existing gcommit function
  gcommit 
  
  # If the commit succeeded (return code 0), push
  if [ $? -eq 0 ]; then
    echo "⬆️  Pushing..."
    git push
  fi
}
