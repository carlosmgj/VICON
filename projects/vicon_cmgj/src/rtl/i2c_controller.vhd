--! \file i2c_controller.vhd
--! Controlador I2C para comunicación con el sensor MT9V111.
--! Protocolo MT9V111:
--!
--! - WRITE: S + ADDR_WR + ACK + REG_ADDR + ACK + DATA_H + ACK + DATA_L + ACK + [repetir DATA_H/DATA_L para más registros, auto-increment] + P
--!
--! - READ:  S + ADDR_WR + ACK + REG_ADDR + ACK + Sr + ADDR_RD + ACK + DATA_H + ACK + ... + DATA_L + NACK + P
--!
--! Timing SCL – 4 fases de CLKS_PER_PHASE ciclos de sistema cada una:
--! - _0  SCL=0  →  cambiar / preparar SDA
--! - _1  SCL=1
--! - _2  SCL=1  →  muestrear SDA
--! - _3  SCL=0  →  transición
--! @htmlonly
--! <iframe src="timing1.html"
--!         width="100%"
--!         height="400px"
--!         style="border:none;">
--! </iframe>
--! @endhtmlonly
--!
--! Bloques reutilizables en la FSM:
--!  - TX (ST_TX_*)   envía 'tx_byte' MSB-first. Al completar el bit 0 pasa a ST_RACK_* para recibir el ACK del esclavo.
--!                  Tras el ACK va a 'seq_next'.
--!
--!  - RX (ST_RX_*)   recibe un byte en 'rx_byte' MSB-first. Al completar el bit 0 pasa a ST_MACK_* donde el master envía ACK o NACK según 'send_nack'. 
--!                  Tras el ACK/NACK va a 'seq_next'.
--!
--!  - START (ST_START_*) genera condición START o Repeated START.
--!                  Tras completar carga tx_byte con la dirección y salta a TX.
--!                  La señal 'start_rd_mode' indica si la dirección va con R/W='1'.
--!   @warning Los estados ST_LOAD_DATA_H y ST_LOAD_NEXT_DATA_H añaden un ciclo de latencia para que 'wr_word' se estabilice antes de cargarlo en 'tx_byte'. Sin este ciclo extra, ST_TX_0 arrancaba con el valor antiguo de tx_byte.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_master is
    generic (
        CLK_FREQ_HZ : integer := 50_000_000;
        I2C_FREQ_HZ : integer := 400_000;
        FIFO_DEPTH  : integer := 16
    );
    port (
        clk           : in    std_logic;
        reset         : in    std_logic;
        -- Control
        rw            : in    std_logic;
        start_i2c     : in    std_logic;
        num_regs      : in    integer range 1 to FIFO_DEPTH;
        -- Dirección
        addr_dev      : in    std_logic_vector(6 downto 0);
        addr_reg      : in    std_logic_vector(7 downto 0);
        -- WR FIFO
        wr_fifo_push  : in    std_logic;
        wr_fifo_data  : in    std_logic_vector(15 downto 0);
        wr_fifo_full  : out   std_logic;
        wr_fifo_empty : out   std_logic;
        -- RD FIFO
        rd_fifo_pop   : in    std_logic;
        rd_fifo_data  : out   std_logic_vector(15 downto 0);
        rd_fifo_full  : out   std_logic;
        rd_fifo_empty : out   std_logic;
        -- Estado
        busy          : out   std_logic;
        done          : out   std_logic;
        error         : out   std_logic;
        -- Bus
        sclk          : out   std_logic;
        sdata         : inout std_logic
    );
end entity i2c_master;

architecture rtl of i2c_master is

    constant CLKS_PER_PHASE : integer := CLK_FREQ_HZ / (I2C_FREQ_HZ * 4);

    ---------------------------------------------------------------------------
    -- FIFOs
    ---------------------------------------------------------------------------
    type fifo_mem_t is array (0 to FIFO_DEPTH-1) of std_logic_vector(15 downto 0);


        --! Memoria de la FIFO de escritura (FIFO_DEPTH entradas de 16 bits)
    signal wr_mem     : fifo_mem_t := (others => (others => '0'));
    --! Puntero de escritura de la WR FIFO
    signal wr_wr_ptr  : integer range 0 to FIFO_DEPTH-1 := 0;
    --! Puntero de lectura de la WR FIFO
    signal wr_rd_ptr  : integer range 0 to FIFO_DEPTH-1 := 0;
    --! Número de entradas ocupadas en la WR FIFO
    signal wr_count   : integer range 0 to FIFO_DEPTH   := 0;
    --! Indicador de WR FIFO llena (combinacional)
    signal wr_full_i  : std_logic;
    --! Indicador de WR FIFO vacía (combinacional)
    signal wr_empty_i : std_logic;
    --! Pulso de pop interno de la WR FIFO (generado por la FSM)
    signal wr_pop     : std_logic := '0';
    --! Dato en la cabeza de la WR FIFO (combinacional sobre wr_rd_ptr)
    signal wr_dout    : std_logic_vector(15 downto 0);

    --! Memoria de la FIFO de lectura (FIFO_DEPTH entradas de 16 bits)
    signal rd_mem     : fifo_mem_t := (others => (others => '0'));
    --! Puntero de escritura de la RD FIFO
    signal rd_wr_ptr  : integer range 0 to FIFO_DEPTH-1 := 0;
    --! Puntero de lectura de la RD FIFO
    signal rd_rd_ptr  : integer range 0 to FIFO_DEPTH-1 := 0;
    --! Número de entradas ocupadas en la RD FIFO
    signal rd_count   : integer range 0 to FIFO_DEPTH   := 0;
    --! Indicador de RD FIFO llena (combinacional)
    signal rd_full_i  : std_logic;
    --! Indicador de RD FIFO vacía (combinacional)
    signal rd_empty_i : std_logic;
    --! Pulso de push interno de la RD FIFO (generado por la FSM tras recibir un registro)
    signal rd_push    : std_logic := '0';
    --! Dato a escribir en la RD FIFO (rx_high & rx_byte)
    signal rd_din     : std_logic_vector(15 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- FSM
    ---------------------------------------------------------------------------
    type state_t is (
        ST_IDLE,
        -- START / Repeated START
        ST_START_0, ST_START_1, ST_START_2, ST_START_3,
        -- TX byte + RACK del esclavo
        ST_TX_0, ST_TX_1, ST_TX_2, ST_TX_3,
        ST_RACK_0, ST_RACK_1, ST_RACK_2, ST_RACK_3,
        -- RX byte + MACK del master
        ST_RX_0, ST_RX_1, ST_RX_2, ST_RX_3,
        ST_MACK_0, ST_MACK_1, ST_MACK_2, ST_MACK_3,
        -- Puntos de decisión de secuencia (WRITE)
        ST_DECIDE_AFTER_ADDR_WR,
        ST_DECIDE_AFTER_REG_ADDR,
        ST_LOAD_DATA_H,          -- espera 1 ciclo para que wr_word se estabilice
        ST_DECIDE_AFTER_DATA_H,
        ST_DECIDE_AFTER_DATA_L,
        ST_LOAD_NEXT_DATA_H,     -- igual que ST_LOAD_DATA_H para registros siguientes
        -- Puntos de decisión de secuencia (READ)
        ST_DECIDE_AFTER_ADDR_RD,
        ST_DECIDE_AFTER_RX_H,
        ST_DECIDE_AFTER_RX_L,
        -- STOP
        ST_STOP_0, ST_STOP_1, ST_STOP_2, ST_STOP_3,
        -- Fin
        ST_DONE,
        ST_ERROR_STOP,
        ST_ERROR
    );
    signal state    : state_t := ST_IDLE;
    signal seq_next : state_t := ST_IDLE;   -- retorno tras TX+RACK o RX+MACK

    ---------------------------------------------------------------------------
    -- Registros de la transacción
    ---------------------------------------------------------------------------
    signal r_rw           : std_logic := '0';
    signal r_addr_dev     : std_logic_vector(6 downto 0)  := (others => '0');
    signal r_addr_reg     : std_logic_vector(7 downto 0)  := (others => '0');
    signal r_num_regs     : integer range 1 to FIFO_DEPTH := 1;
    signal reg_cnt        : integer range 0 to FIFO_DEPTH := 0;

    -- '1' → el bloque START enviará addr_dev con R/W='1' (lectura)
    signal start_rd_mode  : std_logic := '0';

    -- Byte en curso de TX/RX
    signal tx_byte        : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_byte        : std_logic_vector(7 downto 0) := (others => '0');
    signal bit_cnt        : integer range 0 to 7 := 7;

    -- Dato capturado de WR FIFO para el registro en curso
    -- Se captura en ST_DECIDE_AFTER_REG_ADDR / ST_DECIDE_AFTER_DATA_L
    -- y se usa en ST_LOAD_DATA_H / ST_LOAD_NEXT_DATA_H un ciclo después.
    signal wr_word        : std_logic_vector(15 downto 0) := (others => '0');

    -- Byte alto recibido (read), se empareja con el byte bajo en ST_DECIDE_AFTER_RX_L
    signal rx_high        : std_logic_vector(7 downto 0) := (others => '0');

    -- '1' → MACK enviará NACK en lugar de ACK
    signal send_nack      : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Timing
    ---------------------------------------------------------------------------
    signal phase_cnt  : integer range 0 to CLKS_PER_PHASE-1 := 0;
    signal phase_tick : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Bus
    ---------------------------------------------------------------------------
    signal scl_r     : std_logic := '1';
    signal sda_out_r : std_logic := '1';
    signal sda_oe    : std_logic := '1';   -- '1'=drive  '0'=tristate

    ---------------------------------------------------------------------------
    -- Salidas internas
    ---------------------------------------------------------------------------
    signal busy_i  : std_logic := '0';
    signal done_i  : std_logic := '0';
    signal error_i : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- WR FIFO
    -- wr_dout es combinacional sobre wr_rd_ptr (lectura asíncrona).
    -- El pop avanza wr_rd_ptr en el flanco siguiente, por eso se necesita
    -- ST_LOAD_DATA_H para capturar wr_word antes de usarlo en TX.
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
    ---------------------------------------------------------------------------
    p_phase : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                phase_cnt <= 0; phase_tick <= '0';
            elsif phase_cnt = CLKS_PER_PHASE - 1 then
                phase_cnt <= 0; phase_tick <= '1';
            else
                phase_cnt  <= phase_cnt + 1;
                phase_tick <= '0';
            end if;
        end if;
    end process p_phase;

    ---------------------------------------------------------------------------
    -- FSM principal
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
                    -- SDA baja mientras SCL está alto → condición START
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
                            sda_out_r <= '0';   -- SDA baja con SCL alto → START
                            state     <= ST_START_3;
                        end if;

                    when ST_START_3 =>
                        if phase_tick = '1' then
                            scl_r   <= '0';
                            bit_cnt <= 7;
                            if start_rd_mode = '0' then
                                tx_byte  <= r_addr_dev & '0';   -- Write
                                seq_next <= ST_DECIDE_AFTER_ADDR_WR;
                            else
                                tx_byte  <= r_addr_dev & '1';   -- Read
                                seq_next <= ST_DECIDE_AFTER_ADDR_RD;
                            end if;
                            state <= ST_TX_0;
                        end if;

                    -----------------------------------------------------------
                    -- TX byte reutilizable
                    -- Precargar: tx_byte, bit_cnt=7, seq_next
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
                    -- RACK: ACK del esclavo (SDA='0'=ACK, '1'=NACK)
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
                            if sdata = '1' then
                                state <= ST_ERROR_STOP;
                            else
                                state <= ST_RACK_3;
                            end if;
                        end if;

                    when ST_RACK_3 =>
                        if phase_tick = '1' then
                            scl_r <= '0'; state <= seq_next;
                        end if;

                    -----------------------------------------------------------
                    -- Decisión WRITE: tras RACK de ADDR_WR → enviar REG_ADDR
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_ADDR_WR =>
                        tx_byte  <= r_addr_reg;
                        bit_cnt  <= 7;
                        seq_next <= ST_DECIDE_AFTER_REG_ADDR;
                        state    <= ST_TX_0;

                    -----------------------------------------------------------
                    -- Decisión: tras RACK de REG_ADDR
                    --   Write → capturar dato de WR FIFO, esperar un ciclo
                    --   Read  → Repeated START con R/W='1'
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_REG_ADDR =>
                        if r_rw = '0' then
                            if wr_empty_i = '0' then
                                wr_word <= wr_dout;   -- capturar dato (wr_dout combinacional)
                                wr_pop  <= '1';       -- avanzar puntero en el flanco siguiente
                                state   <= ST_LOAD_DATA_H;
                            end if;
                            -- Si FIFO vacía: esperar en este estado
                        else
                            start_rd_mode <= '1';
                            state         <= ST_START_0;
                        end if;

                    -----------------------------------------------------------
                    -- ST_LOAD_DATA_H: wr_word ya estable → cargar byte alto en TX
                    -----------------------------------------------------------
                    when ST_LOAD_DATA_H =>
                        tx_byte  <= wr_word(15 downto 8);
                        bit_cnt  <= 7;
                        seq_next <= ST_DECIDE_AFTER_DATA_H;
                        state    <= ST_TX_0;

                    -----------------------------------------------------------
                    -- Decisión: tras RACK de DATA_H → enviar byte bajo
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_DATA_H =>
                        tx_byte  <= wr_word(7 downto 0);
                        bit_cnt  <= 7;
                        seq_next <= ST_DECIDE_AFTER_DATA_L;
                        state    <= ST_TX_0;

                    -----------------------------------------------------------
                    -- Decisión: tras RACK de DATA_L → ¿más registros?
                    -----------------------------------------------------------
                    when ST_DECIDE_AFTER_DATA_L =>
                        reg_cnt <= reg_cnt + 1;
                        if reg_cnt + 1 = r_num_regs then
                            state <= ST_STOP_0;     -- todos escritos
                        else
                            -- Más registros: capturar siguiente dato
                            if wr_empty_i = '0' then
                                wr_word <= wr_dout;
                                wr_pop  <= '1';
                                state   <= ST_LOAD_NEXT_DATA_H;
                            end if;
                            -- Si FIFO vacía: esperar aquí
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
                    -- Decisión READ: tras RACK de ADDR_RD → recibir DATA_H
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
                            send_nack <= '1';   -- último byte → NACK
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
                    -- Precargar: send_nack, bit_cnt=7, seq_next
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
                            rx_byte(bit_cnt) <= sdata; state <= ST_RX_3;
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
                            sda_out_r <= '1';   -- SDA sube con SCL alto → STOP
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
    -- Salidas
    ---------------------------------------------------------------------------
    sclk  <= scl_r;
    sdata <= sda_out_r when sda_oe = '1' else 'Z';
    busy  <= busy_i;
    done  <= done_i;
    error <= error_i;

end architecture rtl;