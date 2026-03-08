import tkinter as tk
from tkinter import filedialog, messagebox
import subprocess
import os

class SVGConverterApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Inkscape SVG to PDF Converter")
        self.root.geometry("500x300")
        self.root.configure(bg="#f0f0f0")

        self.selected_files = []

        # Interfaz
        self.label = tk.Label(root, text="Convertidor de SVG a PDF", font=("Arial", 16, "bold"), bg="#f0f0f0")
        self.label.pack(pady=20)

        self.btn_select = tk.Button(root, text="Seleccionar archivos SVG", command=self.select_files, width=25, bg="#007acc", fg="white")
        self.btn_select.pack(pady=10)

        self.files_label = tk.Label(root, text="No hay archivos seleccionados", bg="#f0f0f0", fg="#555")
        self.files_label.pack()

        self.btn_convert = tk.Button(root, text="Convertir a PDF", command=self.convert_files, width=25, bg="#28a745", fg="white", state="disabled")
        self.btn_convert.pack(pady=20)

    def select_files(self):
        files = filedialog.askopenfilenames(title="Selecciona archivos SVG", filetypes=[("Archivos SVG", "*.svg")])
        if files:
            self.selected_files = list(files)
            self.files_label.config(text=f"{len(self.selected_files)} archivos listos.")
            self.btn_convert.config(state="normal")

    def convert_files(self):
        output_dir = filedialog.askdirectory(title="Selecciona carpeta de destino")
        if not output_dir:
            return

        success_count = 0
        for svg_path in self.selected_files:
            file_name = os.path.splitext(os.path.basename(svg_path))[0]
            pdf_path = os.path.join(output_dir, f"{file_name}.pdf")

            # Comando de Inkscape para exportar
            # Usamos la sintaxis moderna de Inkscape 1.x
            command = [
                "inkscape",
                svg_path,
                "--export-type=pdf",
                f"--export-filename={pdf_path}"
            ]

            try:
                # Ejecutamos en segundo plano sin abrir ventana de consola
                subprocess.run(command, check=True, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
                success_count += 1
            except Exception as e:
                messagebox.showerror("Error", f"No se pudo convertir {file_name}: {str(e)}")

        messagebox.showinfo("Proceso terminado", f"Se han convertido {success_count} archivos con éxito.")
        self.reset_ui()

    def reset_ui(self):
        self.selected_files = []
        self.files_label.config(text="No hay archivos seleccionados")
        self.btn_convert.config(state="disabled")

if __name__ == "__main__":
    root = tk.Tk()
    app = SVGConverterApp(root)
    root.mainloop()