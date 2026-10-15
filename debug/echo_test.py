#!/usr/bin/env python3
"""Send bytes out each USB port, see if they come back (echo_top flashed)."""
import glob, time, serial
for port in sorted(glob.glob("/dev/cu.usb*")):
    for baud in (9600, 115200, 921600):
        s = serial.Serial(port, baud, timeout=0.5)
        s.reset_input_buffer()
        s.write(b"HELLO123"); s.flush()
        time.sleep(0.3)
        got = s.read(64)
        s.close()
        print(f"{port} {baud:7d} sent b'HELLO123' got {got!r}")
