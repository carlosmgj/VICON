# Reiniciamos simulacion para resetar
restart

puts "\[INFO\]--------- Iniciado reloj de 100 MHz"
add_force {/TOP/CLK} -radix bin {0 0ns} {1 5ns} -repeat_every 10ns ;
add_force {/TOP/BTN(0)} -radix bin {0 0ns} {1 40ns} {0 140ns} ;
run 700ns
add_force {/TOP/BTN(0)} -radix bin {1 0ns} {0 100ns} ;
run 15000ns