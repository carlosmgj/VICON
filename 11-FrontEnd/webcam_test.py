from pyftdi.ftdi import Ftdi
from PIL import Image, ImageTk
import tkinter as tk
import threading

H, W = 480, 640
MARKER = bytes([0xFF, 0x00, 0xAA, 0x55])

ftdi = Ftdi()
ftdi.open_from_url('ftdi://ftdi:232h:FTAVP4X5/1')
ftdi.set_bitmode(0xFF, Ftdi.BitMode.SYNCFF)
ftdi.purge_buffers()

root = tk.Tk()
root.title("MT9V111")
label = tk.Label(root)
label.pack()

def read_frames():
    buf = b''
    while True:
        # Buscar marcador de inicio de frame
        while True:
            buf += ftdi.read_data(1024)
            idx = buf.find(MARKER)
            if idx != -1:
                buf = buf[idx + len(MARKER):]
                break

        # Leer frame completo
        while len(buf) < H * W:
            buf += ftdi.read_data(H * W - len(buf))

        frame_data = buf[:H * W]
        buf = buf[H * W:]

        img = Image.frombytes('L', (W, H), frame_data)
        tk_img = ImageTk.PhotoImage(img)
        label.config(image=tk_img)
        label.image = tk_img

t = threading.Thread(target=read_frames, daemon=True)
t.start()
root.mainloop()
ftdi.close()