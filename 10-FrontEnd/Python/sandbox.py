"""
validate_ila.py — Valida frame con resolución reducida para debug con ILA.
Espera pulsación de Enter antes de empezar a leer (para armar el ILA primero).
Uso: py -3.11 validate_ila.py [H] [W]
"""

import sys
from pyftdi.ftdi import Ftdi
import numpy as np

H = int(sys.argv[1]) if len(sys.argv) > 1 else 10
W = int(sys.argv[2]) if len(sys.argv) > 2 else 20
MARKER   = bytes([0xAA, 0x55, 0xAA, 0x55])
SUBS     = {0xAA: 0xAB, 0x55: 0x56, 0xFF: 0xFE}

# ─── Abrir FTDI y generar reloj ───────────────────────────────────────────────
print("Abriendo FT232H...")
ftdi = Ftdi()
ftdi.open_from_url('ftdi://ftdi:232h:FTAVP4X5/1')
ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)
ftdi.purge_buffers()
print("FT232H listo — reloj activo")

# ─── Esperar pulsación ────────────────────────────────────────────────────────
input("\nArma el ILA en Vivado y pulsa Enter para empezar a leer...")

# ─── Sincronizar ─────────────────────────────────────────────────────────────
print("Buscando marcador...")
buf = b''
while True:
    buf += ftdi.read_data(4096)
    idx = buf.find(MARKER)
    if idx != -1:
        buf = buf[idx + len(MARKER):]
        break

print("Sincronizando (segundo marcador)...")
while True:
    buf += ftdi.read_data(4096)
    idx = buf.find(MARKER)
    if idx != -1:
        buf = buf[idx + len(MARKER):]
        break

# ─── Leer frame ──────────────────────────────────────────────────────────────
print(f"Leyendo frame {W}×{H}...")
while len(buf) < H * W:
    buf += ftdi.read_data(H * W - len(buf))

frame = buf[:H * W]

# ─── Mostrar frame completo ───────────────────────────────────────────────────
arr = np.frombuffer(frame, dtype=np.uint8).reshape(H, W)

print(f"\n--- Frame {W}×{H} ---")
for row in range(H):
    print(f"  Fila {row:2d}: {list(arr[row, :])}")

# ─── Discontinuidades ────────────────────────────────────────────────────────
print("\nDiscontinuidades entre filas:")
n_errors = 0
for row in range(1, H):
    prev_last = int(arr[row-1, -1])
    curr_first = int(arr[row, 0])
    expected = (prev_last + 1) % 256
    if curr_first != expected:
        print(f"  Fila {row}: fin_anterior={prev_last}, inicio={curr_first}, esperado={expected}, diff={curr_first-expected}")
        n_errors += 1
if n_errors == 0:
    print("  Ninguna ✓")

# ─── Validar patrón esperado ──────────────────────────────────────────────────
expected_raw = np.tile(np.arange(256, dtype=np.uint8), W // 256 + 1)[:W]
expected_raw = np.tile(expected_raw, (H, 1))
expected = np.vectorize(lambda x: SUBS.get(int(x), int(x)))(expected_raw).astype(np.uint8)

offset = int(arr[0, 0])
expected_offset = np.roll(expected, -offset, axis=1)
errors = np.sum(arr != expected_offset)

print(f"\nOffset primer píxel: {offset}")
print(f"Errores: {errors} / {H*W} ({100*errors/(H*W):.2f}%)")
if errors == 0:
    print("✓ Frame perfecto")

input("\nPulsa Enter para cerrar...")
ftdi.close()