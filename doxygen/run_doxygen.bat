@echo off
setlocal

REM ============================================================
REM CONFIGURACIÓN
REM ============================================================

REM Rutas
set DOXYGEN_DIR=%~dp0
set PROJECT_DIR=%DOXYGEN_DIR%..\projects\vicon_cmgj
set REPORTS_DIR=%DOXYGEN_DIR%reports
set RTL_DIR=%PROJECT_DIR%\src\rtl
set TB_DIR=%PROJECT_DIR%\tb

REM VSG: fail_on_error=1 para parar el bat si hay errores de estilo
set VSG_ENABLED=1
set VSG_FAIL_ON_ERROR=0
set VSG_DETAIL=1

REM GHDL: fail_on_error=1 para parar el bat si hay errores de sintaxis
set GHDL_ENABLED=1
set GHDL_FAIL_ON_ERROR=0
set GHDL_DETAIL=1
set VSG_CONFIG=1

REM ============================================================

cd /d "%DOXYGEN_DIR%"

REM Crear carpeta de reportes si no existe
if not exist "%REPORTS_DIR%" mkdir "%REPORTS_DIR%"

REM ============================================================
REM ANÁLISIS SINTÁCTICO CON GHDL
REM ============================================================
if "%GHDL_ENABLED%"=="1" (
    echo.
    echo [GHDL] Analizando sintaxis VHDL...

    REM Limpiar reporte anterior
    if exist "%REPORTS_DIR%\ghdl_report.txt" del "%REPORTS_DIR%\ghdl_report.txt"

    REM Analizar RTL primero (orden de compilación)
    for %%f in ("%RTL_DIR%\*.vhd") do (
        ghdl -a --std=08 --work=work "%%f" >> "%REPORTS_DIR%\ghdl_report.txt" 2>&1
    )

    REM Analizar TB después
    for %%f in ("%TB_DIR%\*.vhd") do (
        ghdl -a --std=08 --work=work "%%f" >> "%REPORTS_DIR%\ghdl_report.txt" 2>&1
    )

    if "%GHDL_DETAIL%"=="0" (
        find /c "error" "%REPORTS_DIR%\ghdl_report.txt" > "%REPORTS_DIR%\ghdl_summary.txt"
    )

    REM Comprobar si hay errores reales en el reporte
    find /i "error:" "%REPORTS_DIR%\ghdl_report.txt" >nul 2>&1
    if errorlevel 1 (
        echo [GHDL] OK - Sin errores de sintaxis.
    ) else (
        echo [GHDL] Se encontraron errores de sintaxis. Ver reports\ghdl_report.txt
        if "%GHDL_FAIL_ON_ERROR%"=="1" (
            echo ERROR: Parando por errores de sintaxis GHDL.
            pause
            exit /b 1
        )
    )
)

REM ============================================================
REM CHEQUEO DE ESTILO CON VSG
REM ============================================================
if "%VSG_ENABLED%"=="1" (
    echo.
    echo [VSG] Comprobando estilo VHDL...

    if exist "%REPORTS_DIR%\vsg_report.txt" del "%REPORTS_DIR%\vsg_report.txt"

    if "%VSG_CONFIG%"=="1" (
        if "%VSG_DETAIL%"=="1" (
            vsg -f "%RTL_DIR%\*.vhd" "%TB_DIR%\*.vhd" --output_format syntastic -c "%DOXYGEN_DIR%scripts\vsg_config.yaml" > "%REPORTS_DIR%\vsg_report.txt" 2>&1
        ) else (
            vsg -f "%RTL_DIR%\*.vhd" "%TB_DIR%\*.vhd" --output_format summary -c "%DOXYGEN_DIR%scripts\vsg_config.yaml" > "%REPORTS_DIR%\vsg_report.txt" 2>&1
        )
    ) else (
        if "%VSG_DETAIL%"=="1" (
            vsg -f "%RTL_DIR%\*.vhd" "%TB_DIR%\*.vhd" --output_format syntastic > "%REPORTS_DIR%\vsg_report.txt" 2>&1
        ) else (
            vsg -f "%RTL_DIR%\*.vhd" "%TB_DIR%\*.vhd" --output_format summary > "%REPORTS_DIR%\vsg_report.txt" 2>&1
        )
    )

    find /i "ERROR:" "%REPORTS_DIR%\vsg_report.txt" >nul 2>&1
    if errorlevel 1 (
        echo [VSG] OK - Sin problemas de estilo.
    ) else (
        echo [VSG] Se encontraron problemas de estilo. Ver reports\vsg_report.txt
        if "%VSG_FAIL_ON_ERROR%"=="1" (
            echo ERROR: Parando por errores de estilo VSG.
            pause
            exit /b 1
        )
    )
)

REM ============================================================
REM GENERAR reports.dox
REM ============================================================
echo.
echo [REPORTS] Generando página de reportes...
py -3.11 scripts\generate_reports.py "%REPORTS_DIR%"
if errorlevel 1 (
    echo AVISO: No se pudo generar la página de reportes.
)

REM ============================================================
REM JERARQUÍA VHDL
REM ============================================================
echo.
echo [HIERARCHY] Generando jerarquía VHDL...
py -3.11 scripts\generate_hierarchy.py "%PROJECT_DIR%"
if errorlevel 1 (
    echo.
    echo ERROR generando jerarquía VHDL.
    pause
    exit /b 1
)

REM ============================================================
REM FECHA DE GENERACIÓN
REM ============================================================
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set DT=%%I
set BUILD_DATE=%DT:~6,2%/%DT:~4,2%/%DT:~0,4%
echo \var build_date %BUILD_DATE% > content\builddate.dox

REM ============================================================
REM DOXYGEN
REM ============================================================
echo.
echo [DOXYGEN] Generando documentación...
doxygen "%DOXYGEN_DIR%\Doxyfile"
if errorlevel 1 (
    echo.
    echo ERROR ejecutando Doxygen.
    pause
    exit /b 1
)

REM ============================================================
REM ABRIR RESULTADO
REM ============================================================
set INDEX_FILE=%DOXYGEN_DIR%\docs\html\index.html
if exist "%INDEX_FILE%" (
    start "" "%INDEX_FILE%"
) else (
    echo No se encontró %INDEX_FILE%
    pause
)

endlocal