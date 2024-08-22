-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - fully connected
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2023/12/08 -> 2023/12/13
--            : 2024/03/15 (FIXED)
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

-- ・実装todo 
-- [X] メモリ読み出しステート 
-- [X] 内積演算 
-- [X] 積和レジスタ初期値ロード 
--
-- ・検証todo 
-- [X] ストール制御の可否(backpressure制御が行われるか？)
-- [X] 飽和演算とフラグの挙動 
-- [X] init信号アボートの動作(正しく復帰するか？タイミングを勘違いしている部分はないか？) 
-- [X] 32bitで確認したらgenericを変えて確認する(バス幅で計算結果が変わらないかどうか見る)
--
-- ・リソース概算 
-- 490LE + 4DSP + 1M9k (32bit幅, 8ワードバースト, FIFOフローチェックOFF時)
-- 520LE + 4DSP + 1M9k (32bit幅, 64ワードバースト)
-- 950LE + 32DSP + 8M9k (256bit幅, 256ワードバースト)


-- status(0) : Error, Bus access cannot be continued. (no use. always 0)
-- status(1) : reserved. (no use. always 0)
-- status(2) : Warning, Saturation occurs in channel sum calculation.
--
-- fc_channel_num : Output data length
-- vectordata_num : Input vector length
-- vectordata_top : Start address of vector data (Must be 32byte alignment) 
-- weightdata_top : Start address of weight data (Must be 32byte alignment) 
-- matmulbias     : Matrix bias data (int32)
--
-- データバス幅単位での並列演算を行うため、各ベクトルの開始アドレス(V(0)および
-- W(c,0)は32バイト境界でなければならない。 
-- V(i)の数がバス幅に足りない場合、無効データ部分はW(c,i)は0を設定しておく。 
-- 通常、W(c,i)の無効部分(パディング領域)を0フィルすることで対処する。 


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

entity peridot_cnn_fullyconn is
	generic(
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		RDMAXBURST_POW2_NUMBER	: integer := 4;		-- 読み出しバースト長 (3:8ワード ～ 11:2048 *バス幅単位)
		FIFO_FLOW_CHECKING		: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 
		FIFO_SPEED_OPTION		: string := "ON";	-- FIFOのインスタンスオプション(ON=speed / OFF=area)

		-- SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
		test_start			: out std_logic;
		test_finally		: out std_logic;
		test_memread_ready	: out std_logic;
		test_rdfifo_flush	: out std_logic;
		test_rdfifo_wrreq	: out std_logic;
		test_rdfifo_full	: out std_logic;
		test_rdfifo_rdack	: out std_logic;
		test_rdfifo_empty	: out std_logic;

		test_datavalid		: out std_logic;
		test_vdata			: out std_logic_vector(2**(DATABUS_POW2_NUMBER-1)-1 downto 0);
		test_wdata			: out std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		test_datalast		: out std_logic;
		test_sat			: out std_logic;


		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: in  std_logic := '0';
		start			: in  std_logic;
		ready			: out std_logic;
		error			: out std_logic;
		status			: out std_logic_vector(2 downto 0);
		fc_calc_mode	: in  std_logic_vector(1 downto 0);
		fc_channel_num	: in  std_logic_vector(12 downto 0);
		vectordata_num	: in  std_logic_vector(17 downto 0);
		vectordata_top	: in  std_logic_vector(31 downto 0);
		weightdata_top	: in  std_logic_vector(31 downto 0);
		matmulbias		: in  std_logic_vector(31 downto 0);

		read_request	: out std_logic;
		read_complete	: out std_logic;
		read_address	: out std_logic_vector(31 downto 0);
		read_burstcount	: out std_logic_vector(RDMAXBURST_POW2_NUMBER downto 0);
		read_datavalid	: in  std_logic;
		read_data		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);

		sto_ready		: in  std_logic;
		sto_valid		: out std_logic;
		sto_data		: out std_logic_vector(31 downto 0);
		sto_endofline	: out std_logic;
		sto_endofframe	: out std_logic
	);
end peridot_cnn_fullyconn;

architecture RTL of peridot_cnn_fullyconn is
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

	-- モジュール固定値 
	constant STARTALIGN_WIDTH	: integer := 5;			-- データ先頭のアライメントサイズ (5=32バイトで固定)
	constant RD_DCFIFO_WIDTHU	: integer := RDMAXBURST_POW2_NUMBER-1;		-- 読み出しFIFOの深さ(最大バースト長の半分) 
	constant ALIGN_ADDR_WIDTH	: integer := DATABUS_POW2_NUMBER-3;			-- ワード境界のアドレスビット幅 
	constant BURST_MAXLENGTH	: integer := 2**RDMAXBURST_POW2_NUMBER;		-- 最大バースト長 

	-- 内積演算器のパイプライン数 
		-- DATABUS_POW2_NUMBER = 5	: 5-stage
		-- DATABUS_POW2_NUMBER = 6	: 6-stage
		-- DATABUS_POW2_NUMBER = 7	: 6-stage
		-- DATABUS_POW2_NUMBER = 8	: 7-stage
	function sel(F:boolean; A,B:integer) return integer is begin if F then return A; else return B; end if; end;
	constant PRODUCT_PIPELINE	: integer := sel(DATABUS_POW2_NUMBER = 5, 5, sel(DATABUS_POW2_NUMBER <= 7, 6, 7));


	-- 全体制御 
	signal init_sig				: std_logic;
	signal start_sig			: std_logic;
	signal finally_sig			: std_logic;
	signal ready_sig			: std_logic;
	signal sto_ready_sig		: std_logic;
	signal proc_enable_sig		: std_logic;
	signal ready_reg			: std_logic;
--	signal error_deviated_reg	: std_logic;	-- fcではアサートされないエラー信号 ('0'に固定) 
	signal error_opsat_reg		: std_logic;

	-- 入力データ／重み係数読み込み制御ブロック 
	type DEF_STATE_MEMREAD is (READIDLE, READSETUP, READREQ, READDATA, READDONE, CALCDONE);
	signal state_memread : DEF_STATE_MEMREAD;
	signal memread_init_sig		: std_logic;
	signal memread_ready_sig	: std_logic;
	signal calcfinally_reg		: std_logic;
	signal fifoqueue_reg		: std_logic;
	signal vdata_sel_reg		: std_logic;
	signal sign_ena_reg			: std_logic;
	signal cnum_reg				: std_logic_vector(fc_channel_num'range);
	signal totalwordnum_reg		: std_logic_vector(vectordata_num'left - ALIGN_ADDR_WIDTH downto 0);
	signal wd_address_reg		: std_logic_vector(31 downto ALIGN_ADDR_WIDTH);
	signal vd_address_reg		: std_logic_vector(31 downto ALIGN_ADDR_WIDTH);
	signal vdtop_address_reg	: std_logic_vector(31 downto ALIGN_ADDR_WIDTH);
	signal read_request_reg		: std_logic;
	signal rd_address_reg		: std_logic_vector(31 downto ALIGN_ADDR_WIDTH);
	signal rd_datanum_reg		: std_logic_vector(read_burstcount'range);
	signal rd_remain_reg		: std_logic_vector(totalwordnum_reg'range);
	signal rd_fiforeq_sig		: std_logic;
	signal read_datavalid_sig	: std_logic;

	signal rdfifo_flush_sig		: std_logic;
	signal rdfifo_wrreq_sig		: std_logic;
	signal rdfifo_full_sig		: std_logic;
	signal rdfifo_rdack_sig		: std_logic;
	signal rdfifo_q_sig			: std_logic_vector(read_data'range);
	signal rdfifo_empty_sig		: std_logic;
	signal datavalid_sig		: std_logic;
	signal vdata_sig			: std_logic_vector(read_data'length/2-1 downto 0);
	signal wdata_sig			: std_logic_vector(read_data'range);
	signal bias_sig				: std_logic_vector(38 downto 0);
	signal datalast_sig			: std_logic;

	-- 内積演算ブロック 
	signal datalast_delay_reg	: std_logic_vector(PRODUCT_PIPELINE-1 downto 0);
	signal product_valid_sig	: std_logic;
	signal product_eol_sig		: std_logic;
	signal product_eof_sig		: std_logic;
	signal product_init_sig		: std_logic;
	signal result_sig			: std_logic_vector(31 downto 0);
	signal sat_sig				: std_logic;


	-- コンポーネント宣言 
	component peridot_cnn_fullyconn_product
	generic(
		DATABUS_POW2_NUMBER		: integer
	);
	port(
		clk			: in  std_logic;
		init		: in  std_logic := '0';		-- initialize
		enable		: in  std_logic := '1';		-- clock enable

		sign_ena	: in  std_logic;			-- vector data sign extension : '1'=signed 8bit / '0'=unsigned 8bit
		valid		: in  std_logic := '1';		-- data valid
		vector		: in  std_logic_vector(2**(DATABUS_POW2_NUMBER-1)-1 downto 0);	-- vectordata (8bit x n)
		weight		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);		-- weightdata (16bit x n)
		bias		: in  std_logic_vector(38 downto 0) := (others=>'0');			-- bias

		result		: out std_logic_vector(31 downto 0);
		saturated	: out std_logic
	);
	end component;

begin

	-- テスト記述 

	test_start <= start_sig;
	test_finally <= finally_sig;
	test_memread_ready <= memread_ready_sig;

	test_rdfifo_flush <= rdfifo_flush_sig;
	test_rdfifo_wrreq <= rdfifo_wrreq_sig;
	test_rdfifo_full <= rdfifo_full_sig;
	test_rdfifo_rdack <= rdfifo_rdack_sig;
	test_rdfifo_empty <= rdfifo_empty_sig;

	test_datavalid <= datavalid_sig;
	test_vdata <= vdata_sig;
	test_wdata <= wdata_sig;
	test_datalast <= datalast_sig;
	test_sat <= sat_sig;


	-- パラメータ範囲チェック 

	assert (DATABUS_POW2_NUMBER >= 5 and DATABUS_POW2_NUMBER <= 8)
		report "DATABUS_POW2_NUMBER is out of range." severity FAILURE;

	assert (RDMAXBURST_POW2_NUMBER >= 3 and RDMAXBURST_POW2_NUMBER <= 11)
		report "RDMAXBURST_POW2_NUMBER is out of range. Equal or less than 11." severity FAILURE;

	assert (read_burstcount'length <= 11)
		report "Avalon-MM burstcount port width is out of range. Equal or less than 11." severity FAILURE;



	----------------------------------------------------------------------
	-- モジュール全体制御 
	----------------------------------------------------------------------

	init_sig <= init;
	ready_sig <= ready_reg;

	ready <= ready_sig;
	error <= '0';					-- fcではerrorはアサートされない ('0'に固定) 
	status <= error_opsat_reg & "00";


	-- 開始信号と終了信号生成 

	start_sig <= start when is_true(ready_sig) else '0';
	finally_sig <= calcfinally_reg;

	process (clk, reset) begin
		if is_true(reset) then
			ready_reg <= '1';
			error_opsat_reg <= '0';

		elsif rising_edge(clk) then
			-- バストランザクションFSMの異常で続行できない 
			-- * fcではバストランザクション異常の場合はerror_deviatedはアサートせず、readyが戻らない 

			-- 飽和演算でオーバーフローが発生した 
			if is_true(init_sig) or is_true(start_sig) then
				error_opsat_reg <= '0';
			elsif is_true(sat_sig) then
				error_opsat_reg <= '1';
			end if;

			-- ready信号 
			if is_true(init_sig) or is_true(finally_sig) then
				ready_reg <= memread_ready_sig;
			elsif is_true(start_sig) then
				ready_reg <= '0';
			end if;

		end if;
	end process;


	-- 結果出力とAvalonSTフロー制御 

	sto_ready_sig <= sto_ready;
	proc_enable_sig <= '0' when is_false(sto_ready_sig) and is_true(product_valid_sig) else '1';

	sto_valid <= product_valid_sig;
	sto_data <= result_sig;
	sto_endofline <= product_eol_sig;
	sto_endofframe <= product_eof_sig;



	----------------------------------------------------------------------
	-- 入力データ／重み係数読み込み制御 
	----------------------------------------------------------------------

	memread_init_sig <= init_sig;
	memread_ready_sig <= '1' when(state_memread = READIDLE) else '0';


	-- メモリリードリクエスト 

	read_request <= read_request_reg;
	read_complete <= '1' when(state_memread = READDONE) else '0';
	read_address <= rd_address_reg & repbit('0', ALIGN_ADDR_WIDTH);
	read_burstcount <= rd_datanum_reg;
	read_datavalid_sig <= read_datavalid;


	-- バーストリードおよび全体制御 

	process (clk, reset) begin
		if is_true(reset) then
			state_memread <= READIDLE;
			calcfinally_reg <= '0';
			read_request_reg <= '0';

		elsif rising_edge(clk) then
			case state_memread is

			-- 開始信号を待つ 

			when READIDLE =>
				calcfinally_reg <= '0';

				if is_true(start_sig) then
					state_memread <= READSETUP;

					-- 符号モード選択 
					sign_ena_reg <= fc_calc_mode(0);

					-- 行要素数(チャネル数)のロード 
					cnum_reg <= fc_channel_num;

					-- ベクタ長を重みデータの読み出しワード数に変換 
					if (vectordata_num(ALIGN_ADDR_WIDTH-2 downto 0) /= 0) then
						totalwordnum_reg <= slice(vectordata_num, totalwordnum_reg'length, ALIGN_ADDR_WIDTH-1) + 1;
					else
						totalwordnum_reg <= slice(vectordata_num, totalwordnum_reg'length, ALIGN_ADDR_WIDTH-1);
					end if;

					-- 読み出し先頭アドレスの確定 
					vdtop_address_reg <= vectordata_top(vd_address_reg'range);	-- 入力データ(ベクタ長)
					wd_address_reg <= weightdata_top(wd_address_reg'range);		-- 重み係数(ベクタ長×チャネル数)
				end if;

			-- アフィン演算1行分のループ 

			when READSETUP =>
				state_memread <= READREQ;
				fifoqueue_reg <= '1';
				vd_address_reg <= vdtop_address_reg;
				rd_remain_reg <= totalwordnum_reg;

			when READREQ =>
				-- 初期化リクエストが来ていたら中断する 
				if is_true(memread_init_sig) then
					state_memread <= READIDLE;

				-- 入力データ／重みデータの読み込み要求 (入力データ読み込み開始時はFIFOは空になっている) 
				else
					state_memread <= READDATA;
					read_request_reg <= '1';
				end if;

				vdata_sel_reg <= '0';

				-- 入力データのアドレスと読み込みデータ数の設定 
				if is_true(fifoqueue_reg) then
					rd_address_reg <= vd_address_reg;

					if (rd_remain_reg >= BURST_MAXLENGTH) then
						rd_datanum_reg <= to_vector(BURST_MAXLENGTH/2, rd_datanum_reg'length);
					else
						rd_datanum_reg <= slice(rd_remain_reg, rd_datanum_reg'length, 1) + rd_remain_reg(0);
					end if;

				-- 重み係数のアドレスを読み込みデータ数の設定 
				else
					rd_address_reg <= wd_address_reg;

					if (rd_remain_reg >= BURST_MAXLENGTH) then
						rd_datanum_reg <= to_vector(BURST_MAXLENGTH, rd_datanum_reg'length);
					else
						rd_datanum_reg <= slice(rd_remain_reg, rd_datanum_reg'length, 0);
					end if;

				end if;

			when READDATA =>
				-- データが送られてきたらFIFOへ書き込む／演算を行う 
				if is_true(read_datavalid_sig) then
					if (rd_datanum_reg = 1) then
						state_memread <= READDONE;
					end if;

					read_request_reg <= '0';
					rd_datanum_reg <= rd_datanum_reg - 1;

					if is_true(fifoqueue_reg) then
						vd_address_reg <= vd_address_reg + 1;	-- 入力データアドレスを更新 
					else
						vdata_sel_reg <= not vdata_sel_reg;
						rd_remain_reg <= rd_remain_reg - 1;
						wd_address_reg <= wd_address_reg + 1;	-- 重み係数アドレスを更新 
					end if;
				end if;

			when READDONE =>
				-- データを全て読み終わっていたら結果出力へ 
				if (rd_remain_reg = 0) then
					state_memread <= CALCDONE;
				else
					state_memread <= READREQ;
				end if;

				-- 重み係数データアドレスのアライメント調整(データ幅256bit以下の場合は32バイト境界に切り上げる)
				if (DATABUS_POW2_NUMBER < 8) then
					if (wd_address_reg(STARTALIGN_WIDTH-1 downto wd_address_reg'right) /= 0) then
						wd_address_reg(wd_address_reg'left downto STARTALIGN_WIDTH) <= wd_address_reg(wd_address_reg'left downto STARTALIGN_WIDTH) + 1;
						wd_address_reg(STARTALIGN_WIDTH-1 downto wd_address_reg'right) <= (others=>'0');
					end if;
				end if;

				fifoqueue_reg <= not fifoqueue_reg;


			-- 計算結果出力 

			when CALCDONE =>
				-- 初期化リクエストが来ていたら中断する 
				if is_true(memread_init_sig) then
					state_memread <= READIDLE;

				-- 行要素数をすべて処理したら終了 
				elsif is_true(product_valid_sig) and is_true(sto_ready_sig) then
					if (cnum_reg = 1) then
						state_memread <= READIDLE;
						calcfinally_reg <= '1';
					else
						state_memread <= READSETUP;
					end if;

					cnum_reg <= cnum_reg - 1;
				end if;

			end case;
		end if;
	end process;


	-- 入力FIFOのインスタンス 

	rdfifo_flush_sig <= '1' when(state_memread = READSETUP) else '0';
	rdfifo_wrreq_sig <= read_datavalid_sig when is_true(fifoqueue_reg) else '0';
	rdfifo_rdack_sig <= read_datavalid_sig when is_true(vdata_sel_reg) else '0';

	u_rdfifo : scfifo
	generic map (
		lpm_type			=> "scfifo",
		lpm_showahead		=> "ON",
		lpm_numwords		=> 2**RD_DCFIFO_WIDTHU,
		lpm_widthu			=> RD_DCFIFO_WIDTHU,
		lpm_width			=> 2**DATABUS_POW2_NUMBER,
		add_ram_output_register => FIFO_SPEED_OPTION,
		overflow_checking	=> FIFO_FLOW_CHECKING,
		underflow_checking	=> FIFO_FLOW_CHECKING
	)
	port map (
		clock	=> clk,
		sclr	=> rdfifo_flush_sig,

		wrreq	=> rdfifo_wrreq_sig,
		data	=> read_data,
		full	=> rdfifo_full_sig,

		rdreq	=> rdfifo_rdack_sig,	-- ack
		q		=> rdfifo_q_sig,
		empty	=> rdfifo_empty_sig
	);


	-- 演算データ 

	datavalid_sig <= read_datavalid_sig when is_false(fifoqueue_reg) else '0';
	vdata_sig <=
		slice(rdfifo_q_sig, vdata_sig'length, vdata_sig'length) when is_true(vdata_sel_reg) else
		slice(rdfifo_q_sig, vdata_sig'length, 0);
	wdata_sig <= read_data;
	datalast_sig <= read_datavalid_sig when(rd_remain_reg = 1) else '0';



	----------------------------------------------------------------------
	-- ベクトル内積演算 
	----------------------------------------------------------------------

	-- タイミング信号生成 

	process (clk) begin
		if rising_edge(clk) then
			if is_true(ready_sig) then
				datalast_delay_reg <= (others=>'0');
			elsif is_true(proc_enable_sig) then
				datalast_delay_reg <= shiftin(datalast_delay_reg, datalast_sig);
			end if;
		end if;
	end process;

	product_valid_sig <= shiftout(datalast_delay_reg);
	product_eof_sig <= shiftout(datalast_delay_reg) when(cnum_reg = 1) else '0';
	product_eol_sig <= product_eof_sig;


	-- 内積演算器のインスタンス 

	product_init_sig <= '1' when(state_memread = READSETUP) else '0';
	bias_sig <= slice_sxt(matmulbias, bias_sig'length, 0);

	u_product : peridot_cnn_fullyconn_product
	generic map (
		DATABUS_POW2_NUMBER		=> DATABUS_POW2_NUMBER
	)
	port map (
		clk			=> clk,
		init		=> product_init_sig,
		enable		=> proc_enable_sig,

		sign_ena	=> sign_ena_reg,
		valid		=> datavalid_sig,
		vector		=> vdata_sig,
		weight		=> wdata_sig,
		bias		=> bias_sig,

		result		=> result_sig,
		saturated	=> sat_sig
	);



end RTL;
