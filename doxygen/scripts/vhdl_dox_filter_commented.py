#!/usr/bin/env python3
"""
vhdl_dox_filter.py
==================
Filtro de entrada (INPUT_FILTER) de Doxygen para ficheros VHDL.

Funcionamiento general
----------------------
Doxygen invoca este script pasándole la ruta de cada fichero .vhd como
argumento. El script lo procesa y escribe por stdout el fichero enriquecido
con bloques de documentación Doxygen autogenerados. Doxygen lee esa salida
como si fuera el fichero original.

Qué genera automáticamente (sin tocar el código VHDL):
  - Tabla de genéricos
  - Tabla de puertos con dirección, tipo, valor por defecto y descripción
  - Diagrama de entidad PlantUML (caja con entradas/salidas y señales internas)
  - Tabla de señales internas (excluye señales next_* de FSM)
  - Tabla de constantes
  - Diagrama de estados PlantUML (FSM detectada automáticamente)

Qué conserva del fichero original sin modificar:
  - Todos los comentarios --! existentes
  - Bloques \\htmlonly...\\endhtmlonly (p.ej. WaveDrom)
  - Bloques \\startuml...\\enduml escritos manualmente

Convención de comentarios en el .vhd
--------------------------------------
El ingeniero escribe únicamente:
  1. \\brief  en el comentario de la entidad  → título de la página
  2. \\htmlonly con WaveDrom (opcional)        → timing diagram

El script genera todo lo demás automáticamente desde el AST.

Ejemplo mínimo en el .vhd:
  --! \\brief Mi módulo con FSM
  --! \\htmlonly
  --! <script type="WaveDrom">{ "signal": [...] }</script>
  --! \\endhtmlonly
  entity mi_modulo is
      port (
          clk : in std_logic; --! Reloj del sistema
          ...
      );

Uso en Doxyfile
---------------
  FILTER_PATTERNS = *.vhd="py -3.11 scripts/vhdl_dox_filter.py" \\
                    *.vhdl="py -3.11 scripts/vhdl_dox_filter.py"

Requisitos
----------
  - Python 3.11
  - GHDL 6.x instalado y en el PATH del sistema
  - pyGHDL source clonado en C:\\tools\\ghdl-src-6 (añadido a PYTHONPATH)
  - pyTooling, pyVHDLModel instalados con pip en Python 3.11
  - PlantUML .jar en C:\\tools\\plantuml.jar
  - Java en el PATH del sistema (para que Doxygen invoque PlantUML)
"""

import sys
import re
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional


# =============================================================================
# ESTRUCTURAS DE DATOS
# =============================================================================
# Representación interna de los elementos VHDL extraídos del AST.
# Cada dataclass mapea a un elemento del lenguaje.

@dataclass
class Port:
    """Puerto de una entidad VHDL (señal de la interfaz)."""
    name: str
    direction: str       # "in", "out", "inout" o "buffer"
    type_str: str        # tipo VHDL, p.ej. "std_logic" o "std_logic_vector"
    default: Optional[str] = None   # valor por defecto (:= ...) si existe
    comment: Optional[str] = None   # comentario --! inline en el .vhd


@dataclass
class Generic:
    """Parámetro genérico de una entidad VHDL."""
    name: str
    type_str: str
    default: Optional[str] = None
    comment: Optional[str] = None


@dataclass
class Signal:
    """Señal interna declarada en la sección declarativa de la arquitectura."""
    name: str
    type_str: str
    default: Optional[str] = None
    comment: Optional[str] = None


@dataclass
class Constant:
    """Constante declarada en la sección declarativa de la arquitectura."""
    name: str
    type_str: str
    value: str           # valor de la constante (:= ...)
    comment: Optional[str] = None


@dataclass
class EnumType:
    """Tipo enumerado VHDL. Se usa para detectar FSMs."""
    name: str
    states: list[str]    # lista de literales del enum, en orden de declaración


@dataclass
class FsmTransition:
    """Transición entre estados de una FSM detectada en el código."""
    from_state: str
    to_state: str
    condition: Optional[str] = None   # condición del if que guarda la transición


@dataclass
class VhdlEntity:
    """Representación completa de una entidad VHDL y su arquitectura."""
    name: str
    generics: list[Generic]               = field(default_factory=list)
    ports: list[Port]                     = field(default_factory=list)
    signals: list[Signal]                 = field(default_factory=list)
    constants: list[Constant]             = field(default_factory=list)
    enum_types: list[EnumType]            = field(default_factory=list)
    fsm_transitions: list[FsmTransition]  = field(default_factory=list)


# =============================================================================
# FUNCIONES AUXILIARES
# =============================================================================

def _build_comment_map(source: str) -> dict[int, str]:
    """
    Construye un diccionario {número_de_línea: texto_comentario} a partir
    del fuente VHDL.

    pyGHDL no expone los comentarios del fuente en su AST, así que los
    extraemos manualmente por número de línea. Esto nos permite asociar el
    comentario --! inline de cada declaración con el elemento que documenta.

    Solo se recogen líneas con comentarios que no sean comandos Doxygen
    (es decir, que no empiecen por \\), para evitar capturar \\brief,
    \\startuml, etc. como descripciones de elementos.
    """
    comment_map = {}
    for i, line in enumerate(source.splitlines(), start=1):
        m = re.search(r'--!\s*(.+)$', line)
        if m:
            text = m.group(1).strip()
            if not text.startswith('\\'):
                comment_map[i] = text
    return comment_map


def _clean(name: str) -> str:
    """
    Limpia el nombre de un elemento VHDL devuelto por pyGHDL.

    pyGHDL añade '?' a los nombres que no ha podido resolver completamente
    (referencias externas, tipos de packages no cargados, etc.).
    En modo documentación esto es normal y no indica un error — simplemente
    eliminamos el '?' para que el output quede limpio.
    """
    return str(name).replace('?', '').strip()


def _format_condition(cond) -> str:
    """
    Formatea una condición de un IfStatement del AST de pyGHDL como
    string VHDL legible.

    Para condiciones de tipo EqualExpression (p.ej. and_out = '1'),
    reconstruye la expresión con el formato correcto incluyendo las
    comillas simples de los CharacterLiteral.

    Para otros tipos de condición, usa la representación str() por defecto.
    """
    try:
        from pyGHDL.dom.Expression import EqualExpression
        from pyGHDL.dom.Literal import CharacterLiteral
        if isinstance(cond, EqualExpression):
            left = _clean(str(cond.LeftOperand))
            right = cond.RightOperand
            if isinstance(right, CharacterLiteral):
                # CharacterLiteral.Value devuelve el carácter sin comillas
                return f"{left} = '{right.Value}'"
            return f"{left} = {_clean(str(right))}"
    except Exception:
        pass
    return _clean(str(cond))


# =============================================================================
# PARSER VHDL (pyGHDL)
# =============================================================================

class GhdlParser:
    """
    Parser VHDL basado en pyGHDL (AST real del compilador GHDL).

    A diferencia de un parser basado en regex, pyGHDL entiende la gramática
    completa de VHDL-2008 y produce un árbol de sintaxis abstracta (AST)
    tipado. Esto garantiza que la extracción de puertos, señales, tipos y
    transiciones FSM es correcta incluso con sintaxis compleja.

    Limitación: pyGHDL necesita el binario de GHDL instalado para funcionar,
    y en modo documentación no resuelve referencias a packages externos
    (de ahí los '?' en algunos nombres de tipos).
    """

    def parse(self, path: Path, source: str) -> Optional[VhdlEntity]:
        """
        Parsea el fichero VHDL en 'path' y devuelve un VhdlEntity con
        toda la información extraída, o None si el fichero no contiene
        una entidad (p.ej. packages, contextos, testbenches sin entidad).
        """
        # Importaciones locales para que el ImportError sea capturable
        # si pyGHDL no está disponible en el entorno
        from pyGHDL.dom.NonStandard import Document
        from pyGHDL.dom.Object import Signal as GhdlSignal, Constant as GhdlConstant
        from pyGHDL.dom.Type import EnumeratedType
        from pyGHDL.dom.Concurrent import ProcessStatement
        from pyGHDL.dom.Sequential import (
            CaseStatement,
            SequentialSimpleSignalAssignment,
            IfStatement,
        )

        try:
            doc = Document(path)
        except Exception as e:
            # pyGHDL lanza excepciones para ficheros no-VHDL (.dox, etc.)
            # En ese caso devolvemos None y el fichero pasa sin modificar
            print(f"[vhdl_dox_filter] pyGHDL error en {path}: {e}", file=sys.stderr)
            return None

        if not doc.Entities:
            return None

        # Mapa de comentarios para recuperar las descripciones inline
        comment_map = _build_comment_map(source)

        # Tomamos la primera (y normalmente única) entidad del fichero
        entity_name, ghdl_entity = next(iter(doc.Entities.items()))
        entity = VhdlEntity(name=_clean(entity_name))

        # --- Genéricos ---
        # ghdl_entity.GenericItems devuelve los parámetros genéricos
        for g in ghdl_entity.GenericItems:
            for ident in g.Identifiers:
                line = getattr(g, 'Position', None)
                line_no = line.Line if line else None
                entity.generics.append(Generic(
                    name=_clean(ident),
                    type_str=_clean(g.Subtype),
                    default=_clean(g.DefaultExpression) if g.DefaultExpression else None,
                    comment=comment_map.get(line_no),
                ))

        # --- Puertos ---
        # ghdl_entity.PortItems devuelve los puertos de la entidad
        for p in ghdl_entity.PortItems:
            for ident in p.Identifiers:
                line = getattr(p, 'Position', None)
                line_no = line.Line if line else None
                entity.ports.append(Port(
                    name=_clean(ident),
                    direction=_clean(p.Mode).lower(),
                    type_str=_clean(p.Subtype),
                    default=_clean(p.DefaultExpression) if p.DefaultExpression else None,
                    comment=comment_map.get(line_no),
                ))

        # --- Arquitectura ---
        if not doc.Architectures:
            return entity

        # doc.Architectures es un dict {entity_name: {arch_name: arch}}
        _, archs = next(iter(doc.Architectures.items()))
        _, arch  = next(iter(archs.items()))

        # arch.DeclaredItems contiene todo lo declarado entre "is" y "begin"
        for item in arch.DeclaredItems:
            line = getattr(item, 'Position', None)
            line_no = line.Line if line else None

            if isinstance(item, GhdlSignal):
                for ident in item.Identifiers:
                    entity.signals.append(Signal(
                        name=_clean(ident),
                        type_str=_clean(item.Subtype),
                        default=_clean(item.DefaultExpression) if item.DefaultExpression else None,
                        comment=comment_map.get(line_no),
                    ))

            elif isinstance(item, GhdlConstant):
                for ident in item.Identifiers:
                    entity.constants.append(Constant(
                        name=_clean(ident),
                        type_str=_clean(item.Subtype),
                        value=_clean(item.DefaultExpression) if item.DefaultExpression else '?',
                        comment=comment_map.get(line_no),
                    ))

            elif isinstance(item, EnumeratedType):
                # Los tipos enumerados son la base de detección de FSMs
                entity.enum_types.append(EnumType(
                    name=_clean(item.Identifier),
                    states=[_clean(lit) for lit in item.Literals],
                ))

        # --- Detección de FSM ---
        # Patrón: existe un tipo enum + una señal de ese tipo (sin "next" en el nombre)
        enum_names = {t.name.lower() for t in entity.enum_types}
        state_signals = {
            s.name.lower() for s in entity.signals
            if s.type_str.lower() in enum_names and 'next' not in s.name.lower()
        }

        if state_signals:
            # arch.Statements contiene los procesos y asignaciones concurrentes
            entity.fsm_transitions = self._extract_fsm(
                arch.Statements, state_signals,
                CaseStatement, SequentialSimpleSignalAssignment, IfStatement
            )

        return entity

    def _extract_fsm(self, statements, state_signals,
                     CaseStatement, SequentialSimpleSignalAssignment, IfStatement):
        """
        Extrae las transiciones FSM buscando el patrón:
          process(...)
            case <señal_de_estado> is
              when ESTADO_A =>
                if <condición> then
                  next_state <= ESTADO_B;   -- transición condicional
                end if;
              when ESTADO_C =>
                next_state <= ESTADO_D;     -- transición incondicional
            end case;

        Devuelve una lista de FsmTransition con el estado origen, destino
        y la condición (si la hay).
        """
        transitions = []

        for stmt in statements:
            # Solo buscamos dentro de procesos (ProcessStatement)
            proc_stmts = getattr(stmt, 'Statements', [])
            for s in proc_stmts:
                if not isinstance(s, CaseStatement):
                    continue

                # Verificar que el case es sobre una señal de estado FSM
                case_expr = _clean(str(s._expression)).lower()
                if not any(sig in case_expr for sig in state_signals):
                    continue

                # Recorrer cada rama "when ESTADO =>"
                for branch in s.Cases:
                    choices = getattr(branch, 'Choices', [])
                    if not choices:
                        continue
                    from_state = _clean(str(choices[0].Expression))
                    if from_state.upper() in ('OTHERS', 'NULL', ''):
                        continue

                    for bs in branch.Statements:
                        # Transición condicional: if cond then next_state <= X
                        if isinstance(bs, IfStatement):
                            condition = _format_condition(bs.IfBranch._condition)
                            for ifs in bs.IfBranch.Statements:
                                if isinstance(ifs, SequentialSimpleSignalAssignment):
                                    target = _clean(str(ifs.Target))
                                    if 'next' in target.lower():
                                        for wave in ifs.Waveform:
                                            to_state = _clean(str(wave.Expression))
                                            transitions.append(FsmTransition(
                                                from_state=from_state,
                                                to_state=to_state,
                                                condition=condition,
                                            ))

                        # Transición incondicional: next_state <= X (sin if)
                        elif isinstance(bs, SequentialSimpleSignalAssignment):
                            target = _clean(str(bs.Target))
                            if 'next' in target.lower():
                                for wave in bs.Waveform:
                                    to_state = _clean(str(wave.Expression))
                                    transitions.append(FsmTransition(
                                        from_state=from_state,
                                        to_state=to_state,
                                        condition=None,
                                    ))

        return transitions


# =============================================================================
# GENERADOR DE BLOQUES DOXYGEN
# =============================================================================

class DoxygenGenerator:
    """
    Genera los bloques de documentación Doxygen a partir de un VhdlEntity.

    Cada método privado genera una sección (tabla o diagrama) como string
    con líneas --! listas para ser insertadas en el fuente VHDL.
    """

    def generate(self, entity: VhdlEntity, existing_uml: bool = False) -> str:
        """
        Genera el bloque completo de documentación para la entidad.

        existing_uml: si True, el comentario de la entidad ya contiene un
        bloque \\startuml manual (p.ej. WaveDrom convertido). En ese caso
        no se genera el diagrama de entidad automático para evitar duplicados.
        """
        blocks = []

        if entity.generics:
            blocks.append(self._generic_table(entity.generics))

        blocks.append(self._port_table(entity.ports))

        # Solo generar el diagrama de entidad si no hay uno manual
        if not existing_uml:
            blocks.append(self._entity_diagram(entity))

        # Filtrar señales next_* (internas de FSM, no relevantes para el usuario)
        visible_signals = [s for s in entity.signals if 'next' not in s.name.lower()]
        if visible_signals:
            blocks.append(self._signal_table(visible_signals))

        if entity.constants:
            blocks.append(self._constant_table(entity.constants))

        if entity.fsm_transitions:
            blocks.append(self._fsm_diagram(entity))

        return '\n'.join(blocks) + '\n'

    # -------------------------------------------------------------------------
    # Tablas Markdown
    # -------------------------------------------------------------------------

    def _port_table(self, ports: list[Port]) -> str:
        """Tabla de puertos con dirección, tipo, valor por defecto y descripción."""
        lines = [
            '--! \\par Ports',
            '--! | Name | Direction | Type | Default | Description |',
            '--! |------|:---------:|------|---------|-------------|',
        ]
        for p in ports:
            default = f'`{p.default}`' if p.default else '—'
            comment = p.comment or ''
            lines.append(
                f'--! | `{p.name}` | `{p.direction}` | `{p.type_str}` | {default} | {comment} |'
            )
        lines.append('--!')
        return '\n'.join(lines)

    def _generic_table(self, generics: list[Generic]) -> str:
        """Tabla de genéricos con tipo, valor por defecto y descripción."""
        lines = [
            '--! \\par Generics',
            '--! | Name | Type | Default | Description |',
            '--! |------|------|---------|-------------|',
        ]
        for g in generics:
            default = f'`{g.default}`' if g.default else '—'
            comment = g.comment or ''
            lines.append(
                f'--! | `{g.name}` | `{g.type_str}` | {default} | {comment} |'
            )
        lines.append('--!')
        return '\n'.join(lines)

    def _signal_table(self, signals: list[Signal]) -> str:
        """Tabla de señales internas (ya filtradas, sin next_*)."""
        lines = [
            '--! \\par Internal Signals',
            '--! | Name | Type | Default | Description |',
            '--! |------|------|---------|-------------|',
        ]
        for s in signals:
            default = f'`{s.default}`' if s.default else '—'
            comment = s.comment or ''
            lines.append(
                f'--! | `{s.name}` | `{s.type_str}` | {default} | {comment} |'
            )
        lines.append('--!')
        return '\n'.join(lines)

    def _constant_table(self, constants: list[Constant]) -> str:
        """Tabla de constantes con tipo, valor y descripción."""
        lines = [
            '--! \\par Constants',
            '--! | Name | Type | Value | Description |',
            '--! |------|------|-------|-------------|',
        ]
        for c in constants:
            comment = c.comment or ''
            lines.append(
                f'--! | `{c.name}` | `{c.type_str}` | `{c.value}` | {comment} |'
            )
        lines.append('--!')
        return '\n'.join(lines)

    # -------------------------------------------------------------------------
    # Diagramas PlantUML
    # -------------------------------------------------------------------------

    def _entity_diagram(self, entity: VhdlEntity) -> str:
        """
        Diagrama de componente PlantUML con:
          - Puertos de entrada como interfaces a la izquierda
          - Puertos de salida como interfaces a la derecha
          - Nota con señales internas, tipos enum (estados FSM) y constantes
        """
        inputs  = [p for p in entity.ports if p.direction in ('in', 'inout')]
        outputs = [p for p in entity.ports if p.direction in ('out', 'buffer', 'inout')]

        lines = [
            '--! \\par Entity Diagram',
            '--! \\startuml',
            '--! skinparam componentStyle rectangle',
            '--! skinparam defaultFontName Helvetica',
            '--! skinparam component {',
            '--!   BackgroundColor #E8F4FD',
            '--!   BorderColor #2E86AB',
            '--! }',
            '--! left to right direction',
            '--!',
        ]

        # Declarar interfaces de entrada y salida
        for p in inputs:
            lines.append(f'--! () "{p.name}\\n[{p.type_str}]" as i_{p.name}')
        for p in outputs:
            lines.append(f'--! () "{p.name}\\n[{p.type_str}]" as o_{p.name}')
        lines.append('--!')

        # Bloque del componente
        lines.append(f'--! [{entity.name}] as ENT')
        lines.append('--!')

        # Nota con información interna (señales, enums, constantes)
        note_lines = []
        internals = [s for s in entity.signals if 'next' not in s.name.lower()]
        if internals:
            note_lines.append('--!   **Internal Signals**')
            for s in internals:
                note_lines.append(f'--!   {s.name} : {s.type_str}')

        for t in entity.enum_types:
            if note_lines:
                note_lines.append('--!   ----')
            note_lines.append(f'--!   **{t.name}**')
            note_lines.append(f'--!   {", ".join(t.states)}')

        if entity.constants:
            if note_lines:
                note_lines.append('--!   ----')
            note_lines.append('--!   **Constants**')
            for c in entity.constants:
                note_lines.append(f'--!   {c.name} = {c.value}')

        if note_lines:
            lines.append('--! note right of ENT')
            lines.extend(note_lines)
            lines.append('--! end note')
            lines.append('--!')

        # Conexiones entre interfaces y componente
        for p in inputs:
            lines.append(f'--! i_{p.name} --> ENT')
        for p in outputs:
            lines.append(f'--! ENT --> o_{p.name}')

        lines.append('--! \\enduml')
        lines.append('--!')
        return '\n'.join(lines)

    def _fsm_diagram(self, entity: VhdlEntity) -> str:
        """
        Diagrama de estados PlantUML.
        El estado inicial es el primer literal del tipo enum detectado,
        que por convención VHDL suele ser el estado de reset.
        """
        initial = entity.enum_types[0].states[0] if entity.enum_types else None

        lines = [
            '--! \\par FSM State Diagram',
            '--! \\startuml',
            '--! skinparam state {',
            '--!   BackgroundColor #E8F4FD',
            '--!   BorderColor #2E86AB',
            '--!   FontName Helvetica',
            '--! }',
            '--!',
        ]

        if initial:
            lines.append(f'--! [*] --> {initial}')
            lines.append('--!')

        for tr in entity.fsm_transitions:
            # Las transiciones condicionales llevan la condición como etiqueta
            label = f' : {tr.condition}' if tr.condition else ''
            lines.append(f'--! {tr.from_state} --> {tr.to_state}{label}')

        lines.append('--! \\enduml')
        lines.append('--!')
        return '\n'.join(lines)


# =============================================================================
# INYECTOR
# =============================================================================

class Injector:
    """
    Inserta los bloques Doxygen generados en el lugar correcto del fuente VHDL.

    Estrategia de inserción:
      1. Busca el \\brief que precede inmediatamente a "entity X is"
      2. Extrae cualquier bloque \\htmlonly...\\endhtmlonly existente
         (p.ej. el WaveDrom escrito por el ingeniero)
      3. Extrae cualquier bloque \\startuml...\\enduml existente
      4. Construye un bloque \\details con: htmlonly + startuml + tablas/diagramas
      5. Lo inserta justo después del \\brief

    De esta forma todo el contenido generado queda dentro del comentario
    Doxygen de la entidad (no del fichero), lo que hace que aparezca en
    la página de la entidad y no en el brief ni en la design unit list.
    """

    _RE_ENTITY_START = re.compile(r'^(\s*entity\s+\w+\s+is)', re.IGNORECASE | re.MULTILINE)

    def inject(self, source: str, block: str) -> str:
        m = self._RE_ENTITY_START.search(source)
        if not m:
            return source  # Fichero sin entidad, devolver intacto

        insert_pos = m.start()

        # Buscar el último \brief antes de "entity X is"
        brief_re = re.compile(r'(--!\s*\\brief[^\n]*\n)', re.IGNORECASE)
        brief_match = None
        for bm in brief_re.finditer(source[:insert_pos]):
            brief_match = bm

        if not brief_match:
            # No hay \brief — insertar el bloque directamente antes de entity
            return source[:insert_pos] + block + source[insert_pos:]

        after_brief = brief_match.end()
        pre_entity = source[after_brief:insert_pos]

        # Extraer bloques \htmlonly...\endhtmlonly (WaveDrom, etc.)
        htmlonly_re = re.compile(
            r'--!\s*\\htmlonly.*?--!\s*\\endhtmlonly[^\n]*\n',
            re.DOTALL
        )
        htmlonly_blocks = ''
        for hm in htmlonly_re.finditer(pre_entity):
            htmlonly_blocks += hm.group(0)

        # Extraer bloques \startuml...\enduml escritos manualmente
        startuml_re = re.compile(
            r'--!\s*\\startuml.*?--!\s*\\enduml[^\n]*\n',
            re.DOTALL
        )
        existing_uml = ''
        for um in startuml_re.finditer(pre_entity):
            existing_uml += um.group(0)

        # Construir el bloque \details con todo el contenido
        details = '--! \\details\n'
        if htmlonly_blocks:
            details += htmlonly_blocks.rstrip() + '\n'
        if existing_uml:
            details += existing_uml
        details += block

        # Reemplazar todo lo que había entre \brief y entity con el nuevo \details
        return source[:after_brief] + details + source[insert_pos:]


# =============================================================================
# ENTRY POINT
# =============================================================================

def main():
    """
    Punto de entrada del script.

    Doxygen lo invoca como:
      py -3.11 vhdl_dox_filter.py <ruta_al_fichero.vhd>

    El script escribe el fichero enriquecido por stdout.
    Doxygen captura esa salida y la procesa como si fuera el fichero original.
    """
    # Forzar UTF-8 en stdout para evitar UnicodeEncodeError en Windows
    # (la consola de Windows usa cp1252 por defecto, que no soporta algunos
    # caracteres unicode como '—' que usamos en las tablas)
    sys.stdout = open(sys.stdout.fileno(), mode='w', encoding='utf-8', buffering=1)

    if len(sys.argv) < 2:
        print("Uso: vhdl_dox_filter.py <fichero.vhd>", file=sys.stderr)
        sys.exit(1)

    path   = Path(sys.argv[1])
    source = path.read_text(encoding='utf-8', errors='replace')

    try:
        parser = GhdlParser()
        entity = parser.parse(path, source)
    except ImportError as e:
        # pyGHDL no disponible en este entorno — pasar el fichero sin modificar
        print(f"[vhdl_dox_filter] pyGHDL no disponible: {e}", file=sys.stderr)
        sys.stdout.write(source)
        return

    if entity is None:
        # Fichero sin entidad VHDL (package, .dox, etc.) — pasar sin modificar
        sys.stdout.write(source)
        return

    # Detectar si ya hay bloques \startuml manuales en el comentario de entidad
    # para no duplicar el diagrama de entidad automático
    m_entity = re.search(r'entity\s+\w+\s+is', source, re.IGNORECASE)
    pre_entity = source[:m_entity.start()] if m_entity else source
    startuml_re = re.compile(r'--!\s*\\startuml.*?--!\s*\\enduml', re.DOTALL)
    existing_uml = bool(startuml_re.search(pre_entity))

    generator = DoxygenGenerator()
    block     = generator.generate(entity, existing_uml=existing_uml)

    injector  = Injector()
    result    = injector.inject(source, block)

    sys.stdout.write(result)


if __name__ == '__main__':
    main()
