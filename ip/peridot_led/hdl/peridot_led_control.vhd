-- ===================================================================
-- TITLE : PERIDOT-NGS / WS2812B/SK6812 led controller (全体制御)
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2018/10/21 -> 2018/11/24
--
-- ===================================================================

-- The MIT License (MIT)
-- Copyright (c) 2018 J-7SYSTEM WORKS LIMITED.
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

library ieee;
library lpm;
library altera_mf;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_misc.all;
use lpm.lpm_components.all;
use altera_mf.altera_mf_components.all;


entity peridot_led_control is
	generic(
		LED_COLOR_TRANSOEDER	: string := "GRB";	-- LEDへ転送する色順序 
		LED_CHANNEL_NUMBER		: integer := 12;	-- 1ユニットのLEDチャネル数(1～16) 
		LED_RAM_ADDRESS_WIDTH	: integer := 15;	-- VRAMのアドレス幅(11:2kバイト～15:32kバイト) 
		BIT_TOTAL_NUNBER		: integer := 9;		-- 1ビットのクロックカウント数
		BIT_SYMBOL0_WIDTH		: integer := 2;		-- シンボル0のパルス幅(BIT_SYMBOL1_WIDTH+1以下であること) 
		BIT_SYMBOL1_WIDTH		: integer := 5;		-- シンボル1のパルス幅(BIT_TOTAL_NUNBER+4以下であること) 
		RES_COUNT_NUMBER		: integer := 3		-- リセット期間のバイトカウント数 
	);
	port(
--		test_scan_begin		: out std_logic;
--		test_led_timing		: out std_logic;
--		test_led_load		: out std_logic;
--		test_led_data		: out std_logic_vector(7 downto 0);
--		test_led_loaded		: out std_logic;
--		test_memb_address	: out std_logic_vector(8 downto 0);


		clk			: in  std_logic;
		init		: in  std_logic;
		ready		: out std_logic;

		start		: in  std_logic;
		done		: out std_logic;

		scan_num	: in  std_logic_vector(8 downto 0);
		ram_offset	: in  std_logic_vector(8 downto 0);
		br_red		: in  std_logic_vector(7 downto 0);
		br_green	: in  std_logic_vector(7 downto 0);
		br_blue		: in  std_logic_vector(7 downto 0);

		led_out		: out std_logic_vector(LED_CHANNEL_NUMBER-1 downto 0);

		-- RAM I/F

		s1_clk		: in  std_logic;
		s1_address	: in  std_logic_vector(LED_RAM_ADDRESS_WIDTH-1 downto 0);
		s1_read		: in  std_logic;
		s1_readdata	: out std_logic_vector(31 downto 0);
		s1_write	: in  std_logic;
		s1_writedata: in  std_logic_vector(31 downto 0)
	);
end peridot_led_control;

architecture RTL of peridot_led_control is
	function CSTD(NUM:integer; WID:integer) return std_logic_vector is
	begin
		return conv_std_logic_vector(NUM, WID);
	end CSTD;

	constant PIPELINE_COUNT		: integer := 3;

	type MAIN_STATE is (IDLE, SETUP1,SETUP2, CH_SYNC, CH_LOOP, CH_DONE, RES_LOOP);
	signal state	: MAIN_STATE;

	signal done_reg				: std_logic;
	signal load_req_reg			: std_logic;
	signal timing_ena_reg		: std_logic;
	signal led_drive_reg		: std_logic;
	signal ch_count_reg			: integer range 0 to LED_CHANNEL_NUMBER-1;
	signal col_sel_reg			: std_logic_vector(1 downto 0);
	signal pix_count_reg		: std_logic_vector(8 downto 0);
	signal ram_offset_reg		: std_logic_vector(8 downto 0);
	signal scan_num_reg			: std_logic_vector(8 downto 0);
	signal res_count_reg		: integer range 0 to RES_COUNT_NUMBER;

	signal timing_ena_sig		: std_logic;
	signal led_drive_sig		: std_logic;
	signal scan_begin_sig		: std_logic;
	signal scan_timing_sig		: std_logic;
	signal led_loaded_sig		: std_logic;

	signal timing_count_reg		: integer range 0 to BIT_TOTAL_NUNBER-1;
	signal bit_count_reg		: std_logic_vector(2 downto 0);


	type DEF_DATABUS is array(0 to LED_CHANNEL_NUMBER-1) of std_logic_vector(17 downto 0);
	signal mema_address_sig		: std_logic_vector(16 downto 0);
	signal mema_q_sig			: DEF_DATABUS;
	signal mema_readdata_sig	: std_logic_vector(17 downto 0);
	signal mema_write_sig		: std_logic_vector(LED_CHANNEL_NUMBER-1 downto 0);
	signal mema_data_sig		: std_logic_vector(17 downto 0);
	signal memb_address_sig		: std_logic_vector(8 downto 0);
	signal memb_q_sig			: DEF_DATABUS;


	component peridot_led_colorconv is
	generic(
		LED_COLOR_TRANSOEDER	: string
	);
	port(
		clk			: in  std_logic;
		sel			: in  std_logic_vector(1 downto 0);
		br_red		: in  std_logic_vector(7 downto 0);
		br_green	: in  std_logic_vector(7 downto 0);
		br_blue		: in  std_logic_vector(7 downto 0);
		pixel_in	: in  std_logic_vector(17 downto 0);
		data_out	: out std_logic_vector(7 downto 0)
	);
	end component;

	signal pixel_data_sig		: std_logic_vector(17 downto 0);
	signal pixel_data_reg		: std_logic_vector(17 downto 0);
	signal led_data_sig			: std_logic_vector(7 downto 0);


	component peridot_led_serializer is
	port(
		clk			: in  std_logic;
		init		: in  std_logic := '0';

		timing		: in  std_logic;
		load		: in  std_logic;
		timing_next	: out std_logic;
		load_next	: out std_logic;

		data_in		: in  std_logic_vector(7 downto 0);
		led_out		: out std_logic
	);
	end component;

	signal led_timing_sig		: std_logic_vector(LED_CHANNEL_NUMBER downto 0);
	signal led_load_sig			: std_logic_vector(LED_CHANNEL_NUMBER downto 0);

begin

	-- テスト入出力 

--	test_scan_begin <= scan_begin_sig;
--	test_led_timing <= led_timing_sig(0);
--	test_led_load <= led_load_sig(0);
--	test_led_data <= led_data_sig;
--	test_led_loaded <= led_loaded_sig;
--	test_memb_address <= memb_address_sig;


	----------------------------------------------------------------------
	-- Main control
	----------------------------------------------------------------------

	-- ステートマシン 

	process (clk) begin
		if rising_edge(clk) then
			if (init = '1') then
				state <= IDLE;
				done_reg <= '0';
				timing_ena_reg <= '0';
				led_drive_reg <= '0';
				load_req_reg <= '0';

			else
				case (state) is
				when IDLE =>
					done_reg <= '0';

					if (start = '1') then
						state <= SETUP1;
						col_sel_reg <= "00";
						pix_count_reg <= (others=>'0');
						ram_offset_reg <= ram_offset;
						scan_num_reg <= scan_num;
					end if;

				when SETUP1 =>
					state <= SETUP2;

				when SETUP2 =>
					state <= CH_SYNC;
					timing_ena_reg <= '1';
					led_drive_reg <= '1';

				when CH_SYNC =>
					if (scan_begin_sig = '1') then
						state <= CH_LOOP;
						ch_count_reg <= 0;
					end if;

				when CH_LOOP =>
					if (ch_count_reg = LED_CHANNEL_NUMBER-1) then
						state <= CH_DONE;
					else
						ch_count_reg <= ch_count_reg + 1;
					end if;

				when CH_DONE =>
					if (led_loaded_sig = '1') then
						if (col_sel_reg = "10") then
							col_sel_reg <= "00";
							pix_count_reg <= pix_count_reg + 1;
						else
							col_sel_reg <= col_sel_reg + 1;
						end if;

						if (col_sel_reg = "10" and pix_count_reg = scan_num_reg) then
							state <= RES_LOOP;
							res_count_reg <= RES_COUNT_NUMBER;
						else
							state <= CH_SYNC;
						end if;
					end if;

				when RES_LOOP =>
					if (scan_begin_sig = '1') then
						led_drive_reg <= '0';

						if (res_count_reg = 0) then
							state <= IDLE;
							done_reg <= '1';
							timing_ena_reg <= '0';
						else
							res_count_reg <= res_count_reg - 1;
						end if;
					end if;

				when others =>
				end case;


				if (state = CH_SYNC and scan_begin_sig = '1') then
					load_req_reg <= '1';
				elsif (scan_timing_sig = '1') then
					load_req_reg <= '0';
				end if;

			end if;
		end if;
	end process;

	ready <= '1' when(state = IDLE and init = '0') else '0';
	done <= done_reg;


	-- タイミング信号生成 

	timing_ena_sig <= timing_ena_reg;
	led_drive_sig <= led_drive_reg;

	process (clk) begin
		if rising_edge(clk) then
			if (timing_ena_sig = '0') then
				timing_count_reg <= 0;
				bit_count_reg <= "000";

			else
				if (timing_count_reg = BIT_TOTAL_NUNBER-1) then
					timing_count_reg <= 0;
					bit_count_reg <= bit_count_reg + 1;
				else
					timing_count_reg <= timing_count_reg + 1;
				end if;

			end if;
		end if;
	end process;

	scan_begin_sig <= timing_ena_sig when(timing_count_reg = 0 and bit_count_reg = "000") else '0';

	scan_timing_sig <= '1' when(timing_count_reg = PIPELINE_COUNT or
								timing_count_reg = PIPELINE_COUNT + BIT_SYMBOL0_WIDTH or
								timing_count_reg = PIPELINE_COUNT + BIT_SYMBOL1_WIDTH
							) else '0';

	led_timing_sig(0) <= led_drive_sig when(scan_timing_sig = '1') else '0';
	led_load_sig(0) <= load_req_reg when(scan_timing_sig = '1') else '0';

	led_loaded_sig <= led_load_sig(LED_CHANNEL_NUMBER);



	----------------------------------------------------------------------
	-- Instance of sub module
	----------------------------------------------------------------------

	-- LED VRAMインスタンス 

	mema_address_sig(16 downto LED_RAM_ADDRESS_WIDTH) <= (others=>'0');
	mema_address_sig(LED_RAM_ADDRESS_WIDTH-1 downto 0) <= s1_address;

	mema_data_sig <= s1_writedata(23 downto 18) & s1_writedata(15 downto 10) & s1_writedata(7 downto 2);

	memb_address_sig <= ram_offset_reg + pix_count_reg;

	gen_mem : for i in 0 to LED_CHANNEL_NUMBER-1 generate
		mema_write_sig(i) <= s1_write when(mema_address_sig(15 downto 11) = i) else '0';

		u_mem : altsyncram
		generic map (
			address_reg_b => "CLOCK1",
			clock_enable_input_a => "BYPASS",
			clock_enable_input_b => "BYPASS",
			clock_enable_output_a => "BYPASS",
			clock_enable_output_b => "BYPASS",
			indata_reg_b => "CLOCK1",
		--	intended_device_family => "Cyclone III",
			lpm_type => "altsyncram",
			numwords_a => 512,
			numwords_b => 512,
			operation_mode => "BIDIR_DUAL_PORT",
			outdata_aclr_a => "NONE",
			outdata_aclr_b => "NONE",
			outdata_reg_a => "CLOCK0",
			outdata_reg_b => "CLOCK1",
			power_up_uninitialized => "FALSE",
			read_during_write_mode_port_a => "OLD_DATA",
			read_during_write_mode_port_b => "OLD_DATA",
			widthad_a => 9,
			widthad_b => 9,
			width_a => 18,
			width_b => 18,
			width_byteena_a => 1,
			width_byteena_b => 1,
			wrcontrol_wraddress_reg_b => "CLOCK1"
		)
		port map (
			clock0 		=> s1_clk,
			address_a	=> s1_address(10 downto 2),
			q_a			=> mema_q_sig(i),
			data_a		=> mema_data_sig,
			wren_a		=> mema_write_sig(i),

			clock1		=> clk,
			address_b	=> memb_address_sig,
			q_b			=> memb_q_sig(i),
			data_b		=> (others=>'X'),
			wren_b		=> '0'
		);
	end generate;

	mema_readdata_sig <= mema_q_sig(conv_integer(mema_address_sig(15 downto 11)));

	s1_readdata <= X"00" &
			mema_readdata_sig(17 downto 12) & "00" &
			mema_readdata_sig(11 downto  6) & "00" &
			mema_readdata_sig( 5 downto  0) & "00";

	pixel_data_sig <= memb_q_sig(ch_count_reg);

	process (clk) begin
		if rising_edge(clk) then
			pixel_data_reg <= pixel_data_sig;
		end if;
	end process;


	-- ピクセルγ・輝度変換インスタンス 

	u_conv : peridot_led_colorconv
	generic map(
		LED_COLOR_TRANSOEDER	=> LED_COLOR_TRANSOEDER
	)
	port map(
		clk			=> clk,

		sel			=> col_sel_reg,
		br_red		=> br_red,
		br_green	=> br_green,
		br_blue		=> br_blue,

		pixel_in	=> pixel_data_reg,
		data_out	=> led_data_sig
	);


	-- LEDシリアライザインスタンス 

	gen_led : for i in 0 to LED_CHANNEL_NUMBER-1 generate
		u_led : peridot_led_serializer
		port map(
			clk			=> clk,
			init		=> init,

			timing		=> led_timing_sig(i),
			load		=> led_load_sig(i),
			timing_next	=> led_timing_sig(i+1),
			load_next	=> led_load_sig(i+1),

			data_in		=> led_data_sig,
			led_out		=> led_out(i)
		);
	end generate;



end RTL;
