# 00-Libraries

IPs propios en formato Vivado IP Repository.

## Estructura de cada IP
```
module1/
├── sources/     # Código fuente Verilog/VHDL del IP
├── xgui/        # GUI del IP para Vivado
└── *.xml        # Descriptor del IP (component.xml)
```

## Añadir al proyecto Vivado
En Vivado: Tools → Settings → IP → Repository → Añadir ruta a 00-Libraries
