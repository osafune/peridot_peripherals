-- ===================================================================
-- TITLE : PERIDOT peripherals / Avalon-MM burst read
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2023/01/01 -> 2023/01/02
--            : 2023/01/xx (FIXED)
--
-- ===================================================================
--
-- The MIT License (MIT)
-- Copyright (c) 2023 J-7SYSTEM WORKS LIMITED.
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
--

-- VHDL 1993 / IEEE 1076-1993
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity peridot_vga_avm is
	generic (
		PIXEL_COLORORDER	: string := "RGB565";		-- "RGB565"   : RGB565 16bit/pixel
														-- "RGB555"   : RGB555 15bit/pixel
														-- "YUV422"   : YUV422 16bit/word
		PIXEL_DATAORDER		: string := "BYTE";			-- "BYTE"     : バイト順(リトルエンディアン) 
														-- "WORD"     : ワード順(16bitビッグエンディアン) 
		LINEOFFSETBYTES		: integer := 1024*2;		-- メモリ上の1ライン分のデータバイト数 
		BURSTLENGTH_WIDTH	: integer := 9;				-- バースト長指示幅 (log2(H_ACTIVE/2)を表現できる幅) 
		BURSTCYCLE			: integer := 640/2;
		CYCLENUMBER			: integer := 480
	);
	port (
	--==== Avalon-MM Host信号線 ====================================
		csi_m1_reset		: in  std_logic;
		csi_m1_clk			: in  std_logic;

		avm_m1_address		: out std_logic_vector(31 downto 0);
		avm_m1_burstcount	: out std_logic_vector(BURSTLENGTH_WIDTH downto 0);
		avm_m1_waitrequest	: in  std_logic;
		avm_m1_read			: out std_logic;
		avm_m1_readdata		: in  std_logic_vector(31 downto 0);
		avm_m1_readdatavalid: in  std_logic;

	--==== 外部信号 ================================================
		framebuff_addr		: in  std_logic_vector(31 downto 0);	-- async input
		framestart			: in  std_logic;						-- async input
		linestart			: in  std_logic;						-- async input
		ready				: out std_logic;

		video_clk			: in  std_logic;
		video_pixelrequest	: in  std_logic;
		video_rout			: out std_logic_vector(7 downto 0);		-- RGBは3クロック, YUVは5クロック遅延 
		video_gout			: out std_logic_vector(7 downto 0);
		video_bout			: out std_logic_vector(7 downto 0)
	);
end peridot_vga_avm;

architecture RTL of peridot_vga_avm is
	-- Misc function
	function is_true(S:std_logic) return boolean is begin return(S='1'); end;
	function is_false(S:std_logic) return boolean is begin return(S='0'); end;
	function to_vector(N,W:integer) return std_logic_vector is begin return conv_std_logic_vector(N,W); end;

	-- Signal declare
	signal cdb_fstart_reg	: std_logic_vector(2 downto 0);		-- [0] : input false_path
	signal cdb_lstart_reg	: std_logic_vector(2 downto 0);		-- [0] : input false_path
	signal cdb_topaddr_reg	: std_logic_vector(31 downto 0);	-- [*] : input false_path
	signal framebegin		: boolean;
	signal linebegin		: boolean;

	type BUS_STATE is (IDLE, READ_ISSUE,DATA_READ);
	signal avm_state : BUS_STATE;
	signal datacount		: integer range 0 to BURSTCYCLE;
	signal lineoffs_reg		: std_logic_vector(31 downto 0);
	signal addr_reg			: std_logic_vector(31 downto 2);
	signal read_reg			: std_logic;
	signal readdata_sig		: std_logic_vector(31 downto 0);
	signal readdatavalid_sig: std_logic;

	signal pixeladdr_reg	: std_logic_vector(BURSTLENGTH_WIDTH downto 0);
	signal validdelay_reg	: std_logic_vector(3 downto 0);
	signal q_sig			: std_logic_vector(15 downto 0);
	signal pixeldata_sig	: std_logic_vector(15 downto 0);
	signal pixel_r_sig		: std_logic_vector(7 downto 0);
	signal pixel_g_sig		: std_logic_vector(7 downto 0);
	signal pixel_b_sig		: std_logic_vector(7 downto 0);

	signal pixellatch_sig	: std_logic;
	signal rout_reg			: std_logic_vector(7 downto 0);
	signal gout_reg			: std_logic_vector(7 downto 0);
	signal bout_reg			: std_logic_vector(7 downto 0);

	-- Component declare
	component peridot_vga_yvu2rgb
	port (
		reset		: in  std_logic;
		clk			: in  std_logic;

		pixelvalid	: in  std_logic;
		y_data		: in  std_logic_vector(7 downto 0);
		uv_data		: in  std_logic_vector(7 downto 0);

		r_data		: out std_logic_vector(7 downto 0);
		g_data		: out std_logic_vector(7 downto 0);
		b_data		: out std_logic_vector(7 downto 0)
	);
	end component;

begin

	-- 非同期信号の同期化 

	process (csi_m1_clk, csi_m1_reset) begin
		if is_true(csi_m1_reset) then
			cdb_fstart_reg <= (others=>'0');
			cdb_lstart_reg <= (others=>'0');

		elsif rising_edge(csi_m1_clk) then
			cdb_fstart_reg <= cdb_fstart_reg(1 downto 0) & framestart;
			cdb_lstart_reg <= cdb_lstart_reg(1 downto 0) & linestart;
			cdb_topaddr_reg <= framebuff_addr;
		end if;
	end process;

	framebegin <= (cdb_fstart_reg(2 downto 1) = "01");
	linebegin  <= (cdb_lstart_reg(2 downto 1) = "01");


	-- AvalonMMバーストリード制御 

	ready <= '1' when(avm_state = IDLE) else '0';

	avm_m1_address    <= addr_reg & "00";
	avm_m1_burstcount <= to_vector(BURSTCYCLE, avm_m1_burstcount'length);
	avm_m1_read       <= read_reg;
	readdata_sig      <= avm_m1_readdata;
	readdatavalid_sig <= avm_m1_readdatavalid when(avm_state=DATA_READ) else '0';

	process (csi_m1_clk, csi_m1_reset) begin
		if is_true(csi_m1_reset) then
			avm_state <= IDLE;
			datacount <= 0;
			addr_reg  <= (others=>'0');
			read_reg  <= '0';
			lineoffs_reg <= (others=>'0');

		elsif rising_edge(csi_m1_clk) then
			case avm_state is
			when IDLE =>
				if linebegin then
					avm_state <= READ_ISSUE;
					addr_reg  <= cdb_topaddr_reg(31 downto 2) + lineoffs_reg(31 downto 2);
					read_reg  <= '1';
					datacount <= 0;
				end if;

			when READ_ISSUE =>
				if is_false(avm_m1_waitrequest) then
					avm_state <= DATA_READ;
					read_reg  <= '0';
				end if;

			when DATA_READ =>
				if is_true(avm_m1_readdatavalid) then
					if (datacount = BURSTCYCLE-1) then
						avm_state <= IDLE;
					end if;

					datacount <= datacount + 1;
				end if;

			when others=>
			end case;

			if framebegin then
				lineoffs_reg <= (others=>'0');
			elsif (avm_state = IDLE and linebegin) then
				lineoffs_reg <= lineoffs_reg + LINEOFFSETBYTES;
			end if;

		end if;
	end process;


	-- ラインバッファメモリ 

	process (video_clk) begin
		if rising_edge(video_clk) then
			if is_false(video_pixelrequest) then
				pixeladdr_reg <= (others=>'0');
			else
				pixeladdr_reg <= pixeladdr_reg + '1';
			end if;

			validdelay_reg <= validdelay_reg(2 downto 0) & video_pixelrequest;
		end if;
	end process;

	u_mem : altsyncram
	generic map (
		lpm_type => "altsyncram",
		operation_mode => "DUAL_PORT",
		numwords_a => 2**BURSTLENGTH_WIDTH,
		widthad_a => BURSTLENGTH_WIDTH,
		width_a => 32,
		address_aclr_b => "NONE",
		clock_enable_input_a => "BYPASS",

		width_byteena_a => 1,
		numwords_b => 2**(BURSTLENGTH_WIDTH+1),
		widthad_b => BURSTLENGTH_WIDTH+1,
		width_b => 16,
		address_reg_b => "CLOCK1",
		outdata_reg_b => "CLOCK1",
		clock_enable_input_b => "BYPASS",
		clock_enable_output_b => "BYPASS",
		outdata_aclr_b => "NONE",
		power_up_uninitialized => "FALSE"
	)
	port map (
		clock0		=> csi_m1_clk,
		address_a	=> to_vector(datacount, BURSTLENGTH_WIDTH),
		data_a		=> readdata_sig,
		wren_a		=> readdatavalid_sig,

		clock1		=> video_clk,
		address_b	=> pixeladdr_reg,
		q_b			=> q_sig
	);


	-- ピクセルフォーマット変換 

gen_dataword : if (PIXEL_DATAORDER = "WORD") generate
	pixeldata_sig <= q_sig(7 downto 0) & q_sig(15 downto 8);
end generate;
gen_databyte : if (PIXEL_DATAORDER /= "WORD") generate
	pixeldata_sig <= q_sig;
end generate;

gen_rgb565 : if (PIXEL_COLORORDER = "RGB565") generate
	pixel_r_sig <= pixeldata_sig(15 downto 11) & pixeldata_sig(15 downto 13);
	pixel_g_sig <= pixeldata_sig(10 downto  5) & pixeldata_sig(10 downto  9);
	pixel_b_sig <= pixeldata_sig( 4 downto  0) & pixeldata_sig( 4 downto  2);
	pixellatch_sig <= validdelay_reg(1);
end generate;

gen_rgb555 : if (PIXEL_COLORORDER = "RGB555") generate
	pixel_r_sig <= pixeldata_sig(14 downto 10) & pixeldata_sig(14 downto 12);
	pixel_g_sig <= pixeldata_sig( 9 downto  5) & pixeldata_sig( 9 downto  7);
	pixel_b_sig <= pixeldata_sig( 4 downto  0) & pixeldata_sig( 4 downto  2);
	pixellatch_sig <= validdelay_reg(1);
end generate;

gen_yuv422 : if (PIXEL_COLORORDER = "YUV422") generate
	u_yvu2rgb : peridot_vga_yvu2rgb
	port map (
		reset		=> '0',
		clk			=> video_clk,
		pixelvalid	=> validdelay_reg(1),
		y_data		=> pixeldata_sig(7 downto 0),
		uv_data		=> pixeldata_sig(15 downto 8),
		r_data		=> pixel_r_sig,
		g_data		=> pixel_g_sig,
		b_data		=> pixel_b_sig
	);
	pixellatch_sig <= validdelay_reg(3);
end generate;


	-- 出力データラッチ 

	process (video_clk) begin
		if rising_edge(video_clk) then
			if is_true(pixellatch_sig) then
				rout_reg <= pixel_r_sig;
				gout_reg <= pixel_g_sig;
				bout_reg <= pixel_b_sig;
			else
				rout_reg <= (others=>'0');
				gout_reg <= (others=>'0');
				bout_reg <= (others=>'0');
			end if;
		end if;
	end process;

	video_rout <= rout_reg;
	video_gout <= gout_reg;
	video_bout <= bout_reg;


end RTL;
