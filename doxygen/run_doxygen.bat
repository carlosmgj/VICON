@echo off
setlocal

REM Obtener directorio donde está este .bat
set DOXYGEN_DIR=%~dp0

REM Ir al directorio 
cd /d "%DOXYGEN_DIR%"

REM Generar diagrama de jerarquía VHDL
py -3.11 scripts\generate_hierarchy.py ..\projects\vicon_cmgj
if errorlevel 1 (
    echo.
    echo ERROR generando jerarquía VHDL.
    pause
    exit /b 1
)

REM Ejecutar doxygen con Doxyfile tres niveles arriba
doxygen "%DOXYGEN_DIR%\Doxyfile"

REM Comprobar si Doxygen terminó correctamente
if errorlevel 1 (
    echo.
    echo ERROR ejecutando Doxygen.
    pause
    exit /b 1
)

REM Abrir index.html generado
set INDEX_FILE=%DOXYGEN_DIR%\docs\html\index.html

if exist "%INDEX_FILE%" (
    start "" "%INDEX_FILE%"
) else (
    echo No se encontró %INDEX_FILE%
    pause
)

endlocal
