# Project Status

## What Works ✅

| Feature | Status | Notes |
|---------|--------|-------|
| BT RFCOMM connection | ✅ Solid | Channel 4 (SPP), auto-reconnect, device picker with RSSI |
| Handshake FSM | ✅ Complete | ProtocolVersion → Settings → Version → FOTA → OpenApp → ready |
| Display rendering | ✅ Working | 419×138 grayscale, DEFLATE compression, ~2fps animation |
| Camera still capture | ✅ Working | QVGA JPEG over BT, 169KB captures verified |
| Input events | ✅ Working | Tap, long press, swipe L/R, jog CW/CCW, back/camera/PTT buttons |
| Sensor: Battery | ✅ Streaming | ~100ms interval, level in percentage |
| Onboarding flow | ✅ Working | Pi logo, swipe-to-move, 3-tap gate |
| Event logging | ✅ Persistent | ~/.seg-logs/seg-events-\<ISO\>.jsonl |
| Debug wire logging | ✅ Working | --debug flag, TX/RX hex dumps with named commands |

## Partially Working ⚠️

| Feature | Status | Issue |
|---------|--------|-------|
| Camera streaming | ⚠️ BT only captures 1 frame | BT bandwidth too low for continuous JPEG. Needs WiFi TCP transport. |
| WiFi upgrade | ⚠️ Glasses join network but... | See WiFi section below |
| IMU sensors (accel/gyro/mag) | ⚠️ Commands sent, data format verified | Sensor ACK implemented. Needs HW re-verification — was working in earlier sessions. |
| Camera mode enum | ⚠️ Fixed in code | streamLow=2, streamHigh=3 now correct. Untested over WiFi. |

## Not Implemented ❌

| Feature | Complexity | Notes |
|---------|-----------|-------|
| AR rendering | Large (~800 lines) | 0xc3 mode switch, 0xc4 register, 0xc6/0xc7 bitmap exchange, cylindrical coordinates |
| Partial display updates | Small | x,y offset in display command |
| Screen depth control | Small | -4 to 6 range |
| Display callbacks | Small | Transaction number ACK |
| Safe display mode | Small | Bottom-half-only rendering |
| Layer transitions | Medium | moveLowerLayer / moveUpperLayer |
| Double/triple tap | Small | Tap count from 0xe5 payload |
| Swipe up/down | Small | Wire codes unknown (device may not support) |
| Pause/resume lifecycle | Small | displayOff → pause, displayOn → resume |
| Screen state control | Small | 0x3d on/off/dim/auto |
| Sensor accuracy tracking | Small | First 4 bytes of sensor payload |
| Sensor rate control | Small | Rate byte in 0x38 SensorStart |
| Rotation vector fix | Small | 0xbb → currently calls wrong handler |
| Sound effects | Small | Controller beep on/off |
| Standby mode | Small | Low-power sleep mode |
| Telephony | Small | BT headset enable/disable |
| Voice text input | Medium | Speech-to-text |
| Dialog system | Medium | Timeout/OK/custom dialogs |
| LED/vibrate control | Small | Hardware control |
| Clean disconnect | Small | 0x33 OpenAppStopRequest |
| Ping/pong | Small | 0x05 keepalive response |

## WiFi Status — Latest Findings

WiFi upgrade is the critical path for camera streaming. Current state:

### What works
- WiFi radio turns on (`0x92` → `0x91` ENABLED)
- ConnectReq sends correctly (`0x94` with SSID, passphrase, PSK, IP, port, freq)
- Glasses report CONNECTING (`0x95 02`)
- TCP server binds and listens
- **Once**: glasses joined WiFi, got IP (172.20.10.3), pinged successfully

### What doesn't work reliably
- Glasses often stay at `CONNECTING (02)` and never reach `CONNECTED (03)`
- TCP connection established once but dropped immediately
- After failed WiFi attempt, BT RFCOMM becomes unstable (requires power cycle)

### What we know
- **2.4GHz only** — glasses WiFi is 802.11b/g/n, no 5GHz
- **WPA2/WPA3 transition mode fails** — mesh routers with WPA3 rejected
- **iPhone Personal Hotspot** — glasses got `95 02` but never authenticated
- **Open network (SQUER Guest)** — same `95 02` stuck behavior
- **PSK derivation**: PBKDF2-HMAC-SHA1(passphrase, SSID, 4096, 32) → 64-char hex string
- **Payload**: staAddr at offset 0x64, goAddr at 0x60 (IP at both for safety)
- **freq=0 doesn't work** — must send actual 2.4GHz channel frequency

### Bugs found and fixed during WiFi debugging
1. `staAddr` was at wrong offset (0x60 instead of 0x64) — glasses couldn't find TCP target
2. `0x95` handler never updated `wifi.state` — upgrade timed out even when glasses connected
3. 5GHz channel sent to 2.4GHz-only glasses
4. Empty passphrase derived bogus PSK for open networks
5. Channel detection returned wrong frequency for 5GHz channels

### Remaining theories
- Glasses firmware may require specific WPA2-PSK (not WPA2/WPA3 transition)
- PSK might need raw 32 bytes instead of 64-char hex string in some modes
- Sony's original flow uses WiFi Direct (P2P) where glasses are Group Owner — infrastructure mode may have quirks
- The one successful TCP connection suggests the mechanism works, but timing/auth is fragile

## Strange Behaviors Observed

### Blinking square on display
During WiFi connection attempts, a small rectangle blinks in the bottom-left corner of the glasses display. This appears to be a firmware WiFi activity indicator. It persists until WiFi is disabled or glasses are power-cycled.

### RFCOMM instability after WiFi
After a failed WiFi upgrade, the BT RFCOMM connection becomes unreliable:
- Channel opens, gets ProtocolVersion (0x0a), then immediately closes
- Reconnect loop: open → ProtocolVersion → close → open → repeat
- Only resolved by full power cycle (10s hold)
- Even macOS BT reset (`blueutil --power 0/1`) doesn't always fix it

### Display auto-sleep
Display turns off after ~10 seconds of no new frames. Touch sensor tap wakes it. The `displayOff` (0x0d) and `displayOn` (0x0e) events are sent via `0xe5 LayoutEventNotify`.

### Input event byte offset
`0xe5` LayoutEventNotify payload has a leading zero byte: `[00][eventType][00][00]`. The event type is at `payload[1]`, not `payload[0]`. This was a bug in our parser that caused all touch/button events to map to `unknown(0x00)`.

## Firmware Notes

### Version
Firmware version string: `01.001.15041001` (returned via `0x08` VersionResponse).

### FOTA (Firmware Over The Air)
- `0x81` FotaStatus arrives during handshake — just a gate, not an update mechanism
- We send `0x85 [0,0,0,0]` = "no bundled firmware"
- Full FOTA protocol exists in DEX bytecode: `FotaRecipe`, `FotaImageReq`, `FotaImageRes`, `FotaFwUpdate`, `FotaReboot`
- **`ENTER_DFU_MODE`** command exists — puts glasses in bootloader. DANGEROUS without matching firmware image.
- Potentially exploitable for custom firmware, but high brick risk
- We have 4 devices to experiment with

### Firmware Initialize Function
In the glasses' built-in menu (accessible when BT pairing fails):
- Back button + jog wheel navigation reveals system menu
- Contains "Initialize" function — purpose unknown, possibly factory reset
- Not yet tested

### NFC Pairing
- Glasses have NFC chip for quick pairing
- Tap with phone → reads URI: `semc://liveware/B1/6/SmartEyeglass/AC:9B:0A:37:A6:XX/BAEf`
- Contains: protocol version (B1), device model (SmartEyeglass), BT MAC address, auth bytes
- Could enable smooth one-tap pairing flow for the SDK

## APK Versions

Two versions exist on APKMirror:
- [com.sony.smarteyeglass](https://www.apkmirror.com/apk/sony-semiconductor-solutions-corporation/smarteyeglass/) — HostApp
- The reference Java code at [github.com/kaustubhcs/Sony](https://github.com/kaustubhcs/Sony) may correspond to either version
- We decompiled `SmartEyeglassEmulator.apk` from the SDK — it contains the full `com.sonyericsson.j2.*` wire protocol layer with 80+ COMMAND_* constants
