-- ===================================================================
-- TITLE : PERIDOT peripherals / VGA contoroller
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

entity peridot_vga is
	generic (
		-- SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone V" "Cyclone IV E" "Cyclone IV GX" "Cyclone III"}
		DEVICE_FAMILY		: string := "Cyclone III";

		VIDEO_INTERFACE		: string := "PARALLEL";		-- "PARALLEL" : パラレルインターフェース 
														-- "DVI"      : DVIモード出力 
		PIXEL_COLORORDER	: string := "RGB565";		-- "RGB565"   : RGB565 16bit/pixel
														-- "RGB555"   : RGB555 15bit/pixel
														-- "YUV422"   : YUV422 16bit/word
		PIXEL_DATAORDER		: string := "BYTE";			-- "BYTE"     : バイト順(リトルエンディアン) 
														-- "WORD"     : ワード順(16bitビッグエンディアン) 
		LINEOFFSETBYTES		: integer := 1024*2;		-- メモリ上の1ライン分のデータバイト数 
		BURSTLENGTH_WIDTH	: integer := 9;				-- バースト長指示幅 (log2(H_ACTIVE/2)を表現できる幅) 

		VGACLOCK_FREQUENCY	: integer := 25200000;		-- ドットクロック周波数 (Hz)
		H_TOTAL				: integer := 800;			-- 同期信号設定値 
		H_SYNC				: integer := 96;
		H_BACKP				: integer := 48;
		H_ACTIVE			: integer := 640;
		V_TOTAL				: integer := 525;
		V_SYNC				: integer := 2;
		V_BACKP				: integer := 33;
		V_ACTIVE			: integer := 480;
--		H_TOTAL				: integer := 32;	-- test
--		H_SYNC				: integer := 4;		-- test
--		H_BACKP				: integer := 8;		-- test
--		H_ACTIVE			: integer := 16;	-- test
--		V_TOTAL				: integer := 5;		-- test
--		V_SYNC				: integer := 1;		-- test
--		V_BACKP				: integer := 1;		-- test
--		V_ACTIVE			: integer := 3;		-- test

		PCMSAMPLE_FREQUENCY	: integer := 44100;
		USE_AUDIOSTREAM		: string := "OFF"
	);
	port (
	--==== Avalon-MM Agent信号 =======================================
		csi_csr_clk			: in  std_logic;
		csi_csr_reset		: in  std_logic;

		avs_csr_address		: in  std_logic_vector(3 downto 2);
		avs_csr_read		: in  std_logic;
		avs_csr_readdata	: out std_logic_vector(31 downto 0);
		avs_csr_write		: in  std_logic;
		avs_csr_writedata	: in  std_logic_vector(31 downto 0);

		ins_csr_irq			: out std_logic;

	--==== Avalon-MM Host信号 ========================================
		csi_m1_clk			: in  std_logic;

		avm_m1_address		: out std_logic_vector(31 downto 0);
		avm_m1_burstcount	: out std_logic_vector(BURSTLENGTH_WIDTH downto 0);
		avm_m1_waitrequest	: in  std_logic;
		avm_m1_read			: out std_logic;
		avm_m1_readdata		: in  std_logic_vector(31 downto 0);
		avm_m1_readdatavalid: in  std_logic;

	--==== 外部信号 ==================================================
		coe_pcm_fs			: in  std_logic := '0';
		coe_pcm_l			: in  std_logic_vector(23 downto 0) := (others=>'X');
		coe_pcm_r			: in  std_logic_vector(23 downto 0) := (others=>'X');

		coe_vga_clk			: in  std_logic := '0';
		coe_vga_active		: out std_logic := '0';
		coe_vga_rout		: out std_logic_vector(7 downto 0) := (others=>'0');
		coe_vga_gout		: out std_logic_vector(7 downto 0) := (others=>'0');
		coe_vga_bout		: out std_logic_vector(7 downto 0) := (others=>'0');
		coe_vga_hsync_n		: out std_logic := '0';
		coe_vga_vsync_n		: out std_logic := '0';
		coe_vga_csync_n		: out std_logic := '0';

		coe_ser_clk			: in  std_logic := '0';
		coe_ser_x5clk		: in  std_logic := '0';
		coe_ser_data		: out std_logic_vector(2 downto 0) := (others=>'0');
		coe_ser_data_n		: out std_logic_vector(2 downto 0) := (others=>'0');
		coe_ser_clock		: out std_logic := '0';
		coe_ser_clock_n		: out std_logic := '0'
	);
end peridot_vga;

architecture RTL of peridot_vga is
	-- Misc function
	function is_true(S:std_logic) return boolean is begin return(S='1'); end;
	function is_false(S:std_logic) return boolean is begin return(S='0'); end;

	-- ピクセルリクエストの先行クロック数を取得 
	function get_earlyreq_value return integer is
	begin
		if (PIXEL_COLORORDER = "YUV422") then
			return 5;
		else
			return 3;
		end if;
	end;

	-- Constant declare
	constant CLOCK_FREQUENCY	: real := real(VGACLOCK_FREQUENCY)/1000000.0;
	constant AUDIO_FREQUENCY	: real := real(PCMSAMPLE_FREQUENCY)/1000.0;

	-- Signal declare
	signal reset_sig		: std_logic;
	signal pix_clk_sig		: std_logic;
	signal pix_reset_sig	: std_logic;
	signal cdb_reset_reg	: std_logic_vector(1 downto 0);

	signal pixelrequest_sig	: std_logic;
	signal control_sig		: std_logic_vector(3 downto 0);
	signal active_sig		: std_logic;
	signal hsync_sig		: std_logic;
	signal vsync_sig		: std_logic;
	signal csync_sig		: std_logic;

	signal framebuff_top_sig: std_logic_vector(31 downto 0);
	signal scan_enable_sig	: std_logic;
	signal linestart_sig	: std_logic;
	signal rout_sig			: std_logic_vector(7 downto 0);
	signal gout_sig			: std_logic_vector(7 downto 0);
	signal bout_sig			: std_logic_vector(7 downto 0);

	-- Component declare
	component peridot_vga_csr is
	port (
		csi_csr_reset		: in  std_logic;
		csi_csr_clk			: in  std_logic;
		avs_csr_address		: in  std_logic_vector(3 downto 2);
		avs_csr_read		: in  std_logic;
		avs_csr_readdata	: out std_logic_vector(31 downto 0);
		avs_csr_write		: in  std_logic;
		avs_csr_writedata	: in  std_logic_vector(31 downto 0);
		ins_csr_irq			: out std_logic;

		vsync_in			: in  std_logic;	-- async input
		framebuff_top		: out std_logic_vector(31 downto 0);
		scan_enable			: out std_logic
	);
	end component;

	component peridot_vga_avm
	generic (
		PIXEL_COLORORDER	: string;
		PIXEL_DATAORDER		: string;
		LINEOFFSETBYTES		: integer;
		BURSTLENGTH_WIDTH	: integer;
		BURSTCYCLE			: integer;
		CYCLENUMBER			: integer
	);
	port (
		csi_m1_reset		: in  std_logic;
		csi_m1_clk			: in  std_logic;
		avm_m1_address		: out std_logic_vector(31 downto 0);
		avm_m1_burstcount	: out std_logic_vector(BURSTLENGTH_WIDTH downto 0);
		avm_m1_waitrequest	: in  std_logic;
		avm_m1_read			: out std_logic;
		avm_m1_readdata		: in  std_logic_vector(31 downto 0);
		avm_m1_readdatavalid: in  std_logic;

		framebuff_addr		: in  std_logic_vector(31 downto 0);	-- async input
		framestart			: in  std_logic;						-- async input
		linestart			: in  std_logic;						-- async input
		ready				: out std_logic;

		video_clk			: in  std_logic;
		video_pixelrequest	: in  std_logic;
		video_rout			: out std_logic_vector(7 downto 0);
		video_gout			: out std_logic_vector(7 downto 0);
		video_bout			: out std_logic_vector(7 downto 0)
	);
	end component;

	component video_syncgen
	generic (
		START_SIG	: string := "WIDTH";
		EARLY_REQ	: integer;
		H_TOTAL		: integer;
		H_SYNC		: integer;
		H_BACKP		: integer;
		H_ACTIVE	: integer;
		V_TOTAL		: integer;
		V_SYNC		: integer;
		V_BACKP		: integer;
		V_ACTIVE	: integer;
		START_HPOS	: integer := 0;
		START_VPOS	: integer := 0
	);
	port (
		reset		: in  std_logic;
		video_clk	: in  std_logic;

		scan_ena	: in  std_logic := '0';
		framestart	: out std_logic;
		linestart	: out std_logic;
		pixrequest	: out std_logic;

		hdmicontrol	: out std_logic_vector(3 downto 0);
		active		: out std_logic;		-- active high
		hsync		: out std_logic;		-- active high
		vsync		: out std_logic;		-- active high
		csync		: out std_logic;		-- active high
		hblank		: out std_logic;		-- active high
		vblank		: out std_logic			-- active high
	);
	end component;

	component hdmi_tx
	generic(
		DEVICE_FAMILY	: string;
		CLOCK_FREQUENCY	: real;
		ENCODE_MODE		: string;
		USE_EXTCONTROL	: string := "ON";
		SYNC_POLARITY	: string := "NEGATIVE";
		SCANMODE		: string := "UNDER";
		PICTUREASPECT	: string := "NONE";
		FORMATASPECT	: string := "NONE";
		PICTURESCALING	: string := "NONE";
		COLORSPACE		: string := "RGB";
		YCC_DATARANGE	: string := "LIMITED";
		CONTENTTYPE		: string := "GRAPHICS";
		USE_AUDIO_PACKET: string := "OFF";
		AUDIO_FREQUENCY	: real := 44.1;
		PCMFIFO_DEPTH	: integer := 8;
		VIC_CODE		: std_logic_vector(6 downto 0) := "0000000";
		CATEGORY_CODE	: std_logic_vector(7 downto 0) := "00000000"
	);
	port(
		reset		: in  std_logic;
		clk			: in  std_logic;
		clk_x5		: in  std_logic;

		control		: in  std_logic_vector(3 downto 0);
		active		: in  std_logic := '0';
		r_data		: in  std_logic_vector(7 downto 0);
		g_data		: in  std_logic_vector(7 downto 0);
		b_data		: in  std_logic_vector(7 downto 0);
		hsync		: in  std_logic;
		vsync		: in  std_logic;

		pcm_fs		: in  std_logic;
		pcm_l		: in  std_logic_vector(23 downto 0);
		pcm_r		: in  std_logic_vector(23 downto 0);

		data		: out std_logic_vector(2 downto 0);
		data_n		: out std_logic_vector(2 downto 0);
		clock		: out std_logic;
		clock_n		: out std_logic
	);
	end component;

	-- Attribute
	attribute altera_attribute : string;
	attribute altera_attribute of RTL : architecture is
	(
		"-name SDC_STATEMENT ""set_false_path -to [get_registers {*peridot_vga:*|cdb_reset_reg[0]}]"";" & 
		"-name SDC_STATEMENT ""set_false_path -to [get_registers {*peridot_vga:*|peridot_vga_csr:u_csr|cdb_vsyncin_reg[0]}]"";" & 
		"-name SDC_STATEMENT ""set_false_path -to [get_registers {*peridot_vga:*|peridot_vga_avm:u_avm|cdb_fstart_reg[0]}]"";" & 
		"-name SDC_STATEMENT ""set_false_path -to [get_registers {*peridot_vga:*|peridot_vga_avm:u_avm|cdb_lstart_reg[0]}]"";" & 
		"-name SDC_STATEMENT ""set_false_path -to [get_registers {*peridot_vga:*|peridot_vga_avm:u_avm|cdb_topaddr_reg[*]}]"""
	);

begin

	-- リセットデアサート同期 --

	reset_sig <= csi_csr_reset;

	process (pix_clk_sig) begin
		if rising_edge(pix_clk_sig) then
			cdb_reset_reg <= cdb_reset_reg(0) & reset_sig;
		end if;
	end process;

	pix_reset_sig <= cdb_reset_reg(1) or cdb_reset_reg(0);


	-- タイミング信号生成 --

	u_sync : video_syncgen
	generic map(
--		START_VPOS	=> V_TOTAL-1,
		EARLY_REQ	=> get_earlyreq_value,
		H_TOTAL		=> H_TOTAL,
		H_SYNC		=> H_SYNC,
		H_BACKP		=> H_BACKP,
		H_ACTIVE	=> H_ACTIVE,
		V_TOTAL		=> V_TOTAL,
		V_SYNC		=> V_SYNC,
		V_BACKP		=> V_BACKP,
		V_ACTIVE	=> V_ACTIVE
	)
	port map(
		reset		=> pix_reset_sig,
		video_clk	=> pix_clk_sig,

		scan_ena	=> scan_enable_sig,
		linestart	=> linestart_sig,
		pixrequest	=> pixelrequest_sig,

		hdmicontrol	=> control_sig,
		active		=> active_sig,
		hsync		=> hsync_sig,
		vsync		=> vsync_sig,
		csync		=> csync_sig
	);


	-- コントロールレジスタ --

	u_csr : peridot_vga_csr
	port map(
		csi_csr_reset		=> reset_sig,
		csi_csr_clk			=> csi_csr_clk,
		avs_csr_address		=> avs_csr_address,
		avs_csr_read		=> avs_csr_read,
		avs_csr_readdata	=> avs_csr_readdata,
		avs_csr_write		=> avs_csr_write,
		avs_csr_writedata	=> avs_csr_writedata,
		ins_csr_irq			=> ins_csr_irq,

		vsync_in			=> vsync_sig,
		framebuff_top		=> framebuff_top_sig,
		scan_enable			=> scan_enable_sig
	);


	-- ピクセルデータ読み出し --

	u_avm : peridot_vga_avm
	generic map(
		PIXEL_COLORORDER	=> PIXEL_COLORORDER,
		PIXEL_DATAORDER		=> PIXEL_DATAORDER,
		LINEOFFSETBYTES		=> LINEOFFSETBYTES,
		BURSTLENGTH_WIDTH	=> BURSTLENGTH_WIDTH,
		BURSTCYCLE			=> H_ACTIVE/2,
		CYCLENUMBER			=> V_ACTIVE
	)
	port map(
		csi_m1_reset		=> reset_sig,
		csi_m1_clk			=> csi_m1_clk,
		avm_m1_address		=> avm_m1_address,
		avm_m1_waitrequest	=> avm_m1_waitrequest,
		avm_m1_burstcount	=> avm_m1_burstcount,
		avm_m1_read			=> avm_m1_read,
		avm_m1_readdata		=> avm_m1_readdata,
		avm_m1_readdatavalid=> avm_m1_readdatavalid,

		framebuff_addr		=> framebuff_top_sig,
		framestart			=> vsync_sig,
		linestart			=> linestart_sig,

		video_clk			=> pix_clk_sig,
		video_pixelrequest	=> pixelrequest_sig,
		video_rout			=> rout_sig,
		video_gout			=> gout_sig,
		video_bout			=> bout_sig
	);


	-- データ出力 --

gen_par : if (VIDEO_INTERFACE = "PARALLEL") generate
	pix_clk_sig <= coe_vga_clk;

	coe_vga_active  <= active_sig;
	coe_vga_rout    <= rout_sig;
	coe_vga_gout    <= gout_sig;
	coe_vga_bout    <= bout_sig;
	coe_vga_hsync_n <= not hsync_sig;
	coe_vga_vsync_n <= not vsync_sig;
	coe_vga_csync_n <= not csync_sig;
end generate;
gen_ser : if (VIDEO_INTERFACE /= "PARALLEL") generate
	pix_clk_sig <= coe_ser_clk;

	u_ser : hdmi_tx
	generic map(
		DEVICE_FAMILY	=> DEVICE_FAMILY,
		CLOCK_FREQUENCY	=> CLOCK_FREQUENCY,
		ENCODE_MODE		=> VIDEO_INTERFACE,
		AUDIO_FREQUENCY	=> AUDIO_FREQUENCY,
		USE_AUDIO_PACKET=> USE_AUDIOSTREAM
	)
	port map(
		reset	=> pix_reset_sig,
		clk		=> pix_clk_sig,
		clk_x5	=> coe_ser_x5clk,

		control	=> control_sig,
		active	=> active_sig,
		r_data	=> rout_sig,
		g_data	=> gout_sig,
		b_data	=> bout_sig,
		hsync	=> hsync_sig,
		vsync	=> vsync_sig,

		pcm_fs	=> coe_pcm_fs,
		pcm_l	=> coe_pcm_l,
		pcm_r	=> coe_pcm_r,

		data	=> coe_ser_data,
		data_n	=> coe_ser_data_n,
		clock	=> coe_ser_clock,
		clock_n	=> coe_ser_clock_n
	);
end generate;


end RTL;
