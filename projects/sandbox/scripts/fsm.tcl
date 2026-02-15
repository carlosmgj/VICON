## \file fsm.tcl
## \brief Script de test para la FSM del ejercicio 2.
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
add_force {/TOP/BTN(0)} -radix hex {1 0ns} {0 20ns}  ; 
run 40ns

puts "\[STEP 2\]--------- TEST: S0 to S0"
# Aqui deberiamos ver que se queda en s0 con a'.
# a'.b'
run 50ns
# a'.b
add_force {/TOP/BTN(2)} -radix hex {1 0ns} {0 30ns}  ;
run 50ns
#Salida esperada para las dos casuisticas: no sale de s0 y se encienden LED(1) y LED(5).

set sim_time [current_time]
puts "\[STEP 3\] $sim_time --------- TEST: S0 to S1"

# a.b'
add_force {/TOP/BTN(4)} -radix hex {1 0ns} {0 10ns}  ;
run 50ns
    # Transicion a s1, donde se encienden los LED(1) y LED(6).
    # Como ha durado mas de un pulso de reloj, la FSM deberia haber vuelto a s0 o s1 aleatoriamente donde haya acabado.
    # Salida para s0: se encienden LED(1) y LED(5) & se apaga LED(6).

# Encendemos b para comprobar que no sale de s1 
add_force {/TOP/BTN(2)} -radix hex {1 0ns} {0 10ns}  ;
run 40ns

# Volvemos a s0 habilitando A  
add_force {/TOP/BTN(4)} -radix hex {1 0ns} {0 10ns}  ;
run 50ns
    # Transicion a s1, donde se encienden los LED(1) y LED(6).
    # Como NO ha durado mas de un pulso de reloj, la FSM deberia quedarse en s1.

puts "\[STEP 4\]--------- TEST: S0 to S2"

# Habilitamos A y B para pasar a S2 
add_force {/TOP/BTN(2)} -radix hex {1 0ns} {0 10ns}  ;
add_force {/TOP/BTN(4)} -radix hex {1 0ns} {0 10ns}  ;
run 50ns
    # La FSM deberia estar en s2 hasta el siguiente ciclo de reloj
    # Deberia haberse activado Y0 en la transición.

# Vamos a habilitarlo más tiempo para ver que se queda alternando 
add_force {/TOP/BTN(2)} -radix hex {1 0ns} {0 30ns}  ;
add_force {/TOP/BTN(4)} -radix hex {1 0ns} {0 30ns}  ;
run 50ns
    # La FSM alterna entre s0 y s2.
    # Salida para s0: se encienden LED(1) y LED(5) & se apaga LED(6).

puts "\[STEP 5\]--------- RESET ASINCRONO"
add_force {/TOP/BTN(4)} -radix hex {1 0ns} {0 10ns}  ;
run 30ns
set sim_time [current_time]
puts "tiempo de reset 1: $sim_time"
add_force {/TOP/BTN(0)} -radix hex {1 0ns} {0 5ns}  ;
run 30ns
add_force {/TOP/BTN(2)} -radix hex {1 0ns} {0 10ns}  ;
add_force {/TOP/BTN(4)} -radix hex {1 0ns} {0 10ns}  ;
run 10ns
set sim_time [current_time]
puts "tiempo de reset 2: $sim_time"
add_force {/TOP/BTN(0)} -radix hex {1 0ns} {0 5ns}  ;
run 50ns
