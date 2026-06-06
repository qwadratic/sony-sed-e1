#!/usr/bin/env node
import { TUI, Container, Text, ProcessTerminal, type Component } from "@earendil-works/pi-tui";
import chalk from "chalk";

import { tailEvents } from "./events.js";
import { makeInitialState, applyEvent } from "./state.js";
import { GlassesProcess } from "./process.js";
import { HeaderBar } from "./components/HeaderBar.js";
import { EventLog } from "./components/EventLog.js";
import { ProtocolStatePanel } from "./components/ProtocolState.js";
import { QuickActions } from "./components/QuickActions.js";
import { MessageComposer } from "./components/MessageComposer.js";
import { GuardrailPanel } from "./components/GuardrailPanel.js";

const EVENTS_PATH = "/tmp/glasses-events.jsonl";
const args = process.argv.slice(2);
const noGlasses = args.includes("--no-glasses");

// ── Constants: lines consumed by fixed UI chrome ──────────────────────────────
//  1 title bar  +  1 status line  = 2 (HeaderBar)
//  1 divider
//  1 divider
//  2 quick-actions (divider + shortcuts)
//  1 guardrail (hidden unless active)
//  1 input line
const CHROME_LINES = 8;

// ── State ─────────────────────────────────────────────────────────────────────
let protocolState = makeInitialState();
let guardrailOn = false;

// ── Process ───────────────────────────────────────────────────────────────────
const glassesProc = new GlassesProcess();

function sendCmd(raw: string) {
  if (noGlasses) {
    eventLog.addEvent({ ts: Date.now(), type: "LOG", level: "INFO", msg: `[no-glasses] ${raw}` });
    tui.requestRender();
    return;
  }
  glassesProc.send(raw);
}

function handleUserCommand(raw: string) {
  const cmd = raw.trim();
  if (!cmd) return;
  if (guardrailOn) {
    guardrailPanel.setPending(cmd);
    tui.setFocus(guardrailPanel as unknown as Component);
    tui.requestRender();
    return;
  }
  sendCmd(cmd);
}

// ── Components ────────────────────────────────────────────────────────────────
const headerBar    = new HeaderBar(protocolState, guardrailOn);
const eventLog     = new EventLog();
const statePanel   = new ProtocolStatePanel(protocolState);
const quickActions = new QuickActions();
const composer     = new MessageComposer();
const guardrailPanel = new GuardrailPanel();

// ── Split panel: fixed height, event log left / state right ──────────────────
class SplitPanel implements Component {
  private height = 20;

  setHeight(h: number) {
    this.height = Math.max(5, h);
    eventLog.setMaxLines(this.height - 1); // -1 for the header line
  }

  invalidate() {}

  render(width: number): string[] {
    const leftW  = Math.floor(width * 0.58);
    const rightW = width - leftW - 1;

    const leftLines  = eventLog.render(leftW);
    const rightLines = statePanel.render(rightW);

    const out: string[] = [];
    for (let i = 0; i < this.height; i++) {
      const lRaw = leftLines[i] ?? "";
      const vis  = lRaw.replace(/\x1b\[[0-9;]*m/g, "");
      const pad  = " ".repeat(Math.max(0, leftW - vis.length));
      out.push(lRaw + pad + chalk.dim("│") + (rightLines[i] ?? ""));
    }
    return out;
  }
}

const splitPanel = new SplitPanel();

// ── TUI setup ─────────────────────────────────────────────────────────────────
const terminal = new ProcessTerminal();
const tui = new TUI(terminal);

function recalcLayout() {
  const rows = tui.terminal.rows || 40;
  splitPanel.setHeight(Math.max(8, rows - CHROME_LINES));
  tui.requestRender();
}

// Build layout
tui.addChild(headerBar);
tui.addChild(new Text(chalk.dim("─".repeat(200))));
tui.addChild(splitPanel);
tui.addChild(new Text(chalk.dim("─".repeat(200))));
tui.addChild(quickActions);
tui.addChild(guardrailPanel);
tui.addChild(composer);

tui.setFocus(composer);
recalcLayout();

// Recompute on terminal resize
const resizeInterval = setInterval(recalcLayout, 500);

// ── Input handling ────────────────────────────────────────────────────────────
composer.onSubmit = (val) => {
  composer.setValue("");
  handleUserCommand(val);
  tui.requestRender();
};

composer.onEscape = () => {
  composer.setValue("");
  tui.requestRender();
};

tui.addInputListener((data) => {
  if (guardrailPanel.hasPending()) {
    guardrailPanel.handleInput(data);
    tui.requestRender();
    return { consume: true };
  }

  const keyMap: Record<string, string> = {
    w: "wifi on", c: "wifi connect auto", s: "wifi switch",
    b: "wifi bt", g: "glider", x: "stop", "?": "help",
  };

  if (data === "G") {
    guardrailOn = !guardrailOn;
    headerBar.update(protocolState, guardrailOn);
    tui.requestRender();
    return { consume: true };
  }
  if (data === "q") {
    sendCmd("quit");
    clearInterval(resizeInterval);
    eventLog.destroy();
    setTimeout(() => { glassesProc.stop(); tui.stop(); process.exit(0); }, 600);
    return { consume: true };
  }
  if (keyMap[data]) {
    handleUserCommand(keyMap[data]);
    return { consume: true };
  }
  return undefined;
});

guardrailPanel.onAllow = (cmd) => { tui.setFocus(composer); sendCmd(cmd); tui.requestRender(); };
guardrailPanel.onSkip  = ()    => { tui.setFocus(composer); tui.requestRender(); };

// Invalidation callback from EventLog stats flush
eventLog.onInvalidate = () => tui.requestRender();

// ── Event tailing ─────────────────────────────────────────────────────────────
tailEvents(EVENTS_PATH, (e) => {
  protocolState = applyEvent(protocolState, e);
  eventLog.addEvent(e);
  headerBar.update(protocolState, guardrailOn);
  statePanel.update(protocolState);
  // Feed COMPRESS events to statePanel fps tracker
  if (e.type === "COMPRESS") {
    statePanel.recordFrame(e.ts);
  }
  tui.requestRender();
});

// ── Start glasses-tool subprocess ─────────────────────────────────────────────
if (noGlasses) {
  eventLog.addEvent({ ts: Date.now(), type: "LOG", level: "INFO",
    msg: "[no-glasses] dev mode — TUI only" });
} else {
  glassesProc.onStdout = (line) => {
    // Only forward non-frame lines to the event log; frame logs are captured
    // via /tmp/glasses-events.jsonl anyway.
    if (/→ WiFi TX|← WiFi RX|→ BT TX.*GOL|LAYOUT|Compress/.test(line)) return;
    eventLog.addEvent({ ts: Date.now(), type: "LOG", level: "INFO",
      msg: line.replace(/\x1b\[[0-9;]*m/g, "").slice(0, 100) });
    tui.requestRender();
  };
  glassesProc.onStderr = (line) => {
    eventLog.addEvent({ ts: Date.now(), type: "LOG", level: "WARN",
      msg: line.replace(/\x1b\[[0-9;]*m/g, "").slice(0, 100) });
    tui.requestRender();
  };
  glassesProc.onExit = (code) => {
    eventLog.addEvent({ ts: Date.now(), type: "LOG", level: "WARN",
      msg: `glasses-tool exited (code=${code})` });
    tui.requestRender();
  };
  glassesProc.start(false);
}

tui.start();
recalcLayout();
tui.requestRender();
