from pyftdi.ftdi import Ftdi

ftdi = Ftdi()
ftdi.open_from_url('ftdi://ftdi:232h:FTAVP4X5/1')
ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)
ftdi.purge_buffers()

H, W = 480, 640
data = b''
while len(data) < H * W:
    chunk = ftdi.read_data(H * W - len(data))
    if chunk:
        data += chunk

with open('frame.raw', 'wb') as f:
    f.write(data)
print(f"Guardado: {len(data)} bytes")
ftdi.close()