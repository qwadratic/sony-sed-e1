#!/usr/bin/env python3
"""
decode_oob.py — Decode the NFC OOB payload from NFC Tools app

When NFC Tools shows the NDEF record for the glasses, copy the hex bytes here.
This script extracts the BT MAC address and device name.

Usage:
  python3 decode_oob.py "ff ee dd cc bb aa 0f 09 53 6d 61 72 74 45 79 65 67 6c 61 73 73"
  # or paste the hex string shown by NFC Tools
"""

import sys, struct

def decode_oob(hex_str: str):
    """
    Bluetooth SSP OOB (application/vnd.bluetooth.ep.oob) payload decoder.
    Format per Bluetooth Core Spec, Vol 3, Part C, Section 8:
    
      [2 bytes] OOB Data Length (LE, includes itself)
      [6 bytes] BD_ADDR (little-endian MAC)
      [N bytes] Optional EIR structures:
                  [length][type][data...]
                  Types: 0x09 = Complete Local Name
                         0x08 = Shortened Local Name
                         0x0D = Class of Device
                         0x0E = Simple Pairing Hash C-192
                         0x0F = Simple Pairing Randomizer R-192
    """
    raw = bytes.fromhex(hex_str.replace(" ", "").replace(":", "").replace("-", ""))
    
    if len(raw) < 8:
        print(f"Too short ({len(raw)} bytes), need at least 8")
        return

    oob_len = struct.unpack_from('<H', raw, 0)[0]
    print(f"OOB Data Length: {oob_len} bytes")

    # BD_ADDR: 6 bytes at offset 2, little-endian → big-endian for display
    bd_addr = raw[2:8]
    mac = ':'.join(f'{b:02X}' for b in reversed(bd_addr))
    print(f"\n🔵 Bluetooth MAC Address: {mac}")
    print(f"   (raw LE bytes: {bd_addr.hex(' ')})")

    # Parse EIR structures
    offset = 8
    while offset < len(raw):
        if offset >= len(raw): break
        eir_len = raw[offset]
        if eir_len == 0: break
        if offset + eir_len >= len(raw): break
        
        eir_type = raw[offset + 1]
        eir_data = raw[offset + 2 : offset + 1 + eir_len]
        
        if eir_type in (0x08, 0x09):
            name = eir_data.decode('utf-8', errors='replace')
            label = "Complete Name" if eir_type == 0x09 else "Short Name"
            print(f"   {label}: {name}")
        elif eir_type == 0x0D:
            print(f"   Class of Device: {eir_data.hex()}")
        else:
            print(f"   EIR type=0x{eir_type:02x}: {eir_data.hex()}")
        
        offset += 1 + eir_len

    print(f"\n✅ Use this MAC with glasses-tool:")
    print(f"   ./glasses-tool connect {mac}")
    print(f"   ./glasses-tool sdp {mac}")
    print(f"   ./glasses-tool probe {mac}")

if __name__ == '__main__':
    if len(sys.argv) > 1:
        decode_oob(' '.join(sys.argv[1:]))
    else:
        print(__doc__)
        print("\nExample — paste the hex from NFC Tools here:")
        print("  python3 decode_oob.py 'FF EE DD CC BB AA'")
        print("\nIf NFC Tools shows base64, decode it first:")
        print("  python3 -c \"import base64; print(base64.b64decode('BASE64HERE').hex(' '))\"")
