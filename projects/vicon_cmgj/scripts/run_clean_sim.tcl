# 1. Reiniciar y ejecutar
restart
run 2 us

# 2. Localizar ruta del archivo
set proj_dir [get_property DIRECTORY [current_project]]
set proj_name [get_property NAME [current_project]]
set archivo_reporte "${proj_dir}/${proj_name}.sim/sim_1/behav/xsim/reporte_final_1.txt"

# Pausa para que el disco escriba el archivo
after 500

puts "\n======================================="
puts "      REPORTE Y MARCADORES"
puts "=======================================\n"

if {[file exists $archivo_reporte]} {
    # 3. Borrar marcadores anteriores para no acumular
    # get_markers devuelve la lista de marcadores en la wave window
    catch { delete_objects [get_markers] }

    set fp [open $archivo_reporte r]
    set contenido [read $fp]
    close $fp
    
    set lineas [split $contenido "\n"]
    set i 0
    foreach linea $lineas {
        if {[string length [string trim $linea]] > 0} {
            # Imprimir el mensaje en la consola de Vivado
            puts $linea
            
            # 4. Extraer el tiempo entre []
            if {[regexp {\[(.*?)\]} $linea -> timestamp]} {
                # ELIMINAR ESPACIOS: Convertimos "160000 ps" en "160000ps"
                set clean_time [string map {" " ""} $timestamp]
                
                # Añadir el marcador con nombre único
                if {[catch { add_wave_marker -time $clean_time -name "M$i" } err]} {
                    # Si falla, nos avisa por qué
                    puts "No se pudo poner marcador en $clean_time: $err"
                }
                incr i
            }
        }
    }
    
    # 5. Ajustar el zoom automáticamente para ver todos los marcadores
    catch { gui_zoom_full }
    
} else {
    puts "ERROR: No se encontró el archivo $archivo_reporte"
}
puts "\n======================================="