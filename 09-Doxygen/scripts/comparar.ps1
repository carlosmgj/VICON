$folder1 = "C:\Users\cmgomezj\Documents\WORKSPACE\VM_W11\GIT_METEOR\FW\00-PROJECT_STRUCTURE\"
$folder2 = "C:\Users\cmgomezj\Documents\WORKSPACE\VICON_2\"

# 1. Filtros de exclusión (compilados y carpetas de sistema)
$excludeExt = @("*.pyc", "*.pyo", "*.pyd", "*.exe", "*.dll", "*.obj", "*.bin", "*.docx", "*.puml", "*.cf", "*.json", "vsg_report.txt", "ghdl_report.txt", "reports.dox")
$excludeDirs = "__pycache__|\.venv|venv|\.git|\.vs"

Write-Host "Iniciando comparación estilo Git..." -ForegroundColor Yellow

Get-ChildItem -Path $folder1 -Recurse -File -Exclude $excludeExt | ForEach-Object {
    
    if ($_.FullName -notmatch $excludeDirs) {
        $relativePath = $_.FullName.Replace($folder1, "")
        $targetFile = Join-Path $folder2 $relativePath

        if (Test-Path $targetFile) {
            # Normalización (opcional, si prefieres ver las diferencias reales quita el -replace)
            $c1 = Get-Content $_.FullName | ForEach-Object { $_ -replace 'C:\\Users\\[^\\]+\\.*\\', '...\' -replace ':\d+:\d+:', ':XX:XX:' }
            $c2 = Get-Content $targetFile | ForEach-Object { $_ -replace 'C:\\Users\\[^\\]+\\.*\\', '...\' -replace ':\d+:\d+:', ':XX:XX:' }

            $diffs = Compare-Object $c1 $c2
            
            if ($diffs) {
                Write-Host "`n--- diff / $relativePath" -ForegroundColor White
                foreach ($line in $diffs) {
                    if ($line.SideIndicator -eq "=>") {
                        # Lo que está en Carpeta 2 pero no en 1 (Añadido)
                        Write-Host "+ $($line.InputObject)" -ForegroundColor Green
                    }
                    elseif ($line.SideIndicator -eq "<=") {
                        # Lo que está en Carpeta 1 pero no en 2 (Eliminado)
                        Write-Host "- $($line.InputObject)" -ForegroundColor Red
                    }
                }
            }
        }
    }
}

Write-Host "`nComparación finalizada." -ForegroundColor Cyan
pause