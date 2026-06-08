# Session Analytics Runbook — Universal

> Generated: 2026-06-08  
> Project: sony-sed-e1 (serves as reference instantiation)  
> Purpose: Analyze Claude Code session transcripts for tool patterns, failures, repeated mistakes, operator behaviour, and CLAUDE.md improvement opportunities.  
> Reusability: Replace variables in §5 to run on any project.

---

## 1 — Schema Reference

All session transcripts are JSONL files. Each line is one record. The Pi agent stores them at:
```
~/.pi/agent/sessions/--<cwd-path-with-dashes>--/<session-id>.jsonl
```

Subagent children live under the parent session dir:
```
<parent-session-id>/<subagent-short-id>/run-<N>/session.jsonl
```

### 1.1 Record Types

| `type` | When it appears | Key fields |
|--------|----------------|------------|
| `session` | Line 1 of every file | `id`, `timestamp`, `cwd`, `version` |
| `model_change` | Model switch | `provider`, `modelId` |
| `thinking_level_change` | Thinking mode change | `thinkingLevel` (`high`/`low`/`none`) |
| `message` | Every turn | `id`, `parentId`, `timestamp`, `message` |
| `custom_message` | System events | `customType`, `content`, `display` |
| `branch_summary` | User returned from branch | `summary`, `fromId` |
| `label` | User labelled a message | `targetId`, `label` |

### 1.2 Message Record — Inner Structure

```json
{
  "type": "message",
  "id": "ab617062",
  "parentId": "373a632f",
  "timestamp": "2026-06-04T16:06:38.572Z",
  "message": {
    "role": "user|assistant|toolResult",
    "content": [...],
    "usage": {
      "input": 3,
      "output": 131,
      "cacheRead": 0,
      "cacheWrite": 26516,
      "totalTokens": 26650,
      "cost": {"input": 0.000009, "output": 0.001965, "cacheRead": 0, "cacheWrite": 0.099435, "total": 0.101409}
    },
    "stopReason": "toolUse|endTurn|maxTokens",
    "api": "anthropic-messages",
    "model": "claude-sonnet-4-6",
    "isError": false,
    "timestamp": 1780589195335
  }
}
```

### 1.3 Content Item Types (inside `message.content`)

**Assistant turn — tool call:**
```json
{"type": "toolCall", "id": "toolu_01...", "name": "bash", "arguments": {"command": "ls"}}
```

**Assistant turn — thinking block:**
```json
{"type": "thinking", "thinking": "Let me check...", "thinkingSignature": "..."}
```

**Assistant turn — text:**
```json
{"type": "text", "text": "Here is the result..."}
```

**Tool result turn:**
```json
{
  "role": "toolResult",
  "toolCallId": "toolu_01...",
  "toolName": "bash",
  "content": [{"type": "text", "text": "output here"}],
  "isError": true
}
```

### 1.4 Subagent Tool Call Structure

```json
{
  "type": "toolCall",
  "name": "subagent",
  "arguments": {
    "tasks": [
      {"agent": "worker", "task": "Do X in dir Y..."},
      {"agent": "scout",  "task": "Recon Z..."}
    ]
  }
}
```
Single-task form: `{"agent": "delegate", "task": "..."}` (no `tasks` array wrapper).

Subagent lifecycle custom_messages:
- `customType: "subagent_control_notice"` — subagent timed out (60s no activity)
- `customType: "subagent-notify"` — subagent paused/interrupted

### 1.5 branch_summary Structure

```json
{
  "type": "branch_summary",
  "timestamp": "2026-06-05T10:50:40.193Z",
  "summary": "The user explored a different conversation branch...\n## Goal\n...\n## Progress\n..."
}
```

### 1.6 Timestamps and Timing

Each record has a top-level `timestamp` (ISO8601 string). The inner `message.timestamp` is Unix milliseconds (integer). Both refer to the same moment.

**Inter-turn gap** = `record[N+1].timestamp - record[N].timestamp` (parse ISO8601).  
**Model response latency** = `message[role=assistant].timestamp - preceding message[role=toolResult].timestamp`.  
**Session wall-clock duration** = `last_record.timestamp - session_record.timestamp`.

### 1.7 Cost Accounting

Cost is per assistant-turn in `message.usage.cost.total`. Sum all assistant turns for session total.

Observed ranges on this project:
- Tiny session (27 lines): ~$4.50
- Small session (370 lines): ~$52
- Large session (2182 lines): ~$169

---

## 2 — Fleet Architecture

### 2.1 Partitioning Strategy

Sessions should be partitioned so each worker handles ≤ ~4MB / ~150K lines of JSONL to stay within 200K context limits after parsing overhead.

**This project's partition plan** (17 main sessions, ~36MB total):

| Worker | Sessions | Approx size | Theme |
|--------|----------|-------------|-------|
| W1 | `2026-06-04T16-05` (10.9MB) | 10.9MB | Full first session — dev env setup, protocol RE |
| W2 | `2026-06-05T07-08` (6.5MB) | 6.5MB | BT protocol + display rendering |
| W3 | `2026-06-05T13-27` + `13-35` + `13-36` | 5.7MB | Three parallel branches (WiFi, camera RE) |
| W4 | `2026-06-05T14-31` (×4, all small) | 1.6MB | Batch subagent children from Jun 5 |
| W5 | `2026-06-06T08-41` (×3) + `08-49` | 7.7MB | Parallel workers + architecture planning |
| W6 | `2026-06-06T20-58` (3.8MB) | 3.8MB | SEGKit build + UAT + sensor debugging |
| W7 | `2026-06-06T21-06` (×3, all tiny) + subagent children from 20-58 session | ~2MB | Parallel subagent fleet outputs |

**Subagent children** (40+ files under parent dirs): Add key ones to relevant worker (match by parent session date) or run a dedicated W8 for subagent quality analysis.

### 2.2 What Each Worker Extracts

```
Per worker, produce structured JSON with these keys:
{
  "session_ids": [...],
  "date_range": "YYYY-MM-DD to YYYY-MM-DD",
  "wall_clock_minutes": N,
  "total_cost_usd": N.NN,
  "turn_count": N,
  "tool_call_counts": {"bash": N, "read": N, "write": N, "edit": N, "subagent": N, ...},
  "error_count": N,
  "error_patterns": ["pattern1", ...],
  "repeated_mistakes": ["description with frequency", ...],
  "operator_feedback_moments": ["quote from user + context", ...],
  "operator_good_suggestions": ["suggestion text", ...],
  "successful_strategies": ["description", ...],
  "failed_strategies": ["description + why it failed", ...],
  "subagent_launches": N,
  "subagent_timeouts": N,
  "branch_count": N,
  "branch_summaries": ["one-liner", ...],
  "claude_md_suggestions": ["actionable suggestion", ...],
  "timing_observations": ["observation about latency/gaps", ...]
}
```

### 2.3 Consolidation Worker

Takes all W1–W8 JSON outputs → single final report (see §4).

### 2.4 Total Fleet Size

- 7–8 parallel Sonnet workers (analysis)
- 1 Opus consolidation worker
- Total: 9 subagent invocations

---

## 3 — Worker Prompt Template

> This is the universal per-worker prompt. Substitute `{SESSION_FILES}`, `{SESSION_DIR}`, `{PROJECT_NAME}`, `{DATE_RANGE}`, `{PROJECT_START_DATE}`.

---

```
You are an analysis worker. Your job: extract structured intelligence from Claude Code session transcript JSONL files.

## Project Context
- Project: {PROJECT_NAME}
- Session dir: {SESSION_DIR}
- Date range of sessions to analyze: {DATE_RANGE}
- Project start date: {PROJECT_START_DATE}
- Files to analyze:
{SESSION_FILES}

## JSONL Schema (brief)

Each line in a .jsonl file is one record. Key record types:
- `session`: first line, has `cwd`, `timestamp`
- `model_change`: model switch, has `modelId`
- `message`: every conversation turn. Inner `message.role` = user|assistant|toolResult
- `custom_message`: system events (subagent timeouts: customType="subagent_control_notice")
- `branch_summary`: user returned from a branch, has `summary` text
- `label`: user labelled a message (e.g. "wrong summary")

Inside assistant message content:
- `{"type":"toolCall","name":"bash","arguments":{...}}` — tool call
- `{"type":"thinking","thinking":"..."}` — internal reasoning
- `{"type":"text","text":"..."}` — response text

Inside toolResult messages:
- `isError: true` — tool call failed
- `content[0].text` — output or error text

Subagent launches: toolCall with `name:"subagent"` and `arguments.tasks[].agent` values ("worker"/"scout"/"delegate"/"oracle")

Cost is at `message.usage.cost.total` per assistant turn.

Timestamps are ISO8601 strings at record level. Compute durations by diffing timestamps.

## Extraction Tasks

Use bash + jq (or python3) to extract from the files. Then reason about patterns.

### Task A — Quantitative inventory

```bash
# Tool call frequencies
cat {SESSION_FILES} | python3 -c "
import sys, json, collections
tools = collections.Counter()
errors = 0
cost = 0.0
turns = 0
for line in sys.stdin:
    try:
        r = json.loads(line)
        if r.get('type') == 'message':
            msg = r.get('message', {})
            if msg.get('role') == 'assistant':
                turns += 1
                usage = msg.get('usage', {})
                cost_d = usage.get('cost', {})
                cost += cost_d.get('total', 0) if isinstance(cost_d, dict) else 0
                for c in msg.get('content', []):
                    if isinstance(c, dict) and c.get('type') == 'toolCall':
                        tools[c.get('name', '?')] += 1
            elif msg.get('role') == 'toolResult':
                if msg.get('isError'):
                    errors += 1
    except: pass
print(f'turns={turns} errors={errors} cost=\${cost:.2f}')
for k, v in tools.most_common(20): print(f'  {k}: {v}')
"
```

```bash
# Error messages — what failed
cat {SESSION_FILES} | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        r = json.loads(line)
        if r.get('type') == 'message':
            msg = r.get('message', {})
            if msg.get('role') == 'toolResult' and msg.get('isError'):
                text = ''
                for c in msg.get('content', []):
                    if isinstance(c, dict):
                        text += c.get('text', '')
                print(text[:200])
                print('---')
    except: pass
" | head -100
```

```bash
# Subagent launches and timeouts
cat {SESSION_FILES} | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        r = json.loads(line)
        t = r.get('type')
        if t == 'message':
            msg = r.get('message', {})
            for c in msg.get('content', []):
                if isinstance(c, dict) and c.get('name') == 'subagent':
                    args = c.get('arguments', {})
                    tasks = args.get('tasks', [args])
                    for task in tasks:
                        agent = task.get('agent', '?')
                        task_text = str(task.get('task', ''))[:100]
                        print(f'LAUNCH agent={agent}: {task_text}')
        elif t == 'custom_message' and r.get('customType') == 'subagent_control_notice':
            print(f'TIMEOUT: {r.get(\"content\", \"\")[:100]}')
    except: pass
"
```

```bash
# User messages — what did the operator say?
cat {SESSION_FILES} | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        r = json.loads(line)
        if r.get('type') == 'message':
            msg = r.get('message', {})
            if msg.get('role') == 'user':
                for c in msg.get('content', []):
                    if isinstance(c, dict) and c.get('type') == 'text':
                        print(r.get('timestamp', '?'), c.get('text', '')[:300])
                        print('---')
    except: pass
"
```

```bash
# Timing: inter-turn gaps > 60s (operator pauses / tool slowness)
cat {SESSION_FILES} | python3 -c "
import sys, json
from datetime import datetime
prev_ts = None
for line in sys.stdin:
    try:
        r = json.loads(line)
        ts_str = r.get('timestamp')
        if not ts_str: continue
        ts = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
        if prev_ts:
            gap = (ts - prev_ts).total_seconds()
            if gap > 60:
                print(f'GAP {gap:.0f}s at {ts_str[:19]} (type={r.get(\"type\")})')
        prev_ts = ts
    except: pass
"
```

### Task B — Qualitative analysis

After running the above, reason carefully about:

1. **Tool call patterns**: Which tools dominate? Is there excessive bash-to-read ratio (over-exploration)? Are write/edit calls preceded by adequate reads? Any tool called redundantly?

2. **Error patterns**: Cluster errors by type (command not found, file not found, Swift compile, network, permission). Which errors repeat? Were fixes correct on first retry or did the agent loop?

3. **Repeated mistakes**: Look for the same error appearing >2 times, or the same incorrect approach tried multiple times. Note the frequency and the eventual fix.

4. **Operator interventions**: User messages that correct the agent, redirect it, or provide missing context. Classify as: [correction] [redirect] [new-info] [approval] [escalation].

5. **Operator good suggestions**: Moments where the operator's framing, constraint, or direction clearly accelerated progress.

6. **Subagent effectiveness**: Were subagents used well? Did they complete their tasks? Did timeouts indicate poor task scoping? Were results integrated or ignored?

7. **Timing anomalies**: 
   - Timestamp relative to project start ({PROJECT_START_DATE}) shows maturity of the session
   - Large operator gaps (>5 min) between turns may indicate frustration or context-switching
   - Very fast operator replies suggest engaged real-time debugging

8. **CLAUDE.md gaps**: What information would have prevented mistakes if it existed in CLAUDE.md? What rules were learned the hard way?

### Task C — Output

Write a structured JSON object (one per worker) with this schema:

```json
{
  "worker_id": "W1",
  "sessions_analyzed": ["session-id-1", ...],
  "date_range": "YYYY-MM-DD to YYYY-MM-DD",
  "session_age_days_from_start": [0, 1, 2],
  "wall_clock_minutes": 240,
  "total_cost_usd": 169.18,
  "turn_count": 2159,
  "tool_call_counts": {"bash": 690, "read": 81, "write": 48, "edit": 88, "subagent": 28},
  "error_count": 82,
  "error_clusters": [
    {"type": "swift_compile", "count": 15, "example": "error: cannot find type..."},
    {"type": "command_not_found", "count": 8, "example": "avdmanager not found"},
    {"type": "network", "count": 3, "example": "kIOReturnNotAttached"}
  ],
  "repeated_mistakes": [
    "Used wrong RFCOMM channel (1 instead of 4) — repeated 3 times before fix",
    "Missing sensor ACK — sent SensorStart but forgot required [0x01,0x00,0x00] response"
  ],
  "operator_interventions": [
    {"type": "correction", "turn_approx": 45, "quote": "wrong channel, it's 4", "impact": "fixed BT connection"},
    {"type": "redirect", "turn_approx": 120, "quote": "use subagents for parallel work", "impact": "sped up phase 2"}
  ],
  "operator_good_suggestions": [
    "Suggesting smali decompilation to find actual sensor IDs — found 4 wrong IDs at once"
  ],
  "successful_strategies": [
    "Fan-out parallel delegate subagents for reading many files simultaneously",
    "Reading smali bytecode directly when SDK docs were ambiguous"
  ],
  "failed_strategies": [
    "Trying to install Android Studio via Homebrew — wrong package name, wasted 3 turns",
    "Camera chunk dedup by sequence number — rejected valid out-of-order BT segments"
  ],
  "subagent_launches": 12,
  "subagent_timeouts": 2,
  "branch_count": 3,
  "branch_one_liners": [
    "Branch: BT protocol RE + GoL animation",
    "Branch: WiFi data path prototype"
  ],
  "claude_md_suggestions": [
    "Add: 'RFCOMM channel 4 is SPP, channel 1 is HFP — always prefer 4'",
    "Add: 'Sensor ACK [0x01,0x00,0x00] required after each IMU frame or glasses stop sending'",
    "Add: 'All wire protocol values are big-endian (Java ByteBuffer default)'"
  ],
  "timing_observations": [
    "Session day 0: exploratory (high bash ratio, many reads)",
    "3 large operator gaps >10min at turns 45, 180, 340 — likely hardware testing breaks",
    "Subagent timeouts both on W-5 day sessions — task descriptions too vague"
  ]
}
```

Write this JSON to stdout. Do NOT write any files. Just output the JSON.
```

---

## 4 — Consolidation Prompt

> Feed all W1–W8 JSON outputs as input. Run with Opus.

---

```
You are a consolidation analyst. You have received structured JSON reports from {N} analysis workers, each covering a subset of session transcripts for project "{PROJECT_NAME}" (dates: {DATE_RANGE}, project started {PROJECT_START_DATE}).

## Your inputs

The following worker reports are pasted below (JSON objects, separated by ---):

{WORKER_OUTPUTS}

## Your task

Produce a single comprehensive analytics report in Markdown with these sections:

---

### 1. Executive Summary
- Total sessions analyzed, total cost, total turns, total errors
- Project timeline (start to latest session, how many active days)
- Overall health assessment (1 sentence)

### 2. Tool Usage Analysis
- Table: tool name | total calls | % of all calls | trend (increasing/decreasing/stable)
- Top insight: is the bash/read/write ratio healthy? (exploration vs exploitation)
- Notable tool misuse patterns

### 3. Error Analysis
- Table: error type | count | first seen | last seen | resolution
- Error recurrence rate (errors that appeared in 2+ separate sessions = systemic)
- Most costly errors (those that caused long recovery loops)

### 4. Repeated Mistakes (ranked by frequency × cost)
For each:
- What the mistake was
- How many times it recurred across sessions
- The eventual fix
- How long it took to fix (in turns / sessions / days)
- CLAUDE.md rule that would have prevented it

### 5. Operator Behaviour Analysis
- Intervention rate (operator corrections per 100 turns)
- Most common intervention types (correction/redirect/new-info/approval/escalation)
- Operator patterns that accelerated progress
- Operator patterns that caused confusion or wasted work
- Suggestions for better operator prompting

### 6. Subagent Fleet Analysis
- Launch count vs timeout count (ratio)
- Which agent types worked well (worker/scout/delegate/oracle)
- Task scoping issues (too vague → timeout; too narrow → missed context)
- Best-practice examples from this project

### 7. Timing & Pacing
- Session velocity over project lifetime (cost/day, turns/day)
- Peak activity periods
- Notable slow-downs and what caused them
- Operator engagement pattern (gaps suggest hardware testing, frustration, etc.)

### 8. Branch Analysis
- How many branches explored
- Were branches productive or exploratory dead-ends?
- Key insights discovered in branches that landed in main

### 9. CLAUDE.md Improvement Recommendations (PRIORITY RANKED)
For each recommendation:
- **Rule text** (ready to paste into CLAUDE.md)
- **Evidence** (session(s), approximate turn, what went wrong without it)
- **Priority**: HIGH / MEDIUM / LOW

### 10. Strategic Recommendations for Future Sessions
- Top 3 changes to agent workflow
- Top 3 changes to operator approach  
- Tool or infrastructure gaps that slowed the project

---

Be specific and cite evidence from the worker reports. Do not hallucinate patterns not present in the data.
```

---

## 5 — Ready-to-Run Invocation (sony-sed-e1)

This is the exact subagent invocation JSON to run this analysis on the sony-sed-e1 project.

### 5.1 Phase 1 — Parallel Worker Dispatch

```json
{
  "name": "subagent",
  "arguments": {
    "tasks": [
      {
        "agent": "worker",
        "task": "SESSION ANALYTICS WORKER W1\n\nProject: sony-sed-e1\nProject start date: 2026-06-04\nSession dir: /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/\nDate range: 2026-06-04\n\nAnalyze this session file:\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-04T16-05-45-067Z_019e9362-2bea-76cd-87bc-314dac45154b.jsonl\n\n[INSERT WORKER PROMPT TEMPLATE FROM §3 HERE]\n\nOutput ONLY the JSON object to stdout. No files."
      },
      {
        "agent": "worker",
        "task": "SESSION ANALYTICS WORKER W2\n\nProject: sony-sed-e1\nProject start date: 2026-06-04\nSession dir: /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/\nDate range: 2026-06-05 morning\n\nAnalyze this session file:\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-05T07-08-02-349Z_019e969c-3dad-74c8-af0f-86a3606985cd.jsonl\n\n[INSERT WORKER PROMPT TEMPLATE FROM §3 HERE]\n\nOutput ONLY the JSON object to stdout. No files."
      },
      {
        "agent": "worker",
        "task": "SESSION ANALYTICS WORKER W3\n\nProject: sony-sed-e1\nProject start date: 2026-06-04\nSession dir: /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/\nDate range: 2026-06-05 afternoon (three sessions)\n\nAnalyze ALL THREE of these session files:\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-05T13-27-40-844Z_019e97f7-d02c-7d63-9cc5-8b42c717d99e.jsonl\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-05T13-35-05-608Z_019e97fe-9988-7b65-aba8-7b20d62e26b3.jsonl\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-05T13-36-28-984Z_019e97ff-df38-7047-aee2-c744ff35b961.jsonl\n\nNote: These three sessions started within 10 minutes of each other — they are parallel branches.\n\n[INSERT WORKER PROMPT TEMPLATE FROM §3 HERE]\n\nOutput ONLY the JSON object to stdout. No files."
      },
      {
        "agent": "worker",
        "task": "SESSION ANALYTICS WORKER W4\n\nProject: sony-sed-e1\nProject start date: 2026-06-04\nSession dir: /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/\nDate range: 2026-06-05 late afternoon (four small sessions)\n\nAnalyze ALL FOUR of these session files:\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-05T14-31-34-696Z_019e9832-5028-7c4c-b124-e4520f099985.jsonl\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-05T14-31-34-765Z_019e9832-506d-7600-8565-4f0d16a41e2c.jsonl\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-05T14-31-34-835Z_019e9832-50b3-70ec-b8c4-86d249068949.jsonl\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-05T14-31-34-900Z_019e9832-50f4-7b9d-998a-1983b9ff0729.jsonl\n\nNote: All four started at the same second — they are parallel subagent children. Focus especially on subagent effectiveness.\n\n[INSERT WORKER PROMPT TEMPLATE FROM §3 HERE]\n\nOutput ONLY the JSON object to stdout. No files."
      },
      {
        "agent": "worker",
        "task": "SESSION ANALYTICS WORKER W5\n\nProject: sony-sed-e1\nProject start date: 2026-06-04\nSession dir: /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/\nDate range: 2026-06-06 morning (four sessions)\n\nAnalyze ALL FOUR of these session files:\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-06T08-41-44-257Z_019e9c18-6241-70b1-85f9-c57fc2d5c32f.jsonl\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-06T08-41-44-347Z_019e9c18-629b-7035-8425-f884849eeea3.jsonl\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-06T08-41-44-433Z_019e9c18-62f1-71fd-a268-9b971f7732ed.jsonl\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-06T08-49-28-677Z_019e9c1f-7865-76ea-9431-880175ceb29d.jsonl\n\nNote: First three started same second (parallel). Fourth is the main session that came after.\n\n[INSERT WORKER PROMPT TEMPLATE FROM §3 HERE]\n\nOutput ONLY the JSON object to stdout. No files."
      },
      {
        "agent": "worker",
        "task": "SESSION ANALYTICS WORKER W6\n\nProject: sony-sed-e1\nProject start date: 2026-06-04\nSession dir: /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/\nDate range: 2026-06-06 evening (large session)\n\nAnalyze this session file:\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-06T20-58-42-908Z_019e9ebb-1b5c-7d77-aa00-2c81d281c533.jsonl\n\nAlso check key subagent children under:\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-06T20-58-42-908Z_019e9ebb-1b5c-7d77-aa00-2c81d281c533/\n\nList the child dirs, read 10 lines from each run-0/session.jsonl, include subagent effectiveness analysis.\n\n[INSERT WORKER PROMPT TEMPLATE FROM §3 HERE]\n\nOutput ONLY the JSON object to stdout. No files."
      },
      {
        "agent": "worker",
        "task": "SESSION ANALYTICS WORKER W7\n\nProject: sony-sed-e1\nProject start date: 2026-06-04\nSession dir: /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/\nDate range: 2026-06-06 late evening (three tiny sessions)\n\nAnalyze ALL THREE of these session files:\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-06T21-06-51-263Z_019e9ec2-8eff-763d-8441-e8c0b693597c.jsonl\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-06T21-06-51-280Z_019e9ec2-8f10-7d78-a707-a12090ac6ddd.jsonl\n  /Users/gerhardgustav/.pi/agent/sessions/--Users-gerhardgustav-Desktop-hobby-dev-sony-sed-e1--/2026-06-06T21-06-51-289Z_019e9ec2-8f19-7701-9d18-b1b0e9216392.jsonl\n\nNote: These are parallel workers spawned at nearly the same second.\n\n[INSERT WORKER PROMPT TEMPLATE FROM §3 HERE]\n\nOutput ONLY the JSON object to stdout. No files."
      }
    ]
  }
}
```

### 5.2 Phase 2 — Consolidation (run after all workers complete)

Collect all 7 JSON outputs from the workers, then run:

```json
{
  "name": "subagent",
  "arguments": {
    "agent": "oracle",
    "task": "SESSION ANALYTICS CONSOLIDATION\n\nYou have JSON analysis reports from 7 workers covering all session transcripts of the sony-sed-e1 project (2026-06-04 to 2026-06-08).\n\nWorker outputs:\n\nW1: {paste W1 JSON here}\n---\nW2: {paste W2 JSON here}\n---\n[...etc...]\n\n[INSERT CONSOLIDATION PROMPT FROM §4 HERE]\n\nWrite the final report to: /Users/gerhardgustav/Desktop/hobby-dev/sony-sed-e1/_dev/SESSION_ANALYTICS_REPORT.md"
  }
}
```

---

## 6 — Usage Guide (Adapting to Other Projects)

### 6.1 Variable Substitution

| Variable | What to replace with |
|----------|---------------------|
| `{PROJECT_NAME}` | Your project name |
| `{SESSION_DIR}` | `~/.pi/agent/sessions/--<cwd-with-dashes>--/` |
| `{DATE_RANGE}` | First session date to last session date |
| `{PROJECT_START_DATE}` | Date of earliest session (for age calculations) |
| `{SESSION_FILES}` | Space-separated list of .jsonl paths for this worker |
| `{N}` | Number of workers |
| `{WORKER_OUTPUTS}` | All worker JSON objects concatenated with `---` |

### 6.2 Finding Your Session Dir

```bash
# Find your project's session dir
PROJECT_CWD="/path/to/your/project"
SLUG=$(echo "$PROJECT_CWD" | sed 's|/|-|g' | sed 's|^-||')
ls ~/.pi/agent/sessions/--${SLUG}--/
```

### 6.3 Sizing Your Fleet

```bash
# Check sizes to decide partitioning
for f in ~/.pi/agent/sessions/--YOUR-PROJECT--/*.jsonl; do
  echo "$(wc -c < "$f")B  $(basename $f)"
done | sort -rn
```

Rule of thumb:
- < 2MB: safe to combine 3-4 sessions per worker
- 2–8MB: 1 session per worker (or split large ones)
- > 8MB: split into halves by line offset

### 6.4 Splitting a Very Large Session

```bash
# Split a 10MB session into two halves
TOTAL=$(wc -l < large.jsonl)
HALF=$((TOTAL / 2))
head -n $HALF large.jsonl > large_part1.jsonl
tail -n +$((HALF+1)) large.jsonl > large_part2.jsonl
```

### 6.5 Running Without Pi Subagents

If you don't have the `subagent` tool, run each worker prompt manually as a separate Claude conversation with the JSONL file paths provided. Collect the JSON outputs and feed them all to the consolidation prompt in one final conversation.

### 6.6 Interpreting the Timing Dimension

The timestamp on each session combined with `{PROJECT_START_DATE}` gives you session age in days. Key interpretations:

- **Day 0–1**: Exploration phase — expect high error rates, many reads, bash-heavy. This is normal.
- **Day 2–5**: Learning phase — errors should decrease, writes/edits increase. If errors stay high, systemic issue.
- **Day 5+**: Execution phase — should be mostly writes/edits, low errors. If still high bash ratio, agent hasn't learned the codebase.

A healthy project shows this trajectory across sessions. A struggling project shows error rates that don't decrease.

### 6.7 CLAUDE.md Update Workflow

After running the analysis, the consolidation report will have a §9 with ranked CLAUDE.md recommendations. Review them, then:

1. Verify each recommendation against the actual code/session
2. Add HIGH priority items immediately
3. Add MEDIUM items if they're project-specific (not general Claude behaviour)
4. Skip LOW items unless they address systemic issues
5. Keep CLAUDE.md under 2KB — it's read every session, dense > exhaustive

---

*End of runbook. This document is self-contained and reusable across any Pi-managed project.*
