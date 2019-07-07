-- ===================================================================
-- TITLE : PERIDOT-NGS / WS2812B/SK6812 led memory
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2019/06/01 -> 2019/06/03
--
-- ===================================================================

-- The MIT License (MIT)
-- Copyright (c) 2019 J-7SYSTEM WORKS LIMITED.
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


-- ・レイヤ合成を行うとき (USE_LAYER_BLEND="ON") 
-- 　　１チャネルのメモリの前半をBASE,後半をLAYERに割り当てる 
-- 　　CPU I/Fから見たとき、VRAM領域の前半にCH0～CHnのBASE領域、後半にCH0～CHnのLAYER領域が並ぶ 
-- 　　LED_PIXELNUM_WIDTH には VRAM_CHUNKWORD_WIDTH-1 を指定しなければならない 
--
-- ・レイヤ合成を行わないとき (USE_LAYER_BLEND="OFF")
-- 　　１チャネルのメモリの全てをBASEに割り当てる 
-- 　　CPU I/Fから見たとき、VRAM領域はCH0～CHnのBASE領域のみが並ぶ 
-- 　　LED_PIXELNUM_WIDTH には VRAM_CHUNKWORD_WIDTH を指定しなければならない 
--
-- ・ピクセルリクエスト
-- 　　read_req は１クロック幅のアサートでなければならない
-- 　　read_req のアサートとその次のクロックは base_address,layer_address,channel_num を変化させてはならない
-- 　　結果は valid のアサートで示される


library ieee;
library altera_mf;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use altera_mf.altera_mf_components.all;

entity peridot_led_vram is
	generic(
		LED_CHANNEL_NUMBER		: integer := 12;	-- 1ユニットのLEDチャネル数(1～16) 
		LED_PIXELNUM_WIDTH		: integer := 8;		-- 1チャネル分のピクセルワードアドレス幅(8:256～12:4096)
		VRAM_CHUNKWORD_WIDTH	: integer := 9;		-- 1チャネル分のVRAMアドレス幅(9:512ワード～12:4096ワード) 
		VRAM_ADDRESS_WIDTH		: integer := 15;	-- VRAMのアドレス幅(11:2kバイト～18:256kバイト) 
		USE_LAYER_BLEND			: string := "ON"	-- レイヤ合成を行う 
--		USE_LAYER_BLEND			: string := "OFF"	-- レイヤ合成を行わない(layer_～のポートは無視) 
	);
	port(
		test_chnum		: out std_logic_vector(3 downto 0);
		test_pixel		: out std_logic_vector(17 downto 0);
		test_mema_channel	: out std_logic_vector(3 downto 0);
		test_mema_chunkaddr	: out std_logic_vector(VRAM_CHUNKWORD_WIDTH-1 downto 0);
		test_memb_chunkaddr	: out std_logic_vector(VRAM_CHUNKWORD_WIDTH-1 downto 0);


		-- Pixel data read port
		clk				: in  std_logic;

		read_req		: in  std_logic;
		channel_num		: in  std_logic_vector(3 downto 0);
		base_address	: in  std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
		layer_address	: in  std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0) := (others=>'X');

		valid			: out std_logic;
		base_pixel		: out std_logic_vector(17 downto 0);
		layer_pixel		: out std_logic_vector(17 downto 0);

		-- CPU interface port
		s1_clk			: in  std_logic;

		s1_address		: in  std_logic_vector(VRAM_ADDRESS_WIDTH-1 downto 0);
		s1_read			: in  std_logic;
		s1_readdata		: out std_logic_vector(31 downto 0);
		s1_write		: in  std_logic;
		s1_writedata	: in  std_logic_vector(31 downto 0)
	);
end peridot_led_vram;

architecture RTL of peridot_led_vram is
	function CSTD(NUM:integer; WID:integer) return std_logic_vector is
	begin
		return conv_std_logic_vector(NUM, WID);
	end CSTD;

	constant MEM_NUMWORDS	: integer := 2**VRAM_CHUNKWORD_WIDTH;

	signal valid_delay_reg		: std_logic_vector(3 downto 0) := (others=>'0');
	signal chnum_delay_reg		: std_logic_vector(2*4-1 downto 0);
	signal chnum_sig			: std_logic_vector(3 downto 0);
	signal pixel_data_sig		: std_logic_vector(17 downto 0);
	signal base_pixel_reg		: std_logic_vector(17 downto 0);
	signal layer_pixel_reg		: std_logic_vector(17 downto 0);

	type DEF_DATABUS is array(0 to LED_CHANNEL_NUMBER-1) of std_logic_vector(17 downto 0);
	signal mema_channel_sig		: std_logic_vector(VRAM_ADDRESS_WIDTH-VRAM_CHUNKWORD_WIDTH-3 downto 0);
	signal mema_address_sig		: std_logic_vector(18 downto 0);
	signal mema_chunkaddr_sig	: std_logic_vector(VRAM_CHUNKWORD_WIDTH-1 downto 0);
	signal mema_q_sig			: DEF_DATABUS;
	signal mema_readdata_sig	: std_logic_vector(17 downto 0);
	signal mema_write_sig		: std_logic_vector(LED_CHANNEL_NUMBER-1 downto 0);
	signal mema_data_sig		: std_logic_vector(17 downto 0);
	signal memb_chunkaddr_sig	: std_logic_vector(VRAM_CHUNKWORD_WIDTH-1 downto 0);
	signal memb_q_sig			: DEF_DATABUS;

begin

	-- テスト入出力 

	test_chnum <= chnum_sig;
	test_pixel <= pixel_data_sig;
	test_mema_channel <= CSTD(conv_integer(mema_channel_sig) ,4);
	test_mema_chunkaddr <= mema_chunkaddr_sig;
	test_memb_chunkaddr <= memb_chunkaddr_sig;


	----------------------------
	-- アドレスと読み出し制御 --
	----------------------------

	-- アドレス範囲をチェック 
	assert (LED_CHANNEL_NUMBER <= 2**mema_channel_sig'length)
		report "vram address width mismatch!";

	process (clk) begin
		if rising_edge(clk) then
			valid_delay_reg <= valid_delay_reg(valid_delay_reg'left-1 downto 0) & read_req;
			chnum_delay_reg <= chnum_delay_reg(chnum_delay_reg'left-4 downto 0) & channel_num;

			if (valid_delay_reg(1) = '1') then
				layer_pixel_reg <= pixel_data_sig;
			end if;
			if (valid_delay_reg(2) = '1') then
				base_pixel_reg <= pixel_data_sig;
			end if;
		end if;
	end process;

	chnum_sig <= chnum_delay_reg(2*4-1 downto 2*4-4);

	valid <= valid_delay_reg(3);
	base_pixel <= base_pixel_reg;
	layer_pixel <= layer_pixel_reg;


	--------------------------
	-- LED VRAMインスタンス --
	--------------------------

	mema_address_sig(18 downto VRAM_ADDRESS_WIDTH) <= (others=>'0');
	mema_address_sig(VRAM_ADDRESS_WIDTH-1 downto 0) <= s1_address;

	mema_data_sig <= s1_writedata(23 downto 18) & s1_writedata(15 downto 10) & s1_writedata(7 downto 2);

	use_blend : if (USE_LAYER_BLEND = "ON") generate
		mema_channel_sig <= mema_address_sig(VRAM_ADDRESS_WIDTH-2 downto VRAM_CHUNKWORD_WIDTH+1);
		mema_chunkaddr_sig <= mema_address_sig(VRAM_ADDRESS_WIDTH-1) & mema_address_sig(VRAM_CHUNKWORD_WIDTH downto 2);

		memb_chunkaddr_sig <= '1' & layer_address when(read_req = '1') else '0' & base_address;
	end generate;
	no_blend : if (USE_LAYER_BLEND /= "ON") generate
		mema_channel_sig <= mema_address_sig(VRAM_ADDRESS_WIDTH-1 downto VRAM_CHUNKWORD_WIDTH+2);
		mema_chunkaddr_sig <= mema_address_sig(VRAM_CHUNKWORD_WIDTH+1 downto 2);

		memb_chunkaddr_sig <= base_address;
	end generate;

	gen_mem : for i in 0 to LED_CHANNEL_NUMBER-1 generate
		mema_write_sig(i) <= s1_write when(mema_channel_sig = i) else '0';

		u_mem : altsyncram
		generic map (
			lpm_type => "altsyncram",
			operation_mode => "BIDIR_DUAL_PORT",
		--	intended_device_family => "Cyclone III",
			address_reg_b => "CLOCK1",
			clock_enable_input_a => "BYPASS",
			clock_enable_input_b => "BYPASS",
			clock_enable_output_a => "BYPASS",
			clock_enable_output_b => "BYPASS",
			indata_reg_b => "CLOCK1",
			numwords_a => MEM_NUMWORDS,
			numwords_b => MEM_NUMWORDS,
			outdata_aclr_a => "NONE",
			outdata_aclr_b => "NONE",
			outdata_reg_a => "CLOCK0",
			outdata_reg_b => "CLOCK1",
			power_up_uninitialized => "FALSE",
			read_during_write_mode_port_a => "OLD_DATA",
			read_during_write_mode_port_b => "OLD_DATA",
			widthad_a => VRAM_CHUNKWORD_WIDTH,
			widthad_b => VRAM_CHUNKWORD_WIDTH,
			width_a => 18,
			width_b => 18,
			width_byteena_a => 1,
			width_byteena_b => 1,
			wrcontrol_wraddress_reg_b => "CLOCK1"
		)
		port map (
			clock0 		=> s1_clk,
			address_a	=> mema_chunkaddr_sig,
			q_a			=> mema_q_sig(i),
			data_a		=> mema_data_sig,
			wren_a		=> mema_write_sig(i),

			clock1		=> clk,
			address_b	=> memb_chunkaddr_sig,
			q_b			=> memb_q_sig(i),
			data_b		=> (others=>'X'),
			wren_b		=> '0'
		);
	end generate;

	mema_readdata_sig <= mema_q_sig(conv_integer(mema_channel_sig));

	s1_readdata <= X"00" &
			mema_readdata_sig(17 downto 12) & "00" &
			mema_readdata_sig(11 downto  6) & "00" &
			mema_readdata_sig( 5 downto  0) & "00";

	pixel_data_sig <= memb_q_sig(conv_integer(chnum_sig));



end RTL;
