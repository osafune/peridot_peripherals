-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - accumulator
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/08/17 -> 2020/09/18
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
-- ■ ready信号まわりの実装 
-- ■ errorとstatus信号まわりの実装 
-- □ parallel_addモジュールを使わない場合の実装(いったん実機検証をしてから) 

-- ・検証残り
-- ■ init信号アボート 
-- ■ ストール制御の可否(backpressure制御が行われるか？) → 最低限の動作を確認 
-- ■ 飽和演算とフラグの挙動 
-- ■ エラーインジェクションテスト (force_error操作して確認)
-- ■ fifo_fullの時の挙動(RD_DCFIFO_WIDTHUを浅くしてテスト) 
-- □ 32bitで確認したらgenericを変えて確認する(ライン長を変更してsimが変わらないかどうか見る)

-- ・リソース概算
-- 360LE + 1M9k (1カーネル,32bit幅,RDFIFO 128ワード,8ワードバースト,FIFOフローチェックOFF時)
-- 620LE + 4M9k (4カーネル,32bit幅,RDFIFO 512ワード,64ワードバースト時)
-- 900LE +16M9k (8カーネル,256bit幅,RDFIFO 4096ワード時,256ワードバースト時)

-- status(0) : Error, Bus access cannot be continued.
-- status(1) : Warning, Saturation occurs in channel sum calculation.

-- biasinit_ena : Initialize temporary buffer with bias(=1) / load a temporary buffer(=0)
-- bias_data : b(k) value (他のパラメータと違ってstart信号でラッチされないので注意)
-- rd_address_top : 中間値バッファ先頭アドレス (バス幅境界アドレスのみ指定可能) 
-- rd_totalnum : 読み込む中間値ワード数 


-- VHDL 1993 / IEEE 1076-1993
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_misc.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity peridot_cnn_accum is
	generic(
		MAXKERNEL_NUMBER		: integer := 4;		-- カーネルインスタンス数 (1～8)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		RDFIFODEPTH_POW2_NUMBER	: integer := 9;		-- 読み出しFIFOの深さ (7:128ワード ～ 12:4096ワード *出力ワード単位)
		RDMAXBURST_POW2_NUMBER	: integer := 4;		-- 読み出しバースト長 (3:8ワード ～ RD_DCFIFO_WIDTHU-1 *バースト上限はFIFO読み出し側の半分まで)
		FIFO_FLOW_CHECKING		: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 

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
		test_accum_data		: out std_logic_vector(31 downto 0);
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
		error			: out std_logic;						-- errorがアサートされたらreadyには戻らない 
		status			: out std_logic_vector(1 downto 0);
		biasinit_ena	: in  std_logic;
		bias_data		: in  std_logic_vector(31 downto 0);	-- モジュール内でラッチしない 
		rd_address_top	: in  std_logic_vector(31 downto 0);
		rd_totalnum		: in  std_logic_vector(22 downto 0);

		read_request	: out std_logic;
		read_complete	: out std_logic;
		read_address	: out std_logic_vector(31 downto 0);
		read_burstcount	: out std_logic_vector(RDMAXBURST_POW2_NUMBER downto 0);
		read_data		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		read_datavalid	: in  std_logic;

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

-- TEST
--	constant RD_DCFIFO_WIDTHU	: integer := 5;	-- 読み出しFIFOの深さ(テスト用) 

	-- モジュール固定値 
	constant FIFO_SYNC_DELAYPIPE: integer := 4;			-- FIFOのrdsync_delaypipe/wrsync_delaypipeオプション (4で固定) 
	constant FIFO_ARESET_CYCLE	: integer := 4;			-- FIFOの非同期初期化クロック数 (FIFO_SYNC_DELAYPIPE以上)
	constant RD_DCFIFO_WIDTHU	: integer := RDFIFODEPTH_POW2_NUMBER-(DATABUS_POW2_NUMBER-5);	-- 読み出しFIFOの深さ 
	constant ALIGN_ADDR_WIDTH	: integer := DATABUS_POW2_NUMBER-3;			-- ワード境界のアドレスビット幅 
	constant BURST_MAXLENGTH	: integer := 2**RDMAXBURST_POW2_NUMBER;		-- 最大バースト長 

	-- 加算器のパイプライン数 
	function sel(F:boolean; A,B:integer) return integer is begin if F then return A; else return B; end if; end;
	constant ADDER_PIPELINE		: integer := sel(MAXKERNEL_NUMBER = 1, 1, sel(MAXKERNEL_NUMBER < 4, 2, 3));


	-- 全体制御 
	signal init_sig				: std_logic;
	signal start_sig			: std_logic;
	signal finally_sig			: std_logic;
	signal ready_sig			: std_logic;
	signal proc_enable_sig		: std_logic;
	signal ready_reg			: std_logic;
	signal error_deviated_reg	: std_logic;
	signal error_opsat_reg		: std_logic;

	-- 中間値データ読み込み制御ブロック 
	type DEF_STATE_MEMREAD is (READIDLE, READFIFOINIT, READREQ, READDATA, READDONE);
	signal state_memread : DEF_STATE_MEMREAD;
	signal memread_init_sig		: std_logic;
	signal memread_ready_sig	: std_logic;
	signal fifoinit_counter		: integer range 0 to FIFO_ARESET_CYCLE-1;
	signal fifoinit_reg			: std_logic;
	signal read_request_reg		: std_logic;
	signal biasinit_ena_reg		: std_logic;
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
	signal accum_data_sig		: std_logic_vector(31 downto 0);
	signal accum_valid_sig		: std_logic;

	-- 総和演算ブロック 
	signal valid_all_sig		: std_logic;
	signal valid_delay_reg		: std_logic_vector(ADDER_PIPELINE-1 downto 0);
	signal endofframe_delay_reg	: std_logic_vector(ADDER_PIPELINE-1 downto 0);
	signal endofline_delay_reg	: std_logic_vector(ADDER_PIPELINE-1 downto 0);
	signal kernel_valid_sig		: std_logic_vector(MAXKERNEL_NUMBER downto 0);
	signal kernel_data_sig		: std_logic_vector((MAXKERNEL_NUMBER+1)*32-1 downto 0);
	signal kernel_sum_sig		: std_logic_vector(31 downto 0);
	signal adder_valid_sig		: std_logic;
	signal adder_data_sig		: altera_mf_logic_2d(MAXKERNEL_NUMBER downto 0, 31 downto 0);
	signal adder_result_sig		: std_logic_vector(35 downto 0);
	signal adder_eof_sig		: std_logic;
	signal adder_eol_sig		: std_logic;
	signal adder_sign_sig		: std_logic_vector(adder_result_sig'left downto 31);
	signal adder_sat_sig		: std_logic;


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
	test_accum_data <= accum_data_sig;
	test_accum_valid <= accum_valid_sig;
	test_valid_all <= valid_all_sig;
	test_valid_delay <= slice(valid_delay_reg, 6, 0);
	test_adder_sat <= adder_sat_sig;

	test_proc_enable <= proc_enable_sig;


	-- パラメータ範囲チェック 

	assert (MAXKERNEL_NUMBER >= 1 and MAXKERNEL_NUMBER <= 8)
		report "MAXKERNEL_NUMBER is out of range.";

	assert (DATABUS_POW2_NUMBER >= 5 and DATABUS_POW2_NUMBER <= 8)
		report "DATABUS_POW2_NUMBER is out of range.";

	assert (RDFIFODEPTH_POW2_NUMBER >= 7 and RDFIFODEPTH_POW2_NUMBER <= 12)
		report "RDFIFODEPTH_POW2_NUMBER is out of range.";

	assert (RDMAXBURST_POW2_NUMBER >= 3 and RDMAXBURST_POW2_NUMBER <= (RD_DCFIFO_WIDTHU-1))
		report "RDMAXBURST_POW2_NUMBER is out of range. Less then " & integer'image(RD_DCFIFO_WIDTHU-1);

	assert (read_burstcount'length <= 11)
		report "Avalon-MM burstcount port width is out of range. Less then 11.";



	----------------------------------------------------------------------
	-- モジュール全体制御 
	----------------------------------------------------------------------

	init_sig <= init;
	ready_sig <= ready_reg;

	ready <= ready_sig;
	error <= error_deviated_reg;
	status <= error_opsat_reg & error_deviated_reg;


	-- 開始信号と終了信号生成 

	start_sig <= start when is_true(ready_sig) else '0';
	finally_sig <= adder_eof_sig when is_true(proc_enable_sig) else '0';

	process (clk, reset) begin
		if is_true(reset) then
			ready_reg <= '1';
			error_deviated_reg <= '0';
			error_opsat_reg <= '0';

		elsif rising_edge(clk) then
			-- バストランザクションFSMの異常で続行できない 
			if is_true(finally_sig) and is_false(memread_ready_sig) then
				error_deviated_reg <= '1';
			end if;

			-- 飽和演算でオーバーフローが発生した 
			if is_true(init_sig) or is_true(start_sig) then
				error_opsat_reg <= '0';
			elsif is_true(adder_sat_sig) and is_true(adder_valid_sig) then
				error_opsat_reg <= '1';
			end if;

			-- ready信号 
			if is_true(init_sig) and is_true(memread_ready_sig) then
				ready_reg <= '1';
			elsif is_true(finally_sig) then
				ready_reg <= memread_ready_sig;
			elsif is_true(start_sig) then
				ready_reg <= '0';
			end if;

		end if;
	end process;


	-- 結果出力とAvalonSTフロー制御 

	proc_enable_sig <= '0' when is_false(sto_ready) and is_true(adder_valid_sig) else '1';

	sto_valid <= adder_valid_sig;
	sto_data <= kernel_sum_sig;
	sto_endofframe <= adder_eof_sig;
	sto_endofline <= adder_eol_sig;



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
					-- 読み出しモードの確定 
					if is_false(biasinit_ena) then
						state_memread <= READFIFOINIT;
						biasinit_ena_reg <= '0';
					else
						biasinit_ena_reg <= '1';
					end if;

					fifoinit_reg <= '1';
					fifoinit_counter <= FIFO_ARESET_CYCLE - 1;

					-- 読み出し先頭アドレスの確定 
					rd_address_reg <= rd_address_top(rd_address_reg'range);

					-- トータルデータ書き込み数カウンタ 
					rd_totalnum_reg <= rd_totalnum(rd_totalnum_reg'range);
				end if;

			when READFIFOINIT =>
				-- 入力FIFOの非同期初期化 
				if (fifoinit_counter = 0) then
					state_memread <= READREQ;
					fifoinit_reg <= '0';
				end if;

				fifoinit_counter <= fifoinit_counter - 1;


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

	rdfifo_areset_sig <= fifoinit_reg;
	rdfifo_rdack_sig <= proc_enable_sig when is_true(valid_all_sig) and is_false(rdfifo_empty_sig) else '0';

	u_rdfifo : dcfifo_mixed_widths
	generic map (
		intended_device_family => DEVICE_FAMILY,
		lpm_type => "dcfifo",
		lpm_showahead => "ON",
		lpm_numwords => 2**RD_DCFIFO_WIDTHU,
		lpm_widthu => RD_DCFIFO_WIDTHU,
		lpm_width => read_data'length,
		lpm_widthu_r => RDFIFODEPTH_POW2_NUMBER,
		lpm_width_r => 32,
		add_usedw_msb_bit => "ON",
		overflow_checking => FIFO_FLOW_CHECKING,
		underflow_checking => FIFO_FLOW_CHECKING,
		use_eab => "ON",
		write_aclr_synch => "ON",
		rdsync_delaypipe => FIFO_SYNC_DELAYPIPE,
		wrsync_delaypipe => FIFO_SYNC_DELAYPIPE
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


	accum_valid_sig <= '1' when is_true(biasinit_ena_reg) or is_false(rdfifo_empty_sig) else '0';
	accum_data_sig <= bias_data when is_true(biasinit_ena_reg) else rdfifo_q_sig;



	----------------------------------------------------------------------
	-- 加算制御 (指定のカーネル数のストリームを加算)
	----------------------------------------------------------------------

	-- 入力データのシンクロ 

	kernel_valid_sig(0) <= accum_valid_sig;
	kernel_data_sig(31 downto 0) <= accum_data_sig;

	gen_sti : for i in 1 to MAXKERNEL_NUMBER generate
		kernel_valid_sig(i) <= sti_valid(i-1) when is_true(kernel_ena(i-1)) else '1';
		kernel_data_sig((i+1)*32-1 downto i*32) <= sti_data(i*32-1 downto (i-1)*32) when is_true(kernel_ena(i-1)) else (others=>'0');
	end generate;

	valid_all_sig <= and_reduce(kernel_valid_sig);

	sti_ready <= proc_enable_sig when is_true(valid_all_sig) else '0';


	-- タイミング信号生成 

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

	adder_valid_sig <= shiftout(valid_delay_reg);
	adder_eof_sig <= shiftout(endofframe_delay_reg);
	adder_eol_sig <= shiftout(endofline_delay_reg);


	-- パイプライン加算器のインスタンス 

	gen_loop_i : for i in 0 to MAXKERNEL_NUMBER generate
		gen_loop_j : for j in 0 to 31 generate
			adder_data_sig(i, j) <= kernel_data_sig(i*32+j);
		end generate;
	end generate;

	u_adder : parallel_add
	generic map (
		lpm_type => "parallel_add",
		msw_subtract => "NO",
		representation => "SIGNED",
		result_alignment => "LSB",
		shift => 0,
		pipeline => ADDER_PIPELINE,
		size => MAXKERNEL_NUMBER+1,
		width => 32,
		widthr => adder_result_sig'length
	)
	port map (
		clock	=> clk,
		clken	=> proc_enable_sig,

		data	=> adder_data_sig,
		result	=> adder_result_sig
	);


	-- 飽和処理 
	adder_sign_sig <= adder_result_sig(adder_sign_sig'range);
	adder_sat_sig <= '1' when(or_reduce(adder_sign_sig) /= and_reduce(adder_sign_sig)) else '0';	-- 符号ビットが同値ではない 

	kernel_sum_sig <=
		adder_result_sig(kernel_sum_sig'range) when is_false(adder_sat_sig) else
		(31=>adder_sign_sig(adder_sign_sig'left), others=>not adder_sign_sig(adder_sign_sig'left));	-- 正負の最大値に飽和 



end RTL;
