## \file mmcm.tcl
## \brief Script de test para la practica EC24
## \section author Author
## Carlos Manuel Gomez Jimenez, DNI: 76037985P


# Reiniciamos simulacion para resetar
restart


set script_dir [file normalize [file dirname [info script]]]

set wcfg_path [file normalize "$script_dir/../src/sim/sim_config.wcfg"]

if {[get_wave_configs] == ""} {
    if {[file exists $wcfg_path]} {
        open_wave_config $wcfg_path
        puts "\[INFO\] Cargada configuración visual desde: $wcfg_path"
    } else {
        puts "\[ERROR\] No se encontró el archivo .wcfg en: $wcfg_path"
    }
}



puts "\[INFO\]--------- Iniciado reloj de 100 MHz"
add_force {/TOP/CLK} -radix bin {0 0ns} {1 5ns} -repeat_every 10ns ;

puts "\[STEP 1\] ------------------- Condiciones Iniciales de botones a 0"
add_force {/TOP/BTN(0)} -radix hex {0 0ns}  ; # Initial BTN(0) (reset)
add_force {/TOP/BTN(4)} -radix hex {0 0ns}  ; # Initial BTN(4) (a)
add_force {/TOP/BTN(2)} -radix hex {0 0ns}  ; # Initial BTN(2) (b)
run 30 ns

puts "\[INFO\]--------- FSM pulso(20ns) de RST"
add_force {/TOP/BTN(0)} -radix hex {1 0ns} {0 100ns}  ; 
run 2000ns
