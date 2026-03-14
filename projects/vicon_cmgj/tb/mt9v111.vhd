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
    signal s_reg_addr  : integer range 0 to 255;
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
        variable v_rw        : std_logic := '0';
        variable v_reg_addr  : integer range 0 to 255;
        variable v_reg_inc   : integer range 0 to 255;
        variable v_data_h    : std_logic_vector(7 downto 0);
        variable v_data_l    : std_logic_vector(7 downto 0);
        variable v_data_16   : std_logic_vector(15 downto 0);
        variable v_stop_seen : boolean;
        variable v_start_seen : boolean;
        variable v_mack      : std_logic;
        variable v_send_byte : std_logic_vector(7 downto 0);

    begin
        sda <= 'Z';


        loop

            
            ---------------------------------------------------------------------------------------------------------------------------------------------------------------
            ----------------------                                         START 
            ---------------------------------------------------------------------------------------------------------------------------------------------------------------

            
            debug_state <= "ESPERANDO_START  (0)";
            wait until falling_edge(sda) and scl = '1';
            debug_state <= "START DETECTED  (3) ";

            ---------------------------------------------------------------------------------------------------------------------------------------------------------------
            ----------------------                                         SLAVE ADDR + W 
            ---------------------------------------------------------------------------------------------------------------------------------------------------------------
            

            for i in 7 downto 0 loop
                wait until rising_edge(scl);
                v_addr_byte(i) := sda;
            end loop;
            
            debug_state <= "LEYENDO_ADDR    (34)"; -- No se verá si pasa la condicion de direccion.

            if v_addr_byte(7 downto 1) = I2C_ADDR then

                debug_state <= "ADDR_OK         (34)";
                wait until falling_edge(scl);
                debug_state <= "ADDR_SACK       (36)";
                sda <= '0';
                wait until rising_edge(scl); 
                debug_state <= "SACK_READ       (38)";
                sda <= 'Z';
                wait until falling_edge(scl);
                debug_state <= "READING REG_ADDR(42)";

                ---------------------------------------------------------------------------------------------------------------------------------------------------------------
                ----------------------                                         REGISTER ADDRESS 
                ---------------------------------------------------------------------------------------------------------------------------------------------------------------
            

                for i in 7 downto 0 loop
                    wait until rising_edge(scl);
                    v_addr_byte(i) := sda;
                end loop;
                
                debug_state <= "SAVE REG_ADDR   (70)";
                v_reg_addr   := to_integer(unsigned(v_addr_byte));
                s_reg_addr <= v_reg_addr;
                v_reg_inc    := v_reg_addr;
                read_reg_addr <= v_reg_addr;
                wait until falling_edge(scl);

                debug_state <= "REG_ADDR_SACK   (72)";
                sda <= '0';
                wait until rising_edge(scl);  
                debug_state <= "SACK_READ       (74)";
                sda <= 'Z';

                wait until falling_edge(scl); 
                v_stop_seen := false;

                v_rw := '0';

                while not v_stop_seen loop

                    ---------------------------------------------------------------------------------------------------------------------------------------------------------------
                    ----------------------                                         DATA HIGH (DEFAULT WRITE OP) 
                    ---------------------------------------------------------------------------------------------------------------------------------------------------------------
            

                    debug_state <= "LEYENDO/ESCR_DATA_H ";
                    for i in 7 downto 0 loop
                        if v_rw = '0' then
                            wait until rising_edge(scl);
                            debug_state <= "DATAH CLK NUM    i=" & integer'image(i);
                            v_data_h(i) := sda;
                            wait until rising_edge(sda) or falling_edge(sda) or falling_edge(scl);
                            if scl = '1' then
                                if sda = '1' then
                                    v_stop_seen := true;
                                    debug_state <= "STOP_DETECTADO      ";
                                    exit;

                                elsif sda = '0' then
                                    v_start_seen := true;
                                    debug_state <= "START_DETECTADO     ";
                                    exit;

                                end if;
                            else
                                debug_state <= "MAS_DATOS           ";
                            end if;

                        else
                            if i /= 7 then
                                wait until falling_edge(scl);
                            end if;
                            debug_state <= "RDATAH CLK NUM   i=" & integer'image(i);
                            s_reg_addr <= v_reg_inc;
                            sda <= regs_core(v_reg_inc)(8 + i);

                            if i = 0 then
                                wait until falling_edge(scl);
                            end if;
                        end if;
                        
                        
                        
                    end loop;



                    if v_stop_seen then
                        exit;
                    end if;

                    ---------------------------------------------------------------------------------------------------------------------------------------------------------------
                    ----------------------                                         IF REPEATED START, NEXT AND READ REG_ADDR + R (READ OP) 
                    ---------------------------------------------------------------------------------------------------------------------------------------------------------------
             
                    if v_start_seen then
                        v_start_seen := false;
                        debug_state <= "READING REG_ADDR(42)";

                        for i in 7 downto 0 loop
                            wait until rising_edge(scl);
                            debug_state <= "ADDR_R CLK NUM   i=" & integer'image(i);
                            v_addr_byte(i) := sda;
                            
                            wait until rising_edge(sda) or falling_edge(sda) or falling_edge(scl);
                            
                            if scl = '1' then
                                if sda = '1' then
                                    v_stop_seen := true;
                                    debug_state <= "STOP_DETECTADO      ";
                                    exit;

                                elsif sda = '0' then
                                    v_start_seen := true;
                                    debug_state <= "START_DETECTADO     ";
                                    exit;

                                end if;
                            else
                                debug_state <= "MAS_DATOS           ";
                            end if;

                        end loop;
                        
                        

                        if v_addr_byte(0) = '1' then
                            v_rw := '1'; 
                        else
                            v_rw := '0'; --No debería pasar, porque sería mandar un Repeated START en modo write, pero lo manejamos igual por si acaso
                        end if;
                        debug_state <= "TEST PROBE          ";

                        --wait until falling_edge(scl);
                        wait for 0.4 us;
                        debug_state <= "ADDR_READ_SACK  (72)";
                        sda <= '0';
                        wait until rising_edge(scl);  
                        debug_state <= "SACK_READ       (74)";
                        sda <= 'Z';
                        wait until falling_edge(scl);
                    
                        next;   -- Aquí volvemos a empezar el loop de lectura de datos, pero con v_rw = '1' para indicar que ahora es una lectura. 
                        
                    end if;
                    
                    ---------------------------------------------------------------------------------------------------------------------------------------------------------------
                    ----------------------                                         IF NOT REPEATED START, ES DATO HIGH DE UNA ESCRITURA, CONTINUAMOS LEYENDO/ESCRIBIENDO DATA LOW
                    ---------------------------------------------------------------------------------------------------------------------------------------------------------------
                    
                    if v_rw = '0' then

                        debug_state <= "SAVE REG_V_MSB (106)";

                        debug_state <= "ACK_DATA_H          ";

                        debug_state <= "REGV_SACK      (108)";
                        sda <= '0';

                        wait until rising_edge(scl);  
                        debug_state <= "SACK_READ      (110)";
                        sda <= 'Z';
                    else
                        sda <= 'Z';
                        wait until rising_edge(scl);  
                        if sda = '0' then
                            debug_state <= "2ACK_DATA_H         ";
                        else
                            exit;
                        end if;


                    end if;
                    
                    wait until falling_edge(scl);

                    --------------------------------------------------------------------------------------------------------------------------------------------------------------
                    ----------------------                                         LEEMOS/ESCRIBIMOS DATA LOW
                    ---------------------------------------------------------------------------------------------------------------------------------------------------------------

                    debug_state <= "LEYENDO_DATA_L      ";

                    for i in 7 downto 0 loop
                        if v_rw = '0' then
                            wait until rising_edge(scl);
                            
                            v_data_l(i) := sda;
                            debug_state <= "DATAL CLK NUM    i=" & integer'image(i);

                            wait until rising_edge(sda) or falling_edge(sda) or falling_edge(scl);
                            
                            if scl = '1' then
                                if sda = '1' then
                                    v_stop_seen := true;
                                    debug_state <= "STOP_DETECTADO      ";
                                    exit;

                                elsif sda = '0' then
                                    -- SDA bajó = START
                                    v_start_seen := true;
                                    debug_state <= "START_DETECTADO     ";
                                    exit;

                                end if;
                            else
                                debug_state <= "MAS_DATOS           ";
                            end if;
                        else
                            if i /= 7 then
                                wait until falling_edge(scl);
                            end if;
                            debug_state <= "R2DATAH CLK NUM  i=" & integer'image(i);
                            sda <= regs_core(v_reg_inc)(i);
                            if i = 0 then
                                wait until falling_edge(scl);
                            end if;
                        end if;

                    end loop;
                    
                    if v_rw = '0' then

                        debug_state <= "SAVE REG_V_MSB (106)";

                        debug_state <= "ACK_DATA_H          ";

                        debug_state <= "REGV_SACK      (108)";
                        sda <= '0';

                        wait until rising_edge(scl);  
                        debug_state <= "SACK_READ      (110)";
                        sda <= 'Z';
                    else
                        sda <= 'Z';
                        debug_state <= "AAAAAAAAAAA         ";
                        wait until rising_edge(scl);  
                        if sda = '0' then
                            debug_state <= "2ACK_DATA_H         ";
                        else
                            exit;
                        end if;


                    end if;
                    

                    wait until falling_edge(scl);  -- SCL baja después de leer ACK
                    debug_state <= "               (148)";

                    v_data_16 := v_data_h & v_data_l;
                    regs_core(v_reg_inc) <= v_data_16;
                    
                    if v_reg_inc = 255 then
                        v_reg_inc := 0;
                    else
                        v_reg_inc := v_reg_inc + 1;
                    end if;

                    s_reg_addr <= v_reg_inc;
                end loop;
            end if;

        end loop; -- loop exterior

    end process i2c_slave;

end Behavioral;