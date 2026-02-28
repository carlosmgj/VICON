# VICON

## Trabajo Fin de Master en Sistemas Electrónicos para Entornos Inteligentes

Documentación disponible <a href="https://carlosmgj.github.io/VICON/" target="_blank"> aquí</a>


## Configuración de Editor Visual Studio Code

El desarrollo del proyecto se ha realizado utilizando principalmente este editor, que tiene soport (por medio de extensiones) para:

- GIT: Push/pull/Resolver Merge Conflicts/Ver gráfica de ramas, etc
- LaTex: Compilar (Automaticamente al guardar o con la receta), ver PDF (Ctrl + Alt + V), ayuda a sintaxis
- MarkDown: previsualización (Ctrl + Shift + V)


Si se abre la carpeta del repositorio con VSCode, los settings se cargarán desde .vscode/settings.json > globales

Para cargar el perfil, habrá que importar el archivo localizado en: vscode_profiles/FPGA.code-profile. Aquí se incluyen:
- Settings (settings.json) globales
- Extensiones instaladas
- Keybindings (atajos de teclado)
- Snippets
- Tasks y launch configs

La idea es tener por ejemplo un perfil para Python, otro para VHDL/LaTeX, otro para web, cada uno con sus propias extensiones y configuración sin que se mezclen ni se ralenticen entre sí.
