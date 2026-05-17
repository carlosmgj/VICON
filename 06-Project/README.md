# 06-Project

Proyecto de Vivado.

## Tipos de ficheros
- `create_project.tcl` — Script TCL para recrear el proyecto de Vivado desde cero
- `run_synth.tcl` — Script de síntesis
- `run_impl.tcl` — Script de implementación TBD
- `run_sim.tcl` — Script de simulación desde Vivado TBD

## IMPORTANTE
El proyecto de Vivado (.xpr y carpeta generada) NO se incluye en el control
de versiones. Se regenera ejecutando `create_project.tcl`:
```
vivado -mode batch -source create_project.tcl
```
