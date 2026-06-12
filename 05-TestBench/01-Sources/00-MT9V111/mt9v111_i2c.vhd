--! \file mt9v111_i2c.vhd
--! \brief Agente de simulacion I2C esclavo del MT9V111.
--!
--! Protocolo MT9V111 segun datasheet:
--!
--!   WRITE (16-bit):
--!     START -> ADDR_W -> REG_ADDR -> DATA_H -> DATA_L -> STOP
--!
--!   READ (16-bit) con Repeated START:
--!     START -> ADDR_W -> REG_ADDR -> RSTART -> ADDR_R -> DATA_H -> DATA_L -> NACK -> STOP
--!
--!   READ (16-bit) con dos transacciones separadas:
--!     START -> ADDR_W -> REG_ADDR -> STOP
--!     START -> ADDR_R -> DATA_H -> DATA_L -> NACK -> STOP
--!
--! Page select: escritura en reg 0x01
--!   0x0004 -> Core,  0x0001 -> IFP
--!
--! \note Solo valido en simulacion. No sintetizable.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mt9v111_i2c is
    generic (
        g_I2C_ADDR : std_logic_vector(6 downto 0) := "1011100"
    );
    port (
        scl_i  : in    std_logic;
        sda_io : inout std_logic
    );
end entity mt9v111_i2c;

architecture sim of mt9v111_i2c is

    type t_reg_map is array (0 to 255) of std_logic_vector(15 downto 0);

    signal s_regs_core : t_reg_map := (
        16#36# => x"823A",
        16#FF# => x"823A",
        16#0D# => x"0008",
        others => x"CACA"
    );

    signal s_regs_ifp : t_reg_map := (
        16#01# => x"0001",
        others => x"0FE0"
    );

    signal s_current_page : std_logic          := '0';
    signal s_reg_addr     : integer range 0 to 255 := 0;
    signal s_debug_state  : string(1 to 24)    := (others => ' ');

begin

    p_i2c_slave : process
        variable v_addr_byte    : std_logic_vector(7 downto 0);
        variable v_data_h       : std_logic_vector(7 downto 0);
        variable v_data_l       : std_logic_vector(7 downto 0);
        variable v_data_16      : std_logic_vector(15 downto 0);
        variable v_bit          : std_logic;
        variable v_reg_addr     : integer range 0 to 255 := 0;
        variable v_current_page : std_logic := '0';
        variable v_rstart       : boolean   := false;
        variable v_stop         : boolean   := false;

        ---------------------------------------------------------------------------
        -- Espera START o Repeated START: SDA baja con SCL alto
        ---------------------------------------------------------------------------
        procedure wait_start is
        begin
            s_debug_state <= "WAIT_START              ";
            loop
                wait until To_X01(sda_io) = '0';
                exit when To_X01(scl_i) = '1';
            end loop;
            s_debug_state <= "START_DETECTED          ";
        end procedure;

        ---------------------------------------------------------------------------
        -- Lee 8 bits MSB primero.
        -- Detecta Repeated START (SDA baja con SCL alto) o STOP (SDA sube con SCL alto)
        -- durante la lectura y los reporta en v_rstart/v_stop.
        -- Si se detecta, el byte leido hasta ese momento es invalido.
        ---------------------------------------------------------------------------
        procedure read_byte (
            variable b       : out std_logic_vector(7 downto 0);
            variable rstart  : out boolean;
            variable stop    : out boolean
        ) is
            variable v_b        : std_logic;
            variable v_sda_prev : std_logic;
        begin
            rstart := false;
            stop   := false;
            b      := (others => '0');

            for i in 7 downto 0 loop
                -- Esperar flanco de subida de SCL
                wait until To_X01(scl_i) = '1';

                -- Guardar SDA al subir SCL
                v_sda_prev := To_X01(sda_io);
                v_b        := v_sda_prev;
                if v_b = 'X' then v_b := '0'; end if;
                b(i) := v_b;

                -- Mientras SCL esta alto, vigilar cambios de SDA
                -- Un cambio aqui es RSTART (SDA baja) o STOP (SDA sube)
                loop
                    wait on scl_i, sda_io;
                    if To_X01(scl_i) = '0' then
                        exit;  -- bajada normal de SCL, continuar
                    end if;
                    -- SCL sigue alto y SDA cambio
                    if To_X01(sda_io) = '0' and v_sda_prev /= '0' then
                        rstart := true;
                        return;
                    end if;
                    if To_X01(sda_io) = '1' and v_sda_prev /= '1' then
                        stop := true;
                        return;
                    end if;
                    v_sda_prev := To_X01(sda_io);
                end loop;

            end loop;
        end procedure;

        ---------------------------------------------------------------------------
        -- Envia ACK: conduce SDA='0' durante el pulso de ACK
        -- Llamar justo despues de read_byte (SCL ya esta bajo)
        ---------------------------------------------------------------------------
        procedure send_ack is
        begin
            sda_io <= '0';
            wait until To_X01(scl_i) = '1';
            wait until To_X01(scl_i) = '0';
            sda_io <= 'Z';
        end procedure;

        ---------------------------------------------------------------------------
        -- Envia un byte MSB primero en modo lectura
        -- Cada bit se pone en SDA en el flanco de bajada de SCL
        ---------------------------------------------------------------------------
        procedure send_byte (
            constant b : in std_logic_vector(7 downto 0)
        ) is
        begin
            -- SCL ya esta bajo al entrar: poner bit 7 inmediatamente
            sda_io <= b(7);
            for i in 6 downto 0 loop
                wait until To_X01(scl_i) = '0';
                sda_io <= b(i);
            end loop;
            -- Soltar SDA para el ACK/NACK del master
            wait until To_X01(scl_i) = '0';
            sda_io <= 'Z';
        end procedure;

        ---------------------------------------------------------------------------
        -- Lee el ACK/NACK del master (1 pulso de SCL)
        -- Devuelve '0'=ACK, '1'=NACK
        ---------------------------------------------------------------------------
        procedure read_mack (variable mack : out std_logic) is
        begin
            wait until To_X01(scl_i) = '1';
            mack := To_X01(sda_io);
            if mack = 'X' then mack := '1'; end if;
            wait until To_X01(scl_i) = '0';
        end procedure;

        ---------------------------------------------------------------------------
        -- Realiza la transmision de datos en modo lectura
        ---------------------------------------------------------------------------
        procedure do_read is
            variable v_mack : std_logic;
        begin
            s_debug_state <= "TX_DATA                 ";
            s_reg_addr    <= v_reg_addr;

            if v_current_page = '0' then
                send_byte(s_regs_core(v_reg_addr)(15 downto 8));
                -- Esperar bajada de SCL tras el ACK del master antes del segundo byte
                wait until To_X01(scl_i) = '0';
                send_byte(s_regs_core(v_reg_addr)(7  downto 0));
            else
                send_byte(s_regs_ifp(v_reg_addr)(15 downto 8));
                wait until To_X01(scl_i) = '0';
                send_byte(s_regs_ifp(v_reg_addr)(7  downto 0));
            end if;

            read_mack(v_mack);

            if To_X01(v_mack) = '1' then
                s_debug_state <= "READ_DONE_NACK          ";
            else
                s_debug_state <= "READ_DONE_ACK           ";
            end if;
        end procedure;

    begin
        sda_io <= 'Z';

        loop
            -----------------------------------------------------------------------
            -- Esperar START
            -----------------------------------------------------------------------
            wait_start;

            -----------------------------------------------------------------------
            -- Leer byte de direccion + R/W
            -----------------------------------------------------------------------
            read_byte(v_addr_byte, v_rstart, v_stop);

            if v_rstart or v_stop then next; end if;
            if v_addr_byte(7 downto 1) /= g_I2C_ADDR then next; end if;

            s_debug_state <= "ADDR_MATCH              ";
            send_ack;

            -----------------------------------------------------------------------
            -- Modo lectura directa (START -> ADDR_R -> DATA)
            -----------------------------------------------------------------------
            if v_addr_byte(0) = '1' then
                do_read;
                next;
            end if;

            -----------------------------------------------------------------------
            -- Modo escritura: recibir REG_ADDR
            -----------------------------------------------------------------------
            s_debug_state <= "RX_REG_ADDR             ";
            read_byte(v_addr_byte, v_rstart, v_stop);

            if v_rstart or v_stop then next; end if;

            v_reg_addr := to_integer(unsigned(v_addr_byte));
            s_reg_addr <= v_reg_addr;
            send_ack;

            -----------------------------------------------------------------------
            -- Intentar leer DATA_H
            -- Puede llegar: dato normal, Repeated START, o STOP
            -----------------------------------------------------------------------
            s_debug_state <= "RX_DATA_H               ";
            read_byte(v_data_h, v_rstart, v_stop);

            -- STOP: transaccion de solo direccion (para lectura posterior)
            if v_stop then
                s_debug_state <= "ADDR_ONLY_STOP          ";
                next;
            end if;

            -- Repeated START: cambiar a modo lectura
            if v_rstart then
                s_debug_state <= "RSTART_DETECTED         ";
                -- Leer byte de direccion del Repeated START
                read_byte(v_addr_byte, v_rstart, v_stop);
                if v_rstart or v_stop then next; end if;
                if v_addr_byte(7 downto 1) /= g_I2C_ADDR then next; end if;
                if v_addr_byte(0) /= '1' then next; end if;  -- debe ser lectura
                send_ack;
                do_read;
                next;
            end if;

            -- Dato normal: enviar ACK y leer DATA_L
            send_ack;

            s_debug_state <= "RX_DATA_L               ";
            read_byte(v_data_l, v_rstart, v_stop);
            send_ack;

            v_data_16 := v_data_h & v_data_l;

            -- Page select: reg 0x01
            if v_reg_addr = 1 then
                if v_data_16 = x"0004" then
                    v_current_page := '0';
                    s_current_page <= '0';
                    s_debug_state  <= "PAGE_SEL_CORE           ";
                elsif v_data_16 = x"0001" then
                    v_current_page := '1';
                    s_current_page <= '1';
                    s_debug_state  <= "PAGE_SEL_IFP            ";
                end if;
            end if;

            -- Guardar en banco activo
            if v_current_page = '0' then
                s_regs_core(v_reg_addr) <= v_data_16;
            else
                s_regs_ifp(v_reg_addr) <= v_data_16;
            end if;

            s_debug_state <= "WRITE_DONE              ";

        end loop;

    end process p_i2c_slave;

end architecture sim;
