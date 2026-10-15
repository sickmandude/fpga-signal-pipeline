#!/usr/bin/env python3
"""
scan_bauds.py - denser baud sweep. Run with uart_stream_top flashed
(FPGA sending A..Z continuously at 115200 baud on pin 17).

For each USB serial port and each baud rate, read for 0.6 s and report:
  - how many bytes arrived
  - which distinct byte values appeared
  - how many of them are the letters A..Z (what we actually sent)

  python3 scan_bauds.py | tee scan_bauds.txt
"""
import glob
import time
import serial  # pip3 install pyserial

PORTS = sorted(glob.glob("/dev/cu.usb*"))
BAUDS = [300, 1200, 2400, 4800, 9600, 14400, 19200, 28800, 38400, 57600,
         76800, 115200, 128000, 230400, 256000, 460800, 500000, 576000,
         921600, 1000000, 1152000, 1500000, 2000000, 3000000]

print("ports found:", PORTS if PORTS else "NONE")
print(f"{'port':26s} {'baud':>8s} {'bytes':>6s} {'letters':>7s}  distinct values / sample")

for port in PORTS:
    for baud in BAUDS:
        try:
            s = serial.Serial()
            s.port = port
            s.baudrate = baud
            s.timeout = 0.6
            s.open()
            time.sleep(0.05)
            data = s.read(200)
            s.close()
        except Exception as e:
            print(f"{port:26s} {baud:8d}  ERROR {e}")
            continue
        if not data:
            print(f"{port:26s} {baud:8d} {0:6d}")
            continue
        letters = sum(1 for b in data if 0x41 <= b <= 0x5A)
        distinct = sorted(set(data))
        shown = ' '.join(f"{b:02X}" for b in distinct[:12])
        print(f"{port:26s} {baud:8d} {len(data):6d} {letters:7d}  {shown}  {data[:16]!r}")
