from PIL import Image

with open('frame.raw', 'rb') as f:
    data = f.read()

img = Image.frombytes('L', (640, 480), data)
img.save('frame.png')
img.show()