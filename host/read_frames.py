#!/usr/bin/env python3
"""
read_frames.py - read framed samples from the FPGA over a serial port.

Frame (7 bytes):  AA | F2 F1 F0 | R1 R0 | CHK
  F = 24-bit signed filter output (big-endian)
  R = raw 10-bit ADC code (big-endian, top byte only uses 2 bits)
  CHK = XOR of the 5 payload bytes

Usage:
  python3 read_frames.py /dev/cu.usbserial-XXXX            # print live
  python3 read_frames.py /dev/cu.usbserial-XXXX --csv out.csv --seconds 10
"""
import argparse
import csv
import sys
import time

FRAME_LEN = 7
SYNC = 0xAA
VREF = 3.3


def decode_frame(f):
    """f = 7 bytes starting with SYNC. Returns (filtered, raw) or None if bad checksum."""
    chk = f[1] ^ f[2] ^ f[3] ^ f[4] ^ f[5]
    if chk != f[6]:
        return None
    f24 = (f[1] << 16) | (f[2] << 8) | f[3]
    if f24 & 0x800000:
        f24 -= 1 << 24
    raw = ((f[4] & 0x03) << 8) | f[5]
    return f24, raw


def extract_frames(buf):
    """
    Pull every valid frame out of bytearray `buf`.
    Returns (frames, remaining_buf, dropped_bytes).
    Resync rule: if the byte at the front is not a valid frame start,
    discard exactly one byte and try again.
    """
    frames = []
    dropped = 0
    while len(buf) >= FRAME_LEN:
        if buf[0] == SYNC:
            r = decode_frame(buf[:FRAME_LEN])
            if r is not None:
                frames.append(r)
                del buf[:FRAME_LEN]
                continue
        del buf[0]
        dropped += 1
    return frames, buf, dropped


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--csv", help="also write every frame to this CSV file")
    ap.add_argument("--seconds", type=float, help="stop after this many seconds")
    args = ap.parse_args()

    import serial  # pip3 install pyserial

    ser = serial.Serial(args.port, args.baud, timeout=0.1)
    # The bridge/driver may hold several KB of old frames from before we opened
    # the port. Throw that backlog away so every frame we keep is live.
    time.sleep(0.3)
    ser.reset_input_buffer()
    out = open(args.csv, "w", newline="") if args.csv else None
    w = csv.writer(out) if out else None
    if w:
        w.writerow(["t_s", "filtered", "raw", "volts"])

    buf = bytearray()
    t0 = time.time()
    n = 0
    dropped_total = 0
    try:
        while True:
            if args.seconds and time.time() - t0 > args.seconds:
                break
            buf += ser.read(256)
            frames, buf, dropped = extract_frames(buf)
            dropped_total += dropped
            for filt, raw in frames:
                n += 1
                volts = raw / 1024 * VREF
                t = time.time() - t0
                print(f"{n:6d}  raw={raw:4d} ({volts:5.3f} V)  filtered={filt:7d}")
                if w:
                    w.writerow([f"{t:.4f}", filt, raw, f"{volts:.4f}"])
    except KeyboardInterrupt:
        pass
    finally:
        ser.close()
        if out:
            out.close()
    print(f"\n{n} good frames, {dropped_total} bytes discarded while resyncing", file=sys.stderr)


if __name__ == "__main__":
    main()