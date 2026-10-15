#!/usr/bin/env python3
"""Send a continuous stream of 0x00 bytes to a serial port for a few seconds.
Used with uart_pin_probe to see which FPGA pin the USB bridge is driving.

  python3 send_zeros.py /dev/cu.usbserial-11101 8
"""
import sys
import time
import serial  # pip3 install pyserial

port = sys.argv[1]
seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 8.0

s = serial.Serial(port, 115200)
t0 = time.time()
n = 0
while time.time() - t0 < seconds:
    s.write(b"\x00" * 64)
    n += 64
s.close()
print(f"sent {n} bytes of 0x00 to {port}")
