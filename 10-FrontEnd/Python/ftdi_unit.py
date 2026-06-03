from pyftdi.ftdi import Ftdi
import time

ftdi = Ftdi()
ftdi.open_from_url('ftdi://ftdi:232h:FTAVP4X5/1')
ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)
ftdi.purge_buffers()
time.sleep(0.1)

print("CLKOUT activo — configura trigger en ILA ahora")
input("Presiona Enter cuando hayas configurado el trigger...")

print("Leyendo — dale a Run Trigger en la ILA ahora")
# Leer continuamente para mantener el FTDI activo
while True:
    data = ftdi.read_data(4096)
    # No cerrar el FTDI