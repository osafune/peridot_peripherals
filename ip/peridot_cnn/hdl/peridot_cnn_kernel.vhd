-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - kernel
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/07/31 -> 2020/08/19
--            : 2020/09/19 (FIXED)
--
--     UPDATE : 2023/11/30 -> 2024/01/22
--
-- ===================================================================
--
-- The MIT License (MIT)
-- Copyright (c) 2020-2024 J-7SYSTEM WORKS LIMITED.
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

-- ・実装todo
-- [X] カーネル演算をモジュールに分離 
-- [X] アンプーリング機能をカーネル側処理に変更 
-- [X] パディング処理をラインFIFOの後に移動(ラインFIFO容量削減) 
-- [X] リングバッファを4ライン単位からワード単位に変更 
--
-- ・検証todo
-- [X] リングバッファのアドレス周回時の動作(ラウンド処理で正しい空きが得られるか？) 
-- [X] リングバッファfull時の挙動 
-- [X] ストール制御の可否(backpressure制御が行われるか？) → 基本動作を確認 
-- [X] ラインスキャン動作の確認 → 基本動作を確認 
-- [X] カーネル演算の一致(単位行列のみ確認する)
-- [X] バイトパッキングモードの動作 
-- [X] アンプーリングモードの動作 
-- [X] エラーインジェクションテスト (force_error操作して確認)
-- [X] init信号アボートの動作(正しく復帰するか？タイミングを勘違いしている部分はないか？)
-- [X] 32bitで確認したらgenericを変えて確認する(ライン長を変更してsimが変わらないかどうか見る)
--
-- ・リソース概算 
-- 1020LE + 11DSP + 4M9k (32bit幅,256x256,±1kbyte,FIFOフローチェックOFF時,AREA)
-- 1100LE + 11DSP + 5M9k (32bit幅,1024x1024,±32kbyte時)
-- 1130LE + 11DSP + 9M9k (256bit幅,2048x2048,±32kbyte時)
-- 1160LE + 11DSP + 17M9k (256bit幅,4096x4096,±32kbyte時)
--


-- カーネルはparam_validのアサートで動作開始。 
-- カーネルパラメータ分のデータをparam_dataから取得するとparam_doneをアサートし演算を開始。 
-- パラメータのバーストリードで各カーネルの最初のデータ読み出しを抑止しているため、 
-- リードフュージョン機能を使う場合はカーネル数×パラメータワード数以上のバースト長に 
-- なるようにしなければならない。通常はFSMの最低バースト長で設定されている。 
--
-- status(0) : Error, Bus access cannot be continued.
-- status(1) : Warning, Load datalength is out of range.
-- status(2) : Warning, Saturation occurs in kernel operation. (no use. always 0)
--
-- padding_mode(1) : padding enable(=1)
-- padding_mode(0) : zero padding(=1)
--                 : normal padding(=0)
-- bytepacking     : Byte Packing mode(=1)
--                 : Normal mode(=0)


-- VHDL 1993 / IEEE 1076-1993
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_misc.all;

library lpm;
use lpm.lpm_components.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity peridot_cnn_kernel is
	generic(
		PARAMWORD_POW2_NUMBER	: integer := 5;		-- パラメータワード幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		MAXCONVSIZE_POW2_NUMBER	: integer := 9;		-- 畳み込み画像の最大値 (8:256x256 / 9:512x512 / 10:1024x1024 / 11:2048x2048 / 12:4096x4096)
		MAXLINEBYTES_POW2_NUMBER: integer := 15;	-- ラインデータ増分値の最大バイト数 (10:±1kbyte ～ 15:±32kbyte)
		FIFO_FLOW_CHECKING		: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 
		FIFO_SPEED_OPTION		: string := "ON";	-- FIFOのインスタンスオプション(ON=speed / OFF=area)

		-- SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
		test_force_error	: in  std_logic := '0';

		test_start			: out std_logic;
		test_finally		: out std_logic;
		test_memread_ready	: out std_logic;
		test_genpixel_ready	: out std_logic;
		test_beginbytes		: out std_logic_vector(4 downto 0);
		test_burstbytes		: out std_logic_vector(15 downto 0);
		test_err_outofrange	: out std_logic;
		test_attrfifo_flush	: out std_logic;
		test_attrfifo_wrreq	: out std_logic;
		test_attrfifo_full	: out std_logic;
		test_attrfifo_empty	: out std_logic;
		test_attrfifo_rdack	: out std_logic;
		test_ringbuff_wrena	: out std_logic;
		test_ringbuff_wraddr: out std_logic_vector(15 downto 0);
		test_ringbuff_rdaddr: out std_logic_vector(15 downto 0);
		test_ringbuff_rddata: out std_logic_vector(7 downto 0);
		test_rigbuff_free	: out std_logic_vector(15 downto 0);
		test_pixel_lineend	: out std_logic;
		test_pixel_linemask	: out std_logic;
		test_pixel_padding	: out std_logic;
		test_pixel_valid	: out std_logic;
		test_pixel_data		: out std_logic_vector(7 downto 0);
		test_linefifo_full	: out std_logic_vector(1 downto 0);
		test_linefifo_wr	: out std_logic_vector(1 downto 0);
		test_linefifo_rd	: out std_logic_vector(1 downto 0);
		test_linefifo_q0	: out std_logic_vector(7 downto 0);
		test_linefifo_q1	: out std_logic_vector(7 downto 0);
		test_linefifo_q2	: out std_logic_vector(7 downto 0);
		test_kernel_cvalid	: out std_logic;
		test_kernel_enable	: out std_logic;


		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: in  std_logic := '0';
		ready			: out std_logic;
		error			: out std_logic;						-- errorがアサートされたらreadyは不定(解除はresetのみ) 
		status			: out std_logic_vector(2 downto 0);
		conv_x_size		: in  std_logic_vector(MAXCONVSIZE_POW2_NUMBER downto 0);
		conv_y_size		: in  std_logic_vector(MAXCONVSIZE_POW2_NUMBER downto 0);
		padding_mode	: in  std_logic_vector(1 downto 0);
		bytepacking		: in  std_logic;

		param_valid		: in  std_logic;
		param_data		: in  std_logic_vector(2**PARAMWORD_POW2_NUMBER-1 downto 0);
		param_done		: out std_logic;

		read_request	: out std_logic;
		read_complete	: out std_logic;
		read_address	: out std_logic_vector(31 downto 0);
		read_burstcount	: out std_logic_vector(MAXCONVSIZE_POW2_NUMBER-(DATABUS_POW2_NUMBER-3) downto 0);
		read_datavalid	: in  std_logic;
		read_data		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);

		sto_ready		: in  std_logic;
		sto_valid		: out std_logic;
		sto_data		: out std_logic_vector(31 downto 0);
		sto_endofline	: out std_logic;
		sto_endofframe	: out std_logic
	);
end peridot_cnn_kernel;

architecture RTL of peridot_cnn_kernel is
	-- Misc function
	function is_true(S:std_logic) return boolean is begin return(S='1'); end;
	function is_false(S:std_logic) return boolean is begin return(S='0'); end;
	function to_vector(N,W:integer) return std_logic_vector is begin return conv_std_logic_vector(N,W); end;
	function shiftin(V:std_logic_vector; S:std_logic) return std_logic_vector is variable a:std_logic_vector(V'length downto 0); begin a:=V&S; return a(V'range); end;
	function shiftout(V:std_logic_vector) return std_logic is begin return V(V'left); end;
	function repbit(S:std_logic; W:integer) return std_logic_vector is variable a:std_logic_vector(W-1 downto 0); begin a:=(others=>S); return a; end;
	function slice(V:std_logic_vector; W,N:integer) return std_logic_vector is variable a:std_logic_vector(V'length+W+N-2 downto 0);
		begin a:=repbit('0',W+N-1)&V; return a(W+N-1 downto N); end;
	function slice_sxt(V:std_logic_vector; W,N:integer) return std_logic_vector is variable a:std_logic_vector(V'length+W+N-2 downto 0);
		begin a:=repbit(V(V'left),W+N-1)&V; return a(W+N-1 downto N); end;

	-- テスト用 
	constant TEST_FREE_OFFSET	: integer := 0;			-- ringbuff_freeのオフセット(テスト用)
	constant TEST_INADDR_INIT	: integer := 0;			-- ringbuff_inaddr初期値(テスト用)
--	constant ATTRFIFO_WIDTH		: integer := 2;			-- 属性FIFOの深さ(テスト用)

	-- モジュール固定値 
	constant PARAM_BLOCK_SIZE	: integer := 8;			-- パラメータデスクリプタのワード数(32bit×8ワードで固定)
	constant GENPIXEL_DELAY		: integer := 2;			-- ピクセルデータの出力レイテンシ(2クロックで固定)
	constant KERNEL_CONV_DELAY	: integer := 8;			-- カーネル畳み込み演算の出力レイテンシ(8クロックで固定)
	constant ATTRFIFO_WIDTH		: integer := (MAXCONVSIZE_POW2_NUMBER+1)/2;	-- 属性FIFOの深さ(16～64ワード) 
	constant ALIGN_ADDR_WIDTH	: integer := DATABUS_POW2_NUMBER-3;			-- ワード境界のアドレスビット幅 
	constant DATABUS_BITWIDTH	: integer := 2**DATABUS_POW2_NUMBER;		-- データバス幅 
	constant BUFF_INADDR_WIDTH	: integer := MAXCONVSIZE_POW2_NUMBER-ALIGN_ADDR_WIDTH+1;	-- 入力リングバッファのアドレスビット幅(ライン最大長×2) 

	-- xstepレジスタの設定値 
	constant PARAM_XSTEP_1		: std_logic_vector(1 downto 0) := "00";	-- 増分値+1の設定値 *デフォルト 
	constant PARAM_XSTEP_2		: std_logic_vector(1 downto 0) := "01";	-- 増分値+2の設定値 
	constant PARAM_XSTEP_3		: std_logic_vector(1 downto 0) := "10";	-- 増分値+3の設定値 
	constant PARAM_XSTEP_4		: std_logic_vector(1 downto 0) := "11";	-- 増分値+4の設定値 


	-- 全体制御 
	signal init_sig				: std_logic;
	signal finally_sig			: std_logic;
	signal start_sig			: std_logic;
	signal start_1_reg			: std_logic;
	signal conv_xmax_sig		: std_logic_vector(conv_x_size'range);
	signal conv_ymax_sig		: std_logic_vector(conv_y_size'range);
	signal param_xmax_sig		: std_logic_vector(MAXCONVSIZE_POW2_NUMBER-1 downto 0);
	signal param_ymax_sig		: std_logic_vector(MAXCONVSIZE_POW2_NUMBER-1 downto 0);

	-- カーネルパラメータ読み込みブロック 
	signal param_init_sig		: std_logic;
	signal param_ready_reg		: std_logic;
	signal param_bit_sig		: std_logic_vector(2**PARAM_BLOCK_SIZE-1 downto 0);
	signal param_latchena_reg	: std_logic_vector(2**(PARAM_BLOCK_SIZE-PARAMWORD_POW2_NUMBER) downto 0);
	signal param_loaddone_sig	: std_logic;
	signal reg0_latch_sig		: std_logic;
	signal reg1_latch_sig		: std_logic;
	signal reg2_latch_sig		: std_logic;
	signal reg3_latch_sig		: std_logic;
	signal reg4_latch_sig		: std_logic;
	signal reg5_latch_sig		: std_logic;
	signal reg6_latch_sig		: std_logic;

	signal error_deviated_reg	: std_logic;
	signal inputdatatype_reg	: std_logic;
	signal v_doubler_reg		: std_logic;
	signal h_doubler_reg		: std_logic;
	signal byte_position_reg	: std_logic_vector(1 downto 0);
	signal xstep_number_reg		: std_logic_vector(1 downto 0);
	signal x_reverse_reg		: std_logic;
	signal rd_address_reg		: std_logic_vector(31 downto 0);
	signal address_inc0_reg		: std_logic_vector(MAXLINEBYTES_POW2_NUMBER downto 0);
	signal address_inc1_reg		: std_logic_vector(MAXLINEBYTES_POW2_NUMBER downto 0);
	signal kernel_wk00_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk01_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk02_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk10_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk11_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk12_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk20_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk21_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk22_reg		: std_logic_vector(8 downto 0);
	signal kernel_bk_reg		: std_logic_vector(19 downto 0);
	signal kernel_sk_reg		: std_logic_vector(17 downto 0);
	signal line_lastbytes_sig	: std_logic_vector(MAXCONVSIZE_POW2_NUMBER+2-1 downto 0);
	signal update_addr_sig		: std_logic;

	-- ラインデータ読み込み制御ブロック 
	type DEF_STATE_MEMREAD is (READIDLE, READREQ, READDATA, READDONE);
	signal state_memread : DEF_STATE_MEMREAD;
	signal line_count_reg		: std_logic_vector(param_ymax_sig'range);
	signal memread_init_sig		: std_logic;
	signal memread_ready_sig	: std_logic;
	signal read_request_reg		: std_logic;
	signal error_burstover_reg	: std_logic;
	signal flag_almostfull_reg	: std_logic;
	signal loadbytes_reg		: std_logic_vector(line_lastbytes_sig'range);
	signal rd_datanum_reg		: std_logic_vector(MAXCONVSIZE_POW2_NUMBER-ALIGN_ADDR_WIDTH-1 downto 0);

	signal line_beginoffset_sig	: std_logic_vector(ALIGN_ADDR_WIDTH-1 downto 0);
	signal burstdatabytes_sig	: std_logic_vector(loadbytes_reg'range);
	signal burstwordmax_sig		: std_logic_vector(rd_datanum_reg'range);
	signal read_datavalid_sig	: std_logic;
	signal err_burst_over_sig	: std_logic;
	signal rb_almostfull_sig	: std_logic;

	signal ringbuff_inaddr_reg	: std_logic_vector(BUFF_INADDR_WIDTH-1 downto 0);
	signal ringbuff_index_reg	: std_logic_vector(ringbuff_inaddr_reg'range);
	signal ringbuff_wraddr_sig	: std_logic_vector(BUFF_INADDR_WIDTH-1 downto 0);
	signal ringbuff_wrdata_sig	: std_logic_vector(read_data'range);
	signal ringbuff_wrena_sig	: std_logic;
	signal ringbuff_rdaddr_sig	: std_logic_vector(BUFF_INADDR_WIDTH+ALIGN_ADDR_WIDTH-1 downto 0);
	signal ringbuff_rddata_sig	: std_logic_vector(7 downto 0);
	signal ringbuff_rdclkena_sig: std_logic;
	signal ringbuff_free_sig	: std_logic_vector(ringbuff_inaddr_reg'range);

	signal attrfifo_flush_sig	: std_logic;
	signal attrfifo_wrreq_sig	: std_logic;
	signal attrfifo_data_sig	: std_logic_vector(BUFF_INADDR_WIDTH+ALIGN_ADDR_WIDTH-1 downto 0);
	signal attrfifo_full_sig	: std_logic;
	signal attrfifo_rdack_sig	: std_logic;
	signal attrfifo_q_sig		: std_logic_vector(attrfifo_data_sig'range);
	signal attrfifo_empty_sig	: std_logic;

	-- 2次元データ出力制御ブロック 
	type DEF_STATE_GENPIXEL is (PIXELIDLE, PIXELWAIT, PIXELBEGINPADDING, PIXELLOOP, PIXELENDPADDING, PIXELFINALLY);
	signal state_genpixel : DEF_STATE_GENPIXEL;
	signal rdaddr_incvalue		: integer range 1 to 4;
	signal ref_x_counter		: integer range 0 to 2**param_xmax_sig'length-1;
	signal x_counter			: integer range 0 to 2**param_xmax_sig'length-1;
	signal y_counter			: integer range 0 to 2**param_ymax_sig'length-1;
	signal genpixel_init_sig	: std_logic;
	signal genpixel_ready_sig	: std_logic;
	signal genpixel_enable_sig	: std_logic;
	signal x_hold_reg			: std_logic;
	signal y_hold_reg			: std_logic;
	signal pl_hold_reg			: std_logic;
	signal lineend_sig			: std_logic;
	signal frameend_sig			: std_logic;
	signal padding_ena_reg		: std_logic;
	signal padding_zero_reg		: std_logic;
	signal pixel_rdindex_reg	: std_logic_vector(ringbuff_index_reg'range);
	signal pixel_rdoffset_reg	: std_logic_vector(ALIGN_ADDR_WIDTH-1 downto 0);
	signal pixel_rdaddr_reg		: std_logic_vector(MAXCONVSIZE_POW2_NUMBER-1 downto 0);
	signal pixel_rdaddr_sig		: std_logic_vector(pixel_rdaddr_reg'range);

	signal p_linemask_sig		: std_logic;
	signal p_padding_sig		: std_logic;
	signal p_valid_sig			: std_logic;
	signal p_frameend_delay_reg	: std_logic_vector(GENPIXEL_DELAY-2 downto 0);
	signal p_lineend_delay_reg	: std_logic_vector(GENPIXEL_DELAY-2 downto 0);
	signal p_linemask_delay_reg	: std_logic_vector(GENPIXEL_DELAY-1 downto 0);
	signal p_padding_delay_reg	: std_logic_vector(GENPIXEL_DELAY-1 downto 0);
	signal p_valid_delay_reg	: std_logic_vector(GENPIXEL_DELAY-1 downto 0);
	signal pixel_frameend_sig	: std_logic;
	signal pixel_lineend_sig	: std_logic;
	signal pixel_linemask_sig	: std_logic;
	signal pixel_padding_sig	: std_logic;
	signal pixel_valid_sig		: std_logic;
	signal pixel_data_sig		: std_logic_vector(ringbuff_rddata_sig'range);

	-- カーネル演算ブロック 
	signal kernel_bytepack_reg	: std_logic;
	signal kernel_enable_sig	: std_logic;
	signal kernel_calcvalid_sig	: std_logic;
	signal kernel_eolvalid_sig	: std_logic;
	signal kernel_eofvalid_sig	: std_logic;
	signal kernel_calcdelay_reg	: std_logic_vector(KERNEL_CONV_DELAY downto 0);
	signal kernel_eoldelay_reg	: std_logic_vector(KERNEL_CONV_DELAY downto 0);
	signal kernel_eofdelay_reg	: std_logic_vector(KERNEL_CONV_DELAY downto 0);
	signal kernel_linedelay_reg	: std_logic_vector(1 downto 0);
	signal kernel_pixdelay_reg	: std_logic_vector(1 downto 0);
	signal linefifo_wrreq_reg	: std_logic_vector(1 downto 0);
	signal linefifo_flush_sig	: std_logic;
	signal linefifo_wrreq_sig	: std_logic_vector(1 downto 0);
	signal linefifo_rdack_sig	: std_logic_vector(1 downto 0);
	signal linefifo_full_sig	: std_logic_vector(1 downto 0);
	signal linefifo_empty_sig	: std_logic_vector(1 downto 0);
	signal conv_ydata_sig		: std_logic_vector(3*8-1 downto 0);
	signal conv_ydata_reg		: std_logic_vector(conv_ydata_sig'range);
	signal kernel_data_sig		: std_logic_vector(31 downto 0);
	signal kernel_valid_sig		: std_logic;
	signal kernel_eol_sig		: std_logic;
	signal kernel_eof_sig		: std_logic;


	-- コンポーネント宣言 
	component peridot_cnn_kernel_conv
	port(
		clk			: in  std_logic;
		enable		: in  std_logic := '1';		-- clock enable

		sign_ena	: in  std_logic;			-- Line data sign extension : '1'=signed 8bit / '0'=unsigned 8bit
		pack_ena	: in  std_logic;			-- Function mode : '1'=Byte Packing mode / '0'=normal mode(CNN)
		byte_pos	: in  std_logic_vector(1 downto 0);		-- Indicates the byte position when byte packing mode.
		wk00		: in  std_logic_vector(8 downto 0);		-- Kernel wait Wk00～Wk22 : s9
		wk01		: in  std_logic_vector(8 downto 0);
		wk02		: in  std_logic_vector(8 downto 0);
		wk10		: in  std_logic_vector(8 downto 0);
		wk11		: in  std_logic_vector(8 downto 0);
		wk12		: in  std_logic_vector(8 downto 0);
		wk20		: in  std_logic_vector(8 downto 0);
		wk21		: in  std_logic_vector(8 downto 0);
		wk22		: in  std_logic_vector(8 downto 0);
		bk			: in  std_logic_vector(19 downto 0);	-- Kernel local bias Bk : s20
		sk			: in  std_logic_vector(17 downto 0);	-- Kernel scale Sk : s18

		y0			: in  std_logic_vector(7 downto 0);		-- Line data 0～2 : u8/s8
		y1			: in  std_logic_vector(7 downto 0);
		y2			: in  std_logic_vector(7 downto 0);

		result		: out std_logic_vector(31 downto 0)		-- Result : s32
	);
	end component;

begin

	-- テスト記述 

	test_start <= start_sig;
	test_finally <= finally_sig;
	test_memread_ready <= memread_ready_sig;
	test_genpixel_ready <= genpixel_ready_sig;

	test_beginbytes <= slice(line_beginoffset_sig, 5, 0);
	test_burstbytes <= slice(burstdatabytes_sig+1, 16, 0);
	test_err_outofrange <= err_burst_over_sig;

	test_attrfifo_flush <= attrfifo_flush_sig;
	test_attrfifo_wrreq <= attrfifo_wrreq_sig;
	test_attrfifo_full <= attrfifo_full_sig;
	test_attrfifo_empty <= attrfifo_empty_sig;
	test_attrfifo_rdack <= attrfifo_rdack_sig;

	test_ringbuff_wrena <= ringbuff_wrena_sig;
	test_ringbuff_wraddr <= slice(ringbuff_wraddr_sig, 16, 0);
	test_ringbuff_rdaddr <= slice(ringbuff_rdaddr_sig, 16, 0);
	test_ringbuff_rddata <= ringbuff_rddata_sig;
	test_rigbuff_free <= slice(ringbuff_free_sig, 16, 0);

	test_pixel_lineend <= pixel_lineend_sig;
	test_pixel_linemask <= pixel_linemask_sig;
	test_pixel_padding <= pixel_padding_sig;
	test_pixel_valid <= pixel_valid_sig;
	test_pixel_data <= pixel_data_sig;

	test_linefifo_full <= linefifo_full_sig;
	test_linefifo_wr <= linefifo_wrreq_sig;
	test_linefifo_rd <= linefifo_rdack_sig;
	test_linefifo_q0 <= slice(conv_ydata_reg, 8, 0);
	test_linefifo_q1 <= slice(conv_ydata_reg, 8, 8);
	test_linefifo_q2 <= slice(conv_ydata_reg, 8, 16);
	test_kernel_cvalid <= kernel_calcdelay_reg(0);

	test_kernel_enable <= kernel_enable_sig;


	-- パラメータ範囲チェック 

	assert (PARAMWORD_POW2_NUMBER >= 5 and PARAMWORD_POW2_NUMBER <= 8)
		report "PARAMWORD_POW2_NUMBER is out of range." severity FAILURE;

	assert (DATABUS_POW2_NUMBER >= 5 and DATABUS_POW2_NUMBER <= 8)
		report "DATABUS_POW2_NUMBER is out of range." severity FAILURE;

	assert (MAXCONVSIZE_POW2_NUMBER >= 8 and MAXCONVSIZE_POW2_NUMBER <= 12)
		report "MAXCONVSIZE_POW2_NUMBER is out of range." severity FAILURE;

	assert (MAXLINEBYTES_POW2_NUMBER >= 10 and MAXLINEBYTES_POW2_NUMBER <= 15)
		report "MAXLINEBYTES_POW2_NUMBER is out of range." severity FAILURE;

	assert (read_burstcount'length <= 11)
		report "Avalon-MM burstcount port width is out of range. Equal or less than 11." severity FAILURE;



	----------------------------------------------------------------------
	-- モジュール全体制御 
	----------------------------------------------------------------------

	init_sig <= init;
	ready <= param_ready_reg;
	error <= error_deviated_reg;
	status <= '0' & error_burstover_reg & error_deviated_reg;


	-- 開始信号と終了信号生成 

	finally_sig <= '1' when is_true(kernel_enable_sig) and is_true(kernel_eof_sig) else '0';
	start_sig <= '1' when is_false(start_1_reg) and is_true(param_loaddone_sig) else '0';

	process (clk, reset) begin
		if is_true(reset) then
			start_1_reg <= '0';
		elsif rising_edge(clk) then
			start_1_reg <= param_loaddone_sig;
		end if;
	end process;


	-- 結果出力とAvalonSTフロー制御 

	kernel_enable_sig <= '0' when is_false(sto_ready) and is_true(kernel_valid_sig) else '1';

	sto_valid <= kernel_valid_sig;
	sto_data <= kernel_data_sig;
	sto_endofline <= kernel_eol_sig;
	sto_endofframe <= kernel_eof_sig;



	----------------------------------------------------------------------
	-- カーネルパラメータ読み込み
	----------------------------------------------------------------------

	param_init_sig <= init_sig when is_true(memread_ready_sig) and is_true(genpixel_ready_sig) else '0';
	param_loaddone_sig <= param_latchena_reg(param_latchena_reg'left);
	param_done <= param_loaddone_sig;


	-- 変換データサイズを取得 

	conv_xmax_sig <= conv_x_size - 1;
	param_xmax_sig <= conv_xmax_sig(param_xmax_sig'range);	-- x_size-1

	conv_ymax_sig <= conv_y_size - 1;
	param_ymax_sig <= conv_ymax_sig(param_ymax_sig'range);	-- y_size-1


	-- バス幅変換 

	gen_param32 : if (PARAMWORD_POW2_NUMBER = 5) generate
		param_bit_sig <= param_data & param_data & param_data & param_data & param_data & param_data & param_data & param_data;
		reg0_latch_sig <= param_latchena_reg(0);
		reg1_latch_sig <= param_latchena_reg(1);
		reg2_latch_sig <= param_latchena_reg(2);
		reg3_latch_sig <= param_latchena_reg(3);
		reg4_latch_sig <= param_latchena_reg(4);
		reg5_latch_sig <= param_latchena_reg(5);
		reg6_latch_sig <= param_latchena_reg(6);
	end generate;

	gen_param64 : if (PARAMWORD_POW2_NUMBER = 6) generate
		param_bit_sig <= param_data & param_data & param_data & param_data;
		reg0_latch_sig <= param_latchena_reg(0);
		reg1_latch_sig <= param_latchena_reg(0);
		reg2_latch_sig <= param_latchena_reg(1);
		reg3_latch_sig <= param_latchena_reg(1);
		reg4_latch_sig <= param_latchena_reg(2);
		reg5_latch_sig <= param_latchena_reg(2);
		reg6_latch_sig <= param_latchena_reg(3);
	end generate;

	gen_param128 : if (PARAMWORD_POW2_NUMBER = 7) generate
		param_bit_sig <= param_data & param_data;
		reg0_latch_sig <= param_latchena_reg(0);
		reg1_latch_sig <= param_latchena_reg(0);
		reg2_latch_sig <= param_latchena_reg(0);
		reg3_latch_sig <= param_latchena_reg(0);
		reg4_latch_sig <= param_latchena_reg(1);
		reg5_latch_sig <= param_latchena_reg(1);
		reg6_latch_sig <= param_latchena_reg(1);
	end generate;

	gen_param256 : if (PARAMWORD_POW2_NUMBER = 8) generate
		param_bit_sig <= param_data;
		reg0_latch_sig <= param_latchena_reg(0);
		reg1_latch_sig <= param_latchena_reg(0);
		reg2_latch_sig <= param_latchena_reg(0);
		reg3_latch_sig <= param_latchena_reg(0);
		reg4_latch_sig <= param_latchena_reg(0);
		reg5_latch_sig <= param_latchena_reg(0);
		reg6_latch_sig <= param_latchena_reg(0);
	end generate;


	-- レジスタラッチと更新 

	process (clk, reset) begin
		if is_true(reset) then
			param_ready_reg <= '1';
			param_latchena_reg <= (0=>'1', others=>'0');
			error_deviated_reg <= '0';

		elsif rising_edge(clk) then
			-- バストランザクションFSMの異常で続行できない 
			if is_true(finally_sig) and is_false(memread_ready_sig) then
				error_deviated_reg <= '1';
			end if;

			if is_true(param_init_sig) or is_true(finally_sig) then
				param_ready_reg <= memread_ready_sig;
				param_latchena_reg <= (0=>'1', others=>'0');
			else
				if is_true(param_valid) and is_false(param_loaddone_sig) then
					param_ready_reg <= '0';

					-- レジスタラッチ選択信号 (シフトレジスタ)
					param_latchena_reg <= shiftin(param_latchena_reg, '0');

					-- reg0:動作モード設定とカーネルスケール値(Sk)のロード 
					if is_true(reg0_latch_sig) then
						inputdatatype_reg	<= param_bit_sig(0*32+25);
						v_doubler_reg		<= param_bit_sig(0*32+24);
						h_doubler_reg		<= param_bit_sig(0*32+23);
						x_reverse_reg		<= param_bit_sig(0*32+22);
						xstep_number_reg	<= slice(param_bit_sig,  2, 0*32+20);
						byte_position_reg	<= slice(param_bit_sig,  2, 0*32+18);
						kernel_sk_reg		<= slice(param_bit_sig, 18, 0*32+ 0);
					end if;

					-- reg1,2,3:カーネル係数(Wk00～Wk22)のロード 
					if is_true(reg1_latch_sig) then
						kernel_wk00_reg <= slice(param_bit_sig, 9, 1*32+18);
						kernel_wk01_reg <= slice(param_bit_sig, 9, 1*32+ 9);
						kernel_wk02_reg <= slice(param_bit_sig, 9, 1*32+ 0);
					end if;
					if is_true(reg2_latch_sig) then
						kernel_wk10_reg <= slice(param_bit_sig, 9, 2*32+18);
						kernel_wk11_reg <= slice(param_bit_sig, 9, 2*32+ 9);
						kernel_wk12_reg <= slice(param_bit_sig, 9, 2*32+ 0);
					end if;
					if is_true(reg3_latch_sig) then
						kernel_wk20_reg <= slice(param_bit_sig, 9, 3*32+18);
						kernel_wk21_reg <= slice(param_bit_sig, 9, 3*32+ 9);
						kernel_wk22_reg <= slice(param_bit_sig, 9, 3*32+ 0);
					end if;

					-- reg4:カーネルローカルバイアス値(Bk)のロード 
					if is_true(reg4_latch_sig) then
						kernel_bk_reg  <= slice(param_bit_sig, 20, 4*32+ 0);
					end if;

					-- reg5:ライン先頭アドレスのロード 
					if is_true(reg5_latch_sig) then
						rd_address_reg <= slice(param_bit_sig, 32, 5*32+ 0);
					end if;

					-- reg6:アドレス増分値のロード 
					if is_true(reg6_latch_sig) then
						address_inc1_reg <= slice(param_bit_sig, address_inc1_reg'length, 6*32+16);
						address_inc0_reg <= slice(param_bit_sig, address_inc0_reg'length, 6*32+ 0);
					end if;

				elsif is_true(update_addr_sig) then
					rd_address_reg <= rd_address_reg + slice_sxt(address_inc0_reg, rd_address_reg'length, 0);

					address_inc0_reg <= address_inc1_reg;	-- ライン更新ごとに増分値を入れ替える 
					address_inc1_reg <= address_inc0_reg;

				end if;

			end if;
		end if;
	end process;

	-- 最終ピクセルバイトオフセットの取得 (値はラインバイト数-1)
	with (xstep_number_reg) select line_lastbytes_sig <=
		('0' & param_xmax_sig & '0')							when PARAM_XSTEP_2,	-- 2step : (x_size-1)*2
		('0' & param_xmax_sig & '0') + ("00" & param_xmax_sig)	when PARAM_XSTEP_3,	-- 3step : (x_size-1)*3
		(param_xmax_sig & "00")									when PARAM_XSTEP_4,	-- 4step : (x_size-1)*4
		("00" & param_xmax_sig)									when others;		-- 1step : (x_size-1)*1



	----------------------------------------------------------------------
	-- ラインデータ読み込み制御
	----------------------------------------------------------------------

	memread_init_sig <= init_sig;
--	memread_ready_sig <= '1' when(state_memread = READIDLE) else '0';
	memread_ready_sig <= '1' when(state_memread = READIDLE and is_false(test_force_error)) else '0';


	-- メモリリードリクエスト

	read_request <= read_request_reg;
	read_complete <= '1' when(state_memread = READDONE) else '0';
	read_address <= rd_address_reg(31 downto ALIGN_ADDR_WIDTH) & repbit('0', ALIGN_ADDR_WIDTH);
	read_burstcount <= ('0' & rd_datanum_reg) + 1;
	read_datavalid_sig <= read_datavalid;

	ringbuff_wraddr_sig <= ringbuff_inaddr_reg;
	ringbuff_wrdata_sig <= read_data;
	ringbuff_wrena_sig <= read_datavalid_sig;
	ringbuff_free_sig <= (pixel_rdindex_reg - ringbuff_inaddr_reg) - TEST_FREE_OFFSET;


	-- バースト長の計算 

	line_beginoffset_sig <= rd_address_reg(ALIGN_ADDR_WIDTH-1 downto 0);
	burstdatabytes_sig <= loadbytes_reg + line_beginoffset_sig;
	burstwordmax_sig <= slice(burstdatabytes_sig, burstwordmax_sig'length, ALIGN_ADDR_WIDTH);
	err_burst_over_sig <= or_reduce(burstdatabytes_sig(burstdatabytes_sig'left downto burstwordmax_sig'length+ALIGN_ADDR_WIDTH));

	rb_almostfull_sig <= '0' when(ringbuff_free_sig > burstwordmax_sig) else '1';

	process (clk, reset) begin
		if is_true(reset) then
			state_memread <= READIDLE;
			error_burstover_reg <= '0';
			read_request_reg <= '0';

		elsif rising_edge(clk) then
			case state_memread is

			-- 開始信号を待つ 
			when READIDLE =>
				if is_true(start_sig) then
					state_memread <= READREQ;
					error_burstover_reg <= '0';
					flag_almostfull_reg <= '0';
					ringbuff_inaddr_reg <= to_vector(TEST_INADDR_INIT, ringbuff_inaddr_reg'length);

					-- ライン読み込みバイト数の確定 (値にはラインバイト数-1を指定する)
					loadbytes_reg <= line_lastbytes_sig;

					-- 読み込みライン数の確定 (値には処理ライン数-1を指定する)
					if is_true(v_doubler_reg) then
						line_count_reg <= slice(param_ymax_sig, line_count_reg'length, 1);	-- y方向アンプーリングはライン数半分 
					else
						line_count_reg <= param_ymax_sig;
					end if;
				end if;


			-- 処理データの読み込み 
			when READREQ =>
				error_burstover_reg <= err_burst_over_sig;
				flag_almostfull_reg <= rb_almostfull_sig;
				ringbuff_index_reg <= ringbuff_inaddr_reg;
				rd_datanum_reg <= burstwordmax_sig;

				-- 初期化リクエストが来ていたら中断する 
				if is_true(memread_init_sig) then
					state_memread <= READIDLE;

				-- 入力リングバッファが開いていたらライン読み込みをリクエスト 
				elsif is_true(attrfifo_empty_sig) or(is_false(attrfifo_full_sig) and is_false(flag_almostfull_reg)) then
					state_memread <= READDATA;
					read_request_reg <= '1';
				end if;


			when READDATA =>
				-- データが送られてきたらリングバッファへ書き込む 
				if is_true(read_datavalid_sig) then
					read_request_reg <= '0';
					ringbuff_inaddr_reg <= ringbuff_inaddr_reg + 1;

					if (rd_datanum_reg = 0) then
						state_memread <= READDONE;
					else
						rd_datanum_reg <= rd_datanum_reg - 1;
					end if;
				end if;

			when READDONE =>
				-- ラインを全て読み終わるまで繰り返す 
				if (line_count_reg = 0) then
					state_memread <= READIDLE;
				else
					state_memread <= READREQ;
				end if;

				line_count_reg <= line_count_reg - 1;
				flag_almostfull_reg <= '1';

			end case;
		end if;
	end process;

	update_addr_sig <= '1' when(state_memread = READDONE) else '0';		-- READDONEで次のアドレスを計算 

	attrfifo_wrreq_sig <= update_addr_sig;								-- アドレス更新と同時に属性FIFOへキュー 
	attrfifo_data_sig <= line_beginoffset_sig & ringbuff_index_reg;		-- リングバッファインデックスと開始バイトを格納 


	-- 属性FIFOのインスタンス 

	u_attrfifo : scfifo
	generic map (
		lpm_type			=> "scfifo",
		lpm_showahead		=> "ON",
		lpm_numwords		=> 2**ATTRFIFO_WIDTH,
		lpm_widthu			=> ATTRFIFO_WIDTH,
		lpm_width			=> attrfifo_data_sig'length,
		add_ram_output_register => FIFO_SPEED_OPTION,
		overflow_checking	=> FIFO_FLOW_CHECKING,
		underflow_checking	=> FIFO_FLOW_CHECKING
	)
	port map (
		clock	=> clk,
		sclr	=> attrfifo_flush_sig,

		wrreq	=> attrfifo_wrreq_sig,
		data	=> attrfifo_data_sig,
		full	=> attrfifo_full_sig,

		rdreq	=> attrfifo_rdack_sig,	-- ack
		q		=> attrfifo_q_sig,
		empty	=> attrfifo_empty_sig
	);


	-- リングバッファのインスタンス 

	u_ringbuff : altsyncram
	generic map (
		intended_device_family	=> DEVICE_FAMILY,	-- QuestaでSimする場合はデバイス指定が必要 
		lpm_type				=> "altsyncram",
		operation_mode			=> "DUAL_PORT",
		clock_enable_input_a	=> "NORMAL",
		clock_enable_input_b	=> "NORMAL",
		clock_enable_output_b	=> "NORMAL",
		address_aclr_b			=> "NONE",
		address_reg_b			=> "CLOCK1",
		outdata_aclr_b			=> "NONE",
		outdata_reg_b			=> "CLOCK1",
		power_up_uninitialized	=> "FALSE",
		numwords_a				=> 2**BUFF_INADDR_WIDTH,
		widthad_a				=> BUFF_INADDR_WIDTH,
		width_a					=> DATABUS_BITWIDTH,
		width_byteena_a			=> 1,
		numwords_b				=> 2**(BUFF_INADDR_WIDTH+ALIGN_ADDR_WIDTH),
		widthad_b				=> BUFF_INADDR_WIDTH+ALIGN_ADDR_WIDTH,
		width_b					=> 8
	)
	port map (
		clock0		=> clk,
		clocken0	=> '1',
		address_a	=> ringbuff_wraddr_sig,
		data_a		=> ringbuff_wrdata_sig,
		wren_a		=> ringbuff_wrena_sig,

		clock1		=> clk,
		clocken1	=> ringbuff_rdclkena_sig,
		address_b	=> ringbuff_rdaddr_sig,
		q_b			=> ringbuff_rddata_sig
	);



	----------------------------------------------------------------------
	-- 2次元データ出力制御 (ラインデータを画像イメージに成形)
	----------------------------------------------------------------------
	-- loadbytes_reg : 1ラインのバイト数-1 (start_sigアサートでラッチされる固定値)
	-- attrfifo_flush_sig : 属性FIFOの初期化 
	-- attrfifo_rdack_sig : 属性FIFO更新アクノリッジ(FIFOはclkena制御はされないので、ストール制御はこの信号で処理する)
	-- attrfifo_q_sig : 属性FIFOのデータ。リングバッファインデックスと開始バイトオフセットを示す。
	-- ringbuff_rdclkena_sig : リングバッファ読み出しクロックイネーブル信号 
	-- ringbuff_rdaddr_sig : リングバッファの読み出しアドレス信号 
	-- ringbuff_rddata_sig : リングバッファの読み出しデータ(2クロックの固定レイテンシ)

	genpixel_init_sig <= init_sig;
	genpixel_ready_sig <= '1' when(state_genpixel = PIXELIDLE) else '0';
	genpixel_enable_sig <= kernel_enable_sig;	-- スキャンブロックのストール制御はカーネル演算と同期 


	-- 属性FIFOとリングバッファの読み出しリクエスト 

	attrfifo_flush_sig <= start_sig;			-- 全体開始シグナルで属性FIFOを初期化 
	attrfifo_rdack_sig <= '1' when is_true(genpixel_enable_sig) and is_true(lineend_sig) and is_false(pl_hold_reg) and is_false(y_hold_reg) else '0';

	pixel_rdaddr_sig <= pixel_rdaddr_reg + pixel_rdoffset_reg;
	ringbuff_rdaddr_sig <= (pixel_rdindex_reg & repbit('0', ALIGN_ADDR_WIDTH)) + pixel_rdaddr_sig;
	ringbuff_rdclkena_sig <= genpixel_enable_sig;


	process (clk, reset) begin
		if is_true(reset) then
			state_genpixel <= PIXELIDLE;

		elsif rising_edge(clk) then
			if is_true(genpixel_init_sig) then
				state_genpixel <= PIXELIDLE;

			else
				case (state_genpixel) is

				-- 開始信号を待つ 
				when PIXELIDLE =>
					if is_true(start_sig) then
						state_genpixel <= PIXELWAIT;

						-- スキャンパラメータの確定 
						ref_x_counter <= conv_integer(param_xmax_sig);
						y_counter <= conv_integer(param_ymax_sig);
						padding_zero_reg <= padding_mode(0);
						padding_ena_reg <= padding_mode(1);
						pl_hold_reg <= padding_mode(1);
						y_hold_reg <= v_doubler_reg;

						-- 読み出し増分値の確定 
						case (xstep_number_reg) is
						when PARAM_XSTEP_2 => rdaddr_incvalue <= 2;	-- 2step
						when PARAM_XSTEP_3 => rdaddr_incvalue <= 3;	-- 3step
						when PARAM_XSTEP_4 => rdaddr_incvalue <= 4;	-- 4step
						when others => rdaddr_incvalue <= 1;		-- 1step
						end case;
					end if;


				-- ピクセルデータFIFOの受信待ち 
				when PIXELWAIT =>
					if is_true(genpixel_enable_sig) and is_false(attrfifo_empty_sig) then
						if is_true(padding_ena_reg) then
							state_genpixel <= PIXELBEGINPADDING;
						else
							state_genpixel <= PIXELLOOP;
						end if;

						-- ライン初期値の確定 
						x_counter <= ref_x_counter;
						x_hold_reg <= h_doubler_reg;

						-- アドレス初期値の確定 
						if is_true(x_reverse_reg) then
							pixel_rdaddr_reg <= slice(loadbytes_reg, pixel_rdaddr_reg'length, 0);	-- loadbytes_regはstart_sigで固定
						else
							pixel_rdaddr_reg <= (others=>'0');
						end if;

						-- リングバッファアドレスの確定 
						pixel_rdindex_reg <= slice(attrfifo_q_sig, pixel_rdindex_reg'length, 0);
						pixel_rdoffset_reg <= slice(attrfifo_q_sig, pixel_rdoffset_reg'length, pixel_rdindex_reg'length);
					end if;


				-- ピクセルデータを2次元画像に成形 
				when PIXELBEGINPADDING =>
					-- ライン先端パディングピクセルの付加 
					if is_true(genpixel_enable_sig) then
						state_genpixel <= PIXELLOOP;
					end if;

				when PIXELLOOP =>
					-- ラインループ 
					if is_true(genpixel_enable_sig) then
						if (x_counter = 0) then
							if is_true(padding_ena_reg) then
								state_genpixel <= PIXELENDPADDING;
							else
								state_genpixel <= PIXELFINALLY;
							end if;
						else
							x_counter <= x_counter - 1;
							x_hold_reg <= x_hold_reg xor h_doubler_reg;

							-- 読み出しアドレス更新 
							if is_false(x_hold_reg) then
								if is_true(x_reverse_reg) then
									pixel_rdaddr_reg <= pixel_rdaddr_reg - rdaddr_incvalue;
								else
									pixel_rdaddr_reg <= pixel_rdaddr_reg + rdaddr_incvalue;
								end if;
							end if;
						end if;
					end if;

				when PIXELENDPADDING =>
					-- ライン末端パディングピクセルの付加 
					if is_true(genpixel_enable_sig) then
						state_genpixel <= PIXELFINALLY;

						-- もし最終ラインなら末尾パディングラインをリクエスト 
						if (y_counter = 0) then
							pl_hold_reg <= not pl_hold_reg;	-- 最終ラインの末端でパディングリクエスト、末尾パディングラインの末端でクリア 
						end if;
					end if;

				when PIXELFINALLY =>
					-- ライン終了処理と次のラインの更新処理 
					if is_true(genpixel_enable_sig) then
						if is_true(pl_hold_reg) then		-- パディングラインのダブルスキャン 
							state_genpixel <= PIXELWAIT;
							if (y_counter /= 0) then		-- 先頭パディングラインであればフラグをクリア 
								pl_hold_reg <= '0';
							end if;
						else
							if (y_counter = 0) then
								state_genpixel <= PIXELIDLE;
							else
								state_genpixel <= PIXELWAIT;
								y_counter <= y_counter - 1;
								y_hold_reg <= y_hold_reg xor v_doubler_reg;
							end if;
						end if;
					end if;

				end case;
			end if;
		end if;
	end process;

	lineend_sig <= '1' when(state_genpixel = PIXELFINALLY) else '0';
	frameend_sig <= '1' when is_true(lineend_sig) and(is_false(pl_hold_reg) and y_counter = 0) else '0';


	-- リングバッファ出力遅延の調整とパディングデータのマスク 

	p_valid_sig <= '1' when(state_genpixel = PIXELBEGINPADDING or state_genpixel = PIXELLOOP or state_genpixel = PIXELENDPADDING) else '0';
	p_linemask_sig <= '1' when is_true(pl_hold_reg) and is_true(padding_zero_reg) else '0';
	p_padding_sig <= '1' when(state_genpixel = PIXELBEGINPADDING or state_genpixel = PIXELENDPADDING) else '0';

	process (clk) begin
		if rising_edge(clk) then
			if is_true(param_ready_reg) then			-- パラメータブロックが停止している時にクリア 
				p_frameend_delay_reg <= (others=>'0');
				p_lineend_delay_reg <= (others=>'0');
				p_linemask_delay_reg <= (others=>'0');
				p_padding_delay_reg <= (others=>'0');
				p_valid_delay_reg <= (others=>'0');

			elsif is_true(genpixel_enable_sig) then
				p_frameend_delay_reg <= shiftin(p_frameend_delay_reg, frameend_sig);
				p_lineend_delay_reg <= shiftin(p_lineend_delay_reg, lineend_sig);
				p_linemask_delay_reg <= shiftin(p_linemask_delay_reg, p_linemask_sig);
				p_padding_delay_reg <= shiftin(p_padding_delay_reg, p_padding_sig);
				p_valid_delay_reg <= shiftin(p_valid_delay_reg, p_valid_sig);

			end if;

		end if;
	end process;

	pixel_lineend_sig <= shiftout(p_lineend_delay_reg);
	pixel_frameend_sig <= shiftout(p_frameend_delay_reg);
	pixel_linemask_sig <= shiftout(p_linemask_delay_reg);
	pixel_padding_sig <= shiftout(p_padding_delay_reg);
	pixel_valid_sig <= shiftout(p_valid_delay_reg);

	pixel_data_sig <= (others=>'0') when is_true(pixel_linemask_sig) else ringbuff_rddata_sig;



	----------------------------------------------------------------------
	-- 3x3カーネル演算 
	----------------------------------------------------------------------
	-- pixel_data_sig : ピクセルデータ 
	-- pixel_valid_sig : １ラインのピクセル送出中は連続してアサートされる。ラインの間は1クロック以上ネゲートされる。 
	-- pixel_padding_sig : １ラインのパディングピクセル（padding_ena_reg=1のときにライン両端）でアサートされる。 
	-- pixel_lineend_sig : ラインの最終ピクセルを指示 
	-- pixel_frameend_sig : フレームの最後のピクセルを指示 
	-- kernel_data_sig : カーネル演算結果 
	-- kernel_valid_sig : kernel_data_sigの有効信号 
	-- kernel_eol_sig : ラインの最終データを指示 
	-- kernel_eof_sig : フレームの最終データを指示 

	-- カーネル計算レジスタの確定 

	process (clk) begin
		if rising_edge(clk) then
			-- 全体開始信号でカーネルモード確定 
			if is_true(start_sig) then
				kernel_bytepack_reg <= bytepacking;
			end if;

		end if;
	end process;


	-- カーネル計算用のタイミングを生成 

	kernel_calcvalid_sig <= kernel_linedelay_reg(1) and kernel_pixdelay_reg(1) when is_true(pixel_valid_sig) else '0';	-- 演算有効画素を示す 
	kernel_eolvalid_sig <= pixel_lineend_sig when is_true(kernel_calcvalid_sig) else '0';
	kernel_eofvalid_sig <= pixel_frameend_sig when is_true(kernel_calcvalid_sig) else '0';

	process (clk) begin
		if rising_edge(clk) then
			if is_true(param_ready_reg) then			-- パラメータブロックが停止している時にクリア 
				kernel_linedelay_reg <= (others=>'0');
				kernel_pixdelay_reg <= (others=>'0');
				kernel_calcdelay_reg <= (others=>'0');
				kernel_eoldelay_reg <= (others=>'0');
				kernel_eofdelay_reg <= (others=>'0');

			elsif is_true(kernel_enable_sig) then
				-- 3x3の画素が揃うまで有効画素信号をマスク 
				if is_true(pixel_lineend_sig) then
					kernel_linedelay_reg <= shiftin(kernel_linedelay_reg, '1');
					kernel_pixdelay_reg <= (others=>'0');
				elsif is_true(pixel_valid_sig) then
					kernel_pixdelay_reg <= shiftin(kernel_pixdelay_reg, '1');
				end if;

				-- カーネル演算レイテンシの遅延 (KERNEL_CONV_DELAY+1) 
				kernel_calcdelay_reg <= shiftin(kernel_calcdelay_reg, kernel_calcvalid_sig);
				kernel_eoldelay_reg <= shiftin(kernel_eoldelay_reg, kernel_eolvalid_sig);
				kernel_eofdelay_reg <= shiftin(kernel_eofdelay_reg, kernel_eofvalid_sig);

				-- ピクセルデータのラッチ 
				if is_true(pixel_padding_sig) then
					if is_true(padding_zero_reg) then
						conv_ydata_reg <= (others=>'0');	-- ライン両端のパディングピクセルを0にする 
					elsif is_false(pixel_lineend_sig) then
						conv_ydata_reg <= conv_ydata_sig;	-- ライン末端のパディングピクセルはそのまま保持 
					end if;
				else
					conv_ydata_reg <= conv_ydata_sig;
				end if;

				-- ラインFIFO書き込み信号 
				if is_true(pixel_valid_sig) and is_false(pixel_padding_sig) then
					linefifo_wrreq_reg <= slice((kernel_linedelay_reg & '1'), linefifo_wrreq_reg'length, 0);
				else
					linefifo_wrreq_reg <= (others=>'0');
				end if;
			end if;

		end if;
	end process;

	kernel_valid_sig <= shiftout(kernel_calcdelay_reg);
	kernel_eol_sig <= shiftout(kernel_eoldelay_reg);
	kernel_eof_sig <= shiftout(kernel_eofdelay_reg);


	-- ラインFIFOのインスタンス 

	linefifo_flush_sig <= start_sig;		-- 全体開始シグナルでラインFIFOを初期化 

	conv_ydata_sig(7 downto 0) <= pixel_data_sig;
	linefifo_wrreq_sig <= linefifo_wrreq_reg when is_true(kernel_enable_sig) else (others=>'0');
	linefifo_rdack_sig <= kernel_linedelay_reg when is_true(kernel_enable_sig) and is_true(pixel_valid_sig) and is_false(pixel_padding_sig) else (others=>'0');

	gen_linefifo : for i in 0 to 1 generate
		u : scfifo
		generic map (
			lpm_type			=> "scfifo",
			lpm_showahead		=> "ON",
			lpm_numwords		=> 2**MAXCONVSIZE_POW2_NUMBER,
			lpm_widthu			=> MAXCONVSIZE_POW2_NUMBER,
			lpm_width			=> 8,
			add_ram_output_register => FIFO_SPEED_OPTION,
			overflow_checking	=> FIFO_FLOW_CHECKING,
			underflow_checking	=> FIFO_FLOW_CHECKING
		)
		port map (
			clock	=> clk,
			sclr	=> linefifo_flush_sig,

			wrreq	=> linefifo_wrreq_sig(i),
			data	=> conv_ydata_reg(i*8+7 downto i*8+0),
			full	=> linefifo_full_sig(i),

			rdreq	=> linefifo_rdack_sig(i),	-- ack
			q		=> conv_ydata_sig((i+1)*8+7 downto (i+1)*8+0),
			empty	=> linefifo_empty_sig(i)
		);
	end generate;


	-- カーネル演算器のインスタンス (8クロックの固定パイプライン) 

	u_conv : peridot_cnn_kernel_conv
	port map (
		clk 		=> clk,
		enable		=> kernel_enable_sig,

		sign_ena	=> inputdatatype_reg,
		pack_ena	=> kernel_bytepack_reg,
		byte_pos	=> byte_position_reg,
		wk00		=> kernel_wk00_reg,
		wk01		=> kernel_wk01_reg,
		wk02		=> kernel_wk02_reg,
		wk10		=> kernel_wk10_reg,
		wk11		=> kernel_wk11_reg,
		wk12		=> kernel_wk12_reg,
		wk20		=> kernel_wk20_reg,
		wk21		=> kernel_wk21_reg,
		wk22		=> kernel_wk22_reg,
		bk			=> kernel_bk_reg,
		sk			=> kernel_sk_reg,

		y0			=> conv_ydata_reg(23 downto 16),	-- conv_ydata_reg(23..16) : line<n-2>
		y1			=> conv_ydata_reg(15 downto  8),	-- conv_ydata_reg(15.. 8) : line<n-1>
		y2			=> conv_ydata_reg( 7 downto  0),	-- conv_ydata_reg( 7.. 0) : line<n>

		result		=> kernel_data_sig
	);



end RTL;
