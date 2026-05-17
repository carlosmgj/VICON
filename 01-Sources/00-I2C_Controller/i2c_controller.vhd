--! \file i2c_controller.vhd
--! \brief Controlador I2C maestro con FIFOs de escritura y lectura.
--!
--! Protocolo soportado:
--!   WRITE : S + ADDR_W + ACK + REG_ADDR + ACK + [DATA_H + ACK + DATA_L + ACK] x N + P
--!   READ  : S + ADDR_W + ACK + REG_ADDR + ACK + Sr + ADDR_R + ACK + [DATA_H + ACK + DATA_L + ACK/NACK] x N + P
--!
--! Los puertos del bus (scl_out, sda_out, sda_oe_o, sda_in) son señales lógicas
--! separadas. El tristate e open-drain se manejan en el TOP level.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_master is
    generic (
        CLK_FREQ_HZ : integer := 100_000_000;  --! Frecuencia del reloj de sistema (Hz)
        I2C_FREQ_HZ : integer := 400_000;       --! Frecuencia I2C deseada (Hz)
        FIFO_DEPTH  : integer := 16             --! Profundidad de las FIFOs
    );
    port (
        clk           : in  std_logic;
        reset         : in  std_logic;

        ---------------------------------------------------------------------------
        -- Interfaz de control
        ---------------------------------------------------------------------------
        rw            : in  std_logic;                          --! '0'=Write '1'=Read
        start_i2c     : in  std_logic;                          --! Pulso de inicio de transacción
        num_regs      : in  integer range 1 to FIFO_DEPTH;      --! Número de registros a transferir
        addr_dev      : in  std_logic_vector(6 downto 0);       --! Dirección I2C del esclavo
        addr_reg      : in  std_logic_vector(7 downto 0);       --! Dirección del registro inicial

        ---------------------------------------------------------------------------
        -- WR FIFO (el usuario escribe aquí antes de lanzar una transacción Write)
        ---------------------------------------------------------------------------
        wr_fifo_push  : in  std_logic;
        wr_fifo_data  : in  std_logic_vector(15 downto 0);
        wr_fifo_full  : out std_logic;
        wr_fifo_empty : out std_logic;

        ---------------------------------------------------------------------------
        -- RD FIFO (el usuario lee aquí tras una transacción Read)
        ---------------------------------------------------------------------------
        rd_fifo_pop   : in  std_logic;
        rd_fifo_data  : out std_logic_vector(15 downto 0);
        rd_fifo_full  : out std_logic;
        rd_fifo_empty : out std_logic;

        ---------------------------------------------------------------------------
        -- Estado
        ---------------------------------------------------------------------------
        busy          : out std_logic;   --! '1' durante la transacción
        done          : out std_logic;   --! Pulso de 1 ciclo al completar
        error         : out std_logic;   --! '1' si hubo NACK u otro error

        ---------------------------------------------------------------------------
        -- Bus I2C (señales separadas; el tristate/open-drain va en TOP)
        ---------------------------------------------------------------------------
        scl_out       : out std_logic;   --! Valor a poner en SCL ('0' o '1')
        sda_out       : out std_logic;   --! Valor a poner en SDA cuando sda_oe_o='1'
        sda_oe_o      : out std_logic;   --! '1'=conducir SDA  '0'=tristate
        sda_in        : in  std_logic    --! Valor leído del bus SDA
    );
end entity i2c_master;

architecture rtl of i2c_master is

    ---------------------------------------------------------------------------
    -- Constante de timing
    -- CLKS_PER_PHASE: ciclos de reloj por cada cuarto de periodo I2C
    ---------------------------------------------------------------------------
    constant CLKS_PER_PHASE : integer := CLK_FREQ_HZ / (I2C_FREQ_HZ * 4);

    ---------------------------------------------------------------------------
    -- Tipos de FIFO
    ---------------------------------------------------------------------------
    type fifo_mem_t is array (0 to FIFO_DEPTH-1) of std_logic_vector(15 downto 0);

    ---------------------------------------------------------------------------
    -- WR FIFO
    ---------------------------------------------------------------------------
    signal wr_mem     : fifo_mem_t := (others => (others => '0'));
    signal wr_wr_ptr  : integer range 0 to FIFO_DEPTH-1 := 0;  --! Puntero de escritura
    signal wr_rd_ptr  : integer range 0 to FIFO_DEPTH-1 := 0;  --! Puntero de lectura
    signal wr_count   : integer range 0 to FIFO_DEPTH   := 0;  --! Entradas ocupadas
    signal wr_full_i  : std_logic;                              --! FIFO llena (combinacional)
    signal wr_empty_i : std_logic;                              --! FIFO vacía (combinacional)
    signal wr_pop     : std_logic := '0';                       --! Pop interno (generado por FSM)
    signal wr_dout    : std_logic_vector(15 downto 0);          --! Cabeza de FIFO (combinacional)

    ---------------------------------------------------------------------------
    -- RD FIFO
    ---------------------------------------------------------------------------
    signal rd_mem     : fifo_mem_t := (others => (others => '0'));
    signal rd_wr_ptr  : integer range 0 to FIFO_DEPTH-1 := 0;
    signal rd_rd_ptr  : integer range 0 to FIFO_DEPTH-1 := 0;
    signal rd_count   : integer range 0 to FIFO_DEPTH   := 0;
    signal rd_full_i  : std_logic;
    signal rd_empty_i : std_logic;
    signal rd_push    : std_logic := '0';                       --! Push interno (generado por FSM)
    signal rd_din     : std_logic_vector(15 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- FSM
    ---------------------------------------------------------------------------
    type state_t is (
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
        ST_LOAD_DATA_H,          --! Espera 1 ciclo para que wr_word se estabilice
        ST_DECIDE_AFTER_DATA_H,
        ST_DECIDE_AFTER_DATA_L,
        ST_LOAD_NEXT_DATA_H,     --! Igual que ST_LOAD_DATA_H para registros siguientes
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

    signal state    : state_t := ST_IDLE;
    signal seq_next : state_t := ST_IDLE;  --! Estado de retorno tras TX+RACK o RX+MACK

    ---------------------------------------------------------------------------
    -- Registros de la transacción (capturados al inicio para estabilidad)
    ---------------------------------------------------------------------------
    signal r_rw           : std_logic := '0';
    signal r_addr_dev     : std_logic_vector(6 downto 0)  := (others => '0');
    signal r_addr_reg     : std_logic_vector(7 downto 0)  := (others => '0');
    signal r_num_regs     : integer range 1 to FIFO_DEPTH := 1;
    signal reg_cnt        : integer range 0 to FIFO_DEPTH := 0;  --! Registros procesados
    signal start_rd_mode  : std_logic := '0';  --! '1' → próximo START será en modo lectura

    ---------------------------------------------------------------------------
    -- TX / RX
    ---------------------------------------------------------------------------
    signal tx_byte   : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_byte   : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_high   : std_logic_vector(7 downto 0) := (others => '0');  --! Byte alto recibido
    signal bit_cnt   : integer range 0 to 7 := 7;
    signal wr_word   : std_logic_vector(15 downto 0) := (others => '0');  --! Dato capturado de WR FIFO
    signal send_nack : std_logic := '0';  --! '1' → MACK enviará NACK

    ---------------------------------------------------------------------------
    -- Timing
    ---------------------------------------------------------------------------
    signal phase_cnt  : integer range 0 to CLKS_PER_PHASE-1 := 0;
    signal phase_tick : std_logic := '0';  --! Pulso cada cuarto de periodo I2C

    ---------------------------------------------------------------------------
    -- Señales internas del bus
    ---------------------------------------------------------------------------
    signal scl_r     : std_logic := '1';  --! Registro del valor de SCL
    signal sda_out_r : std_logic := '1';  --! Registro del valor a poner en SDA
    signal sda_oe    : std_logic := '1';  --! '1'=conducir  '0'=tristate

    ---------------------------------------------------------------------------
    -- Salidas de estado internas
    ---------------------------------------------------------------------------
    signal busy_i  : std_logic := '0';
    signal done_i  : std_logic := '0';
    signal error_i : std_logic := '0';

    ---------------------------------------------------------------------------
    -- ILA / Debug
    ---------------------------------------------------------------------------
    attribute mark_debug : string;
    attribute mark_debug of state     : signal is "true";
    attribute mark_debug of seq_next  : signal is "true";
    attribute mark_debug of phase_cnt : signal is "true";
    attribute mark_debug of phase_tick: signal is "true";
    attribute mark_debug of scl_r     : signal is "true";
    attribute mark_debug of sda_out_r : signal is "true";
    attribute mark_debug of sda_oe    : signal is "true";

    attribute fsm_encoding : string;
    attribute fsm_encoding of state : signal is "auto";

begin

    ---------------------------------------------------------------------------
    -- WR FIFO
    -- wr_dout es combinacional sobre wr_rd_ptr (lectura asíncrona).
    -- El pop avanza wr_rd_ptr en el flanco siguiente, por eso se necesita
    -- ST_LOAD_DATA_H para capturar wr_word un ciclo antes de usarlo en TX.
    ---------------------------------------------------------------------------
    wr_full_i     <= '1' when wr_count = FIFO_DEPTH else '0';
    wr_empty_i    <= '1' when wr_count = 0          else '0';
    wr_fifo_full  <= wr_full_i;
    wr_fifo_empty <= wr_empty_i;
    wr_dout       <= wr_mem(wr_rd_ptr);

    p_wr_fifo : process(clk)
        variable do_push : boolean;
        variable do_pop  : boolean;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                wr_wr_ptr <= 0; wr_rd_ptr <= 0; wr_count <= 0;
            else
                do_push := (wr_fifo_push = '1') and (wr_full_i  = '0');
                do_pop  := (wr_pop       = '1') and (wr_empty_i = '0');
                if do_push then
                    wr_mem(wr_wr_ptr) <= wr_fifo_data;
                    wr_wr_ptr <= (wr_wr_ptr + 1) mod FIFO_DEPTH;
                end if;
                if do_pop then
                    wr_rd_ptr <= (wr_rd_ptr + 1) mod FIFO_DEPTH;
                end if;
                if    do_push and not do_pop then wr_count <= wr_count + 1;
                elsif do_pop  and not do_push then wr_count <= wr_count - 1;
                end if;
            end if;
        end if;
    end process p_wr_fifo;

    ---------------------------------------------------------------------------
    -- RD FIFO
    ---------------------------------------------------------------------------
    rd_full_i     <= '1' when rd_count = FIFO_DEPTH else '0';
    rd_empty_i    <= '1' when rd_count = 0          else '0';
    rd_fifo_full  <= rd_full_i;
    rd_fifo_empty <= rd_empty_i;
    rd_fifo_data  <= rd_mem(rd_rd_ptr);

    p_rd_fifo : process(clk)
        variable do_push : boolean;
        variable do_pop  : boolean;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                rd_wr_ptr <= 0; rd_rd_ptr <= 0; rd_count <= 0;
            else
                do_push := (rd_push     = '1') and (rd_full_i  = '0');
                do_pop  := (rd_fifo_pop = '1') and (rd_empty_i = '0');
                if do_push then
                    rd_mem(rd_wr_ptr) <= rd_din;
                    rd_wr_ptr <= (rd_wr_ptr + 1) mod FIFO_DEPTH;
                end if;
                if do_pop then
                    rd_rd_ptr <= (rd_rd_ptr + 1) mod FIFO_DEPTH;
                end if;
                if    do_push and not do_pop then rd_count <= rd_count + 1;
                elsif do_pop  and not do_push then rd_count <= rd_count - 1;
                end if;
            end if;
        end if;
    end process p_rd_fifo;

    ---------------------------------------------------------------------------
    -- Generador de fase
    -- Genera un pulso (phase_tick) cada CLKS_PER_PHASE ciclos.
    -- Cada fase corresponde a un cuarto de periodo I2C.
    ---------------------------------------------------------------------------
    p_phase : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                phase_cnt  <= 0;
                phase_tick <= '0';
            elsif phase_cnt = CLKS_PER_PHASE - 1 then
                phase_cnt  <= 0;
                phase_tick <= '1';
            else
                phase_cnt  <= phase_cnt + 1;
                phase_tick <= '0';
            end if;
        end if;
    end process p_phase;

    ---------------------------------------------------------------------------
    -- FSM principal
    --
    -- Cada estado de bus (ST_TX_x, ST_RX_x, etc.) espera un phase_tick
    -- para avanzar, garantizando el timing I2C correcto.
    -- Los estados de decisión (ST_DECIDE_*) no esperan phase_tick.
    ---------------------------------------------------------------------------
    p_fsm : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state         <= ST_IDLE;
                seq_next      <= ST_IDLE;
                busy_i        <= '0';
                done_i        <= '0';
                error_i       <= '0';
                scl_r         <= '1';
                sda_out_r     <= '1';
                sda_oe        <= '1';
                wr_pop        <= '0';
                rd_push       <= '0';
                rd_din        <= (others => '0');
                tx_byte       <= (others => '0');
                rx_byte       <= (others => '0');
                rx_high       <= (others => '0');
                wr_word       <= (others => '0');
                bit_cnt       <= 7;
                reg_cnt       <= 0;
                send_nack     <= '0';
                start_rd_mode <= '0';
                r_rw          <= '0';
                r_addr_dev    <= (others => '0');
                r_addr_reg    <= (others => '0');
                r_num_regs    <= 1;
            else
                -- Pulsos de un ciclo por defecto
                wr_pop  <= '0';
                rd_push <= '0';
                done_i  <= '0';

                case state is

                    -----------------------------------------------------------
                    when ST_IDLE =>
                        scl_r     <= '1';
                        sda_out_r <= '1';
                        sda_oe    <= '1';
                        busy_i    <= '0';
                        error_i   <= '0';
                        if start_i2c = '1' then
                            if rd_empty_i = '0' then
                                null;   -- RD FIFO no vaciada: bloquear
                            else
                                r_rw          <= rw;
                                r_addr_dev    <= addr_dev;
                                r_addr_reg    <= addr_reg;
                                r_num_regs    <= num_regs;
                                reg_cnt       <= 0;
                                start_rd_mode <= '0';
                                busy_i        <= '1';
                                state         <= ST_START_0;
                            end if;
                        end if;

                    -----------------------------------------------------------
                    -- START / Repeated START
                    -- Secuencia: SCL alto → SDA baja → SCL baja
                    -----------------------------------------------------------
                    when ST_START_0 =>
                        if phase_tick = '1' then
                            scl_r <= '0'; sda_out_r <= '1'; sda_oe <= '1';
                            state <= ST_START_1;
                        end if;

                    when ST_START_1 =>
                        if phase_tick = '1' then
                            scl_r <= '1'; state <= ST_START_2;
                        end if;

                    when ST_START_2 =>
                        if phase_tick = '1' then
                            sda_out_r <= '0';   -- SDA baja con SCL alto → condición START
                            state     <= ST_START_3;
                        end if;

                    when ST_START_3 =>
                        if phase_tick = '1' then
                            scl_r   <= '0';
                            bit_cnt <= 7;
                            if start_rd_mode = '0' then
                                tx_byte  <= r_addr_dev & '0';   -- ADDR + Write
                                seq_next <= ST_DECIDE_AFTER_ADDR_WR;
                            else
                                tx_byte  <= r_addr_dev & '1';   -- ADDR + Read
                                seq_next <= ST_DECIDE_AFTER_ADDR_RD;
                            end if;
                            state <= ST_TX_0;
                        end if;

                    -----------------------------------------------------------
                    -- TX byte reutilizable
                    -- Precargar antes de entrar: tx_byte, bit_cnt=7, seq_next
                    -- Envía bit a bit de MSB a LSB, luego va a ST_RACK_0
                    -----------------------------------------------------------
                    when ST_TX_0 =>
                        if phase_tick = '1' then
                            scl_r     <= '0';
                            sda_oe    <= '1';
                            sda_out_r <= tx_byte(bit_cnt);
                            state     <= ST_TX_1;
                        end if;

                    when ST_TX_1 =>
                        if phase_tick = '1' then
                            scl_r <= '1'; state <= ST_TX_2;
                        end if;

                    when ST_TX_2 =>
                        if phase_tick = '1' then
                            state <= ST_TX_3;
                        end if;

                    when ST_TX_3 =>
                        if phase_tick = '1' then
                            scl_r <= '0';
                            if bit_cnt = 0 then
                                bit_cnt <= 7;
                                state   <= ST_RACK_0;
                            else
                                bit_cnt <= bit_cnt - 1;
                                state   <= ST_TX_0;
                            end if;
                        end if;

                    -----------------------------------------------------------
                    -- RACK: ACK del esclavo
                    -- El master suelta SDA (sda_oe='0') y lee el bus.
                    -- SDA='0' → ACK,  SDA='1' → NACK → error
                    -----------------------------------------------------------
                    when ST_RACK_0 =>
                        if phase_tick = '1' then
                            scl_r <= '0'; sda_oe <= '0'; state <= ST_RACK_1;
                        end if;

                    when ST_RACK_1 =>
                        if phase_tick = '1' then
                            scl_r <= '1'; state <= ST_RACK_2;
                        end if;

                    when ST_RACK_2 =>
                        if phase_tick = '1' then
                            if sda_in = '1' then
                                state <= ST_ERROR_STOP;   -- NACK recibido
                            else
                                state <= ST_RACK_3;       -- ACK recibido
                            end if;
                        end if;

                    when ST_RACK_3 =>
                        if phase_tick = '1' then
                            scl_r <= '0'; state <= seq_next;
                        end if;

                    -----------------------------------------------------------
                    -- Decisión WRITE: tras ACK de ADDR_WR → enviar REG_ADDR
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_ADDR_WR =>
                        tx_byte  <= r_addr_reg;
                        bit_cnt  <= 7;
                        seq_next <= ST_DECIDE_AFTER_REG_ADDR;
                        state    <= ST_TX_0;

                    -----------------------------------------------------------
                    -- Decisión: tras ACK de REG_ADDR
                    --   Write → capturar dato de WR FIFO
                    --   Read  → Repeated START en modo lectura
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_REG_ADDR =>
                        if r_rw = '0' then
                            if wr_empty_i = '0' then
                                wr_word <= wr_dout;  -- capturar (wr_dout es combinacional)
                                wr_pop  <= '1';      -- avanzar puntero en el flanco siguiente
                                state   <= ST_LOAD_DATA_H;
                            end if;
                            -- FIFO vacía: esperar en este estado
                        else
                            start_rd_mode <= '1';
                            state         <= ST_START_0;
                        end if;

                    -----------------------------------------------------------
                    -- ST_LOAD_DATA_H: wr_word estable → cargar byte alto en TX
                    -----------------------------------------------------------
                    when ST_LOAD_DATA_H =>
                        tx_byte  <= wr_word(15 downto 8);
                        bit_cnt  <= 7;
                        seq_next <= ST_DECIDE_AFTER_DATA_H;
                        state    <= ST_TX_0;

                    -----------------------------------------------------------
                    -- Decisión: tras ACK de DATA_H → enviar byte bajo
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_DATA_H =>
                        tx_byte  <= wr_word(7 downto 0);
                        bit_cnt  <= 7;
                        seq_next <= ST_DECIDE_AFTER_DATA_L;
                        state    <= ST_TX_0;

                    -----------------------------------------------------------
                    -- Decisión: tras ACK de DATA_L → ¿más registros?
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_DATA_L =>
                        reg_cnt <= reg_cnt + 1;
                        if reg_cnt + 1 = r_num_regs then
                            state <= ST_STOP_0;         -- todos escritos
                        else
                            if wr_empty_i = '0' then
                                wr_word <= wr_dout;
                                wr_pop  <= '1';
                                state   <= ST_LOAD_NEXT_DATA_H;
                            end if;
                            -- FIFO vacía: esperar aquí
                        end if;

                    -----------------------------------------------------------
                    -- ST_LOAD_NEXT_DATA_H: igual que ST_LOAD_DATA_H
                    -- (estado separado para claridad; mismo comportamiento)
                    -----------------------------------------------------------
                    when ST_LOAD_NEXT_DATA_H =>
                        tx_byte  <= wr_word(15 downto 8);
                        bit_cnt  <= 7;
                        seq_next <= ST_DECIDE_AFTER_DATA_H;
                        state    <= ST_TX_0;

                    -----------------------------------------------------------
                    -- Decisión READ: tras ACK de ADDR_RD → recibir DATA_H
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_ADDR_RD =>
                        send_nack <= '0';
                        bit_cnt   <= 7;
                        seq_next  <= ST_DECIDE_AFTER_RX_H;
                        state     <= ST_RX_0;

                    -----------------------------------------------------------
                    -- Decisión: tras MACK de DATA_H → recibir DATA_L
                    -- Activar NACK si este es el último registro
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_RX_H =>
                        rx_high <= rx_byte;
                        if reg_cnt + 1 = r_num_regs then
                            send_nack <= '1';   -- último registro → NACK en DATA_L
                        else
                            send_nack <= '0';
                        end if;
                        bit_cnt  <= 7;
                        seq_next <= ST_DECIDE_AFTER_RX_L;
                        state    <= ST_RX_0;

                    -----------------------------------------------------------
                    -- Decisión: tras MACK de DATA_L → push RD FIFO, ¿más?
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_RX_L =>
                        if rd_full_i = '0' then
                            rd_din  <= rx_high & rx_byte;
                            rd_push <= '1';
                            reg_cnt <= reg_cnt + 1;
                            if reg_cnt + 1 = r_num_regs then
                                state <= ST_STOP_0;     -- todos leídos
                            else
                                send_nack <= '0';
                                bit_cnt   <= 7;
                                seq_next  <= ST_DECIDE_AFTER_RX_H;
                                state     <= ST_RX_0;
                            end if;
                        else
                            state <= ST_ERROR_STOP;     -- RD FIFO llena
                        end if;

                    -----------------------------------------------------------
                    -- RX byte reutilizable
                    -- Precargar antes de entrar: send_nack, bit_cnt=7, seq_next
                    -- Captura bit a bit de MSB a LSB, luego va a ST_MACK_0
                    -----------------------------------------------------------
                    when ST_RX_0 =>
                        if phase_tick = '1' then
                            scl_r <= '0'; sda_oe <= '0'; state <= ST_RX_1;
                        end if;

                    when ST_RX_1 =>
                        if phase_tick = '1' then
                            scl_r <= '1'; state <= ST_RX_2;
                        end if;

                    when ST_RX_2 =>
                        if phase_tick = '1' then
                            rx_byte(bit_cnt) <= sda_in; state <= ST_RX_3;
                        end if;

                    when ST_RX_3 =>
                        if phase_tick = '1' then
                            scl_r <= '0';
                            if bit_cnt = 0 then
                                bit_cnt <= 7;
                                state   <= ST_MACK_0;
                            else
                                bit_cnt <= bit_cnt - 1;
                                state   <= ST_RX_0;
                            end if;
                        end if;

                    -----------------------------------------------------------
                    -- MACK: master envía ACK ('0') o NACK ('1') según send_nack
                    -----------------------------------------------------------
                    when ST_MACK_0 =>
                        if phase_tick = '1' then
                            scl_r     <= '0';
                            sda_oe    <= '1';
                            sda_out_r <= send_nack;
                            state     <= ST_MACK_1;
                        end if;

                    when ST_MACK_1 =>
                        if phase_tick = '1' then
                            scl_r <= '1'; state <= ST_MACK_2;
                        end if;

                    when ST_MACK_2 =>
                        if phase_tick = '1' then
                            state <= ST_MACK_3;
                        end if;

                    when ST_MACK_3 =>
                        if phase_tick = '1' then
                            scl_r <= '0'; state <= seq_next;
                        end if;

                    -----------------------------------------------------------
                    -- STOP: SDA sube mientras SCL está alto
                    -----------------------------------------------------------
                    when ST_STOP_0 =>
                        if phase_tick = '1' then
                            scl_r <= '0'; sda_out_r <= '0'; sda_oe <= '1';
                            state <= ST_STOP_1;
                        end if;

                    when ST_STOP_1 =>
                        if phase_tick = '1' then
                            scl_r <= '1'; state <= ST_STOP_2;
                        end if;

                    when ST_STOP_2 =>
                        if phase_tick = '1' then
                            sda_out_r <= '1';   -- SDA sube con SCL alto → condición STOP
                            state     <= ST_STOP_3;
                        end if;

                    when ST_STOP_3 =>
                        if phase_tick = '1' then
                            state <= ST_DONE;
                        end if;

                    -----------------------------------------------------------
                    when ST_DONE =>
                        done_i <= '1';
                        busy_i <= '0';
                        state  <= ST_IDLE;

                    when ST_ERROR_STOP =>
                        error_i <= '1';
                        state   <= ST_STOP_0;   -- liberar bus antes de volver a IDLE

                    when ST_ERROR =>
                        error_i <= '1';
                        busy_i  <= '0';
                        state   <= ST_IDLE;

                    when others =>
                        state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process p_fsm;

    ---------------------------------------------------------------------------
    -- Asignación de salidas
    ---------------------------------------------------------------------------
    scl_out  <= scl_r;
    sda_out  <= sda_out_r;
    sda_oe_o <= sda_oe;

    busy  <= busy_i;
    done  <= done_i;
    error <= error_i;

end architecture rtl;
