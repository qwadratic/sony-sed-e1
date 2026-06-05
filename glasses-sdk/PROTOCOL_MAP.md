# Sony SED-E1 — Full Connection Protocol Map

> Reverse-engineered from APK string extraction + SDK source, 2026-06-04.

---

## The short answer to "can we skip to WiFi?"

**No — but close.** WiFi is not a standard AP. The glasses use **WiFi Direct (P2P)**, and the
initial group credentials are exchanged over BT SPP. Once you've sniffed or derived the
passphrase, you can reconnect via WiFi P2P without BT.

---

## Connection transports (4 paths, all in the same codebase)

```
ConnectionControllerHandler
├── BluetoothConnectionController   ← POWER_MODE_NORMAL (default)
├── WifiConnectionController        ← POWER_MODE_HIGH (faster display)
├── USBConnectionController         ← wired (dev mode)
└── LocalSocketConnectionController ← SmartEyeglassEmulator (same-device IPC)
```

All four implement the same interface. The handler switches between them at runtime.

---

## Path 1: Bluetooth SPP

- **Profile**: SPP (Serial Port Profile) — classic RFCOMM
- **BT version**: 3.0, Class 2 (≤2.5mW, ~10m range)
- **Used for**: control commands, sensor data, initial WiFi P2P credential exchange
- **POWER_MODE_NORMAL**: all data goes over BT

BT is always the first connection. Even in WiFi mode, BT stays connected for:
- Sensor data (accelerometer, gyro, magnetometer, light)
- Control intents (display mode, camera trigger, etc.)

---

## Path 2: WiFi Direct (P2P) — NOT a regular WiFi AP

**This is the critical finding.** The glasses do NOT create a normal WiFi access point.
They use **Android WifiP2pManager** (WiFi Direct) where the glasses are the Group Owner (GO).

```
Glasses (Group Owner)
    ↕  WiFi Direct P2P link (802.11g)
Android phone (client)
    ↕  RFCOMM first → then [BtWifi] WifiDPSwitchPathReq → switch to P2P
```

**Key P2P details from strings:**
- `[BtWifi] startGroupOwner` — glasses create the P2P group
- `[BtWifi] WifiDPSwitchPathBTReq` — BT sends "switch to WiFi" request
- `[BtWifi] WifiDPSwitchPathReq %d` — response/ack
- `[BtWifi] onGroupInfoAvailable` — phone gets group credentials (SSID + passphrase)
- `getPassphrase` — passphrase retrieved from group info
- `PKCS5PBKDF2HMACSHA1` — HMAC-SHA1 PBKDF2 for WPA key derivation (standard WPA2 spec)
- `[Wifi] listen port number: %d` — glasses listen on a TCP port over the P2P link

**WiFi P2P SSID format** (typical Sony P2P naming): `DIRECT-XX-SmartEyeglass`  
**Passphrase**: WPA2-PSK, derived via PBKDF2-HMAC-SHA1 from a device secret

**Can you skip BT and go straight to WiFi P2P?**  
Only if you already know:
1. The P2P group SSID (visible via WiFi scan once glasses are powered on)
2. The passphrase (requires BT once, then can cache it)
3. The TCP port number the glasses listen on (sniff once)

If the passphrase is derived from the glasses' BT MAC address (fixed hardware value),
it's always the same — and you only need BT once to learn the derivation.

---

## Path 3: USB Serial

- `USBConnectionController` — full USB serial path
- Likely for factory/development use
- Same protocol over a different transport

---

## Path 4: Local UNIX Domain Sockets (SmartEyeglassEmulator)

**This is how the emulator works:**

```
SmartEyeglassEmulator app
    ↕  UNIX domain socket  (Android abstract namespace)
com.sony.smarteyeglass (MisiAha)
    ↕  BT/WiFi/USB
Physical glasses
```

Named sockets (from strings):
- `com.sony.smarteyeglass.MONITOR_SOCKET` — control/status channel
- `EXTRA_SENSOR_LOCAL_SERVER_SOCKET_NAME` — sensor data stream
- `EXTRA_AR_ANIMATION_SOCKET_NAME` — AR animation objects
- `EXTRA_CAMERA_VIDEO_SOCKET_NAME` — camera JPEG stream

**Implication**: ADB port forwarding can expose these sockets to macOS:
```bash
adb forward tcp:7001 localabstract:com.sony.smarteyeglass.MONITOR_SOCKET
```
Then macOS can speak the same protocol the emulator uses — **without needing BT at all**.
This only works when a real Android phone + glasses is connected and the host APK is running.

---

## NFC — what's actually in the tag

From `NFCBluetoothParing.java`, `NFC_CONNECT`, `android.nfc.action.NDEF_DISCOVERED`:
- NFC triggers **Bluetooth pairing** only (not WiFi credentials)
- The NDEF record contains the glasses' **BT MAC address**
- Phone reads MAC → initiates BT SPP connection
- States: `NFC_CONNECT`, `NFC_SUCCESS`, `NFC_ERROR`

**NFC does NOT contain WiFi credentials.** It's a BT bootstrap shortcut.

---

## macOS / iOS feasibility

### macOS

| Transport | Feasibility | How |
|-----------|-------------|-----|
| BT SPP | ✅ | `IOBluetooth.framework`, RFCOMM channel to glasses MAC |
| WiFi P2P | ⚠️ | macOS supports WFD client mode via `NetworkExtension` — but restricted APIs |
| ADB socket bridge | ✅ Easiest | `adb forward`, then TCP socket on macOS |
| USB | ✅ | `IOKit` USB serial, but requires dev hardware |

**Recommended macOS path:**  
`ADB socket bridge` (if always tethered) or `BT SPP + WiFi P2P`.

### iOS

| Transport | Feasibility | How |
|-----------|-------------|-----|
| BT Classic (SPP) | ❌ | Blocked by Apple. Only BLE exposed to apps. MFi required. |
| WiFi P2P | ❌ | `MultipeerConnectivity` is Apple-proprietary P2P, not WiFi Direct |
| Network bridge via Android | ✅ | Companion Android app bridges to iOS via BLE or TCP/IP |

**iOS is not directly feasible** without jailbreak or MFi certification.

---

## What to reverse-engineer next

### Option A: BT SPP init sequence (simplest)
1. Enable HCI snoop: `adb shell setprop bluetooth.btsnoopenable true`
2. Connect glasses to real Android 7 phone
3. Do actions (display push, camera trigger)
4. Pull log: `adb pull /sdcard/btsnoop_hci.log`
5. Open in Wireshark → filter RFCOMM → see binary protocol
6. Implement in macOS `IOBluetooth.framework`

### Option B: Local socket protocol (fastest for macOS bridge)
1. Root or use Frida to hook `LocalSocketConnectionController`
2. Log all bytes on `com.sony.smarteyeglass.MONITOR_SOCKET`
3. The emulator already speaks this protocol — just forward via ADB
4. No BT RE needed

### Option C: WiFi P2P passphrase derivation
1. Connect via BT once, log `passphrase=` string from logcat
2. Check if it correlates with BT MAC or serial number
3. If deterministic: can reconnect via WiFi P2P without BT permanently

---

## Frida hooks needed

```javascript
// Hook LocalSocketConnectionController to log all bytes
Java.perform(function() {
    var LSC = Java.use('com.sonyericsson.j2.connection.LocalSocketConnectionController');
    
    // Hook write
    LSC.writeToConnection.overload('[B', 'int', 'int').implementation = function(buf, offset, len) {
        console.log('[WRITE] ' + bytesToHex(buf, offset, len));
        return this.writeToConnection(buf, offset, len);
    };
    
    // Hook read  
    LSC.readFromConnection.overload('[B', 'int', 'int').implementation = function(buf, offset, len) {
        var result = this.readFromConnection(buf, offset, len);
        console.log('[READ] ' + bytesToHex(buf, offset, result));
        return result;
    };
});
```

---

## The WiFi skip — bottom line

```
Power on glasses
    ↓
Glasses create WiFi Direct group (SSID: DIRECT-XX-SmartEyeglass)
    ↓ (passphrase is fixed per device, derived from hardware ID)
BT SPP connect (just to get passphrase IF unknown)
    ↓
[BtWifi] WifiDPSwitchPathReq  ← tell glasses to expect WiFi client
    ↓
Connect to glasses' WiFi P2P group (SSID + passphrase)
    ↓
TCP connect to glasses' listen port (unknown — must sniff)
    ↓
Same binary protocol, but over TCP instead of RFCOMM
```

**If we sniff the TCP port number and determine that passphrase is deterministic:**  
→ Power on glasses  
→ Scan WiFi for `DIRECT-XX-SmartEyeglass`  
→ Connect with derived passphrase  
→ TCP connect to port XXXX  
→ Push display data  
**BT never needed again.**

The WiFi P2P group is likely created immediately on power-on (glasses are always the Group Owner),
so the SSID is scannable without BT. The question is only the passphrase derivation.
