from pyftdi.ftdi import Ftdi
from PIL import Image

MARKER = bytes([0xFF, 0x00, 0xAA, 0x55])
H, W = 480, 640

ftdi = Ftdi()
ftdi.open_from_url('ftdi://ftdi:232h:FTAVP4X5/1')
ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)
ftdi.purge_buffers()

buf = b''
# Buscar marcador
while True:
    buf += ftdi.read_data(4096)
    idx = buf.find(MARKER)
    if idx != -1:
        buf = buf[idx + len(MARKER):]
        break

# Leer frame completo
while len(buf) < H * W:
    buf += ftdi.read_data(H * W - len(buf))

frame_data = buf[:H * W]

img = Image.frombytes('L', (W, H), frame_data)
img.save('frame.png')
img.show()
ftdi.close()