"""
vicon_viewer.py — Recepción y visualización de frames VICON desde FT232H.

Protocolo:
  - Cada frame comienza con marcador: AA 55 AA 55
  - Datos: píxeles Y (luma) en orden raster, H_RES × V_RES bytes
  - Bytes reservados sustituidos: 00→01, FF→FE, AA→AB, 55→56

Uso:
  python vicon_viewer.py [--res 640x480] [--log] [--save]
"""

import serial
import serial.tools.list_ports
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import argparse
import sys
import time
from collections import deque

# ─── Constantes de protocolo ─────────────────────────────────────────────────
MARKER = bytes([0xAA, 0x55, 0xAA, 0x55])

# Sustituciones inversas (deshacer las sustituciones de frame_capture)
SUBSTITUTIONS_INV = {
    0x01: 0x00,
    0xFE: 0xFF,
    0xAB: 0xAA,
    0x56: 0x55,
}

def reverse_substitution(data: bytes) -> bytes:
    """Deshace las sustituciones de bytes reservados aplicadas por frame_capture."""
    return bytes(SUBSTITUTIONS_INV.get(b, b) for b in data)


# ─── Búsqueda de marcador ─────────────────────────────────────────────────────
def find_marker(buf: deque) -> bool:
    """
    Busca el marcador AA 55 AA 55 en el buffer.
    Descarta bytes hasta encontrarlo. Devuelve True si lo encontró.
    """
    marker = [0xAA, 0x55, 0xAA, 0x55]
    while len(buf) >= 4:
        if list(buf)[:4] == marker:
            for _ in range(4):
                buf.popleft()
            return True
        buf.popleft()
    return False


# ─── Lectura de un frame ──────────────────────────────────────────────────────
def read_frame(ser: serial.Serial, h_res: int, v_res: int,
               timeout_s: float = 2.0) -> np.ndarray | None:
    """
    Lee un frame completo del puerto serie.
    Busca el marcador y luego lee h_res × v_res bytes de luma Y.
    Devuelve un array numpy (v_res, h_res) uint8, o None si timeout.
    """
    n_pixels = h_res * v_res
    buf = deque()
    t_start = time.time()

    # Buscar marcador
    while True:
        if time.time() - t_start > timeout_s:
            print("[WARN] Timeout buscando marcador")
            return None
        chunk = ser.read(ser.in_waiting or 1)
        buf.extend(chunk)
        if find_marker(buf):
            break

    # Leer píxeles
    raw = bytearray()
    while len(raw) < n_pixels:
        if time.time() - t_start > timeout_s:
            print(f"[WARN] Timeout leyendo píxeles ({len(raw)}/{n_pixels})")
            return None
        needed = n_pixels - len(raw)
        chunk = ser.read(min(needed, ser.in_waiting or 1))
        raw.extend(chunk)

    # Deshacer sustituciones
    pixels = reverse_substitution(bytes(raw[:n_pixels]))
    frame = np.frombuffer(pixels, dtype=np.uint8).reshape(v_res, h_res)
    return frame


# ─── Validación de frame de simulación ───────────────────────────────────────
def validate_sim_frame(frame: np.ndarray) -> bool:
    """
    Valida un frame generado por cam_sim.
    Patrón esperado: cada fila es un gradiente horizontal 0,1,2,...,H_RES-1
    (wrapping a 8 bits).
    """
    h_res = frame.shape[1]
    expected_row = np.arange(h_res, dtype=np.uint8)
    ok = True
    for i, row in enumerate(frame):
        if not np.array_equal(row, expected_row):
            print(f"  [FAIL] Fila {i}: esperado {expected_row[:8]}... obtenido {row[:8]}...")
            ok = False
    if ok:
        print(f"  [OK] Frame válido — patrón de gradiente correcto")
    return ok


# ─── Modo log (ftdi_rx_log.txt de simulación) ────────────────────────────────
def parse_log_file(path: str, h_res: int, v_res: int):
    """
    Lee el ftdi_rx_log.txt generado por el agente FTDI en QuestaSim
    y extrae los frames para validarlos.
    """
    print(f"\n=== Leyendo log: {path} ===")
    try:
        with open(path, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"[ERROR] No se encontró {path}")
        return

    # Extraer bytes del log (formato: "time_ns: 0xXX")
    data = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        for p in parts:
            if p.startswith('0x') or p.startswith('0X'):
                try:
                    data.append(int(p, 16))
                except ValueError:
                    pass
            elif p.isdigit():
                try:
                    val = int(p)
                    if 0 <= val <= 255:
                        data.append(val)
                except ValueError:
                    pass

    print(f"  Bytes leídos: {len(data)}")

    # Buscar frames
    n_pixels = h_res * v_res
    frame_num = 0
    i = 0
    while i < len(data) - 4:
        # Buscar marcador
        if data[i:i+4] == [0xAA, 0x55, 0xAA, 0x55]:
            i += 4
            if i + n_pixels <= len(data):
                raw = bytes(data[i:i+n_pixels])
                pixels = reverse_substitution(raw)
                frame = np.frombuffer(pixels, dtype=np.uint8).reshape(v_res, h_res)
                print(f"\n  Frame {frame_num}:")
                print(f"    Primeros bytes: {list(frame[0,:8])}")
                validate_sim_frame(frame)
                frame_num += 1
                i += n_pixels
            else:
                print(f"  [WARN] Frame {frame_num} incompleto al final del log")
                break
        else:
            i += 1

    print(f"\n  Total frames encontrados: {frame_num}")


# ─── Modo live (hardware real) ────────────────────────────────────────────────
def live_viewer(port: str, baud: int, h_res: int, v_res: int, save: bool):
    """Muestra frames en tiempo real desde el FT232H."""
    print(f"\n=== Live viewer: {port} @ {baud} baud, {h_res}×{v_res} ===")

    try:
        ser = serial.Serial(port, baud, timeout=0.1)
    except serial.SerialException as e:
        print(f"[ERROR] No se pudo abrir {port}: {e}")
        sys.exit(1)

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    fig.suptitle(f'VICON — {h_res}×{v_res} px')

    # Imagen en escala de grises
    ax_img = axes[0]
    ax_img.set_title('Imagen (Y luma)')
    dummy = np.zeros((v_res, h_res), dtype=np.uint8)
    im = ax_img.imshow(dummy, cmap='gray', vmin=0, vmax=255, interpolation='nearest')
    plt.colorbar(im, ax=ax_img)

    # Histograma
    ax_hist = axes[1]
    ax_hist.set_title('Histograma de Y')
    ax_hist.set_xlabel('Valor Y')
    ax_hist.set_ylabel('Píxeles')

    frame_count = [0]
    fps_times = deque(maxlen=30)

    def update(_):
        t0 = time.time()
        frame = read_frame(ser, h_res, v_res, timeout_s=1.0)
        if frame is None:
            return

        frame_count[0] += 1
        fps_times.append(time.time())

        # Actualizar imagen
        im.set_data(frame)

        # Actualizar histograma
        ax_hist.cla()
        ax_hist.set_title('Histograma de Y')
        ax_hist.set_xlabel('Valor Y')
        ax_hist.set_ylabel('Píxeles')
        ax_hist.hist(frame.flatten(), bins=64, range=(0, 255), color='#89b4fa')

        # FPS
        if len(fps_times) >= 2:
            fps = len(fps_times) / (fps_times[-1] - fps_times[0])
            fig.suptitle(f'VICON — {h_res}×{v_res} px | Frame {frame_count[0]} | {fps:.1f} fps')

        if save:
            plt.imsave(f'frame_{frame_count[0]:05d}.png', frame, cmap='gray')

        return [im]

    ani = animation.FuncAnimation(fig, update, interval=50, blit=False)
    plt.tight_layout()
    plt.show()
    ser.close()


# ─── Main ─────────────────────────────────────────────────────────────────────
def list_ports():
    ports = serial.tools.list_ports.comports()
    if not ports:
        print("No se encontraron puertos serie.")
    else:
        print("Puertos disponibles:")
        for p in ports:
            print(f"  {p.device} — {p.description}")


def main():
    parser = argparse.ArgumentParser(description='VICON frame viewer')
    parser.add_argument('--port',    default=None,     help='Puerto serie (ej: COM3 o /dev/ttyUSB0)')
    parser.add_argument('--baud',    default=12000000, type=int, help='Baudrate (default: 12000000)')
    parser.add_argument('--res',     default='640x480', help='Resolución HxV (default: 640x480)')
    parser.add_argument('--log',     default=None,     help='Parsear ftdi_rx_log.txt en lugar de puerto serie')
    parser.add_argument('--save',    action='store_true', help='Guardar frames como PNG')
    parser.add_argument('--list',    action='store_true', help='Listar puertos disponibles')
    parser.add_argument('--sim-res', default=None,     help='Resolución reducida de simulación (ej: 8x4)')
    args = parser.parse_args()

    if args.list:
        list_ports()
        return

    # Resolución
    res_str = args.sim_res if args.sim_res else args.res
    try:
        h_res, v_res = map(int, res_str.lower().split('x'))
    except ValueError:
        print(f"[ERROR] Formato de resolución inválido: {res_str} (esperado: WxH)")
        sys.exit(1)

    print(f"Resolución: {h_res}×{v_res} = {h_res*v_res} bytes/frame")

    # Modo log de simulación
    if args.log:
        parse_log_file(args.log, h_res, v_res)
        return

    # Modo live
    if args.port is None:
        print("[ERROR] Especifica --port o --log")
        print("       Usa --list para ver puertos disponibles")
        sys.exit(1)

    live_viewer(args.port, args.baud, h_res, v_res, args.save)


if __name__ == '__main__':
    main()
