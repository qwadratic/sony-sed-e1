# Next Steps — Display Rendering

## Status: Connection works, display command format wrong

### What works
- BT RFCOMM channel 4 connection from macOS ✅
- Full handshake: ProtocolVersion → SettingsStatus → Version → NewHostApp → LayoutInit ✅
- Connection stays alive, sensor data streams, glasses accept image data ✅
- Game of Life engine coded in Swift ✅

### What doesn't work yet
- **Display stays empty** — our `OpenAppImage (0x35)` command is accepted but doesn't render
- The built-in test pattern (H/V lines) appears on connect but our image data doesn't display

### Root cause identified
The `0x35` command (OpenAppImage) is the **inter-process** command used between extension apps and MisiAha on the same Android device. Over the BT RFCOMM wire, MisiAha uses a **different protocol** to send images to the glasses:

The actual display pipeline is:
```
LayoutPlaceRemoveCommand (cmd=0xe3)
  └── contains LayoutPlaceImageData (subcommand type=7)
        ├── objId: int
        ├── imgFormat: int  
        ├── imageData: byte[]  (419×138, 1 byte per pixel, luminance 0-255)
        └── transactionNum: int (-1)
```

### Exact fix needed
Replace the current `golSendFrame()` which sends:
```
[0x35] [len_hi] [len_lo] [x:2B] [y:2B] [w:2B] [h:2B] [pixel_data...]
```

With:
```
[0xe3] [len_hi] [len_lo] [LayoutPlaceRemoveCommand payload containing:]
  [subcmd_type=7] [subcmd_len] [objId:4B] [imgFormat:4B] [transactionNum:4B=-1] [pixel_data]
```

### Files to read for the fix
- `/tmp/seg_decompiled/smali/com/sonyericsson/j2/commands/LayoutPlaceRemoveCommand.smali`
- `/tmp/seg_decompiled/smali/com/sonyericsson/j2/commands/layout/LayoutPlaceImageData.smali`
- `/tmp/seg_decompiled/smali/com/sonyericsson/j2/commands/layout/LayoutSubCommand.smali`

### Alternative: try MckinleyRawScreenImage
Found in APK strings: `MckinleyRawScreenImage.java` — this might be a simpler direct-to-hardware image command.
Search: `/tmp/seg_decompiled/smali/com/sony/smarteyeglass/MckinleyRawScreenImage.smali`

### Quick test: try PNG instead of raw
The SDK's `showBitmap` path through CONTROL_DISPLAY_DATA_INTENT also supports PNG format (it's mentioned in the Intent extras). Try wrapping the image as a PNG and sending via different command.
