#!/bin/bash
# uat-seg.sh — Interactive UAT session for SEGExplorer with real glasses
set -euo pipefail

SESSION=seg-uat
REPO="$(cd "$(dirname "$0")" && pwd)"
EXPLORER="$REPO/seg-swift/SEGExplorer"

# Build first
echo "Building SEGExplorer..."
cd "$EXPLORER" && swift build 2>&1 | tail -2

# Kill old session
tmux kill-session -t $SESSION 2>/dev/null || true
tmux new-session -d -s $SESSION -x 220 -y 55

# Pane 0: SEGExplorer --bt (main)
tmux send-keys -t $SESSION "cd $REPO && swift run --package-path seg-swift/SEGExplorer SEGExplorer --bt" Enter

# Pane 1 (right): Event log with pretty-printing
tmux split-window -t $SESSION -h -p 40
tmux send-keys -t $SESSION:0.1 \
  "tail -F /tmp/seg-events.jsonl 2>/dev/null | python3 -u -c \"
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line)
        t = d.get('type','')
        if t == 'SENSOR':
            print(f'📡 accel=({d.get(\\\"accel_x\\\",0):.2f},{d.get(\\\"accel_y\\\",0):.2f},{d.get(\\\"accel_z\\\",0):.2f}) gyro=({d.get(\\\"gyro_x\\\",0):.3f},{d.get(\\\"gyro_y\\\",0):.3f},{d.get(\\\"gyro_z\\\",0):.3f})')
        elif t == 'INPUT':
            print(f'👆 {d.get(\\\"event\\\",\\\"\\\")}')
        elif t == 'CAMERA':
            print(f'📷 {d.get(\\\"event\\\",\\\"\\\")} {d.get(\\\"bytes\\\",0)}B')
        elif t == 'PHASE':
            print(f'🔄 Phase: {d.get(\\\"phase\\\",\\\"\\\")}')
        else:
            print(json.dumps(d, separators=(',',':')))
        sys.stdout.flush()
    except: pass
\"" Enter

# Pane 2 (right-bottom): JPEG watcher
tmux split-window -t $SESSION:0.1 -v -p 30
tmux send-keys -t $SESSION:0.2 \
  "echo 'Watching /tmp/seg-capture-*.jpg ...'; while true; do ls -lht /tmp/seg-capture-*.jpg 2>/dev/null | head -5; sleep 3; done" Enter

tmux select-pane -t $SESSION:0.0
tmux attach -t $SESSION
