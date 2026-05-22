from pyftdi.ftdi import Ftdi
import time

ftdi = Ftdi()
ftdi.open_from_url('ftdi://ftdi:232h:FTAVP4X5/1')

print("Antes de set_bitmode — captura ahora")
input("Presiona Enter para continuar...")

ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)
print("set_bitmode ejecutado")

time.sleep(0.5)

ftdi.purge_buffers()
print("Buffers purgados")

time.sleep(0.5)

print("Esperando datos...")
H, W = 480, 640
frame_bytes = H * W
data = b''
while len(data) < frame_bytes:
    chunk = ftdi.read_data(frame_bytes - len(data))
    if chunk:
        data += chunk
        print(f"{len(data)}/{frame_bytes} bytes", end='\r')

with open('frame.raw', 'wb') as f:
    f.write(data)

print(f"\nFrame guardado: {len(data)} bytes")
ftdi.close()