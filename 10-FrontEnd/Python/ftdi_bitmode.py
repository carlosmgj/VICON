from pyftdi.ftdi import Ftdi
import time

ftdi = Ftdi()
ftdi.open_from_url('ftdi://ftdi:232h:FTAVP4X5/1')
ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)
print("CLKOUT activo — abre la ILA ahora")
input("Presiona Enter para cerrar...")
ftdi.close()