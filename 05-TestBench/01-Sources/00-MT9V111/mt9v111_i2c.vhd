--! \file mt9v111_i2c.vhd
--! \brief Agente de simulación I2C esclavo del MT9V111.
--!
--! Implementa el comportamiento del bus I2C del sensor MT9V111.
--! Soporta escritura y lectura de registros de 16 bits con auto-incremento.
--!
--! \note Las líneas I2C son open-drain. El TOP conduce '0' o 'Z' (nunca '1').
--!       Con el pull-up del testbench (s_scl_bus='H', s_sda_bus='H'), los
--!       niveles altos llegan como 'H', no como '1'. Por eso todas las
--!       comparaciones y detecciones de flanco usan To_X01() para normalizar
--!       'H'→'1' y 'L'→'0' antes de evaluar.
--!
--! \note Solo válido en simulación — usa wait. No sintetizable.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mt9v111_i2c is
    generic (
        g_I2C_ADDR : std_logic_vector(6 downto 0) := "1011100"  --! Dirección I2C de 7 bits del MT9V111 (0x5C)
    );
    port (
        scl_i  : in    std_logic;  --! Reloj I2C (entrada, open-drain: '0' o 'H')
        sda_io : inout std_logic   --! Datos I2C (open-drain bidireccional)
    );
end entity mt9v111_i2c;

architecture sim of mt9v111_i2c is

    ---------------------------------------------------------------------------
    -- Tipos
    ---------------------------------------------------------------------------
    type t_reg_map is array (0 to 255) of std_logic_vector(15 downto 0);

    ---------------------------------------------------------------------------
    -- Bancos de registros del MT9V111
    -- \note Page select no implementado; s_regs_ifp declarado pero no accedido
    ---------------------------------------------------------------------------
    signal s_regs_core : t_reg_map := (
        16#FF# => x"823A",  --! Chip ID (registro 0xFF, page 0)
        16#0D# => x"0008",  --! Reset register
        others => x"CACA"   --! Valor centinela para detectar accesos no inicializados
    );

    signal s_regs_ifp : t_reg_map := (
        16#01# => x"0001",  --! IFP: registro 1
        others => x"0FE0"   --! Valor por defecto IFP
    );

    ---------------------------------------------------------------------------
    -- Señales de debug
    ---------------------------------------------------------------------------
    signal s_reg_addr    : integer range 0 to 255 := 0;             --! Dirección del registro en curso
    signal s_debug_state : string(1 to 24)        := (others => ' '); --! Estado textual del proceso I2C

begin

    ---------------------------------------------------------------------------
    --! \brief Proceso I2C esclavo — solo simulación
    --!
    --! Todas las comparaciones de nivel usan To_X01() para normalizar
    --! 'H'→'1' y 'L'→'0', ya que el bus open-drain presenta 'H'/'L'
    --! en lugar de '1'/'0' cuando está en reposo con pull-up.
    ---------------------------------------------------------------------------
    p_i2c_slave : process
        variable v_addr_byte  : std_logic_vector(7 downto 0);
        variable v_rw         : std_logic := '0';
        variable v_reg_addr   : integer range 0 to 255;
        variable v_reg_inc    : integer range 0 to 255;
        variable v_data_h     : std_logic_vector(7 downto 0);
        variable v_data_l     : std_logic_vector(7 downto 0);
        variable v_data_16    : std_logic_vector(15 downto 0);
        variable v_stop_seen  : boolean;
        variable v_start_seen : boolean;
        variable v_mack       : std_logic;
        variable v_bit        : std_logic;
    begin
        sda_io <= 'Z';

        loop  -- bucle exterior: esperar START y procesar transacción

            -----------------------------------------------------------------------
            -- Esperar condición START: SDA baja mientras SCL está alto
            -- Usando eventos en SDA + comprobación de SCL con To_X01
            -----------------------------------------------------------------------
            s_debug_state <= "WAIT_START              ";
            loop
                wait on sda_io, scl_i;
                exit when To_X01(sda_io) = '0' and To_X01(scl_i) = '1';
            end loop;
            s_debug_state <= "START_DETECTED          ";

            -----------------------------------------------------------------------
            -- Leer byte de dirección + R/W (8 bits, MSB primero)
            -- wait on scl_i + To_X01: normaliza 'H'→'1' para detectar flancos en bus open-drain
            -----------------------------------------------------------------------
            for i in 7 downto 0 loop
                wait on scl_i; while To_X01(scl_i) /= '1' loop wait on scl_i; end loop;
                v_bit := To_X01(sda_io);
                if v_bit = 'X' then v_bit := '0'; end if;
                v_addr_byte(i) := v_bit;
            end loop;

            -----------------------------------------------------------------------
            -- Comprobar si la dirección coincide
            -----------------------------------------------------------------------
            if v_addr_byte(7 downto 1) = g_I2C_ADDR then

                s_debug_state <= "ADDR_MATCH              ";

                -- ACK de dirección
                wait on scl_i; while To_X01(scl_i) /= '0' loop wait on scl_i; end loop;
                sda_io <= '0';
                wait on scl_i; while To_X01(scl_i) /= '1' loop wait on scl_i; end loop;
                sda_io <= 'Z';
                wait on scl_i; while To_X01(scl_i) /= '0' loop wait on scl_i; end loop;

                -----------------------------------------------------------------------
                -- Leer dirección de registro (8 bits)
                -----------------------------------------------------------------------
                s_debug_state <= "RX_REG_ADDR             ";
                for i in 7 downto 0 loop
                    wait on scl_i; while To_X01(scl_i) /= '1' loop wait on scl_i; end loop;
                    v_bit := To_X01(sda_io);
                    if v_bit = 'X' then v_bit := '0'; end if;
                    v_addr_byte(i) := v_bit;
                end loop;

                v_reg_addr := to_integer(unsigned(v_addr_byte));
                v_reg_inc  := v_reg_addr;
                s_reg_addr <= v_reg_addr;

                -- ACK de dirección de registro
                wait on scl_i; while To_X01(scl_i) /= '0' loop wait on scl_i; end loop;
                sda_io <= '0';
                wait on scl_i; while To_X01(scl_i) /= '1' loop wait on scl_i; end loop;
                sda_io <= 'Z';
                wait on scl_i; while To_X01(scl_i) /= '0' loop wait on scl_i; end loop;

                v_stop_seen  := false;
                v_start_seen := false;
                v_rw         := '0';

                -------------------------------------------------------------------
                -- Bucle de datos
                -------------------------------------------------------------------
                while not v_stop_seen loop

                    -------------------------------------------------------------------
                    -- DATA_H
                    -------------------------------------------------------------------
                    s_debug_state <= "DATA_H                  ";
                    for i in 7 downto 0 loop

                        if v_rw = '0' then
                            -- WRITE: recibir bit
                            wait on scl_i; while To_X01(scl_i) /= '1' loop wait on scl_i; end loop;
                            v_bit := To_X01(sda_io);
                            if v_bit = 'X' then v_bit := '0'; end if;
                            v_data_h(i) := v_bit;
                            -- Detectar STOP o Repeated START con SCL alto
                            wait on sda_io, scl_i;
                            if To_X01(scl_i) = '1' then
                                if To_X01(sda_io) = '1' then
                                    v_stop_seen  := true;
                                    s_debug_state <= "STOP_IN_DATA_H          ";
                                    exit;
                                elsif To_X01(sda_io) = '0' then
                                    v_start_seen := true;
                                    s_debug_state <= "RSTART_IN_DATA_H        ";
                                    exit;
                                end if;
                            end if;
                        else
                            -- READ: enviar bit al master
                            if i /= 7 then
                                wait on scl_i; while To_X01(scl_i) /= '0' loop wait on scl_i; end loop;
                            end if;
                            s_reg_addr <= v_reg_inc;
                            sda_io <= s_regs_core(v_reg_inc)(8 + i);
                            if i = 0 then
                                wait on scl_i; while To_X01(scl_i) /= '0' loop wait on scl_i; end loop;
                            end if;
                        end if;

                    end loop;

                    if v_stop_seen then exit; end if;

                    -------------------------------------------------------------------
                    -- Repeated START: leer nueva dirección + R/W
                    -------------------------------------------------------------------
                    if v_start_seen then
                        v_start_seen := false;
                        s_debug_state <= "RX_RSTART_ADDR          ";

                        for i in 7 downto 0 loop
                            wait on scl_i; while To_X01(scl_i) /= '1' loop wait on scl_i; end loop;
                            v_bit := To_X01(sda_io);
                            if v_bit = 'X' then v_bit := '0'; end if;
                            v_addr_byte(i) := v_bit;
                            wait on sda_io, scl_i;
                            if To_X01(scl_i) = '1' then
                                if To_X01(sda_io) = '1' then
                                    v_stop_seen  := true;
                                    s_debug_state <= "STOP_IN_RSTART_ADDR     ";
                                    exit;
                                elsif To_X01(sda_io) = '0' then
                                    v_start_seen := true;
                                    s_debug_state <= "RSTART_IN_RSTART_ADDR   ";
                                    exit;
                                end if;
                            end if;
                        end loop;

                        if v_addr_byte(0) = '1' then
                            v_rw := '1';
                        else
                            v_rw := '0';
                        end if;

                        -- ACK del Repeated START — SCL ya está bajo
                        sda_io <= '0';
                        wait on scl_i; while To_X01(scl_i) /= '1' loop wait on scl_i; end loop;
                        sda_io <= 'Z';
                        wait on scl_i; while To_X01(scl_i) /= '0' loop wait on scl_i; end loop;

                        next;
                    end if;

                    -------------------------------------------------------------------
                    -- ACK/MACK tras DATA_H
                    -------------------------------------------------------------------
                    if v_rw = '0' then
                        s_debug_state <= "SACK_DATA_H             ";
                        sda_io <= '0';
                        wait on scl_i; while To_X01(scl_i) /= '1' loop wait on scl_i; end loop;
                        sda_io <= 'Z';
                    else
                        sda_io <= 'Z';
                        wait on scl_i; while To_X01(scl_i) /= '1' loop wait on scl_i; end loop;
                        v_mack := To_X01(sda_io);
                        if v_mack /= '0' then
                            s_debug_state <= "NACK_AFTER_DATA_H       ";
                            exit;
                        end if;
                        s_debug_state <= "MACK_DATA_H             ";
                    end if;

                    wait on scl_i; while To_X01(scl_i) /= '0' loop wait on scl_i; end loop;

                    -------------------------------------------------------------------
                    -- DATA_L
                    -------------------------------------------------------------------
                    s_debug_state <= "DATA_L                  ";
                    for i in 7 downto 0 loop

                        if v_rw = '0' then
                            wait on scl_i; while To_X01(scl_i) /= '1' loop wait on scl_i; end loop;
                            v_bit := To_X01(sda_io);
                            if v_bit = 'X' then v_bit := '0'; end if;
                            v_data_l(i) := v_bit;
                            wait on sda_io, scl_i;
                            if To_X01(scl_i) = '1' then
                                if To_X01(sda_io) = '1' then
                                    v_stop_seen  := true;
                                    s_debug_state <= "STOP_IN_DATA_L          ";
                                    exit;
                                elsif To_X01(sda_io) = '0' then
                                    v_start_seen := true;
                                    s_debug_state <= "RSTART_IN_DATA_L        ";
                                    exit;
                                end if;
                            end if;
                        else
                            if i /= 7 then
                                wait on scl_i; while To_X01(scl_i) /= '0' loop wait on scl_i; end loop;
                            end if;
                            sda_io <= s_regs_core(v_reg_inc)(i);
                            if i = 0 then
                                wait on scl_i; while To_X01(scl_i) /= '0' loop wait on scl_i; end loop;
                            end if;
                        end if;

                    end loop;

                    -------------------------------------------------------------------
                    -- ACK/MACK tras DATA_L
                    -------------------------------------------------------------------
                    if v_rw = '0' then
                        s_debug_state <= "SACK_DATA_L             ";
                        sda_io <= '0';
                        wait on scl_i; while To_X01(scl_i) /= '1' loop wait on scl_i; end loop;
                        sda_io <= 'Z';
                        wait on scl_i; while To_X01(scl_i) /= '0' loop wait on scl_i; end loop;

                        v_data_16 := v_data_h & v_data_l;
                        s_regs_core(v_reg_inc) <= v_data_16;
                    else
                        sda_io <= 'Z';
                        wait on scl_i; while To_X01(scl_i) /= '1' loop wait on scl_i; end loop;
                        v_mack := To_X01(sda_io);
                        wait on scl_i; while To_X01(scl_i) /= '0' loop wait on scl_i; end loop;
                        if v_mack /= '0' then
                            s_debug_state <= "NACK_AFTER_DATA_L       ";
                            exit;
                        end if;
                        s_debug_state <= "MACK_DATA_L             ";
                    end if;

                    -- Auto-incremento
                    if v_reg_inc = 255 then
                        v_reg_inc := 0;
                    else
                        v_reg_inc := v_reg_inc + 1;
                    end if;
                    s_reg_addr <= v_reg_inc;

                end loop;
            end if;

        end loop;

    end process p_i2c_slave;

end architecture sim;
