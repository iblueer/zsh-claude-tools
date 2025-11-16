# Compatibility wrapper for claude-use -> claude-switch
# This file provides backward compatibility for existing users

# Load the main claude-switch function
if [[ -f "$HOME/.claude-tools/bin/claude-switch.zsh" ]]; then
  source "$HOME/.claude-tools/bin/claude-switch.zsh"
fi

# Define claude-use as an alias for claude-switch
claude-use() {
  claude-switch "$@"
}

# Set up completion for claude-use as well
if (( $+functions[compdef] )); then
  compdef _cu_zsh_complete claude-use
fi
