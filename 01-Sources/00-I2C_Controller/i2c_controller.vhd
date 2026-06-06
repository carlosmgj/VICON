--! \file i2c_controller.vhd
--! \brief Controlador I2C maestro con FIFOs de escritura y lectura.


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--! \brief Entidad del controlador I2C
--! \fsm_show_actions
entity i2c_master is
    generic (
        g_CLK_FREQ_HZ  : integer := 100_000_000;    --! Frecuencia del reloj de sistema (Hz)
        g_I2C_FREQ_HZ  : integer := 400_000;        --! Frecuencia I2C deseada (Hz); típico 100k o 400k
        g_FIFO_DEPTH   : integer := 16              --! Profundidad de las FIFOs de escritura y lectura
    );
    port (
        clk_i   : in std_logic;  --! Reloj de sistema
        reset_i : in std_logic;  --! Reset síncrono activo alto

        ---------------------------------------------------------------------------
        -- Interfaz de control
        ---------------------------------------------------------------------------
        rw_i        : in std_logic;                              --! Dirección de la transacción: '0'=escritura, '1'=lectura
        start_i2c_i : in std_logic;                              --! Pulso de inicio de transacción (activo 1 ciclo)
        num_regs_i  : in integer range 1 to g_FIFO_DEPTH;        --! Número de registros de 16 bits a transferir
        addr_dev_i  : in std_logic_vector(6 downto 0);           --! Dirección I2C de 7 bits del esclavo
        addr_reg_i  : in std_logic_vector(7 downto 0);           --! Dirección del registro inicial a acceder

        ---------------------------------------------------------------------------
        -- WR FIFO — el usuario escribe aquí antes de lanzar una transacción Write
        ---------------------------------------------------------------------------
        wr_fifo_push_i  : in  std_logic;                          --! Pulso para encolar dato en WR FIFO (activo 1 ciclo)
        wr_fifo_data_i  : in  std_logic_vector(15 downto 0);      --! Dato de 16 bits a escribir en el registro del esclavo
        wr_fifo_full_o  : out std_logic;                          --! WR FIFO llena; no encolar más datos
        wr_fifo_empty_o : out std_logic;                          --! WR FIFO vacía; todos los datos han sido consumidos

        ---------------------------------------------------------------------------
        -- RD FIFO — el usuario lee aquí tras una transacción Read
        ---------------------------------------------------------------------------
        rd_fifo_pop_i   : in  std_logic;                          --! Pulso para extraer dato de RD FIFO (activo 1 ciclo)
        rd_fifo_data_o  : out std_logic_vector(15 downto 0);      --! Dato de 16 bits leído del registro del esclavo
        rd_fifo_full_o  : out std_logic;                          --! RD FIFO llena; drenar antes de lanzar nueva lectura
        rd_fifo_empty_o : out std_logic;                          --! RD FIFO vacía; no hay datos disponibles

        ---------------------------------------------------------------------------
        -- Estado de la transacción
        ---------------------------------------------------------------------------
        busy_o  : out std_logic;  --! '1' durante la transacción I2C
        done_o  : out std_logic;  --! Pulso de 1 ciclo al completar correctamente
        error_o : out std_logic;  --! '1' si hubo NACK u otro error

        ---------------------------------------------------------------------------
        -- Bus I2C — señales separadas; el tristate/open-drain va en TOP
        ---------------------------------------------------------------------------
        scl_o    : out std_logic;  --! Valor a poner en SCL: '0'=pull-down, '1'=soltar (Z en TOP)
        sda_o    : out std_logic;  --! Valor a poner en SDA cuando sda_oe_o='1'
        sda_oe_o : out std_logic;  --! '1'=conducir SDA con sda_o,  '0'=tristate
        sda_i    : in  std_logic   --! Valor leído del bus SDA
    );
end entity i2c_master;

architecture rtl of i2c_master is

    ---------------------------------------------------------------------------
    -- Constante de timing
    -- c_CLKS_PER_PHASE: ciclos de reloj por cada cuarto de periodo I2C
    ---------------------------------------------------------------------------
    constant c_CLKS_PER_PHASE : integer := g_CLK_FREQ_HZ / (g_I2C_FREQ_HZ * 4);

    ---------------------------------------------------------------------------
    -- Tipos
    ---------------------------------------------------------------------------
    type t_fifo_mem is array (0 to g_FIFO_DEPTH-1) of std_logic_vector(15 downto 0);

    ---------------------------------------------------------------------------
    -- WR FIFO — FIFO de escritura (usuario → bus I2C)
    ---------------------------------------------------------------------------
    signal s_wr_mem     : t_fifo_mem := (others => (others => '0'));  --! Memoria de la WR FIFO
    signal s_wr_wr_ptr  : integer range 0 to g_FIFO_DEPTH-1 := 0;     --! Puntero de escritura
    signal s_wr_rd_ptr  : integer range 0 to g_FIFO_DEPTH-1 := 0;     --! Puntero de lectura
    signal s_wr_count   : integer range 0 to g_FIFO_DEPTH   := 0;     --! Entradas ocupadas
    signal s_wr_full    : std_logic;                                  --! FIFO llena (combinacional)
    signal s_wr_empty   : std_logic;                                  --! FIFO vacía (combinacional)
    signal s_wr_pop     : std_logic := '0';                           --! Pop interno generado por la FSM (1 ciclo)
    signal s_wr_dout    : std_logic_vector(15 downto 0);              --! Cabeza de la FIFO (lectura asíncrona)

    ---------------------------------------------------------------------------
    -- RD FIFO — FIFO de lectura (bus I2C → usuario)
    ---------------------------------------------------------------------------
    signal s_rd_mem     : t_fifo_mem := (others => (others => '0'));         --! Memoria de la RD FIFO
    signal s_rd_wr_ptr  : integer range 0 to g_FIFO_DEPTH-1 := 0;            --! Puntero de escritura
    signal s_rd_rd_ptr  : integer range 0 to g_FIFO_DEPTH-1 := 0;            --! Puntero de lectura
    signal s_rd_count   : integer range 0 to g_FIFO_DEPTH   := 0;            --! Entradas ocupadas
    signal s_rd_full    : std_logic;                                         --! FIFO llena (combinacional)
    signal s_rd_empty   : std_logic;                                         --! FIFO vacía (combinacional)
    signal s_rd_push    : std_logic := '0';                                  --! Push interno generado por la FSM (1 ciclo)
    signal s_rd_din     : std_logic_vector(15 downto 0) := (others => '0');  --! Dato a escribir en la RD FIFO

    ---------------------------------------------------------------------------
    -- FSM principal
    ---------------------------------------------------------------------------
    type t_state is (
        ST_IDLE,
        -- START / Repeated START
        ST_START_0, ST_START_1, ST_START_2, ST_START_3,
        -- TX byte + ACK del esclavo (RACK)
        ST_TX_0, ST_TX_1, ST_TX_2, ST_TX_3,
        ST_RACK_0, ST_RACK_1, ST_RACK_2, ST_RACK_3,
        -- RX byte + ACK del master (MACK)
        ST_RX_0, ST_RX_1, ST_RX_2, ST_RX_3,
        ST_MACK_0, ST_MACK_1, ST_MACK_2, ST_MACK_3,
        -- Puntos de decisión — secuencia WRITE
        ST_DECIDE_AFTER_ADDR_WR,
        ST_DECIDE_AFTER_REG_ADDR,
        ST_LOAD_DATA_H,           --! Espera 1 ciclo para que s_wr_word se estabilice
        ST_DECIDE_AFTER_DATA_H,
        ST_DECIDE_AFTER_DATA_L,
        ST_LOAD_NEXT_DATA_H,      --! Igual que ST_LOAD_DATA_H para registros siguientes
        -- Puntos de decisión — secuencia READ
        ST_DECIDE_AFTER_ADDR_RD,
        ST_DECIDE_AFTER_RX_H,
        ST_DECIDE_AFTER_RX_L,
        -- STOP
        ST_STOP_0, ST_STOP_1, ST_STOP_2, ST_STOP_3,
        -- Fin / Error
        ST_DONE,
        ST_ERROR_STOP,
        ST_ERROR
    );

    signal s_state    : t_state := ST_IDLE;                --! Estado actual de la FSM
    signal s_seq_next : t_state := ST_IDLE;                --! Estado de retorno tras TX+RACK o RX+MACK

    ---------------------------------------------------------------------------
    -- Registros de la transacción — capturados al inicio para estabilidad
    ---------------------------------------------------------------------------
    signal rw_r            : std_logic                        := '0';              --! Dirección capturada al inicio de la transacción
    signal addr_dev_r      : std_logic_vector(6 downto 0)     := (others => '0');  --! Dirección del esclavo capturada
    signal addr_reg_r      : std_logic_vector(7 downto 0)     := (others => '0');  --! Dirección del registro capturada
    signal num_regs_r      : integer range 1 to g_FIFO_DEPTH  := 1;                --! Número de registros capturado
    signal s_reg_cnt       : integer range 0 to g_FIFO_DEPTH  := 0;                --! Registros procesados hasta el momento
    signal s_start_rd_mode : std_logic                        := '0';              --! '1' → el próximo START será en modo lectura (Repeated START)

    ---------------------------------------------------------------------------
    -- TX / RX
    ---------------------------------------------------------------------------
    signal s_tx_byte   : std_logic_vector(7 downto 0) := (others => '0');  --! Byte actual a transmitir por el bus
    signal s_rx_byte   : std_logic_vector(7 downto 0) := (others => '0');  --! Byte actual recibido del bus
    signal s_rx_high   : std_logic_vector(7 downto 0) := (others => '0');  --! Byte alto recibido, pendiente de combinarse con el bajo
    signal s_bit_cnt   : integer range 0 to 7         := 7;                --! Índice del bit en curso (MSB=7)
    signal s_wr_word   : std_logic_vector(15 downto 0) := (others => '0'); --! Dato de 16 bits capturado de la WR FIFO
    signal s_send_nack : std_logic                    := '0';              --! '1' → MACK enviará NACK (último byte de lectura)

    ---------------------------------------------------------------------------
    -- Generador de fase
    ---------------------------------------------------------------------------
    signal s_phase_cnt  : integer range 0 to c_CLKS_PER_PHASE-1 := 0;   --! Contador de ciclos dentro de la fase actual
    signal s_phase_tick : std_logic                             := '0'; --! Pulso activo cada cuarto de periodo I2C

    ---------------------------------------------------------------------------
    -- Señales internas del bus I2C
    ---------------------------------------------------------------------------
    signal scl_r     : std_logic := '1';  --! Registro del valor de SCL
    signal sda_out_r : std_logic := '1';  --! Registro del valor a conducir en SDA
    signal s_sda_oe  : std_logic := '1';  --! '1'=conducir SDA,  '0'=tristate

    ---------------------------------------------------------------------------
    -- Salidas de estado — registros internos que alimentan las salidas
    ---------------------------------------------------------------------------
    signal s_busy  : std_logic := '0';  --! Registro interno de busy_o
    signal s_done  : std_logic := '0';  --! Registro interno de done_o
    signal s_error : std_logic := '0';  --! Registro interno de error_o


    attribute fsm_encoding : string;
    attribute fsm_encoding of s_state : signal is "auto";


    -- signal debug_state_slv : std_logic_vector(4 downto 0);  --! ILA: estado FSM codificado

begin

    -- with s_state select debug_state_slv <=
    -- "00000" when ST_IDLE,
    -- "00001" when ST_START_0,
    -- "00010" when ST_START_1,
    -- "00011" when ST_START_2,
    -- "00100" when ST_START_3,
    -- "00101" when ST_TX_0,
    -- "00110" when ST_TX_1,
    -- "00111" when ST_TX_2,
    -- "01000" when ST_TX_3,
    -- "01001" when ST_RACK_0,
    -- "01010" when ST_RACK_1,
    -- "01011" when ST_RACK_2,
    -- "01100" when ST_RACK_3,
    -- "01101" when ST_RX_0,
    -- "01110" when ST_RX_1,
    -- "01111" when ST_RX_2,
    -- "10000" when ST_RX_3,
    -- "10001" when ST_MACK_0,
    -- "10010" when ST_MACK_1,
    -- "10011" when ST_MACK_2,
    -- "10100" when ST_MACK_3,
    -- "10101" when ST_DECIDE_AFTER_ADDR_WR,
    -- "10110" when ST_DECIDE_AFTER_REG_ADDR,
    -- "10111" when ST_LOAD_DATA_H,
    -- "11000" when ST_DECIDE_AFTER_DATA_H,
    -- "11001" when ST_DECIDE_AFTER_DATA_L,
    -- "11010" when ST_LOAD_NEXT_DATA_H,
    -- "11011" when ST_DECIDE_AFTER_ADDR_RD,
    -- "11100" when ST_DECIDE_AFTER_RX_H,
    -- "11101" when ST_DECIDE_AFTER_RX_L,
    -- "11110" when ST_STOP_0,
    -- "11111" when ST_STOP_1,
    -- "11111" when ST_STOP_2,  -- se solapan pero son poco críticos
    -- "11111" when ST_DONE,
    -- "11111" when ST_ERROR_STOP,
    -- "11111" when ST_ERROR,
    -- "11111" when others;

    -- u_ila_i2c : entity work.ila_1
    -- port map (
    --     clk       => clk_i,
    --     probe0(0) => scl_r,
    --     probe1(0) => sda_out_r,
    --     probe2(0) => sda_i,
    --     probe3    => addr_reg_r,
    --     probe4(0) => rw_r,
    --     probe5(0) => s_busy,
    --     probe6(0) => s_sda_oe,
    --     probe7(0) => s_error,
    --     probe8(0) => s_start_rd_mode,
    --     probe9 => debug_state_slv
    -- );

    ---------------------------------------------------------------------------
    -- WR FIFO
    -- s_wr_dout es combinacional sobre s_wr_rd_ptr (lectura asíncrona).
    -- El pop avanza s_wr_rd_ptr en el flanco siguiente, por eso se necesita
    -- ST_LOAD_DATA_H para capturar s_wr_word un ciclo antes de usarlo en TX.
    ---------------------------------------------------------------------------
    s_wr_full       <= '1' when s_wr_count = g_FIFO_DEPTH else '0';
    s_wr_empty      <= '1' when s_wr_count = 0            else '0';
    wr_fifo_full_o  <= s_wr_full;
    wr_fifo_empty_o <= s_wr_empty;
    s_wr_dout       <= s_wr_mem(s_wr_rd_ptr);

    p_wr_fifo : process(clk_i)
        variable v_do_push : boolean;
        variable v_do_pop  : boolean;
    begin
        if rising_edge(clk_i) then
            if reset_i = '1' then
                s_wr_wr_ptr <= 0;
                s_wr_rd_ptr <= 0;
                s_wr_count  <= 0;
            else
                v_do_push := (wr_fifo_push_i = '1') and (s_wr_full  = '0');
                v_do_pop  := (s_wr_pop       = '1') and (s_wr_empty = '0');
                if v_do_push then
                    s_wr_mem(s_wr_wr_ptr) <= wr_fifo_data_i;
                    s_wr_wr_ptr <= (s_wr_wr_ptr + 1) mod g_FIFO_DEPTH;
                end if;
                if v_do_pop then
                    s_wr_rd_ptr <= (s_wr_rd_ptr + 1) mod g_FIFO_DEPTH;
                end if;
                if    v_do_push and not v_do_pop then s_wr_count <= s_wr_count + 1;
                elsif v_do_pop  and not v_do_push then s_wr_count <= s_wr_count - 1;
                end if;
            end if;
        end if;
    end process p_wr_fifo;

    ---------------------------------------------------------------------------
    -- RD FIFO
    ---------------------------------------------------------------------------
    s_rd_full       <= '1' when s_rd_count = g_FIFO_DEPTH else '0';
    s_rd_empty      <= '1' when s_rd_count = 0            else '0';
    rd_fifo_full_o  <= s_rd_full;
    rd_fifo_empty_o <= s_rd_empty;
    rd_fifo_data_o  <= s_rd_mem(s_rd_rd_ptr);

    p_rd_fifo : process(clk_i)
        variable v_do_push : boolean;
        variable v_do_pop  : boolean;
    begin
        if rising_edge(clk_i) then
            if reset_i = '1' then
                s_rd_wr_ptr <= 0;
                s_rd_rd_ptr <= 0;
                s_rd_count  <= 0;
            else
                v_do_push := (s_rd_push     = '1') and (s_rd_full  = '0');
                v_do_pop  := (rd_fifo_pop_i = '1') and (s_rd_empty = '0');
                if v_do_push then
                    s_rd_mem(s_rd_wr_ptr) <= s_rd_din;
                    s_rd_wr_ptr <= (s_rd_wr_ptr + 1) mod g_FIFO_DEPTH;
                end if;
                if v_do_pop then
                    s_rd_rd_ptr <= (s_rd_rd_ptr + 1) mod g_FIFO_DEPTH;
                end if;
                if    v_do_push and not v_do_pop then s_rd_count <= s_rd_count + 1;
                elsif v_do_pop  and not v_do_push then s_rd_count <= s_rd_count - 1;
                end if;
            end if;
        end if;
    end process p_rd_fifo;

    ---------------------------------------------------------------------------
    -- Generador de fase
    -- Genera un pulso (s_phase_tick) cada c_CLKS_PER_PHASE ciclos.
    -- Cada fase corresponde a un cuarto de periodo I2C.
    ---------------------------------------------------------------------------
    p_phase : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if reset_i = '1' then
                s_phase_cnt  <= 0;
                s_phase_tick <= '0';
            elsif s_phase_cnt = c_CLKS_PER_PHASE - 1 then
                s_phase_cnt  <= 0;
                s_phase_tick <= '1';
            else
                s_phase_cnt  <= s_phase_cnt + 1;
                s_phase_tick <= '0';
            end if;
        end if;
    end process p_phase;

    ---------------------------------------------------------------------------
    -- FSM principal
    --
    -- Cada estado de bus (ST_TX_x, ST_RX_x, etc.) espera un s_phase_tick
    -- para avanzar, garantizando el timing I2C correcto.
    -- Los estados de decisión (ST_DECIDE_*) no esperan s_phase_tick.
    ---------------------------------------------------------------------------
    p_fsm : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if reset_i = '1' then
                s_state         <= ST_IDLE;
                s_seq_next      <= ST_IDLE;
                s_busy          <= '0';
                s_done          <= '0';
                s_error         <= '0';
                scl_r           <= '1';
                sda_out_r       <= '1';
                s_sda_oe        <= '1';
                s_wr_pop        <= '0';
                s_rd_push       <= '0';
                s_rd_din        <= (others => '0');
                s_tx_byte       <= (others => '0');
                s_rx_byte       <= (others => '0');
                s_rx_high       <= (others => '0');
                s_wr_word       <= (others => '0');
                s_bit_cnt       <= 7;
                s_reg_cnt       <= 0;
                s_send_nack     <= '0';
                s_start_rd_mode <= '0';
                rw_r            <= '0';
                addr_dev_r      <= (others => '0');
                addr_reg_r      <= (others => '0');
                num_regs_r      <= 1;
            else
                -- Pulsos de un ciclo por defecto
                s_wr_pop  <= '0';
                s_rd_push <= '0';
                s_done    <= '0';

                case s_state is

                    -----------------------------------------------------------
                    when ST_IDLE =>
                        scl_r       <= '1';
                        sda_out_r   <= '1';
                        s_sda_oe    <= '1';
                        s_busy      <= '0';
                        s_error     <= '0';
                        if start_i2c_i = '1' then
                            if s_rd_empty = '0' then
                                null;   -- RD FIFO no vaciada: bloquear
                            else
                                rw_r            <= rw_i;
                                addr_dev_r      <= addr_dev_i;
                                addr_reg_r      <= addr_reg_i;
                                num_regs_r      <= num_regs_i;
                                s_reg_cnt       <= 0;
                                s_start_rd_mode <= '0';
                                s_busy          <= '1';
                                s_state         <= ST_START_0;
                            end if;
                        end if;

                    -----------------------------------------------------------
                    -- START / Repeated START
                    -- Secuencia: SCL alto → SDA baja → SCL baja
                    -----------------------------------------------------------
                    when ST_START_0 =>
                        if s_phase_tick = '1' then
                            scl_r <= '0'; sda_out_r <= '1'; s_sda_oe <= '1';
                            s_state <= ST_START_1;
                        end if;

                    when ST_START_1 =>
                        if s_phase_tick = '1' then
                            scl_r <= '1'; s_state <= ST_START_2;
                        end if;

                    when ST_START_2 =>
                        if s_phase_tick = '1' then
                            sda_out_r <= '0';   -- SDA baja con SCL alto → condición START
                            s_state     <= ST_START_3;
                        end if;

                    when ST_START_3 =>
                        if s_phase_tick = '1' then
                            scl_r   <= '0';
                            s_bit_cnt <= 7;
                            if s_start_rd_mode = '0' then
                                s_tx_byte  <= addr_dev_r & '0';   -- ADDR + Write
                                s_seq_next <= ST_DECIDE_AFTER_ADDR_WR;
                            else
                                s_tx_byte  <= addr_dev_r & '1';   -- ADDR + Read
                                s_seq_next <= ST_DECIDE_AFTER_ADDR_RD;
                            end if;
                            s_state <= ST_TX_0;
                        end if;

                    -----------------------------------------------------------
                    -- TX byte reutilizable
                    -- Precargar antes de entrar: s_tx_byte, s_bit_cnt=7, s_seq_next
                    -- Envía bit a bit de MSB a LSB, luego va a ST_RACK_0
                    -----------------------------------------------------------
                    when ST_TX_0 =>
                        if s_phase_tick = '1' then
                            scl_r       <= '0';
                            s_sda_oe    <= '1';
                            sda_out_r   <= s_tx_byte(s_bit_cnt);
                            s_state     <= ST_TX_1;
                        end if;

                    when ST_TX_1 =>
                        if s_phase_tick = '1' then
                            scl_r <= '1'; s_state <= ST_TX_2;
                        end if;

                    when ST_TX_2 =>
                        if s_phase_tick = '1' then
                            s_state <= ST_TX_3;
                        end if;

                    when ST_TX_3 =>
                        if s_phase_tick = '1' then
                            scl_r <= '0';
                            if s_bit_cnt = 0 then
                                s_bit_cnt <= 7;
                                s_state   <= ST_RACK_0;
                            else
                                s_bit_cnt <= s_bit_cnt - 1;
                                s_state   <= ST_TX_0;
                            end if;
                        end if;

                    -----------------------------------------------------------
                    -- RACK: ACK del esclavo
                    -- El master suelta SDA (s_sda_oe='0') y lee el bus.
                    -- SDA='0' → ACK,  SDA='1' → NACK → error
                    -----------------------------------------------------------
                    when ST_RACK_0 =>
                        if s_phase_tick = '1' then
                            scl_r <= '0'; s_sda_oe <= '0'; s_state <= ST_RACK_1;
                        end if;

                    when ST_RACK_1 =>
                        if s_phase_tick = '1' then
                            scl_r <= '1'; s_state <= ST_RACK_2;
                        end if;

                    when ST_RACK_2 =>
                        if s_phase_tick = '1' then
                            if sda_i = '1' then
                                s_state <= ST_ERROR_STOP;   -- NACK recibido
                            else
                                s_state <= ST_RACK_3;       -- ACK recibido
                            end if;
                        end if;

                    when ST_RACK_3 =>
                        if s_phase_tick = '1' then
                            scl_r <= '0'; s_state <= s_seq_next;
                        end if;

                    -----------------------------------------------------------
                    -- Decisión WRITE: tras ACK de ADDR_WR → enviar REG_ADDR
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_ADDR_WR =>
                        s_tx_byte  <= addr_reg_r;
                        s_bit_cnt  <= 7;
                        s_seq_next <= ST_DECIDE_AFTER_REG_ADDR;
                        s_state    <= ST_TX_0;

                    -----------------------------------------------------------
                    -- Decisión: tras ACK de REG_ADDR
                    --   Write → capturar dato de WR FIFO
                    --   Read  → Repeated START en modo lectura
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_REG_ADDR =>
                        if rw_r = '0' then
                            if s_wr_empty = '0' then
                                s_wr_word <= s_wr_dout;  -- capturar (s_wr_dout es combinacional)
                                s_wr_pop  <= '1';        -- avanzar puntero en el flanco siguiente
                                s_state   <= ST_LOAD_DATA_H;
                            end if;
                            -- FIFO vacía: esperar en este estado
                        else
                            s_start_rd_mode <= '1';
                            s_state         <= ST_START_0;
                        end if;

                    -----------------------------------------------------------
                    -- ST_LOAD_DATA_H: s_wr_word estable → cargar byte alto en TX
                    -----------------------------------------------------------
                    when ST_LOAD_DATA_H =>
                        s_tx_byte  <= s_wr_word(15 downto 8);
                        s_bit_cnt  <= 7;
                        s_seq_next <= ST_DECIDE_AFTER_DATA_H;
                        s_state    <= ST_TX_0;

                    -----------------------------------------------------------
                    -- Decisión: tras ACK de DATA_H → enviar byte bajo
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_DATA_H =>
                        s_tx_byte  <= s_wr_word(7 downto 0);
                        s_bit_cnt  <= 7;
                        s_seq_next <= ST_DECIDE_AFTER_DATA_L;
                        s_state    <= ST_TX_0;

                    -----------------------------------------------------------
                    -- Decisión: tras ACK de DATA_L → ¿más registros?
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_DATA_L =>
                        s_reg_cnt <= s_reg_cnt + 1;
                        if s_reg_cnt + 1 = num_regs_r then
                            s_state <= ST_STOP_0;         -- todos escritos
                        else
                            if s_wr_empty = '0' then
                                s_wr_word <= s_wr_dout;
                                s_wr_pop  <= '1';
                                s_state   <= ST_LOAD_NEXT_DATA_H;
                            end if;
                            -- FIFO vacía: esperar aquí
                        end if;

                    -----------------------------------------------------------
                    -- ST_LOAD_NEXT_DATA_H: igual que ST_LOAD_DATA_H
                    -- (estado separado para claridad; mismo comportamiento)
                    -----------------------------------------------------------
                    when ST_LOAD_NEXT_DATA_H =>
                        s_tx_byte  <= s_wr_word(15 downto 8);
                        s_bit_cnt  <= 7;
                        s_seq_next <= ST_DECIDE_AFTER_DATA_H;
                        s_state    <= ST_TX_0;

                    -----------------------------------------------------------
                    -- Decisión READ: tras ACK de ADDR_RD → recibir DATA_H
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_ADDR_RD =>
                        s_send_nack <= '0';
                        s_bit_cnt   <= 7;
                        s_seq_next  <= ST_DECIDE_AFTER_RX_H;
                        s_state     <= ST_RX_0;

                    -----------------------------------------------------------
                    -- Decisión: tras MACK de DATA_H → recibir DATA_L
                    -- Activar NACK si este es el último registro
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_RX_H =>
                        s_rx_high <= s_rx_byte;
                        if s_reg_cnt + 1 = num_regs_r then
                            s_send_nack <= '1';   -- último registro → NACK en DATA_L
                        else
                            s_send_nack <= '0';
                        end if;
                        s_bit_cnt  <= 7;
                        s_seq_next <= ST_DECIDE_AFTER_RX_L;
                        s_state    <= ST_RX_0;

                    -----------------------------------------------------------
                    -- Decisión: tras MACK de DATA_L → push RD FIFO, ¿más?
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_RX_L =>
                        if s_rd_full = '0' then
                            s_rd_din  <= s_rx_high & s_rx_byte;
                            s_rd_push <= '1';
                            s_reg_cnt <= s_reg_cnt + 1;
                            if s_reg_cnt + 1 = num_regs_r then
                                s_state <= ST_STOP_0;     -- todos leídos
                            else
                                s_send_nack <= '0';
                                s_bit_cnt   <= 7;
                                s_seq_next  <= ST_DECIDE_AFTER_RX_H;
                                s_state     <= ST_RX_0;
                            end if;
                        else
                            s_state <= ST_ERROR_STOP;     -- RD FIFO llena
                        end if;

                    -----------------------------------------------------------
                    -- RX byte reutilizable
                    -- Precargar antes de entrar: s_send_nack, s_bit_cnt=7, s_seq_next
                    -- Captura bit a bit de MSB a LSB, luego va a ST_MACK_0
                    -----------------------------------------------------------
                    when ST_RX_0 =>
                        if s_phase_tick = '1' then
                            scl_r <= '0'; s_sda_oe <= '0'; s_state <= ST_RX_1;
                        end if;

                    when ST_RX_1 =>
                        if s_phase_tick = '1' then
                            scl_r <= '1'; s_state <= ST_RX_2;
                        end if;

                    when ST_RX_2 =>
                        if s_phase_tick = '1' then
                            s_rx_byte(s_bit_cnt) <= sda_i; s_state <= ST_RX_3;
                        end if;

                    when ST_RX_3 =>
                        if s_phase_tick = '1' then
                            scl_r <= '0';
                            if s_bit_cnt = 0 then
                                s_bit_cnt <= 7;
                                s_state   <= ST_MACK_0;
                            else
                                s_bit_cnt <= s_bit_cnt - 1;
                                s_state   <= ST_RX_0;
                            end if;
                        end if;

                    -----------------------------------------------------------
                    -- MACK: master envía ACK ('0') o NACK ('1') según s_send_nack
                    -----------------------------------------------------------
                    when ST_MACK_0 =>
                        if s_phase_tick = '1' then
                            scl_r       <= '0';
                            s_sda_oe    <= '1';
                            sda_out_r   <= s_send_nack;
                            s_state     <= ST_MACK_1;
                        end if;

                    when ST_MACK_1 =>
                        if s_phase_tick = '1' then
                            scl_r <= '1'; s_state <= ST_MACK_2;
                        end if;

                    when ST_MACK_2 =>
                        if s_phase_tick = '1' then
                            s_state <= ST_MACK_3;
                        end if;

                    when ST_MACK_3 =>
                        if s_phase_tick = '1' then
                            scl_r <= '0'; s_state <= s_seq_next;
                        end if;

                    -----------------------------------------------------------
                    -- STOP: SDA sube mientras SCL está alto
                    -----------------------------------------------------------
                    when ST_STOP_0 =>
                        if s_phase_tick = '1' then
                            scl_r <= '0'; sda_out_r <= '0'; s_sda_oe <= '1';
                            s_state <= ST_STOP_1;
                        end if;

                    when ST_STOP_1 =>
                        if s_phase_tick = '1' then
                            scl_r <= '1'; s_state <= ST_STOP_2;
                        end if;

                    when ST_STOP_2 =>
                        if s_phase_tick = '1' then
                            sda_out_r   <= '1';   -- SDA sube con SCL alto → condición STOP
                            s_state     <= ST_STOP_3;
                        end if;

                    when ST_STOP_3 =>
                        if s_phase_tick = '1' then
                            s_state <= ST_DONE;
                        end if;

                    -----------------------------------------------------------
                    when ST_DONE =>
                        s_done  <= '1';
                        s_busy  <= '0';
                        s_state <= ST_IDLE;

                    when ST_ERROR_STOP =>
                        s_error <= '1';
                        s_state <= ST_STOP_0;   -- liberar bus antes de volver a IDLE

                    when ST_ERROR =>
                        s_error <= '1';
                        s_busy  <= '0';
                        s_state <= ST_IDLE;

                    when others =>
                        s_state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process p_fsm;

    ---------------------------------------------------------------------------
    -- Asignación de salidas
    ---------------------------------------------------------------------------
    scl_o    <= scl_r;
    sda_o    <= sda_out_r;
    sda_oe_o <= s_sda_oe;

    busy_o  <= s_busy;
    done_o  <= s_done;
    error_o <= s_error;

end architecture rtl;
