--! \file mt9v111_agent.vhd
--! Agente de simulación MT9V111 con escritura y lectura múltiple (auto-increment).
--! El proceso I2C es continuo: tras cada transacción vuelve a esperar START.
--! CORREGIDO: Después de cada ACK, espera explícitamente a STOP o a más datos

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.sim_utils_pkg.all;

entity mt9v111_agent is
    generic (
        I2C_ADDR   : std_logic_vector(6 downto 0) := "1011100";
        IMG_WIDTH  : integer := 640;
        IMG_HEIGHT : integer := 480
    );
    port (
        pixclk : out std_logic;
        fval   : out std_logic;
        lval   : out std_logic;
        dout   : out std_logic_vector(7 downto 0);
        scl    : in    std_logic;
        sda    : inout std_logic
    );
end mt9v111_agent;

architecture Behavioral of mt9v111_agent is

    constant PIX_PERIOD : time := 37 ns;
    signal clk_int : std_logic := '0';

    type reg_map_t is array (0 to 255) of std_logic_vector(15 downto 0);

    signal regs_core : reg_map_t := (
        16#00# => x"823A",
        16#0D# => x"0008",
        others => x"CACA"
    );

    signal regs_ifp : reg_map_t := (
        16#01# => x"0001",
        others => x"0FE0"
    );

    -- Registro base para lectura: el master primero escribe addr_reg en modo
    -- write, luego hace Repeated START en modo read. Guardamos addr_reg entre
    -- las dos fases en esta señal compartida.
    signal read_reg_addr : integer range 0 to 255 := 0;
    
    signal debug_state : string(1 to 20) := (others => ' ');
begin

    clk_int <= not clk_int after PIX_PERIOD / 2;
    pixclk  <= clk_int;
    fval    <= '0';
    lval    <= '0';
    dout    <= (others => '0');

    ---------------------------------------------------------------------------
    -- Proceso I2C esclavo continuo.
    --
    -- Secuencia WRITE:
    --   S + ADDR_WR + ACK + REG_ADDR + ACK + DATA_H + ACK + DATA_L + ACK + [más regs] + P
    --
    -- Secuencia READ (el master hace dos transacciones seguidas):
    --   1ª: S + ADDR_WR + ACK + REG_ADDR + ACK  (establece el registro a leer)
    --   2ª: Sr + ADDR_RD + ACK + [agente envía DATA_H + master ACK + DATA_L + master ACK/NACK] + P
    ---------------------------------------------------------------------------
    i2c_slave : process
        variable v_addr_byte : std_logic_vector(7 downto 0);
        variable v_rw        : std_logic;
        variable v_reg_addr  : integer range 0 to 255;
        variable v_reg_inc   : integer range 0 to 255;
        variable v_data_h    : std_logic_vector(7 downto 0);
        variable v_data_l    : std_logic_vector(7 downto 0);
        variable v_data_16   : std_logic_vector(15 downto 0);
        variable v_stop_seen : boolean;
        variable v_mack      : std_logic;
        variable v_send_byte : std_logic_vector(7 downto 0);

    begin
        sda <= 'Z';

        -- Loop exterior: una iteración = una transacción I2C completa
        loop

            ---------------"01234567890123456789"
            debug_state <= "ESPERANDO_START  (0)";


            wait until falling_edge(sda) and scl = '1';
            log_to_file("reporte_final_1.txt", "I2C Agente: START detectado", false);
            
            ---------------"01234567890123456789"
            debug_state <= "START DETECTED  (2) ";

            for i in 7 downto 0 loop
                wait until rising_edge(scl);
                v_addr_byte(i) := sda;
            end loop;
            v_rw := v_addr_byte(0);   -- '0'=Write  '1'=Read

            ---------------"01234567890123456789"
            debug_state <= "LEYENDO_ADDR    (34)";

            if v_addr_byte(7 downto 1) = I2C_ADDR then

                ---------------"01234567890123456789"
                debug_state <= "ADDR_OK         (34)";
            
                wait until falling_edge(scl);

                ---------------"01234567890123456789"
                debug_state <= "ADDR_SACK       (36)";
                sda <= '0';

                wait until rising_edge(scl);  -- Espera a que master lea el ACK
                ---------------"01234567890123456789"
                debug_state <= "SACK_READ       (38)";
                sda <= 'Z';

                wait until falling_edge(scl);  -- SCL baja después de leer ACK

                -- ============================================================
                -- MODO WRITE (R/W='0')
                -- ============================================================
                if v_rw = '0' then

                    log_to_file("reporte_final_1.txt","I2C Agente: Direccion reconocida, modo WRITE", false);

                    ---------------"01234567890123456789"
                    debug_state <= "READING REG_ADDR(42)";

                    for i in 7 downto 0 loop
                        wait until rising_edge(scl);
                        v_addr_byte(i) := sda;
                    end loop;
                    
                    ---------------"01234567890123456789"
                    debug_state <= "SAVE REG_ADDR   (70)";

                    v_reg_addr   := to_integer(unsigned(v_addr_byte));
                    v_reg_inc    := v_reg_addr;
                    read_reg_addr <= v_reg_addr;   -- guardar para posible lectura posterior

                    wait until falling_edge(scl);

                    ---------------"01234567890123456789"
                    debug_state <= "REG_ADDR_SACK   (72)";
                    sda <= '0';

                    wait until rising_edge(scl);  -- Espera a que master lea el ACK
                    ---------------"01234567890123456789"
                    debug_state <= "SACK_READ       (74)";
                    sda <= 'Z';

                    wait until falling_edge(scl);  -- SCL baja después de leer ACK

                    log_to_file("reporte_final_1.txt", "I2C Agente: Registro base 0x" & int_to_hex_str(v_reg_addr, 2), false);

                    -- Bucle de recepción de datos con auto-increment.
                    -- Termina al detectar STOP (SDA sube con SCL alto).
                    v_stop_seen := false;

                    while not v_stop_seen loop

                        -- ------------------------------------------------
                        -- Recibir DATA_H
                        -- ------------------------------------------------
                        debug_state <= "LEYENDO_DATA_H      ";
                        

                        for i in 7 downto 0 loop
                            wait until rising_edge(scl);
                            
                            -- SCL está alto. Leer el bit.
                            v_data_h(i) := sda;
                            
                            -- Ahora esperar: ¿SDA sube (potencial STOP) o SCL baja primero?
                            -- IMPORTANTE: Solo es STOP si SDA sube MIENTRAS SCL está alto
                            wait until rising_edge(sda) or falling_edge(scl);
                            
                            -- Checar cuál evento ocurrió
                            if sda = '1' and scl = '1' then
                                -- SDA subió MIENTRAS SCL seguía alto = STOP
                                v_stop_seen := true;
                                debug_state <= "STOP_DETECTADO      ";
                                log_to_file("reporte_final_1.txt", 
                                    "I2C Agente: STOP detectado en bit " & integer'image(i), false);
                                exit;
                            else
                                debug_state <= "MAS_DATOS           ";
                                -- SCL bajó primero, o SDA ya estaba en '1'
                                -- Es un bit normal ('1' o '0'), continuar leyendo
                                wait until falling_edge(scl);
                                
                            end if;
                            
                        end loop;

                        -- Si vimos STOP, no seguir adelante
                        if v_stop_seen then
                            exit;  -- Salir del while también
                        end if;

                        ---------------"01234567890123456789"
                        debug_state <= "SAVE REG_V_MSB (106)";

                        -- ACK DATA_H
                        debug_state <= "ACK_DATA_H          ";


                        wait until falling_edge(scl);

                        ---------------"01234567890123456789"
                        debug_state <= "REGV_SACK      (108)";
                        sda <= '0';

                        wait until rising_edge(scl);  -- Espera a que master lea el ACK
                        ---------------"01234567890123456789"
                        debug_state <= "SACK_READ      (110)";
                        sda <= 'Z';

                        wait until falling_edge(scl);  -- SCL baja después de leer ACK

                        -- ------------------------------------------------
                        -- Recibir DATA_L
                        -- ------------------------------------------------
                        debug_state <= "LEYENDO_DATA_L      ";

                        for i in 7 downto 0 loop
                            wait until rising_edge(scl);
                            
                            v_data_h(i) := sda;

                            -- SDA aún está bajo, esperar a que suba o SCL baje
                            wait until rising_edge(sda) or falling_edge(scl);
                            
                            if sda = '1' then
                                -- SDA subió ANTES de que SCL bajara = STOP
                                v_stop_seen := true;
                                ---------------"01234567890123456789"
                                debug_state <= "STOP_DETECTADO      ";
                                log_to_file("reporte_final_1.txt", "I2C Agente: STOP detectado, fin escritura", false);
                            else
                                -- SCL bajó primero (sda = '0') = hay más datos
                                ---------------"01234567890123456789"
                                debug_state <= "MAS_DATOS           ";

                            end if;
                        end loop;
                        
                        ---------------"01234567890123456789"
                        debug_state <= "SAVE REG_V_LSB (142)";

                        -- ACK DATA_L
                        wait until falling_edge(scl);

                        ---------------"01234567890123456789"
                        debug_state <= "REGV_SACK      (144)";
                        sda <= '0';

                        wait until rising_edge(scl);  -- Espera a que master lea el ACK
                        ---------------"01234567890123456789"
                        debug_state <= "SACK_READ      (146)";
                        sda <= 'Z';

                        wait until falling_edge(scl);  -- SCL baja después de leer ACK
                        ---------------"01234567890123456789"
                        debug_state <= "               (148)";


                        -- Guardar con auto-increment
                        v_data_16 := v_data_h & v_data_l;
                        regs_core(v_reg_inc) <= v_data_16;

                        log_to_file("reporte_final_1.txt","I2C Agente: Reg 0x" & int_to_hex_str(v_reg_inc, 2) & " = 0x" & int_to_hex_str(to_integer(unsigned(v_data_16)), 4), false);

                        if v_reg_inc = 255 then
                            v_reg_inc := 0;
                        else
                            v_reg_inc := v_reg_inc + 1;
                        end if;
                    
                    end loop;

                -- ============================================================
                -- MODO READ (R/W='1')
                -- El master ya nos indicó el registro en la transacción write
                -- previa (guardado en read_reg_addr).
                -- El agente conduce SDA con los bits del registro solicitado.
                -- El master controla SCL en todo momento.
                -- ============================================================
                else

                    log_to_file("reporte_final_1.txt", "I2C Agente: Direccion reconocida, modo READ desde reg 0x" & int_to_hex_str(read_reg_addr, 2), false);

                    v_reg_inc   := read_reg_addr;
                    v_stop_seen := false;

                    while not v_stop_seen loop

                        -- ------------------------------------------------
                        -- Enviar DATA_H del registro actual
                        -- ------------------------------------------------
                        debug_state <= "(R) ENVIANDO_DATA_H ";
                        v_send_byte := regs_core(v_reg_inc)(15 downto 8);

                        for i in 7 downto 0 loop
                            -- Esperar flanco de bajada de SCL para cambiar SDA
                            wait until falling_edge(scl);
                            sda <= v_send_byte(i);
                        end loop;

                        -- Soltar SDA para que el master envíe ACK
                        wait until falling_edge(scl);
                        sda <= 'Z';

                        -- Leer ACK del master (flanco de subida de SCL)
                        debug_state <= "LEYENDO_ACK_H       ";
                        wait until rising_edge(scl);
                        v_mack := sda;

                        if v_mack = '1' then
                            -- NACK: el master no quiere más datos
                            v_stop_seen := true;
                            log_to_file("reporte_final_1.txt",
                                "I2C Agente: NACK recibido tras DATA_H, fin lectura", false);
                        else
                            -- ------------------------------------------------
                            -- Enviar DATA_L del mismo registro
                            -- ------------------------------------------------
                            debug_state <= "ENVIANDO_DATA_L     ";
                            v_send_byte := regs_core(v_reg_inc)(7 downto 0);

                            for i in 7 downto 0 loop
                                wait until falling_edge(scl);
                                sda <= v_send_byte(i);
                            end loop;

                            -- Soltar SDA para ACK del master
                            wait until falling_edge(scl);
                            sda <= 'Z';

                            -- Leer ACK/NACK del master
                            debug_state <= "LEYENDO_ACK_L       ";
                            wait until rising_edge(scl);
                            v_mack := sda;

                            log_to_file("reporte_final_1.txt",
                                "I2C Agente: Reg 0x" & int_to_hex_str(v_reg_inc, 2) &
                                " leido: 0x" & int_to_hex_str(
                                    to_integer(unsigned(regs_core(v_reg_inc))), 4), false);

                            if v_mack = '1' then
                                -- NACK: fin de lectura
                                v_stop_seen := true;
                                log_to_file("reporte_final_1.txt",
                                    "I2C Agente: NACK recibido, fin lectura multiple", false);
                            else
                                -- ACK: auto-increment y continuar
                                if v_reg_inc = 255 then
                                    v_reg_inc := 0;
                                else
                                    v_reg_inc := v_reg_inc + 1;
                                end if;
                            end if;

                        end if;

                    end loop;

                    -- Esperar STOP del master
                    debug_state <= "ESPERANDO_STOP_READ ";
                    wait until rising_edge(sda) and scl = '1';
                    log_to_file("reporte_final_1.txt",
                        "I2C Agente: STOP detectado, fin lectura", false);

                end if; -- v_rw

            else
                -- Dirección no reconocida
                debug_state <= "ADDR_INVALIDO       ";
                log_to_file("reporte_final_1.txt",
                    "I2C Agente: Direccion no reconocida, ignorando", false);
                wait until rising_edge(sda) and scl = '1';

            end if; -- I2C_ADDR

        end loop; -- loop exterior

    end process i2c_slave;

end Behavioral;