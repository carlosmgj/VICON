#!/usr/bin/env python3
"""
generate_reports.py
===================
Lee los reportes generados por VSG y GHDL y genera un fichero reports.dox
para Doxygen con una página de reportes estructurada.

Uso
---
    py -3.11 scripts/generate_reports.py <ruta_reports>

Ejemplo:
    py -3.11 scripts/generate_reports.py reports/

Ficheros de entrada esperados en <ruta_reports>:
    ghdl_report.txt   — salida de GHDL -a
    vsg_report.txt    — salida de VSG

Fichero de salida:
    content/reports.dox — página Doxygen con los reportes
"""

import sys
import re
from pathlib import Path
from datetime import datetime
from dataclasses import dataclass, field


# =============================================================================
# ESTRUCTURAS DE DATOS
# =============================================================================

@dataclass
class ReportIssue:
    """Un problema encontrado por una herramienta de análisis."""
    file: str
    line: int
    column: int
    severity: str   # error, warning, info
    rule: str
    message: str


@dataclass
class ToolReport:
    """Resultado completo de una herramienta de análisis."""
    tool: str
    issues: list[ReportIssue] = field(default_factory=list)
    raw_content: str = ''
    available: bool = False

    @property
    def errors(self) -> list[ReportIssue]:
        return [i for i in self.issues if i.severity == 'error']

    @property
    def warnings(self) -> list[ReportIssue]:
        return [i for i in self.issues if i.severity == 'warning']


# =============================================================================
# PARSERS DE REPORTES
# =============================================================================

class GhdlReportParser:
    """
    Parsea la salida de GHDL -a.
    Formato: fichero:linea:col: (error|warning): mensaje
    """
    _RE = re.compile(
        r'^(.+?):(\d+):(\d+):\s*(error|warning|note):\s*(.+)$',
        re.IGNORECASE
    )

    # Patrones de errores que son warnings en realidad (IPs externos, primitivas Vivado, etc.)
    RECLASSIFY_AS_WARNING = [
        r'not found in library',
        r'cannot find entity',
        r'unit ".+" not found',
    ]
    
    def parse(self, content: str) -> ToolReport:
        report = ToolReport(tool='GHDL', raw_content=content, available=True)
        for line in content.splitlines():
            m = self._RE.match(line.strip())
            if m:
                severity = m.group(4).lower()
                if severity == 'note':
                    severity = 'info'
                
                # Reclasificar errores conocidos como warnings
                if severity == 'error':
                    message = m.group(5).strip()
                    for pattern in self.RECLASSIFY_AS_WARNING:
                        if re.search(pattern, message, re.IGNORECASE):
                            severity = 'warning'
                            break
    
                report.issues.append(ReportIssue(
                    file=Path(m.group(1)).name,
                    line=int(m.group(2)),
                    column=int(m.group(3)),
                    severity=severity,
                    rule='',
                    message=m.group(5).strip(),
                ))
        return report


class VsgReportParser:
    """
    Parsea la salida de VSG en formato syntastic.
    Formato: ERROR: fichero(linea)regla -- mensaje
    """
    _RE = re.compile(
        r'^(ERROR|WARNING):\s*(.+?)\((\d+)\)(\w+)\s*--\s*(.+)$',
        re.IGNORECASE
    )

    def parse(self, content: str) -> ToolReport:
        report = ToolReport(tool='VSG', raw_content=content, available=True)
        for line in content.splitlines():
            m = self._RE.match(line.strip())
            if m:
                report.issues.append(ReportIssue(
                    file=Path(m.group(2)).name,
                    line=int(m.group(3)),
                    column=0,
                    severity=m.group(1).lower(),
                    rule=m.group(4),
                    message=m.group(5).strip(),
                ))
        return report


# =============================================================================
# GENERADOR DE .DOX
# =============================================================================

class ReportsDoxGenerator:
    def _vhd_to_dox_url(self, filename: str, line: int) -> str:
        stem = Path(filename).stem
        print(f"DEBUG: filename={filename}, stem={stem}", file=sys.stderr)
        result = ''
        for ch in stem:
            if ch.isupper():
                result += '_' + ch.lower()
            elif ch == '_':
                result += '__'
            else:
                result += ch
        return f'{result}_8vhd_source.html#l{line:05d}'
    
    def generate(self, reports: list[ToolReport], timestamp: str) -> str:
        sections = []
        for report in reports:
            if report.available:
                sections.append(self._tool_section(report))

        if not sections:
            body = '\\par No hay reportes disponibles.\n'
        else:
            body = '\n'.join(sections)

        return f'''/*!
\\page page_reports REPORTS

\\brief Reportes de análisis estático y verificación de estilo del código VHDL.

Generated: {timestamp}

\\tableofcontents

{body}

*/
'''

    def _tool_section(self, report: ToolReport) -> str:
        """Genera la sección de una herramienta."""
        n_errors   = len(report.errors)
        n_warnings = len(report.warnings)
        n_total    = len(report.issues)

        # Badge de estado
        if n_errors == 0 and n_warnings == 0:
            status = '✅ PASSED'
        elif n_errors == 0:
            status = f'⚠️ {n_warnings} warnings'
        else:
            status = f'❌ {n_errors} errors, {n_warnings} warnings'

        lines = [
            f'\\section sec_report_{report.tool.lower()} {report.tool} — {status}',
            '',
        ]

        # Resumen
        lines += [
            '\\par Summary',
            f'| Tool | Total | Errors | Warnings |',
            f'|------|-------|--------|----------|',
            f'| `{report.tool}` | {n_total} | {n_errors} | {n_warnings} |',
            '',
        ]

        if not report.issues:
            lines.append('No issues found.')
            lines.append('')
            return '\n'.join(lines)

        # Agrupar por fichero
        by_file: dict[str, list[ReportIssue]] = {}
        for issue in report.issues:
            by_file.setdefault(issue.file, []).append(issue)

        lines.append('\\par Issues by file')
        lines.append('')

        for fname, issues in sorted(by_file.items()):
            n_e = sum(1 for i in issues if i.severity == 'error')
            n_w = sum(1 for i in issues if i.severity == 'warning')
            lines.append(f'\\subsection sec_{report.tool.lower()}_{self._safe_id(fname)} {fname} ({n_e} errors, {n_w} warnings)')
            lines.append('')
            lines.append('| Line | Col | Severity | Rule | Message |')
            lines.append('|------|-----|----------|------|---------|')
            for issue in sorted(issues, key=lambda x: x.line):
                sev_badge = '🔴' if issue.severity == 'error' else '🟡'
                rule_str = f'`{issue.rule}`' if issue.rule else '—'
                base = Path(issue.file).stem.lower().replace('_', '__')
                url = self._vhd_to_dox_url(issue.file, issue.line)
                lines.append(
                    f'| {issue.line} | {issue.column} | {sev_badge} {issue.severity} | {rule_str} | {issue.message} |'
                )
            lines.append('')

        return '\n'.join(lines)

    def _safe_id(self, name: str) -> str:
        """Convierte un nombre de fichero a un ID válido para Doxygen."""
        return re.sub(r'[^a-zA-Z0-9]', '_', name)


# =============================================================================
# ENTRY POINT
# =============================================================================

def main():
    if len(sys.argv) < 2:
        print("Uso: generate_reports.py <ruta_reports>", file=sys.stderr)
        sys.exit(1)

    reports_dir = Path(sys.argv[1])
    if not reports_dir.exists():
        print(f"[generate_reports] Carpeta no encontrada: {reports_dir}", file=sys.stderr)
        sys.exit(1)

    reports = []

    # GHDL
    ghdl_file = reports_dir / 'ghdl_report.txt'
    if ghdl_file.exists():
        print(f"[generate_reports] Procesando GHDL report...", file=sys.stderr)
        content = ghdl_file.read_text(encoding='utf-8', errors='replace')
        reports.append(GhdlReportParser().parse(content))
    else:
        print(f"[generate_reports] GHDL report no encontrado, omitiendo.", file=sys.stderr)

    # VSG
    vsg_file = reports_dir / 'vsg_report.txt'
    if vsg_file.exists():
        print(f"[generate_reports] Procesando VSG report...", file=sys.stderr)
        content = vsg_file.read_text(encoding='utf-8', errors='replace')
        reports.append(VsgReportParser().parse(content))
    else:
        print(f"[generate_reports] VSG report no encontrado, omitiendo.", file=sys.stderr)

    # Generar .dox
    timestamp = datetime.now().strftime('%d/%m/%Y %H:%M')
    generator = ReportsDoxGenerator()
    dox_content = generator.generate(reports, timestamp)

    # Escribir en content/reports.dox
    out_path = Path('content/reports.dox')
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(dox_content, encoding='utf-8')
    print(f"[generate_reports] Generado: {out_path}", file=sys.stderr)


if __name__ == '__main__':
    main()
