#!/usr/bin/env python3
"""
vhdl_dox_filter.py  -  INPUT_FILTER de Doxygen para VHDL
=========================================================
Parsea VHDL usando pyGHDL (AST real) y enriquece el fichero
con bloques Doxygen autogenerados: tablas de puertos, señales,
constantes, diagrama de entidad PlantUML y diagrama FSM PlantUML.

Uso en Doxyfile:
    FILTER_PATTERNS = *.vhd="py -3.11 scripts/vhdl_dox_filter.py"
                      *.vhdl="py -3.11 scripts/vhdl_dox_filter.py"

Requisitos:
    - Python 3.11
    - pyGHDL (C:/tools/ghdl-src-6 en PYTHONPATH)
    - pyVHDLModel, pyTooling  (pip install)
    - GHDL binario en PATH
"""

import sys
import re
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional
import tempfile
import os


# ---------------------------------------------------------------------------
# Estructuras de datos internas
# ---------------------------------------------------------------------------

@dataclass
class Port:
    name: str
    direction: str
    type_str: str
    default: Optional[str] = None
    comment: Optional[str] = None

@dataclass
class Generic:
    name: str
    type_str: str
    default: Optional[str] = None
    comment: Optional[str] = None

@dataclass
class Signal:
    name: str
    type_str: str
    default: Optional[str] = None
    comment: Optional[str] = None

@dataclass
class Constant:
    name: str
    type_str: str
    value: str
    comment: Optional[str] = None

@dataclass
class EnumType:
    name: str
    states: list[str]

@dataclass
class FsmState:
    """Estado FSM con sus acciones (asignaciones a señales no-estado)."""
    name: str
    actions: list[str] = field(default_factory=list)

@dataclass
class FsmPointer:
    """Señal que actúa como puntero de retorno en una FSM."""
    name: str                          # nombre de la señal puntero (ej. seq_next)
    used_from: list[str] = field(default_factory=list)   # estados que hacen state <= pointer
    possible_values: list[str] = field(default_factory=list)  # posibles valores del puntero

@dataclass
class FsmTransition:
    from_state: str
    to_state: str
    condition: Optional[str] = None
    
@dataclass
class VhdlEntity:
    name: str
    generics: list[Generic]        = field(default_factory=list)
    ports: list[Port]              = field(default_factory=list)
    signals: list[Signal]          = field(default_factory=list)
    constants: list[Constant]      = field(default_factory=list)
    enum_types: list[EnumType]     = field(default_factory=list)
    fsm_transitions: list[FsmTransition] = field(default_factory=list)
    fsm_states: list[FsmState]           = field(default_factory=list)
    fsm_pointers: list[FsmPointer] = field(default_factory=list)



# ---------------------------------------------------------------------------
# Helpers para extraer comentarios inline --! del texto fuente
# (pyGHDL no expone comentarios, los extraemos por posición de línea)
# ---------------------------------------------------------------------------

def _build_comment_map(source: str) -> dict[int, str]:
    """Devuelve un dict {nº_línea_1based: comentario_doxygen} del fuente."""
    comment_map = {}
    for i, line in enumerate(source.splitlines(), start=1):
        m = re.search(r'--!\s*(.+)$', line)
        if m:
            text = m.group(1).strip()
            # Ignorar líneas que son bloques \startuml, \brief, etc.
            if not text.startswith('\\'):
                comment_map[i] = text
    return comment_map

def _clean(name: str) -> str:
    """Elimina el '?' que pyGHDL añade a nombres no resueltos."""
    return str(name).replace('?', '').strip()
    
def _format_condition(cond) -> str:
    """Reconstruye una condición EqualExpression con formato VHDL correcto."""
    try:
        from pyGHDL.dom.Expression import EqualExpression
        from pyGHDL.dom.Literal import CharacterLiteral
        if isinstance(cond, EqualExpression):
            left  = _clean(str(cond.LeftOperand))
            right = cond.RightOperand
            if isinstance(right, CharacterLiteral):
                return f"{left} = '{right.Value}'"
            return f"{left} = {_clean(str(right))}"
    except Exception:
        pass
    return _clean(str(cond))
        
# ---------------------------------------------------------------------------
# Parser pyGHDL
# ---------------------------------------------------------------------------

class GhdlParser:
    """
    Parsea un fichero VHDL con pyGHDL y devuelve un VhdlEntity.
    Si pyGHDL no está disponible lanza ImportError.
    """

    def parse(self, path: Path, source: str) -> Optional[VhdlEntity]:
        from pyGHDL.dom.NonStandard import Document
        from pyGHDL.dom.Object import Signal as GhdlSignal, Constant as GhdlConstant
        from pyGHDL.dom.Type import EnumeratedType
        from pyGHDL.dom.Concurrent import ProcessStatement
        from pyGHDL.dom.Sequential import (
            CaseStatement,
            SequentialSimpleSignalAssignment,
            IfStatement,
        )
        # pyGHDL necesita UTF-8 — si el fichero es UTF-16 lo convertimos
        raw = path.read_bytes()
        tmp = None
        parse_path = path
        if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
            tmp = tempfile.NamedTemporaryFile(suffix='.vhd', delete=False,
                                            mode='w', encoding='utf-8')
            tmp.write(source)
            tmp.close()
            parse_path = Path(tmp.name)
        try:
            doc = Document(path)
        except Exception as e:
            print(f"[vhdl_dox_filter] pyGHDL error en {path}: {e}", file=sys.stderr)
            return None

        if not doc.Entities:
            return None

        comment_map = _build_comment_map(source)

        # Tomamos la primera entidad del fichero
        entity_name, ghdl_entity = next(iter(doc.Entities.items()))
        entity = VhdlEntity(name=_clean(entity_name))

        # --- Genéricos ---
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

        _, archs = next(iter(doc.Architectures.items()))
        _, arch  = next(iter(archs.items()))

        # Señales y constantes en la sección declarativa
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
                entity.enum_types.append(EnumType(
                    name=_clean(item.Identifier),
                    states=[_clean(lit) for lit in item.Literals],
                ))

        # --- FSM: buscar CaseStatement sobre señal de estado ---
        enum_names = {t.name.lower() for t in entity.enum_types}
        state_signals = {
            s.name.lower() for s in entity.signals
            if s.type_str.lower() in enum_names and 'next' not in s.name.lower()
        }

        if state_signals:
            known_states = {s.lower() for t in entity.enum_types for s in t.states}
            entity.fsm_transitions = self._extract_fsm(
                arch.Statements, state_signals, known_states,
                CaseStatement, SequentialSimpleSignalAssignment, IfStatement
            )
            entity.fsm_states = getattr(self, '_last_fsm_states', [])
            entity.fsm_pointers = getattr(self, '_last_fsm_pointers', [])

        return entity


    def _extract_fsm(self, statements, state_signals, known_states,
                     CaseStatement, SequentialSimpleSignalAssignment, IfStatement):
        transitions = []
        fsm_states_dict = {}
        pointer_uses = {}


        for stmt in statements:
            proc_stmts = getattr(stmt, 'Statements', [])
            case_stmts = self._find_case_statements(proc_stmts, CaseStatement, IfStatement)
    
            for case_stmt in case_stmts:
                case_expr = _clean(str(case_stmt._expression)).lower()
                if not any(sig in case_expr for sig in state_signals):
                    continue
    
                for branch in case_stmt.Cases:
                    choices = getattr(branch, 'Choices', [])
                    if not choices:
                        continue
                    from_state = _clean(str(choices[0].Expression))
                    if from_state.upper() in ('OTHERS', 'NULL', ''):
                        continue
    
                    state_actions = []
                    fsm_states_dict[from_state] = state_actions
    
                    self._extract_branch_transitions(
                        branch.Statements, from_state, state_signals,
                        transitions, CaseStatement,
                        SequentialSimpleSignalAssignment, IfStatement,
                        known_states=known_states,
                        state_actions=state_actions,
                        pointer_uses=pointer_uses
                    )
        # Recoger valores posibles de cada puntero
        pointer_values = {}
        if pointer_uses:
            pointer_values = self._collect_pointer_values(
                statements, 
                {k.lower() for k in pointer_uses.keys()},
                known_states,
                SequentialSimpleSignalAssignment, IfStatement
            )
        
        self._last_fsm_pointers = [
            FsmPointer(
                name=ptr_name,
                used_from=used_from,
                possible_values=pointer_values.get(ptr_name.lower(), [])
            )
            for ptr_name, used_from in pointer_uses.items()
        ]
        self._last_fsm_states = [
            FsmState(name=name, actions=actions)
            for name, actions in fsm_states_dict.items()
        ]

        # Deduplicar transiciones
        seen = set()
        unique_transitions = []
        for tr in transitions:
            key = (tr.from_state, tr.to_state, tr.condition)
            if key not in seen:
                seen.add(key)
                unique_transitions.append(tr)
        transitions = unique_transitions

        return transitions

    def _find_case_statements(self, statements, CaseStatement, IfStatement):
        """Busca CaseStatements recursivamente en cualquier nivel de anidamiento."""
        result = []
        for s in statements:
            if isinstance(s, CaseStatement):
                result.append(s)
            elif isinstance(s, IfStatement):
                for branch in [s.IfBranch] + list(getattr(s, 'ElsIfBranches', []) or []):
                    result.extend(self._find_case_statements(
                        getattr(branch, 'Statements', []), CaseStatement, IfStatement
                    ))
                if s.ElseBranch:
                    result.extend(self._find_case_statements(
                        getattr(s.ElseBranch, 'Statements', []), CaseStatement, IfStatement
                    ))
        return result

    def _extract_branch_transitions(self, statements, from_state, state_signals,
                                     transitions, CaseStatement,
                                     SequentialSimpleSignalAssignment, IfStatement,
                                     condition=None, known_states=None,
                                     state_actions=None, pointer_uses=None):
        for bs in statements:
            if isinstance(bs, IfStatement):
                cond = _format_condition(bs.IfBranch._condition)
                self._extract_branch_transitions(
                    bs.IfBranch.Statements, from_state, state_signals,
                    transitions, CaseStatement,
                    SequentialSimpleSignalAssignment, IfStatement,
                    condition=cond, known_states=known_states,
                    state_actions=state_actions, pointer_uses=pointer_uses
                )
                # ElsIf branches
                for elsif in getattr(bs, 'ElsIfBranches', []) or []:
                    elsif_cond = _format_condition(elsif._condition)
                    self._extract_branch_transitions(
                        getattr(elsif, 'Statements', []), from_state, state_signals,
                        transitions, CaseStatement,
                        SequentialSimpleSignalAssignment, IfStatement,
                        condition=elsif_cond, known_states=known_states,
                        state_actions=state_actions, pointer_uses=pointer_uses
                    )
                # Else branch
                if bs.ElseBranch:
                    self._extract_branch_transitions(
                        bs.ElseBranch.Statements, from_state, state_signals,
                        transitions, CaseStatement,
                        SequentialSimpleSignalAssignment, IfStatement,
                        condition=f'not ({cond})', known_states=known_states,
                        state_actions=state_actions, pointer_uses=pointer_uses
                    )
    
            elif isinstance(bs, SequentialSimpleSignalAssignment):
                target = _clean(str(bs.Target)).lower()
                if any(sig in target for sig in state_signals):
                    for wave in bs.Waveform:
                        to_state = _clean(str(wave.Expression))
                        if to_state.upper() in ('OTHERS', 'NULL', ''):
                            continue
                        if known_states and to_state.lower() not in known_states:
                            if pointer_uses is not None:
                                key = to_state
                                if key not in pointer_uses:
                                    pointer_uses[key] = []
                                if from_state not in pointer_uses[key]:
                                    pointer_uses[key].append(from_state)
                            continue
                        transitions.append(FsmTransition(
                            from_state=from_state,
                            to_state=to_state,
                            condition=condition,
                        ))
                else:
                    if state_actions is not None and from_state not in [None, '']:
                        for wave in bs.Waveform:
                            value = _clean(str(wave.Expression))
                            action = f'{_clean(str(bs.Target))} <= {value}'
                            if action not in state_actions:
                                state_actions.append(action)

    def _collect_pointer_values(self, statements, pointer_names, known_states,
                                 SequentialSimpleSignalAssignment, IfStatement):
        """
        Recorre todo el código buscando asignaciones a señales puntero
        para recoger todos sus posibles valores.
        """
        values = {p: [] for p in pointer_names}
    
        def search(stmts):
            for s in stmts:
                if isinstance(s, SequentialSimpleSignalAssignment):
                    target = _clean(str(s.Target)).lower()
                    if target in pointer_names:
                        for wave in s.Waveform:
                            val = _clean(str(wave.Expression))
                            if known_states and val.lower() in known_states:
                                if val not in values[target]:
                                    values[target].append(val)
                elif isinstance(s, IfStatement):
                    search(getattr(s.IfBranch, 'Statements', []))
                    if s.ElseBranch:
                        search(getattr(s.ElseBranch, 'Statements', []))
    
        for stmt in statements:
            search(getattr(stmt, 'Statements', []))
    
        return values
# ---------------------------------------------------------------------------
# Generador de bloques Doxygen
# ---------------------------------------------------------------------------

class DoxygenGenerator:

    def generate(self, entity: VhdlEntity, existing_uml: bool = False, fsm_show_actions: bool = False) -> str:
        blocks = []

        if entity.generics:
            blocks.append(self._generic_table(entity.generics))

        if entity.ports:
            blocks.append(self._port_table(entity.ports))
        
        if not existing_uml:
            # Descomentar la siguiete línea y comentar la que está activa para UML similar a TEROSHDL
            # blocks.append(self._entity_diagram2(entity))
            blocks.append(self._entity_diagram(entity))

        if entity.signals:
            visible_signals = [s for s in entity.signals if 'next' not in s.name.lower()]
            if visible_signals:
                blocks.append(self._signal_table(visible_signals))

        if entity.constants:
            blocks.append(self._constant_table(entity.constants))

        if entity.fsm_transitions:
            blocks.append(self._fsm_diagram(entity, fsm_show_actions))

        return '\n'.join(blocks) + '\n'

    # --- Tablas ---

    def _port_table(self, ports: list[Port]) -> str:
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

    # --- Diagramas PlantUML ---

    def _entity_diagram2(self, entity: VhdlEntity) -> str:
        """
        Diagrama de entidad estilo TerosHDL generado como HTML inline.
        Caja verde para parámetros/señales internas, caja amarilla para puertos.
        """
        inputs  = [p for p in entity.ports if p.direction in ('in', 'inout')]
        outputs = [p for p in entity.ports if p.direction in ('out', 'buffer', 'inout')]

        # Calcular altura de la caja de puertos
        max_ports = max(len(inputs), len(outputs), 1)
        row_height = 28
        port_box_height = max_ports * row_height + 20

        # Construir filas de puertos
        port_rows = ''
        for i in range(max_ports):
            left  = inputs[i]  if i < len(inputs)  else None
            right = outputs[i] if i < len(outputs) else None

            left_td  = f'<td style="width:1px;white-space:nowrap;"padding:4px 10px;text-align:right;color:#1a1a1a;font-family:monospace;font-size:13px;">← {left.name}<br/><span style="font-size:10px;color:inherit;">{left.type_str}</span></td>'   if left  else '<td></td>'
            right_td = f'<td style="padding:4px 10px;text-align:right;color:#1a1a1a;font-family:monospace;font-size:13px;">{right.name} →<br/><span style="font-size:10px;color:inherit;">{right.type_str}</span></td>' if right else '<td></td>'

            port_rows += f'<tr>{left_td}{right_td}</tr>'

        # Construir filas de parámetros/constantes/señales internas
        internal_rows = ''
        for t in entity.enum_types:
            internal_rows += f'<tr><td style="padding:2px 10px;font-family:monospace;font-size:12px;color:#1a1a1a;"><b>{t.name}</b>: {", ".join(t.states)}</td></tr>'
        for c in entity.constants:
            internal_rows += f'<tr><td style="padding:2px 10px;font-family:monospace;font-size:12px;color:#1a1a1a;">{c.name} = {c.value}</td></tr>'
        internals = [s for s in entity.signals if 'next' not in s.name.lower()]
        for s in internals:
            internal_rows += f'<tr><td style="padding:2px 10px;font-family:monospace;font-size:12px;color:#1a1a1a;">{s.name} : {s.type_str}</td></tr>'

        # HTML del diagrama
        html = f'''--! \\par Entity Diagram
    --! \\htmlonly
    --! <div style="display:inline-block;border:2px solid #888;border-radius:4px;overflow:hidden;font-family:sans-serif;min-width:300px;">
    --!   <!-- Cabecera con nombre de entidad -->
    --!   <div style="background:#4a4a4a;color:white;text-align:center;padding:6px 16px;font-size:15px;font-weight:bold;letter-spacing:1px;">
    --!     {entity.name}
    --!   </div>
    --!   <!-- Caja verde: parámetros, constantes, señales internas -->'''

        if internal_rows:
            html += f'''
    --!   <div style="background:#c8e6c9;padding:6px 0;border-bottom:1px solid #888;">
    --!     <table style="width:100%;border-collapse:collapse;">
    --!       {internal_rows}
    --!     </table>
    --!   </div>'''

        html += f'''
    --!   <!-- Caja amarilla: puertos -->
    --!   <div style="background:#fff9c4;padding:6px 0;">
    --!     <table style="width:100%;border-collapse:collapse;">
    --!       {port_rows}
    --!     </table>
    --!   </div>
    --! </div>
    --! \\endhtmlonly
    --!'''

        # Convertir a líneas --!
        lines = []
        for line in html.split('\n'):
            lines.append(line)
        return '\n'.join(lines)

    def _entity_diagram(self, entity: VhdlEntity) -> str:
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

        for p in inputs:
            lines.append(f'--! () "{p.name}\\n[{p.type_str}]" as i_{p.name}')
        for p in outputs:
            lines.append(f'--! () "{p.name}\\n[{p.type_str}]" as o_{p.name}')
        lines.append('--!')

        lines.append(f'--! [{entity.name}] as ENT')
        lines.append('--!')

        # Nota con señales internas, enums y constantes
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

        for p in inputs:
            lines.append(f'--! i_{p.name} --> ENT')
        for p in outputs:
            lines.append(f'--! ENT --> o_{p.name}')

        lines.append('--! \\enduml')
        lines.append('--!')
        return '\n'.join(lines)

    def _fsm_diagram(self, entity: VhdlEntity, show_actions: bool = False) -> str:
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

        # Declarar explícitamente todos los estados
        all_states = entity.enum_types[0].states if entity.enum_types else []
        for state in all_states:
            lines.append(f'--! state {state}')
        lines.append('--!')

        # Mapa de acciones por estado
        actions_map = {s.name: s.actions for s in entity.fsm_states} if show_actions else {}
        
        # Declarar estados con acciones si show_actions está activo
        all_states = entity.enum_types[0].states if entity.enum_types else []
        for state in all_states:
            lines.append(f'--! state {state}')
            if show_actions and state in actions_map and actions_map[state]:
                for action in actions_map[state]:
                    lines.append(f'--! {state} : {action}')
        lines.append('--!')
        
        for tr in entity.fsm_transitions:
            label = f' : {tr.condition}' if tr.condition else ''
            lines.append(f'--! {tr.from_state} --> {tr.to_state}{label}')
        
        # Nodos especiales para punteros de retorno
        if entity.fsm_pointers:
            lines.append('--!')
            for ptr in entity.fsm_pointers:
                ptr_node = f'PTR_{ptr.name}'
                # Declarar nodo puntero con estilo diferenciado
                lines.append(f'--! state {ptr_node} : {ptr.name}\\n(dynamic return)')
                # Flechas desde estados que usan el puntero
                for from_state in ptr.used_from:
                    lines.append(f'--! {from_state} --> {ptr_node}')
                # Flechas hacia posibles valores
                for val in ptr.possible_values:
                    lines.append(f'--! {ptr_node} --> {val}')

        lines.append('--! \\enduml')
        lines.append('--!')
        return '\n'.join(lines)

# ---------------------------------------------------------------------------
# Inyector: inserta los bloques justo antes de "entity X is"
# ---------------------------------------------------------------------------

class Injector:
    _RE_ENTITY_START = re.compile(r'^(\s*entity\s+\w+\s+is)', re.IGNORECASE | re.MULTILINE)

    def inject(self, source: str, block: str) -> str:
        m = self._RE_ENTITY_START.search(source)
        if not m:
            return source

        insert_pos = m.start()

        # Buscar el último \brief antes de "entity X is"
        brief_re = re.compile(r'(--!\s*\\brief[^\n]*\n)', re.IGNORECASE)
        brief_match = None
        for bm in brief_re.finditer(source[:insert_pos]):
            brief_match = bm

        if not brief_match:
            return source[:insert_pos] + block + source[insert_pos:]

        after_brief = brief_match.end()
        pre_entity = source[after_brief:insert_pos]

        # Construir \details conservando todo el contenido existente
        # (texto, WaveDrom, UML manual) y añadiendo las tablas al final
        details = '--! \\details\n'
        details += pre_entity
        details += block

        return source[:after_brief] + details + source[insert_pos:]

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    sys.stdout = open(sys.stdout.fileno(), mode='w', encoding='utf-8', buffering=1)
    if len(sys.argv) < 2:
        print("Uso: vhdl_dox_filter.py <fichero.vhd>", file=sys.stderr)
        sys.exit(1)

    
    path   = Path(sys.argv[1])
    # Detectar codificación automáticamente (UTF-16, UTF-8, latin-1, etc.)
    raw = path.read_bytes()
    if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
        source = raw.decode('utf-16')
    elif raw[:3] == b'\xef\xbb\xbf':
        source = raw.decode('utf-8-sig')
    else:
        source = raw.decode('utf-8', errors='replace')

    try:
        parser = GhdlParser()
        entity = parser.parse(path, source)
    except ImportError as e:
        # pyGHDL no disponible - devolver el fichero sin modificar
        print(f"[vhdl_dox_filter] pyGHDL no disponible: {e}", file=sys.stderr)
        sys.stdout.write(source)
        return

    if entity is None:
        # Fichero sin entidad (package, context, etc.)
        sys.stdout.write(source)
        return

    generator = DoxygenGenerator()

    startuml_re = re.compile(r'--!\s*\\startuml.*?--!\s*\\enduml', re.DOTALL)
    m_entity = re.search(r'entity\s+\w+\s+is', source, re.IGNORECASE)
    pre_entity = source[:m_entity.start()] if m_entity else source
    existing_uml = bool(startuml_re.search(pre_entity))
    fsm_show_actions = bool(re.search(r'--!\s*\\fsm_show_actions', pre_entity, re.IGNORECASE))

    block = generator.generate(entity, existing_uml=existing_uml, fsm_show_actions=fsm_show_actions)
    
    injector  = Injector()
    result    = injector.inject(source, block)

    sys.stdout.write(result)


if __name__ == '__main__':
    main()