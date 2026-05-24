--! \file TOP.vhd
--! \brief VICON: Top Level.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

library work;
use work.config_pkg.all;


--! \brief Entidad de Sistema de Visión.
--! \fsm_show_actions
entity TOP is
    generic ( 
        g_SYSTEM_CLK_FREQ_HZ        : integer                      := c_SYSTEM_CLK_FREQ_HZ;        --! Frecuencia del reloj (s_mclk) para cálculos, CUIDADO puede no coincidir
        g_MT9V111_MCLK_DIV          : integer                      := c_MT9V111_MCLK_DIV;          --! Divisor del reloj del sistema para generar mt_clk_o
        g_MT9V111_I2C_FREQ_HZ       : integer                      := c_MT9V111_I2C_FREQ_HZ;       --! Frecuencia del bus I2C usado para comunicación con MT9V111
        g_MT9V111_I2C_FIFO_DEPTH    : integer                      := c_MT9V111_I2C_FIFO_DEPTH;    --! Profundidad de las FIFOs de LECTURA y ESCRITURA de tramas I2C (mclk <-> sclk)     
        g_MT9V111_I2C_SENSOR_ADDR   : std_logic_vector(6 downto 0) := c_MT9V111_I2C_SENSOR_ADDR;   --! Dirección de 7 bits del MT9V111 dentro del bus I2C
        g_MT9V111_H_RES             : integer                      := c_MT9V111_H_RES;             --! Resolución horizontal del sensor en píxeles
        g_MT9V111_V_RES             : integer                      := c_MT9V111_V_RES;             --! Resolución vertical del sensor en píxeles
        g_MT9V111_RESET_HOLD_US     : integer                      := c_MT9V111_RESET_HOLD_US;     --! Tiempo mínimo de RESET# a nivel bajo según datasheet (µs)
        g_MT9V111_RESET_WAIT_US     : integer                      := c_MT9V111_RESET_WAIT_US      --! Tiempo de espera tras liberar RESET# para estabilización del PLL (µs)
        );
    port (
        -- Basys 3 Ports: Propios de la placa de evaluación
        basys3_clk_i   : in    std_logic;                                              --! Señal de reloj externa
        basys3_sw_i    : in    std_logic_vector(c_BASYS3_SW_QTY-1          downto 0);  --! Interruptores deslizantes de la tarjeta: 0-Dcha
        basys3_led_o   : out   std_logic_vector(c_BASYS3_LED_QTY-1         downto 0);  --! LEDs de la tarjeta: 0-Dcha
        basys3_cat_o   : out   std_logic_vector(c_BASYS3_7SEG_BAR_QTY-1    downto 0);  --! Cátodos de cada "línea" o "barra" de un dígito, ver imagen de datasheet
        basys3_dp_o    : out   std_logic;                                              --! Cátodo de punto de dígito
        basys3_an_o    : out   std_logic_vector(c_BASYS3_7SEG_DIGIT_QTY-1  downto 0);  --! Ánodos de cada dígito: 0-Dcha
        basys3_btn_i   : in    std_logic_vector(c_BASYS3_BTN_QTY-1         downto 0);  --! Pulsadores de la Basys3: ¿¿ 0-Centro, 1-Dcha, 2-Arriba, 3-Izda, 4-Abajo ?? 
        -- MT9V111 Ports: Señales del sensor óptico
        mt_data_i      : in    std_logic_vector(c_MT9V111_DATA_BITS-1      downto 0);  --! Datos de imagen que proporciona el sensor MT9V111
        mt_lvalid_i    : in    std_logic;                                              --! Indica cuando una línea ...
        mt_pixclk_i    : in    std_logic;                                              --! Indica cuando ...
        mt_fvalid_i    : in    std_logic;                                              --! Indica cuando ...
        mt_reset_n_o   : out   std_logic;                                              --! Reset a nivel bajo del MT9V111
        mt_clk_o       : out   std_logic;                                              --! Señal de reloj que hay que proporcionar al MT9V111
            -- BUS I2C
        i2c_sclk_io    : inout std_logic;                                              --! Señal de reloj del bus I2C conectado al MT9V111
        i2c_sdata_io   : inout std_logic;                                              --! Señal de datos del bus I2C conectado al MT9V111
        -- FT232H Ports: Señales del chip FTDI
        ftdi_adbus_o   : out   std_logic_vector(c_FTDI_DATABUS_W-1         downto 0);  --! Señales de datos transferidos entre FPGA y chip FTDI
        ftdi_acbus_io  : inout std_logic_vector(c_FTDI_CONTROLBUS_W-1      downto 0)   --! Señales de control transferidos entre FPGA y chip FTDI
    );
end entity TOP;

architecture Behavioral of TOP is

    constant c_MT9V111_RESET_HOLD_CYCLES : integer := (g_SYSTEM_CLK_FREQ_HZ / 1_000_000) * g_MT9V111_RESET_HOLD_US;
    constant c_MT9V111_RESET_WAIT_CYCLES : integer := (g_SYSTEM_CLK_FREQ_HZ / 1_000_000) * g_MT9V111_RESET_WAIT_US;
    
    ---------------------------------------------------------------------------
    -- Señales de RELOJ & RESET
    ---------------------------------------------------------------------------
    signal s_mclk         : std_logic;                                            --! Reloj estabilizado por el MMCM
    signal s_locked       : std_logic;                                            --! Activada (LL) cuando el MMCM genera un reloj estable (Async?) 
    signal s_rst_final    : std_logic;                                            --! Reset vinculado a la correcta generación de s_mclk. (Async?) Añadir 2FF Sync
    signal s_mclk_div_cnt : integer range 0 to g_MT9V111_MCLK_DIV - 1 := 0;       --! Ciclos de reloj de s_mclk que hay en flanco activo de s_cam_mclk_o
    signal cam_mclk_r     : std_logic                                 := '0';     --! Registro del divisor de reloj que genera mt_clk_o

    ---------------------------------------------------------------------------
    -- Señales MT9V111 — Interfaz FSM <-> Controlador I2C
    ---------------------------------------------------------------------------
    signal s_i2c_rw       : std_logic                                    := '0';              --! Dirección de la transacción: '0'=escritura, '1'=lectura
    signal s_i2c_start    : std_logic                                    := '0';              --! Pulso de inicio de transacción I2C (activo 1 ciclo de s_mclk)
    signal s_i2c_num_regs : integer range 1 to g_MT9V111_I2C_FIFO_DEPTH  := 1;                --! Número de registros a transferir en la transacción en curso
    signal s_i2c_addr_reg : std_logic_vector(7 downto 0)                 := (others => '0');  --! Dirección del registro del MT9V111 al que se accede
    signal s_i2c_wr_push  : std_logic                                    := '0';              --! Pulso para encolar un dato en la FIFO de escritura (activo 1 ciclo)
    signal s_i2c_wr_data  : std_logic_vector(15 downto 0)                := (others => '0');  --! Dato de 16 bits a escribir en el registro del MT9V111
    signal s_i2c_wr_full  : std_logic;                                                        --! FIFO de escritura llena; no encolar más datos
    signal s_i2c_wr_empty : std_logic;                                                        --! FIFO de escritura vacía; todos los datos han sido enviados
    signal s_i2c_rd_pop   : std_logic                                    := '0';              --! Pulso para extraer un dato de la FIFO de lectura (activo 1 ciclo)
    signal s_i2c_rd_data  : std_logic_vector(15 downto 0);                                    --! Dato de 16 bits leído del registro del MT9V111
    signal s_i2c_rd_full  : std_logic;                                                        --! FIFO de lectura llena; no llegar a este estado antes de drenar
    signal s_i2c_rd_empty : std_logic;                                                        --! FIFO de lectura vacía; no hay datos disponibles para leer
    signal s_i2c_busy     : std_logic;                                                        --! El controlador I2C está ejecutando una transacción activamente
    signal s_i2c_done     : std_logic;                                                        --! Pulso que indica fin correcto de transacción (activo 1 ciclo)
    signal s_i2c_error    : std_logic;                                                        --! Pulso que indica error en la transacción: NACK u otro fallo
    -- Bus I2C — señales físicas open-drain                                                               
    signal s_scl_out      : std_logic;                                                        --! Valor a aplicar en SCL: '0'=pull-down activo, '1'=soltar (Z)
    signal s_sda_out      : std_logic;                                                        --! Buffer Triestate sda: valor a conducir cuando s_sda_oe='1'
    signal s_sda_oe       : std_logic;                                                        --! Buffer Triestate sda: habilitación de salida : '1'=conducir s_sda_out, '0'=Z
    signal s_sda_in       : std_logic;                                                        --! Buffer Triestate sda: valor muestreado del bus  (leído de i2c_sdata_io)

    ---------------------------------------------------------------------------
    -- Señales FTDI — Transferencia de imagen al PC vía FT232H
    ---------------------------------------------------------------------------
    signal s_ftdi_clk       : std_logic;                                        --! Reloj 60 MHz proporcionado por el FT232H; entra por ACBUS[5] vía BUFG
    signal s_ftdi_txe_n     : std_logic;                                        --! TXE# (activo bajo): '0'=FT232H listo para recibir; leído de ACBUS[1]
    signal s_ftdi_wr_n      : std_logic;                                        --! WR# (activo bajo): pulso de escritura de byte en ADBUS; enviado a ACBUS[3]
    signal s_ftdi_adbus     : std_logic_vector(7 downto 0);                     --! Byte de datos a enviar al FT232H por el bus ADBUS
    signal s_ftdi_tx_active : std_logic;                                        --! Indica que el controlador FTDI está activamente escribiendo datos

    ---------------------------------------------------------------------------
    -- Señales de Captura de Frame — FIFO asíncrona pixclk → ftdi_clk
    ---------------------------------------------------------------------------
    signal s_cap_fifo_data  : std_logic_vector(7 downto 0);                     --! Byte de píxel a escribir en la FIFO de captura (dominio pixclk)
    signal s_cap_fifo_wr    : std_logic;                                        --! Habilitación de escritura en la FIFO de captura (dominio pixclk)
    signal s_cap_fifo_full  : std_logic;                                        --! FIFO de captura llena; frame_capture debe detener escritura
    signal s_cap_fifo_empty : std_logic;                                        --! FIFO de captura vacía; el controlador FTDI no puede leer
    signal s_cap_fifo_dout  : std_logic_vector(7 downto 0);                     --! Byte leído de la FIFO de captura (dominio ftdi_clk)
    signal s_cap_fifo_rd_en : std_logic;                                        --! Habilitación de lectura de la FIFO de captura (dominio ftdi_clk)
    signal s_cap_frame_done : std_logic;                                        --! Pulso que indica que un frame completo ha sido capturado
    signal s_cap_overflow   : std_logic;                                        --! Desbordamiento: la FIFO se llenó antes de vaciarse; frame corrupto
    signal s_cap_en         : std_logic;                                        --! Habilitación de captura: activa únicamente en estado ST_FINISH

    type main_state_t is (
        ST_CAM_RESET_ASSERT,        --! Mantiene RESET# a '0' durante RESET_HOLD_CYCLES ciclos
        ST_CAM_RESET_WAIT,          --! Libera RESET# y espera RESET_WAIT_CYCLES para estabilización del sensor
        ST_PAGE_SEL_FILL,           --! Encola en la FIFO de escritura el valor de page (0x0004 → IFP page 1)
        ST_PAGE_SEL_START,          --! Lanza transacción I2C de escritura al registro 0x01 (Page Map)
        ST_PAGE_SEL_WAIT,           --! Espera a que el controlador I2C señale done o error
        ST_CHIPID_RD_START,         --! Lanza transacción I2C de lectura del registro 0xFF (Chip ID)
        ST_CHIPID_RD_WAIT,          --! Espera a que el controlador I2C señale done o error
        ST_CHIPID_RD_DRAIN,         --! Extrae el Chip ID de la FIFO de lectura y verifica el valor esperado
        ST_FINISH,                  --! Chip ID correcto: configura captura activa y enciende LED de OK
        ST_ERROR                    --! Error I2C o Chip ID incorrecto: enciende LED de error y se detiene
    );

    signal s_state       : main_state_t                                   := ST_CAM_RESET_ASSERT;     --! Estado actual de la FSM de inicialización del sensor
    signal s_init_cnt    : integer range 0 to c_MT9V111_RESET_WAIT_CYCLES := 0;                       --! Contador de ciclos para temporización de reset e inicialización
    signal s_fill_cnt    : integer range 0 to g_MT9V111_I2C_FIFO_DEPTH    := 0;                       --! Contador de registros encolados en la FIFO de escritura I2C
    signal cam_reset_r   : std_logic                                      := '0';                     --! Registro de control del pin RESET# del MT9V111 (activo bajo)
    signal s_chip_id     : std_logic_vector(15 downto 0)                  := (others => '0');         --! Chip ID leído del MT9V111 (esperado: CHIP_ID_EXPECTED)

    ---------------------------------------------------------------------------
    -- Señales de Simulación — sustituyen entradas del sensor en testbench
    ---------------------------------------------------------------------------
    signal s_sim_fval : std_logic;                                              --! FVALID simulado generado por cam_sim
    signal s_sim_lval : std_logic;                                              --! LVALID simulado generado por cam_sim
    signal s_sim_dout : std_logic_vector(7 downto 0);                           --! Datos de píxel simulados generados por cam_sim

    ---------------------------------------------------------------------------
    -- Señales de Debug — capturadas en s_mclk para el ILA
    ---------------------------------------------------------------------------
    signal debug_sclk   : std_logic;                     --! ILA: SCL conducido por el controlador I2C
    signal debug_sdata  : std_logic;                     --! ILA: SDA muestreado del bus I2C
    signal debug_dout   : std_logic_vector(7 downto 0);  --! ILA: Byte de datos del sensor (dominio pixclk → mclk)
    signal debug_pixclk : std_logic;                     --! ILA: Reloj del sensor registrado en mclk
    signal debug_fval   : std_logic;                     --! ILA: FVALID del sensor registrado en mclk
    signal debug_lval   : std_logic;                     --! ILA: LVALID del sensor registrado en mclk
    signal debug_txe_n  : std_logic;                     --! ILA: TXE# del FT232H registrado en mclk
    signal debug_wr_n   : std_logic;                     --! ILA: WR# enviado al FT232H registrado en mclk

begin

    --! \todo Async? Añadir 2FF Sync?
    s_rst_final <= not s_locked;

    i2c_sclk_io   <= '0' when s_scl_out        = '0' else 'Z';
    i2c_sdata_io  <= s_sda_out when s_sda_oe = '1' else 'Z';
    s_sda_in      <= i2c_sdata_io;

    mt_reset_n_o <= cam_reset_r;
    mt_clk_o     <= cam_mclk_r;
    s_cap_en     <= '1' when s_state = ST_FINISH else '0';

    ---------------------------------------------------------------------------
    -- FTDI — CLKOUT via BUFG, OE# y PWRSAV# y SIWU# fijos
    ---------------------------------------------------------------------------
    ftdi_clk_buf : BUFG
        port map (
            I => ftdi_acbus_io(c_FTDI_ACBUS_CLKOUT),
            O => s_ftdi_clk
        );

    ftdi_acbus_io(c_FTDI_ACBUS_RXF_N)      <= 'Z';
    ftdi_acbus_io(c_FTDI_ACBUS_TXE_N)      <= 'Z';
    ftdi_acbus_io(c_FTDI_ACBUS_RD_N)       <= '1';
    ftdi_acbus_io(c_FTDI_ACBUS_WR_N)       <= s_ftdi_wr_n;
    ftdi_acbus_io(c_FTDI_ACBUS_SIWU_N)     <= '1';
    -- FTDI_ACBUS_CLKOUT — entrada via BUFG (ver ftdi_clk_buf)
    ftdi_acbus_io(c_FTDI_ACBUS_OE_N)       <= '1';
    ftdi_acbus_io(c_FTDI_ACBUS_PWRSAV)     <= '1';

    ftdi_adbus_o <= s_ftdi_adbus;
    s_ftdi_txe_n <= ftdi_acbus_io(c_FTDI_ACBUS_TXE_N);

    basys3_cat_o <= (others => '0');
    basys3_dp_o  <= '0';
    basys3_an_o  <= (others => '1');
    
    --! \brief Registro de algunos puertos y señales de otros dominios en s_mclk 
    p_debug : process(s_mclk)
    begin
        if rising_edge(s_mclk) then
            debug_sclk   <= s_scl_out;
            debug_sdata  <= s_sda_in;
            debug_dout   <= mt_data_i;
            debug_pixclk <= mt_pixclk_i;
            debug_fval   <= mt_fvalid_i;
            debug_lval   <= mt_lvalid_i;
            debug_txe_n  <= s_ftdi_txe_n;
            debug_wr_n   <= s_ftdi_wr_n;
        end if;
    end process p_debug;

    --! \brief Clock Divider: generación de s_cam_mclk, freq ~ SYSTEM_CLK_FREQ_HZ/MT9V111_MCLK_DIV
    p_cam_mclk : process(s_mclk)
    begin
        if rising_edge(s_mclk) then
            if s_rst_final = '1' then
                s_mclk_div_cnt <= 0;
                cam_mclk_r   <= '0';
            elsif s_mclk_div_cnt = g_MT9V111_MCLK_DIV - 1 then
                s_mclk_div_cnt <= 0;
                cam_mclk_r     <= not cam_mclk_r;
            else
                s_mclk_div_cnt <= s_mclk_div_cnt + 1;
            end if;
        end if;
    end process p_cam_mclk;
    
    --! \brief Máquina de estados principal de VICON
    p_fsm : process(s_mclk)
    begin
        if rising_edge(s_mclk) then
            if s_rst_final = '1' then
                s_state          <= ST_CAM_RESET_ASSERT;
                cam_reset_r      <= '0';
                s_init_cnt       <= 0;
                s_i2c_rw         <= '0';
                s_i2c_start      <= '0';
                s_i2c_wr_push    <= '0';
                s_i2c_rd_pop     <= '0';
                s_i2c_num_regs   <= 1;
                s_i2c_addr_reg   <= (others => '0');
                s_i2c_wr_data    <= (others => '0');
                s_fill_cnt       <= 0;
                s_chip_id        <= (others => '0');
                basys3_led_o(0)  <= '0';
                basys3_led_o(1)  <= '0';
            else
                s_i2c_start   <= '0';
                s_i2c_wr_push <= '0';
                s_i2c_rd_pop  <= '0';

                case s_state is

                    when ST_CAM_RESET_ASSERT =>
                        cam_reset_r <= '0';
                        if s_init_cnt = c_MT9V111_RESET_HOLD_CYCLES - 1 then
                            s_init_cnt <= 0;
                            s_state    <= ST_CAM_RESET_WAIT;
                        else
                            s_init_cnt <= s_init_cnt + 1;
                        end if;

                    when ST_CAM_RESET_WAIT =>
                        cam_reset_r <= '1';
                        if s_init_cnt = c_MT9V111_RESET_WAIT_CYCLES - 1 then
                            s_init_cnt <= 0;
                            s_fill_cnt <= 0;
                            s_state    <= ST_PAGE_SEL_FILL;
                        else
                            s_init_cnt <= s_init_cnt + 1;
                        end if;

                    when ST_PAGE_SEL_FILL =>
                        if s_i2c_wr_full = '0' then
                            s_i2c_wr_data <= x"0004";
                            s_i2c_wr_push <= '1';
                            s_state       <= ST_PAGE_SEL_START;
                        end if;

                    when ST_PAGE_SEL_START =>
                        if s_i2c_busy = '0' then
                            s_i2c_rw       <= '0';
                            s_i2c_addr_reg <= x"01";
                            s_i2c_num_regs <= 1;
                            s_i2c_start    <= '1';
                            s_state        <= ST_PAGE_SEL_WAIT;
                        end if;

                    when ST_PAGE_SEL_WAIT =>
                        if s_i2c_error = '1' then
                            s_state <= ST_ERROR;
                        elsif s_i2c_done = '1' then
                            s_state <= ST_CHIPID_RD_START;
                        end if;

                    when ST_CHIPID_RD_START =>
                        if s_i2c_busy = '0' and s_i2c_rd_empty = '1' then
                            s_i2c_rw       <= '1';
                            s_i2c_addr_reg <= x"FF";
                            s_i2c_num_regs <= 1;
                            s_i2c_start    <= '1';
                            s_state        <= ST_CHIPID_RD_WAIT;
                        end if;

                    when ST_CHIPID_RD_WAIT =>
                        if s_i2c_error = '1' then
                            s_state <= ST_ERROR;
                        elsif s_i2c_done = '1' then
                            s_state <= ST_CHIPID_RD_DRAIN;
                        end if;

                    when ST_CHIPID_RD_DRAIN =>
                        if s_i2c_rd_empty = '0' then
                            s_i2c_rd_pop <= '1';
                            s_chip_id    <= s_i2c_rd_data;
                            if s_i2c_rd_data = c_MT9V111_CHIP_ID_EXPECTED then
                                s_state <= ST_FINISH;
                            else
                                s_state <= ST_ERROR;
                            end if;
                        end if;

                    when ST_FINISH =>
                        basys3_led_o(0) <= '1';
                        basys3_led_o(1) <= '0';
                        s_state  <= ST_FINISH;

                    when ST_ERROR =>
                        basys3_led_o(0) <= '0';
                        basys3_led_o(1) <= '1';
                        s_state  <= ST_ERROR;

                    when others =>
                        s_state <= ST_CAM_RESET_ASSERT;

                end case;
            end if;
        end if;
    end process p_fsm;

    basys3_led_o(15 downto 2) <= basys3_sw_i(15 downto 2);


    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------
    -- INSTANCIAS DIRECTAS DE IPS DEL CATÁLOGO DE XILINX
    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------
    
    --! \brief Clock Modifying Block
    u_MMCM : entity work.clk_wiz_0
        port map (
            clk_in1  => basys3_clk_i,
            reset    => basys3_btn_i(c_BASYS3_BTN_CENTER),
            clk_out1 => s_mclk,
            locked   => s_locked
        );

    --! \brief  FIFO Asíncrona de Xilinx: relojes independientes
    u_async_fifo : entity work.fifo_generator_0
        port map (
            wr_clk    => mt_pixclk_i,
            din       => s_cap_fifo_data,
            wr_en     => s_cap_fifo_wr,
            full      => s_cap_fifo_full,
            rd_clk    => s_ftdi_clk,
            dout      => s_cap_fifo_dout,
            rd_en     => s_cap_fifo_rd_en,
            empty     => s_cap_fifo_empty,
            rst       => s_rst_final
        );
    
    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------
    -- INSTANCIAS DIRECTAS DE MÓDULOS
    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------
    
    --! \brief  Agente del MT9V111
    u_cam_sim : entity work.cam_sim
        port map (
            pixclk_i => mt_pixclk_i,
            reset_i  => s_rst_final,
            fvalid_i => s_sim_fval,
            lvalid_i => s_sim_lval,
            data_i   => s_sim_dout
        );

    --! \brief  Capturador de imágenes
    u_frame_capture : entity work.frame_capture
        generic map (
            H_RES => g_MT9V111_H_RES,
            V_RES => g_MT9V111_V_RES
        )
        port map (
            pixclk_i     => mt_pixclk_i,
            reset_i      => s_rst_final,
            fvalid_i     => s_sim_fval,
            lvalid_i     => s_sim_lval,
            data_i       => s_sim_dout,
            capture_en_i => s_cap_en,
            fifo_data_o  => s_cap_fifo_data,
            fifo_wr_o    => s_cap_fifo_wr,
            fifo_full_i  => s_cap_fifo_full,
            frame_done_o => s_cap_frame_done,
            overflow_o   => s_cap_overflow
        );
    
    
    
    --! \brief Interfaz con chip FTDI FT232H
    u_ftdi_ctrl : entity work.ftdi_controller
        port map (
            clk_i        => s_ftdi_clk,
            reset_i      => s_rst_final,
            fifo_data_i  => s_cap_fifo_dout,
            fifo_empty_i => s_cap_fifo_empty,
            fifo_rd_en_o => s_cap_fifo_rd_en,
            txe_n_i      => s_ftdi_txe_n,
            wr_n_o       => s_ftdi_wr_n,
            adbus_o      => s_ftdi_adbus,
            tx_active_o  => s_ftdi_tx_active
        );
    
    --! \brief Controlador I2C (Maestro)
    u_i2c : entity work.i2c_master
        generic map (
            g_CLK_FREQ_HZ => g_SYSTEM_CLK_FREQ_HZ,
            g_I2C_FREQ_HZ => g_MT9V111_I2C_FREQ_HZ,
            g_FIFO_DEPTH  => g_MT9V111_I2C_FIFO_DEPTH
        )
        port map (
            clk_i           => s_mclk,
            reset_i         => s_rst_final,
            rw_i            => s_i2c_rw,
            start_i2c_i     => s_i2c_start,
            num_regs_i      => s_i2c_num_regs,
            addr_dev_i      => g_MT9V111_I2C_SENSOR_ADDR,
            addr_reg_i      => s_i2c_addr_reg,
            wr_fifo_push_i  => s_i2c_wr_push,
            wr_fifo_data_i  => s_i2c_wr_data,
            wr_fifo_full_o  => s_i2c_wr_full,
            wr_fifo_empty_o => s_i2c_wr_empty,
            rd_fifo_pop_i   => s_i2c_rd_pop,
            rd_fifo_data_o  => s_i2c_rd_data,
            rd_fifo_full_o  => s_i2c_rd_full,
            rd_fifo_empty_o => s_i2c_rd_empty,
            busy_o          => s_i2c_busy,
            done_o          => s_i2c_done,
            error_o         => s_i2c_error,
            scl_o           => s_scl_out,
            sda_o           => s_sda_out,
            sda_oe_o        => s_sda_oe,
            sda_i           => s_sda_in
        );

    

end architecture Behavioral;