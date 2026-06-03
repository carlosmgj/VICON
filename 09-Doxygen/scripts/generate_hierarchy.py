#!/usr/bin/env python3
import re
import sys
import argparse
from pathlib import Path
from dataclasses import dataclass, field


# =============================================================================
# ESTRUCTURAS DE DATOS
# =============================================================================

@dataclass
class VhdlModule:
    """Representa una entidad VHDL con sus instanciaciones."""
    name: str
    path: Path
    instantiates: list[str] = field(default_factory=list)
    architecture: str = ''


# =============================================================================
# PARSER DE JERARQUÍA
# =============================================================================

class HierarchyParser:
    """
    Extrae la jerarquía de instanciaciones VHDL usando regex.

    Se usa regex en lugar de pyGHDL porque este script se ejecuta antes
    de Doxygen y necesita ser robusto con cualquier sintaxis VHDL,
    incluyendo ficheros con errores de compilación o packages.
    """

    # Detecta declaración de entidad: entity nombre is
    _RE_ENTITY = re.compile(
        r'\bentity\s+(\w+)\s+is\b',
        re.IGNORECASE
    )

    # Detecta instanciación directa: label : entity work.nombre
    # Soporta nombre de arquitectura opcional: entity work.nombre(rtl)
    _RE_ENTITY_INST = re.compile(
        r':\s*entity\s+\w+\.(\w+)(?:\s*\(\w+\))?\s*(?:generic|port|\n)',
        re.IGNORECASE
    )

    # Palabras reservadas VHDL para evitar falsos positivos en instanciaciones
    _VHDL_KEYWORDS = {
        'process', 'begin', 'end', 'if', 'else', 'elsif', 'case', 'when',
        'loop', 'for', 'while', 'wait', 'signal', 'variable', 'constant',
        'port', 'generic', 'map', 'architecture', 'package', 'library',
        'use', 'with', 'select', 'generate', 'block', 'component',
        'function', 'procedure', 'return', 'type', 'subtype', 'record',
        'array', 'of', 'in', 'out', 'inout', 'buffer', 'linkage',
        'std_logic', 'std_logic_vector', 'integer', 'natural', 'boolean',
        'bit', 'bit_vector', 'string', 'real', 'time', 'others', 'null',
        'open', 'true', 'false', 'rising_edge', 'falling_edge',
        'to_integer', 'to_unsigned', 'to_signed', 'resize', 'conv_integer',
    }

    # Detecta instanciación por componente: label : ComponentName port map
    _RE_COMPONENT_INST = re.compile(
        r'(\w+)\s*:\s*(\w+)\s*(?:generic\s+map|port\s+map)',
        re.IGNORECASE
    )

    _RE_ARCH = re.compile(
        r'\barchitecture\s+(\w+)\s+of\s+(\w+)\s+is\b',
        re.IGNORECASE
    )

    def parse_file(self, path: Path) -> list[VhdlModule]:
        try:
            source = path.read_text(encoding='utf-8', errors='replace')
        except Exception as e:
            print(f"[generate_hierarchy] Error leyendo {path}: {e}", file=sys.stderr)
            return []

        # Eliminar comentarios de línea para evitar falsos positivos
        source_clean = re.sub(r'--[^\n]*', '', source)

        modules = []

        for entity_match in self._RE_ENTITY.finditer(source_clean):
            entity_name = entity_match.group(1)

            # Ignorar "end entity nombre" — solo queremos la declaración
            before = source_clean[max(0, entity_match.start()-10):entity_match.start()]
            if re.search(r'\bend\s*$', before, re.IGNORECASE):
                continue

            module = VhdlModule(name=entity_name, path=path)

            # Detectar arquitectura
            arch_match = self._RE_ARCH.search(source_clean)
            if arch_match:
                module.architecture = arch_match.group(1)

            rest = source_clean[entity_match.start():]

            # 1. Instanciaciones directas: entity work.X(arch) o entity lib.X
            for inst_match in self._RE_ENTITY_INST.finditer(rest):
                inst_name = inst_match.group(1)
                if inst_name.lower() not in self._VHDL_KEYWORDS:
                    if inst_name not in module.instantiates:
                        module.instantiates.append(inst_name)

            # 2. Instanciaciones por componente: label : ComponentName port map
            for comp_match in self._RE_COMPONENT_INST.finditer(rest):
                comp_name = comp_match.group(2)
                if comp_name.lower() not in self._VHDL_KEYWORDS:
                    if comp_name not in module.instantiates:
                        module.instantiates.append(comp_name)

            modules.append(module)

        return modules


# =============================================================================
# GENERADOR DE DIAGRAMA WBS (Work Breakdown Structure)
# =============================================================================

class HierarchyWbsGenerator:
    """
    Genera un diagrama de jerarquía PlantUML con dirección top-to-bottom.
    Más legible que left-to-right cuando hay muchos módulos.
    """

    def generate(self, modules: list[VhdlModule]) -> str:
        module_map = {m.name.lower(): m for m in modules}

        # Detectar módulos raíz
        all_instantiated = set()
        for m in modules:
            for inst in m.instantiates:
                all_instantiated.add(inst.lower())

        root_modules = {m.name for m in modules if m.name.lower() not in all_instantiated}

        def is_testbench(name: str) -> bool:
            n = name.lower()
            return (n.startswith('tb_') or n.endswith('_tb') or
                    'testbench' in n or n.startswith('tb'))

        lines = [
            '@startuml',
            'skinparam componentStyle rectangle',
            'skinparam defaultFontName Helvetica',
            'skinparam defaultFontSize 11',
            'skinparam component {',
            '  BackgroundColor #E8F4FD',
            '  BorderColor #2E86AB',
            '  FontColor #1a1a1a',
            '}',
            'skinparam arrow {',
            '  Color #2E86AB',
            '}',
            'top to bottom direction',
            '',
        ]

        # Declarar módulos con colores según tipo
        for m in modules:
            if is_testbench(m.name):
                lines.append(f'component "{m.name}" as {m.name} #FFF3CD')
            elif m.name in root_modules:
                lines.append(f'component "{m.name}" as {m.name} #D4EDDA')

        lines.append('')

        # Relaciones
        added = set()
        for m in modules:
            for inst_name in m.instantiates:
                key = (m.name, inst_name)
                if key not in added:
                    lines.append(f'{m.name} --> {inst_name}')
                    added.add(key)

        lines.append('')
        lines.append('@enduml')

        return '\n'.join(lines)


# =============================================================================
# GENERADOR DE FICHERO .DOX
# =============================================================================

class DoxFileGenerator:
    """Genera el fichero .dox con la página Doxygen del diagrama de jerarquía."""

class HierarchyTreeGenerator:
    """Genera un árbol HTML colapsable estilo Vivado Sources."""

    def _is_testbench(self, name: str) -> bool:
        n = name.lower()
        return (n.startswith('tb_') or n.endswith('_tb') or
                'testbench' in n or n.startswith('tb'))

    def _build_tree_html(self, module_map: dict, name: str,
                         visited_path: set, depth: int = 0) -> str:
        """Genera el HTML de un nodo y sus hijos recursivamente."""
        mod = module_map.get(name.lower())
        is_tb = self._is_testbench(name)

        if is_tb:
            icon = '🟡'
            color = '#7a6000'
        elif depth == 0:
            icon = '🟢'
            color = '#1a5c2a'
        else:
            icon = '🔵'
            color = '#1a3a5c'

        has_children = mod and mod.instantiates
        toggle = 'class="toggle" onclick="toggleNode(this)"' if has_children else ''
        arrow = '▶ ' if has_children else '◾ '

        html = f'<li>\n'
        html += f'<span {toggle} style="color:{color};cursor:{"pointer" if has_children else "default"}">'
        html += f'{arrow}{icon} <a href="{{doxref_{name}}}">{name}</a>'
        if mod:
            html += f' <span style="font-size:0.85em;color:#888;">({mod.path.name})</span>'
        html += f'</span>\n'

        if has_children:
            html += '<ul class="subtree" style="display:none;">\n'
            # Evitar ciclos en la misma rama
            for inst in mod.instantiates:
                if inst.lower() not in visited_path:
                    new_path = visited_path | {inst.lower()}
                    html += self._build_tree_html(module_map, inst, new_path, depth + 1)
            html += '</ul>\n'

        html += '</li>\n'
        return html

    def generate_html(self, modules: list[VhdlModule]) -> str:
        module_map = {m.name.lower(): m for m in modules}

        # Detectar raíces
        all_instantiated = set()
        for m in modules:
            for inst in m.instantiates:
                all_instantiated.add(inst.lower())
        root_modules = [m for m in modules if m.name.lower() not in all_instantiated]

        # Generar columnas (una por raíz)
        columns_html = ''
        for root in root_modules:
            tree_html = self._build_tree_html(module_map, root.name, {root.name.lower()}, 0)
            columns_html += f'''
<div class="hier-column">
  <ul class="hier-tree">
    {tree_html}
  </ul>
</div>'''

        return f'''
<style>
.hier-container {{
  display: flex;
  flex-wrap: wrap;
  gap: 24px;
  font-family: monospace;
  font-size: 13px;
  margin: 16px 0;
}}
.hier-column {{
  min-width: 220px;
  background: var(--page-background-color, #fff);
  border: 1px solid var(--separator-color, #ddd);
  border-radius: 6px;
  padding: 10px 14px;
}}
.hier-tree, .subtree {{
  list-style: none;
  padding-left: 16px;
  margin: 2px 0;
}}
.hier-tree {{
  padding-left: 0;
}}
.toggle {{
  user-select: none;
}}
.toggle.open > span {{
  /* flecha girada */
}}
</style>
<script>
function toggleNode(el) {{
  var sub = el.nextElementSibling;
  if (!sub) return;
  var open = sub.style.display !== 'none';
  sub.style.display = open ? 'none' : 'block';
  el.innerHTML = el.innerHTML.replace(open ? '▼' : '▶', open ? '▶' : '▼');
}}
</script>
<div class="hier-container">
{columns_html}
</div>'''


class DoxFileGenerator:
    """Genera el fichero .dox con la página Doxygen del diagrama de jerarquía."""

    def generate(self, modules: list[VhdlModule]) -> str:
        # Árbol colapsable HTML
        tree_gen = HierarchyTreeGenerator()
        tree_html = tree_gen.generate_html(modules)

        # Tabla de módulos
        table_lines = [
            '| Module | File | Instantiates |',
            '|--------|------|--------------|',
        ]
        for m in sorted(modules, key=lambda x: x.name.lower()):
            inst_str = ', '.join(f'\\ref {i}' for i in m.instantiates) if m.instantiates else '—'
            table_lines.append(f'| \\ref {m.name} | `{m.path.name}` | {inst_str} |')

        table = '\n'.join(table_lines)

        dox = f'''/*!
\\page page_hierarchy DESIGN HIERARCHY

\\brief Jerarquía de instanciaciones del proyecto VHDL.

🟢 Módulo raíz (top-level) &nbsp;&nbsp; 🔵 Submódulo &nbsp;&nbsp; 🟡 Testbench

Haz click en los nodos con ▶ para expandir/colapsar.

\\htmlonly
{tree_html}
\\endhtmlonly

\\par Module List
{table}

*/
'''
        return dox


# =============================================================================
# ENTRY POINT
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description='Genera diagrama de jerarquía VHDL para Doxygen'
    )
    parser.add_argument(
        'project_path',
        help='Ruta raíz del proyecto VHDL (se recorre recursivamente)'
    )
    parser.add_argument(
        '--out',
        default='content/hierarchy.dox',
        help='Ruta del fichero .dox de salida (default: content/hierarchy.dox)'
    )
    args = parser.parse_args()

    project_path = Path(args.project_path)
    if not project_path.exists():
        print(f"[generate_hierarchy] Error: no existe la ruta {project_path}", file=sys.stderr)
        sys.exit(1)

    # Excluir carpetas de IPs y generadas
    EXCLUDE_DIRS = {'02-IPs', 'ip', '__pycache__', 'node_modules', '.git'}

    vhd_files = [
        f for f in list(project_path.rglob('*.vhd')) + list(project_path.rglob('*.vhdl'))
        if not any(part in EXCLUDE_DIRS for part in f.parts)
    ]

    if not vhd_files:
        print(f"[generate_hierarchy] No se encontraron ficheros .vhd en {project_path}", file=sys.stderr)
        sys.exit(1)

    print(f"[generate_hierarchy] Encontrados {len(vhd_files)} ficheros VHDL", file=sys.stderr)

    # Parsear todos los ficheros
    hierarchy_parser = HierarchyParser()
    all_modules = []
    for vhd_file in sorted(vhd_files):
        modules = hierarchy_parser.parse_file(vhd_file)
        all_modules.extend(modules)
        if modules:
            print(f"[generate_hierarchy]   {vhd_file.name}: {[m.name for m in modules]}", file=sys.stderr)

    if not all_modules:
        print("[generate_hierarchy] No se encontraron entidades VHDL", file=sys.stderr)
        sys.exit(1)

    # Generar árbol HTML y fichero .dox
    diagram = HierarchyWbsGenerator().generate(all_modules)
    dox_content = DoxFileGenerator().generate(all_modules)

    # Escribir el fichero de salida
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(dox_content, encoding='utf-8')

    print(f"[generate_hierarchy] Diagrama generado en {out_path}", file=sys.stderr)


if __name__ == '__main__':
    main()
