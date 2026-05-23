# scripts

Scripts Python de generación automática de documentación.

## Ficheros
- `vhdl_dox_filter.py` — Filtro INPUT_FILTER de Doxygen. Parsea VHDL con pyGHDL
  y genera tablas de puertos, señales, constantes, diagrama de entidad y FSM.
- `generate_hierarchy.py` — Genera el diagrama de jerarquía del proyecto.
- `generate_reports.py` — Procesa reportes de GHDL y VSG y genera página Doxygen.
- `vsg_config.yaml` — Configuración de reglas de estilo VSG.

## Requisitos Python (py -3.11)
- pyGHDL (C:\tools\ghdl-src-6 en PYTHONPATH)
- pyTooling
- pyVHDLModel
- vsg
