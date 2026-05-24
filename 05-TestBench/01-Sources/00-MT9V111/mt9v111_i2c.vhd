--! \file mt9v111.vhd
--! \brief Agente de simulación I2C esclavo del MT9V111.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mt9v111_i2c is
    generic (
        g_I2C_ADDR  : std_logic_vector(6 downto 0) := "1011100";  --! Dirección I2C de 7 bits del MT9V111 (0x5C)
        g_IMG_WIDTH : integer                       := 640;        --! Ancho de imagen (no usado aquí; ver cam_sim)
        g_IMG_HEIGHT: integer                       := 480         --! Alto de imagen  (no usado aquí; ver cam_sim)
    );
    port (
        pixclk_o : out std_logic;                     --! Reloj de píxel generado internamente (\todo conectar a cam_sim)
        fvalid_o : out std_logic;                     --! Frame valid (\todo conectar a cam_sim)
        lvalid_o : out std_logic;                     --! Line valid  (\todo conectar a cam_sim)
        data_o   : out std_logic_vector(7 downto 0); --! Datos de imagen (\todo conectar a cam_sim)
        scl_i    : in    std_logic;                   --! Reloj I2C (entrada)
        sda_io   : inout std_logic                    --! Datos I2C (open-drain bidireccional)
    );
end entity mt9v111_i2c;

architecture sim of mt9v111_i2c is

    ---------------------------------------------------------------------------
    -- Constantes de simulación
    ---------------------------------------------------------------------------
    constant c_PIX_PERIOD     : time := 37 ns;      --! Periodo del reloj de píxel (~27 MHz)
    constant c_ACK_SETUP_TIME : time := 400 ns;     --! Tiempo de setup antes de conducir ACK tras Repeated START

    ---------------------------------------------------------------------------
    -- Tipos
    ---------------------------------------------------------------------------
    type t_reg_map is array (0 to 255) of std_logic_vector(15 downto 0);

    ---------------------------------------------------------------------------
    -- Reloj de píxel interno
    ---------------------------------------------------------------------------
    signal s_clk_int : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Bancos de registros del MT9V111
    -- \note Page select no implementado; regs_ifp declarado pero no accedido por I2C
    ---------------------------------------------------------------------------
    signal s_regs_core : t_reg_map := (
        16#00# => x"823A",   --! Chip ID (0xFF en la numeración del datasheet)
        16#0D# => x"0008",   --! Reset register
        others => x"CACA"    --! Valor por defecto para detectar accesos no inicializados
    );

    signal s_regs_ifp : t_reg_map := (
        16#01# => x"0001",   --! IFP: registro 1
        others => x"0FE0"    --! Valor por defecto IFP
    );

    ---------------------------------------------------------------------------
    -- Señales de debug — visibles en simulador para seguimiento del estado I2C
    ---------------------------------------------------------------------------
    signal s_reg_addr   : integer range 0 to 255 := 0;  --! Dirección del registro en curso (debug)
    signal s_debug_state : string(1 to 24) := (others => ' ');  --! Estado textual del proceso I2C (debug)

begin

    ---------------------------------------------------------------------------
    -- Generador de reloj de píxel
    -- \todo Eliminar cuando se use cam_sim como fuente de pixclk/fval/lval/data
    ---------------------------------------------------------------------------
    s_clk_int <= not s_clk_int after c_PIX_PERIOD / 2;
    pixclk_o  <= s_clk_int;
    fvalid_o  <= '0';
    lvalid_o  <= '0';
    data_o    <= (others => '0');

    ---------------------------------------------------------------------------
    --! \brief Proceso I2C esclavo — solo simulación
    --!
    --! Detecta START, lee dirección + R/W, y gestiona transacciones de
    --! escritura y lectura con auto-incremento de dirección de registro.
    ---------------------------------------------------------------------------
    p_i2c_slave : process
        variable v_addr_byte  : std_logic_vector(7 downto 0);
        variable v_rw         : std_logic := '0';               --! '0'=write, '1'=read
        variable v_reg_addr   : integer range 0 to 255;         --! Dirección base de la transacción
        variable v_reg_inc    : integer range 0 to 255;         --! Dirección con auto-incremento
        variable v_data_h     : std_logic_vector(7 downto 0);   --! Byte alto del registro
        variable v_data_l     : std_logic_vector(7 downto 0);   --! Byte bajo del registro
        variable v_data_16    : std_logic_vector(15 downto 0);  --! Dato completo de 16 bits
        variable v_stop_seen  : boolean;
        variable v_start_seen : boolean;
        variable v_mack       : std_logic;                      --! MACK leído del master ('0'=ACK, '1'=NACK)
    begin
        sda_io <= 'Z';

        loop  -- bucle exterior: esperar START y procesar transacción indefinidamente

            -----------------------------------------------------------------------
            -- Esperar condición START: SDA baja mientras SCL está alto
            -----------------------------------------------------------------------
            s_debug_state <= "WAIT_START              ";
            wait until falling_edge(sda_io) and scl_i = '1';
            s_debug_state <= "START_DETECTED          ";

            -----------------------------------------------------------------------
            -- Leer byte de dirección + R/W (8 bits, MSB primero)
            -----------------------------------------------------------------------
            for i in 7 downto 0 loop
                wait until rising_edge(scl_i);
                v_addr_byte(i) := sda_io;
            end loop;

            -----------------------------------------------------------------------
            -- Comprobar si la dirección coincide con la nuestra
            -----------------------------------------------------------------------
            if v_addr_byte(7 downto 1) = g_I2C_ADDR then

                s_debug_state <= "ADDR_MATCH              ";

                -- ACK de dirección
                wait until falling_edge(scl_i);
                sda_io <= '0';
                wait until rising_edge(scl_i);
                sda_io <= 'Z';
                wait until falling_edge(scl_i);

                -----------------------------------------------------------------------
                -- Leer dirección de registro (8 bits)
                -----------------------------------------------------------------------
                s_debug_state <= "RX_REG_ADDR             ";
                for i in 7 downto 0 loop
                    wait until rising_edge(scl_i);
                    v_addr_byte(i) := sda_io;
                end loop;

                v_reg_addr  := to_integer(unsigned(v_addr_byte));
                v_reg_inc   := v_reg_addr;
                s_reg_addr  <= v_reg_addr;

                -- ACK de dirección de registro
                wait until falling_edge(scl_i);
                sda_io <= '0';
                wait until rising_edge(scl_i);
                sda_io <= 'Z';
                wait until falling_edge(scl_i);

                v_stop_seen  := false;
                v_start_seen := false;
                v_rw         := '0';

                -------------------------------------------------------------------
                -- Bucle de datos: procesa pares DATA_H + DATA_L hasta STOP o NACK
                -------------------------------------------------------------------
                while not v_stop_seen loop

                    -------------------------------------------------------------------
                    -- DATA_H: escribir (recibir del master) o leer (enviar al master)
                    -------------------------------------------------------------------
                    s_debug_state <= "DATA_H                  ";
                    for i in 7 downto 0 loop

                        if v_rw = '0' then
                            -- WRITE: recibir bit del master
                            wait until rising_edge(scl_i);
                            v_data_h(i) := sda_io;
                            -- Detectar STOP o Repeated START mientras SCL está alto
                            wait until rising_edge(sda_io) or falling_edge(sda_io) or falling_edge(scl_i);
                            if scl_i = '1' then
                                if sda_io = '1' then
                                    v_stop_seen  := true;
                                    s_debug_state <= "STOP_IN_DATA_H          ";
                                    exit;
                                elsif sda_io = '0' then
                                    v_start_seen := true;
                                    s_debug_state <= "RSTART_IN_DATA_H        ";
                                    exit;
                                end if;
                            end if;
                        else
                            -- READ: enviar bit al master (byte alto del registro)
                            if i /= 7 then
                                wait until falling_edge(scl_i);
                            end if;
                            s_reg_addr <= v_reg_inc;
                            sda_io <= s_regs_core(v_reg_inc)(8 + i);
                            if i = 0 then
                                wait until falling_edge(scl_i);
                            end if;
                        end if;

                    end loop;

                    if v_stop_seen then exit; end if;

                    -------------------------------------------------------------------
                    -- Repeated START detectado: leer nueva dirección + R/W
                    -------------------------------------------------------------------
                    if v_start_seen then
                        v_start_seen := false;
                        s_debug_state <= "RX_RSTART_ADDR          ";

                        for i in 7 downto 0 loop
                            wait until rising_edge(scl_i);
                            v_addr_byte(i) := sda_io;
                            wait until rising_edge(sda_io) or falling_edge(sda_io) or falling_edge(scl_i);
                            if scl_i = '1' then
                                if sda_io = '1' then
                                    v_stop_seen  := true;
                                    s_debug_state <= "STOP_IN_RSTART_ADDR     ";
                                    exit;
                                elsif sda_io = '0' then
                                    v_start_seen := true;
                                    s_debug_state <= "RSTART_IN_RSTART_ADDR   ";
                                    exit;
                                end if;
                            end if;
                        end loop;

                        -- R/W del Repeated START (bit 0 del byte de dirección)
                        if v_addr_byte(0) = '1' then
                            v_rw := '1';   -- modo lectura
                        else
                            v_rw := '0';   -- Repeated START en modo write (inusual)
                        end if;

                        -- ACK de la dirección del Repeated START
                        wait for c_ACK_SETUP_TIME;
                        sda_io <= '0';
                        wait until rising_edge(scl_i);
                        sda_io <= 'Z';
                        wait until falling_edge(scl_i);

                        next;   -- reiniciar bucle con v_rw actualizado
                    end if;

                    -------------------------------------------------------------------
                    -- ACK / envío de DATA_H
                    -------------------------------------------------------------------
                    if v_rw = '0' then
                        -- WRITE: ACK del agente
                        s_debug_state <= "SACK_DATA_H             ";
                        sda_io <= '0';
                        wait until rising_edge(scl_i);
                        sda_io <= 'Z';
                    else
                        -- READ: leer MACK del master
                        sda_io <= 'Z';
                        wait until rising_edge(scl_i);
                        v_mack := sda_io;
                        if v_mack = '1' then
                            s_debug_state <= "NACK_AFTER_DATA_H       ";
                            exit;   -- master envió NACK → fin de lectura
                        end if;
                        s_debug_state <= "MACK_DATA_H             ";
                    end if;

                    wait until falling_edge(scl_i);

                    -------------------------------------------------------------------
                    -- DATA_L: escribir (recibir del master) o leer (enviar al master)
                    -------------------------------------------------------------------
                    s_debug_state <= "DATA_L                  ";
                    for i in 7 downto 0 loop

                        if v_rw = '0' then
                            -- WRITE: recibir bit
                            wait until rising_edge(scl_i);
                            v_data_l(i) := sda_io;
                            wait until rising_edge(sda_io) or falling_edge(sda_io) or falling_edge(scl_i);
                            if scl_i = '1' then
                                if sda_io = '1' then
                                    v_stop_seen  := true;
                                    s_debug_state <= "STOP_IN_DATA_L          ";
                                    exit;
                                elsif sda_io = '0' then
                                    v_start_seen := true;
                                    s_debug_state <= "RSTART_IN_DATA_L        ";
                                    exit;
                                end if;
                            end if;
                        else
                            -- READ: enviar bit al master (byte bajo del registro)
                            if i /= 7 then
                                wait until falling_edge(scl_i);
                            end if;
                            sda_io <= s_regs_core(v_reg_inc)(i);
                            if i = 0 then
                                wait until falling_edge(scl_i);
                            end if;
                        end if;

                    end loop;

                    -------------------------------------------------------------------
                    -- ACK / recepción de DATA_L
                    -------------------------------------------------------------------
                    if v_rw = '0' then
                        -- WRITE: ACK del agente + guardar dato en registro
                        s_debug_state <= "SACK_DATA_L             ";
                        sda_io <= '0';
                        wait until rising_edge(scl_i);
                        sda_io <= 'Z';
                        wait until falling_edge(scl_i);

                        -- Guardar par DATA_H:DATA_L en el banco de registros
                        v_data_16 := v_data_h & v_data_l;
                        s_regs_core(v_reg_inc) <= v_data_16;

                    else
                        -- READ: leer MACK del master
                        sda_io <= 'Z';
                        wait until rising_edge(scl_i);
                        v_mack := sda_io;
                        wait until falling_edge(scl_i);
                        if v_mack = '1' then
                            s_debug_state <= "NACK_AFTER_DATA_L       ";
                            exit;   -- master envió NACK → fin de lectura
                        end if;
                        s_debug_state <= "MACK_DATA_L             ";
                    end if;

                    -- Auto-incremento de dirección de registro
                    if v_reg_inc = 255 then
                        v_reg_inc := 0;
                    else
                        v_reg_inc := v_reg_inc + 1;
                    end if;
                    s_reg_addr <= v_reg_inc;

                end loop;  -- bucle de datos
            end if;        -- if dirección coincide

        end loop;  -- bucle exterior

    end process p_i2c_slave;

end architecture sim;
