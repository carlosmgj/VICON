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
    name: str                          # nombre de la entidad
    path: Path                         # ruta del fichero fuente
    instantiates: list[str] = field(default_factory=list)  # entidades que instancia
    architecture: str = ''  # nombre de la arquitectura

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
    _RE_ENTITY_INST = re.compile(
        r':\s*entity\s+\w+\.(\w+)\s*(?:generic|port|\n)',
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
        """
        Parsea un fichero VHDL y devuelve los módulos (entidades) encontrados
        con sus instanciaciones.
        """
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

            # 1. Instanciaciones directas: entity work.X o entity lib.X
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
# GENERADOR DE DIAGRAMA PLANTUML
# =============================================================================

class HierarchyDiagramGenerator:
    """
    Genera el diagrama PlantUML de jerarquía a partir de los módulos extraídos.
    """

    def generate(self, modules: list[VhdlModule]) -> str:
        """
        Genera el string PlantUML del diagrama de jerarquía.
        Las flechas representan instanciaciones: A --> B significa A instancia B.
        Los módulos raíz (no instanciados por nadie) se marcan en verde.
        """
        # Detectar módulos raíz (no instanciados por ningún otro módulo)
        all_instantiated = set()
        for m in modules:
            for inst in m.instantiates:
                all_instantiated.add(inst.lower())

        root_modules = {m.name for m in modules if m.name.lower() not in all_instantiated}

        lines = [
            '@startuml',
            'skinparam componentStyle rectangle',
            'skinparam defaultFontName Helvetica',
            'skinparam component {',
            '  BackgroundColor #E8F4FD',
            '  BorderColor #2E86AB',
            '  FontColor #1a1a1a',
            '}',
            'skinparam arrow {',
            '  Color #2E86AB',
            '  FontColor #1a1a1a',
            '}',
            'left to right direction',
            '',
        ]

        # Declarar módulos raíz con color verde
        for m in modules:
            if m.name in root_modules:
                lines.append(f'component "{m.name}" as {m.name} #D4EDDA')

        lines.append('')

        # Generar relaciones de instanciación
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

    def generate(self, plantuml_diagram: str, modules: list[VhdlModule]) -> str:
        """
        Genera el contenido del fichero .dox con:
          - Página Doxygen con título y descripción
          - Diagrama PlantUML de jerarquía
          - Tabla de módulos con sus ficheros fuente e instanciaciones
        """
        # Tabla de módulos
        table_lines = [
            '| Module | File | Instantiates |',
            '|--------|------|--------------|',
        ]
        for m in sorted(modules, key=lambda x: x.name.lower()):
            inst_str = ', '.join(f'`{i}`' for i in m.instantiates) if m.instantiates else '—'
            table_lines.append(f'| `{m.name}` | `{m.path.name}` | {inst_str} |')

        table = '\n'.join(table_lines)

        dox = f'''/*!
\\page page_hierarchy DESIGN HIERARCHY

\\brief Jerarquía de instanciaciones del proyecto VHDL.

Este diagrama muestra la jerarquía de instanciaciones entre las entidades
del proyecto. Los módulos en verde son los módulos raíz (top-level),
es decir, los que no son instanciados por ningún otro módulo.

\\par Hierarchy Diagram
\\startuml
{plantuml_diagram}
\\enduml

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

    # Recoger todos los ficheros VHDL recursivamente
    vhd_files = list(project_path.rglob('*.vhd')) + list(project_path.rglob('*.vhdl'))

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

    # Generar diagrama y fichero .dox
    diagram = HierarchyDiagramGenerator().generate(all_modules)
    dox_content = DoxFileGenerator().generate(diagram, all_modules)

    # Escribir el fichero de salida
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(dox_content, encoding='utf-8')

    print(f"[generate_hierarchy] Diagrama generado en {out_path}", file=sys.stderr)


if __name__ == '__main__':
    main()
