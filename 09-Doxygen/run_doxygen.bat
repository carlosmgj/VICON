@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM CONFIGURACIÓN
REM ============================================================

REM Rutas base
set DOXYGEN_DIR=%~dp0
set PROJECT_DIR=%DOXYGEN_DIR%..

REM Carpetas de fuentes VHDL
set RTL_DIR=%PROJECT_DIR%\01-Sources
set TB_DIR=%PROJECT_DIR%\05-TestBench\01-Sources

REM Carpetas de salida y contenido
set REPORTS_DIR=%PROJECT_DIR%\00-Documents\00-Reports
set CONTENT_DIR=%PROJECT_DIR%\00-Documents\01-Doxygen\00-ExtraContent
set OUTPUT_DIR=%PROJECT_DIR%\00-Documents\01-Doxygen

set PLANTUML_JAR=C:\tools\plantuml.jar
set DOX_EXTRA_CONTENT=%CONTENT_DIR%


REM ============================================================
REM FLAGS DE CONFIGURACIÓN
REM ============================================================

REM VSG
set VSG_ENABLED=1
set VSG_FAIL_ON_ERROR=0
set VSG_DETAIL=1
set VSG_CONFIG=1

REM GHDL
set GHDL_ENABLED=1
set GHDL_FAIL_ON_ERROR=0
set GHDL_DETAIL=1

REM Word
set WORD_ENABLED=1
set WORD_FAIL_ON_ERROR=0

REM ============================================================

cd /d "%DOXYGEN_DIR%"

REM Crear carpetas necesarias si no existen
if not exist "%REPORTS_DIR%" mkdir "%REPORTS_DIR%"
if not exist "%CONTENT_DIR%" mkdir "%CONTENT_DIR%"
if not exist "%OUTPUT_DIR%\html" mkdir "%OUTPUT_DIR%\html"

REM ============================================================
REM ANÁLISIS SINTÁCTICO CON GHDL
REM Primero RTL (recursivo), luego TB (recursivo)
REM ============================================================
if "%GHDL_ENABLED%"=="1" (
    echo.
    echo [GHDL] Analizando sintaxis VHDL...

    if exist "%REPORTS_DIR%\ghdl_report.txt" del "%REPORTS_DIR%\ghdl_report.txt"

    REM Analizar RTL recursivamente (orden: fichero por fichero)
    for /r "%RTL_DIR%" %%f in (*.vhd *.vhdl) do (
        ghdl -a --std=08 --work=work "%%f" >> "%REPORTS_DIR%\ghdl_report.txt" 2>&1
    )

    REM Analizar TB recursivamente después del RTL
    for /r "%TB_DIR%" %%f in (*.vhd *.vhdl) do (
        ghdl -a --std=08 --work=work "%%f" >> "%REPORTS_DIR%\ghdl_report.txt" 2>&1
    )

    find /i "error:" "%REPORTS_DIR%\ghdl_report.txt" >nul 2>&1
    if errorlevel 1 (
        echo [GHDL] OK - Sin errores de sintaxis.
    ) else (
        echo [GHDL] Se encontraron errores de sintaxis. Ver 00-Documents\00-Reports\ghdl_report.txt
        if "%GHDL_FAIL_ON_ERROR%"=="1" (
            echo ERROR: Parando por errores de sintaxis GHDL.
            pause
            exit /b 1
        )
    )
)

REM ============================================================
REM CHEQUEO DE ESTILO CON VSG
REM Busca recursivamente en todas las carpetas *Sources*
REM ============================================================
if "%VSG_ENABLED%"=="1" (
    echo.
    echo [VSG] Comprobando estilo VHDL...

    if exist "%REPORTS_DIR%\vsg_report.txt" del "%REPORTS_DIR%\vsg_report.txt"

    REM Recoger todos los .vhd recursivamente en carpetas *Sources*
    set VHD_LIST=
    for /r "%PROJECT_DIR%" %%f in (*.vhd *.vhdl) do (
        echo %%~pf | findstr /i "Sources" >nul 2>&1
        if not errorlevel 1 set VHD_LIST=!VHD_LIST! "%%f"
    )

    if defined VHD_LIST (
        if "%VSG_CONFIG%"=="1" (
            if "%VSG_DETAIL%"=="1" (
                vsg -f !VHD_LIST! --output_format syntastic -c "%DOXYGEN_DIR%scripts\vsg_config.yaml" > "%REPORTS_DIR%\vsg_report.txt" 2>&1
            ) else (
                vsg -f !VHD_LIST! --output_format summary -c "%DOXYGEN_DIR%scripts\vsg_config.yaml" > "%REPORTS_DIR%\vsg_report.txt" 2>&1
            )
        ) else (
            if "%VSG_DETAIL%"=="1" (
                vsg -f !VHD_LIST! --output_format syntastic > "%REPORTS_DIR%\vsg_report.txt" 2>&1
            ) else (
                vsg -f !VHD_LIST! --output_format summary > "%REPORTS_DIR%\vsg_report.txt" 2>&1
            )
        )
    ) else (
        echo [VSG] No se encontraron ficheros VHDL en carpetas Sources.
    )

    find /i "ERROR:" "%REPORTS_DIR%\vsg_report.txt" >nul 2>&1
    if errorlevel 1 (
        echo [VSG] OK - Sin problemas de estilo.
    ) else (
        echo [VSG] Se encontraron problemas de estilo. Ver 00-Documents\00-Reports\vsg_report.txt
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
py -3.11 scripts\generate_reports.py "%REPORTS_DIR%" --out "%CONTENT_DIR%\reports.dox"
if errorlevel 1 (
    echo AVISO: No se pudo generar la página de reportes.
)

REM ============================================================
REM JERARQUÍA VHDL
REM ============================================================
echo.
echo [HIERARCHY] Generando jerarquía VHDL...
py -3.11 scripts\generate_hierarchy.py "%PROJECT_DIR%" --out "%CONTENT_DIR%\hierarchy.dox"
if errorlevel 1 (
    echo.
    echo ERROR generando jerarquía VHDL.
    pause
    exit /b 1
)

REM ============================================================
REM DOCUMENTO WORD DE DISEÑO
REM ============================================================
if not "%WORD_ENABLED%"=="1" goto :skip_word

echo.
echo [WORD] Generando documento Word de diseño...

where node >nul 2>&1
if errorlevel 1 (
    echo AVISO: Node.js no encontrado en PATH, omitiendo generacion Word.
    goto :skip_word
)

if not exist "%DOXYGEN_DIR%scripts\node_modules\docx" (
    echo [WORD] Instalando dependencia docx en scripts\...
    cd /d "%DOXYGEN_DIR%scripts"
    npm install docx --no-save
    cd /d "%DOXYGEN_DIR%"
)
echo [WORD] Directorio actual: %CD%

echo PLANTUML_JAR=%PLANTUML_JAR%

set PLANTUML_ARGS=--plantuml plantuml
if defined PLANTUML_JAR set PLANTUML_ARGS=--plantuml-jar "%PLANTUML_JAR%"

py -3.11 scripts\generate_word.py "%PROJECT_DIR%" --config "%DOXYGEN_DIR%doc_config.yaml" --out "%OUTPUT_DIR%\design_document.docx" --diagrams-dir "%OUTPUT_DIR%\diagrams" %PLANTUML_ARGS%

if errorlevel 1 (
    echo AVISO: No se pudo generar el documento Word.
    if "%WORD_FAIL_ON_ERROR%"=="1" ( pause & exit /b 1 )
) else (
    echo [WORD] OK - %OUTPUT_DIR%\design_document.docx
)

:skip_word


REM ============================================================
REM FECHA DE GENERACIÓN
REM ============================================================
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "Get-Date -Format 'dd/MM/yyyy'"`) do set BUILD_DATE=%%D
echo \var build_date %BUILD_DATE% > "%CONTENT_DIR%\builddate.dox"

REM ============================================================
REM DOXYGEN
REM ============================================================
echo.
echo [DOXYGEN] Generando documentación...
doxygen "%DOXYGEN_DIR%Doxyfile"
if errorlevel 1 (
    echo.
    echo ERROR ejecutando Doxygen.
    pause
    exit /b 1
)

REM ============================================================
REM ABRIR RESULTADO
REM ============================================================
set INDEX_FILE=%OUTPUT_DIR%\html\index.html
if exist "%INDEX_FILE%" (
    start "" "%INDEX_FILE%"
) else (
    echo No se encontró %INDEX_FILE%
    pause
)

endlocal


REM Abrir Word si se generó
if "%WORD_ENABLED%"=="1" (
    set WORD_FILE=%OUTPUT_DIR%\design_document.docx
    if exist "!WORD_FILE!" (
        start "" "!WORD_FILE!"
    )
)