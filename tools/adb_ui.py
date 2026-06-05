#!/usr/bin/env python3
"""
adb_ui.py — Reliable ADB UI interaction helper.

Fixes every coordinate problem we hit:
  - screencap uses PHYSICAL pixels (always portrait origin)
  - adb input uses LOGICAL pixels (rotated with the app)
  - uiautomator dump uses LOGICAL pixels

Usage:
  from adb_ui import UI
  ui = UI()
  el = ui.find(text="Accept")
  el.tap()
  ui.screenshot("/tmp/out.png")
"""

import subprocess
import re
import xml.etree.ElementTree as ET
import time
from dataclasses import dataclass
from typing import Optional, List

# ── ADB shell helper ────────────────────────────────────────────────────────

def adb(*args, check=True) -> str:
    result = subprocess.run(
        ["adb", "shell"] + list(args),
        capture_output=True, text=True
    )
    return result.stdout.strip()

def adb_raw(*args) -> bytes:
    result = subprocess.run(
        ["adb"] + list(args),
        capture_output=True
    )
    return result.stdout

# ── Screen state ─────────────────────────────────────────────────────────────

@dataclass
class ScreenInfo:
    physical_w: int    # always the narrow side in portrait
    physical_h: int    # always the tall side in portrait
    logical_w: int     # app-visible width (may be swapped when rotated)
    logical_h: int     # app-visible height
    rotation: int      # 0=portrait, 1=landscape-right, 2=upside-down, 3=landscape-left
    density: int

    @property
    def is_landscape(self) -> bool:
        return self.rotation in (1, 3)


def get_screen_info() -> ScreenInfo:
    """Query current screen geometry and rotation."""
    size_out = adb("wm", "size")
    density_out = adb("wm", "density")

    # "Physical size: WxH"
    phys_m = re.search(r"Physical size: (\d+)x(\d+)", size_out)
    phy_w, phy_h = (int(phys_m.group(1)), int(phys_m.group(2))) if phys_m else (1080, 1920)

    density_m = re.search(r"Physical density: (\d+)", density_out)
    density = int(density_m.group(1)) if density_m else 480

    # Get rotation from display dump
    disp_out = adb("dumpsys", "display", "|", "grep", "mDefaultViewport")
    rot_m = re.search(r"orientation=(\d)", disp_out)
    rotation = int(rot_m.group(1)) if rot_m else 0

    if rotation in (1, 3):  # landscape
        log_w, log_h = phy_h, phy_w
    else:
        log_w, log_h = phy_w, phy_h

    return ScreenInfo(phy_w, phy_h, log_w, log_h, rotation, density)


# ── Coordinate translation ───────────────────────────────────────────────────

def logical_to_input(lx: int, ly: int, info: ScreenInfo) -> tuple:
    """
    adb input tap uses logical coordinates.
    This function is mostly a passthrough — logical == input space.
    Kept for documentation / future use.
    """
    return lx, ly


def physical_to_logical(px: int, py: int, info: ScreenInfo) -> tuple:
    """
    Convert screencap pixel coordinates to logical (input) coordinates.
    Needed when you measure positions from a screenshot.
    
    rotation=0 (portrait):  1:1 mapping
    rotation=1 (landscape): lx=py,  ly=physical_w-px
    rotation=3 (landscape): lx=physical_h-py, ly=px
    """
    if info.rotation == 0:
        return px, py
    elif info.rotation == 1:  # 90° CW
        return py, info.physical_w - px
    elif info.rotation == 2:  # 180°
        return info.physical_w - px, info.physical_h - py
    elif info.rotation == 3:  # 90° CCW
        return info.physical_h - py, px
    return px, py


# ── UI element ───────────────────────────────────────────────────────────────

@dataclass
class UIElement:
    text: str
    resource_id: str
    classname: str
    bounds: tuple        # (x1, y1, x2, y2) in LOGICAL coords
    checked: bool
    enabled: bool
    clickable: bool
    _info: ScreenInfo

    @property
    def cx(self) -> int:
        return (self.bounds[0] + self.bounds[2]) // 2

    @property
    def cy(self) -> int:
        return (self.bounds[1] + self.bounds[3]) // 2

    def tap(self, wait: float = 0.5):
        adb("input", "tap", str(self.cx), str(self.cy))
        if wait: time.sleep(wait)

    def long_tap(self, duration_ms: int = 1000):
        adb("input", "swipe", str(self.cx), str(self.cy),
            str(self.cx), str(self.cy), str(duration_ms))

    def type_text(self, text: str):
        escaped = text.replace(" ", "%s").replace("'", "\\'")
        adb("input", "text", escaped)

    def __repr__(self):
        return f"UIElement({self.classname.split('.')[-1]} '{self.text}' at ({self.cx},{self.cy}))"


# ── UIAutomator dump + parsing ───────────────────────────────────────────────

def dump_ui(retries: int = 3) -> str:
    """Dump UI hierarchy, retry on failure."""
    for i in range(retries):
        adb("uiautomator", "dump", "/data/local/tmp/ui_dump.xml")
        time.sleep(0.3)
        xml = adb("cat", "/data/local/tmp/ui_dump.xml")
        if xml and "<hierarchy" in xml:
            return xml
        time.sleep(0.5 * (i + 1))
    raise RuntimeError("uiautomator dump failed after retries")


def parse_bounds(bounds_str: str) -> tuple:
    """Parse '[x1,y1][x2,y2]' → (x1,y1,x2,y2)"""
    nums = list(map(int, re.findall(r"\d+", bounds_str)))
    return tuple(nums)  # (x1, y1, x2, y2)


def parse_elements(xml_str: str, info: ScreenInfo) -> List[UIElement]:
    root = ET.fromstring(xml_str)
    elements = []
    for node in root.iter("node"):
        bounds_str = node.get("bounds", "")
        if not bounds_str:
            continue
        bounds = parse_bounds(bounds_str)
        elements.append(UIElement(
            text=node.get("text", ""),
            resource_id=node.get("resource-id", ""),
            classname=node.get("class", ""),
            bounds=bounds,
            checked=node.get("checked", "false") == "true",
            enabled=node.get("enabled", "true") == "true",
            clickable=node.get("clickable", "false") == "true",
            _info=info,
        ))
    return elements


# ── Main UI class ────────────────────────────────────────────────────────────

class UI:
    def __init__(self, auto_refresh: bool = True):
        self._info = get_screen_info()
        self._elements: List[UIElement] = []
        self._xml: str = ""
        if auto_refresh:
            self.refresh()

    def refresh(self) -> "UI":
        """Re-dump UI hierarchy."""
        self._info = get_screen_info()
        self._xml = dump_ui()
        self._elements = parse_elements(self._xml, self._info)
        return self

    @property
    def screen(self) -> ScreenInfo:
        return self._info

    # ── Finders ──────────────────────────────────────────────────────────────

    def find(self, text: str = "", resource_id: str = "", classname: str = "",
             contains: bool = True) -> Optional[UIElement]:
        """Find first matching element."""
        for el in self._elements:
            if text:
                match = (text.lower() in el.text.lower()) if contains else (text == el.text)
                if not match:
                    continue
            if resource_id and resource_id not in el.resource_id:
                continue
            if classname and classname not in el.classname:
                continue
            return el
        return None

    def find_all(self, text: str = "", resource_id: str = "",
                 classname: str = "") -> List[UIElement]:
        results = []
        for el in self._elements:
            if text and text.lower() not in el.text.lower():
                continue
            if resource_id and resource_id not in el.resource_id:
                continue
            if classname and classname not in el.classname:
                continue
            results.append(el)
        return results

    def wait_for(self, text: str = "", resource_id: str = "",
                 timeout: float = 10.0, poll: float = 0.5) -> Optional[UIElement]:
        """Wait until an element appears."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.refresh()
            el = self.find(text=text, resource_id=resource_id)
            if el:
                return el
            time.sleep(poll)
        return None

    def wait_gone(self, text: str = "", resource_id: str = "",
                  timeout: float = 10.0, poll: float = 0.5) -> bool:
        """Wait until an element disappears."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.refresh()
            if not self.find(text=text, resource_id=resource_id):
                return True
            time.sleep(poll)
        return False

    # ── Actions ───────────────────────────────────────────────────────────────

    def tap(self, lx: int, ly: int, wait: float = 0.3):
        """Tap at logical coordinates."""
        adb("input", "tap", str(lx), str(ly))
        if wait: time.sleep(wait)

    def tap_physical(self, px: int, py: int, wait: float = 0.3):
        """Tap at physical (screencap) coordinates — auto-converts."""
        lx, ly = physical_to_logical(px, py, self._info)
        self.tap(lx, ly, wait)

    def swipe(self, x1: int, y1: int, x2: int, y2: int,
              duration_ms: int = 300, wait: float = 0.3):
        adb("input", "swipe", str(x1), str(y1), str(x2), str(y2), str(duration_ms))
        if wait: time.sleep(wait)

    def swipe_left(self, wait: float = 0.3):
        cx, cy = self._info.logical_w // 2, self._info.logical_h // 2
        self.swipe(cx + 300, cy, cx - 300, cy, wait=wait)

    def swipe_right(self, wait: float = 0.3):
        cx, cy = self._info.logical_w // 2, self._info.logical_h // 2
        self.swipe(cx - 300, cy, cx + 300, cy, wait=wait)

    def press_back(self):
        adb("input", "keyevent", "4")
        time.sleep(0.3)

    def press_home(self):
        adb("input", "keyevent", "3")
        time.sleep(0.3)

    # ── Smart actions ─────────────────────────────────────────────────────────

    def accept_dialog(self, positive_texts=("Accept", "OK", "Yes", "ACCEPT"),
                      checkbox_id="CheckBox") -> bool:
        """
        Handles consent / alert dialogs robustly.
        1. Checks for checkbox and ticks it if needed.
        2. Taps the positive button.
        Returns True if dialog was handled.
        """
        # Find and tick checkbox if present and unchecked
        cb = self.find(classname="CheckBox")
        if cb and not cb.checked:
            cb.tap(wait=0.8)
            self.refresh()

        # Find accept/ok button
        for t in positive_texts:
            btn = self.find(text=t)
            if btn and btn.enabled:
                btn.tap(wait=1.0)
                return True

        return False

    # ── Screenshot ────────────────────────────────────────────────────────────

    def screenshot(self, path: str):
        """
        Take screenshot. Saved at `path` in physical pixel space.
        Use screen.rotation to interpret orientation.
        """
        data = adb_raw("exec-out", "screencap", "-p")
        with open(path, "wb") as f:
            f.write(data)
        return path

    # ── Debug ─────────────────────────────────────────────────────────────────

    def dump(self, filter_text: str = ""):
        """Print all elements, optionally filtered."""
        for el in self._elements:
            if filter_text and filter_text.lower() not in (el.text + el.resource_id).lower():
                continue
            print(f"  {el}")

    def __repr__(self):
        return (f"UI(rotation={self._info.rotation}, "
                f"logical={self._info.logical_w}x{self._info.logical_h}, "
                f"elements={len(self._elements)})")


# ── Convenience scripts ───────────────────────────────────────────────────────

def accept_smart_connect_eula():
    """Accept Smart Connect EULA — works on any screen size/rotation."""
    ui = UI()
    # Wait for dialog
    el = ui.wait_for(text="consent", timeout=15)
    if not el:
        print("EULA dialog not found")
        return False
    success = ui.accept_dialog()
    if success:
        # Tap OK on the welcome screen
        ui2 = UI()
        ok = ui2.find(text="OK")
        if ok: ok.tap(wait=1.0)
    return success


def install_and_accept(apk_path: str, eula_text: str = "consent"):
    """Install APK and handle first-run dialogs."""
    subprocess.run(["adb", "install", "-r", apk_path], check=True)
    time.sleep(2)
    ui = UI()
    el = ui.wait_for(text=eula_text, timeout=8)
    if el:
        ui.accept_dialog()


if __name__ == "__main__":
    import sys
    ui = UI()
    print(ui)
    if len(sys.argv) > 1:
        ui.dump(sys.argv[1])
    else:
        ui.dump()
