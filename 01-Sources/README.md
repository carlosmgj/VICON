# 01-Sources

Código fuente VHDL del diseño RTL.

## Estructura
```
01-Sources/
├── 00-<Module_name>/          # Módulo principal
│   ├── 01-<Submodule1_name>/  # Submódulo 1
│   └── 02-<Submodule2_name>/  # Submódulo 2
├── Constant_Packages/         # Packages de constantes globales
├── pkg1.vhd                   # Packages compartidos
└── pkg2.vhd
```

## Tipos de ficheros
- `*.vhd` — Código fuente VHDL
- `*.vhdl` — Código fuente VHDL (extensión alternativa)


## Convenciones de nomenclatura
- Ficheros en minúsculas con guión bajo: `mi_modulo.vhd`
- Entidades en minúsculas: `entity mi_modulo is`
- Carpetas numeradas con prefijo: `00-`, `01-`, `02-`...
