import sys
import time
from pyftdi.ftdi import Ftdi
import numpy as np

H        = int(sys.argv[1]) if len(sys.argv) > 1 else 10
W        = int(sys.argv[2]) if len(sys.argv) > 2 else 20
VERBOSE  = False   # ← True: muestra filas/esperado/diffs; False: solo Frame N FAIL
MARKER   = bytes([0xAA, 0x55, 0xAA, 0x55])
SUBS     = {0xAA: 0xAB, 0x55: 0x56, 0xFF: 0xFE}

expected_row = np.array([SUBS.get(i % 256, i % 256) for i in range(W)], dtype=np.uint8)

ftdi = Ftdi()
ftdi.open_from_url('ftdi://ftdi:232h:FTAVP4X5/1')
ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)
ftdi.purge_buffers()
print(f"FT232H listo. Validando frames {W}×{H}...")
print(f"Patrón esperado: {list(expected_row)}")
print(f"Ctrl+C para parar\n")

buf = b''
for _ in range(2):
    while True:
        buf += ftdi.read_data(4096)
        idx = buf.find(MARKER)
        if idx != -1:
            buf = buf[idx + len(MARKER):]
            break

frame_num  = 0
ok_count   = 0
fail_count = 0

try:
    while True:
        # ─── Leer frame ───────────────────────────────────────────────────
        t_start = time.perf_counter()
        while len(buf) < H * W:
            buf += ftdi.read_data(H * W - len(buf))
        t_read = time.perf_counter() - t_start

        velocidad_mbps = (H * W) / t_read / 1e6 if t_read > 0 else 0

        frame = buf[:H * W]
        buf   = buf[H * W:]
        arr   = np.frombuffer(frame, dtype=np.uint8).reshape(H, W)

        # ─── Validar ──────────────────────────────────────────────────────
        ok = True
        for row in range(H):
            if not np.array_equal(arr[row], expected_row):
                if ok:
                    print(f"\nFrame {frame_num} FAIL:  ({t_read*1000:.2f} ms, {velocidad_mbps:.2f} MB/s)")
                if VERBOSE:
                    diffs    = np.where(arr[row] != expected_row)[0]
                    got      = list(map(int, arr[row]))
                    expected = list(map(int, expected_row))
                    print(f"  Fila {row}: {got}")
                    print(f"  esperado: {expected}")
                    print(f"  diffs en col: {list(map(int, diffs))}")
                else:
                    print(f"  Fila {row} falla")
                ok = False

        if ok:
            ok_count += 1
            print(f"Frame {frame_num:5d} ✓  "
                  f"({t_read*1000:.2f} ms, {velocidad_mbps:.2f} MB/s)  "
                  f"ok={ok_count}, fail={fail_count}",
                  end='\r')
        else:
            fail_count += 1

        frame_num += 1

        # ─── Buscar siguiente marcador ────────────────────────────────────
        while True:
            buf += ftdi.read_data(4096)
            idx = buf.find(MARKER)
            if idx != -1:
                buf = buf[idx + len(MARKER):]
                break

except KeyboardInterrupt:
    print(f"\n\nParado. Total: {frame_num} frames, {ok_count} OK, {fail_count} FAIL "
          f"({100*fail_count/max(frame_num,1):.1f}%)")

ftdi.close()