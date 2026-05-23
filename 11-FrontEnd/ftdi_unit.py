from pyftdi.ftdi import Ftdi
import time

ftdi = Ftdi()
ftdi.open_from_url('ftdi://ftdi:232h:FTAVP4X5/1')
ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)
ftdi.purge_buffers()
time.sleep(0.1)

print("CLKOUT activo — abre la ILA ahora")
input("Presiona Enter para leer datos...")

data = ftdi.read_data(1024)
errors = 0
for i in range(1, len(data)):
    if data[i] != (data[i-1] + 1) % 256:
        errors += 1
        print(f"Error en posición {i}: esperado {(data[i-1]+1)%256}, recibido {data[i]}")
print(f"Total errores: {errors}/{len(data)} bytes")

ftdi.close()