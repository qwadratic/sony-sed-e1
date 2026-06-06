import type { Component } from "@earendil-works/pi-tui";
import chalk from "chalk";
import type { GlassesEvent } from "../events.js";

// Commands that fire at 30fps — suppress from log, roll into stats instead
const FRAME_CMDS = new Set(["0xe7", "0xe8"]);

interface FrameStats {
  frames: number;
  acks: number;
  windowStart: number;
  fps: number;
  avgRatio: number;
  ratioSamples: number[];
}

export class EventLog implements Component {
  private entries: string[] = [];
  private maxLines = 20;
  private stats: FrameStats = {
    frames: 0, acks: 0, windowStart: Date.now(),
    fps: 0, avgRatio: 0, ratioSamples: [],
  };
  private statsFlushTimer?: ReturnType<typeof setInterval>;
  public onInvalidate?: () => void;

  constructor() {
    // Flush frame stats as a single summary line every second
    this.statsFlushTimer = setInterval(() => this.flushStats(), 1000);
  }

  setMaxLines(n: number) {
    this.maxLines = Math.max(5, n);
  }

  private flushStats() {
    const now = Date.now();
    const elapsed = (now - this.stats.windowStart) / 1000;
    if (this.stats.frames === 0) return;

    const fps = this.stats.frames / elapsed;
    const avgRatio = this.stats.ratioSamples.length > 0
      ? this.stats.ratioSamples.reduce((a, b) => a + b, 0) / this.stats.ratioSamples.length
      : 0;
    const ackPct = this.stats.frames > 0
      ? Math.round(this.stats.acks / this.stats.frames * 100)
      : 0;

    const line =
      chalk.dim(`${new Date().toLocaleTimeString("en", { hour12: false })}`) + "  " +
      chalk.bold.cyan(`${fps.toFixed(1)} fps`) +
      chalk.dim("  via ") + (this.stats.frames > 0 ? chalk.green("WiFi") : chalk.yellow("BT")) +
      chalk.dim(`  ${this.stats.frames} frames  ack ${ackPct}%`) +
      (avgRatio > 0
        ? chalk.dim(`  compress ${(avgRatio * 100).toFixed(2)}%`)
        : "");

    this.push(line);
    this.stats = {
      frames: 0, acks: 0, windowStart: now,
      fps: 0, avgRatio: 0, ratioSamples: [],
    };
    this.onInvalidate?.();
  }

  private push(line: string) {
    this.entries.push(line);
    if (this.entries.length > 500) this.entries.shift();
  }

  addEvent(e: GlassesEvent) {
    // Frame flood: accumulate into stats only
    if (e.type === "TX" && FRAME_CMDS.has(e.cmd)) {
      this.stats.frames++;
      return;
    }
    if (e.type === "RX" && FRAME_CMDS.has(e.cmd)) {
      this.stats.acks++;
      return;
    }
    if (e.type === "COMPRESS") {
      this.stats.ratioSamples.push(e.ratio);
      if (this.stats.ratioSamples.length > 100) this.stats.ratioSamples.shift();
      return;
    }

    // Everything else: format and push
    const ts = new Date(e.ts);
    const t = `${String(ts.getMinutes()).padStart(2,"0")}:${String(ts.getSeconds()).padStart(2,"0")}.${String(ts.getMilliseconds()).padStart(3,"0")}`;

    let line: string;
    switch (e.type) {
      case "TX": {
        const ok = e.ok ? chalk.green("✓") : chalk.red("✗");
        const nb = e.bytes < 1024 ? `${e.bytes}B` : `${(e.bytes/1024).toFixed(1)}KB`;
        line = `${chalk.dim(t)} ${chalk.blue("TX")} ${chalk.cyan(e.cmd.padEnd(5))} ${chalk.white(e.name.slice(0,24).padEnd(24))} ${chalk.dim(nb)} ${ok}`;
        break;
      }
      case "RX": {
        const payload = e.payload ? chalk.dim(` ${e.payload.slice(0,12)}`) : "";
        line = `${chalk.dim(t)} ${chalk.green("RX")} ${chalk.cyan(e.cmd.padEnd(5))} ${chalk.white(e.name.slice(0,24).padEnd(24))}${payload}`;
        break;
      }
      case "STATE":
        line = `${chalk.dim(t)} ${chalk.magenta("STATE")} ph=${e.phase} wph=${e.wifi_phase} wifi=${e.wifi_active} tcp=${e.tcp_connected}`;
        break;
      case "WIFI":
        line = `${chalk.dim(t)} ${chalk.yellow("●WIFI ")} ${chalk.bold.yellow(e.event)} state=${e.state}`;
        break;
      case "LOG": {
        if (e.level === "INFO" && e.msg.startsWith("[no-glasses]")) {
          line = `${chalk.dim(t)} ${chalk.dim(e.msg.slice(0, 70))}`;
          break;
        }
        const lvl = e.level === "ERROR" ? chalk.red(e.level)
                  : e.level === "WARN"  ? chalk.yellow(e.level)
                  : chalk.dim(e.level);
        line = `${chalk.dim(t)} ${lvl} ${chalk.dim(e.msg.slice(0, 70))}`;
        break;
      }
      default:
        line = `${chalk.dim(t)} ${chalk.dim(JSON.stringify(e).slice(0, 70))}`;
    }

    this.push(line);
  }

  invalidate() {}

  render(width: number): string[] {
    const header = chalk.bold(" EVENT LOG");
    const visible = this.entries.slice(-this.maxLines);
    // Pad to maxLines so the panel height stays fixed
    const padded: string[] = [header];
    for (let i = 0; i < this.maxLines; i++) {
      padded.push(" " + (visible[i] ?? ""));
    }
    return padded;
  }

  destroy() {
    if (this.statsFlushTimer) clearInterval(this.statsFlushTimer);
  }
}
