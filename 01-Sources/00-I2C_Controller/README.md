# 00-<Module_name>

Módulo principal del diseño. Renombrar esta carpeta con el nombre real del módulo.

## Tipos de ficheros
- `*.vhd` — Entidad y arquitectura del módulo

## Documentación Doxygen
Para documentar este módulo añadir en el .vhd:
```vhdl
--! \brief Descripción breve del módulo
--! \htmlonly
--! <script type="WaveDrom">{ "signal": [...] }</script>
--! \endhtmlonly
entity mi_modulo is
    port (
        clk : in std_logic;  --! Reloj del sistema
        ...
    );
```
