#!/usr/bin/env python3
"""
generate_drawio.py
==================
Genera un fichero Draw.io multi-página con el diagrama de bloques del proyecto VHDL.

Cada página representa un nivel de la jerarquía. En cada página aparecen los módulos
de ese nivel con sus puertos y las conexiones entre ellos según el port map.

Uso
---
    py -3.11 scripts/generate_drawio.py <ruta_proyecto> [--out <ruta_output>]

Ejemplo:
    py -3.11 scripts/generate_drawio.py ..
    py -3.11 scripts/generate_drawio.py .. --out docs/diagram.drawio

Requisitos
----------
    Python 3.11, pyGHDL en PYTHONPATH
"""

import re
import sys
import argparse
import xml.etree.ElementTree as ET
from pathlib import Path
from dataclasses import dataclass, field
from xml.dom import minidom


# =============================================================================
# ESTRUCTURAS DE DATOS
# =============================================================================

@dataclass
class Port:
    name: str
    direction: str   # in, out, inout, buffer
    type_str: str


@dataclass
class PortConnection:
    """Conexión en un port map: puerto_formal -> señal_actual"""
    formal: str      # nombre del puerto del módulo instanciado
    actual: str      # señal/puerto del módulo padre


@dataclass
class Instance:
    """Instanciación de un módulo dentro de otro"""
    label: str           # etiqueta de la instancia (u_i2c, etc.)
    entity_name: str     # nombre de la entidad instanciada
    connections: list[PortConnection] = field(default_factory=list)


@dataclass
class VhdlModule:
    name: str
    path: Path
    ports: list[Port] = field(default_factory=list)
    instances: list[Instance] = field(default_factory=list)
    architecture: str = ''


# =============================================================================
# PARSER VHDL (pyGHDL)
# =============================================================================

class VhdlParser:
    """Parsea ficheros VHDL usando pyGHDL para extraer módulos, puertos e instanciaciones."""

    def parse_file(self, path: Path) -> list[VhdlModule]:
        try:
            from pyGHDL.dom.NonStandard import Document
            from pyGHDL.dom.InterfaceItem import (
                PortSignalInterfaceItem,
            )
            from pyGHDL.dom.Concurrent import (
                EntityInstantiation,
                ComponentInstantiation,
            )
            from pyGHDL.dom.Concurrent import (
                EntityInstantiation,
                ComponentInstantiation,
            )
        except ImportError as e:
            print(f"[generate_drawio] pyGHDL no disponible: {e}", file=sys.stderr)
            return self._parse_regex(path)

        # Detectar codificación
        raw = path.read_bytes()
        if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
            source = raw.decode('utf-16')
        elif raw[:3] == b'\xef\xbb\xbf':
            source = raw.decode('utf-8-sig')
        else:
            source = raw.decode('utf-8', errors='replace')

        # Fichero temporal UTF-8 para pyGHDL si era UTF-16
        import tempfile, os
        tmp = None
        parse_path = path
        if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
            tmp = tempfile.NamedTemporaryFile(suffix='.vhd', delete=False,
                                              mode='w', encoding='utf-8')
            tmp.write(source)
            tmp.close()
            parse_path = Path(tmp.name)

        modules = []
        try:
            doc = Document(parse_path)
        except Exception as e:
            print(f"[generate_drawio] pyGHDL error en {path.name}: {e}", file=sys.stderr)
            if tmp:
                os.unlink(tmp.name)
            return self._parse_regex(path)
        finally:
            if tmp:
                try:
                    os.unlink(tmp.name)
                except:
                    pass

        for entity in doc.Entities:
            mod = VhdlModule(name=str(entity.Identifier), path=path)

            # Puertos
            for port in entity.PortItems:
                try:
                    direction = str(port.Mode).lower().replace('mode.', '')
                    type_str  = str(port.Subtype.SymbolName) if hasattr(port.Subtype, 'SymbolName') else str(port.Subtype)
                    mod.ports.append(Port(
                        name=str(port.Identifiers[0]),
                        direction=direction,
                        type_str=type_str,
                    ))
                except Exception:
                    pass

            # Arquitecturas e instanciaciones
            for arch in doc.Architectures:
                if str(arch.Entity).lower() != mod.name.lower():
                    continue
                mod.architecture = str(arch.Identifier)
                for stmt in arch.Statements:
                    inst = self._parse_instance(stmt, EntityInstantiation,
                                                ComponentInstantiation, PortAssociationItem)
                    if inst:
                        mod.instances.append(inst)

            modules.append(mod)

        return modules

    def _parse_instance(self, stmt, EntityInstantiation, ComponentInstantiation, PortAssociationItem):
        """Extrae una instanciación y sus conexiones de port map."""
        entity_name = None
        label = None

        if isinstance(stmt, EntityInstantiation):
            try:
                entity_name = str(stmt.Entity.EntityName)
                label = str(stmt.Label)
            except Exception:
                return None
        elif isinstance(stmt, ComponentInstantiation):
            try:
                entity_name = str(stmt.Component)
                label = str(stmt.Label)
            except Exception:
                return None
        else:
            return None

        inst = Instance(label=label or entity_name, entity_name=entity_name)

        # Port map
        try:
            for assoc in (stmt.PortMap or []):
                try:
                    formal = str(assoc.Formal) if assoc.Formal else ''
                    actual = str(assoc.Actual) if assoc.Actual else 'open'
                    inst.connections.append(PortConnection(formal=formal, actual=actual))
                except Exception:
                    pass
        except Exception:
            pass

        return inst

    def _parse_regex(self, path: Path) -> list[VhdlModule]:
        """Fallback con regex cuando pyGHDL falla."""
        try:
            raw = path.read_bytes()
            if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
                source = raw.decode('utf-16')
            else:
                source = raw.decode('utf-8', errors='replace')
        except Exception:
            return []

        source_clean = re.sub(r'--[^\n]*', '', source)
        modules = []

        RE_ENTITY = re.compile(r'\bentity\s+(\w+)\s+is\b', re.IGNORECASE)
        RE_PORT   = re.compile(
            r'(\w+(?:\s*,\s*\w+)*)\s*:\s*(in|out|inout|buffer)\s+([\w_\s()]+?)(?:;|\))',
            re.IGNORECASE
        )
        RE_INST   = re.compile(
            r'(\w+)\s*:\s*(?:entity\s+\w+\.)?(\w+)(?:\s*\(\w+\))?\s*port\s+map',
            re.IGNORECASE
        )

        for em in RE_ENTITY.finditer(source_clean):
            before = source_clean[max(0, em.start()-10):em.start()]
            if re.search(r'\bend\s*$', before, re.IGNORECASE):
                continue
            mod = VhdlModule(name=em.group(1), path=path)

            # Puertos
            port_section = re.search(r'\bport\s*\((.+?)\)\s*;', source_clean[em.start():],
                                      re.IGNORECASE | re.DOTALL)
            if port_section:
                for pm in RE_PORT.finditer(port_section.group(1)):
                    names = [n.strip() for n in pm.group(1).split(',')]
                    for n in names:
                        mod.ports.append(Port(
                            name=n,
                            direction=pm.group(2).lower(),
                            type_str=pm.group(3).strip(),
                        ))

            # Instanciaciones
            for im in RE_INST.finditer(source_clean[em.start():]):
                mod.instances.append(Instance(
                    label=im.group(1),
                    entity_name=im.group(2),
                ))

            modules.append(mod)

        return modules


# =============================================================================
# ANÁLISIS DE JERARQUÍA
# =============================================================================

class HierarchyAnalyzer:
    """Construye el árbol de jerarquía a partir de los módulos parseados."""

    def __init__(self, modules: list[VhdlModule]):
        self.modules = {m.name.lower(): m for m in modules}

    def find_roots(self) -> list[str]:
        """Módulos que no son instanciados por nadie (top-level)."""
        instantiated = set()
        for m in self.modules.values():
            for inst in m.instances:
                instantiated.add(inst.entity_name.lower())
        return [name for name in self.modules if name not in instantiated]

    def get_levels(self) -> list[list[str]]:
        """
        Devuelve los módulos organizados por niveles (BFS desde raíces).
        Nivel 0 = roots, Nivel 1 = sus hijos directos, etc.
        """
        roots = self.find_roots()
        if not roots:
            return [list(self.modules.keys())]

        levels = []
        visited = set()
        current_level = roots[:]

        while current_level:
            levels.append(current_level[:])
            visited.update(n.lower() for n in current_level)
            next_level = []
            for name in current_level:
                mod = self.modules.get(name.lower())
                if not mod:
                    continue
                for inst in mod.instances:
                    child = inst.entity_name.lower()
                    if child in self.modules and child not in visited:
                        if child not in next_level:
                            next_level.append(child)
            current_level = next_level

        return levels


# =============================================================================
# GENERADOR DRAW.IO XML
# =============================================================================

# Colores
COLOR_MODULE_HEADER = '#4a4a4a'
COLOR_MODULE_BG     = '#f5f5f5'
COLOR_PORT_IN       = '#dae8fc'
COLOR_PORT_OUT      = '#d5e8d4'
COLOR_PORT_INOUT    = '#fff2cc'
COLOR_WIRE          = '#2E86AB'
COLOR_ROOT_BG       = '#d5e8d4'

# Dimensiones
MODULE_W        = 220
PORT_H          = 24
HEADER_H        = 32
MODULE_SPACING_X = 320
MODULE_SPACING_Y = 60
PAGE_MARGIN_X   = 80
PAGE_MARGIN_Y   = 60


class DrawioGenerator:

    def __init__(self, analyzer: HierarchyAnalyzer):
        self.analyzer = analyzer
        self._cell_id = 1

    def next_id(self) -> str:
        self._cell_id += 1
        return str(self._cell_id)

    def generate(self) -> str:
        """Genera el XML completo del fichero Draw.io."""
        levels = self.analyzer.get_levels()

        root_el = ET.Element('mxGraphModel')
        root_el.set('dx', '1422')
        root_el.set('dy', '762')
        root_el.set('grid', '1')
        root_el.set('gridSize', '10')
        root_el.set('guides', '1')
        root_el.set('tooltips', '1')
        root_el.set('connect', '1')
        root_el.set('arrows', '1')
        root_el.set('fold', '1')
        root_el.set('page', '1')
        root_el.set('pageScale', '1')
        root_el.set('pageWidth', '1169')
        root_el.set('pageHeight', '827')
        root_el.set('math', '0')
        root_el.set('shadow', '0')

        # Crear diagrama multi-página
        mxfile = ET.Element('mxfile')
        mxfile.set('host', 'app.diagrams.net')

        for level_idx, level_modules in enumerate(levels):
            diagram = ET.SubElement(mxfile, 'diagram')
            diagram.set('name', f'Level {level_idx} — {", ".join(level_modules[:3])}{"..." if len(level_modules) > 3 else ""}')
            diagram.set('id', f'level_{level_idx}')

            graph_model = ET.SubElement(diagram, 'mxGraphModel')
            graph_model.set('dx', '1422')
            graph_model.set('dy', '762')
            graph_model.set('grid', '1')
            graph_model.set('gridSize', '10')
            graph_model.set('guides', '1')
            graph_model.set('tooltips', '1')
            graph_model.set('connect', '1')
            graph_model.set('arrows', '1')
            graph_model.set('fold', '1')
            graph_model.set('page', str(level_idx + 1))
            graph_model.set('pageScale', '1')
            graph_model.set('pageWidth', '1654')
            graph_model.set('pageHeight', '1169')
            graph_model.set('math', '0')
            graph_model.set('shadow', '0')

            parent = ET.SubElement(graph_model, 'root')
            ET.SubElement(parent, 'mxCell', id='0')
            ET.SubElement(parent, 'mxCell', id='1', parent='0')

            self._add_level_page(parent, level_modules, level_idx, levels)

        # Serializar
        xml_str = ET.tostring(mxfile, encoding='unicode')
        dom = minidom.parseString(xml_str)
        return dom.toprettyxml(indent='  ', encoding=None)

    def _add_level_page(self, parent, level_modules, level_idx, all_levels):
        """Añade todos los módulos de un nivel a la página."""
        modules = self.analyzer.modules
        is_root = (level_idx == 0)

        # Calcular posiciones de módulos
        positions = {}
        x = PAGE_MARGIN_X
        for mod_name in level_modules:
            mod = modules.get(mod_name.lower())
            if not mod:
                continue
            n_ports = len(mod.ports)
            h = HEADER_H + max(n_ports, 1) * PORT_H + 10
            positions[mod_name.lower()] = (x, PAGE_MARGIN_Y, MODULE_W, h)
            x += MODULE_W + MODULE_SPACING_X

        # Dibujar módulos
        port_cell_ids = {}  # (mod_name, port_name) -> cell_id
        for mod_name in level_modules:
            mod = modules.get(mod_name.lower())
            if not mod:
                continue
            mx, my, mw, mh = positions[mod_name.lower()]
            ids = self._draw_module(parent, mod, mx, my, mw, mh,
                                    is_root, level_idx, len(all_levels))
            port_cell_ids.update(ids)

        # Dibujar conexiones entre módulos del nivel actual
        # Buscar módulos del nivel anterior que instancian a los del nivel actual
        if level_idx > 0:
            prev_level = all_levels[level_idx - 1]
            for parent_name in prev_level:
                parent_mod = modules.get(parent_name.lower())
                if not parent_mod:
                    continue
                for inst in parent_mod.instances:
                    child_name = inst.entity_name.lower()
                    if child_name not in [m.lower() for m in level_modules]:
                        continue
                    child_mod = modules.get(child_name)
                    if not child_mod:
                        continue
                    # Dibujar cables según port map
                    for conn in inst.connections:
                        src_key = (parent_name.lower(), conn.actual.lower())
                        dst_key = (child_name, conn.formal.lower())
                        src_id = port_cell_ids.get(src_key)
                        dst_id = port_cell_ids.get(dst_key)
                        if src_id and dst_id:
                            self._draw_wire(parent, src_id, dst_id, conn.actual)

    def _draw_module(self, parent, mod: VhdlModule, x, y, w, h,
                     is_root, level_idx, total_levels) -> dict:
        """Dibuja un módulo con header y puertos. Devuelve dict (mod,port)->cell_id."""
        port_ids = {}
        bg = COLOR_ROOT_BG if is_root else COLOR_MODULE_BG

        # Contenedor del módulo
        container_id = self.next_id()
        cell = ET.SubElement(parent, 'mxCell')
        cell.set('id', container_id)
        cell.set('value', '')
        cell.set('style', f'rounded=1;whiteSpace=wrap;html=1;fillColor={bg};strokeColor=#666666;fontSize=11;verticalAlign=top;')
        cell.set('vertex', '1')
        cell.set('parent', '1')
        geo = ET.SubElement(cell, 'mxGeometry')
        geo.set('x', str(x))
        geo.set('y', str(y))
        geo.set('width', str(w))
        geo.set('height', str(h))
        geo.set('as', 'geometry')

        # Header con nombre del módulo
        header_id = self.next_id()
        cell = ET.SubElement(parent, 'mxCell')
        cell.set('id', header_id)
        cell.set('value', f'<b>{mod.name}</b>')
        cell.set('style', f'rounded=0;whiteSpace=wrap;html=1;fillColor={COLOR_MODULE_HEADER};fontColor=#ffffff;strokeColor=none;fontSize=12;fontStyle=1;')
        cell.set('vertex', '1')
        cell.set('parent', container_id)
        geo = ET.SubElement(cell, 'mxGeometry')
        geo.set('x', '0')
        geo.set('y', '0')
        geo.set('width', str(w))
        geo.set('height', str(HEADER_H))
        geo.set('as', 'geometry')

        # Puertos
        inputs  = [p for p in mod.ports if p.direction in ('in', 'inout')]
        outputs = [p for p in mod.ports if p.direction in ('out', 'buffer')]

        # Inputs (izquierda)
        for i, port in enumerate(inputs):
            port_id = self.next_id()
            py_pos = HEADER_H + i * PORT_H + 5
            color = COLOR_PORT_IN if port.direction == 'in' else COLOR_PORT_INOUT
            cell = ET.SubElement(parent, 'mxCell')
            cell.set('id', port_id)
            cell.set('value', f'→ {port.name}')
            cell.set('style', f'rounded=0;whiteSpace=wrap;html=1;fillColor={color};strokeColor=#aaaaaa;fontSize=10;align=left;spacingLeft=4;')
            cell.set('vertex', '1')
            cell.set('parent', container_id)
            geo = ET.SubElement(cell, 'mxGeometry')
            geo.set('x', '0')
            geo.set('y', str(py_pos))
            geo.set('width', str(w // 2 - 2))
            geo.set('height', str(PORT_H - 2))
            geo.set('as', 'geometry')
            port_ids[(mod.name.lower(), port.name.lower())] = port_id

        # Outputs (derecha)
        for i, port in enumerate(outputs):
            port_id = self.next_id()
            py_pos = HEADER_H + i * PORT_H + 5
            cell = ET.SubElement(parent, 'mxCell')
            cell.set('id', port_id)
            cell.set('value', f'{port.name} →')
            cell.set('style', f'rounded=0;whiteSpace=wrap;html=1;fillColor={COLOR_PORT_OUT};strokeColor=#aaaaaa;fontSize=10;align=right;spacingRight=4;')
            cell.set('vertex', '1')
            cell.set('parent', container_id)
            geo = ET.SubElement(cell, 'mxGeometry')
            geo.set('x', str(w // 2 + 2))
            geo.set('y', str(py_pos))
            geo.set('width', str(w // 2 - 2))
            geo.set('height', str(PORT_H - 2))
            geo.set('as', 'geometry')
            port_ids[(mod.name.lower(), port.name.lower())] = port_id

        # Enlace a página del nivel inferior si tiene instanciaciones
        if mod.instances and level_idx < total_levels - 1:
            link_id = self.next_id()
            cell = ET.SubElement(parent, 'mxCell')
            cell.set('id', link_id)
            cell.set('value', '▶ ver interior')
            cell.set('style', 'text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;fontSize=10;fontColor=#2E86AB;fontStyle=4;')
            cell.set('vertex', '1')
            cell.set('parent', container_id)
            geo = ET.SubElement(cell, 'mxGeometry')
            geo.set('x', str(w // 2 - 50))
            geo.set('y', str(h - HEADER_H - 4))
            geo.set('width', '100')
            geo.set('height', str(HEADER_H))
            geo.set('as', 'geometry')

        return port_ids

    def _draw_wire(self, parent, src_id: str, dst_id: str, label: str):
        """Dibuja un cable entre dos puertos."""
        wire_id = self.next_id()
        cell = ET.SubElement(parent, 'mxCell')
        cell.set('id', wire_id)
        cell.set('value', label if label and label != 'open' else '')
        cell.set('style', f'edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;strokeColor={COLOR_WIRE};fontSize=9;')
        cell.set('edge', '1')
        cell.set('source', src_id)
        cell.set('target', dst_id)
        cell.set('parent', '1')
        geo = ET.SubElement(cell, 'mxGeometry')
        geo.set('relative', '1')
        geo.set('as', 'geometry')


# =============================================================================
# ENTRY POINT
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description='Genera diagrama de bloques Draw.io del proyecto VHDL'
    )
    parser.add_argument(
        'project_path',
        help='Ruta raíz del proyecto VHDL (se recorre recursivamente)'
    )
    parser.add_argument(
        '--out',
        default='docs/diagram.drawio',
        help='Ruta del fichero .drawio de salida (default: docs/diagram.drawio)'
    )
    args = parser.parse_args()

    project_path = Path(args.project_path)
    if not project_path.exists():
        print(f"[generate_drawio] Error: no existe {project_path}", file=sys.stderr)
        sys.exit(1)

    # Excluir carpetas de IPs y generadas
    EXCLUDE_DIRS = {'02-IPs', 'ip', '__pycache__', 'node_modules', '.git'}

    vhd_files = [
        f for f in list(project_path.rglob('*.vhd')) + list(project_path.rglob('*.vhdl'))
        if not any(part in EXCLUDE_DIRS for part in f.parts)
    ]

    if not vhd_files:
        print(f"[generate_drawio] No se encontraron ficheros VHDL en {project_path}", file=sys.stderr)
        sys.exit(1)

    print(f"[generate_drawio] Encontrados {len(vhd_files)} ficheros VHDL", file=sys.stderr)

    # Parsear
    vhdl_parser = VhdlParser()
    all_modules = []
    for f in sorted(vhd_files):
        mods = vhdl_parser.parse_file(f)
        all_modules.extend(mods)
        if mods:
            print(f"[generate_drawio]   {f.name}: {[m.name for m in mods]}", file=sys.stderr)

    if not all_modules:
        print("[generate_drawio] No se encontraron entidades VHDL", file=sys.stderr)
        sys.exit(1)

    # Analizar jerarquía
    analyzer = HierarchyAnalyzer(all_modules)
    levels = analyzer.get_levels()
    print(f"[generate_drawio] {len(levels)} niveles de jerarquía detectados", file=sys.stderr)
    for i, lvl in enumerate(levels):
        print(f"[generate_drawio]   Nivel {i}: {lvl}", file=sys.stderr)

    # Generar Draw.io
    generator = DrawioGenerator(analyzer)
    xml_content = generator.generate()

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(xml_content, encoding='utf-8')
    print(f"[generate_drawio] Diagrama generado en {out_path}", file=sys.stderr)


if __name__ == '__main__':
    main()
