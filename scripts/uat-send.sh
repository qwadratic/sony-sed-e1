#!/usr/bin/env bash
# Send commands to SEGExplorer running in the seg-uat tmux session.
# Designed for AI-driven UAT via tmux send-keys + capture-pane.
#
# Usage:
#   ./scripts/uat-send.sh <command>        # Send a REPL command
#   ./scripts/uat-send.sh --capture [N]    # Capture last N lines (default 30)
#   ./scripts/uat-send.sh --status         # Show session info
#   ./scripts/uat-send.sh --demo N         # Switch to demo N (0-8)
#   ./scripts/uat-send.sh --tap            # Simulate tap
#   ./scripts/uat-send.sh --menu           # Back to menu
#   ./scripts/uat-send.sh --debug          # Toggle debug level
#   ./scripts/uat-send.sh --raw "c3 00 01" # Send raw hex
#   ./scripts/uat-send.sh --quit           # Quit explorer
#   ./scripts/uat-send.sh --logs [N]       # Last N lines from log file
#
# Examples (AI-driven UAT):
#   ./scripts/uat-send.sh --demo 0    # Start TextDemo
#   sleep 2
#   ./scripts/uat-send.sh --capture   # See what rendered
#   ./scripts/uat-send.sh --tap       # Tap to interact
#   ./scripts/uat-send.sh --capture   # Verify response

set -euo pipefail

SESSION="seg-uat"
PANE="$SESSION:0.0"
LOG_DIR="$HOME/.seg-logs"

# Check session exists
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "ERROR: No tmux session '$SESSION'. Run ./scripts/uat-tmux.sh first."
    exit 1
fi

case "${1:---help}" in
    --capture)
        LINES="${2:-30}"
        tmux capture-pane -t "$PANE" -p -S "-$LINES"
        ;;
    --status)
        echo "Session: $SESSION"
        tmux list-panes -t "$SESSION" -F '  pane #{pane_index}: #{pane_current_command} (#{pane_width}x#{pane_height})'
        echo ""
        echo "Last 5 lines from explorer:"
        tmux capture-pane -t "$PANE" -p -S -5
        ;;
    --demo)
        [ -z "${2:-}" ] && echo "Usage: --demo N (0-8)" && exit 1
        tmux send-keys -t "$PANE" "$2" Enter
        echo "Sent: demo $2"
        ;;
    --tap)
        tmux send-keys -t "$PANE" "t" Enter
        echo "Sent: tap"
        ;;
    --menu)
        tmux send-keys -t "$PANE" "m" Enter
        echo "Sent: menu"
        ;;
    --debug)
        tmux send-keys -t "$PANE" "d" Enter
        echo "Sent: toggle debug"
        ;;
    --raw)
        [ -z "${2:-}" ] && echo "Usage: --raw 'c3 00 01 01'" && exit 1
        tmux send-keys -t "$PANE" "raw $2" Enter
        echo "Sent: raw $2"
        ;;
    --quit)
        tmux send-keys -t "$PANE" "q" Enter
        echo "Sent: quit"
        ;;
    --logs)
        LINES="${2:-20}"
        LATEST=$(ls -t "$LOG_DIR"/*.jsonl 2>/dev/null | head -1)
        if [ -n "$LATEST" ]; then
            tail -n "$LINES" "$LATEST"
        else
            echo "No log files in $LOG_DIR"
        fi
        ;;
    --help|-h)
        head -25 "$0" | grep '^#' | sed 's/^# *//'
        ;;
    *)
        # Send arbitrary command
        tmux send-keys -t "$PANE" "$1" Enter
        echo "Sent: $1"
        ;;
esac
