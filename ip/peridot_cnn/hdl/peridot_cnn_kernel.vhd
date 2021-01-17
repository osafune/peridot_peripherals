-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - kernel
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/07/31 -> 2020/08/19
--            : 2020/09/19 (FIXED)
--
-- ===================================================================
--
-- The MIT License (MIT)
-- Copyright (c) 2020 J-7SYSTEM WORKS LIMITED.
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

-- ・実装残り
-- ■ 全体終了後にreadyにする処理 
-- ■ memreadよりもgenpixelが先に終了する異常状態のフック 
-- ■ パラメータ読み込みバスを分離 
-- □ メモリリードFSMの構成を他のモジュールと同様に修正(現状での実機動作を確認後)

-- ・検証残り
-- ■ INITアボートの動作(正しく復帰するか？タイミングを勘違いしている部分はないか？)
-- ■ ストール制御の可否(backpressure制御が行われるか？) → 最低限の動作を確認 
-- ■ ラインスキャン動作の確認 → 最低限の動作を確認 
-- ■ カーネル演算の一致(単位行列のみ確認する) → 単位行列部分の対応はあってる 
-- ■ エラーインジェクションテスト
-- □ 32bitで確認したらgenericを変えて確認する(ライン長を変更してsimが変わらないかどうか見る)

-- ・リソース概算
--  870LE + 6DSP + 3M9k (32bit幅,256x256,±1kbyte,FIFOフローチェックOFF時)
--  930LE + 6DSP + 4M9k (32bit幅,512x512,±32kbyte時)
-- 1000LE + 6DSP +16M9k (256bit幅,2048x2048,±32kbyte時)

-- status(0) : Error, Bus access cannot be continued.
-- status(1) : Warning, Load datalength is out of range.
-- status(2) : Warning, Saturation occurs in kernel operation.

-- padding_mode(0) : padding enable(=1)
-- padding_mode(1) : zero padding(=1)
--                 : normal padding(=0)
-- unpooling_mode(0) : horizontal double(=1)
-- unpooling_mode(1) : vertical double(=1)
-- precision : high precision(=1) * 3x3の結果を s1.int9.dec8 で取得する / 通常は s1.int11.dec6
-- decimal_pos : 19bit decimal places(=00)
--             : 15bit decimal places(=01)
--             : 11bit decimal places(=10)
--             :  7bit decimal places(=11)


-- VHDL 1993 / IEEE 1076-1993
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_misc.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity peridot_cnn_kernel is
	generic(
		PARAMWORD_POW2_NUMBER	: integer := 5;		-- パラメータワード幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		MAXCONVSIZE_POW2_NUMBER	: integer := 9;		-- 畳み込み画像の最大値 (8:256x256 / 9:512x512 / 10:1024x1024 / 11:2048x2048)
		MAXLINEBYTES_POW2_NUMBER: integer := 15;	-- ラインデータ増分値の最大バイト数 (10:±1kbyte ～ 15:±32kbyte)
		FIFO_FLOW_CHECKING		: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 

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
		test_attrfifo_data	: out std_logic_vector(6 downto 0);
		test_attrfifo_full	: out std_logic;
		test_attrfifo_empty	: out std_logic;
		test_attrfifo_rdack	: out std_logic;
		test_ringbuff_wrena	: out std_logic;
		test_ringbuff_wraddr: out std_logic_vector(15 downto 0);
		test_ringbuff_rdaddr: out std_logic_vector(15 downto 0);
		test_ringbuff_rddata: out std_logic_vector(7 downto 0);
		test_pixel_lineend	: out std_logic;
		test_pixel_padding	: out std_logic;
		test_pixel_valid	: out std_logic;
		test_pixel_data		: out std_logic_vector(7 downto 0);
		test_linefifo_empty	: out std_logic_vector(1 downto 0);
		test_linefifo_wr	: out std_logic_vector(1 downto 0);
		test_linefifo_rd	: out std_logic_vector(1 downto 0);
		test_linefifo_q0	: out std_logic_vector(7 downto 0);
		test_linefifo_q1	: out std_logic_vector(7 downto 0);
		test_linefifo_q2	: out std_logic_vector(7 downto 0);
		test_kernel_cvalid	: out std_logic;
		test_multadd_res2	: out std_logic_vector(18 downto 0);
		test_multadd_res1	: out std_logic_vector(18 downto 0);
		test_multadd_res0	: out std_logic_vector(18 downto 0);
		test_multadd_sat	: out std_logic_vector(17 downto 0);
		test_calcsat_valid	: out std_logic;
		test_err_opsat		: out std_logic;
		test_mult_res		: out std_logic_vector(35 downto 0);
		test_kernel_enable	: out std_logic;


		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: in  std_logic := '0';
		ready			: out std_logic;
		error			: out std_logic;						-- errorがアサートされたらreadyには戻らない 
		status			: out std_logic_vector(2 downto 0);
		conv_x_size		: in  std_logic_vector(MAXCONVSIZE_POW2_NUMBER downto 0);
		conv_y_size		: in  std_logic_vector(MAXCONVSIZE_POW2_NUMBER downto 0);
		padding_mode	: in  std_logic_vector(1 downto 0);
		unpooling_mode	: in  std_logic_vector(1 downto 0);
		precision		: in  std_logic;
		decimal_pos		: in  std_logic_vector(1 downto 0);

		param_data		: in  std_logic_vector(2**PARAMWORD_POW2_NUMBER-1 downto 0);
		param_valid		: in  std_logic;
		param_done		: out std_logic;

		read_request	: out std_logic;
		read_complete	: out std_logic;
		read_address	: out std_logic_vector(31 downto 0);
		read_burstcount	: out std_logic_vector(MAXCONVSIZE_POW2_NUMBER-(DATABUS_POW2_NUMBER-3) downto 0);
		read_data		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		read_datavalid	: in  std_logic;

		sto_ready		: in  std_logic;
		sto_valid		: out std_logic;
		sto_data		: out std_logic_vector(31 downto 0);
		sto_endofline	: out std_logic;
		sto_endofframe	: out std_logic
	);
end peridot_cnn_kernel;

architecture RTL of peridot_cnn_kernel is
	function is_true(S:std_logic) return boolean is begin return(S='1'); end;
	function is_false(S:std_logic) return boolean is begin return(S='0'); end;
	function to_vector(N,W:integer) return std_logic_vector is begin return conv_std_logic_vector(N,W); end;
	function repbit(S:std_logic; W:integer) return std_logic_vector is variable a:std_logic_vector(W-1 downto 0); begin a:=(others=>S); return a; end;
	function shiftin(V:std_logic_vector; S:std_logic) return std_logic_vector is begin return V(V'left-1 downto 0)&S; end;
	function shiftout(V:std_logic_vector) return std_logic is begin return V(V'left); end;

	function slice(V:std_logic_vector; W,N:integer) return std_logic_vector is variable a:std_logic_vector(V'length+W+N-2 downto 0);
	begin a:=repbit('0',W+N-1)&V; return a(W+N-1 downto N); end;
	function slice_sxt(V:std_logic_vector; W,N:integer) return std_logic_vector is variable a:std_logic_vector(V'length+W+N-2 downto 0);
	begin a:=repbit(V(V'left),W+N-1)&V; return a(W+N-1 downto N); end;

	-- モジュール固定値 
	constant PARAM_BLOCK_SIZE	: integer := 8;			-- パラメータデスクリプタのワード数(32bit×8ワードで固定)
	constant BUFF_INDEX_WIDTH	: integer := 2;			-- リングバッファのインデックス幅(2^RINGINDEX_WIDTHがリングバッファの要素数)
	constant GENPIXEL_DELAY		: integer := 2;			-- ピクセルデータの出力レイテンシ(2クロックで固定)
	constant KERNEL_CALC_DELAY	: integer := 6;			-- カーネル計算の出力レイテンシ(6クロックで固定)
	constant KERNEL_OPSAT_TAP	: integer := 4-1;		-- カーネル計算の飽和演算のディレイタップ(4クロック目で固定)
	constant ALIGN_ADDR_WIDTH	: integer := DATABUS_POW2_NUMBER-3;		-- ワード境界のアドレスビット幅 
	constant DATABUS_BITWIDTH	: integer := 2**DATABUS_POW2_NUMBER;	-- データバス幅 
	constant BUFF_INADDR_WIDTH	: integer := MAXCONVSIZE_POW2_NUMBER-ALIGN_ADDR_WIDTH;	-- 入力リングバッファのアドレスビット幅 

	-- xstepレジスタの設定値 
	constant PARAM_XSTEP_1		: std_logic_vector(1 downto 0) := "00";	-- 増分値+1の設定値 *デフォルト 
	constant PARAM_XSTEP_2		: std_logic_vector(1 downto 0) := "01";	-- 増分値+2の設定値 
	constant PARAM_XSTEP_3		: std_logic_vector(1 downto 0) := "10";	-- 増分値+3の設定値 
	constant PARAM_XSTEP_4		: std_logic_vector(1 downto 0) := "11";	-- 増分値+4の設定値 

	-- decposの設定値 
	constant PARAM_DECPOS_19	: std_logic_vector(1 downto 0) := "00";	-- 19bit小数モード *デフォルト 
	constant PARAM_DECPOS_15	: std_logic_vector(1 downto 0) := "01";	-- 15bit小数モード 
	constant PARAM_DECPOS_11	: std_logic_vector(1 downto 0) := "10";	-- 11bit小数モード 
	constant PARAM_DECPOS_7		: std_logic_vector(1 downto 0) := "11";	--  7bit小数モード 


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

	signal error_deviated_reg	: std_logic;
	signal rd_address_reg		: std_logic_vector(31 downto 0);
	signal address_inc_reg		: std_logic_vector(MAXLINEBYTES_POW2_NUMBER downto 0);
	signal xstep_number_reg		: std_logic_vector(1 downto 0);
	signal x_reverse_reg		: std_logic;
	signal kernel_ws_reg		: std_logic_vector(17 downto 0);
	signal kernel_wk00_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk10_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk20_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk01_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk11_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk21_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk02_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk12_reg		: std_logic_vector(8 downto 0);
	signal kernel_wk22_reg		: std_logic_vector(8 downto 0);
	signal line_lastbytes_sig	: std_logic_vector(MAXCONVSIZE_POW2_NUMBER+2-1 downto 0);
	signal update_addr_sig		: std_logic;

	-- ラインデータ読み込み制御ブロック 
	type DEF_STATE_MEMREAD is (READIDLE, READREQ, READDATA, READDONE);
	signal state_memread : DEF_STATE_MEMREAD;
	signal line_counter			: integer range 0 to 2**param_ymax_sig'length-1;
	signal memread_init_sig		: std_logic;
	signal memread_ready_sig	: std_logic;
	signal read_request_reg		: std_logic;
	signal error_burstover_reg	: std_logic;
	signal loadbytes_reg		: std_logic_vector(line_lastbytes_sig'range);
	signal rd_datanum_reg		: std_logic_vector(BUFF_INADDR_WIDTH-1 downto 0);

	signal line_beginoffset_sig	: std_logic_vector(ALIGN_ADDR_WIDTH-1 downto 0);
	signal burstdatabytes_sig	: std_logic_vector(loadbytes_reg'range);
	signal burstwordmax_sig		: std_logic_vector(rd_datanum_reg'range);
	signal read_datavalid_sig	: std_logic;
	signal err_burst_over_sig	: std_logic;

	signal ringbuff_index_reg	: std_logic_vector(BUFF_INDEX_WIDTH-1 downto 0);
	signal ringbuff_inaddr_reg	: std_logic_vector(BUFF_INADDR_WIDTH-1 downto 0);
	signal ringbuff_wraddr_sig	: std_logic_vector(BUFF_INADDR_WIDTH+BUFF_INDEX_WIDTH-1 downto 0);
	signal ringbuff_wrdata_sig	: std_logic_vector(read_data'range);
	signal ringbuff_wrena_sig	: std_logic;
	signal ringbuff_rdaddr_sig	: std_logic_vector(MAXCONVSIZE_POW2_NUMBER+BUFF_INDEX_WIDTH-1 downto 0);
	signal ringbuff_rddata_sig	: std_logic_vector(7 downto 0);
	signal ringbuff_rdclkena_sig: std_logic;

	signal attrfifo_flush_sig	: std_logic;
	signal attrfifo_wrreq_sig	: std_logic;
	signal attrfifo_data_sig	: std_logic_vector(ALIGN_ADDR_WIDTH+BUFF_INDEX_WIDTH-1 downto 0);
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
	signal x_unpooling_ena_reg	: std_logic;
	signal y_unpooling_ena_reg	: std_logic;
	signal pixel_rdaddr_reg		: std_logic_vector(MAXCONVSIZE_POW2_NUMBER-1 downto 0);
	signal pixel_rdindex_sig	: std_logic_vector(ringbuff_index_reg'range);
	signal pixel_rdoffset_sig	: std_logic_vector(line_beginoffset_sig'range);

	signal p_padding_sig		: std_logic;
	signal p_valid_sig			: std_logic;
	signal p_frameend_delay_reg	: std_logic_vector(GENPIXEL_DELAY-2 downto 0);
	signal p_lineend_delay_reg	: std_logic_vector(GENPIXEL_DELAY-2 downto 0);
	signal p_padding_delay_reg	: std_logic_vector(GENPIXEL_DELAY-1 downto 0);
	signal p_valid_delay_reg	: std_logic_vector(GENPIXEL_DELAY-1 downto 0);
	signal pixel_frameend_sig	: std_logic;
	signal pixel_lineend_sig	: std_logic;
	signal pixel_padding_sig	: std_logic;
	signal pixel_valid_sig		: std_logic;
	signal pixel_data_sig		: std_logic_vector(ringbuff_rddata_sig'range);

	-- カーネル演算ブロック 
	signal kernel_enable_sig	: std_logic;
	signal kernel_calcvalid_sig	: std_logic;
	signal kernel_eofvalid_sig	: std_logic;
	signal kernel_eolvalid_sig	: std_logic;
	signal kernel_calcdelay_reg	: std_logic_vector(KERNEL_CALC_DELAY-1 downto 0);
	signal kernel_eofdelay_reg	: std_logic_vector(KERNEL_CALC_DELAY-1 downto 0);
	signal kernel_eoldelay_reg	: std_logic_vector(KERNEL_CALC_DELAY-1 downto 0);
	signal kernel_linedelay_reg	: std_logic_vector(1 downto 0);
	signal kernel_pixdelay_reg	: std_logic_vector(1 downto 0);
	signal kernal_precision_reg	: std_logic;
	signal kernel_decpos_reg	: std_logic_vector(1 downto 0);
	signal error_opsat_reg		: std_logic;
	signal err_kernel_opsat_sig	: std_logic;
	signal linefifo_flush_sig	: std_logic;
	signal linefifo_q_sig		: std_logic_vector(3*8-1 downto 0);
	signal linefifo_queue_sig	: std_logic_vector(2 downto 0);
	signal linefifo_empty_sig	: std_logic_vector(1 downto 0);

	signal kernel_sat0_sig		: std_logic;
	signal kernel_sat1_sig		: std_logic;
	signal multadd_dataa_sig	: std_logic_vector(3*3*8-1 downto 0);
	signal multadd_datab_sig	: std_logic_vector(3*3*9-1 downto 0);
	signal multadd_result_sig	: std_logic_vector(3*19-1 downto 0);
	signal multadd_sum_sig		: std_logic_vector(19+2-1 downto 0);
	signal multadd_sum_reg		: std_logic_vector(multadd_sum_sig'range);
	signal multadd_sat_sig		: std_logic_vector(17 downto 0);
	signal mult_result_sig		: std_logic_vector(35 downto 0);
	signal kernel_data_sig		: std_logic_vector(31 downto 0);
	signal kernel_valid_sig		: std_logic;
	signal kernel_eof_sig		: std_logic;
	signal kernel_eol_sig		: std_logic;


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
	test_attrfifo_data <= slice(attrfifo_data_sig, 7, 0);
	test_attrfifo_full <= attrfifo_full_sig;
	test_attrfifo_empty <= attrfifo_empty_sig;
	test_attrfifo_rdack <= attrfifo_rdack_sig;

	test_ringbuff_wrena <= ringbuff_wrena_sig;
	test_ringbuff_wraddr <= slice(ringbuff_wraddr_sig, 16, 0);
	test_ringbuff_rdaddr <= slice(ringbuff_rdaddr_sig, 16, 0);
	test_ringbuff_rddata <= ringbuff_rddata_sig;

	test_pixel_lineend <= pixel_lineend_sig;
	test_pixel_padding <= pixel_padding_sig;
	test_pixel_valid <= pixel_valid_sig;
	test_pixel_data <= pixel_data_sig;

	test_linefifo_empty <= linefifo_empty_sig;
	test_linefifo_wr <= linefifo_queue_sig(1 downto 0);
	test_linefifo_rd <= linefifo_queue_sig(2 downto 1);
	test_linefifo_q0 <= slice(linefifo_q_sig, 8, 0);
	test_linefifo_q1 <= slice(linefifo_q_sig, 8, 8);
	test_linefifo_q2 <= slice(linefifo_q_sig, 8, 16);
	test_kernel_cvalid <= kernel_calcvalid_sig;

	test_multadd_res2 <= slice(multadd_result_sig, 19, 2*19);	-- line<n-2>
	test_multadd_res1 <= slice(multadd_result_sig, 19, 1*19);	-- line<n-1>
	test_multadd_res0 <= slice(multadd_result_sig, 19, 0*19);	-- line<n>
	test_multadd_sat <= multadd_sat_sig;
	test_calcsat_valid <= kernel_calcdelay_reg(KERNEL_OPSAT_TAP);
	test_err_opsat <= err_kernel_opsat_sig;
	test_mult_res <= mult_result_sig;

	test_kernel_enable <= kernel_enable_sig;


	-- パラメータ範囲チェック 

	assert (PARAMWORD_POW2_NUMBER >= 5 and PARAMWORD_POW2_NUMBER <= 8)
		report "PARAMWORD_POW2_NUMBER is out of range.";

	assert (DATABUS_POW2_NUMBER >= 5 and DATABUS_POW2_NUMBER <= 8)
		report "DATABUS_POW2_NUMBER is out of range.";

	assert (MAXCONVSIZE_POW2_NUMBER >= 8 and MAXCONVSIZE_POW2_NUMBER <= 11)
		report "MAXCONVSIZE_POW2_NUMBER is out of range.";

	assert (MAXLINEBYTES_POW2_NUMBER >= 10 and MAXLINEBYTES_POW2_NUMBER <= 15)
		report "MAXLINEBYTES_POW2_NUMBER is out of range.";

	assert (read_burstcount'length <= 11)
		report "Avalon-MM burstcount port width is out of range. Less then 11.";



	----------------------------------------------------------------------
	-- モジュール全体制御 
	----------------------------------------------------------------------

	init_sig <= init;
	ready <= param_ready_reg;
	error <= error_deviated_reg;
	status <= error_opsat_reg & error_burstover_reg & error_deviated_reg;


	-- 開始信号と終了信号生成 

	finally_sig <= kernel_eof_sig when is_true(kernel_enable_sig) else '0';
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
	sto_endofframe <= kernel_eof_sig;
	sto_endofline <= kernel_eol_sig;



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
	end generate;

	gen_param64 : if (PARAMWORD_POW2_NUMBER = 6) generate
		param_bit_sig <= param_data & param_data & param_data & param_data;
		reg0_latch_sig <= param_latchena_reg(0);
		reg1_latch_sig <= param_latchena_reg(0);
		reg2_latch_sig <= param_latchena_reg(1);
		reg3_latch_sig <= param_latchena_reg(1);
		reg4_latch_sig <= param_latchena_reg(2);
		reg5_latch_sig <= param_latchena_reg(2);
	end generate;

	gen_param128 : if (PARAMWORD_POW2_NUMBER = 7) generate
		param_bit_sig <= param_data & param_data;
		reg0_latch_sig <= param_latchena_reg(0);
		reg1_latch_sig <= param_latchena_reg(0);
		reg2_latch_sig <= param_latchena_reg(0);
		reg3_latch_sig <= param_latchena_reg(0);
		reg4_latch_sig <= param_latchena_reg(1);
		reg5_latch_sig <= param_latchena_reg(1);
	end generate;

	gen_param256 : if (PARAMWORD_POW2_NUMBER = 8) generate
		param_bit_sig <= param_data;
		reg0_latch_sig <= param_latchena_reg(0);
		reg1_latch_sig <= param_latchena_reg(0);
		reg2_latch_sig <= param_latchena_reg(0);
		reg3_latch_sig <= param_latchena_reg(0);
		reg4_latch_sig <= param_latchena_reg(0);
		reg5_latch_sig <= param_latchena_reg(0);
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

					-- reg0:ライン先頭アドレスのロード 
					if is_true(reg0_latch_sig) then
						rd_address_reg <= slice(param_bit_sig, 32, 0*32);
					end if;

					-- reg1:アドレス増分値とxスキャンステップ数、xスキャン方向のロード 
					if is_true(reg1_latch_sig) then
						address_inc_reg  <= slice(param_bit_sig, address_inc_reg'length, 1*32+0);
						xstep_number_reg <= slice(param_bit_sig, 2, 1*32+16);
						x_reverse_reg <= param_bit_sig(1*32+18);
					end if;

					-- reg2:カーネルスケール値(Ws)のロード 
					if is_true(reg2_latch_sig) then
						kernel_ws_reg <= slice(param_bit_sig, 18, 2*32);
					end if;

					-- reg3,4,5:カーネル係数(Wk00～Wk22)のロード 
					if is_true(reg3_latch_sig) then
						kernel_wk00_reg <= slice(param_bit_sig, 9, 3*32+ 0);
						kernel_wk10_reg <= slice(param_bit_sig, 9, 3*32+ 9);
						kernel_wk20_reg <= slice(param_bit_sig, 9, 3*32+18);
					end if;
					if is_true(reg4_latch_sig) then
						kernel_wk01_reg <= slice(param_bit_sig, 9, 4*32+ 0);
						kernel_wk11_reg <= slice(param_bit_sig, 9, 4*32+ 9);
						kernel_wk21_reg <= slice(param_bit_sig, 9, 4*32+18);
					end if;
					if is_true(reg5_latch_sig) then
						kernel_wk02_reg <= slice(param_bit_sig, 9, 5*32+ 0);
						kernel_wk12_reg <= slice(param_bit_sig, 9, 5*32+ 9);
						kernel_wk22_reg <= slice(param_bit_sig, 9, 5*32+18);
					end if;

				elsif is_true(update_addr_sig) then
					rd_address_reg <= rd_address_reg + slice_sxt(address_inc_reg, rd_address_reg'length, 0);

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

	ringbuff_wraddr_sig <= ringbuff_index_reg & ringbuff_inaddr_reg;
	ringbuff_wrdata_sig <= read_data;
	ringbuff_wrena_sig <= read_datavalid_sig;


	-- バースト長の計算 

	line_beginoffset_sig <= rd_address_reg(ALIGN_ADDR_WIDTH-1 downto 0);
	burstdatabytes_sig <= loadbytes_reg + line_beginoffset_sig;
	burstwordmax_sig <= slice(burstdatabytes_sig, burstwordmax_sig'length, ALIGN_ADDR_WIDTH);
	err_burst_over_sig <= or_reduce(burstdatabytes_sig(burstdatabytes_sig'left downto burstwordmax_sig'length+ALIGN_ADDR_WIDTH));

	process (clk, reset) begin
		if is_true(reset) then
			state_memread <= READIDLE;
			read_request_reg <= '0';

		elsif rising_edge(clk) then
			case state_memread is

			-- 開始信号を待つ 
			when READIDLE =>
				if is_true(start_sig) then
					state_memread <= READREQ;
					error_burstover_reg <= '0';
					ringbuff_index_reg <= (others=>'0');

					-- ライン読み込みバイト数の確定 (値にはラインバイト数-1を指定する)
					loadbytes_reg <= line_lastbytes_sig;

					-- 読み込みライン数の確定 (値には処理ライン数-1を指定する)
					line_counter <= conv_integer(param_ymax_sig);
				end if;


			-- 処理データの読み込み 
			when READREQ =>
				-- 初期化リクエストが来ていたら中断する 
				if is_true(memread_init_sig) then
					state_memread <= READIDLE;

				-- 入力リングバッファが開いていたらライン読み込みをリクエスト 
				elsif is_false(attrfifo_full_sig) then
					state_memread <= READDATA;
					read_request_reg <= '1';
					error_burstover_reg <= err_burst_over_sig;
					ringbuff_inaddr_reg <= (others=>'0');
					rd_datanum_reg <= burstwordmax_sig;
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
				if (line_counter = 0) then
					state_memread <= READIDLE;
				else
					state_memread <= READREQ;
					line_counter <= line_counter - 1;
				end if;

				ringbuff_index_reg <= ringbuff_index_reg + 1;

			end case;
		end if;
	end process;

	update_addr_sig <= '1' when(state_memread = READDONE) else '0';		-- READDONEで次のアドレスを計算 

	attrfifo_wrreq_sig <= update_addr_sig;								-- アドレス更新と同時に属性FIFOへキュー 
	attrfifo_data_sig <= line_beginoffset_sig & ringbuff_index_reg;		-- リングバッファインデックスと開始バイトを格納 


	-- 属性FIFOのインスタンス 

	u_attrfifo : scfifo
	generic map (
		intended_device_family => DEVICE_FAMILY,
		lpm_type => "scfifo",
		lpm_showahead => "ON",
		lpm_numwords => 2**BUFF_INDEX_WIDTH,
		lpm_widthu => BUFF_INDEX_WIDTH,
		lpm_width => ALIGN_ADDR_WIDTH+BUFF_INDEX_WIDTH,
		add_ram_output_register => "OFF",
		overflow_checking => FIFO_FLOW_CHECKING,
		underflow_checking => FIFO_FLOW_CHECKING,
		use_eab => "OFF"				-- ramtype:LE
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
		intended_device_family => DEVICE_FAMILY,
		lpm_type => "altsyncram",
		operation_mode => "DUAL_PORT",
		--ram_block_type => "M9K",		-- ramtype:auto
		clock_enable_input_a => "NORMAL",
		clock_enable_input_b => "NORMAL",
		clock_enable_output_b => "NORMAL",
		address_aclr_b => "NONE",
		address_reg_b => "CLOCK1",
		outdata_aclr_b => "NONE",
		outdata_reg_b => "CLOCK1",
		power_up_uninitialized => "FALSE",
		numwords_a => 2**(BUFF_INADDR_WIDTH+BUFF_INDEX_WIDTH),
		widthad_a => BUFF_INADDR_WIDTH+BUFF_INDEX_WIDTH,
		width_a => DATABUS_BITWIDTH,
		numwords_b => 2**(MAXCONVSIZE_POW2_NUMBER+BUFF_INDEX_WIDTH),
		widthad_b => MAXCONVSIZE_POW2_NUMBER+BUFF_INDEX_WIDTH,
		width_b => 8,
		width_byteena_a => 1
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
	attrfifo_rdack_sig <= genpixel_enable_sig when(is_true(lineend_sig) and is_false(pl_hold_reg) and is_false(y_hold_reg)) else '0';

	pixel_rdindex_sig  <= slice(attrfifo_q_sig, pixel_rdindex_sig'length, 0);
	pixel_rdoffset_sig <= slice(attrfifo_q_sig, pixel_rdoffset_sig'length, pixel_rdindex_sig'length);
	ringbuff_rdaddr_sig <= pixel_rdindex_sig & (pixel_rdaddr_reg + pixel_rdoffset_sig);
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
						x_unpooling_ena_reg <= unpooling_mode(0);
						y_unpooling_ena_reg <= unpooling_mode(1);
						y_hold_reg <= unpooling_mode(1);

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
						x_hold_reg <= x_unpooling_ena_reg;

						-- アドレス初期値の確定 
						if is_true(x_reverse_reg) then
							pixel_rdaddr_reg <= slice(loadbytes_reg, pixel_rdaddr_reg'length, 0);	-- loadbytes_regはstart_sigで固定
						else
							pixel_rdaddr_reg <= (others=>'0');
						end if;
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
						if is_true(x_hold_reg) then
							x_hold_reg <= '0';
						else
							if (x_counter = 0) then
								if is_true(padding_ena_reg) then
									state_genpixel <= PIXELENDPADDING;
								else
									state_genpixel <= PIXELFINALLY;
								end if;
							else
								x_counter <= x_counter - 1;
								x_hold_reg <= x_unpooling_ena_reg;

								-- 読み出しアドレス更新 
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
						if (y_counter = 0 and is_false(y_hold_reg)) then
							pl_hold_reg <= not pl_hold_reg;	-- 今が末尾パディングラインならば解除する 
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

						elsif is_true(y_hold_reg) then		-- unpoolingのダブルスキャン 
							state_genpixel <= PIXELWAIT;
							y_hold_reg <= '0';

						else
							if (y_counter = 0) then
								state_genpixel <= PIXELIDLE;
							else
								state_genpixel <= PIXELWAIT;
								y_counter <= y_counter - 1;
								y_hold_reg <= y_unpooling_ena_reg;
							end if;
						end if;
					end if;

				end case;
			end if;
		end if;
	end process;

	lineend_sig <= '1' when(state_genpixel = PIXELFINALLY) else '0';
	frameend_sig <= lineend_sig when(is_false(pl_hold_reg) and is_false(y_hold_reg) and y_counter = 0) else '0';


	-- リングバッファ出力遅延の調整とパディングデータのマスク 

	p_valid_sig <= '1' when(state_genpixel = PIXELBEGINPADDING or state_genpixel = PIXELLOOP or state_genpixel = PIXELENDPADDING) else '0';
	p_padding_sig <= '1' when(is_true(pl_hold_reg) or state_genpixel = PIXELBEGINPADDING or state_genpixel = PIXELENDPADDING) else '0';

	process (clk) begin
		if rising_edge(clk) then
			if is_true(param_ready_reg) then			-- パラメータブロックが停止している時にクリア 
				p_frameend_delay_reg <= (others=>'0');
				p_lineend_delay_reg <= (others=>'0');
				p_padding_delay_reg <= (others=>'0');
				p_valid_delay_reg <= (others=>'0');

			elsif is_true(genpixel_enable_sig) then
				p_frameend_delay_reg <= shiftin(p_frameend_delay_reg, frameend_sig);
				p_lineend_delay_reg <= shiftin(p_lineend_delay_reg, lineend_sig);
				p_padding_delay_reg <= shiftin(p_padding_delay_reg, p_padding_sig);
				p_valid_delay_reg <= shiftin(p_valid_delay_reg, p_valid_sig);

			end if;

		end if;
	end process;

	pixel_frameend_sig <= shiftout(p_frameend_delay_reg);
	pixel_lineend_sig <= shiftout(p_lineend_delay_reg);
	pixel_padding_sig <= shiftout(p_padding_delay_reg);
	pixel_valid_sig <= shiftout(p_valid_delay_reg);

	pixel_data_sig <= (others=>'0') when(is_true(pixel_padding_sig) and is_true(padding_zero_reg)) else ringbuff_rddata_sig;



	----------------------------------------------------------------------
	-- 3x3カーネル演算 
	----------------------------------------------------------------------
	-- pixel_data_sig : ピクセルデータ 
	-- pixel_valid_sig : １ラインのピクセル送出中は連続してアサートされる。ラインの間は1クロック以上ネゲートされる。
	-- pixel_lineend_sig : ラインの最終ピクセルを指示 
	-- pixel_frameend_sig : フレームの最後のピクセルを指示 
	-- kernel_data_sig : カーネル演算結果 
	-- kernel_valid_sig : kernel_data_sigの有効信号 
	-- kernel_eof_sig : フレームの最終データを指示 
	-- kernel_eol_sig : ラインの最終データを指示 


	-- カーネル計算レジスタの確定 

	err_kernel_opsat_sig <= '1' when(is_true(kernel_sat0_sig) and is_false(kernal_precision_reg)) or
									(is_true(kernel_sat1_sig) and is_true(kernal_precision_reg)) else '0';

	process (clk) begin
		if rising_edge(clk) then
			-- 全体開始信号でカーネル精度と小数位置モード確定 
			if is_true(start_sig) then
				kernal_precision_reg <= precision;
				kernel_decpos_reg <= decimal_pos;
			end if;

			-- カーネル係数演算飽和フラグ 
			if is_true(start_sig) then
				error_opsat_reg <= '0';
			elsif is_true(kernel_enable_sig) and is_true(kernel_calcdelay_reg(KERNEL_OPSAT_TAP)) and is_true(err_kernel_opsat_sig) then
				error_opsat_reg <= '1';
			end if;
		end if;
	end process;


	-- カーネル計算用のタイミングを生成 

	kernel_calcvalid_sig <= kernel_linedelay_reg(1) and kernel_pixdelay_reg(1) when is_true(pixel_valid_sig) else '0';	-- 演算有効画素を示す 
	kernel_eofvalid_sig <= pixel_frameend_sig when is_true(kernel_calcvalid_sig) else '0';
	kernel_eolvalid_sig <= pixel_lineend_sig when is_true(kernel_calcvalid_sig) else '0';

	process (clk) begin
		if rising_edge(clk) then
			if is_true(param_ready_reg) then			-- パラメータブロックが停止している時にクリア 
				kernel_linedelay_reg <= (others=>'0');
				kernel_pixdelay_reg <= (others=>'0');
				kernel_calcdelay_reg <= (others=>'0');
				kernel_eofdelay_reg <= (others=>'0');
				kernel_eoldelay_reg <= (others=>'0');

			elsif is_true(kernel_enable_sig) then
				-- 3x3の画素が揃うまで有効画素信号をマスク 
				if is_true(pixel_lineend_sig) then
					kernel_linedelay_reg <= shiftin(kernel_linedelay_reg, '1');
					kernel_pixdelay_reg <= (others=>'0');
				elsif is_true(pixel_valid_sig) then
					kernel_pixdelay_reg <= shiftin(kernel_pixdelay_reg, '1');
				end if;

				-- カーネル演算レイテンシの遅延 
				kernel_calcdelay_reg <= shiftin(kernel_calcdelay_reg, kernel_calcvalid_sig);
				kernel_eofdelay_reg <= shiftin(kernel_eofdelay_reg, kernel_eofvalid_sig);
				kernel_eoldelay_reg <= shiftin(kernel_eoldelay_reg, kernel_eolvalid_sig);
			end if;

		end if;
	end process;

	kernel_valid_sig <= shiftout(kernel_calcdelay_reg);
	kernel_eof_sig <= shiftout(kernel_eofdelay_reg);
	kernel_eol_sig <= shiftout(kernel_eoldelay_reg);


	-- ラインFIFOのインスタンス 

	linefifo_flush_sig <= start_sig;		-- 全体開始シグナルでラインFIFOを初期化 

	linefifo_q_sig(7 downto 0) <= pixel_data_sig;
	linefifo_queue_sig(0) <= kernel_enable_sig when is_true(pixel_valid_sig) else '0';

	gen_linefifo : for i in 0 to 1 generate
		linefifo_queue_sig(i+1) <= kernel_enable_sig when is_true(pixel_valid_sig) and is_true(kernel_linedelay_reg(i)) else '0';

		u : scfifo
		generic map (
			intended_device_family => DEVICE_FAMILY,
			lpm_type => "scfifo",
			lpm_showahead => "ON",
			lpm_numwords => 2**(MAXCONVSIZE_POW2_NUMBER+1),
			lpm_widthu => MAXCONVSIZE_POW2_NUMBER+1,
			lpm_width => 8,
			add_ram_output_register => "OFF",
			overflow_checking => FIFO_FLOW_CHECKING,
			underflow_checking => FIFO_FLOW_CHECKING,
			use_eab => "ON"
		)
		port map (
			clock	=> clk,
			sclr	=> linefifo_flush_sig,

			wrreq	=> linefifo_queue_sig(i),
			data	=> linefifo_q_sig(i*8+7 downto i*8),

			rdreq	=> linefifo_queue_sig(i+1),	-- ack
			q		=> linefifo_q_sig((i+1)*8+7 downto (i+1)*8),
			empty	=> linefifo_empty_sig(i)
		);
	end generate;


	-- カーネル演算器のインスタンス 

	multadd_dataa_sig <=
		repbit('0', 16) & slice(linefifo_q_sig, 8, 2*8) &		-- linefifo_q_sig(23..16) : line<n-2> (wk00,wk10,wk20) の画素データ 
		repbit('0', 16) & slice(linefifo_q_sig, 8, 1*8) &		-- linefifo_q_sig(15.. 8) : line<n-1> (wk01,wk11,wk21) の画素データ 
		repbit('0', 16) & slice(linefifo_q_sig, 8, 0*8);		-- linefifo_q_sig( 7.. 0) : line<n>   (wk02,wk12,wk22) の画素データ 

	multadd_datab_sig <= 
		kernel_wk00_reg & kernel_wk10_reg & kernel_wk20_reg &
		kernel_wk01_reg & kernel_wk11_reg & kernel_wk21_reg &
		kernel_wk02_reg & kernel_wk12_reg & kernel_wk22_reg;

	gen_multadd3 : for i in 0 to 2 generate
		-- (u8 x s9) + (u8 x s9) + (u8 x s9) -> result : 3clock latency
		u : ALTMULT_ADD
		generic map (
			intended_device_family => DEVICE_FAMILY,
			lpm_type => "altmult_add",
			addnsub_multiplier_aclr1 => "UNUSED",
			addnsub_multiplier_pipeline_aclr1 => "UNUSED",
			addnsub_multiplier_pipeline_register1 => "CLOCK0",
			addnsub_multiplier_register1 => "CLOCK0",
			dedicated_multiplier_circuitry => "AUTO",
			input_aclr_a0 => "UNUSED",
			input_aclr_a1 => "UNUSED",
			input_aclr_a2 => "UNUSED",
			input_aclr_b0 => "UNUSED",
			input_aclr_b1 => "UNUSED",
			input_aclr_b2 => "UNUSED",
			input_register_a0 => "CLOCK0",
			input_register_a1 => "CLOCK0",
			input_register_a2 => "CLOCK0",
			input_register_b0 => "CLOCK0",
			input_register_b1 => "CLOCK0",
			input_register_b2 => "CLOCK0",
			input_source_a0 => "DATAA",
			input_source_a1 => "SCANA",
			input_source_a2 => "SCANA",
			input_source_b0 => "DATAB",
			input_source_b1 => "DATAB",
			input_source_b2 => "DATAB",
			multiplier1_direction => "ADD",
			multiplier_aclr0 => "UNUSED",
			multiplier_aclr1 => "UNUSED",
			multiplier_aclr2 => "UNUSED",
			multiplier_register0 => "CLOCK0",
			multiplier_register1 => "CLOCK0",
			multiplier_register2 => "CLOCK0",
			number_of_multipliers => 3,
			output_aclr => "UNUSED",
			output_register => "CLOCK0",
			port_addnsub1 => "PORT_UNUSED",
			port_signa => "PORT_UNUSED",
			port_signb => "PORT_UNUSED",
			representation_a => "UNSIGNED",
			representation_b => "SIGNED",
			signed_aclr_a => "UNUSED",
			signed_aclr_b => "UNUSED",
			signed_pipeline_aclr_a => "UNUSED",
			signed_pipeline_aclr_b => "UNUSED",
			signed_pipeline_register_a => "CLOCK0",
			signed_pipeline_register_b => "CLOCK0",
			signed_register_a => "CLOCK0",
			signed_register_b => "CLOCK0",
			width_a => 8,
			width_b => 9,
			width_result => 19
		)
		port map (
			clock0	=> clk,
			ena0	=> kernel_enable_sig,

			dataa	=> multadd_dataa_sig(i*3*8+23 downto i*3*8),
			datab	=> multadd_datab_sig(i*3*9+26 downto i*3*9),
			result	=> multadd_result_sig(i*19+18 downto i*19)
		);
	end generate;


	-- 3ライン分の総和 : 1clock latency
	multadd_sum_sig <= 
		slice_sxt(slice(multadd_result_sig, 19, 2*19), 19+2, 0) +
		slice_sxt(slice(multadd_result_sig, 19, 1*19), 19+2, 0) +
		slice_sxt(slice(multadd_result_sig, 19, 0*19), 19+2, 0);

	process (clk) begin
		if rising_edge(clk) then
			if is_true(kernel_enable_sig) then
				multadd_sum_reg <= multadd_sum_sig;
			end if;
		end if;
	end process;


	-- カーネル演算精度設定で飽和処理 
	kernel_sat0_sig <= '1' when(multadd_sum_reg(19+2-1) /= multadd_sum_reg(19+2-2)) else '0';
	kernel_sat1_sig <= '1' when(or_reduce(slice(multadd_sum_reg, 4, 17)) /= and_reduce(slice(multadd_sum_reg, 4, 17))) else '0';

	multadd_sat_sig <=
		slice(multadd_sum_reg, 18, 2) when is_false(kernel_sat0_sig) and is_false(kernal_precision_reg) else
		slice(multadd_sum_reg, 18, 0) when is_false(kernel_sat1_sig) and is_true(kernal_precision_reg) else
		(17=>multadd_sum_reg(19+2-1), others=>not multadd_sum_reg(19+2-1));			-- 正負の最大値に飽和 


	-- s18 x u18 -> result : 2clock latency
	u_mult_s18xu18 : ALTMULT_ADD
	generic map (
		intended_device_family => DEVICE_FAMILY,
		lpm_type => "altmult_add",
		addnsub_multiplier_aclr1 => "UNUSED",
		addnsub_multiplier_pipeline_aclr1 => "UNUSED",
		addnsub_multiplier_pipeline_register1 => "CLOCK0",
		addnsub_multiplier_register1 => "CLOCK0",
		dedicated_multiplier_circuitry => "AUTO",
		input_aclr_a0 => "UNUSED",
		input_aclr_b0 => "UNUSED",
		input_register_a0 => "CLOCK0",
		input_register_b0 => "CLOCK0",
		input_source_a0 => "DATAA",
		input_source_b0 => "DATAB",
		multiplier1_direction => "ADD",
		multiplier_aclr0 => "UNUSED",
		multiplier_register0 => "CLOCK0",
		number_of_multipliers => 1,
		output_register => "UNREGISTERED",
		port_addnsub1 => "PORT_UNUSED",
		port_signa => "PORT_UNUSED",
		port_signb => "PORT_UNUSED",
		representation_a => "SIGNED",
		representation_b => "UNSIGNED",
		signed_aclr_a => "UNUSED",
		signed_aclr_b => "UNUSED",
		signed_pipeline_aclr_a => "UNUSED",
		signed_pipeline_aclr_b => "UNUSED",
		signed_pipeline_register_a => "CLOCK0",
		signed_pipeline_register_b => "CLOCK0",
		signed_register_a => "CLOCK0",
		signed_register_b => "CLOCK0",
		width_a => 18,
		width_b => 18,
		width_result => 36
	)
	port map (
		clock0	=> clk,
		ena0	=> kernel_enable_sig,

		dataa	=> multadd_sat_sig,
		datab	=> kernel_ws_reg,
		result	=> mult_result_sig
	);


	-- 小数位置モードの選択 
	with (kernel_decpos_reg) select kernel_data_sig <=
		slice_sxt(mult_result_sig, 32, 16)	when PARAM_DECPOS_7,
		slice_sxt(mult_result_sig, 32, 12)	when PARAM_DECPOS_11,
		slice_sxt(mult_result_sig, 32, 8)	when PARAM_DECPOS_15,
		slice_sxt(mult_result_sig, 32, 4)	when others;



end RTL;
