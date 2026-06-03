from pyftdi.ftdi import Ftdi
import time

MARKER  = bytes([0xAA, 0x55, 0xAA, 0x55])
H, W    = 480, 640
SUBS_INV = { 0xFE: 0xFF, 0xAB: 0xAA, 0x56: 0x55}

ftdi = Ftdi()
ftdi.open_from_url('ftdi://ftdi:232h:FTAVP4X5/1')
ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)
ftdi.purge_buffers()
time.sleep(0.5)

# Buscar primer marcador (descartar — puede estar a mitad de frame)
print("Buscando marcador...")
buf = b''
while True:
    buf += ftdi.read_data(4096)
    idx = buf.find(MARKER)
    if idx != -1:
        buf = buf[idx + len(MARKER):]
        break

# Esperar segundo marcador (frame completo garantizado)
print("Sincronizando...")
while True:
    buf += ftdi.read_data(4096)
    idx = buf.find(MARKER)
    if idx != -1:
        print(f"Frame sincronizado")
        buf = buf[idx + len(MARKER):]
        break

# Leer frame
print("Leyendo frame...")
while len(buf) < H * W:
    buf += ftdi.read_data(H * W - len(buf))
    print(f"{len(buf)}/{H*W} bytes", end='\r')

# Deshacer sustituciones
frame = bytes(SUBS_INV.get(b, b) for b in buf[:H*W])

print(f"Primeros 32 bytes: {[hex(b) for b in frame[:32]]}")
print(f"Bytes 638-648 (fin fila 0 / inicio fila 1): {[hex(b) for b in frame[638:650]]}")
print(f"Bytes 1278-1288 (fin fila 1 / inicio fila 2): {[hex(b) for b in frame[1278:1290]]}")

# Imprimir primeros bytes para verificar
print(f"\nPrimeros 16 bytes: {[hex(b) for b in frame[:16]]}")

with open('frame.raw', 'wb') as f:
    f.write(frame)
print("Guardado en frame.raw")

ftdi.close()