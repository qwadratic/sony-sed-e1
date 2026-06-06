import type { Component } from "@earendil-works/pi-tui";
import chalk from "chalk";
import type { ProtocolState } from "../state.js";
import { PHASE_NAMES, WIFI_PHASE_NAMES } from "../state.js";

export class ProtocolStatePanel implements Component {
  private state: ProtocolState;
  // Rolling fps from COMPRESS events (timestamps of last N frames)
  private frameTimes: number[] = [];

  constructor(state: ProtocolState) {
    this.state = state;
  }

  update(state: ProtocolState) {
    this.state = state;
  }

  recordFrame(ts: number) {
    this.frameTimes.push(ts);
    const cutoff = ts - 2000; // 2s window
    while (this.frameTimes.length > 0 && this.frameTimes[0] < cutoff) {
      this.frameTimes.shift();
    }
  }

  getFps(): number {
    if (this.frameTimes.length < 2) return 0;
    const span = (this.frameTimes[this.frameTimes.length - 1] - this.frameTimes[0]) / 1000;
    return span > 0 ? (this.frameTimes.length - 1) / span : 0;
  }

  invalidate() {}

  render(width: number): string[] {
    const s = this.state;
    const phaseName = `${s.phase} (${PHASE_NAMES[s.phase] ?? "?"})`;
    const wifiPhaseName = `${s.wifiPhase} (${WIFI_PHASE_NAMES[s.wifiPhase] ?? "?"})`;
    const bt = s.btConnected ? chalk.green("connected ch4") : chalk.dim("—");
    const tcp = s.tcpConnected ? chalk.green("connected") : chalk.dim("—");
    const wifi = s.wifiActive ? chalk.bold.green("ACTIVE") : chalk.dim("off");
    const fps = this.getFps();
    const fpsStr = fps > 0 ? chalk.bold.cyan(`${fps.toFixed(1)} fps`) : chalk.dim("—");
    const avgRatio = s.avgCompressionRatio > 0
      ? chalk.dim(`${(s.avgCompressionRatio * 100).toFixed(2)}%`)
      : chalk.dim("—");

    const rows: Array<[string, string]> = [
      ["Phase",      phaseName],
      ["WiFi phase", wifiPhaseName],
      ["BT",         bt],
      ["TCP",        tcp],
      ["WiFi path",  wifi],
      ["Frames",     s.framesSent > 0 ? chalk.dim(`${s.framesSent} sent`) : chalk.dim("—")],
      ["Fps",        fpsStr],
      ["Compress",   avgRatio],
    ];

    const lines: string[] = [chalk.bold(" PROTOCOL STATE")];
    for (const [label, value] of rows) {
      const lbl = chalk.dim((label + ":").padEnd(12));
      lines.push(` ${lbl} ${value}`);
    }
    return lines;
  }
}
