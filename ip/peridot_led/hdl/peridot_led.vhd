-- ===================================================================
-- TITLE : PERIDOT-NGS / WS2812B/SK6812 Serial LED controller
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2018/10/21 -> 2018/11/24
--
--     MODITY : 2019/01/14 added EXTSEL register
--
-- ===================================================================

-- The MIT License (MIT)
-- Copyright (c) 2018-2019 J-7SYSTEM WORKS LIMITED.
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
-- reg0 status  : bit4-3:mode, bit2:done, bit1:start, bit0:ready
-- reg1 control : bit15:init, bit14:trigedge, bit13-10:extsel, bit8-0:scannum
-- reg2 scroll  : bit31-16:speed, bit8-0:vrampos
-- reg3 bright  : bit23-16:red, bit15-8:green, bit7-0:blue
--
-- MEM
-- +0000 ch0,pixel0   : bit23-18:red, bit15-10:green, bit7-2:blue 
-- +0004 ch0,pixel1   :                 〃
--   :
-- +07fc ch0,pixel511 :                 〃
-- +0800 ch1,pixel0   :                 〃
--   :
-- +7ffc ch15,pixel511:                 〃


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;


entity peridot_led is
	generic(
		LED_COLOR_TRANSOEDER	: string := "GRB";	-- LEDへ転送する色順序 "GRB"または"RGB"
		LED_CHANNEL_NUMBER		: integer := 12;	-- 1ユニットのLEDチャネル数(1～16) 
		LED_RAM_ADDRESS_WIDTH	: integer := 15;	-- VRAMのアドレス幅(11:2kバイト～15:32kバイト) 
		BIT_TOTAL_NUNBER		: integer := 63;	-- 1ビットのクロックカウント数 
		BIT_SYMBOL0_WIDTH		: integer := 18;	-- シンボル0のパルス幅(BIT_SYMBOL1_WIDTH-1以下であること) 
		BIT_SYMBOL1_WIDTH		: integer := 45;	-- シンボル1のパルス幅(BIT_TOTAL_NUNBER-4以下であること) 
		RES_COUNT_NUMBER		: integer := 28		-- リセット期間のバイトカウント数 
--		RES_COUNT_NUMBER		: integer := 2		-- TEST
	);
	port(
		csi_reset			: in  std_logic;
		csi_clk				: in  std_logic;

		-- Control/Status Register I/F

		avs_csr_address		: in  std_logic_vector(1 downto 0);		-- word address
		avs_csr_read		: in  std_logic;
		avs_csr_readdata	: out std_logic_vector(31 downto 0);
		avs_csr_write		: in  std_logic;
		avs_csr_writedata	: in  std_logic_vector(31 downto 0);

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
	signal done_sig			: std_logic;
	signal ready_sig		: std_logic;
	signal continue_reg		: std_logic;
	signal start_sig		: std_logic;
	signal exttrig_reg		: std_logic_vector(2 downto 0);
	signal exttrig_sig		: std_logic;

	signal startreq_reg		: std_logic_vector(1 downto 0);
	signal donereq_reg		: std_logic;
	signal mode_reg			: std_logic_vector(1 downto 0);
	signal init_reg			: std_logic;
	signal trigedge_reg		: std_logic;
	signal extsel_reg		: std_logic_vector(3 downto 0);
	signal scan_num_reg		: std_logic_vector(8 downto 0);
	signal offset_reg		: std_logic_vector(18 downto 0);
	signal scroll_reg		: std_logic_vector(15 downto 0);
	signal br_red_reg		: std_logic_vector(7 downto 0);
	signal br_green_reg		: std_logic_vector(7 downto 0);
	signal br_blue_reg		: std_logic_vector(7 downto 0);


	component peridot_led_control is
	generic(
		LED_COLOR_TRANSOEDER	: string;
		LED_CHANNEL_NUMBER		: integer;
		LED_RAM_ADDRESS_WIDTH	: integer;
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

		scan_num	: in  std_logic_vector(8 downto 0);
		ram_offset	: in  std_logic_vector(8 downto 0);
		br_red		: in  std_logic_vector(7 downto 0);
		br_green	: in  std_logic_vector(7 downto 0);
		br_blue		: in  std_logic_vector(7 downto 0);

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

	reset_sig <= csi_reset;
	clock_sig <= csi_clk;

	with (avs_csr_address) select avs_csr_readdata <=
		X"0000" & init_reg & trigedge_reg & extsel_reg & "0" & scan_num_reg	when "01",
		scroll_reg & "0000000" & offset_reg(18 downto 10)					when "10",
		X"00" & br_red_reg & br_green_reg & br_blue_reg						when "11",
		X"000000" & "000" & mode_reg & donereq_reg & startreq_reg(0) & ready_sig when others;


	process (clock_sig, reset_sig) begin
		if (reset_sig = '1') then
			init_reg <= '1';
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

			if (avs_csr_address = 1 and avs_csr_write = '1') then
				init_reg <= avs_csr_writedata(15);
				trigedge_reg <= avs_csr_writedata(14);
				extsel_reg <= avs_csr_writedata(13 downto 10);
				scan_num_reg <= avs_csr_writedata(8 downto 0);
			end if;

			if (avs_csr_address = 2 and avs_csr_write = '1') then
				scroll_reg <= avs_csr_writedata(31 downto 16);
				offset_reg <= avs_csr_writedata(8 downto 0) & "0000000000";
			elsif (done_sig = '1') then
				offset_reg <= offset_reg + (scroll_reg(15) & scroll_reg(15) & scroll_reg(15) & scroll_reg);
			end if;

			if (avs_csr_address = 3 and avs_csr_write = '1') then
				br_red_reg   <= avs_csr_writedata(23 downto 16);
				br_green_reg <= avs_csr_writedata(15 downto  8);
				br_blue_reg  <= avs_csr_writedata( 7 downto  0);
			end if;

		end if;
	end process;

	exttrig_sig <= '1' when((trigedge_reg = '0' and exttrig_reg(2 downto 1) = "01") or
							(trigedge_reg = '1' and exttrig_reg(2 downto 1) = "10")
						) else '0';

	start_sig <= '1' when((mode_reg(1) = '0' and startreq_reg = "01") or
							(mode_reg(1) = '1' and startreq_reg(0) = '1' and exttrig_sig = '1') or
							(continue_reg = '1')
						) else '0';

	coe_ext_sel <= extsel_reg;


	----------------------------------------------------------------------
	-- Instance of sub module
	----------------------------------------------------------------------

	u0 : peridot_led_control
	generic map(
		LED_COLOR_TRANSOEDER	=> LED_COLOR_TRANSOEDER,
		LED_CHANNEL_NUMBER		=> LED_CHANNEL_NUMBER,
		LED_RAM_ADDRESS_WIDTH	=> LED_RAM_ADDRESS_WIDTH,
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
		ram_offset	=> offset_reg(18 downto 10),
		br_red		=> br_red_reg,
		br_green	=> br_green_reg,
		br_blue		=> br_blue_reg,

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
