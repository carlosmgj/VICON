--! \file cmd_processor.vhd
--! \brief Procesador de comandos recibidos del PC vía FT232H.
--!
--! Recibe bytes serie del ftdi_controller y los interpreta como comandos.
--! Protocolo: [0xBB] [CMD] [ARG0] [ARG1] [ARG2] [ARG3]  (6 bytes fijos)
--!
--! Comandos soportados:
--!   0x01 — LED:       ARG0 = valor 8 bits para los LEDs de la Basys3
--!   0x02 — I2C write: ARG0=page, ARG1=reg, ARG2=val_hi, ARG3=val_lo
--!   0x03 — I2C read:  ARG0=page, ARG1=reg  (ARG2/ARG3 ignorados)
--!
--! El acceso al bus I2C solo está activo cuando la inicialización del TOP
--! ha terminado (i2c_grant_i='1'). Antes de ese punto los comandos I2C
--! se descartan silenciosamente.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.config_pkg.all;

--! \fsm_show_actions
entity cmd_processor is
    generic (
        g_I2C_FIFO_DEPTH : integer := c_MT9V111_I2C_FIFO_DEPTH  --! Profundidad de la FIFO I2C (para rango de num_regs)
    );
    port (
        clk_i   : in std_logic;  --! Reloj del dominio ftdi_clk (60 MHz)
        reset_i : in std_logic;  --! Reset síncrono activo alto

        -- Bytes entrantes del ftdi_controller
        rx_data_i  : in std_logic_vector(7 downto 0);  --! Byte recibido del PC
        rx_valid_i : in std_logic;                     --! Pulso de 1 ciclo cuando rx_data_i es válido

        -- Control de LEDs
        led_o      : out std_logic_vector(7 downto 0);  --! Valor a mostrar en los LEDs bajos

        -- Interfaz con i2c_master (solo activa cuando i2c_grant_i='1')
        i2c_grant_i    : in  std_logic;  --! '1' = inicialización terminada, el bus I2C es nuestro
        i2c_busy_i     : in  std_logic;  --! i2c_master ocupado
        i2c_done_i     : in  std_logic;  --! Pulso de fin de transacción
        i2c_error_i    : in  std_logic;  --! Pulso de error en transacción
        i2c_rd_empty_i : in  std_logic;  --! FIFO de lectura vacía
        i2c_rd_data_i  : in  std_logic_vector(15 downto 0);  --! Dato leído del sensor

        i2c_start_o    : out std_logic;                      --! Pulso de inicio de transacción
        i2c_rw_o       : out std_logic;                      --! '0'=escritura, '1'=lectura
        i2c_num_regs_o : out integer range 1 to g_I2C_FIFO_DEPTH;
        i2c_addr_reg_o : out std_logic_vector(7 downto 0);   --! Dirección del registro
        i2c_wr_push_o  : out std_logic;                      --! Encolar dato en FIFO de escritura
        i2c_wr_data_o  : out std_logic_vector(15 downto 0);  --! Dato a escribir
        i2c_rd_pop_o   : out std_logic                       --! Extraer dato de FIFO de lectura
    );
end entity cmd_processor;

architecture rtl of cmd_processor is

    -- Marcador y códigos de comando
    constant c_CMD_MARKER    : std_logic_vector(7 downto 0) := x"BB";
    constant c_CMD_LED       : std_logic_vector(7 downto 0) := x"01";
    constant c_CMD_I2C_WRITE : std_logic_vector(7 downto 0) := x"02";
    constant c_CMD_I2C_READ  : std_logic_vector(7 downto 0) := x"03";

    -- Número de bytes de argumento por comando (todos tienen 4)
    constant c_NUM_ARGS : integer := 4;

    type t_rx_state is (
        ST_WAIT_MARKER,  --! Esperando el byte 0xBB de inicio
        ST_WAIT_CMD,     --! Esperando el byte de comando
        ST_WAIT_ARGS,    --! Acumulando los 4 bytes de argumentos
        ST_EXECUTE       --! Ejecutar el comando recibido
    );

    type t_exec_state is (
        ST_EXEC_IDLE,        --! Sin comando pendiente
        ST_EXEC_I2C_FILL,    --! Encolar dato en FIFO de escritura I2C
        ST_EXEC_I2C_START,   --! Lanzar transacción I2C
        ST_EXEC_I2C_WAIT,    --! Esperar a que el i2c_master termine
        ST_EXEC_I2C_DRAIN    --! Extraer resultado de lectura I2C
    );

    signal s_rx_state   : t_rx_state   := ST_WAIT_MARKER;
    signal s_exec_state : t_exec_state := ST_EXEC_IDLE;

    signal s_cmd      : std_logic_vector(7 downto 0) := (others => '0');
    signal s_args     : std_logic_vector(31 downto 0) := (others => '0');  --! ARG3..ARG0 empaquetados
    signal s_arg_cnt  : integer range 0 to c_NUM_ARGS - 1 := 0;
    signal s_cmd_rdy  : std_logic := '0';  --! Pulso interno: comando completo listo para ejecutar

    signal s_led_r    : std_logic_vector(7 downto 0) := (others => '0');

begin

    led_o <= s_led_r;

    ---------------------------------------------------------------------------
    -- Recepción de bytes y ensamblado del comando
    -- Corre en ftdi_clk; los bytes llegan uno a uno con rx_valid_i
    ---------------------------------------------------------------------------
    p_rx : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if reset_i = '1' then
                s_rx_state <= ST_WAIT_MARKER;
                s_cmd      <= (others => '0');
                s_args     <= (others => '0');
                s_arg_cnt  <= 0;
                s_cmd_rdy  <= '0';
            else
                s_cmd_rdy <= '0';

                if rx_valid_i = '1' then
                    case s_rx_state is

                        -- Buscar el marcador 0xBB; cualquier otro byte se ignora
                        when ST_WAIT_MARKER =>
                            if rx_data_i = c_CMD_MARKER then
                                s_rx_state <= ST_WAIT_CMD;
                            end if;

                        -- Byte de comando
                        when ST_WAIT_CMD =>
                            s_cmd      <= rx_data_i;
                            s_arg_cnt  <= 0;
                            s_rx_state <= ST_WAIT_ARGS;

                        -- 4 bytes de argumentos; ARG0 llega primero (byte más significativo)
                        when ST_WAIT_ARGS =>
                            s_args    <= s_args(23 downto 0) & rx_data_i;  --! shift-in ARG
                            if s_arg_cnt = c_NUM_ARGS - 1 then
                                s_cmd_rdy  <= '1';
                                s_rx_state <= ST_WAIT_MARKER;  --! Listo para siguiente comando
                            else
                                s_arg_cnt <= s_arg_cnt + 1;
                            end if;

                        when others =>
                            s_rx_state <= ST_WAIT_MARKER;

                    end case;
                end if;
            end if;
        end if;
    end process p_rx;

    ---------------------------------------------------------------------------
    -- Ejecución del comando
    -- s_args(31..24)=ARG0, (23..16)=ARG1, (15..8)=ARG2, (7..0)=ARG3
    ---------------------------------------------------------------------------
    p_exec : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if reset_i = '1' then
                s_exec_state   <= ST_EXEC_IDLE;
                s_led_r        <= (others => '0');
                i2c_start_o    <= '0';
                i2c_rw_o       <= '0';
                i2c_num_regs_o <= 1;
                i2c_addr_reg_o <= (others => '0');
                i2c_wr_push_o  <= '0';
                i2c_wr_data_o  <= (others => '0');
                i2c_rd_pop_o   <= '0';
            else
                i2c_start_o   <= '0';
                i2c_wr_push_o <= '0';
                i2c_rd_pop_o  <= '0';

                case s_exec_state is

                    when ST_EXEC_IDLE =>
                        if s_cmd_rdy = '1' then
                            case s_cmd is

                                -- LED: aplicar ARG0 directamente a los LEDs
                                when c_CMD_LED =>
                                    s_led_r      <= s_args(31 downto 24);
                                    -- no hay estado adicional, vuelve a idle

                                -- I2C write/read: solo si el bus es nuestro
                                when c_CMD_I2C_WRITE | c_CMD_I2C_READ =>
                                    if i2c_grant_i = '1' then
                                        s_exec_state <= ST_EXEC_I2C_FILL;
                                    end if;

                                when others => null;

                            end case;
                        end if;

                    -- Encolar el dato a escribir en la FIFO del i2c_master
                    when ST_EXEC_I2C_FILL =>
                        if s_cmd = c_CMD_I2C_WRITE then
                            -- dato = {ARG2, ARG3} = {val_hi, val_lo}
                            i2c_wr_data_o <= s_args(15 downto 0);
                            i2c_wr_push_o <= '1';
                        end if;
                        s_exec_state <= ST_EXEC_I2C_START;

                    -- Lanzar la transacción cuando el master esté libre
                    when ST_EXEC_I2C_START =>
                        if i2c_busy_i = '0' then
                            if s_cmd = c_CMD_I2C_WRITE then
                                i2c_rw_o <= '0';
                            else
                                i2c_rw_o <= '1';
                            end if;
                            -- ARG1 = dirección del registro
                            i2c_addr_reg_o <= s_args(23 downto 16);
                            i2c_num_regs_o <= 1;
                            i2c_start_o    <= '1';
                            s_exec_state   <= ST_EXEC_I2C_WAIT;
                        end if;

                    -- Esperar done o error
                    when ST_EXEC_I2C_WAIT =>
                        if i2c_error_i = '1' or i2c_done_i = '1' then
                            if s_cmd = c_CMD_I2C_READ and i2c_done_i = '1' then
                                s_exec_state <= ST_EXEC_I2C_DRAIN;
                            else
                                s_exec_state <= ST_EXEC_IDLE;
                            end if;
                        end if;

                    -- Drenar el resultado de lectura (por ahora lo descartamos;
                    -- en el futuro se enviará de vuelta al PC)
                    when ST_EXEC_I2C_DRAIN =>
                        if i2c_rd_empty_i = '0' then
                            i2c_rd_pop_o <= '1';
                            s_exec_state <= ST_EXEC_IDLE;
                        end if;

                    when others =>
                        s_exec_state <= ST_EXEC_IDLE;

                end case;
            end if;
        end if;
    end process p_exec;

end architecture rtl;
