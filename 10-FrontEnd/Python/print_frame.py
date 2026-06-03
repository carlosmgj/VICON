"""
print_frame.py — Lee ftdi_rx_log.txt y muestra los frames en consola.
Uso: python print_frame.py [ruta_log] [H_RES] [V_RES]
"""

import sys

LOG_FILE = sys.argv[1] if len(sys.argv) > 1 else "ftdi_rx_log.txt"
H_RES    = int(sys.argv[2]) if len(sys.argv) > 2 else 8
V_RES    = int(sys.argv[3]) if len(sys.argv) > 3 else 4
MARKER   = [0xAA, 0x55, 0xAA, 0x55]

# Sustituciones inversas
SUBS_INV = { 0xFE: 0xFF, 0xAB: 0xAA, 0x56: 0x55}

# ─── Leer bytes del log ───────────────────────────────────────────────────────
data = []
with open(LOG_FILE, 'r') as f:
    for line in f:
        for token in line.split():
            try:
                data.append(int(token, 16) if token.startswith('0x') else int(token))
            except ValueError:
                pass

print(f"Bytes leídos: {len(data)}")

# ─── Extraer y mostrar frames ─────────────────────────────────────────────────
n_pixels = H_RES * V_RES
frame_num = 0
i = 0

while i < len(data):
    # Buscar marcador
    if data[i:i+4] == MARKER:
        i += 4
        if i + n_pixels > len(data):
            print(f"\nFrame {frame_num}: datos incompletos ({len(data)-i}/{n_pixels} bytes)")
            break

        raw = data[i:i+n_pixels]
        pixels = [SUBS_INV.get(b, b) for b in raw]

        print(f"\n--- Frame {frame_num} ---")
        for row in range(V_RES):
            line = pixels[row*H_RES : (row+1)*H_RES]
            print(f"  Línea {row}: {[hex(v) for v in line]}")

        frame_num += 1
        i += n_pixels
    else:
        i += 1

print(f"\nTotal frames: {frame_num}")
