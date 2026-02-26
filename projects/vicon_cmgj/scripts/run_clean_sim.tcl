# 1. Cargar cambios del VHDL y reiniciar la simulación
# Es vital que sea lo primero para que compile los .vhd modificados

# 2. Localizar ruta del archivo
set proj_dir [get_property DIRECTORY [current_project]]
set proj_name [get_property NAME [current_project]]
set archivo_reporte "${proj_dir}/${proj_name}.sim/sim_1/behav/xsim/reporte_final_1.txt"

# 3. Limpieza: Borrar el archivo de log viejo para que no se mezclen resultados
if {[file exists $archivo_reporte]} {
    file delete -force $archivo_reporte
}

relaunch_sim

# 4. Ejecutar la simulación
run 2 us

# Pausa para que el sistema operativo vuelque los datos al disco
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
                #1 if {[catch { add_wave_marker -time $clean_time -name "M$i" } err]} {
                    # Si falla, nos avisa por qué
                #1     puts "No se pudo poner marcador en $clean_time: $err"
                #1 }
                #1 incr i
            }
        }
    }
    
    # 5. Ajustar el zoom automáticamente para ver todos los marcadores
    catch { gui_zoom_full }
    
} else {
    puts "ERROR: No se encontró el archivo $archivo_reporte"
}
puts "\n======================================="