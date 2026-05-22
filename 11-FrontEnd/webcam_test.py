from pyftdi.ftdi import Ftdi

MARKER = bytes([0xFF, 0x00, 0xAA, 0x55])
H, W = 480, 640

ftdi = Ftdi()
ftdi.open_from_url('ftdi://ftdi:232h:FTAVP4X5/1')
ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)
ftdi.purge_buffers()

buf = b''
while True:
    buf += ftdi.read_data(4096)
    idx = buf.find(MARKER)
    if idx != -1:
        buf = buf[idx + len(MARKER):]
        break

# Leer dos frames y medir la distancia entre marcadores
while True:
    buf += ftdi.read_data(4096)
    idx = buf.find(MARKER)
    if idx != -1:
        print(f"Distancia entre marcadores: {idx} bytes")
        print(f"Esperado: {H*W} = {H*W} bytes")
        print(f"Diferencia: {idx - H*W} bytes")
        break

ftdi.close()