#!/bin/bash
SESSION=glasses-uat
REPO=/Users/gerhardgustav/Desktop/hobby-dev/sony-sed-e1
TOOL=$REPO/macos-middleware/glasses-tool

tmux kill-session -t $SESSION 2>/dev/null || true
tmux new-session -d -s $SESSION -x 240 -y 55

# Pane 0: glasses-tool REPL (main)
tmux send-keys -t $SESSION "cd $REPO && $TOOL" Enter

# Pane 1 (right): live JSON event stream — camera events highlighted
tmux split-window -t $SESSION -h -p 40
tmux send-keys -t $SESSION:0.1 \
  "tail -F /tmp/glasses-events.jsonl | grep --line-buffered -v '\"type\":\"LOG\"' | python3 -u -c \"
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line)
        t = d.get('type','')
        marker = '📷 ' if t == 'CAMERA' else ('📡 ' if t in ('WIFI','STATE') else '   ')
        print(marker + json.dumps(d, separators=(',',':')))
        sys.stdout.flush()
    except: pass
\"" Enter

# Pane 2 (right bottom): JPEG watcher
tmux split-window -t $SESSION:0.1 -v -p 40
tmux send-keys -t $SESSION:0.2 \
  "echo 'Watching /tmp/glasses-capture-*.jpg ...'; while true; do ls -lht /tmp/glasses-capture-*.jpg 2>/dev/null | head -5; sleep 2; done" Enter

tmux select-pane -t $SESSION:0.0
tmux attach -t $SESSION
