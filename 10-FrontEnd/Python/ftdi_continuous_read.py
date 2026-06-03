from pyftdi.ftdi import Ftdi
import time

ftdi = Ftdi()
ftdi.open_from_url('ftdi://ftdi:232h:FTAVP4X5/1')
ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)
ftdi.purge_buffers()

print("CLKOUT activo — abre la ILA y pon el trigger")
input("Presiona Enter para empezar a leer...")

print("Leyendo...")
while True:
    data = ftdi.read_data(1024)
    if data:
        print(f"Recibido: {len(data)} bytes — primeros: {list(data[:10])}")
    time.sleep(0.01)