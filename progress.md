# WiFi ConnectReq (0x94) Payload Research — COMPLETE

## Status: ✅ DEFINITIVE FINDINGS from DEX bytecode disassembly

Research method: Full DEX class analysis + constructor disassembly of `WifiConnectReq.java`
from the SmartEyeglassEmulator APK (`com.sonyericsson.j2.commands.WifiConnectReq`).

---

## 1. EXACT 184-Byte Payload Layout (from DEX bytecode)

```
Offset  Size  Field         Java Type       Required  Notes
──────  ────  ────────────  ──────────────  ────────  ─────────────────────────────────
0x00    32    SSID          String.getBytes  yes      UTF-8 bytes, length = strlen, rest = 0
0x20    32    passphrase    String.getBytes  yes      UTF-8 bytes, length = strlen, rest = 0
0x40    32    (reserved)    —                —        ALWAYS ZEROS (no code writes here)
0x60    4     goAddr        Inet4Address     no       Group Owner IP (optional, 0 if null)
0x64    4     staAddr       Inet4Address     YES      Station/host IP — TCP target address
0x68    4     subnetMask    Inet4Address     yes      e.g. 255.255.255.0
0x6C    4     gateway       Inet4Address     no       Router gateway (optional, 0 if null)
0x70    4     dnsServer     Inet4Address     no       DNS server (optional, 0 if null)
0x74    2     freq          short (BE)       yes      WiFi channel frequency in MHz
0x76    2     port          short (BE)       yes      TCP server port (port & 0xFFFF)
0x78    64    psk           String.getBytes  yes      PBKDF2 result as 64-char hex string
──────  ────
TOTAL   184 (0xB8)
```

Wire frame: `[0x94][0x00][0xB8][184 payload bytes]` = 187 bytes total.

## 2. 🔴 CRITICAL BUG in Swift `buildWifiConnectReq()`

**The Mac's IP address is in the WRONG field.**

| What | Java (correct) | Swift (buggy) |
|------|---------------|---------------|
| Mac IP (TCP server) | offset 0x64 (`staAddr`) | offset 0x60 (`goAddr`) |
| offset 0x64 | **REQUIRED** field | left as zeros |

The Java constructor **throws IllegalArgumentException("must set sta address")** if `staAddr` is null.
The `toString()` stores `staAddr.toString()` as `mIPAddress` — confirming `staAddr` is the TCP target.
Debug format string in APK: `$ssid:%s, freq:%d, ipAddr:%s, port:%d` where `ipAddr` = `staAddr`.

**Fix**: Move Mac IP from offset 0x60 to 0x64. Set 0x60 to 0.0.0.0 (or router IP for infrastructure).

## 3. Java Class Structure (from DEX)

```java
class WifiConnectReq extends Command {
    // Command base: byte[] data, int id (=0x94), int length (=184)
    
    // Instance fields (for toString display only):
    private short  mFreq;       // channel MHz
    private String mIPAddress;  // = staAddr.toString()
    private int    mPortNum;    // TCP port
    private String mSSID;       // SSID
    
    // Constructor (10 params):
    WifiConnectReq(
        String ssid,               // → data[0x00]
        String passphrase,         // → data[0x20]
        String psk,                // → data[0x78] (hex string)
        Inet4Address goAddr,       // → data[0x60] (nullable)
        Inet4Address staAddr,      // → data[0x64] (REQUIRED)
        Inet4Address subnetMask,   // → data[0x68]
        Inet4Address gateway,      // → data[0x6C] (nullable)
        Inet4Address dnsServer,    // → data[0x70] (nullable)
        short freq,                // → data[0x74] (BE)
        int port                   // → data[0x76] (BE, masked 0xFFFF)
    )
    
    // Second constructor for deserialization:
    WifiConnectReq(byte[] rawPayload)
}
```

## 4. Key Answers to Research Questions

### Q: Is PSK sent as raw 32 bytes or 64-char hex string?
**A: 64-char hex string** at offset 0x78. The Java code does `psk.getBytes()` on the hex string
parameter. Offset 0x40-0x5F is ALWAYS ZEROS (confirmed by bytecode — no writes to that region).

### Q: What is the EXACT offset for IP, port, channel?
- **staAddr (TCP target IP)**: offset 0x64 (4 bytes, big-endian network order)
- **goAddr (glasses GO IP)**: offset 0x60 (4 bytes, optional)
- **port**: offset 0x76 (2 bytes, big-endian)
- **channel/freq**: offset 0x74 (2 bytes, big-endian, MHz)

### Q: WiFi Direct or infrastructure mode?
**Both supported.** The emulator APK has NO Android WiFi P2P APIs (`WifiP2pManager` etc.) —
all WiFi control is at wire-protocol level. The glasses firmware handles WiFi internally.
- `goAddr` = glasses' own IP when acting as WiFi Direct GO (optional, zero for infrastructure)
- `staAddr` = host's IP = TCP server address (REQUIRED)
- In infrastructure mode: goAddr=0.0.0.0, staAddr=host IP

### Q: What frequency/channel format?
**MHz as big-endian short.** Examples: ch1=2412, ch6=2437, ch11=2462.
The Swift `detectWifiChannel()` already computes this correctly.

### Q: Is the subnet mask correct (255.255.255.0)?
**Yes, 255.255.255.0 is fine** for typical home networks. Java passes it as Inet4Address.

## 5. All Issues in Current Swift Code

### 🔴 P0: IP in wrong field (WILL prevent WiFi from working)
```swift
// CURRENT (WRONG):
for i in 0..<4 { payload[0x60 + i] = octets[i] }  // puts Mac IP in goAddr

// CORRECT:
for i in 0..<4 { payload[0x64 + i] = octets[i] }  // put Mac IP in staAddr
// leave 0x60 as zeros (or set to router IP)
```

### ⚠️ P1: gateway and dnsServer are zeros
The Java code passes these as optional params. For infrastructure mode, setting the
actual gateway/DNS may help the glasses' WiFi stack resolve connectivity faster.
Get from: `netstat -rn | awk '/default/{print $2}'` or `scutil --dns`.

### ℹ️ P2: goAddr should be explicitly zero for infrastructure mode
Currently contains Mac IP (wrong). Should be 0.0.0.0 for infrastructure mode,
or the glasses' desired GO IP for WiFi Direct mode.

## 6. Recommended Fix (WifiSubsystem.swift `buildWifiConnectReq`)

```swift
internal func buildWifiConnectReq(ssid: String, passphrase: String, psk: String,
                                   goIP: String, port: Int, channelMHz: Int) -> [UInt8] {
    var payload = [UInt8](repeating: 0, count: 184)
    
    // 0x00: SSID (up to 32 bytes)
    let ssidB = Array(ssid.utf8.prefix(32))
    for i in 0..<ssidB.count { payload[i] = ssidB[i] }
    
    // 0x20: passphrase (up to 32 bytes)
    let passB = Array(passphrase.utf8.prefix(32))
    for i in 0..<passB.count { payload[0x20 + i] = passB[i] }
    
    // 0x40: reserved — leave as zeros (confirmed by DEX: nothing written here)
    
    // 0x60: goAddr — leave as zeros for infrastructure mode
    //   (In WiFi Direct mode, this would be the glasses' GO IP)
    
    // 0x64: staAddr — REQUIRED: our Mac IP (TCP server address)
    let octets = goIP.split(separator: ".").compactMap { UInt8($0) }
    guard octets.count == 4 else { return [] }
    for i in 0..<4 { payload[0x64 + i] = octets[i] }
    
    // 0x68: subnetMask
    payload[0x68] = 255; payload[0x69] = 255; payload[0x6A] = 255; payload[0x6B] = 0
    
    // 0x6C: gateway — optional, fill if available
    // 0x70: dnsServer — optional, fill if available
    
    // 0x74: channel frequency (MHz, big-endian)
    payload[0x74] = UInt8((channelMHz >> 8) & 0xFF)
    payload[0x75] = UInt8(channelMHz & 0xFF)
    
    // 0x76: TCP server port (big-endian)
    payload[0x76] = UInt8((port >> 8) & 0xFF)
    payload[0x77] = UInt8(port & 0xFF)
    
    // 0x78: PSK hex string (64 chars)
    let pskB = Array(psk.utf8.prefix(64))
    for i in 0..<pskB.count { payload[0x78 + i] = pskB[i] }
    
    return [0x94, 0x00, 0xB8] + payload
}
```

## 7. Files That Need Changes

1. **`seg-swift/SEGKit/Sources/SEGKit/WifiSubsystem.swift`** lines 117-135 (`buildWifiConnectReq`)
   - Move IP from offset 0x60 to 0x64
   - Optionally fill gateway (0x6C) and DNS (0x70)
   - Rename `goIP` parameter to `hostIP` or `serverIP` for clarity

2. **`ARCHITECTURE_MODERN.md`** lines 1711-1716
   - Update payload field names: `goAddr` → `goAddr (opt)`, `staAddr` → `staAddr (REQ)`
   - Note that 0x40-0x5F is confirmed zeros

## 8. Evidence Chain

| Source | Finding |
|--------|---------|
| DEX class def | WifiConnectReq has 4 instance fields + extends Command(byte[] data) |
| DEX constructor params | 10 params: 3 String + 5 Inet4Address + short + int |
| DEX bytecode 0x0004 | `super(0x94, 184)` — confirms cmd=0x94, len=184 |
| DEX bytecode 0x0009 | `Arrays.fill(data, 0)` — entire buffer zeroed |
| DEX bytecode 0x0019 | `arraycopy(ssid, 0, data, 0, len)` — SSID at 0x00 |
| DEX bytecode 0x0029 | `arraycopy(pass, 0, data, 32, len)` — pass at 0x20 |
| DEX bytecode 0x0031 | `ByteBuffer.wrap(data, 96, 88)` — BB starts at 0x60 |
| DEX bytecode 0x003e | `bb.put(goAddr.getAddress())` — goAddr at 0x60 |
| DEX bytecode 0x0047 | `bb.put(staAddr.getAddress())` — staAddr at 0x64 |
| DEX bytecode 0x009b | `throw IAE("must set sta address")` — staAddr required |
| DEX bytecode 0x0069 | `bb.putShort(freq)` — freq at 0x74 |
| DEX bytecode 0x0072 | `bb.putShort(port & 0xFFFF)` — port at 0x76 |
| DEX bytecode 0x0079 | `bb.put(psk.getBytes())` — PSK hex at 0x78 |
| DEX bytecode 0x0084 | `mIPAddress = staAddr.toString()` — TCP target = staAddr |
| DEX string table | `$ssid:%s, freq:%d, ipAddr:%s, port:%d` — confirms field semantics |
| DEX string table | `"must set sta address"` — staAddr is required |
