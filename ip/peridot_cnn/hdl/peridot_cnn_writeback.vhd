-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - writeback
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/08/11 -> 2020/09/04
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
-- ■ byteenable追加で書き直す 
-- ■ バスマスタ付きに構成変更 
-- ■ Ready周りの制御の全面見直し 
-- ■ valid非連続への修正 
-- ■ write_complete→write_burstendへ変更、タイミング修正 

-- ・検証残り
-- ■ 修正した飽和演算の動作(pos19,pos15,pos11,pos7) 
-- ■ ラインデータvalidが分断されても正しく動くか(eol,eof等の境界部分を確認する) 
-- ■ 32bit以上でのファイナライズ処理 → 128bit/8burstで確認 
-- ■ avmm動作の確認 
-- ■ init信号アボート 
-- ■ 境界条件1:前段ファイナライズ後にavmmにぴったりバースト長のデータが残ってる 
-- ■ 境界条件2:前段ファイナライズ後にavmmにもうデータが残ってない(pooling時に発生)
-- ■ 境界条件3:32bit幅以上でダミーワード書き込み後にバースト長以下のデータが残っている(emptyディレイ)

-- ・リソース概算
--  480LE + 2M9k (32bit幅,256x256,WBFIFO 128ワード,8ワードバースト,FIFOフローチェックOFF時)
--  520LE + 3M9k (32bit幅,512x512,WBFIFO 512ワード,64ワードバースト時)
-- 1020LE +18M9k (256bit幅,2048x2048,WBFIFO 4096ワード時,256ワードバースト時)

-- relu_ena : ReLU/Pooling processing enable(=1)
-- decimal_pos : 19bit decimal places(=00)
--             : 15bit decimal places(=01)
--             : 11bit decimal places(=10)
--             :  7bit decimal places(=11)
-- pooling_ena : pooling enable(=1)
-- pooling_mode : simple pooling(=00) *(0,0)を返す 
--              : simple pooling(=01) *(1,1)を返す 
--              : max pooling(=10) *最大値を返す 
--              : avg pooling(=11) *平均値を返す 
-- wb_address_top : 書き戻しの先頭アドレス (バス幅境界アドレスのみ指定可能) 
-- wb_totalnum : 書き戻したワード数を返す (start→doneまでの総データ数) 


-- VHDL 1993 / IEEE 1076-1993
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_misc.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity peridot_cnn_writeback is
	generic(
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		MAXCONVSIZE_POW2_NUMBER	: integer := 9;		-- 畳み込み画像の最大値 (8:256x256 / 9:512x512 / 10:1024x1024 / 11:2048x2048)
		WBFIFODEPTH_POW2_NUMBER	: integer := 8;		-- 書き戻しFIFOの深さ (7:128ワード ～ 12:4096ワード *入力ワード単位)
		WBMAXBURST_POW2_NUMBER	: integer := 4;		-- 書き戻しバースト長 (3:8ワード ～ WB_SCFIFO_WIDTHU-1 *バースト上限はFIFO読み出し側の半分まで)
		FIFO_FLOW_CHECKING		: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 

		-- SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
		test_force_wbfull	: in  std_logic := '0';

		test_start			: out std_logic;
		test_relu_result	: out std_logic_vector(7 downto 0);
		test_relu_finally	: out std_logic;
		test_pool_x			: out std_logic_vector(8 downto 0);
		test_x_valid		: out std_logic;
		test_y_valid		: out std_logic;
		test_linefifo_wrreq	: out std_logic;
		test_linefifo_rdack	: out std_logic;
		test_linefifo_q		: out std_logic_vector(8 downto 0);
		test_linefifo_empty	: out std_logic;
		test_pool_data		: out std_logic_vector(7 downto 0);
		test_pool_valid		: out std_logic;
		test_pool_finally	: out std_logic;
		test_finalize_req	: out std_logic;
		test_wordwrite_last	: out std_logic;
		test_wb_worddata	: out std_logic_vector(31 downto 0);
		test_wb_byteenable	: out std_logic_vector(3 downto 0);
		test_wbfifo_wrreq	: out std_logic_vector(7 downto 0);
		test_wbfifo_empty	: out std_logic_vector(7 downto 0);
		test_wbfifo_usedw	: out std_logic_vector(12 downto 0);
		test_wbfifo_remain	: out std_logic;
		test_wr_fiforeq		: out std_logic;
		test_proc_enable	: out std_logic;


		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: in  std_logic := '0';
		start			: in  std_logic;
		ready			: out std_logic;
		relu_ena		: in  std_logic;
		decimal_pos		: in  std_logic_vector(1 downto 0);
		pooling_ena		: in  std_logic;
		pooling_mode	: in  std_logic_vector(1 downto 0);
		wb_address_top	: in  std_logic_vector(31 downto 0);
		wb_totalnum		: out std_logic_vector(22 downto 0);

		sti_ready		: out std_logic;
		sti_valid		: in  std_logic;
		sti_data		: in  std_logic_vector(31 downto 0);
		sti_endofline	: in  std_logic;
		sti_endofframe	: in  std_logic;

		write_request	: out std_logic;
		write_burstend	: out std_logic;
		write_address	: out std_logic_vector(31 downto 0);
		write_burstcount: out std_logic_vector(WBMAXBURST_POW2_NUMBER downto 0);
		write_data		: out std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		write_byteenable: out std_logic_vector(2**(DATABUS_POW2_NUMBER-3)-1 downto 0);
		write_dataack	: in  std_logic
	);
end peridot_cnn_writeback;

architecture RTL of peridot_cnn_writeback is
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
	constant WB_SCFIFO_WIDTHU	: integer := WBFIFODEPTH_POW2_NUMBER-(DATABUS_POW2_NUMBER-5);	-- 書き戻しFIFOの深さ 
	constant WB_SCFIFO_NUM		: integer := 2**(DATABUS_POW2_NUMBER-5);	-- 書き戻しFIFOのインスタンス数 
	constant ALIGN_ADDR_WIDTH	: integer := DATABUS_POW2_NUMBER-3;			-- ワード境界のアドレスビット幅 
	constant BURST_MAXLENGTH	: integer := 2**WBMAXBURST_POW2_NUMBER;		-- 最大バースト長 

	-- decposの設定値 
	constant PARAM_DECPOS_19	: std_logic_vector(1 downto 0) := "00";	-- 19bit小数モード *デフォルト 
	constant PARAM_DECPOS_15	: std_logic_vector(1 downto 0) := "01";	-- 15bit小数モード 
	constant PARAM_DECPOS_11	: std_logic_vector(1 downto 0) := "10";	-- 11bit小数モード 
	constant PARAM_DECPOS_7		: std_logic_vector(1 downto 0) := "11";	--  7bit小数モード 

	-- poolingの設定値 
	constant PARAM_POOL_P00		: std_logic_vector(1 downto 0) := "00";	-- p(0,0)を返す *デフォルト 
	constant PARAM_POOL_P11		: std_logic_vector(1 downto 0) := "01";	-- p(1,1)を返す 
	constant PARAM_POOL_MAX		: std_logic_vector(1 downto 0) := "10";	-- 最大値を返す 
	constant PARAM_POOL_AVG		: std_logic_vector(1 downto 0) := "11";	-- 平均値を返す 


	-- 全体制御 
	signal init_sig				: std_logic;
	signal start_sig			: std_logic;
	signal ready_sig			: std_logic;
	signal proc_enable_sig		: std_logic;

	-- ReLUブロック 
	signal finalize_reg			: std_logic;
	signal relu_ena_reg			: std_logic;
	signal relu_decpos_reg		: std_logic_vector(1 downto 0);
	signal relu_valid_reg		: std_logic;
	signal relu_data_reg		: std_logic_vector(31 downto 0);
	signal relu_eol_reg			: std_logic;
	signal relu_eof_reg			: std_logic;
	signal relu_finally_reg		: std_logic;
	signal relu_result_sig		: std_logic_vector(7 downto 0);
	signal relu_pos19_sig		: std_logic_vector(11 downto 0);
	signal relu_pos15_sig		: std_logic_vector(15 downto 0);
	signal relu_pos11_sig		: std_logic_vector(19 downto 0);
	signal relu_pos7_sig		: std_logic_vector(23 downto 0);
	signal relu_pos19_sat_sig	: std_logic_vector(relu_result_sig'range);
	signal relu_pos15_sat_sig	: std_logic_vector(relu_result_sig'range);
	signal relu_pos11_sat_sig	: std_logic_vector(relu_result_sig'range);
	signal relu_pos7_sat_sig	: std_logic_vector(relu_result_sig'range);
	signal relu_pos_sig			: std_logic_vector(relu_result_sig'range);

	-- poolingブロック 
	signal poolproc_enable_sig	: std_logic;
	signal pooling_ena_reg		: std_logic;
	signal pooling_mode_reg		: std_logic_vector(1 downto 0);
	signal pool_delay_x_reg		: std_logic;
	signal pool_delay_y_reg		: std_logic;
	signal pool_eol_reg			: std_logic;
	signal pool_eof_reg			: std_logic_vector(2 downto 0);
	signal pool_x_valid_reg		: std_logic;
	signal pool_x0_reg			: std_logic_vector(relu_result_sig'range);
	signal pool_x1_reg			: std_logic_vector(relu_result_sig'range);
	signal pool_x_sel_sig		: std_logic_vector(relu_result_sig'range);
	signal pool_x_add_sig		: std_logic_vector(relu_result_sig'left+1 downto 0);
	signal pool_x_sig			: std_logic_vector(pool_x_add_sig'range);
	signal pool_y_valid_reg		: std_logic;
	signal pool_y0_reg			: std_logic_vector(pool_x_sig'range);
	signal pool_y1_reg			: std_logic_vector(pool_x_sig'range);
	signal pool_y0_comp_sig		: std_logic_vector(relu_result_sig'range);
	signal pool_y1_comp_sig		: std_logic_vector(relu_result_sig'range);
	signal pool_y_sel_sig		: std_logic_vector(relu_result_sig'range);
	signal pool_y_add_sig		: std_logic_vector(pool_x_sig'left+1 downto 0);
	signal pool_y_sig			: std_logic_vector(relu_result_sig'range);
	signal pool_delay_sig		: std_logic;
	signal pool_data_sig		: std_logic_vector(relu_result_sig'range);
	signal pool_valid_sig		: std_logic;
	signal pool_finally_sig		: std_logic;

	signal linefifo_flush_sig	: std_logic;
	signal linefifo_wrreq_sig	: std_logic;
	signal linefifo_data_sig	: std_logic_vector(8 downto 0);
	signal linefifo_rdack_sig	: std_logic;
	signal linefifo_q_sig		: std_logic_vector(8 downto 0);
	signal linefifo_empty_sig	: std_logic;

	-- 書き戻しFIFOブロック 
	signal wa_bytenum_reg		: std_logic_vector(1 downto 0);
	signal wa_data_reg			: std_logic_vector(7 downto 0);
	signal wa_valid_reg			: std_logic;
	signal wa_finally_reg		: std_logic_vector(2 downto 0);
	signal wa_worddata_reg		: std_logic_vector(31 downto 0);
	signal wa_byteenable_reg	: std_logic_vector(3 downto 0);
	signal wa_wordvalid_reg		: std_logic;

	type DEF_STATE_WBCTRL is (WBWRITE, WBFINALLY, WBWAIT1, WBDONE);
	signal state_wbctrl : DEF_STATE_WBCTRL;
	signal wb_wordsel_reg		: std_logic_vector(WB_SCFIFO_NUM-1 downto 0);
	signal writeback_enable_sig	: std_logic;
	signal finalize_req_sig		: std_logic;
	signal worddata_sig			: std_logic_vector(32+4-1 downto 0);
	signal wordvalid_sig		: std_logic;
	signal wordwrite_req_sig	: std_logic;
	signal wordwrite_last_sig	: std_logic;

	signal wbfifo_flush_sig		: std_logic;
	signal wbfifo_wrreq_sig		: std_logic_vector(WB_SCFIFO_NUM-1 downto 0);
	signal wbfifo_data_sig		: std_logic_vector(35 downto 0);
	signal wbfifo_full_sig		: std_logic_vector(WB_SCFIFO_NUM-1 downto 0);
	signal wbfifo_rdack_sig		: std_logic;
	signal wbfifo_q_sig			: std_logic_vector(WB_SCFIFO_NUM*36-1 downto 0);
	signal wbfifo_rdusedw_sig	: std_logic_vector(WB_SCFIFO_NUM*WB_SCFIFO_WIDTHU-1 downto 0);
	signal wbfifo_empty_sig		: std_logic_vector(WB_SCFIFO_NUM-1 downto 0);
	signal wbfifo_usedw_sig		: std_logic_vector(WB_SCFIFO_WIDTHU downto 0);
	signal wbfifo_remain_sig	: std_logic;

	-- ラインデータ書き戻し制御ブロック 
	type DEF_STATE_MEMWRITE is (WRITEIDLE, WRITEREQ, WRITEDATA);
	signal state_memwrite : DEF_STATE_MEMWRITE;
	signal memwrite_init_sig	: std_logic;
	signal memwrite_ready_sig	: std_logic;
	signal memwrite_ready_reg	: std_logic;
	signal write_request_reg	: std_logic;
	signal wr_address_reg		: std_logic_vector(31 downto ALIGN_ADDR_WIDTH);
	signal wr_datanum_reg		: std_logic_vector(write_burstcount'range);
	signal wr_totalnum_reg		: std_logic_vector(MAXCONVSIZE_POW2_NUMBER*2-(DATABUS_POW2_NUMBER-5) downto 0);
	signal wr_fiforeq_sig		: std_logic;
	signal wr_dataack_sig		: std_logic;


begin

	-- テスト記述 

	test_start <= start_sig;

	test_relu_result <= relu_result_sig;
	test_relu_finally <= relu_finally_reg;
	test_pool_x <= pool_x_sig;
	test_x_valid <= pool_x_valid_reg;
	test_y_valid <= pool_y_valid_reg;

	test_linefifo_wrreq <= linefifo_wrreq_sig;
	test_linefifo_rdack <= linefifo_rdack_sig;
	test_linefifo_q <= linefifo_q_sig;
	test_linefifo_empty <= linefifo_empty_sig;

	test_pool_data <= pool_data_sig;
	test_pool_valid <= pool_valid_sig;
	test_pool_finally <= pool_finally_sig;
	test_finalize_req <= finalize_req_sig;
	test_wordwrite_last <= wordwrite_last_sig;

	test_wb_worddata <= slice(wbfifo_data_sig, 32, 0);
	test_wb_byteenable <= slice(wbfifo_data_sig, 4, 32);
	test_wbfifo_wrreq <= slice(wbfifo_wrreq_sig, 8, 0);
	test_wbfifo_empty <= slice(wbfifo_empty_sig, 8, 0);
	test_wbfifo_usedw <= slice(wbfifo_usedw_sig, 13, 0);
	test_wbfifo_remain <= wbfifo_remain_sig;
	test_wr_fiforeq <=  wr_fiforeq_sig;

	test_proc_enable <= proc_enable_sig;


	-- パラメータ範囲チェック 

	assert (DATABUS_POW2_NUMBER >= 5 and DATABUS_POW2_NUMBER <= 8)
		report "DATABUS_POW2_NUMBER is out of range.";

	assert (MAXCONVSIZE_POW2_NUMBER >= 8 and MAXCONVSIZE_POW2_NUMBER <= 11)
		report "MAXCONVSIZE_POW2_NUMBER is out of range.";

	assert (WBFIFODEPTH_POW2_NUMBER >= 7 and WBFIFODEPTH_POW2_NUMBER <= 12)
		report "WBFIFODEPTH_POW2_NUMBER is out of range.";

	assert (WBMAXBURST_POW2_NUMBER >= 3 and WBMAXBURST_POW2_NUMBER <= (WB_SCFIFO_WIDTHU-1))
		report "WBMAXBURST_POW2_NUMBER is out of range. Less then " & integer'image(WB_SCFIFO_WIDTHU-1);

	assert (write_burstcount'length <= 11)
		report "Avalon-MM burstcount port width is out of range. Less then 11.";



	----------------------------------------------------------------------
	-- モジュール全体制御 
	----------------------------------------------------------------------

	init_sig <= init;
	ready <= ready_sig;

	wb_totalnum <= slice(wr_totalnum_reg, wb_totalnum'length, 0);


	-- 開始信号と終了信号生成 

--	proc_enable_sig <= writeback_enable_sig;
	proc_enable_sig <= writeback_enable_sig when is_false(test_force_wbfull) else '0';

	ready_sig <= memwrite_ready_sig;
	start_sig <= start when is_true(ready_sig) else '0';



	----------------------------------------------------------------------
	-- ReLU処理 (ラインデータの整数部をUINT8に丸める)
	----------------------------------------------------------------------

	sti_ready <= proc_enable_sig when is_false(ready_sig) and is_false(finalize_reg) else '0';


	-- レジスタラッチと更新 

	process (clk) begin
		if rising_edge(clk) then
			-- 全体開始信号でReLU処理有効と小数位置モード確定 
			if is_true(start_sig) then
				relu_ena_reg <= relu_ena;
				relu_decpos_reg <= decimal_pos;
			end if;

			 -- ファイナライズ信号生成 
			if is_true(ready_sig) then
				finalize_reg <= '0';
			elsif is_true(proc_enable_sig) and is_true(sti_valid) and is_true(sti_endofframe) then
				finalize_reg <= '1';
			end if;

			-- データ有効ディレイ信号生成 
			if is_true(ready_sig) then
				relu_valid_reg <= '0';
				relu_eol_reg <= '0';
				relu_eof_reg <= '0';
				relu_finally_reg <= '0';

			elsif is_true(proc_enable_sig) then
				if is_true(finalize_reg) then	-- ファイナライズ中はvalidを無視 (ソース側はreadyで待機する) 
					relu_valid_reg <= '0';
					relu_eol_reg <= '0';
					relu_eof_reg <= '0';
				else
					relu_valid_reg <= sti_valid;
					relu_eol_reg <= sti_endofline;
					relu_eof_reg <= sti_endofframe;
				end if;

				relu_finally_reg <= relu_eof_reg;	-- 1クロック後のrelu_eof_reg信号 
			end if;

			-- 入力データラッチ 
			if is_true(proc_enable_sig) then
				relu_data_reg <= sti_data;
			end if;

		end if;
	end process;


	-- 小数位置での切り出しと飽和 

	relu_pos19_sig <= slice(relu_data_reg, 12, 19);
	relu_pos19_sat_sig <= slice(relu_pos19_sig, 8, 0) when(slice(relu_pos19_sig, 4, 8) = 0) else (others=>'1');

	relu_pos15_sig <= slice(relu_data_reg, 16, 15);
	relu_pos15_sat_sig <= slice(relu_pos15_sig, 8, 0) when(slice(relu_pos15_sig, 8, 8) = 0) else (others=>'1');

	relu_pos11_sig <= slice(relu_data_reg, 20, 11);
	relu_pos11_sat_sig <= slice(relu_pos11_sig, 8, 0) when(slice(relu_pos11_sig, 12, 8) = 0) else (others=>'1');

	relu_pos7_sig <= slice(relu_data_reg, 24,  7);
	relu_pos7_sat_sig <= slice(relu_pos7_sig, 8, 0) when(slice(relu_pos7_sig, 16, 8) = 0) else (others=>'1');

	with relu_decpos_reg select relu_pos_sig <=
		relu_pos7_sat_sig	when PARAM_DECPOS_7,
		relu_pos11_sat_sig	when PARAM_DECPOS_11,
		relu_pos15_sat_sig	when PARAM_DECPOS_15,
		relu_pos19_sat_sig	when others;

	relu_result_sig <= relu_pos_sig when(relu_data_reg(31) = '0') else (others=>'0');	-- 負数を0に縮退 



	----------------------------------------------------------------------
	-- pooling処理 (データを1/4に間引く)
	----------------------------------------------------------------------
	-- relu_result_sig : ReLUでUINT8に丸められたデータ 
	-- relu_valid_reg : 有効画素を示す 
	-- relu_eol_reg : ライン最終データを示す 
	-- relu_eof_reg : フレーム最終データを示す 

	poolproc_enable_sig <= proc_enable_sig when is_true(relu_valid_reg) or is_true(finalize_reg) else '0';	-- validが有効な時に進める 


	process (clk) begin
		if rising_edge(clk) then
			-- 全体開始信号でReLU処理有効と小数位置モード確定 
			if is_true(start_sig) then
				pooling_ena_reg <= pooling_ena;
				pooling_mode_reg <= pooling_mode;
			end if;

			-- データ有効ディレイ信号生成 
			if is_true(ready_sig) then
				pool_delay_x_reg <= '0';
				pool_delay_y_reg <= '0';
				pool_eol_reg <= '0';
				pool_eof_reg <= (others=>'0');
			elsif is_true(poolproc_enable_sig) then
				pool_delay_x_reg <= relu_valid_reg;
				pool_delay_y_reg <= pool_delay_x_reg and pool_x_valid_reg and pool_y_valid_reg;
				pool_eol_reg <= relu_eol_reg;
				pool_eof_reg <= shiftin(pool_eof_reg, relu_eof_reg);
			end if;

			-- 間引き信号生成 
			if is_true(ready_sig) then
				pool_x_valid_reg <= '0';
				pool_y_valid_reg <= '0';
			elsif is_true(poolproc_enable_sig) then
				if is_true(pool_eol_reg) then
					pool_x_valid_reg <= '0';
					pool_y_valid_reg <= not pool_y_valid_reg;
				elsif is_true(pool_delay_x_reg) then
					pool_x_valid_reg <= not pool_x_valid_reg;
				end if;
			end if;

			-- データラッチ 
			if is_true(poolproc_enable_sig) then
				pool_x0_reg <= relu_result_sig;
				pool_x1_reg <= pool_x0_reg;
				pool_y0_reg <= pool_x_sig;
				pool_y1_reg <= linefifo_q_sig;
			end if;
		end if;
	end process;


	-- MAX値,平均値,指定値の選択 

	pool_x_sel_sig <=
		pool_x0_reg when((is_true(pooling_mode_reg(1)) and (pool_x0_reg >= pool_x1_reg)) or is_true(pooling_mode_reg(0))) else	-- MAXかP11のとき 
		pool_x1_reg;

	pool_x_add_sig <= ('0' & pool_x0_reg) + ('0' & pool_x1_reg);

	pool_x_sig <= pool_x_add_sig when(pooling_mode_reg = PARAM_POOL_AVG) else ('0' & pool_x_sel_sig);

	pool_y0_comp_sig <= slice(pool_y0_reg, 8, 0);
	pool_y1_comp_sig <= slice(pool_y1_reg, 8, 0);
	pool_y_sel_sig <=
		pool_y0_comp_sig when((is_true(pooling_mode_reg(1)) and (pool_y0_comp_sig >= pool_y1_comp_sig)) or is_true(pooling_mode_reg(0))) else	-- MAXかP11のとき 
		pool_y1_comp_sig;

	pool_y_add_sig <= ('0' & pool_y0_reg) + ('0' & pool_y1_reg);

	pool_y_sig <= slice(pool_y_add_sig, 8, 2) when(pooling_mode_reg = PARAM_POOL_AVG) else pool_y_sel_sig;


	-- ラインFIFOインスタンス 

	linefifo_flush_sig <= ready_sig;

	linefifo_wrreq_sig <= poolproc_enable_sig when is_true(pool_x_valid_reg) and is_false(pool_y_valid_reg) and is_true(pool_delay_x_reg) else '0';
	linefifo_data_sig <= pool_x_sig;
	linefifo_rdack_sig <= poolproc_enable_sig when is_true(pool_x_valid_reg) and is_true(pool_y_valid_reg) and is_true(pool_delay_x_reg) else '0';

	u_delayline : scfifo
	generic map (
		intended_device_family => DEVICE_FAMILY,
		lpm_type => "scfifo",
		lpm_showahead => "ON",
		lpm_numwords => 2**(MAXCONVSIZE_POW2_NUMBER),
		lpm_widthu => MAXCONVSIZE_POW2_NUMBER,
		lpm_width => 9,
		add_ram_output_register => "OFF",
		overflow_checking => FIFO_FLOW_CHECKING,
		underflow_checking => FIFO_FLOW_CHECKING,
		use_eab => "ON"
	)
	port map (
		clock	=> clk,
		sclr	=> linefifo_flush_sig,

		wrreq	=> linefifo_wrreq_sig,
		data	=> linefifo_data_sig,

		rdreq	=> linefifo_rdack_sig,	-- ack
		q		=> linefifo_q_sig,
		empty	=> linefifo_empty_sig
	);


	pool_delay_sig <= pool_delay_y_reg when is_true(pooling_ena_reg) else pool_delay_x_reg;
	pool_valid_sig <= pool_delay_sig when is_true(poolproc_enable_sig) else '0';
	pool_data_sig <= pool_y_sig when is_true(pooling_ena_reg) else pool_x0_reg;
	pool_finally_sig <= pool_eof_reg(2) when is_true(pooling_ena_reg) else pool_eof_reg(1);



	----------------------------------------------------------------------
	-- 書き戻しFIFO (ラインデータまたはUINT8をバス幅に整列) 
	----------------------------------------------------------------------
	-- relu_data_reg : 入力データ 
	-- relu_valid_reg : relu_data_regが有効であることを示す 
	-- relu_finally_reg : フレームの終了をリクエスト (必ず最後のデータの後にアサートされる)
	-- pool_data_sig : pooling後のピクセルデータ 
	-- pool_valid_sig : pool_data_sigが有効であることを示す (proc_enable_sigでマスクされていることに注意)
	-- pool_finally_sig : フレームの終了をリクエスト (必ず最後のピクセルデータの後にアサートされる)

	writeback_enable_sig <= '1' when is_false(wbfifo_full_sig(0)) else '0';	-- wbfifoのfull信号でフロー制御をする 


	-- poolingデータをワードに整列 : 2clock latency

	process (clk) begin
		if rising_edge(clk) then
			-- データ有効ディレイ信号生成 
			if is_true(ready_sig) then
				wa_valid_reg <= '0';
				wa_finally_reg <= (others=>'0');
			elsif is_true(proc_enable_sig) then
				wa_valid_reg <= pool_valid_sig;
				wa_finally_reg <= shiftin(wa_finally_reg, pool_finally_sig);
			end if;

			-- データラッチ 
			if is_true(proc_enable_sig) then
				wa_data_reg <= pool_data_sig;
			end if;

			-- ワードアライン 
			if is_true(ready_sig) then
				wa_bytenum_reg <= (others=>'0');
				wa_wordvalid_reg <= '0';

			elsif is_true(proc_enable_sig) then
				if is_true(wa_valid_reg) then
					case wa_bytenum_reg is
					when "01" =>
						wa_worddata_reg(1*8+7 downto 1*8) <= wa_data_reg;
						wa_byteenable_reg(1) <= '1';
					when "10" =>
						wa_worddata_reg(2*8+7 downto 2*8) <= wa_data_reg;
						wa_byteenable_reg(2) <= '1';
					when "11" =>
						wa_worddata_reg(3*8+7 downto 3*8) <= wa_data_reg;
						wa_byteenable_reg(3) <= '1';
					when others =>
						wa_worddata_reg <= slice(wa_data_reg, 32, 0);
						wa_byteenable_reg <= "0001";
					end case;

					wa_bytenum_reg <= wa_bytenum_reg + 1;
				end if;

				if (is_true(wa_valid_reg) and wa_bytenum_reg = 3) or (is_true(wa_finally_reg(0)) and wa_bytenum_reg /= 0) then
					wa_wordvalid_reg <= '1';
				else
					wa_wordvalid_reg <= '0';
				end if;
			end if;

		end if;
	end process;


	-- 書き戻しFIFO制御 

	worddata_sig <= (wa_byteenable_reg & wa_worddata_reg) when is_true(relu_ena_reg) else ("1111" & relu_data_reg);
	wordvalid_sig <= wa_wordvalid_reg when is_true(relu_ena_reg) else relu_valid_reg;
	finalize_req_sig <= wa_finally_reg(2) when is_true(relu_ena_reg) else relu_finally_reg;

	wordwrite_req_sig <= '1' when(state_wbctrl = WBFINALLY) else wordvalid_sig;
	wordwrite_last_sig <= '1' when(state_wbctrl = WBDONE) else '0';

	process (clk) begin
		if rising_edge(clk) then
			if is_true(ready_sig) then
				state_wbctrl <= WBWRITE;
				wb_wordsel_reg <= (0=>'1', others=>'0');

			elsif is_true(proc_enable_sig) then
				case state_wbctrl is
				-- ワードデータが来たらFIFOへ書き込みリクエスト 
				when WBWRITE =>
					if is_true(finalize_req_sig) then
						if is_false(wb_wordsel_reg(0)) then
							state_wbctrl <= WBFINALLY;
						else
							state_wbctrl <= WBWAIT1;
						end if;
					end if;

					if is_true(wordvalid_sig) then
						wb_wordsel_reg <= shiftin(wb_wordsel_reg, shiftout(wb_wordsel_reg));
					end if;

				-- 最終ワード後のバス幅のダミーワード書き込み 
				when WBFINALLY =>
					if is_false(wb_wordsel_reg(WB_SCFIFO_NUM-1)) then
						wb_wordsel_reg <= shiftin(wb_wordsel_reg, shiftout(wb_wordsel_reg));
					else
						state_wbctrl <= WBWAIT1;
					end if;

				-- FIFOのFULL/EMPTY信号アップデート待ち (wordwrite_last_sigとwbfifo_remain_sigを同期させる) 
				when WBWAIT1 =>
					state_wbctrl <= WBDONE;

				when WBDONE =>
				end case;

			end if;
		end if;
	end process;


	-- 書き戻しFIFOインスタンス 

	wbfifo_flush_sig <= ready_sig;

	wbfifo_data_sig <= (others=>'0') when(state_wbctrl = WBFINALLY) else worddata_sig;
	wbfifo_rdack_sig <= wr_dataack_sig;
	wbfifo_remain_sig <= '1' when is_false(wbfifo_empty_sig(WB_SCFIFO_NUM-1)) else '0';
	wbfifo_usedw_sig <=
		wbfifo_full_sig(WB_SCFIFO_NUM-1) & 
		slice(wbfifo_rdusedw_sig, WB_SCFIFO_WIDTHU, (WB_SCFIFO_NUM-1)*WB_SCFIFO_WIDTHU);

	gen_wbfifo : for i in 0 to WB_SCFIFO_NUM-1 generate
		wbfifo_wrreq_sig(i) <= proc_enable_sig when is_true(wb_wordsel_reg(i)) and is_true(wordwrite_req_sig) else '0';

		-- ※メモリマクロ構成のFIFOとLE/ALU構成のFIFOが混ざるとemptyのタイミングに差ができるので注意すること 
		u : scfifo
		generic map (
			intended_device_family => DEVICE_FAMILY,
			lpm_type => "scfifo",
			lpm_showahead => "ON",
			lpm_numwords => 2**WB_SCFIFO_WIDTHU,
			lpm_widthu => WB_SCFIFO_WIDTHU,
			lpm_width => 36,
			add_ram_output_register => "OFF",
			overflow_checking => FIFO_FLOW_CHECKING,
			underflow_checking => FIFO_FLOW_CHECKING,
			use_eab => "ON"
		)
		port map (
			clock	=> clk,
			sclr	=> wbfifo_flush_sig,

			wrreq	=> wbfifo_wrreq_sig(i),
			data	=> wbfifo_data_sig,
			full	=> wbfifo_full_sig(i),

			rdreq	=> wbfifo_rdack_sig,	-- ack
			q		=> wbfifo_q_sig((i+1)*36-1 downto i*36),
			empty	=> wbfifo_empty_sig(i),
			usedw	=> wbfifo_rdusedw_sig((i+1)*WB_SCFIFO_WIDTHU-1 downto i*WB_SCFIFO_WIDTHU)
		);
	end generate;



	----------------------------------------------------------------------
	-- データ書き戻し制御 
	----------------------------------------------------------------------

	memwrite_init_sig <= init_sig;
	memwrite_ready_sig <= memwrite_ready_reg;


	-- メモリライトリクエスト 

	write_request <= write_request_reg;
	write_burstend <= write_dataack when(state_memwrite = WRITEDATA and wr_datanum_reg = 1) else '0';
	write_address <= wr_address_reg & repbit('0', ALIGN_ADDR_WIDTH);
	write_burstcount <= wr_datanum_reg;

	gen_wb : for i in 0 to WB_SCFIFO_NUM-1 generate
		write_data((i+1)*32-1 downto i*32) <= slice(wbfifo_q_sig, 32, i*36);
		write_byteenable((i+1)*4-1 downto i*4) <= slice(wbfifo_q_sig, 4, i*36+32);
	end generate;

	wr_dataack_sig <= write_dataack;


	-- バーストライト制御 
	-- ※wbfifo_usedw_sigのMSBは下位よりも1クロック遅れる。n-1→fullの時に1クロック分だけ0が指示されるので注意する 

	wr_fiforeq_sig <= '1' when(wbfifo_usedw_sig >= BURST_MAXLENGTH) else '0';	-- 規定数のデータがキューされている 

	process (clk, reset) begin
		if is_true(reset) then
			state_memwrite <= WRITEIDLE;
			memwrite_ready_reg <= '1';
			write_request_reg <= '0';

		elsif rising_edge(clk) then
			case state_memwrite is

			-- 開始信号を待つ 
			when WRITEIDLE =>
				if is_true(start_sig) then
					state_memwrite <= WRITEREQ;
					memwrite_ready_reg <= '0';

					-- 書き戻し先頭アドレスの確定 
					wr_address_reg <= wb_address_top(wr_address_reg'range);

					-- トータルデータ書き込み数カウンタ 
					wr_totalnum_reg <= (others=>'0');
				end if;

			-- データの書き戻し要求 
			when WRITEREQ =>
				-- 初期化リクエストが来ていたら中断する 
				if is_true(memwrite_init_sig) then
					state_memwrite <= WRITEIDLE;
					memwrite_ready_reg <= '1';

				-- 書き戻しFIFOにバースト数のデータが積まれていれば書き込みをリクエスト 
				elsif is_true(wr_fiforeq_sig) then
					state_memwrite <= WRITEDATA;
					write_request_reg <= '1';
					wr_datanum_reg <= to_vector(BURST_MAXLENGTH, wr_datanum_reg'length);

				-- 最終データの処理 
				elsif is_true(wordwrite_last_sig) then
					if is_true(wbfifo_remain_sig) then	-- FIFOにデータが残っていれば書き込みをリクエストする 
						state_memwrite <= WRITEDATA;
						write_request_reg <= '1';
						wr_datanum_reg <= wbfifo_usedw_sig(wr_datanum_reg'range);
					else
						state_memwrite <= WRITEIDLE;
						memwrite_ready_reg <= '1';
					end if;
				end if;

			when WRITEDATA =>
				-- データがリクエストされたらFIFOから読み出す 
				if is_true(write_dataack) then
					if (wr_datanum_reg = 1) then
						state_memwrite <= WRITEREQ;
					end if;

					write_request_reg <= '0';
					wr_address_reg <= wr_address_reg + 1;
					wr_datanum_reg <= wr_datanum_reg - 1;
					wr_totalnum_reg <= wr_totalnum_reg + 1;
				end if;

			end case;
		end if;
	end process;



end RTL;
