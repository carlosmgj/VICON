# 1. Reiniciar y ejecutar
restart
run 2 us

# 2. Construir la ruta desde el proyecto (Esto siempre tiene la propiedad DIRECTORY)
set proj_dir [get_property DIRECTORY [current_project]]
set proj_name [get_property NAME [current_project]]

# La ruta estándar donde xsim crea archivos es:
# <directorio_proyecto>/<nombre_proyecto>.sim/sim_1/behav/xsim/
set xsim_path "${proj_dir}/${proj_name}.sim/sim_1/behav/xsim"
set archivo_reporte "${xsim_path}/reporte_final_1.txt"

# 3. Pausa para que el sistema de archivos se actualice
after 500

puts "\n======================================="
puts "      REPORTE FINAL DE VERIFICACION"
puts "=======================================\n"

# 4. Intentar leer el archivo
if {[file exists $archivo_reporte]} {
    set fp [open $archivo_reporte r]
    set contenido [read $fp]
    close $fp
    
    if {[string length [string trim $contenido]] > 0} {
        puts $contenido
    } else {
        puts "ERROR: El archivo existe pero está vacío. Revisa el VHDL."
    }
} else {
    puts "ERROR: No se encontró el reporte en la ruta esperada:"
    puts "Buscado en: $archivo_reporte"
    puts "\n--- TIP DE DEPURACIÓN ---"
    puts "Si la ruta anterior no existe, comprueba en tu carpeta .sim"
    puts "si el set de simulación se llama 'sim_1' u otro nombre."
}

puts "\n======================================="