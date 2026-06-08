# Session Analytics Report — sony-sed-e1
> Generated: 2026-06-08  
> Covers: 17 main sessions + 37 subagent children (54 transcripts total)  
> Project start: 2026-06-04 · Analysis date: 2026-06-08  
> Workers: W1–W7 (Sonnet 4.6) + this consolidation pass (Opus 4.6)

---

## 1. Executive Summary

| Metric | Value |
|--------|-------|
| **Total sessions** | 17 main + 37 subagent children = **54 transcripts** |
| **Project duration** | Jun 4–8, 2026 (4 days active) |
| **Total API cost** | **~$633 USD** (Jun 4: $169, Jun 5: $228, Jun 6: $227, Jun 8: $9+) |
| **Total assistant turns** | ~2,800 across all sessions |
| **Total tool calls** | ~4,800+ |
| **Total tool errors** | ~313 unique errors (error rate: ~6.5% overall) |
| **Subagent launches** | ~180 individual task dispatches |
| **Subagent timeout/failure** | ~18 timeouts, 3 full failures |
| **Estimated wasted cost** | **~$85–100** (duplicate forks + wrong-path work + retry loops) |
| **Project health** | ✅ Good — core deliverables achieved. Hardware protocol cracked, SDK built, 8 demos working on both emulator and real glasses |

### Timeline at a Glance

```
Jun 4 16:05  Session starts. Android emulator path attempted (1.5h wasted).
             Operator provides device MAC. NFC payload decoded.
Jun 5 01:06  Overnight autonomous RE: APK decompiled, smali analyzed, Swift tool built.
Jun 5 10:32  BREAKTHROUGH: "i see checkers!" — first pixels on real glasses.
Jun 5 13:15  "yeah, nice" — GoL animation at 2.4fps confirmed.
Jun 5 14:31  WiFi subagent chain launched (research → implement → review).
Jun 6 08:41  Parallel fork sessions × 3 — same work triplicated ($47 wasted).
Jun 6 08:49  Full architecture redesign begins. SEGKit + SEGExplorer planned.
Jun 6 21:00  "step back and restart" → 37-child subagent fleet built entire SDK.
Jun 7 09:43  Phase 1–3 complete: 8 demos, camera, sensors, BT+WiFi transport.
Jun 8 09:01  Current session: Java SDK docs analysis + session analytics.
```

---

## 2. Tool Usage Analysis

### Cross-Session Tool Frequencies (estimated across all unique sessions)

| Tool | Count (est.) | % | Trend |
|------|-------------|---|-------|
| **bash** | ~2,700 | 73% | Constant throughout — never drops below 70% |
| **read** | ~500 | 13% | Spiked in subagent children (W6 children: 348 reads) |
| **edit** | ~430 | 12% | Peaked Day 1 during iterative Swift coding |
| **write** | ~240 | 6% | Higher in subagent children (bulk file creation) |
| **subagent** | ~180 | 5% | Escalated Day 2 onward as operator pushed parallelism |
| **AskUserQuestion** | ~120 | 3% | Healthy use — 33 in W1 alone |
| **exa_search** | ~5 | <1% | Severely underused (see §3) |
| **grep/find/ls** | ~110 | 3% | Primarily subagent children |

### Bash/Read Ratio

Across all sessions: **bash:read ≈ 5.4:1**

W2 flags the worst offender: **38% of all bash calls in Day 0** began with `export PATH=...` — a pure overhead pattern (~136 redundant exports). Every bash tool call runs in a fresh shell. Cumulative waste: hundreds of characters of noise per turn.

**Pattern observations:**
- Agent consistently uses `cat file.swift` via bash instead of `Read` tool. `Read` handles large files with `offset/limit`; bash-cat dumps the whole thing into context.
- `edit` tool usage clustered on `glasses-tool.swift` (a 1400+ line file), which explains the high edit failure rate (see §3).
- `exa_search` was called only 5 times total across 54 sessions. Several costly multi-attempt loops (emulator BT, macOS WiFi AP, CoreWLAN API) would have been immediately resolved by a single search.

### Ratio Trends Over Time

| Day | bash% | edit% | subagent% | Error rate |
|-----|-------|-------|-----------|------------|
| Day 0 | 72% | 9% | 2.9% | 8.4% |
| Day 1 | 76% | 12% | 4.1% | 6.5–11% |
| Day 2 | 74% | 10% | 7.4% | 5.8–9.6% |
| Day 4 | 61% | 0% | 14% | 0.0% |

Error rate improved from 8.4% → 0% over the project. Subagent usage grew as operator consistently prompted toward parallelism.

---

## 3. Error Analysis

### Error Types Ranked (across all unique sessions)

| Rank | Error Type | Count (est.) | % | Sessions |
|------|-----------|-------------|---|---------|
| 1 | **Generic exit code 1 (non-zero, silent)** | ~100 | 32% | All sessions |
| 2 | **Other/mixed** (APK, ADB, Android tooling) | ~85 | 27% | W1, W2, W3 |
| 3 | **Swift compile errors** | ~35 | 11% | W1, W2, W5, W6 |
| 4 | **Edit tool oldText mismatch** | ~17 | 5% | W1, W3, W4, W5, W6 |
| 5 | **Timeout** | ~26 | 8% | W1, W4, W6 |
| 6 | **Network/connection** | ~15 | 5% | W2, W4, W6 |
| 7 | **File not found** | ~8 | 3% | W1, W2, W4 |
| 8 | **Permission/sudo denied** | ~4 | 1% | W4 |

### Most Costly Errors

1. **Android emulator BT wall** (W1, W2): ~1.5h of work, ~$25–30 in API cost. 3 API levels tried (21, 24, 30). A single `exa_search` would have immediately revealed "Apple Silicon emulators have no BT." 

2. **Timeout retry cascade** (W6): 13 identical timeouts in 10 minutes (13:41–13:51 Jun 7) from `RunLoop.current.run()` blocking a piped shell. Agent kept decreasing timeout values on the same broken approach instead of changing strategy. Cost: ~$1.30 + 10 minutes.

3. **Display rendering off-screen** (W3): `LayoutInit(419, 138, 1)` sent instead of `LayoutInit(0, 0, 0)`. Images rendered off-screen for **30+ minutes**. Cost: ~$15–20 in debugging turns. Fixed only by smali re-analysis.

4. **Edit mismatch on `glasses-tool.swift`** (W1, W3, W4, W5, W6): 17 total edit failures across sessions. The file exceeded 1400 lines and was being modified by both main session and subagent workers simultaneously. Each failure: 2–3 turns to recover.

5. **Mock sensor data undetected** (W6): `SensorDemo` displayed `Accel: 0.12` (hardcoded). Agent didn't validate that data was dynamic. Operator caught it ("check logs you will be surprised…static"). Cost: wasted UAT cycle + operator trust degradation.

### Error Resolution Patterns

| Error | First attempt fix | Eventual fix | Turns wasted |
|-------|------------------|--------------|-------------|
| RFCOMM channel | Tried channels 1, 7, 4 in sequence | Channel 4 hardcoded (correct) | ~8 turns |
| LayoutInit coordinates | Assumed dimensions → off-screen | Smali analysis revealed `(0,0,0)` | ~30 turns |
| Sensor IDs | Guessed from SDK docs | Smali decompilation found true IDs | ~15 turns |
| BT RunLoop blocking | Increased timeout → timeout → ... | tmux-based UAT | ~13 turns |
| Edit mismatch | Re-tried → failed → re-tried | Python3 heredoc file surgery | ~3 turns each |

**Pattern**: Protocol/hardware errors that were solved by "look at reference code / smali" averaged 3–5x fewer turns than errors solved by trial-and-error.

---

## 4. Repeated Mistakes — Ranked by Frequency × Cost

### 🔴 CRITICAL (high frequency, high cost)

**#1 — Sending display commands before handshake complete**  
- Frequency: **8+ occurrences** (W1 ×4, W3 ×4)  
- Impact: Glasses firmware corrupted state, required power cycle, multiple UAT sessions failed  
- Eventual fix: Established the BT→FOTA status→OpenApp→LINIT→ready lifecycle  
- Cost: ~$20–25 in debugging turns  
- CLAUDE.md rule: *"LIFECYCLE: Never send any display data until this sequence completes: (1) BT RFCOMM connect, (2) FOTA status received (0x81) or 5s timeout, (3) OpenApp received (0x31) or 3s timeout, (4) LINIT sent and ACKed, (5) SyncResponse (0xFF) sent. Glasses entering wrong state requires power cycle."*

**#2 — Edit tool exact-match failures on large files**  
- Frequency: **~17 occurrences** (W1×5, W3×2, W4×2, W5×6, W6×2)  
- Impact: 2–3 recovery turns each, fell back to python3 file surgery  
- Eventual fix: Python3 heredoc regex replacement  
- Cost: ~$8–12 total  
- CLAUDE.md rule: *"For files >500 lines (glasses-tool.swift, ProtocolActor.swift, Control.java): use write (full replacement) or bash python3 regex surgery. Never use edit on files modified by concurrent subagents — re-read first."*

**#3 — Android emulator BT attempts (Apple Silicon)**  
- Frequency: **6 attempts** across Day 0 (W1×3, W2×3)  
- Impact: 1.5h and ~$25–30 wasted before abandoning  
- Eventual fix: Operator redirected to macOS native IOBluetooth  
- Cost: ~$25–30  
- CLAUDE.md rule: *"NEVER attempt BT testing on Android emulator on Apple Silicon. AVD on ARM64 has no Bluetooth hardware below API 30; API 30+ BT emulation requires virtio-serial-bus not available in standard images. Go directly to macOS native IOBluetooth."*

**#4 — Duplicate / triplicate subagent launches for identical tasks**  
- Frequency: **4 distinct incidents** (W3: 3 sessions, W4: 2-3x, W6: batch 2+3 and 5+6, W7: 3 identical forks)  
- Impact: $32–47 wasted on triplicated work  
- Root cause: Pi platform forks sessions at operator branch points; agent also relaunched with different role labels  
- CLAUDE.md rule: *"If the platform forked ≥2 sessions at the same 'step back'/'restart' moment, assume duplicate work is running. Check if tasks are already completed before launching more workers. Don't re-launch subagents with different role names (worker/delegate/scout) for the same task — pick one."*

### 🟡 HIGH (moderate frequency, significant cost)

**#5 — Wrong BT device selection**  
- Frequency: **7 operator corrections** (W5: 4 corrections in 9 min, W7: similar)  
- Impact: 9 minutes wasted in one UAT session  
- Root cause: Agent used cached `~/.glasses-last` device (`6b`) when operator was wearing `8e` or `8f`  
- CLAUDE.md rule: *"Three SmartEyeglass devices are paired: 6b (ac-9b-0a-37-a6-6b), 8f (ac-9b-0a-37-a6-8f), 8e (ac-9b-0a-37-a6-8e). Device `6b` is the primary UAT unit. ALWAYS ask the operator which suffix they are wearing before connecting. Never use cached selection silently."*

**#6 — Guessing wire protocol values instead of reading smali**  
- Frequency: **4+ incidents** (sensor IDs W6, camera endianness W6, LayoutInit W3, sensor ACK W6)  
- Impact: Multi-session debugging loops, 4 wrong sensor IDs shipped, camera frames malformed  
- Eventual fix: Smali decompilation from `_dev/smarteyeglass-explorer/` and Sony APK  
- CLAUDE.md rule: *"PROTOCOL GROUND TRUTH: All wire protocol constants, payload sizes, and endianness must be verified against smali in `Sony/` and `_dev/smarteyeglass-explorer/libs/SmartEyeglassAPI/`. SDK docs are incomplete. smali has the truth. Never invent protocol values."*

**#7 — Claiming hardware success without proof**  
- Frequency: **5+ corrections** (W5, W6, W7)  
- Examples: "BT connected!" before handshake; sensor data was static/mock; WiFi "working" without byte-level logs  
- CLAUDE.md rule: *"Never claim a hardware feature works without: (1) showing actual wire bytes received, (2) confirming dynamic data (not hardcoded), (3) operator visual confirmation. Use --debug flag to show TX/RX hex dumps as evidence."*

**#8 — Timeout retry loop without strategy change**  
- Frequency: **13 identical timeouts** in W6, **6 timeouts** in W1  
- Pattern: Same command retried with decreasing timeouts instead of changing approach  
- CLAUDE.md rule: *"After 2 consecutive failures of the same command, STOP and change strategy. Do not change only the timeout value and retry. Diagnose root cause first."*

**#9 — PATH exports in every bash call**  
- Frequency: **136 occurrences in W2 alone** (Day 0)  
- Impact: Pure context waste, ~136 extra lines of noise  
- CLAUDE.md rule: *"Absolute tool paths: ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb, JAVA_HOME=/opt/homebrew/opt/openjdk@17, SWIFT=/usr/bin/swift. Use absolute paths instead of prepending export PATH= to every command."*

### 🟢 MEDIUM (occasional, recoverable)

**#10 — Subagent with invalid agent type**  
- Frequency: 2 occurrences (W5: `general-coding`, W1: `code`)  
- CLAUDE.md rule: *"Valid subagent agent types: worker, scout, delegate, oracle. Any other string fails silently or errors. Never invent agent type names."*

**#11 — Feature removal without confirmation**  
- Frequency: 1 confirmed incident (WiFi auto-upgrade removed, W5)  
- CLAUDE.md rule: *"Never remove a working feature without explicit operator approval. 'Simplifying' is not a reason to delete functionality."*

**#12 — Test suite against live hardware without mocks**  
- Frequency: 6 consecutive pytest retry loops (W5)  
- CLAUDE.md rule: *"Protocol tests that require live device must be marked @pytest.mark.hardware and skipped by default. Unit tests must use mock transport. Never run live-device tests >2 times without diagnosing root cause."*

---

## 5. Operator Behaviour Analysis

### Intervention Rate

- Total operator messages: ~205 across all sessions
- Corrections (redirecting wrong behavior): ~38 (18.5%)
- Redirects (strategic pivots): ~22 (10.7%)
- New information: ~18 (8.8%)
- Approvals: ~45 (22%)
- Short confirmations ("yes", "1", "ok"): ~82 (40%)

**Intervention rate: ~29%** of all operator messages actively corrected or redirected agent behavior. This is high — roughly 1 in 3 non-trivial messages was a correction.

### Operator Communication Style

The operator is **terse, directive, and technically sophisticated**:
- Short messages ("yes", "1", "bro its you who need to initiate pairing")
- Provides raw hardware artifacts directly (BT scan output, WiFi hex dumps, NFC payloads)
- Expects agent to figure out implementation details
- Corrects scope creep decisively (3 messages to trim demo auto-start)
- **Fast follow-ups** (44-second gap = watching in real-time and not happy)

### Highest-Impact Operator Interventions

| Rank | Quote | Session | Impact |
|------|-------|---------|--------|
| 1 | "don't guess, just look reference code" | W6, W7 | Found 4 wrong sensor IDs; all subsequent protocol work correct |
| 2 | "lets just write up to date sdk...no permissions yolo" | W1 | Pivoted entire approach to smali RE instead of fighting emulator |
| 3 | "Test only after connection. Understand the sequence." | W3 | Established glasses init lifecycle protocol |
| 4 | "subagents and ultracode are superpowers" | W6 | Unlocked 37-child fleet that built the entire SDK |
| 5 | "separate threads: control/media/heartbeat" | W5 | Led directly to actor-based TransportActor/ProtocolActor architecture |
| 6 | "we own the full stack, don't be confused by Android intents" | W5 | Simplified camera architecture, removed unnecessary abstractions |
| 7 | "lets make sure we don't lose logs from all runs" | W6 | Led to persistent ~/.seg-logs/ archival system |
| 8 | "maybe it is a rectangle that I am treating as empty display?" | W3 | Led to understanding green OLED rendering, unlocked first visual debug |

### Operator Mistakes / Confusion Patterns

1. **Branch creation creates parallel sessions** (W3, W4, W7): The operator forked sessions multiple times without realizing the platform was running 3 identical sessions in parallel. This tripled cost on 3 separate occasions. The operator wasn't informed about the fork behavior.

2. **"step back and restart"** triggered triple fork (W7): Well-intentioned correction, but cost $1.62 in duplicate work immediately after.

3. **Implicit context expectations**: Operator would say "continue the work" without specifying which task. Agent spent turns finding current state via sequential file reads, prompting "kind reminder — subagents are superpowers" 44s later. A `progress.md` discipline would remove this friction.

4. **Model quality complaint too late** (W3): "I'm sorry, but what is Sonet 4? please use sonnet 4.6" — model quality concern raised 15 hours in. Should be in CLAUDE.md defaults from day 0.

### Suggestions for Better Operator Prompting

1. **Open sessions with**: "Continue from progress.md. Use subagents for anything that touches >1 file." Eliminates sequential-file-read orientation delay.
2. **When forking**: "Run one branch only — avoid triplicating work."
3. **Hardware sessions**: Begin with explicit device suffix: "Using glasses `6b` today."
4. **Before UAT**: "Confirm: BT powered, glasses on, device suffix `__`."

---

## 6. Subagent Fleet Analysis

### Total Fleet Statistics

| Metric | Value |
|--------|-------|
| Total task dispatches | ~180 across all sessions |
| Fully successful | ~145 (81%) |
| Partial / timeout | ~23 (13%) |
| Complete failures | ~12 (6%) |
| Average cost per task | $0.48 (children), $1.10 (main-session delegates) |
| Duplicate waste identified | ~$35–47 |
| Model waste (Opus where Sonnet sufficient) | ~$8–12 |

### Task Type Effectiveness

| Task Type | Success Rate | Notes |
|-----------|-------------|-------|
| **Read/recon/analysis** | ~95% | Best use of subagents. Self-contained, clear output. |
| **Code review (adversarial)** | ~70% | Good when scoped to ≤3 files. Timed out when at end of long chains. |
| **Single-file implementation** | ~85% | Works when file content is fresh (not concurrently edited). |
| **Multi-file implementation** | ~60% | Edit mismatches from stale reads. Needs read-first protocol. |
| **Hardware-interaction** | **~10%** | Fails always — subagents can't access open BT/TCP connections. |
| **Chain (A→B→C→review)** | ~50% | Chain step 4 (reviewer) timed out in every observed chain. |

### Model Choice Efficiency

The Jun 6 20:58 session used **claude-opus-4-6 for all 37 subagent children**. Analysis of what those children actually did:
- 14 of 19 agents: read-dominant recon (reading Java/smali files). These are pure reasoning tasks where Sonnet 4.6 performs comparably at ~10× lower cost.
- 5 of 19 agents: write/build tasks (creating Swift packages, writing implementations). Opus justified.

Estimated savings if Sonnet used for recon: **~$8.50 on this one fleet** ($9.45 → ~$0.95 for the 14 read agents). Extrapolated across the project, this pattern likely represents $20–30 in avoidable Opus spend.

### Best Fleet Patterns Observed

1. **4-delegate parallel SDK read** (W6 Batch #9): Four delegates simultaneously read SmartExtensionAPI, SmartExtensionUtils, SmartEyeglassAPI, and demos → results compressed into ARCHITECTURE_MODERN.md. Saved ~1 hour vs sequential.

2. **Scout-then-build pipeline** (W6 Batches #4→#5): Scouts find current file state → workers get explicit file locations and content → very low edit mismatch rate.

3. **Parallel package creation with shared spec** (W6 Batch #11): Two packages (SEGKit + SEGExplorer) built simultaneously because both could reference the spec in ARCHITECTURE_MODERN.md. Zero conflicts.

4. **Single smali-analysis delegate** (W1 Batch #3): One focused delegate read 13 WiFi smali files → `/tmp/wifi-smali-analysis.md`. ~$2 for high-quality protocol documentation. Best cost/value in the project.

### Worst Fleet Patterns Observed

1. **Reviewer at end of long chain**: Every chain (WiFi chain W4, review chain W1) had the reviewer time out. The pattern of `research → implement → review` means the reviewer runs last with maximal context load. **Fix**: Run reviewer as first step with a snapshot of the output, or as an independent batch.

2. **Re-launching with different role labels**: W6 batches 5+6 launched identical tasks first as `worker` then as `delegate`. Both ran. Fix: pick one role and commit.

3. **Subagent chain paused 6h, reviewer never recovered**: The Jun 5 WiFi chain was paused at 14:55, resumed at 20:33. The reviewer step (step 4) was never re-triggered after resume. **Fix**: When resuming a paused chain, explicitly re-dispatch the remaining steps.

---

## 7. Timing & Pacing

### Cost Per Day

| Day | Date | Cost | Active Hours | Cost/Hour |
|-----|------|------|-------------|----------|
| 0 | Jun 4 | $169.18 | ~5.2h | $32.54/h |
| 1 | Jun 5 | $227.70 | ~10h | $22.77/h |
| 2 | Jun 6 | $227.14 | ~12h | $18.93/h |
| 4 | Jun 8 | $9.12+ | ~2h | ~$4.56/h |
| **Total** | | **$633.14+** | **~29h** | **$21.83/h avg** |

Day 0 was most expensive per hour — environment setup, wrong-path exploration, and RE work. Efficiency improved each day as the codebase stabilized and the agent accumulated domain knowledge.

### Operator Engagement Pattern

```
Day 0 evening  (2.25h active): Setup → BT pairing → overnight hand-off
Day 1 overnight (6h autonomous): Deep RE work with no operator input
Day 1 morning  (5.5h active): Live hardware debugging, multiple pivots
Day 2           (12h span): Long day with 4.5h + 2h gaps; WiFi + architecture
Day 3           (12h span): UAT day — real-time BT debugging, sensor fixing
Day 4           (2h active): Meta-work, analytics
```

### Notable Response Patterns

- **44-second operator reply** (W7): After agent continued sequentially despite instructions → operator was watching live. Very fast follow-up = low patience mode.
- **6-hour pause** (W4): Operator paused WiFi chain work at 14:55. Returned 6 hours later to find the reviewer had never run.
- **Rapid-fire hardware debugging** (W3): 30 operator turns in 2 hours during display debugging = ~4 min/turn — physically handling glasses between turns.
- **Overnight gaps** (W1, W6): 9–36h overnight breaks. Agent had no activity during these periods (no background tasks persisted).

### Peak Productivity Window

Most valuable 2.5 hours in the project: **Jun 7 09:43–12:17** (W6)
- All of SEGKit + SEGExplorer built
- Phase 1 (handshake FSM) → Phase 2 (all 8 demos) → Phase 3 (camera/sensors) completed
- ~$35 spent, enormous output (10 SDK files, 14 demo files, working emulator verification)
- What made it work: architecture spec already written in ARCHITECTURE_MODERN.md, parallel workers dispatched with clear file targets

### Most Wasteful Window

**Jun 4 16:05–17:42** (W1, W2):
- Android emulator BT attempts × 3 API levels
- ~$25–30 spent
- Zero useful output
- Resolved by single operator redirect

---

## 8. Branch Analysis

### Confirmed Branch Events

| Date | Sessions | Branch Type | Valuable? | Notes |
|------|----------|-------------|-----------|-------|
| Jun 5 13:27 | 3 sessions (W3) | Pi fork at adversarial review request | ❌ Wasted | All 3 sessions ran identical task on same filesystem. S1 did work, S2+S3 redundant. |
| Jun 5 14:31 | 4 sessions (W4) | Pi fork at WiFi chain launch | ⚠️ Mixed | S1 was orchestrator. S2 did research (valuable). S3+S4 re-launched same chain. |
| Jun 6 08:41 | 3 sessions (W4) | Pi fork at "big redesign" moment | ❌ Wasted | $47.46 for $15.82 of unique work. |
| Jun 6 21:06 | 3 sessions (W7) | Pi fork at "step back" | ❌ Wasted | $2.43 for $0.81 of unique work. |
| Jun 8 current | 2+ sessions (W7) | Fork at analytics task | ⚠️ Mixed | Monitor interference caused one re-run. |

### Branch Cost Summary
- 4 confirmed wasteful fork incidents
- Total wasted from forks: **~$50–55**
- Pattern: Pi platform creates forks at branch points in conversation; each fork independently replays the same agent decisions

### Key Discoveries That Came FROM Branches

The branch exploration (W1 branch summary) shows a whole parallel workstream discovered:
- Sensor type IDs from smali (gyro=0x0d, mag=0x0e, light=0x10, battery=0x03)
- Sensor ACK requirement `[0x01,0x00,0x00]`
- Camera JPEG big-endian byte order fix
- Full input event types (tap/longPress/swipe/back/camera/PTT/jogCW/jogCCW)
- CameraStreamDemo frame saving
- AudioDemo via ffmpeg
- REPL ar/normal/raw commands

These were significant protocol fixes that were merged into main. The branch exploration was architecturally valuable even if some parallel sessions were wasteful.

---

## 9. CLAUDE.md Improvement Recommendations

### Priority: HIGH — Add immediately

**Rule H1: Hardware lifecycle (prevents ~$25, most common operator frustration)**
```
## SmartEyeglass Hardware Lifecycle
NEVER send display data until the full init sequence completes:
1. BT RFCOMM connects on channel 4 (SPP)
2. FOTA status received (0x81) OR 5s timeout passes
3. OpenApp received (0x31) OR 3s timeout passes
4. LINIT command sent (0x30)
5. SyncResponse (0xFF) sent
6. Display commands can now be sent — wait for 0xe8 ACK after each

Violation = glasses enters bad state = power cycle required.
```
Evidence: W1 (4 occurrences), W3 (4 occurrences), multiple operator frustration escalations.

**Rule H2: Always confirm BT device before connecting (prevents ~$10, recurring annoyance)**
```
## Bluetooth Device Selection
Three paired devices: 6b (ac-9b-0a-37-a6-6b), 8f, 8e.
Primary UAT unit: `6b`. ALWAYS ask operator "which device suffix are you wearing today?"
before connecting. Never use cached ~/.glasses-last silently.
```
Evidence: W5 (4 corrections in 9 min), W7.

**Rule H3: No emulator Bluetooth on Apple Silicon (prevents ~$25–30)**
```
## Android Emulator Bluetooth — FORBIDDEN
Apple Silicon ARM64 AVDs have NO Bluetooth support. Don't attempt it at any API level.
For hardware testing: use macOS IOBluetooth.framework directly.
For protocol testing without hardware: use TCP transport (--local flag).
```
Evidence: W1, W2 (6 total attempts, 1.5h wasted).

**Rule H4: Edit tool guidance (prevents ~$10)**
```
## Editing Large Files
For files >500 lines (glasses-tool.swift, ProtocolActor.swift, GlassesConnection.swift):
- Prefer `write` (full replacement) OR `bash python3` regex surgery
- NEVER use `edit` on a file modified by a concurrent subagent — re-read first
- If edit fails with "oldText not found": immediately re-read the file, do NOT retry with same oldText
```
Evidence: W1×5, W3×2, W4×2, W5×6, W6×2 (17 total failures).

**Rule H5: Protocol constants from smali only (prevents multi-session debugging loops)**
```
## Wire Protocol Ground Truth
ALL wire protocol constants, payload sizes, byte order, ACK sequences must be verified
against smali in: Sony/sony_smarteyeglass_sdk/ and _dev/smarteyeglass-explorer/libs/
The SDK Javadoc is incomplete. smali has the authoritative values.
Key verified values: gyro=0x0d, mag=0x0e, light=0x10, battery=0x03, channel=4, all big-endian.
Never invent or guess protocol values.
```
Evidence: W6, W7 (4 wrong sensor IDs, camera endianness, LayoutInit bug).

**Rule H6: Proof required for hardware claims (prevents trust degradation)**
```
## Hardware Verification Standard
Never claim a hardware feature works without:
1. Showing actual wire bytes received (use --debug flag for TX/RX hex dumps)
2. Confirming data is dynamic (not hardcoded mock values)
3. Explicit operator visual confirmation
"BT connected!" without showing handshake bytes = invalid claim.
```
Evidence: W6 (mock sensor data), W5 (WiFi "working" without proof), W7.

### Priority: MEDIUM — Add soon

**Rule M1: Retry limit**
```
## Retry Policy
After 2 consecutive identical failures: STOP and change strategy.
Do NOT change only the timeout value and retry. Diagnose root cause first.
After 3 failures of any kind: ask operator for guidance before continuing.
```
Evidence: W6 (13 identical timeouts), W1 (6 timeouts), W5 (6 pytest loops).

**Rule M2: Valid subagent types**
```
## Subagent Agent Types
Valid values: worker, scout, delegate, oracle
Any other string (e.g. "code", "general-coding", "reviewer") will fail.
- worker: implements changes, writes files
- scout: read-only recon, produces analysis
- delegate: high-level delegation with autonomy
- oracle: analysis/reasoning without tool use
```
Evidence: W1 (`code` type), W5 (`general-coding`).

**Rule M3: Never remove working features**
```
## Feature Preservation
Never delete or disable a working feature without explicit operator approval.
"Simplifying" is not a reason to remove functionality.
Always ask: "I'm planning to remove X — confirm?"
```
Evidence: W5 (WiFi auto-upgrade removed without asking).

**Rule M4: Model selection for subagents**
```
## Subagent Model Selection
- Recon/read/analysis tasks (reading files, summarizing): use claude-sonnet-4-6
- Build/implementation tasks (writing code, creating files): use claude-opus-4-6
- Code review: either, prefer sonnet for speed
Using Opus for recon tasks wastes ~10× budget per task.
```
Evidence: W6 (14 read-only agents used Opus, ~$8.50 waste).

**Rule M5: Subagent workers must ignore monitor**
```
## Subagent Task Template
Always include in subagent task instructions:
"IGNORE any .monitor/ files, proposal-ready.flag, or monitor proposals.
Do not read or act on monitor files. Your only deliverable is [specific task]."
```
Evidence: W7 (analytics worker derailed by monitor proposal, cost $2.21 extra).

**Rule M6: Duplicate fork detection**
```
## Fork Deduplication
The Pi platform creates parallel sessions at branch points. If you see identical inherited
context across multiple sessions, assume ≥1 duplicate is running.
Check if your task's output file already exists before starting work.
Don't re-launch subagents if their output files are already present.
```
Evidence: W3, W4, W6, W7 (multiple fork incidents, ~$50 total waste).

### Priority: LOW — Nice to have

**Rule L1: Absolute tool paths** (eliminates 136+ PATH exports/session)
```
## Tool Paths (Apple Silicon Mac)
ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb
JAVA_HOME=/opt/homebrew/opt/openjdk@17
SWIFT=/usr/bin/swift
PYTHON3=/usr/bin/python3
Use absolute paths instead of prepending export PATH=... to every bash call.
```

**Rule L2: Display hardware behavior**
```
## Display Behavior
Display auto-sleeps after ~10s idle. Touch sensor (tap) wakes it.
Always wait for 0xe8 PlaceRemoveAck before sending next display command.
Keep-alive: send minimal display update every 8s for demos.
```

**Rule L3: WiFi & network**
```
## WiFi Configuration
Credentials: .env file in project root (SSID=HOIV).
Auto-upgrade path: BT handshake → WiFi upgrade after LINIT → WiFi data transport.
Glasses and Mac must be on same network.
```

**Rule L4: Log persistence (already implemented, document it)**
```
## Log Persistence
All session logs auto-archived to ~/.seg-logs/seg-events-<ISO8601>.jsonl
Live tail: /tmp/seg-events.jsonl
Debug mode: --debug flag shows TX/RX hex for every frame.
```

**Rule L5: test harness**
```
## Test Architecture
Tests requiring live device: @pytest.mark.hardware, skipped by default.
Run with --local flag for TCP transport (emulator or real device via ADB forward).
Mock transport available for unit tests.
Never retry live-device tests >2× without diagnosing root cause.
```

---

## 10. Strategic Recommendations

### A. Agent Workflow Changes

**A1. Orient from `progress.md` in ≤2 bash calls**  
Current: Agent reads 4–6 files sequentially before understanding state (triggers operator "step back" resets).  
Fix: CLAUDE.md instruction: "Open every session by reading `progress.md` only. One recon subagent for current state if needed. Start executing in ≤2 turns."

**A2. Default to Sonnet subagents, escalate to Opus for builds**  
Current: Opus for all 37 children in the big Jun 6 fleet.  
Fix: Add model routing rule (Rule M4 above). Expected savings: ~$20–30 per major build session.

**A3. Output-file-first protocol for all subagent tasks**  
Current: Workers sometimes complete "without making edits" or produce noise.  
Fix: Every task MUST specify `output: /tmp/task-name.md` or `output: path/to/file.swift`. The worker's first act is confirming the output location exists/will be created. This creates a natural checkpoint.

**A4. Reviewer as independent batch, not chain tail**  
Current: Reviewer always ends the chain, always times out.  
Fix: Dispatch reviewer separately after confirming implementer completed. Or run reviewer on a snapshot/diff, not on live code. Chains longer than research→implement should not exist.

**A5. Smali-first for any unfamiliar protocol feature**  
Current: Agent guesses, tries, fails, then checks smali.  
Fix: Any new protocol feature starts with: "scout reads smali files in `_dev/smarteyeglass-explorer/libs/SmartEyeglassAPI/` → confirms constants → worker implements." The scout adds 1 turn and saves 5–15.

### B. Operator Approach Changes

**B1. Session-opening ritual**  
Before starting: confirm device suffix, BT powered state, WiFi network. One message: "Device 6b, BT on, WiFi HOIV. Continue SEGKit work from progress.md." This eliminates orientation overhead and wrong-device errors.

**B2. Avoid "step back" during active subagent dispatches**  
"Step back and restart" created 3 identical parallel sessions. Instead, use: "pause current work, then start fresh approach." Or let the current work finish and then redirect.

**B3. progress.md discipline**  
The `progress.md` is inconsistently maintained. Operator should prompt: "Update progress.md" at session end. Next session can orient in one read.

**B4. Explicit model request**  
"Use Opus for build sessions, Sonnet for analysis" added to session opener eliminates the $59 equivalent of Opus used for recon.

### C. Infrastructure Changes

**C1. Fork deduplication in Pi platform**  
The Pi platform creating 3 identical sessions at branch points is the single biggest avoidable cost in this project (~$50). If the platform cannot be changed: CLAUDE.md rule M6 + operator education.

**C2. Persistent shell environment for bash tool**  
W2 identified 136 PATH re-exports in Day 0 alone. If the tool cannot persist shell state, a `~/.bashrc` with tool paths could be sourced at the top of the first bash call per session.

**C3. Chain reviewer timeout fix**  
The reviewer always times out at the tail of long chains. The Pi framework's 270s subagent timeout should either be extended for review tasks, or reviewers should be dispatched independently.

**C4. Subagent output verification**  
Framework should fail loudly (not silently) when a worker completes "without making edits." Currently the main session has no way to know the worker was a no-op until checking the file manually.

---

## Appendix: Quick Reference — All CLAUDE.md Rules

Ready-to-paste rule set for CLAUDE.md:

```markdown
## SmartEyeglass Hardware Lifecycle [HIGH]
NEVER send display commands until: BT connect (ch4) → FOTA 0x81 or 5s timeout → OpenApp 0x31 or 3s timeout → LINIT 0x30 → SyncResponse 0xFF. Violation = power cycle required.

## BT Device Selection [HIGH]  
Paired: 6b (primary), 8f, 8e. ALWAYS ask which suffix before connecting. Never use cached address.

## No Emulator BT on Apple Silicon [HIGH]
AVD has NO Bluetooth. Use IOBluetooth directly or --local TCP transport for testing.

## Editing Large Swift Files [HIGH]
Files >500 lines: prefer write (full) or bash python3 surgery. Re-read before editing if subagents may have modified. On edit failure: re-read immediately, don't retry with stale oldText.

## Protocol Constants = smali [HIGH]
All wire constants from Sony/ and _dev/smarteyeglass-explorer/libs/SmartEyeglassAPI/. Never guess values.

## Hardware Claim Standard [HIGH]
No claim of "X works" without: TX/RX hex bytes showing, dynamic data confirmed (not mock), operator visual confirmation.

## Retry Policy [MEDIUM]
After 2 identical failures: change strategy. After 3 any failures: ask operator.

## Valid Subagent Types [MEDIUM]
worker, scout, delegate, oracle. No other values.

## Feature Preservation [MEDIUM]
Never remove working features without explicit operator approval.

## Subagent Model Selection [MEDIUM]  
Read/recon/analysis = claude-sonnet-4-6. Build/implementation = claude-opus-4-6.

## Subagent Monitor Suppression [MEDIUM]
Include in every subagent task: "IGNORE .monitor/ files and proposals. Your only deliverable is [task]."

## Fork Detection [MEDIUM]
Check output files exist before starting subagent work. Don't re-launch if outputs already present.

## Absolute Tool Paths [LOW]
ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb, JAVA_HOME=/opt/homebrew/opt/openjdk@17

## Display Behavior [LOW]
Auto-sleeps ~10s idle. 0xe8 ACK required between commands. Keep-alive every 8s.

## Valid Agent Types [LOW]
worker, scout, delegate, oracle only.
```
