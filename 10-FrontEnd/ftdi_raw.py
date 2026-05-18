from pyftdi.ftdi import Ftdi

ftdi = Ftdi()
ftdi.open(vendor=0x0403, product=0x6014)
ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)

H, W = 480, 640
frame_bytes = H * W  # 307200 bytes

# Leer un solo frame y guardarlo
data = b''
while len(data) < frame_bytes:
    chunk = ftdi.read_data(frame_bytes - len(data))
    if chunk:
        data += chunk

with open('frame.raw', 'wb') as f:
    f.write(data)

print(f"Frame guardado: {len(data)} bytes")
ftdi.close()