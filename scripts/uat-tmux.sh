#!/usr/bin/env bash
# UAT tmux session for SEGExplorer interactive testing.
# Usage: ./scripts/uat-tmux.sh [--bt|--local HOST:PORT] [--address XX:XX]
#
# Creates a 3-pane tmux layout:
#   [0] SEGExplorer running (interactive REPL)
#   [1] Live log tail (~/.seg-logs/ latest)
#   [2] Command pane (for AI or human to send keys)

set -euo pipefail

SESSION="seg-uat"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPLORER="$PROJECT_ROOT/SEGExplorer"
LOG_DIR="$HOME/.seg-logs"

# Default args
ARGS="${@:---bt --debug}"

# Kill existing session
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Build first
echo "Building SEGExplorer..."
cd "$EXPLORER" && swift build 2>&1 | tail -3
echo ""

# Create session with explorer pane
tmux new-session -d -s "$SESSION" -x 200 -y 50

# Pane 0: SEGExplorer
tmux send-keys -t "$SESSION:0.0" "cd '$EXPLORER' && swift run SEGExplorer $ARGS" Enter

# Split horizontal for log tail
tmux split-window -h -t "$SESSION:0"
tmux send-keys -t "$SESSION:0.1" "mkdir -p '$LOG_DIR' && sleep 2 && tail -f '$LOG_DIR'/\$(ls -t '$LOG_DIR' | head -1) 2>/dev/null || echo 'No logs yet — waiting...'" Enter

# Split pane 1 vertical for command pane
tmux split-window -v -t "$SESSION:0.1"
tmux send-keys -t "$SESSION:0.2" "echo '=== UAT Command Pane ==='; echo 'Send commands to explorer: tmux send-keys -t $SESSION:0.0 \"CMD\" Enter'; echo ''; echo 'Quick reference:'; echo '  0-8  = switch demo'; echo '  d    = toggle debug'; echo '  t    = simulate tap'; echo '  m    = back to menu'; echo '  ar   = AR mode'; echo '  normal = normal mode'; echo '  raw XX XX = send hex'; echo '  q    = quit'" Enter

# Layout: explorer gets 60% width, logs+cmd get 40%
tmux select-layout -t "$SESSION" main-vertical

# Focus on explorer pane
tmux select-pane -t "$SESSION:0.0"

echo "UAT session ready: tmux attach -t $SESSION"
echo ""
echo "Panes:"
echo "  [0] SEGExplorer (REPL)"
echo "  [1] Log tail"
echo "  [2] Command helper"
echo ""
tmux attach -t "$SESSION"
