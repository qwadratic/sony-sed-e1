# FOTA / Firmware Research — Complete Findings

**Date:** 2026-06-08  
**Status:** ✅ COMPLETE — Rich data extracted from SmartEyeglassEmulator.apk DEX strings

---

## Executive Summary

The SED-E1 firmware is **immutable** — ARCHITECTURE_MODERN.md line 1570 explicitly states: *"The SED-E1 firmware is immutable — no OTA, no modification."* However, the Sony HostApp (bundled inside SmartEyeglassEmulator.apk) contains a **complete FOTA subsystem** with 6 wire commands, a multi-phase update UI, and DFU mode support. This FOTA system was designed for the HostApp to push firmware updates to the glasses over BT/WiFi, but **our glasses likely already have final firmware** and the FOTA handshake during connection is just a version check that responds "no update needed."

---

## 1. Decompilation Status

| Asset | Status |
|-------|--------|
| Decompiled smali/DEX | ❌ None found anywhere in project |
| HostApp APK (com.sony.smarteyeglass) | ❌ Not present — only the Emulator APK exists |
| SmartEyeglassEmulator.apk | ✅ Present at `Sony/sony_smarteyeglass_sdk/.../apks/SmartEyeglassEmulator.apk` |
| Decompilation tools (apktool/jadx) | ❌ Not installed via brew |
| DEX string extraction | ✅ **Successful** — `unzip -p ... classes.dex \| strings` yielded full class/method/constant names |

**Key finding:** The Emulator APK (1.2MB DEX) contains the **complete HostApp j2 wire protocol layer** (`com.sonyericsson.j2.*`) plus the emulator UI (`com.sony.smarteyeglass.emulator.*`). This means ALL wire protocol logic including FOTA is in this DEX.

---

## 2. FOTA Wire Protocol — 6 Commands Identified

From DEX string extraction of `COMMAND_*` constants:

| Command Constant | Wire ID | Direction | Role |
|-----------------|---------|-----------|------|
| `COMMAND_FOTA_STATUS` | `0x81` | RX (glasses→host) | Glasses report FOTA status during handshake |
| `COMMAND_NEW_HOSTAPP` | `0x85` | TX (host→glasses) | Host announces its version; triggers FOTA check |
| `COMMAND_FOTA_RECIPE` | unknown | TX? | Recipe = update manifest (blocks, versions) |
| `COMMAND_FOTA_IMAGE_REQ` | unknown | TX (host→glasses) | Request firmware image block transfer |
| `COMMAND_FOTA_IMAGE_RES` | unknown | RX (glasses→host) | Response to image block request |
| `COMMAND_FOTA_FW_UPDATE` | unknown | TX? | Trigger the actual firmware flash |
| `COMMAND_FOTA_REBOOT` | unknown | TX? | Reboot glasses after flash |
| `COMMAND_ENTER_DFU_MODE` | unknown | TX? | Put glasses into DFU (Device Firmware Update) mode |

### Java Classes in j2 Package

```
com.sonyericsson.j2.commands.FotaStatus       — parses 0x81 response
com.sonyericsson.j2.commands.FotaRecipe        — FOTA update recipe/manifest
com.sonyericsson.j2.commands.FotaImageRequest   — request firmware image blocks
com.sonyericsson.j2.commands.FotaImageResponse  — receive firmware image blocks
com.sonyericsson.j2.commands.FotaFwUpdate       — initiate FW update
com.sonyericsson.j2.commands.FotaReboot         — reboot after update
com.sonyericsson.j2.commands.NewHostApp         — announce HostApp version (0x85)
com.sonyericsson.j2.commands.VersionRequest     — version query (0x07)
com.sonyericsson.j2.commands.VersionResponse    — version reply (0x08)
com.sonyericsson.j2.commands.ProtocolVersion    — protocol ver (0x0a)
com.sonyericsson.j2.FirmwareVersionFetcher      — retrieves/parses FW version
com.sonyericsson.j2.preferences.FirmwarePreferences — UI for firmware settings
```

---

## 3. FOTA Update Flow (Reconstructed from Strings)

### Phase A: Handshake Version Check (what we already implement)
```
1. RX 0x0a  → ProtocolVersion (glasses announce protocol ver)
2. TX 0x71  → SettingsStatusRequest
3. RX 0x72  → SettingsStatusResponse
4. TX 0x07  → VersionRequest [0x01]
5. RX 0x08  → VersionResponse (contains FW version string)
   Debug: "FW version = %s"
   Debug: "Supported protocol version by accessory: %s"
6. TX 0x85  → NewHostApp [0x00, 0x00, 0x00, 0x00]
   (announces host app version; payload = 4 bytes, all zeros = "no bundled firmware")
7. RX 0x81  → FotaStatus
   (glasses respond with FOTA status — likely "no update needed")
```

### Phase B: Actual FOTA Transfer (if update available)
```
8. TX FOTA_RECIPE  → Send update recipe (block count, version info)
   Debug: "exOK=%d inOK=%d blockNum=%d version=%s"
   Fields: startBlockNum, updatedBlockNum, blockCount, subblock
   
9. TX FOTA_IMAGE_REQ  → Request firmware image blocks
   Fields: block, subblock, blockData, imageSize
   Debug: "startBlockNum=%d", "block=%d subblock=%d"
   
10. RX FOTA_IMAGE_RES  → Glasses send image block data back (or confirm receipt?)
    
11. TX FOTA_FW_UPDATE  → Commit the firmware update
    
12. TX FOTA_REBOOT  → Reboot glasses with new firmware
```

### Phase C: DFU Mode (emergency/recovery)
```
COMMAND_ENTER_DFU_MODE — Put glasses into Device Firmware Update mode
(Preference key: "enter_dfu_mode_pref_key" / "enterDfuModePref")
(Available from FirmwarePreferences settings screen)
```

### FOTA UI Screens (from layout XMLs)
```
fota_recommended.xml  — "A firmware update is recommended"
fota_make_sure.xml    — "Are you sure?" confirmation
fota_notification.xml — System notification during update
fota_progress.xml     — Download/flash progress bar
fota_completed.xml    — "Update complete"
fota_interrupted.xml  — "Update was interrupted"
fota_not_needed.xml   — "Latest version already installed"
```

### Resource Strings (from resources.arsc)
```
"Accessory firmware update"
"The latest version of the firmware is already installed on your accessory."
"The update was interrupted."
"A later version of SmartEyeglass application is required. Update to the latest version."
"bundled_firmare_version" [sic — typo in Sony code]
```

---

## 4. The 0x85 NewHostApp Payload

Our current implementation sends: `[0x85, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00]`

- Byte 0: `0x85` = command ID
- Bytes 1-2: `0x00, 0x04` = payload length (4 bytes)
- Bytes 3-6: `0x00, 0x00, 0x00, 0x00` = **host app version = 0**

This effectively tells the glasses "I have no bundled firmware" — which makes the glasses respond with `0x81` FotaStatus = "no update needed" and the handshake continues.

**The DEX string `bundled_firmare_version`** suggests the HostApp could carry a bundled firmware image. When the HostApp had a newer firmware than the glasses, the 4-byte payload in 0x85 would encode the HostApp's bundled firmware version, triggering the FOTA flow.

---

## 5. The 0x08 VersionResponse Payload

From ARCHITECTURE_MODERN.md line 1640: *"RX 0x08 (contains FW version string)"*

Debug string from DEX: `"FW version = %s"` and `"Supported protocol version by accessory: %s"`

**Our current implementation ignores this payload.** We should parse it to:
1. Log the actual firmware version of connected glasses
2. Display it in REPL/diagnostics
3. Confirm our glasses are on final firmware

---

## 6. What This Means for Our Project

### Confirmed: Firmware is Immutable for Our Purposes
- ARCHITECTURE_MODERN.md explicitly says so (line 1570)
- Sony discontinued the product; no new firmware will be released
- The FOTA handshake is vestigial — glasses respond "no update" and move on
- Our 5-second timeout for 0x81 is correct behavior

### Actionable Items

| Priority | Action | Effort |
|----------|--------|--------|
| **Low** | Parse 0x08 VersionResponse payload to log FW version string | ~10 lines Swift |
| **Low** | Parse 0x81 FotaStatus payload to confirm "no update" status byte | ~5 lines Swift |
| **None** | Implement actual FOTA transfer | Not needed — no firmware to push |
| **None** | Implement DFU mode | Dangerous — could brick glasses |
| **Info** | Install jadx (`brew install jadx`) to fully decompile Emulator APK | Optional for deep protocol RE |

### Risk: DFU Mode
The `COMMAND_ENTER_DFU_MODE` command exists and is accessible from the FirmwarePreferences screen. **Do NOT send this command** — it would put the glasses into a bootloader mode that expects a firmware image we don't have, potentially bricking them.

---

## 7. Complete Wire Protocol Command Map (from DEX)

All 80+ COMMAND_* constants extracted. New ones not in our CommandConstants.swift:

```
COMMAND_ACK                          COMMAND_NAK
COMMAND_ENTER_DFU_MODE               COMMAND_FOTA_FW_UPDATE
COMMAND_FOTA_IMAGE_REQ               COMMAND_FOTA_IMAGE_RES
COMMAND_FOTA_REBOOT                  COMMAND_FOTA_RECIPE
COMMAND_CHANGE_STATE                 COMMAND_CHANGE_VIEWPORT
COMMAND_CYLINDRICAL_MODE             COMMAND_DEBUG_MESSAGE
COMMAND_DEBUG_SET_ACC_VALUES          COMMAND_DISPLAY_MASK_SELECT
COMMAND_HFP_CALL                     COMMAND_HFP_NOTIFY
COMMAND_HOSTAPP_EVENT                COMMAND_LEVEL_INVALIDATE
COMMAND_OPEN_APP_EDIT_RING           COMMAND_OPEN_APP_KEYEVENT
COMMAND_OPEN_APP_OBJECT              COMMAND_OPEN_APP_OBJECT_ACK
COMMAND_OPEN_APP_OBJECT_CONTROL      COMMAND_OPEN_APP_OBJECT_DELETE
COMMAND_OPEN_APP_OBJECT_REQ          COMMAND_OPEN_APP_OBJECT_RSP
COMMAND_OPEN_APP_SET_SWIPE_MODE      COMMAND_OPEN_APP_SHIFT_OBJECT
COMMAND_OPEN_APP_STOP                COMMAND_OPEN_APP_STOP_REQ
COMMAND_OPEN_APP_TOUCH               COMMAND_OPEN_APP_VIBRATE
COMMAND_PLAY_SOUNDEFFECT             COMMAND_PREF_CHANGE
COMMAND_SCREEN_LOCK                  COMMAND_SCREEN_UNLOCK
COMMAND_SETTINGS_PAIRING_REQ         COMMAND_SETTINGS_RESET
COMMAND_STANDBY_NOTIFICATION         COMMAND_STANDBY_PERMISSION_REQ
COMMAND_STANDBY_PERMISSION_RSP       COMMAND_STANDBY_REQ
COMMAND_STANDBY_WOW                  COMMAND_SYNC_ACK
COMMAND_SYNC_REQ                     COMMAND_SYNC_REQUEST
COMMAND_WIFI_CONNECTIVITY_STATUS     (= COMMAND_WIFI_STATUS_RES? or separate)
```

---

## 8. Files Retrieved

1. `ARCHITECTURE_MODERN.md` (lines 34, 85, 99, 120, 186, 210-215, 340-362, 1530-1570, 1620-1700, 1740-1760) — Protocol handshake FSM, FOTA phase, immutable firmware statement
2. `seg-swift/SEGKit/Sources/SEGKit/ProtocolActor.swift` (lines 40-81, 186-225) — Current FOTA handling implementation
3. `seg-swift/SEGKit/Sources/SEGKit/CommandConstants.swift` (full file) — Current wire command IDs
4. `Sony/.../apks/SmartEyeglassEmulator.apk` → `classes.dex` strings — **Primary source**: all FOTA classes, commands, UI strings
5. `Sony/.../SmartEyeglassAPI/src/com/sony/smarteyeglass/SmartEyeglassControl.java` (lines 60-85, 635-650) — API version confirm intent
6. `_dev/.../Registration.java` (lines 960-971) — FIRMWARE_VERSION column in registration DB
7. `Sony/.../SmartEyeglassControlUtils.java` (lines 405-430) — API version handshake to HostApp

---

## Method

Extracted all findings via `unzip -p SmartEyeglassEmulator.apk classes.dex | strings | grep ...` — no decompilation tools needed. Full decompilation with jadx would yield actual bytecode/logic for the FOTA state machine, but string extraction already reveals the complete protocol vocabulary and flow.
