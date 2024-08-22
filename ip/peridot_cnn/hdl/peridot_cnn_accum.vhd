-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - accumulator
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/08/17 -> 2020/09/18
--            : 2020/09/19 (FIXED)
--
--     UPDATE : 2023/11/30 -> 2024/03/15
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
-- [X] 内蔵バッファモードの追加 
-- [X] parallel_addモジュールを使わない場合の実装 
-- [X] ランダムノイズ注入器の追加 
-- [X] dcfifo_mixed_widthsの代替実装 → 不具合原因判明 
-- [X] 乗算モード追加 
--
-- ・検証todo 
-- [X] 内蔵バッファモードの動作確認 
-- [X] ストール制御の可否(backpressure制御が行われるか？) → 基本動作を確認 
-- [X] 飽和演算とフラグの挙動 
-- [X] エラーインジェクションテスト (force_error操作して確認)
-- [X] init信号アボートの動作(正しく復帰するか？タイミングを勘違いしている部分はないか？) 
-- [X] fifo_fullの時の挙動(RD_DCFIFO_WIDTHUを浅くしてテスト) 
-- [X] 32bitで確認したらgenericを変えて確認する(ライン長を変更してsimが変わらないかどうか見る)
-- [X] 乗算モードの動作 → 4カーネル時の動作確認 
--
-- ・解決済み 
-- 症状：Questaでdcfifo_mixed_widthsのwrreqとrdackの数が合わない(23.1LE/2023.3) 
--   -> dcfifo_mixed_widthsでデータ幅が異なるインスタンスのモデルでadd_usedw_msb_bit設定が無視される 
--
-- ・リソース概算 
-- 400LE + 2DSP + 1M9k (1カーネル,乱数なし,32bit幅,RDFIFO 128ワード,8ワードバースト,内蔵バッファなし,FIFOフローチェックOFF時)
-- 880LE + 4DSP + 6M9k (4カーネル,RANDGEN=1,32bit幅,RDFIFO 512ワード,64ワードバースト,内蔵バッファ1kワード時)
-- 1190LE + 4DSP + 32M9k (8カーネル,RANDGEN=1,256bit幅,RDFIFO 4096ワード時,256ワードバースト,内蔵バッファ4kワード時)


-- status(0) : Error, Bus access cannot be continued.
-- status(1) : Warning, An read underrun occurred in the built-in buffer.
-- status(2) : Warning, Saturation occurs in channel sum calculation.
--
-- bias_data  : Bf value (他のパラメータと違ってstart信号でラッチされないので注意)
-- noise_type : Uniform random(=00) / Pseudo cos^19(=01) / reserved(=1X)
-- noise_gain : noise gain value (signed int 18bit)
-- rd_address_top : Start address of temporary buffer (Must be 32byte alignment) 
-- rd_totalnum : Word length of temporary data to read
--
-- intrbuff_ena (startアサート時有効)
--  1:加算中間値を内蔵バッファに格納する 
--    *内蔵バッファを使うときはフィルター累積の最初から最後まで変更しないこと 
--  0:加算中間値を外部メモリ上に格納する 
--
-- multcalc_ena (startアサート時有効)
--  1:乗算モード。カーネル0とカーネル1の出力を乗算。カーネルインスタンス数が1の場合はバッファを利用 
--  0:フィルター累算モード。
--
-- firstchunk (startアサート時有効)
--  1:フィルター累算の最初のフレーム。中間値入力はbias_dataで固定 
--  0:フィルター累算の途中のフレーム。中間値入力はバッファから読み出し 
--
-- lastchunk (startアサート時有効)
--  1:フィルター累算の最後のフレーム。活性化関数へ結果を出力 
--  0:フィルター累算の途中のフレーム。intrbuff_ena=0の場合は書き戻しモジュールに出力 


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

entity peridot_cnn_accum is
	generic(
		MAXKERNEL_NUMBER		: integer := 4;		-- カーネルインスタンス数 (1～8)
		RANDGEN_INSTANCE_TYPE	: integer := 1;		-- 乱数生成器実装タイプ (0:なし / 1:一様乱数,近似cos^19)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		RDFIFODEPTH_POW2_NUMBER	: integer := 8;		-- 読み出しFIFOの深さ (7:128ワード ～ 12:4096ワード *出力ワード単位)
		RDMAXBURST_POW2_NUMBER	: integer := 4;		-- 読み出しバースト長 (3:8ワード ～ RD_DCFIFO_WIDTHU-1 *バースト上限はFIFO読み出し側の半分まで)
		INTRBUFFER_POW2_NUMBER	: integer := 10;	-- 内蔵バッファのサイズ (0:なし / 10:1kワード / 12:4kワード / 14:16kワード)
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
		test_rd_fiforeq		: out std_logic;
		test_rdfifo_areset	: out std_logic;
		test_rdfifo_wrusedw	: out std_logic_vector(8 downto 0);
		test_rdfifo_empty	: out std_logic;
		test_rdfifo_rdack	: out std_logic;
		test_intrfifo_init	: out std_logic;
		test_intrfifo_empty : out std_logic;
		test_intrfifo_wrreq	: out std_logic;
		test_intrfifo_rdack : out std_logic;
		test_accum_data		: out std_logic_vector(32 downto 0);
		test_accum_valid	: out std_logic;
		test_valid_all		: out std_logic;
		test_valid_delay	: out std_logic_vector(5 downto 0);
		test_adder_sat		: out std_logic;
		test_proc_enable	: out std_logic;


		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: in  std_logic := '0';
		start			: in  std_logic;
		ready			: out std_logic;
		error			: out std_logic;						-- errorがアサートされたらreadyは不定(解除はresetのみ) 
		status			: out std_logic_vector(2 downto 0);
		firstchunk		: in  std_logic;
		lastchunk		: in  std_logic;
		intrbuff_ena	: in  std_logic;
		multcalc_ena	: in  std_logic;
		bias_data		: in  std_logic_vector(31 downto 0);	-- RANDGEN_INSTANCE_TYPE=0のときはモジュール内でラッチしない 
		noise_type		: in  std_logic_vector(1 downto 0);
		noise_gain		: in  std_logic_vector(17 downto 0);
		rd_address_top	: in  std_logic_vector(31 downto 0);
		rd_totalnum		: in  std_logic_vector(22 downto 0);

		read_request	: out std_logic;
		read_complete	: out std_logic;
		read_address	: out std_logic_vector(31 downto 0);
		read_burstcount	: out std_logic_vector(RDMAXBURST_POW2_NUMBER downto 0);
		read_datavalid	: in  std_logic;
		read_data		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);

		kernel_ena		: in  std_logic_vector(MAXKERNEL_NUMBER-1 downto 0);
		sti_ready		: out std_logic;
		sti_valid		: in  std_logic_vector(MAXKERNEL_NUMBER-1 downto 0);
		sti_data		: in  std_logic_vector(MAXKERNEL_NUMBER*32-1 downto 0);
		sti_endofline	: in  std_logic;
		sti_endofframe	: in  std_logic;

		sto_ready		: in  std_logic;
		sto_valid		: out std_logic;
		sto_data		: out std_logic_vector(31 downto 0);
		sto_endofline	: out std_logic;
		sto_endofframe	: out std_logic
	);
end peridot_cnn_accum;

architecture RTL of peridot_cnn_accum is
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

-- TEST
--	constant RD_DCFIFO_WIDTHU	: integer := 5;	-- 読み出しFIFOの深さ(テスト用) 

	-- モジュール固定値 
	constant FIFO_SYNC_DELAYPIPE: integer := 4;		-- FIFOのrdsync_delaypipe/wrsync_delaypipeオプション (4:Normal / 5:Speed) 
	constant FIFO_ARESET_CYCLE	: integer := FIFO_SYNC_DELAYPIPE;			-- FIFOの非同期初期化クロック数 (FIFO_SYNC_DELAYPIPE以上)
	constant RD_DCFIFO_WIDTHU	: integer := RDFIFODEPTH_POW2_NUMBER-(DATABUS_POW2_NUMBER-5);	-- 読み出しFIFOの深さ 
	constant ALIGN_ADDR_WIDTH	: integer := DATABUS_POW2_NUMBER-3;			-- ワード境界のアドレスビット幅 
	constant BURST_MAXLENGTH	: integer := 2**RDMAXBURST_POW2_NUMBER;		-- 最大バースト長 

	-- 加算器のパイプライン数 
		-- MAXKERNEL_NUMBER = 1    : 2-stage adder
		-- MAXKERNEL_NUMBER = 2～4 : 3-stage adder
		-- MAXKERNEL_NUMBER = 5～8 : 4-stage adder
	function sel(F:boolean; A,B:integer) return integer is begin if F then return A; else return B; end if; end;
	constant ADDER_PIPELINE		: integer := sel(MAXKERNEL_NUMBER = 1, 2, sel(MAXKERNEL_NUMBER <= 4, 3, 4));
	constant MULT_PIPELINE		: integer := 2;
	constant DELAYTAP_LENGTH	: integer := sel(ADDER_PIPELINE > MULT_PIPELINE, ADDER_PIPELINE, MULT_PIPELINE);


	-- 全体制御 
	signal init_sig				: std_logic;
	signal start_sig			: std_logic;
	signal finally_sig			: std_logic;
	signal ready_sig			: std_logic;
	signal sto_ready_sig		: std_logic;
	signal proc_enable_sig		: std_logic;
	signal ready_reg			: std_logic;
	signal error_deviated_reg	: std_logic;
	signal error_opsat_reg		: std_logic;
	signal error_bufur_reg		: std_logic;

	-- 中間値データ読み込み制御ブロック 
	type DEF_STATE_MEMREAD is (READIDLE, READFIFOINIT, READREQ, READDATA, READDONE);
	signal state_memread : DEF_STATE_MEMREAD;
	signal memread_init_sig		: std_logic;
	signal memread_ready_sig	: std_logic;
	signal fifoinit_counter		: integer range 0 to FIFO_ARESET_CYCLE-1;
	signal fifoinit_reg			: std_logic;
	signal read_request_reg		: std_logic;
	signal intrbuff_ena_reg		: std_logic;
	signal multcalc_ena_reg		: std_logic;
	signal biasinit_ena_reg		: std_logic;
	signal activation_ena_reg	: std_logic;
	signal rd_address_reg		: std_logic_vector(31 downto ALIGN_ADDR_WIDTH);
	signal rd_datanum_reg		: std_logic_vector(read_burstcount'range);
	signal rd_totalnum_reg		: std_logic_vector(rd_totalnum'range);
	signal rd_fiforeq_sig		: std_logic;
	signal read_datavalid_sig	: std_logic;

	signal rdfifo_areset_sig	: std_logic;
	signal rdfifo_wrusedw_sig	: std_logic_vector(RD_DCFIFO_WIDTHU-1 downto 0);
	signal rdfifo_rdack_sig		: std_logic;
	signal rdfifo_q_sig			: std_logic_vector(31 downto 0);
	signal rdfifo_empty_sig		: std_logic;
	signal intrfifo_vall_sig	: std_logic;
	signal intrfifo_init_sig	: std_logic;
	signal intrfifo_wrreq_sig	: std_logic;
	signal intrfifo_data_sig	: std_logic_vector(31 downto 0);
	signal intrfifo_rdack_sig	: std_logic;
	signal intrfifo_q_sig		: std_logic_vector(31 downto 0);
	signal intrfifo_empty_sig	: std_logic;

	signal randadder_data_sig	: std_logic_vector(32 downto 0);
	signal accum_data_sig		: std_logic_vector(32 downto 0);
	signal accum_valid_sig		: std_logic;

	-- 演算ブロック 
	signal valid_all_sig		: std_logic;
	signal valid_delay_reg		: std_logic_vector(DELAYTAP_LENGTH-1 downto 0);
	signal endofframe_delay_reg	: std_logic_vector(DELAYTAP_LENGTH-1 downto 0);
	signal endofline_delay_reg	: std_logic_vector(DELAYTAP_LENGTH-1 downto 0);
	signal kernel_valid_sig		: std_logic_vector(MAXKERNEL_NUMBER downto 0);
	signal kernel_data_sig		: std_logic_vector(8*32-1 downto 0);
	signal sto_data_sig			: std_logic_vector(31 downto 0);
	signal sto_valid_sig		: std_logic;
	signal sto_eof_sig			: std_logic;
	signal sto_eol_sig			: std_logic;
	signal adder_ovf_sig		: std_logic;

	signal adder_accum_reg		: std_logic_vector(accum_data_sig'range);
	signal adder_tmp0_reg		: std_logic_vector(31+1 downto 0);
	signal adder_tmp1_reg		: std_logic_vector(31+1 downto 0);
	signal adder_tmp2_reg		: std_logic_vector(31+1 downto 0);
	signal adder_tmp3_reg		: std_logic_vector(31+1 downto 0);
	signal adder_tmp4_reg		: std_logic_vector(31+3 downto 0);
	signal adder_tmp5_reg		: std_logic_vector(31+3 downto 0);
	signal adder_sum_reg		: std_logic_vector(31+4 downto 0);
	signal adder_sign_sig		: std_logic_vector(adder_sum_reg'left downto 31);
	signal adder_sat_sig		: std_logic;
	signal adder_result_sig		: std_logic_vector(31 downto 0);
	signal adder_data_reg		: std_logic_vector(31 downto 0);
	signal mult_dataa_sig		: std_logic_vector(17 downto 0);
	signal mult_datab_sig		: std_logic_vector(17 downto 0);
	signal mult_result_sig		: std_logic_vector(35 downto 0);
	signal mult_data_sig		: std_logic_vector(31 downto 0);


	-- コンポーネント宣言 
	component peridot_cnn_accum_noise
	generic(
		RANDGEN_INSTANCE_TYPE	: integer
	);
	port(
		reset		: in  std_logic;
		clk			: in  std_logic;

		bias_data	: in  std_logic_vector(31 downto 0);
		noise_type	: in  std_logic_vector(1 downto 0);
		noise_gain	: in  std_logic_vector(17 downto 0);

		result		: out std_logic_vector(32 downto 0)
	);
	end component;

begin

	-- テスト記述 

	test_start <= start_sig;
	test_finally <= finally_sig;
	test_memread_ready <= memread_ready_sig;

	test_rd_fiforeq <= rd_fiforeq_sig;
	test_rdfifo_areset <= rdfifo_areset_sig;
	test_rdfifo_wrusedw <= slice(rdfifo_wrusedw_sig, 9, 0);
	test_rdfifo_empty <= rdfifo_empty_sig;
	test_rdfifo_rdack <= rdfifo_rdack_sig;
	test_intrfifo_init <= intrfifo_init_sig;
	test_intrfifo_empty <= intrfifo_empty_sig;
	test_intrfifo_wrreq <= intrfifo_wrreq_sig;
	test_intrfifo_rdack <= intrfifo_rdack_sig;
	test_accum_data <= accum_data_sig;
	test_accum_valid <= accum_valid_sig;
	test_valid_all <= valid_all_sig;
	test_valid_delay <= slice(valid_delay_reg, 6, 0);
	test_adder_sat <= adder_sat_sig;

	test_proc_enable <= proc_enable_sig;


	-- パラメータ範囲チェック 

	assert (MAXKERNEL_NUMBER >= 1 and MAXKERNEL_NUMBER <= 8)
		report "MAXKERNEL_NUMBER is out of range." severity FAILURE;

	assert (RANDGEN_INSTANCE_TYPE >= 0 and RANDGEN_INSTANCE_TYPE <= 1)
		report "RANDGEN_INSTANCE_TYPE is out of range." severity FAILURE;

	assert (DATABUS_POW2_NUMBER >= 5 and DATABUS_POW2_NUMBER <= 8)
		report "DATABUS_POW2_NUMBER is out of range." severity FAILURE;

	assert (RDFIFODEPTH_POW2_NUMBER >= 7 and RDFIFODEPTH_POW2_NUMBER <= 12)
		report "RDFIFODEPTH_POW2_NUMBER is out of range." severity FAILURE;

	assert (RDMAXBURST_POW2_NUMBER >= 3 and RDMAXBURST_POW2_NUMBER <= (RD_DCFIFO_WIDTHU-1))
		report "RDMAXBURST_POW2_NUMBER is out of range. Equal or less than " & integer'image(RD_DCFIFO_WIDTHU-1) severity FAILURE;

	assert (INTRBUFFER_POW2_NUMBER = 0 or INTRBUFFER_POW2_NUMBER = 10 or INTRBUFFER_POW2_NUMBER = 12 or INTRBUFFER_POW2_NUMBER = 14 or INTRBUFFER_POW2_NUMBER = 16)
		report "INTRBUFFER_POW2_NUMBER is out of range." severity FAILURE;

	assert (read_burstcount'length <= 11)
		report "Avalon-MM burstcount port width is out of range. Equal or less than 11." severity FAILURE;



	----------------------------------------------------------------------
	-- モジュール全体制御 
	----------------------------------------------------------------------

	init_sig <= init;
	ready_sig <= ready_reg;

	ready <= ready_sig;
	error <= error_deviated_reg;
	status <= error_opsat_reg & error_bufur_reg & error_deviated_reg;


	-- 開始信号と終了信号生成 

	start_sig <= start when is_true(ready_sig) else '0';
	finally_sig <= sto_eof_sig when is_true(proc_enable_sig) else '0';

	process (clk, reset) begin
		if is_true(reset) then
			ready_reg <= '1';
			error_deviated_reg <= '0';
			error_opsat_reg <= '0';
			error_bufur_reg <= '0';

		elsif rising_edge(clk) then
			-- バストランザクションFSMの異常で続行できない 
			if is_true(finally_sig) and is_false(memread_ready_sig) then
				error_deviated_reg <= '1';
			end if;

			-- 飽和演算でオーバーフローが発生した 
			if is_true(init_sig) or is_true(start_sig) then
				error_opsat_reg <= '0';
			elsif is_true(adder_ovf_sig) then
				error_opsat_reg <= '1';
			end if;

			-- 内蔵バッファでアンダーランが発生した 
			if is_true(init_sig) or is_true(start_sig) then
				error_bufur_reg <= '0';
			elsif is_true(intrfifo_rdack_sig) and is_true(intrfifo_empty_sig) then
				error_bufur_reg <= '1';
			end if;

			-- ready信号 
			if is_true(init_sig) or is_true(finally_sig) then
				ready_reg <= memread_ready_sig;
			elsif is_true(start_sig) then
				ready_reg <= '0';
			end if;

			-- 活性化関数への出力 
			if is_true(start_sig) then
				activation_ena_reg <= lastchunk;
			end if;
		end if;
	end process;


	-- 結果出力とAvalonSTフロー制御 

	sto_ready_sig <= sto_ready when is_false(intrbuff_ena_reg) or is_true(activation_ena_reg) else '1';
	proc_enable_sig <= sto_ready_sig when is_true(sto_valid_sig) else '1';

	sto_valid <= sto_valid_sig when is_false(intrbuff_ena_reg) or is_true(activation_ena_reg) else '0';
	sto_data <= sto_data_sig;
	sto_endofframe <= sto_eof_sig;
	sto_endofline <= sto_eol_sig;



	----------------------------------------------------------------------
	-- 中間値データ読み込み制御 (中間値または初期値をストリームにする)
	----------------------------------------------------------------------

	memread_init_sig <= init_sig;
--	memread_ready_sig <= '1' when(state_memread = READIDLE) else '0';
	memread_ready_sig <= '1' when(state_memread = READIDLE and is_false(test_force_error)) else '0';


	-- メモリリードリクエスト

	read_request <= read_request_reg;
	read_complete <= '1' when(state_memread = READDONE) else '0';
	read_address <= rd_address_reg(31 downto ALIGN_ADDR_WIDTH) & repbit('0', ALIGN_ADDR_WIDTH);
	read_burstcount <= rd_datanum_reg;
	read_datavalid_sig <= read_datavalid;


	-- バーストリード制御 

	rd_fiforeq_sig <= '1' when(rdfifo_wrusedw_sig < (2**RD_DCFIFO_WIDTHU - BURST_MAXLENGTH)) else '0';	-- バースト長以上の空きがある 

	process (clk, reset) begin
		if is_true(reset) then
			state_memread <= READIDLE;
			read_request_reg <= '0';

		elsif rising_edge(clk) then
			case state_memread is

			-- 開始信号を待つ 

			when READIDLE =>
				if is_true(start_sig) then
					intrbuff_ena_reg <= intrbuff_ena;
					biasinit_ena_reg <= firstchunk;

					-- 乗算モード確定 
					if is_true(lastchunk) then
						multcalc_ena_reg <= multcalc_ena;
					else
						multcalc_ena_reg <= '0';
					end if;

					-- メモリリード動作確定 
					if is_false(firstchunk) and is_false(intrbuff_ena) then
						state_memread <= READFIFOINIT;
					end if;

					fifoinit_reg <= '1';
					fifoinit_counter <= FIFO_ARESET_CYCLE - 1;

					-- 読み出し先頭アドレスの確定 
					rd_address_reg <= rd_address_top(rd_address_reg'range);

					-- トータルデータ書き込み数カウンタ 
					rd_totalnum_reg <= rd_totalnum(rd_totalnum_reg'range);
				end if;

			when READFIFOINIT =>
				-- 入力FIFOのリセット 
				if (fifoinit_counter = 0) then
					state_memread <= READREQ;
					fifoinit_reg <= '0';
				else
					fifoinit_counter <= fifoinit_counter - 1;
				end if;


			-- データの読み込み要求 

			when READREQ =>
				-- 初期化リクエストが来ていたら中断する 
				if is_true(memread_init_sig) then
					state_memread <= READIDLE;

				-- データを全て読み終わっていたら終了 
				elsif (rd_totalnum_reg = 0) then
					state_memread <= READIDLE;

				-- 入力FIFOが開いていたらバースト読み込みをリクエスト 
				elsif is_true(rd_fiforeq_sig) then
					state_memread <= READDATA;
					read_request_reg <= '1';

					if (rd_totalnum_reg >= BURST_MAXLENGTH) then
						rd_datanum_reg <= to_vector(BURST_MAXLENGTH, rd_datanum_reg'length);
					else
						rd_datanum_reg <= rd_totalnum_reg(rd_datanum_reg'range);
					end if;
				end if;

			when READDATA =>
				-- データが送られてきたらFIFOへ書き込む 
				if is_true(read_datavalid_sig) then
					if (rd_datanum_reg = 1) then
						state_memread <= READDONE;
					end if;

					read_request_reg <= '0';
					rd_datanum_reg <= rd_datanum_reg - 1;
					rd_totalnum_reg <= rd_totalnum_reg - 1;
				end if;

			when READDONE =>
				state_memread <= READREQ;
				rd_address_reg <= rd_address_reg + BURST_MAXLENGTH;	-- アドレスを更新 

			end case;
		end if;
	end process;


	-- 入力FIFOのインスタンス 
	--   * writeポートとreadポートのデータ幅が異なるfifoはdcfifo_mixed_widthsでのみ使用できる 

	rdfifo_areset_sig <= fifoinit_reg;	-- firstchunk(biasinit)とintrbuff_enaのときは次のstartまでアサート保持 
	rdfifo_rdack_sig <= '1' when is_true(proc_enable_sig) and is_false(fifoinit_reg) and is_true(valid_all_sig) else '0';

	u_rdfifo : dcfifo_mixed_widths
	generic map (
		intended_device_family	=> DEVICE_FAMILY,	-- QuestaでSimする場合はデバイス指定が必要 
		lpm_type			=> "dcfifo",
		lpm_showahead		=> "ON",
		lpm_numwords		=> 2**RD_DCFIFO_WIDTHU,
		lpm_widthu			=> RD_DCFIFO_WIDTHU,
		lpm_width			=> read_data'length,
		lpm_widthu_r		=> RDFIFODEPTH_POW2_NUMBER,
		lpm_width_r			=> 32,
		overflow_checking	=> FIFO_FLOW_CHECKING,
		underflow_checking	=> FIFO_FLOW_CHECKING,
		write_aclr_synch	=> "ON",
		rdsync_delaypipe	=> FIFO_SYNC_DELAYPIPE,
		wrsync_delaypipe	=> FIFO_SYNC_DELAYPIPE
	)
	port map (
		aclr	=> rdfifo_areset_sig,

		wrclk	=> clk,
		wrreq	=> read_datavalid_sig,
		data	=> read_data,
		wrusedw	=> rdfifo_wrusedw_sig,

		rdclk	=> clk,
		rdreq	=> rdfifo_rdack_sig,	-- ack
		q		=> rdfifo_q_sig,
		rdempty	=> rdfifo_empty_sig
	);


	-- 中間値バッファのインスタンス 
	--   *入出力のデータ数とタイミングが決まっているのでFull/Emptyによるフロー制御は不要 

	intrfifo_vall_sig <= and_reduce(kernel_valid_sig(MAXKERNEL_NUMBER-1 downto 0));		-- 内蔵バッファ時はカーネルデータのvalidだけ見ればよい 

	intrfifo_init_sig <= '1' when is_true(start_sig) and is_true(firstchunk) else '0';
	intrfifo_wrreq_sig <= '1' when is_true(intrbuff_ena_reg) and is_false(activation_ena_reg) and is_true(sto_valid_sig) else '0';
	intrfifo_rdack_sig <= '1' when is_true(proc_enable_sig) and is_true(intrbuff_ena_reg) and is_false(biasinit_ena_reg) and is_true(intrfifo_vall_sig) else '0';

	gen_intrbuff : if (INTRBUFFER_POW2_NUMBER /= 0) generate
		u : scfifo
		generic map (
			lpm_type		=> "scfifo",
			lpm_showahead	=> "ON",
			lpm_numwords	=> 2**INTRBUFFER_POW2_NUMBER,
			lpm_widthu		=> INTRBUFFER_POW2_NUMBER,
			lpm_width		=> 32,
			add_ram_output_register => FIFO_SPEED_OPTION
		)
		port map (
			clock	=> clk,
			sclr	=> intrfifo_init_sig,

			wrreq	=> intrfifo_wrreq_sig,
			data	=> adder_data_reg,

			rdreq	=> intrfifo_rdack_sig,	-- ack
			q		=> intrfifo_q_sig,
			empty	=> intrfifo_empty_sig
		);
	end generate;
	gen_nointrbuff : if (INTRBUFFER_POW2_NUMBER = 0) generate
		intrfifo_q_sig <= (others=>'0');
		intrfifo_empty_sig <= '0';
	end generate;


	-- 乱数加算器のインスタンス 

	gen_noise : if (RANDGEN_INSTANCE_TYPE > 0) generate
		u : peridot_cnn_accum_noise
		generic map (
			RANDGEN_INSTANCE_TYPE	=> RANDGEN_INSTANCE_TYPE
		)
		port map (
			reset		=> reset,
			clk			=> clk,

			bias_data	=> bias_data,
			noise_type	=> noise_type,
			noise_gain	=> noise_gain,

			result		=> randadder_data_sig
		);
	end generate;
	gen_nonoise : if (RANDGEN_INSTANCE_TYPE = 0) generate
		randadder_data_sig <= slice_sxt(bias_data, 33, 0);
	end generate;


	-- 中間値バッファデータ出力 

	accum_valid_sig <=
		'1' when is_true(biasinit_ena_reg) else
		'1' when is_true(intrbuff_ena_reg) else
		'1' when is_false(intrbuff_ena_reg) and is_false(rdfifo_empty_sig) else
		'0';

	accum_data_sig <=
		randadder_data_sig when is_true(biasinit_ena_reg) else
		slice_sxt(intrfifo_q_sig, 33, 0) when is_true(intrbuff_ena_reg) else
		slice_sxt(rdfifo_q_sig, 33, 0);



	----------------------------------------------------------------------
	-- 演算制御 (カーネル数のストリームを加算または2カーネルを乗算)
	----------------------------------------------------------------------

	-- 入力データのシンクロ 

	gen_sti : for i in 0 to MAXKERNEL_NUMBER-1 generate
		kernel_valid_sig(i) <= sti_valid(i) when is_true(kernel_ena(i)) else '1';
		kernel_data_sig(i*32+31 downto i*32+0) <= sti_data(i*32+31 downto i*32+0) when is_true(kernel_ena(i)) else (others=>'0');
	end generate;
	gen_nosti : if (MAXKERNEL_NUMBER < 8) generate
		kernel_data_sig(7*32+31 downto MAXKERNEL_NUMBER*32+0) <= (others=>'0');
	end generate;

	kernel_valid_sig(MAXKERNEL_NUMBER) <= accum_valid_sig;
	valid_all_sig <= and_reduce(kernel_valid_sig);

	sti_ready <= '1' when is_true(proc_enable_sig) and is_true(valid_all_sig) else '0';


	-- タイミング信号生成と出力データ選択 

	process (clk) begin
		if rising_edge(clk) then
			if is_true(ready_sig) then
				valid_delay_reg <= (others=>'0');
				endofframe_delay_reg <= (others=>'0');
				endofline_delay_reg <= (others=>'0');

			elsif is_true(proc_enable_sig) then
				valid_delay_reg <= shiftin(valid_delay_reg, valid_all_sig);
				endofframe_delay_reg <= shiftin(endofframe_delay_reg, sti_endofframe);
				endofline_delay_reg <= shiftin(endofline_delay_reg, sti_endofline);

			end if;
		end if;
	end process;

	sto_data_sig <= mult_data_sig when is_true(multcalc_ena_reg) else adder_data_reg;
	sto_valid_sig <= valid_delay_reg(MULT_PIPELINE-1) when is_true(multcalc_ena_reg) else valid_delay_reg(ADDER_PIPELINE-1);
	sto_eof_sig <= endofframe_delay_reg(MULT_PIPELINE-1) when is_true(multcalc_ena_reg) else endofframe_delay_reg(ADDER_PIPELINE-1);
	sto_eol_sig <= endofline_delay_reg(MULT_PIPELINE-1) when is_true(multcalc_ena_reg) else endofline_delay_reg(ADDER_PIPELINE-1);

	adder_ovf_sig <= adder_sat_sig when is_false(multcalc_ena_reg) and is_true(valid_delay_reg(ADDER_PIPELINE-2)) else '0';


	-- パイプライン加算器 

	process (clk) begin
		if rising_edge(clk) then
			if is_true(proc_enable_sig) then
				if (MAXKERNEL_NUMBER = 1) then
					-- stage1
					adder_sum_reg <= 
						slice_sxt(accum_data_sig, 32+4, 0) +
						slice_sxt(slice(kernel_data_sig, 32, 0*32), 32+4, 0);

					-- stage2
					adder_data_reg <= adder_result_sig;

				elsif (MAXKERNEL_NUMBER <= 4) then
					-- stage1
					adder_accum_reg <= accum_data_sig;

					adder_tmp0_reg <=
						slice_sxt(slice(kernel_data_sig, 32, 0*32), 32+1, 0) +
						slice_sxt(slice(kernel_data_sig, 32, 1*32), 32+1, 0);

					adder_tmp1_reg <=
						slice_sxt(slice(kernel_data_sig, 32, 2*32), 32+1, 0) +
						slice_sxt(slice(kernel_data_sig, 32, 3*32), 32+1, 0);

					-- stage2
					adder_sum_reg <=
						slice_sxt(adder_accum_reg, 32+4, 0) +
						slice_sxt(adder_tmp0_reg,  32+4, 0) +
						slice_sxt(adder_tmp1_reg,  32+4, 0);

					-- stage3
					adder_data_reg <= adder_result_sig;

				else
					-- stage1
					adder_accum_reg <= accum_data_sig;

					adder_tmp0_reg <=
						slice_sxt(slice(kernel_data_sig, 32, 0*32), 32+1, 0) +
						slice_sxt(slice(kernel_data_sig, 32, 1*32), 32+1, 0);

					adder_tmp1_reg <=
						slice_sxt(slice(kernel_data_sig, 32, 2*32), 32+1, 0) +
						slice_sxt(slice(kernel_data_sig, 32, 3*32), 32+1, 0);

					adder_tmp2_reg <=
						slice_sxt(slice(kernel_data_sig, 32, 4*32), 32+1, 0) +
						slice_sxt(slice(kernel_data_sig, 32, 5*32), 32+1, 0);

					adder_tmp3_reg <=
						slice_sxt(slice(kernel_data_sig, 32, 6*32), 32+1, 0) +
						slice_sxt(slice(kernel_data_sig, 32, 7*32), 32+1, 0);

					-- stage2
					adder_tmp4_reg <=
						slice_sxt(adder_accum_reg, 32+3, 0) +
						slice_sxt(adder_tmp0_reg,  32+3, 0) +
						slice_sxt(adder_tmp1_reg,  32+3, 0);

					adder_tmp5_reg <=
						slice_sxt(adder_tmp2_reg,  32+3, 0) +
						slice_sxt(adder_tmp3_reg,  32+3, 0);

					-- stage3
					adder_sum_reg <=
						slice_sxt(adder_tmp4_reg,  32+4, 0) +
						slice_sxt(adder_tmp5_reg,  32+4, 0);

					-- stage4
					adder_data_reg <= adder_result_sig;

				end if;
			end if;

		end if;
	end process;

	adder_sign_sig <= adder_sum_reg(adder_sign_sig'range);
	adder_sat_sig <= '1' when(or_reduce(adder_sign_sig) /= and_reduce(adder_sign_sig)) else '0';	-- 符号ビットが同値ではない 
	adder_result_sig <=
		adder_sum_reg(adder_result_sig'range) when is_false(adder_sat_sig) else
		(31=>adder_sign_sig(adder_sign_sig'left), others=>not adder_sign_sig(adder_sign_sig'left));	-- 正負の最大値に飽和 


	-- パイプライン乗算器 

	gen_kernel_eq1 : if (MAXKERNEL_NUMBER = 1) generate
		mult_dataa_sig <= slice_sxt(accum_data_sig, mult_dataa_sig'length, 14);						-- [31:14]
		mult_datab_sig <= slice_sxt(slice(kernel_data_sig, 32, 0*32), mult_datab_sig'length, 14);	-- [31:14]
	end generate;
	gen_kernel_gt1 : if (MAXKERNEL_NUMBER > 1) generate
		mult_dataa_sig <= slice_sxt(slice(kernel_data_sig, 32, 0*32), mult_dataa_sig'length, 14);	-- [31:14]
		mult_datab_sig <= slice_sxt(slice(kernel_data_sig, 32, 1*32), mult_datab_sig'length, 14);	-- [31:14]
	end generate;

	u_mult : lpm_mult
	generic map(
		lpm_type			=> "LPM_MULT",
		lpm_representation	=> "SIGNED",
		lpm_pipeline		=> MULT_PIPELINE,
		lpm_widtha			=> 18,
		lpm_widthb			=> 18,
		lpm_widthp			=> 36
	)
	port map(
		clock	=> clk,
		clken	=> proc_enable_sig,
		dataa	=> mult_dataa_sig,
		datab	=> mult_datab_sig,
		result	=> mult_result_sig	-- (s18 x s18) -> s36 *resultの上位2bitは必ず符号ビット 
	);

	mult_data_sig <= slice_sxt(mult_result_sig, mult_data_sig'length, 4);	-- [34:4] → s32に符号拡張切り出し 



end RTL;
