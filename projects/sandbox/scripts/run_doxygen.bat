@echo off
setlocal

REM Obtener directorio donde está este .bat
set SCRIPT_DIR=%~dp0

REM Ir al directorio del script
cd /d "%SCRIPT_DIR%"

REM Ejecutar doxygen con Doxyfile tres niveles arriba
doxygen "%SCRIPT_DIR%..\..\..\Doxyfile"

endlocal
