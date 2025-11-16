# Compatibility wrapper for claude-use -> claude-switch
# This file provides backward compatibility for existing users

# Load the main claude-switch function
if [ -f "$HOME/.claude-tools/bin/claude-switch.bash" ]; then
  source "$HOME/.claude-tools/bin/claude-switch.bash"
fi

# Define claude-use as an alias for claude-switch
claude-use() {
  claude-switch "$@"
}
