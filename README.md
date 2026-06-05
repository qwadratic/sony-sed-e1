# Sony SmartEyeglass SED-E1 — macOS toolkit

Drive Sony SED-E1 AR glasses from macOS via Bluetooth and WiFi. No Android required.

**Display**: 419×138 green monochrome. **Working**: BT connection, display rendering, glider animation, WiFi path.

---

## Files

```
macos-middleware/glasses-tool.swift   single-file Swift CLI — the whole thing
macos-middleware/glasses.conf.example config template
macos-middleware/glasses-wifi-setup.sh macOS hotspot setup (sudo, optional)
glasses-sdk/PROTOCOL_MAP.md          full reverse-engineered wire protocol
```

---

## Build & run

```bash
cd macos-middleware
swiftc glasses-tool.swift -framework IOBluetooth -framework Foundation -o glasses-tool -O
cp glasses.conf.example glasses.conf   # edit if needed
./glasses-tool                         # scans for glasses, pick one, connects
```

Requires macOS + Xcode command-line tools. No other dependencies.

---

## REPL (after connect)

```
glider          start glider animation (~2.5 fps over BT)
stop            stop demo
wifi setup      step-by-step WiFi upgrade (30 fps)
wifi on         enable glasses WiFi radio
wifi connect auto   connect using .env credentials + auto IP
wifi switch     move display to WiFi — 30 fps glider starts
help            all commands
quit            disconnect
```

WiFi credentials: create `macos-middleware/.env`:
```
SSID=YourNetwork
PSWD=YourPassword
```

---

## Protocol essentials

See [`glasses-sdk/PROTOCOL_MAP.md`](glasses-sdk/PROTOCOL_MAP.md) for the full spec.

Key facts:
- Frame format: `[cmdId:1B][len:2B big-endian][payload]`
- **SyncResponse (0xFF) after FotaStatus is mandatory** — without it glasses ignore all commands
- **LayoutInit x/y are scroll offsets** not dimensions — use `(0, 0, state=0)`
- Display command: `0xe7` LayoutPlaceRemoveCommand with 8-bit grayscale + raw DEFLATE (`wbits=-15`)
- WiFi: macOS is TCP server, glasses TCP-connect back after receiving `WifiConnectReq (0x94)`
