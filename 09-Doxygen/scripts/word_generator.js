'use strict';
/**
 * word_generator.js
 * =================
 * Genera el documento Word de diseño VHDL a partir de:
 *   - module_data.json   (producido por generate_word.py)
 *   - doc_config.json    (config convertida a JSON por generate_word.py)
 *
 * Uso:
 *   node word_generator.js <module_data.json> <doc_config.json> <output.docx>
 *
 * Requiere:  npm install -g docx
 */

const fs   = require('fs');
const path = require('path');

const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  ImageRun, Header, Footer, AlignmentType, HeadingLevel,
  BorderStyle, WidthType, ShadingType, VerticalAlign,
  PageNumber, PageBreak, TableOfContents,
  TabStopType, TabStopPosition,
} = require('docx');

// ─── NULL SAFETY ─────────────────────────────────────────────────────────────
/** Sanitiza texto para TextRun: elimina \n, \r, caracteres de control. */
function safe(value) {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/[\r\n\t]/g, ' ')    // newlines → espacio (docx no permite \n en TextRun)
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');  // eliminar control chars
}

// ─── CLI ──────────────────────────────────────────────────────────────────────
const [,, jsonPath, configPath, outPath] = process.argv;
if (!jsonPath || !configPath || !outPath) {
  console.error('Uso: node word_generator.js <module_data.json> <doc_config.json> <output.docx>');
  process.exit(1);
}

const DATA   = JSON.parse(fs.readFileSync(jsonPath,   'utf8'));
const CONFIG = JSON.parse(fs.readFileSync(configPath, 'utf8'));

// Diagnóstico de arranque
const modCount = Object.keys(DATA.modules || {}).length;
console.log(`[word_generator] Procesando: ${modCount} módulos, top="${DATA.top_module}", secciones=${(CONFIG.sections||[]).length}`);

// ─── CONFIG HELPERS ──────────────────────────────────────────────────────────
const docMeta   = CONFIG.document  || {};
const pageCfg   = CONFIG.page      || {};
const hdrCfg    = CONFIG.header    || {};
const ftrCfg    = CONFIG.footer    || {};
// Si no hay secciones definidas en el config, usar defaults razonables
const DEFAULT_SECTIONS = [
  { type: 'cover' },
  { type: 'toc',     title: 'Table of Contents' },
  { type: 'modules', max_depth: 3, show: {} },
];
const sections  = (CONFIG.sections && CONFIG.sections.length) ? CONFIG.sections : DEFAULT_SECTIONS;
const modSecCfg = sections.find(s => s.type === 'modules') || {};
const showCfg   = modSecCfg.show   || {};

/** Reemplaza {variable} en un template con los metadatos del documento. */
function fmt(template) {
  const vars = {
    project:         safe(docMeta.project),
    title:           safe(docMeta.title),
    version:         safe(docMeta.version),
    author:          safe(docMeta.author),
    confidentiality: safe(docMeta.confidentiality),
    date:            safe(docMeta.date),
  };
  return safe(template).replace(/\{(\w+)\}/g, (_, k) => vars[k] !== undefined ? vars[k] : '');
}

// ─── PAGE & MARGIN ───────────────────────────────────────────────────────────
const PAGE = pageCfg.size === 'US_LETTER'
  ? { width: 12240, height: 15840 }
  : { width: 11906, height: 16838 };   // A4 por defecto

const MARGIN   = { top: 1440, right: 1134, bottom: 1440, left: 1701 };  // 1in top/bot, 2cm right, 3cm left (más profesional)
const CONTENT_W = PAGE.width - MARGIN.left - MARGIN.right;  // DXA

// ─── PALETA ──────────────────────────────────────────────────────────────────
const C = {
  primary:    '1F5C8B',   // azul oscuro headings
  accent:     '2E86AB',   // azul medio (líneas, borders)
  header_bg:  'D6E4F0',   // fondo cabecera de tabla
  row_alt:    'F0F6FB',   // fila alterna tabla
  text:       '1A1A1A',
  muted:      '666666',
  white:      'FFFFFF',
  border:     'CCCCCC',
};

// ─── HELPER: PNG DIMENSIONS ──────────────────────────────────────────────────
function pngDims(buf) {
  if (!buf || buf.length < 24) return { w: 800, h: 400 };
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

/** Construye un ImageRun ajustando la imagen a maxWidthDxa y maxHeightDxa manteniendo el ratio. */
function makeImage(pngPath, maxWidthDxa, label, maxHeightDxa) {
  if (!pngPath || !fs.existsSync(pngPath)) return null;
  const buf    = fs.readFileSync(pngPath);
  const { w, h } = pngDims(buf);
  // Conversión: DXA → pulgadas → píxeles  (1440 DXA = 1 in = 96 px)
  let dispW  = Math.round(maxWidthDxa * 96 / 1440);
  let dispH  = Math.round(dispW * h / w);
  // Limitar altura máxima para evitar que FSMs grandes se salgan de la página
  if (maxHeightDxa) {
    const maxDispH = Math.round(maxHeightDxa * 96 / 1440);
    if (dispH > maxDispH) {
      dispH = maxDispH;
      dispW = Math.round(dispH * w / h);
    }
  }
  return new ImageRun({
    type: 'png',
    data: buf,
    transformation: { width: dispW, height: dispH },
    altText: { title: safe(label), description: safe(label), name: safe(label) },
  });
}

// ─── ENTITY DIAGRAM TABLE ────────────────────────────────────────────────────
/**
 * Genera el diagrama de entidad como tabla Word (estilo TerosHDL).
 * Header gris oscuro, caja verde para genéricos, caja amarilla para puertos.
 * Entradas (izquierda): name →   Salidas (derecha): ← name
 */
function makeEntityDiagramTable(mod) {
  const entityCfg  = (CONFIG.entity_diagram) || {};
  const widthPct   = (entityCfg.width_percent || 85) / 100;
  const TABLE_W    = Math.floor(CONTENT_W * widthPct);
  const COL_W      = Math.floor(TABLE_W / 2);

  const COLOR_HEADER  = '4a4a4a';
  const COLOR_GENERIC = 'c8e6c9';
  const COLOR_PORT    = 'fff9c4';

  const noBorder  = { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' };
  const noBorders = { top: noBorder, bottom: noBorder, left: noBorder, right: noBorder };
  const sepBorder = { style: BorderStyle.SINGLE, size: 1, color: 'AAAAAA' };

  const rows = [];

  // ── Header: nombre de entidad ──
  rows.push(new TableRow({
    children: [new TableCell({
      columnSpan: 2,
      width:   { size: TABLE_W, type: WidthType.DXA },
      shading: { fill: COLOR_HEADER, type: ShadingType.CLEAR },
      borders: noBorders,
      margins: { top: 80, bottom: 80, left: 160, right: 160 },
      verticalAlign: VerticalAlign.CENTER,
      children: [new Paragraph({
        alignment: AlignmentType.CENTER,
        children:  [new TextRun({ text: safe(mod.name || ''), bold: true, size: 24, color: 'FFFFFF', font: 'Arial' })]
      })]
    })]
  }));

  // ── Genéricos (caja verde) ──
  const generics = mod.generics || [];
  if (generics.length > 0) {
    const genericLines = generics.map(g =>
      new Paragraph({ children: [
        new TextRun({ text: safe(g.name), bold: true, size: 18, font: 'Courier New' }),
        new TextRun({ text: ` : ${safe(g.type)}`, size: 18, font: 'Courier New' }),
        ...(g.default ? [new TextRun({ text: ` = ${safe(g.default)}`, size: 18, font: 'Courier New', color: '555555' })] : []),
      ]})
    );
    rows.push(new TableRow({
      children: [new TableCell({
        columnSpan: 2,
        width:   { size: TABLE_W, type: WidthType.DXA },
        shading: { fill: COLOR_GENERIC, type: ShadingType.CLEAR },
        borders: { ...noBorders, bottom: sepBorder },
        margins: { top: 60, bottom: 60, left: 160, right: 160 },
        children: genericLines
      })]
    }));
  }

  // ── Puertos (caja amarilla) ──
  const inputs  = (mod.ports || []).filter(p => ['in','inout'].includes((p.direction||'').toLowerCase()));
  const outputs = (mod.ports || []).filter(p => ['out','buffer'].includes((p.direction||'').toLowerCase()));
  const maxPorts = Math.max(inputs.length, outputs.length, 1);

  for (let i = 0; i < maxPorts; i++) {
    const inp = inputs[i];
    const out = outputs[i];

    // Input: name → type  (flecha de izquierda a derecha)
    const leftChildren = inp ? [new Paragraph({ children: [
      new TextRun({ text: safe(inp.name), bold: true, size: 18, font: 'Courier New' }),
      new TextRun({ text: ' \u2192 ', size: 18, font: 'Courier New', color: '2E86AB' }),
      new TextRun({ text: safe(inp.type), size: 16, font: 'Courier New', color: '666666' }),
    ]})] : [new Paragraph({ children: [] })];

    // Output: type ← name  (flecha apuntando hacia afuera a la derecha)
    const rightChildren = out ? [new Paragraph({ alignment: AlignmentType.RIGHT, children: [
      new TextRun({ text: safe(out.type), size: 16, font: 'Courier New', color: '666666' }),
      new TextRun({ text: ' \u2192 ', size: 18, font: 'Courier New', color: '2E86AB' }),
      new TextRun({ text: safe(out.name), bold: true, size: 18, font: 'Courier New' }),
    ]})] : [new Paragraph({ children: [] })];

    rows.push(new TableRow({
      children: [
        new TableCell({
          width:   { size: COL_W, type: WidthType.DXA },
          shading: { fill: COLOR_PORT, type: ShadingType.CLEAR },
          borders: noBorders,
          margins: { top: 40, bottom: 40, left: 160, right: 80 },
          children: leftChildren
        }),
        new TableCell({
          width:   { size: COL_W, type: WidthType.DXA },
          shading: { fill: COLOR_PORT, type: ShadingType.CLEAR },
          borders: noBorders,
          margins: { top: 40, bottom: 40, left: 80, right: 160 },
          children: rightChildren
        }),
      ]
    }));
  }

  return new Table({
    width:        { size: TABLE_W, type: WidthType.DXA },
    columnWidths: [COL_W, COL_W],
    rows,
  });
}

// ─── BORDER HELPERS ──────────────────────────────────────────────────────────
const BORDER_CELL  = { style: BorderStyle.SINGLE, size: 1,  color: C.border };
const BORDER_NONE  = { style: BorderStyle.NONE,   size: 0,  color: 'FFFFFF' };
const BORDER_ACCENT = { style: BorderStyle.SINGLE, size: 6,  color: C.accent, space: 4 };
const BORDER_LIGHT  = { style: BorderStyle.SINGLE, size: 2,  color: C.border, space: 4 };

// ─── PARAGRAPH BUILDERS ──────────────────────────────────────────────────────

/** Párrafo vacío (espaciado). */
function spacer(n = 1) {
  return Array.from({ length: n }, () => new Paragraph({ children: [] }));
}

/** Heading en nivel 1, 2 o 3. */
function mkHeading(text, level) {
  const MAP = {
    1: HeadingLevel.HEADING_1,
    2: HeadingLevel.HEADING_2,
    3: HeadingLevel.HEADING_3,
  };
  return new Paragraph({
    heading: MAP[Math.min(level, 3)] || HeadingLevel.HEADING_3,
    children: [new TextRun({ text })],
  });
}

/** Subtítulo de sección dentro de un módulo (Ports, Signals, etc.). */
function sectionLabel(text) {
  return new Paragraph({
    children: [new TextRun({ text, bold: true, size: 20, font: 'Arial', color: C.primary })],
    spacing:  { before: 280, after: 100 },
    border:   { bottom: BORDER_ACCENT },
  });
}

/** Texto en monospace (para nombres de señales, tipos, etc.). */
function mono(text) {
  return new TextRun({ text: safe(text), font: 'Courier New', size: 18 });
}

/** Texto normal pequeño. */
function txt(text, opts = {}) {
  return new TextRun({ text: safe(text), font: 'Arial', size: 18, ...opts });
}

// ─── TABLE BUILDER ───────────────────────────────────────────────────────────
/**
 * Crea una tabla con cabecera azul y filas alternas.
 * @param {string[]} headers  — nombres de columnas
 * @param {string[][]} rows   — filas de datos
 * @param {number[]} colWidths — anchos en DXA (deben sumar = tabla total)
 */
function makeTable(headers, rows, colWidths) {
  const totalW  = colWidths.reduce((a, b) => a + b, 0);
  const borders = {
    top: BORDER_CELL, bottom: BORDER_CELL, left: BORDER_CELL, right: BORDER_CELL,
  };
  const cellMgn = { top: 70, bottom: 70, left: 110, right: 110 };

  const mkCell = (text, isHeader, colIdx, rowIdx) => new TableCell({
    borders,
    width:   { size: colWidths[colIdx], type: WidthType.DXA },
    margins: cellMgn,
    shading: isHeader
      ? { fill: C.header_bg,                          type: ShadingType.CLEAR }
      : { fill: rowIdx % 2 === 1 ? C.row_alt : C.white, type: ShadingType.CLEAR },
    verticalAlign: VerticalAlign.CENTER,
    children: [new Paragraph({
      children: [new TextRun({
        text:  safe(text),
        font:  'Arial',
        size:  18,
        bold:  isHeader,
        color: C.text,
      })],
    })],
  });

  const headerRow = new TableRow({
    tableHeader: true,
    children: headers.map((h, i) => mkCell(h, true, i, 0)),
  });

  const dataRows = rows.map((row, ri) =>
    new TableRow({
      children: row.map((cell, ci) => mkCell(cell, false, ci, ri)),
    })
  );

  return new Table({
    width:        { size: totalW, type: WidthType.DXA },
    columnWidths: colWidths,
    rows:         [headerRow, ...dataRows],
  });
}

// ─── HEADER Y FOOTER ─────────────────────────────────────────────────────────

function makeHeader() {
  const right = fmt(hdrCfg.right_text || '{project}  |  v{version}');
  return new Header({
    children: [new Paragraph({
      children: [txt(right, { color: C.muted, size: 16 })],
      alignment: AlignmentType.RIGHT,
      border:    { bottom: BORDER_ACCENT },
    })],
  });
}

function makeFooter() {
  const left = fmt(ftrCfg.left_text || '{confidentiality}');
  // Footer: texto izquierda, número de página alineado a la derecha con tab stop
  return new Footer({
    children: [new Paragraph({
      tabStops: [{ type: TabStopType.RIGHT, position: TabStopPosition.MAX }],
      children: [
        txt(left, { color: C.muted, size: 16 }),
        new TextRun({ text: '\t' }),
        txt('Page ', { color: C.muted, size: 16 }),
        new TextRun({ children: [PageNumber.CURRENT], size: 16, font: 'Arial', color: C.muted }),
        txt(' of ', { color: C.muted, size: 16 }),
        new TextRun({ children: [PageNumber.TOTAL_PAGES], size: 16, font: 'Arial', color: C.muted }),
      ],
      border: { top: BORDER_LIGHT },
    })],
  });
}

// ─── PORTADA ─────────────────────────────────────────────────────────────────

function buildCover() {
  return [
    ...spacer(9),
    // Título principal
    new Paragraph({
      children: [new TextRun({
        text: fmt('{title}'), size: 64, bold: true, font: 'Arial', color: C.primary,
      })],
      alignment: AlignmentType.CENTER,
      spacing:   { after: 320 },
    }),
    // Nombre del proyecto
    new Paragraph({
      children: [new TextRun({
        text: fmt('{project}'), size: 40, font: 'Arial', color: C.muted,
      })],
      alignment: AlignmentType.CENTER,
      spacing:   { after: 600 },
    }),
    // Línea separadora
    new Paragraph({
      children: [],
      border:   { bottom: { style: BorderStyle.SINGLE, size: 8, color: C.accent, space: 1 } },
      spacing:  { after: 500 },
    }),
    // Metadatos
    ...['Version: {version}', 'Author: {author}', 'Date: {date}'].map(t =>
      new Paragraph({
        children: [new TextRun({ text: fmt(t), size: 24, font: 'Arial', color: C.muted })],
        alignment: AlignmentType.CENTER,
        spacing:   { after: 140 },
      })
    ),
    // Confidencialidad al fondo
    ...spacer(4),
    new Paragraph({
      children: [new TextRun({
        text: fmt('{confidentiality}'), size: 18, font: 'Arial', color: 'AAAAAA', italics: true,
      })],
      alignment: AlignmentType.CENTER,
    }),
  ];
}

// ─── CONTENIDO DE MÓDULO ─────────────────────────────────────────────────────

// Lookup case-insensitive
const MODULE_MAP = {};
for (const [k, v] of Object.entries(DATA.modules || {})) {
  MODULE_MAP[k.toLowerCase()] = v;
}
function getMod(name) { return MODULE_MAP[(name || '').toLowerCase()]; }

/**
 * Genera el contenido de un módulo (heading + tablas + diagramas).
 * @param {string} name  — nombre del módulo
 * @param {number} depth — profundidad en la jerarquía (1 = H1, 2 = H2, 3 = H3)
 */
function buildModuleContent(name, depth) {
  const mod = getMod(name);
  const out = [];

  // Heading
  out.push(mkHeading(name, depth));

  if (!mod) {
    out.push(new Paragraph({ children: [txt(`[Módulo ${name} sin datos parseados]`, { italics: true, color: C.muted })] }));
    return out;
  }

  // Subtítulo con fichero fuente
  if (mod.file) {
    out.push(new Paragraph({
      children: [txt(`Source: ${mod.file}`, { italics: true, size: 16, color: C.muted })],
      spacing:  { after: 120 },
    }));
  }

  // ── Diagrama de entidad (tabla estilo TerosHDL) ────────────────────────
  if (showCfg.entity_diagram !== false) {
    out.push(sectionLabel('Entity Diagram'));
    out.push(makeEntityDiagramTable(mod));
    out.push(...spacer(1));
  }

  // ── Tabla de puertos ───────────────────────────────────────────────────
  if (showCfg.ports_table !== false && mod.ports?.length) {
    out.push(sectionLabel('Ports'));
    const descW = CONTENT_W - 1500 - 900 - 2100 - 1300;
    out.push(makeTable(
      ['Name', 'Direction', 'Type', 'Default', 'Description'],
      mod.ports.map(p => [p.name, p.direction, p.type, p.default || '—', p.description]),
      [1500, 900, 2100, 1300, Math.max(descW, 800)],
    ));
    out.push(...spacer(1));
  }

  // ── Tabla de genéricos ─────────────────────────────────────────────────
  if (showCfg.generics_table !== false && mod.generics?.length) {
    out.push(sectionLabel('Generics'));
    const descW = CONTENT_W - 2000 - 2500 - 1400;
    out.push(makeTable(
      ['Name', 'Type', 'Default', 'Description'],
      mod.generics.map(g => [g.name, g.type, g.default || '—', g.description]),
      [2000, 2500, 1400, Math.max(descW, 800)],
    ));
    out.push(...spacer(1));
  }

  // ── Lista de submódulos ─────────────────────────────────────────────────
  if (showCfg.submodules_list !== false && mod.instantiates?.length) {
    out.push(sectionLabel('Instantiated Submodules'));
    out.push(new Paragraph({
      children: [mono(mod.instantiates.join(',  '))],
      spacing:  { after: 160 },
    }));
  }

  // ── Tabla de señales internas ──────────────────────────────────────────
  if (showCfg.signals_table !== false && mod.signals?.length) {
    out.push(sectionLabel('Internal Signals'));
    const descW = CONTENT_W - 2000 - 2500 - 1300;
    out.push(makeTable(
      ['Name', 'Type', 'Default', 'Description'],
      mod.signals.map(s => [s.name, s.type, s.default || '—', s.description]),
      [2000, 2500, 1300, Math.max(descW, 800)],
    ));
    out.push(...spacer(1));
  }

  // ── Tabla de constantes ────────────────────────────────────────────────
  if (showCfg.constants_table !== false && mod.constants?.length) {
    out.push(sectionLabel('Constants'));
    const descW = CONTENT_W - 2000 - 2000 - 1800;
    out.push(makeTable(
      ['Name', 'Type', 'Value', 'Description'],
      mod.constants.map(c => [c.name, c.type, c.value || '—', c.description]),
      [2000, 2000, 1800, Math.max(descW, 800)],
    ));
    out.push(...spacer(1));
  }

  // ── Diagrama FSM ───────────────────────────────────────────────────────
  if (showCfg.fsm_diagram !== false && mod.fsm_diagram_png) {
    out.push(sectionLabel('FSM State Diagram'));
    // Limitar ancho al 90% del contenido y altura máxima a 20cm (~11340 DXA)
    const img = makeImage(mod.fsm_diagram_png, Math.floor(CONTENT_W * 0.90), `${name} FSM`, 11340);
    if (img) out.push(new Paragraph({ children: [img], alignment: AlignmentType.CENTER, spacing: { after: 200 } }));
  }

  out.push(...spacer(1));
  return out;
}

// ─── TRAVERSAL DE JERARQUÍA ──────────────────────────────────────────────────
const documented = new Set();
const maxDepth   = modSecCfg.max_depth || 3;

function traverseHierarchy(node, depth, out, isFirst) {
  if (!node || documented.has(node.name.toLowerCase())) return;
  if (depth > maxDepth) return;

  documented.add(node.name.toLowerCase());

  // Salto de página antes de cada módulo H1 (excepto el primero)
  if (depth === 1 && !isFirst) {
    out.push(new Paragraph({ children: [new PageBreak()] }));
  }

  out.push(...buildModuleContent(node.name, depth));

  let childFirst = true;
  for (const child of (node.children || [])) {
    if (!child.recursive) {
      traverseHierarchy(child, depth + 1, out, childFirst);
      childFirst = false;
    }
  }
}

// ─── CONSTRUIR SECCIONES DEL DOCUMENTO ───────────────────────────────────────
const docSections = [];

// ── Sección 0: Portada (sin header ni footer) ─────────────────────────────
docSections.push({
  properties: { page: { size: PAGE, margin: MARGIN } },
  children:   buildCover(),
});

// ── Sección 1: Contenido principal (con header y footer) ─────────────────
const mainContent = [];

// TOC
const tocCfg = sections.find(s => s.type === 'toc');
if (tocCfg) {
  mainContent.push(
    new TableOfContents(tocCfg.title || 'Table of Contents', {
      hyperlink:         true,
      headingStyleRange: '1-3',
    })
  );
  mainContent.push(new Paragraph({ children: [new PageBreak()] }));
}

// Módulos
if (sections.some(s => s.type === 'modules') && DATA.hierarchy) {
  traverseHierarchy(DATA.hierarchy, 1, mainContent, true);
}

docSections.push({
  properties: { page: { size: PAGE, margin: MARGIN } },
  headers:    { default: makeHeader() },
  footers:    { default: makeFooter() },
  children:   mainContent,
});

// ─── ESTILOS DEL DOCUMENTO ───────────────────────────────────────────────────
const docStyles = {
  default: {
    document: { run: { font: 'Arial', size: 20, color: C.text } },
  },
  paragraphStyles: [
    {
      id: 'Heading1', name: 'Heading 1',
      basedOn: 'Normal', next: 'Normal', quickFormat: true,
      run: { size: 40, bold: true, font: 'Arial', color: C.primary },
      paragraph: {
        spacing:      { before: 560, after: 280 },
        outlineLevel: 0,
        border:       { bottom: { style: BorderStyle.SINGLE, size: 8, color: C.accent, space: 6 } },
      },
    },
    {
      id: 'Heading2', name: 'Heading 2',
      basedOn: 'Normal', next: 'Normal', quickFormat: true,
      run: { size: 30, bold: true, font: 'Arial', color: C.primary },
      paragraph: { spacing: { before: 400, after: 200 }, outlineLevel: 1 },
    },
    {
      id: 'Heading3', name: 'Heading 3',
      basedOn: 'Normal', next: 'Normal', quickFormat: true,
      run: { size: 24, bold: true, font: 'Arial', color: '2C7BB6' },
      paragraph: { spacing: { before: 280, after: 140 }, outlineLevel: 2 },
    },
  ],
};

// ─── BUILD & WRITE ───────────────────────────────────────────────────────────
const doc = new Document({ styles: docStyles, sections: docSections });

Packer.toBuffer(doc)
  .then(buf => {
    fs.writeFileSync(outPath, buf);
    console.log(`[word_generator] ✓ Documento generado: ${outPath}`);
  })
  .catch(err => {
    console.error('[word_generator] Error:', err.message || err);
    process.exit(1);
  });