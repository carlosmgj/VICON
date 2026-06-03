"""
vicon_capture.py — Captura un frame desde VICON via FT232H (pyftdi).

Uso:
    python vicon_capture.py
"""

from pyftdi.ftdi import Ftdi
from PIL import Image

# ─── Configuración ────────────────────────────────────────────────────────────
FTDI_URL = 'ftdi://ftdi:232h/1'  # ajustar si hay varios dispositivos
H, W    = 480, 640               # resolución del sensor
MARKER  = bytes([0xAA, 0x55, 0xAA, 0x55])

# Sustituciones inversas (deshacer lo que hace frame_capture)
SUBS_INV = {0x01: 0x00, 0xFE: 0xFF, 0xAB: 0xAA, 0x56: 0x55}

# ─── Abrir FT232H en modo FIFO síncrono ──────────────────────────────────────
ftdi = Ftdi()
ftdi.open_from_url(FTDI_URL)
ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)
ftdi.purge_buffers()

# ─── Buscar marcador ──────────────────────────────────────────────────────────
buf = b''
while True:
    buf += ftdi.read_data(4096)
    idx = buf.find(MARKER)
    if idx != -1:
        buf = buf[idx + len(MARKER):]
        break

# ─── Leer frame completo ──────────────────────────────────────────────────────
while len(buf) < H * W:
    buf += ftdi.read_data(H * W - len(buf))

frame_data = buf[:H * W]

# ─── Deshacer sustituciones ───────────────────────────────────────────────────
frame_data = bytes(SUBS_INV.get(b, b) for b in frame_data)

# ─── Guardar y mostrar ────────────────────────────────────────────────────────
img = Image.frombytes('L', (W, H), frame_data)
img.save('frame.png')
img.show()
print(f"Frame guardado en frame.png ({W}x{H} px)")

ftdi.close()
