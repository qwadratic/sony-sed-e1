# AI Operator UAT Guide — Driving Tests via tmux

> How an AI agent runs interactive UAT sessions, sends commands, reads output,
> and verifies results — all through tmux pane manipulation.

---

## Core Pattern

```
1. Create tmux session with named panes
2. Send commands via `tmux send-keys`
3. Read output via `tmux capture-pane`
4. Verify output matches expectations
5. Repeat for each test scenario
```

---

## tmux Commands Reference

### Session & Window Management
```bash
# Create session
tmux new-session -d -s uat -x 220 -y 55

# Create named windows
tmux new-window -t uat -n main      # main app
tmux new-window -t uat -n logs      # log tailing
tmux new-window -t uat -n verify    # verification commands

# Split panes within a window
tmux split-window -t uat:main -h -p 40    # vertical split, right 40%
tmux split-window -t uat:main.1 -v -p 50  # horizontal split bottom-right
```

### Sending Commands to Panes
```bash
# Send text + Enter to a specific pane
tmux send-keys -t uat:main.0 "echo hello" Enter

# Send text WITHOUT Enter (for prompts that need typing first)
tmux send-keys -t uat:main.0 "2"
tmux send-keys -t uat:main.0 Enter

# Send special keys
tmux send-keys -t uat:main.0 C-c       # Ctrl+C
tmux send-keys -t uat:main.0 q Enter   # type q then Enter

# Send to a named window's first pane
tmux send-keys -t uat:logs "tail -F /tmp/seg-events.jsonl" Enter
```

### Reading Output from Panes (THE KEY TECHNIQUE)
```bash
# Capture visible pane content (what's on screen right now)
tmux capture-pane -t uat:main.0 -p

# Capture with scrollback history (last 100 lines)
tmux capture-pane -t uat:main.0 -p -S -100

# Capture to a file for analysis
tmux capture-pane -t uat:main.0 -p -S -200 > /tmp/pane_output.txt

# Capture specific pane by index
tmux capture-pane -t uat:main.1 -p -S -50   # right pane

# Grep the captured output
tmux capture-pane -t uat:main.0 -p -S -100 | grep "PHASE"
tmux capture-pane -t uat:main.0 -p -S -100 | grep "← RX"
tmux capture-pane -t uat:main.0 -p -S -100 | grep "SENSOR"
```

### Pipe Pane to File (continuous logging)
```bash
# Log everything that appears in a pane to a file
tmux pipe-pane -t uat:main.0 -o "cat >> /tmp/uat_main.log"

# Stop logging
tmux pipe-pane -t uat:main.0
```

---

## UAT Session Setup Pattern

```bash
#!/bin/bash
SESSION=uat
REPO=/Users/gerhardgustav/Desktop/hobby-dev/sony-sed-e1

tmux kill-session -t $SESSION 2>/dev/null
tmux new-session -d -s $SESSION -x 220 -y 55

# Pane 0 (left): App under test
# Pane 1 (right-top): Event log stream
# Pane 2 (right-bottom): Verification / file watchers

tmux split-window -t $SESSION -h -p 40
tmux split-window -t $SESSION:0.1 -v -p 40

# Enable logging on all panes
tmux pipe-pane -t $SESSION:0.0 -o "cat >> /tmp/uat_app.log"
tmux pipe-pane -t $SESSION:0.1 -o "cat >> /tmp/uat_events.log"
tmux pipe-pane -t $SESSION:0.2 -o "cat >> /tmp/uat_verify.log"
```

---

## Test Execution Pattern

### Step 1: Launch App
```bash
tmux send-keys -t uat:0.0 "cd $REPO/seg-swift/SEGExplorer && swift run SEGExplorer --bt --debug" Enter
sleep 3
```

### Step 2: Read Device List & Select
```bash
# Read what the app printed
tmux capture-pane -t uat:0.0 -p -S -30

# Look for the device list, find the right index
# Then send selection
tmux send-keys -t uat:0.0 "0" Enter
```

### Step 3: Wait for Handshake & Verify
```bash
sleep 15  # handshake timeout is 5s+3s

# Check if handshake completed
OUTPUT=$(tmux capture-pane -t uat:0.0 -p -S -50)
echo "$OUTPUT" | grep "PHASE: ready"
if [ $? -eq 0 ]; then
    echo "✅ Handshake complete"
else
    echo "❌ Handshake failed"
    echo "$OUTPUT" | grep -E "PHASE|← RX|→ TX|error|Error"
fi
```

### Step 4: Run Demo & Verify
```bash
# Select TextDemo
tmux send-keys -t uat:0.0 "0" Enter
sleep 3

# Check for frame acknowledgments
tmux capture-pane -t uat:0.0 -p -S -20 | grep "DISPLAY\|→ TX LayoutPlaceRemove"
```

### Step 5: Capture Evidence
```bash
# Save full session output
tmux capture-pane -t uat:0.0 -p -S -500 > /tmp/uat_evidence.txt

# Read the JSONL event log
cat /tmp/seg-events.jsonl | python3 -c "
import sys, json
for line in sys.stdin:
    d = json.loads(line)
    print(f\"{d['type']:8s} {json.dumps({k:v for k,v in d.items() if k not in ('type','ts')})}\")
"
```

---

## Verification Patterns

### Check Handshake Progression
```bash
tmux capture-pane -t uat:0.0 -p -S -100 | grep -E "PHASE|← RX Protocol|→ TX Settings"
# Expected:
#   ← RX ProtocolVersion ...
#   → TX SettingsStatusReq ...
#   PHASE: handshaking(step: 1)
#   ← RX SettingsStatusRes ...
#   → TX VersionReq ...
#   PHASE: handshaking(step: 2)
#   ...
#   PHASE: ready
```

### Check Sensor Data Validity
```bash
tmux capture-pane -t uat:0.0 -p -S -100 | grep "SENSOR"
# Expected when stationary:
#   [SENSOR #10] accel=(~0, ~9.81, ~0) gyro=(~0, ~0, ~0)
# Gravity should be ~9.81 on one axis
```

### Check Camera Capture
```bash
tmux capture-pane -t uat:0.0 -p -S -50 | grep "CAMERA\|JPEG"
# Expected:
#   CAMERA: captured NNNN bytes → /tmp/seg-capture-XXX.jpg
#   JPEG valid: true, first bytes: ff d8 ff e0 ...
ls -la /tmp/seg-capture-*.jpg
```

### Check Touch Input
```bash
tmux capture-pane -t uat:0.0 -p -S -50 | grep "INPUT"
# Expected after physical tap:
#   INPUT: tap
```

---

## Multi-Pane Monitoring Setup

```bash
# Pane 1: filtered event stream
tmux send-keys -t uat:0.1 "tail -F /tmp/seg-events.jsonl | python3 -u -c \"
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line)
        t = d.get('type','')
        if t == 'SENSOR':
            print(f'📡 accel=({d.get(\\\"accel_x\\\",0):.2f},{d.get(\\\"accel_y\\\",0):.2f},{d.get(\\\"accel_z\\\",0):.2f})')
        elif t == 'INPUT':
            print(f'👆 {d.get(\\\"event\\\",\\\"\\\")}')
        elif t == 'CAMERA':
            print(f'📷 {d.get(\\\"event\\\",\\\"\\\")} {d.get(\\\"bytes\\\",0)}B')
        elif t == 'PHASE':
            print(f'🔄 {d.get(\\\"phase\\\",\\\"\\\")}')
        sys.stdout.flush()
    except: pass
\"" Enter

# Pane 2: file watchers
tmux send-keys -t uat:0.2 "watch -n2 'ls -lht /tmp/seg-capture-*.jpg 2>/dev/null | head -5; echo ---; wc -l /tmp/seg-events.jsonl 2>/dev/null'" Enter
```

---

## Troubleshooting via tmux

### App seems stuck
```bash
# Check if process is running
tmux capture-pane -t uat:0.0 -p | tail -5

# Send Ctrl+C and restart
tmux send-keys -t uat:0.0 C-c
sleep 1
tmux send-keys -t uat:0.0 "swift run SEGExplorer --bt --debug" Enter
```

### No BT data flowing
```bash
# Check for RX frames
tmux capture-pane -t uat:0.0 -p -S -100 | grep "← RX"

# If empty — glasses may not be paired or powered on
# Check BT state:
tmux send-keys -t uat:0.2 "system_profiler SPBluetoothDataType 2>/dev/null | grep -A5 SmartEyeglass" Enter
sleep 2
tmux capture-pane -t uat:0.2 -p -S -10
```

### Glasses in pairing mode
```bash
# The glasses show "Pairing..." on their display.
# macOS must initiate pairing via System Settings → Bluetooth
# OR we can try programmatic pairing:
# IOBluetoothDevice.openConnection() triggers pairing if not paired.
# But usually: System Settings → Bluetooth → click "Connect" next to SmartEyeglass
```

---

## Full Automated UAT Script

```bash
#!/bin/bash
# Automated UAT — AI operator drives entire test sequence

SESSION=uat
REPO=/path/to/sony-sed-e1
BINARY=$REPO/seg-swift/SEGExplorer/.build/arm64-apple-macosx/debug/SEGExplorer

# Setup
tmux kill-session -t $SESSION 2>/dev/null
tmux new-session -d -s $SESSION -x 220 -y 55
tmux pipe-pane -t $SESSION -o "cat >> /tmp/uat_full.log"

# Launch
tmux send-keys -t $SESSION "$BINARY --bt --debug" Enter
sleep 3

# Read device list
DEVICES=$(tmux capture-pane -t $SESSION -p -S -20)
echo "$DEVICES"

# Find first online glasses and select it
GLASSES_IDX=$(echo "$DEVICES" | grep '🕶️.*rssi:' | head -1 | grep -o '^\s*\[[0-9]*\]' | tr -d '[] ')
if [ -n "$GLASSES_IDX" ]; then
    echo "Selecting glasses index: $GLASSES_IDX"
    tmux send-keys -t $SESSION "$GLASSES_IDX" Enter
else
    echo "No online glasses found"
    exit 1
fi

# Wait for handshake
sleep 15
HANDSHAKE=$(tmux capture-pane -t $SESSION -p -S -50)
if echo "$HANDSHAKE" | grep -q "PHASE: ready"; then
    echo "✅ Handshake complete"
else
    echo "❌ Handshake failed. Output:"
    echo "$HANDSHAKE" | grep -E "PHASE|RX|TX|error"
    exit 1
fi

# Test TextDemo
tmux send-keys -t $SESSION "0" Enter
sleep 3
echo "TextDemo selected. Check glasses display."

# Cleanup
tmux send-keys -t $SESSION "q" Enter
```
