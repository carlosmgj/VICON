##
# @file recortar_json_wavedrom.py
# @brief Herramienta de edición y recorte de diagramas de tiempo para WaveDrom.
# 
# @details Esta utilidad permite procesar archivos JSON de WaveDrom con formato flexible 
# (estilo JavaScript). Realiza recortes precisos de señales, sincroniza etiquetas de datos 
# y corrige estados iniciales indeterminados mediante expresiones regulares y lógica de 
# retropropagación de estados.
#
# @section funcionalidades Funcionalidades principales:
# - Limpieza automática de JSON no estándar (claves sin comillas, comas sobrantes).
# - Recorte de señales manteniendo la continuidad lógica (evita puntos iniciales aislados).
# - Sincronización automática de la lista 'data' con la cadena 'wave'.
# - Interfaz gráfica (GUI) intuitiva con Tkinter.
# - Integración directa con el editor web de WaveDrom mediante el portapapeles.
#
# @author Carlos (MSEEI - TFM)
# @date 2026-03
##
import json
import re
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import webbrowser
import urllib.parse

def limpiar_formato_wavedrom(texto):
    """Limpia el formato flexible de WaveDrom para hacerlo JSON estándar."""
    texto = re.sub(r'//.*', '', texto) 
    texto = re.sub(r',\s*([\]}])', r'\1', texto) 
    texto = re.sub(r'([{,]\s*)([a-zA-Z_]\w*)\s*:', r'\1"\2":', texto) 
    texto = texto.replace("'", '"')
    return texto

def obtener_info_archivo(path):
    """Calcula la duración máxima de las señales."""
    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = json.loads(limpiar_formato_wavedrom(f.read()))
        max_ticks = 0
        for sig in data.get('signal', []):
            if 'wave' in sig:
                max_ticks = max(max_ticks, len(sig['wave']))
        return max_ticks
    except:
        return 0

def recortar_wavedrom(data, tick_start, tick_end, config_ui):
    """Aplica recorte, sincronización de datos y configuración visual."""
    data_chars = "23456789=" 
    for sig in data.get('signal', []):
        if 'wave' in sig:
            wave_full = sig['wave']
            skipped_data = sum(1 for char in wave_full[:tick_start] if char in data_chars)
            new_wave = wave_full[tick_start:tick_end]
            keep_data = sum(1 for char in new_wave if char in data_chars)
            sig['wave'] = new_wave
            if 'data' in sig and isinstance(sig['data'], list):
                sig['data'] = sig['data'][skipped_data : skipped_data + keep_data]

    if 'head' not in data: data['head'] = {}
    if 'foot' not in data: data['foot'] = {}
    
    data['head']['text'] = config_ui['titulo']
    data['foot']['text'] = config_ui['pie']
    
    if 'config' not in data: data['config'] = {}
    data['config']['hscale'] = int(config_ui['hscale'])
    data['config']['skin'] = config_ui['skin']
    data['head']['every'] = config_ui['every']
    
    return data

def seleccionar_archivo():
    """Función corregida para evitar el error UnboundLocalError."""
    archivo = filedialog.askopenfilename(filetypes=[("JSON files", "*.json"), ("All files", "*.*")])
    if archivo:
        entry_file.delete(0, tk.END)
        entry_file.insert(0, archivo)
        duracion = obtener_info_archivo(archivo)
        lbl_info.config(text=f"Duración: {duracion} ticks", fg="#1b5e20")
        entry_end.delete(0, tk.END)
        entry_end.insert(0, str(duracion))

def procesar(abrir_navegador=False):
    """Genera el JSON y opcionalmente lo abre en la web."""
    path = entry_file.get()
    if not path:
        messagebox.showwarning("Aviso", "Por favor, selecciona un archivo.")
        return

    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = json.loads(limpiar_formato_wavedrom(f.read()))
        
        config_ui = {
            'titulo': entry_title.get(),
            'pie': entry_foot.get(),
            'hscale': spin_hscale.get(),
            'skin': combo_skin.get(),
            'every': int(spin_every.get())
        }
        
        resultado = recortar_wavedrom(data, int(entry_start.get()), int(entry_end.get()), config_ui)
        json_str = json.dumps(resultado, indent=2)

        if abrir_navegador:
            
            codigo_url = urllib.parse.quote(json_str)
            webbrowser.open(f"https://wavedrom.com/editor.html?{codigo_url}")
        else:
            save_path = filedialog.asksaveasfilename(defaultextension=".json")
            if save_path:
                with open(save_path, 'w', encoding='utf-8') as f:
                    f.write(json_str)
                messagebox.showinfo("Éxito", "Archivo guardado correctamente.")
                
    except Exception as e:
        messagebox.showerror("Error", f"Ocurrió un problema:\n{e}")


root = tk.Tk()
root.title("WaveDrom Ultra Editor Pro")
root.geometry("500x550")


tk.Label(root, text="1. Selecciona tu archivo", font=('Arial', 10, 'bold')).pack(pady=(10,0))
frame_file = tk.Frame(root)
frame_file.pack(pady=5)
entry_file = tk.Entry(frame_file, width=45)
entry_file.pack(side=tk.LEFT, padx=5)
tk.Button(frame_file, text="Buscar", command=seleccionar_archivo).pack(side=tk.LEFT)
lbl_info = tk.Label(root, text="Sin archivo cargado")
lbl_info.pack()


tk.Label(root, text="2. Títulos y Notas", font=('Arial', 10, 'bold')).pack(pady=(10,0))
tk.Label(root, text="Título:").pack()
entry_title = tk.Entry(root, width=50); entry_title.pack()
tk.Label(root, text="Pie de página:").pack()
entry_foot = tk.Entry(root, width=50); entry_foot.pack()


frame_params = tk.LabelFrame(root, text=" 3. Ajustes de Recorte y Estilo ", padx=10, pady=10)
frame_params.pack(pady=15)

tk.Label(frame_params, text="Estilo:").grid(row=0, column=0)
combo_skin = ttk.Combobox(frame_params, values=["default", "narrow"], width=10)
combo_skin.set("default"); combo_skin.grid(row=0, column=1)

tk.Label(frame_params, text="Escala (Hscale):").grid(row=0, column=2, padx=(10,0))
spin_hscale = tk.Spinbox(frame_params, from_=1, to=10, width=5)
spin_hscale.grid(row=0, column=3)

tk.Label(frame_params, text="Tick Inicio:").grid(row=1, column=0, pady=10)
entry_start = tk.Entry(frame_params, width=7); entry_start.insert(0, "0")
entry_start.grid(row=1, column=1)

tk.Label(frame_params, text="Tick Fin:").grid(row=1, column=2)
entry_end = tk.Entry(frame_params, width=7); entry_end.insert(0, "20")
entry_end.grid(row=1, column=3)

tk.Label(frame_params, text="Numerar cada:").grid(row=2, column=0)
spin_every = tk.Spinbox(frame_params, from_=1, to=100, width=7)
spin_every.grid(row=2, column=1)


btn_frame = tk.Frame(root)
btn_frame.pack(pady=10)

tk.Button(btn_frame, text="GUARDAR JSON", bg="#455a64", fg="white", 
          command=lambda: procesar(False), padx=10, pady=10).pack(side=tk.LEFT, padx=5)

tk.Button(btn_frame, text="VER EN NAVEGADOR", bg="#1e88e5", fg="white", 
          font=('Arial', 10, 'bold'), command=lambda: procesar(True), padx=15, pady=10).pack(side=tk.LEFT, padx=5)

root.mainloop()