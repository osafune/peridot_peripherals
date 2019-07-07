-- ===================================================================
-- TITLE : PERIDOT-NGS / WS2812B/SK6812 Serial LED controller
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2018/10/21 -> 2018/11/24
--
--     MODITY : 2019/06/12 s.osafune@j7system.jp
--
-- ===================================================================

-- The MIT License (MIT)
-- Copyright (c) 2018,2019 J-7SYSTEM WORKS LIMITED.
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


-- [USAGE]
--
-- CSR
-- reg00 status  : bit4-3:mode, bit2:done, bit1:start, bit0:ready
-- reg01 control : bit21:irqena, bit20:trigedge, bit19-16:extsel, bit15:init, bit11-0:scannum
-- reg02 scroll  : bit31-16:speed, bit11-0:vrampos
-- reg03 bright  : bit23-16:red, bit15-8:green, bit7-0:blue
-- reg04 scroll2 : bit31-16:speed, bit11-0:ovlayerpos
-- reg05 alpha   : bit25-24:blmode, bit23-16:ovred, bit15-8:ovgreen, bit7-0:ovblue
-- reg06 seed    : bit31-0:effect seed
-- reg07 fluct   : bit26:freerun, bit25-24:flmode, bit23-16:flred, bit15-8:flgreen, bit7-0:flblue
--
-- MEM (ex.LED_PIXELNUM_WIDTH=8 and USE_LAYER_BLEND="ON")
-- +0000 ch0,pixel0   : bit23-18:red, bit15-10:green, bit7-2:blue (base)
-- +0004 ch0,pixel1   :                 〃
--   :
-- +03fc ch0,pixel255 :                 〃
-- +0400 ch1,pixel0   :                 〃
--   :
-- +3ffc ch15,pixel255:                 〃
-- +4000 ch0,pixel0   : bit23-18:red, bit15-10:green, bit7-2:blue (layer)
-- +4004 ch0,pixel1   :                 〃
--   :
-- +43fc ch0,pixel255 :                 〃
-- +4400 ch1,pixel0   :                 〃
--   :
-- +7ffc ch15,pixel255:                 〃


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity peridot_led is
	generic(
		LED_COLOR_TRANSORDER	: string := "GRB";	-- LEDへ転送する色順序 "GRB"または"RGB"
		LED_CHANNEL_NUMBER		: integer := 12;	-- 1ユニットのLEDチャネル数(1～16) 
		LED_PIXELNUM_WIDTH		: integer := 8;		-- 1チャネル分のピクセルワードアドレス幅(8:256個～12:4096個)
		LED_RAM_ADDRESS_WIDTH	: integer := 15;	-- VRAMのアドレス幅(11:2kバイト～18:256kバイト) 
		USE_LAYER_BLEND			: string := "ON";	-- レイヤ合成の有無 "ON"または"OFF" 
		USE_FLUCTUATOR_EFFECT	: string := "ON";	-- レイヤ輝度のゆらぎ効果の有無 "ON"または"OFF"
		BIT_TOTAL_NUNBER		: integer := 63;	-- 1ビットのクロックカウント数 
		BIT_SYMBOL0_WIDTH		: integer := 18;	-- シンボル0のパルス幅(BIT_SYMBOL1_WIDTH-1以下であること) 
		BIT_SYMBOL1_WIDTH		: integer := 45;	-- シンボル1のパルス幅(BIT_TOTAL_NUNBER-8以下であること) 
--		RES_COUNT_NUMBER		: integer := 28		-- リセット期間のバイトカウント数 
		RES_COUNT_NUMBER		: integer := 2		-- リセット期間のバイトカウント数 
	);
	port(
		csi_reset			: in  std_logic;
		csi_clk				: in  std_logic;

		-- Control/Status Register I/F

		avs_csr_address		: in  std_logic_vector(2 downto 0);		-- word address
		avs_csr_read		: in  std_logic;
		avs_csr_readdata	: out std_logic_vector(31 downto 0);
		avs_csr_write		: in  std_logic;
		avs_csr_writedata	: in  std_logic_vector(31 downto 0);

		ins_csr_irq			: out std_logic;

		-- Pixel Memory I/F

		avs_mem_address		: in  std_logic_vector(LED_RAM_ADDRESS_WIDTH-1 downto 0);	-- byte address
		avs_mem_read		: in  std_logic;						-- 3clock read (2clock latency)
		avs_mem_readdata	: out std_logic_vector(31 downto 0);
		avs_mem_write		: in  std_logic;						-- 2clock setup / 1clock write
		avs_mem_writedata	: in  std_logic_vector(31 downto 0);
		avs_mem_byteenable	: in  std_logic_vector(3 downto 0);

		-- External I/F

		coe_ext_trig		: in  std_logic;
		coe_ext_sel			: out std_logic_vector(3 downto 0);
		coe_led				: out std_logic_vector(LED_CHANNEL_NUMBER-1 downto 0)
	);
end peridot_led;

architecture RTL of peridot_led is
	signal reset_sig		: std_logic;
	signal clock_sig		: std_logic;

	signal readreg00_sig	: std_logic_vector(31 downto 0);
	signal readreg01_sig	: std_logic_vector(31 downto 0);
	signal readreg02_sig	: std_logic_vector(31 downto 0);
	signal readreg03_sig	: std_logic_vector(31 downto 0);
	signal readreg04_sig	: std_logic_vector(31 downto 0);
	signal readreg05_sig	: std_logic_vector(31 downto 0);
	signal readreg06_sig	: std_logic_vector(31 downto 0);
	signal readreg07_sig	: std_logic_vector(31 downto 0);

	signal done_sig			: std_logic;
	signal ready_sig		: std_logic;
	signal continue_reg		: std_logic;
	signal start_sig		: std_logic;
	signal exttrig_reg		: std_logic_vector(2 downto 0);
	signal exttrig_sig		: std_logic;

	signal startreq_reg		: std_logic_vector(1 downto 0);
	signal donereq_reg		: std_logic;
	signal mode_reg			: std_logic_vector(1 downto 0);
	signal irqena_reg		: std_logic := '0';
	signal init_reg			: std_logic := '1';
	signal trigedge_reg		: std_logic;
	signal extsel_reg		: std_logic_vector(3 downto 0);
	signal scan_num_reg		: std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
	signal offset_reg		: std_logic_vector(LED_PIXELNUM_WIDTH+9 downto 0);
	signal scroll_reg		: std_logic_vector(15 downto 0);
	signal br_red_reg		: std_logic_vector(7 downto 0);
	signal br_green_reg		: std_logic_vector(7 downto 0);
	signal br_blue_reg		: std_logic_vector(7 downto 0);
	signal ov_offset_reg	: std_logic_vector(LED_PIXELNUM_WIDTH+9 downto 0) := (others=>'0');
	signal ov_scroll_reg	: std_logic_vector(15 downto 0);
	signal ov_mode_reg		: std_logic_vector(1 downto 0) := (others=>'0');
	signal ov_red_reg		: std_logic_vector(7 downto 0) := (others=>'0');
	signal ov_green_reg		: std_logic_vector(7 downto 0) := (others=>'0');
	signal ov_blue_reg		: std_logic_vector(7 downto 0) := (others=>'0');
	signal fl_seed_reg		: std_logic_vector(31 downto 0) := (others=>'X');
	signal fl_freerun_reg	: std_logic := '0';
	signal fl_mode_reg		: std_logic_vector(1 downto 0) := (others=>'0');
	signal fl_red_reg		: std_logic_vector(7 downto 0) := (others=>'0');
	signal fl_green_reg		: std_logic_vector(7 downto 0) := (others=>'0');
	signal fl_blue_reg		: std_logic_vector(7 downto 0) := (others=>'0');

	signal scroll_sig		: std_logic_vector(offset_reg'left downto 0);
	signal ov_scroll_sig	: std_logic_vector(ov_offset_reg'left downto 0);


	component peridot_led_control is
	generic(
		LED_COLOR_TRANSORDER	: string;
		LED_CHANNEL_NUMBER		: integer;
		LED_PIXELNUM_WIDTH		: integer;
		VRAM_ADDRESS_WIDTH		: integer;
		USE_LAYER_BLEND			: string;
		USE_FLUCTUATOR_EFFECT	: string;
		BIT_TOTAL_NUNBER		: integer;
		BIT_SYMBOL0_WIDTH		: integer;
		BIT_SYMBOL1_WIDTH		: integer;
		RES_COUNT_NUMBER		: integer
	);
	port(
		clk			: in  std_logic;
		init		: in  std_logic;
		ready		: out std_logic;

		start		: in  std_logic;
		done		: out std_logic;
		scan_num	: in  std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);

		base_offset	: in  std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
		br_red		: in  std_logic_vector(7 downto 0);
		br_green	: in  std_logic_vector(7 downto 0);
		br_blue		: in  std_logic_vector(7 downto 0);

		ov_mode		: in  std_logic_vector(1 downto 0);
		ov_offset	: in  std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
		ov_red		: in  std_logic_vector(7 downto 0);
		ov_green	: in  std_logic_vector(7 downto 0);
		ov_blue		: in  std_logic_vector(7 downto 0);

		fl_freerun	: in  std_logic;
		fl_mode		: in  std_logic_vector(1 downto 0);
		fl_seed		: in  std_logic_vector(31 downto 0);
		fl_red		: in  std_logic_vector(7 downto 0);
		fl_green	: in  std_logic_vector(7 downto 0);
		fl_blue		: in  std_logic_vector(7 downto 0);

		led_out		: out std_logic_vector(LED_CHANNEL_NUMBER-1 downto 0);

		s1_clk		: in  std_logic;
		s1_address	: in  std_logic_vector(LED_RAM_ADDRESS_WIDTH-1 downto 0);
		s1_read		: in  std_logic;
		s1_readdata	: out std_logic_vector(31 downto 0);
		s1_write	: in  std_logic;
		s1_writedata: in  std_logic_vector(31 downto 0)
	);
	end component;

	signal readdata_sig		: std_logic_vector(31 downto 0);
	signal writedata_sig	: std_logic_vector(31 downto 0);

begin

	----------------------------------------------------------------------
	-- Register Read/Write
	----------------------------------------------------------------------

	-- クロックとリセット 

	reset_sig <= csi_reset;
	clock_sig <= csi_clk;


	-- レジスタ読み出し 

	readreg00_sig(31 downto 5) <= (others=>'0');
	readreg00_sig(4 downto 3) <= mode_reg;
	readreg00_sig(2) <= donereq_reg;
	readreg00_sig(1) <= startreq_reg(0);
	readreg00_sig(0) <= ready_sig;

	readreg01_sig(31 downto 22) <= (others=>'0');
	readreg01_sig(21) <= irqena_reg;
	readreg01_sig(20) <= trigedge_reg;
	readreg01_sig(19 downto 16) <= extsel_reg;
	readreg01_sig(15) <= init_reg;
	readreg01_sig(14 downto LED_PIXELNUM_WIDTH) <= (others=>'0');
	readreg01_sig(LED_PIXELNUM_WIDTH-1 downto 0) <= scan_num_reg;

	readreg02_sig(31 downto 16) <= scroll_reg;
	readreg02_sig(15 downto LED_PIXELNUM_WIDTH) <= (others=>'0');
	readreg02_sig(LED_PIXELNUM_WIDTH-1 downto 0) <= offset_reg(offset_reg'left downto 10);

	scroll_sig(scroll_sig'left downto 16) <= (others=>scroll_reg(15));
	scroll_sig(15 downto 0) <= scroll_reg;

	readreg03_sig(31 downto 24) <= (others=>'0');
	readreg03_sig(23 downto 16) <= br_red_reg;
	readreg03_sig(15 downto  8) <= br_green_reg;
	readreg03_sig( 7 downto  0) <= br_blue_reg;

	use_blend : if (USE_LAYER_BLEND = "ON") generate
		readreg04_sig(31 downto 16) <= ov_scroll_reg;
		readreg04_sig(15 downto LED_PIXELNUM_WIDTH) <= (others=>'0');
		readreg04_sig(LED_PIXELNUM_WIDTH-1 downto 0) <= ov_offset_reg(ov_offset_reg'left downto 10);

		ov_scroll_sig(ov_scroll_sig'left downto 16) <= (others=>ov_scroll_reg(15));
		ov_scroll_sig(15 downto 0) <= ov_scroll_reg;

		readreg05_sig(31 downto 26) <= (others=>'0');
		readreg05_sig(25 downto 24) <= ov_mode_reg;
		readreg05_sig(23 downto 16) <= ov_red_reg;
		readreg05_sig(15 downto  8) <= ov_green_reg;
		readreg05_sig( 7 downto  0) <= ov_blue_reg;

		use_fluct : if (USE_FLUCTUATOR_EFFECT = "ON") generate
			readreg06_sig <= fl_seed_reg;

			readreg07_sig(31 downto 27) <= (others=>'0');
			readreg07_sig(26) <= fl_freerun_reg;
			readreg07_sig(25 downto 24) <= fl_mode_reg;
			readreg07_sig(23 downto 16) <= fl_red_reg;
			readreg07_sig(15 downto  8) <= fl_green_reg;
			readreg07_sig( 7 downto  0) <= fl_blue_reg;
		end generate;
		no_fluct : if (USE_FLUCTUATOR_EFFECT /= "ON") generate
			readreg06_sig <= (others=>'X');
			readreg07_sig <= (others=>'X');
		end generate;

	end generate;
	no_blend : if (USE_LAYER_BLEND /= "ON") generate
		readreg04_sig <= (others=>'X');
		readreg05_sig <= (others=>'X');
		readreg06_sig <= (others=>'X');
		readreg07_sig <= (others=>'X');
	end generate;

	with (avs_csr_address) select avs_csr_readdata <=
		readreg00_sig	when "000",
		readreg01_sig	when "001",
		readreg02_sig	when "010",
		readreg03_sig	when "011",
		readreg04_sig	when "100",
		readreg05_sig	when "101",
		readreg06_sig	when "110",
		readreg07_sig	when "111",
		(others=>'X')	when others;


	-- レジスタ書き込み

	process (clock_sig, reset_sig) begin
		if (reset_sig = '1') then
			init_reg <= '1';
			irqena_reg <= '0';
			continue_reg <= '0';
			startreq_reg <= "00";
			exttrig_reg <= "000";
			donereq_reg <= '0';

		elsif rising_edge(clock_sig) then
			startreq_reg(1) <= startreq_reg(0);
			exttrig_reg <= exttrig_reg(1 downto 0) & coe_ext_trig;

			if (mode_reg = "00" and startreq_reg(0) = '1') then
				continue_reg <= done_sig;
			else
				continue_reg <= '0';
			end if;


			-- reg00 : ステータスレジスタ 
			if (init_reg = '1') then
				startreq_reg(0) <= '0';
			elsif (avs_csr_address = 0 and avs_csr_write = '1') then
				startreq_reg(0) <= avs_csr_writedata(1);
			elsif (done_sig = '1' and mode_reg = "01") then
				startreq_reg(0) <= '0';
			end if;

			if (init_reg = '1') then
				donereq_reg <= '0';
			elsif (avs_csr_address = 0 and avs_csr_write = '1' and avs_csr_writedata(2) = '0') then
				donereq_reg <= '0';
			elsif (done_sig = '1') then
				donereq_reg <= '1';
			end if;

			if (avs_csr_address = 0 and avs_csr_write = '1' and ready_sig = '1') then
				mode_reg <= avs_csr_writedata(4 downto 3);
			end if;

			-- reg01 : コントロールレジスタ 
			if (avs_csr_address = 1 and avs_csr_write = '1') then
				irqena_reg <= avs_csr_writedata(21);
				trigedge_reg <= avs_csr_writedata(20);
				extsel_reg <= avs_csr_writedata(19 downto 16);
				init_reg <= avs_csr_writedata(15);
				scan_num_reg <= avs_csr_writedata(LED_PIXELNUM_WIDTH-1 downto 0);
			end if;

			-- reg02 : スクロールレジスタ(base)
			if (avs_csr_address = 2 and avs_csr_write = '1') then
				scroll_reg <= avs_csr_writedata(31 downto 16);
				offset_reg <= avs_csr_writedata(LED_PIXELNUM_WIDTH-1 downto 0) & "0000000000";
			elsif (done_sig = '1') then
				offset_reg <= offset_reg + scroll_sig;
			end if;

			-- reg03 : 輝度レジスタ(base)
			if (avs_csr_address = 3 and avs_csr_write = '1') then
				br_red_reg   <= avs_csr_writedata(23 downto 16);
				br_green_reg <= avs_csr_writedata(15 downto  8);
				br_blue_reg  <= avs_csr_writedata( 7 downto  0);
			end if;

			if (USE_LAYER_BLEND = "ON") then
				-- reg04 : スクロールレジスタ(layer)
				if (avs_csr_address = 4 and avs_csr_write = '1') then
					ov_scroll_reg <= avs_csr_writedata(31 downto 16);
					ov_offset_reg <= avs_csr_writedata(LED_PIXELNUM_WIDTH-1 downto 0) & "0000000000";
				elsif (done_sig = '1') then
					ov_offset_reg <= ov_offset_reg + ov_scroll_sig;
				end if;

				-- reg05 : 合成モード・αレジスタ(layer)
				if (avs_csr_address = 5 and avs_csr_write = '1') then
					ov_mode_reg  <= avs_csr_writedata(25 downto 24);
					ov_red_reg   <= avs_csr_writedata(23 downto 16);
					ov_green_reg <= avs_csr_writedata(15 downto  8);
					ov_blue_reg  <= avs_csr_writedata( 7 downto  0);
				end if;
			end if;

			if (USE_LAYER_BLEND = "ON" and USE_FLUCTUATOR_EFFECT = "ON") then
				-- reg06 : レイヤーゆらぎ効果シードレジスタ
				if (avs_csr_address = 6 and avs_csr_write = '1') then
					fl_seed_reg <= avs_csr_writedata;
				end if;

				-- reg07 : レイヤーゆらぎ効果モード・ゲインレジスタ
				if (avs_csr_address = 7 and avs_csr_write = '1') then
					fl_freerun_reg <= avs_csr_writedata(26);
					fl_mode_reg  <= avs_csr_writedata(25 downto 24);
					fl_red_reg   <= avs_csr_writedata(23 downto 16);
					fl_green_reg <= avs_csr_writedata(15 downto  8);
					fl_blue_reg  <= avs_csr_writedata( 7 downto  0);
				end if;
			end if;

		end if;
	end process;


	-- 割り込み信号と外部トリガ入力 

	ins_csr_irq <= donereq_reg when(irqena_reg = '1') else '0';

	exttrig_sig <= '1' when((trigedge_reg = '0' and exttrig_reg(2 downto 1) = "01") or
							(trigedge_reg = '1' and exttrig_reg(2 downto 1) = "10")
						) else '0';

	coe_ext_sel <= extsel_reg;


	-- 制御信号 

	start_sig <= '1' when((mode_reg(1) = '0' and startreq_reg = "01") or
							(mode_reg(1) = '1' and startreq_reg(0) = '1' and exttrig_sig = '1') or
							(continue_reg = '1')
						) else '0';



	----------------------------------------------------------------------
	-- Instance of sub module
	----------------------------------------------------------------------

	u0 : peridot_led_control
	generic map(
		LED_COLOR_TRANSORDER	=> LED_COLOR_TRANSORDER,
		LED_CHANNEL_NUMBER		=> LED_CHANNEL_NUMBER,
		LED_PIXELNUM_WIDTH		=> LED_PIXELNUM_WIDTH,
		VRAM_ADDRESS_WIDTH		=> LED_RAM_ADDRESS_WIDTH,
		USE_LAYER_BLEND			=> USE_LAYER_BLEND,
		USE_FLUCTUATOR_EFFECT	=> USE_FLUCTUATOR_EFFECT,
		BIT_TOTAL_NUNBER		=> BIT_TOTAL_NUNBER,
		BIT_SYMBOL0_WIDTH		=> BIT_SYMBOL0_WIDTH,
		BIT_SYMBOL1_WIDTH		=> BIT_SYMBOL1_WIDTH,
		RES_COUNT_NUMBER		=> RES_COUNT_NUMBER
	)
	port map(
		clk			=> clock_sig,
		init		=> init_reg,
		ready		=> ready_sig,

		start		=> start_sig,
		done		=> done_sig,
		scan_num	=> scan_num_reg,

		base_offset => offset_reg(offset_reg'left downto 10),
		br_red		=> br_red_reg,
		br_green	=> br_green_reg,
		br_blue		=> br_blue_reg,

		ov_mode		=> ov_mode_reg,
		ov_offset	=> ov_offset_reg(ov_offset_reg'left downto 10),
		ov_red		=> ov_red_reg,
		ov_green	=> ov_green_reg,
		ov_blue		=> ov_blue_reg,

		fl_freerun	=> fl_freerun_reg,
		fl_mode		=> fl_mode_reg,
		fl_seed		=> fl_seed_reg,
		fl_red		=> fl_red_reg,
		fl_green	=> fl_green_reg,
		fl_blue		=> fl_blue_reg,

		led_out		=> coe_led,

		s1_clk		=> clock_sig,
		s1_address	=> avs_mem_address,
		s1_read		=> avs_mem_read,
		s1_readdata	=> readdata_sig,
		s1_write	=> avs_mem_write,
		s1_writedata=> writedata_sig
	);

	-- Read modified write control

	avs_mem_readdata <= readdata_sig;

	writedata_sig(31 downto 24) <= avs_mem_writedata(31 downto 24) when(avs_mem_byteenable(3) = '1') else readdata_sig(31 downto 24);
	writedata_sig(23 downto 16) <= avs_mem_writedata(23 downto 16) when(avs_mem_byteenable(2) = '1') else readdata_sig(23 downto 16);
	writedata_sig(15 downto  8) <= avs_mem_writedata(15 downto  8) when(avs_mem_byteenable(1) = '1') else readdata_sig(15 downto  8);
	writedata_sig( 7 downto  0) <= avs_mem_writedata( 7 downto  0) when(avs_mem_byteenable(0) = '1') else readdata_sig( 7 downto  0);



end RTL;
