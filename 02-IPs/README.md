# 02-IPs

IPs del catálogo de Vivado.

## Tipos de ficheros
- `*.xci` — Fichero de configuración de IP de Vivado
- `*.xco` — Fichero de IP legacy (ISE)

## Estructura
```
02-IPs/
├── IP1/
│   └── ip1.xci
└── IP2/
    └── ip2.xci
```

## NOTA para GHDL/documentación
Los IPs de Vivado no son analizables por GHDL. Los errores
"unit not found in library" relacionados con IPs son esperados
y están marcados como warnings en el reporte de GHDL.
