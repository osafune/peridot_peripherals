-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - writeback
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/08/11 -> 2020/09/04
--            : 2020/09/19 (FIXED)
--
--     UPDATE : 2023/11/30 -> 2024/01/17
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
-- [X] 活性化関数部分を分離 
-- [X] プーリング部分を分離 
-- [X] 活性化関数LUT書き込みポート追加 
--
-- ・検証todo
-- [X] ラインデータvalidが分断されても正しく動くか(eol,eof等の境界部分を確認する) 
-- [X] avmm動作の確認 
-- [X] init信号アボートの動作(正しく復帰するか？タイミングを勘違いしている部分はないか？)
-- [X] 32bit以上でのファイナライズ処理 → 32/64/128/256で確認 
-- [X] 境界条件1:前段ファイナライズ後にavmmにぴったりバースト長のデータが残ってる 
-- [X] 境界条件2:前段ファイナライズ後にavmmにもうデータが残ってない(pooling時に発生)
-- [X] 境界条件3:32bit幅以上でダミーワード書き込み後にバースト長以下のデータが残っている(emptyディレイ)
--
-- ・リソース概算
--  500LE + 2M9k (ACTFUNC=0,32bit幅,256x256,WBFIFO 128ワード,8ワードバースト,FIFOフローチェックOFF時)
--  560LE + 4M9k (ACTFUNC=1,32bit幅,512x512,WBFIFO 512ワード,64ワードバースト時)
-- 1060LE + 21M9k (ACTFUNC=2,256bit幅,2048x2048,WBFIFO 4096ワード時,256ワードバースト時)
--
--
-- * start後に書き戻すデータが存在しない場合はデータ待ちのままホールドするため 
--   書き戻しが不要な場合（内蔵バッファにキューイング等）はstartを立てないこと。 


-- activation_ena : Activation function enable(=1) / 32bit-word data writeback(=0)
-- decimal_pos  : 19bit decimal places(=00)
--              : 14bit decimal places(=01)
--              :  9bit decimal places(=10)
-- actfunc_type : ReLU(=000) / Hard-tanh(=001) / Step(=010) / Leaky-ReLU(=011)
--              : sigmoid(=100) / tanh(=101) / LUT1(=110) / LUT2(=111)  *option
-- pooling_mode : none(=00)
--              : simple pooling(=01) *(0,0)を返す(Conv2D stride=2と等価)
--              : max pooling(=10) *(0,0)～(1,1)の最大値を返す 
--              : avg pooling(=11) *(0,0)～(1,1)の平均値を返す 
-- wb_address_top : Start address of write back destination (Must be 32byte alignment) 
-- wb_totalnum : Word length of written data (Total number of data between start -> done)

-- aflut_wrclk : Activation function LUT write port clock (csr_clk)
-- aflut_wrad  : LUT wraddress(19..8) and wrdata(7..0)
-- aflut_wrena : LUT write enable(=1)


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

entity peridot_cnn_writeback is
	generic(
		ACTFUNC_INSTANCE_TYPE	: integer := 1;		-- 活性化関数実装タイプ (0:ReLU,Hard-tanh,Step,Leaky-ReLU / 1:0+sigmoid / 2:0+1+tanh / 3:0+1+2+LUT)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		MAXCONVSIZE_POW2_NUMBER	: integer := 9;		-- 畳み込み画像の最大値 (8:256x256 / 9:512x512 / 10:1024x1024 / 11:2048x2048 / 12:4096x4096)
		WBFIFODEPTH_POW2_NUMBER	: integer := 8;		-- 書き戻しFIFOの深さ (7:128ワード ～ 12:4096ワード *入力ワード単位)
		WBMAXBURST_POW2_NUMBER	: integer := 4;		-- 書き戻しバースト長 (3:8ワード ～ WB_SCFIFO_WIDTHU-1 *バースト上限はFIFO読み出し側の半分まで)
		FIFO_FLOW_CHECKING		: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 
		FIFO_SPEED_OPTION		: string := "ON";	-- FIFOのインスタンスオプション(ON=speed / OFF=area)
		AFLUT_SET_INITIALVALUE	: string := "ON";	-- LUTの初期値を設定オプション (メモリマクロの初期値を持てないデバイスではOFFにする)

		-- SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
		test_force_wbfull	: in  std_logic := '0';

		test_start			: out std_logic;
		test_proc_enable	: out std_logic;
		test_af_valid		: out std_logic;
		test_af_data		: out std_logic_vector(7 downto 0);
		test_pool_valid		: out std_logic;
		test_pool_data		: out std_logic_vector(7 downto 0);
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


		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: in  std_logic := '0';
		start			: in  std_logic;
		ready			: out std_logic;
		activation_ena	: in  std_logic;
		actfunc_type	: in  std_logic_vector(2 downto 0);
		decimal_pos		: in  std_logic_vector(1 downto 0);
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
		write_dataack	: in  std_logic;

		aflut_wrclk		: in  std_logic;						-- Avtivate function LUT write-port clock
		aflut_wrad		: in  std_logic_vector(19 downto 0);
		aflut_wrena		: in  std_logic := '0'
	);
end peridot_cnn_writeback;

architecture RTL of peridot_cnn_writeback is
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
	constant WB_SCFIFO_WIDTHU	: integer := WBFIFODEPTH_POW2_NUMBER-(DATABUS_POW2_NUMBER-5);	-- 書き戻しFIFOの深さ 
	constant WB_SCFIFO_NUM		: integer := 2**(DATABUS_POW2_NUMBER-5);	-- 書き戻しFIFOのインスタンス数 
	constant ALIGN_ADDR_WIDTH	: integer := DATABUS_POW2_NUMBER-3;			-- ワード境界のアドレスビット幅 
	constant BURST_MAXLENGTH	: integer := 2**WBMAXBURST_POW2_NUMBER;		-- 最大バースト長 


	-- 全体制御 
	signal init_sig				: std_logic;
	signal start_sig			: std_logic;
	signal ready_sig			: std_logic;
	signal proc_enable_sig		: std_logic;
	signal finalize_reg			: std_logic;
	signal activation_ena_reg	: std_logic;
	signal actfunc_type_reg		: std_logic_vector(2 downto 0);
	signal decimal_pos_reg		: std_logic_vector(1 downto 0);
	signal pooling_sign_reg		: std_logic;
	signal pooling_mode_reg		: std_logic_vector(1 downto 0);

	-- データ入力ブロック 
	signal sti_valid_reg		: std_logic;
	signal sti_data_reg			: std_logic_vector(31 downto 0);
	signal sti_eol_reg			: std_logic;
	signal sti_eof_reg			: std_logic;
	signal sti_finally_reg		: std_logic;
	signal submodule_init_sig	: std_logic;
	signal activate_valid_sig	: std_logic;
	signal activate_data_sig	: std_logic_vector(7 downto 0);
	signal activate_eol_sig		: std_logic;
	signal activate_eof_sig		: std_logic;
	signal pool_data_sig		: std_logic_vector(7 downto 0);
	signal pool_valid_sig		: std_logic;
	signal pool_finally_sig		: std_logic;

	-- データアライメントFIFOブロック 
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

	signal wbfifo_wrreq_sig		: std_logic_vector(WB_SCFIFO_NUM-1 downto 0);
	signal wbfifo_data_sig		: std_logic_vector(35 downto 0);
	signal wbfifo_full_sig		: std_logic_vector(WB_SCFIFO_NUM-1 downto 0);
	signal wbfifo_rdack_sig		: std_logic;
	signal wbfifo_q_sig			: std_logic_vector(WB_SCFIFO_NUM*36-1 downto 0);
	signal wbfifo_rdusedw_sig	: std_logic_vector(WB_SCFIFO_NUM*WB_SCFIFO_WIDTHU-1 downto 0);
	signal wbfifo_empty_sig		: std_logic_vector(WB_SCFIFO_NUM-1 downto 0);
	signal wbfifo_usedw_sig		: std_logic_vector(WB_SCFIFO_WIDTHU downto 0);
	signal wbfifo_remain_sig	: std_logic;

	-- 書き戻し制御ブロック 
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


	-- コンポーネント宣言 
	component peridot_cnn_writeback_actfunc
	generic(
		ACTFUNC_INSTANCE_TYPE	: integer;
		AFLUT_SET_INITIALVALUE	: string
	);
	port(
		clk				: in  std_logic;
		actfunc_type	: in  std_logic_vector(2 downto 0);		-- Avtivate function type
		decimal_pos		: in  std_logic_vector(1 downto 0);		-- Decimal position

		init			: in  std_logic;
		enable			: in  std_logic;
		sti_valid		: in  std_logic;
		sti_data		: in  std_logic_vector(31 downto 0);
		sti_eol			: in  std_logic;
		sti_eof			: in  std_logic;

		activate_valid	: out std_logic;
		activate_data	: out std_logic_vector(7 downto 0);
		activate_eol	: out std_logic;
		activate_eof	: out std_logic;

		aflut_wrclk		: in  std_logic;						-- Avtivate function LUT write-port clock
		aflut_wrad		: in  std_logic_vector(19 downto 0);	-- LUT address/data
		aflut_wrena		: in  std_logic							-- LUT write enable
	);
	end component;

	component peridot_cnn_writeback_pooling
	generic(
		MAXCONVSIZE_POW2_NUMBER	: integer;
		FIFO_FLOW_CHECKING		: string;
		FIFO_SPEED_OPTION		: string
	);
	port(
		clk				: in  std_logic;
		pooling_mode	: in  std_logic_vector(1 downto 0);	-- pooling mode
		sign_ena		: in  std_logic;			-- Line data sign extension : '1'=signed 8bit / '0'=unsigned 8bit

		init			: in  std_logic;			-- Frame initiatize
		enable			: in  std_logic;			-- Data processing enable (backpressure control)
		activate_valid	: in  std_logic;
		activate_data	: in  std_logic_vector(7 downto 0);
		activate_eol	: in  std_logic;			-- * When activate_valid is negated, set it to 0.
		activate_eof	: in  std_logic;			-- * When activate_valid is negated, set it to 0.

		pooling_valid	: out std_logic;
		pooling_data	: out std_logic_vector(7 downto 0);
		pooling_finally	: out std_logic
	);
	end component;

begin

	-- テスト記述 

	test_start <= start_sig;
	test_proc_enable <= proc_enable_sig;

	test_af_valid <= activate_valid_sig;
	test_af_data <= activate_data_sig;
	test_pool_valid <= pool_valid_sig;
	test_pool_data <= pool_data_sig;
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


	-- パラメータ範囲チェック 

	assert (ACTFUNC_INSTANCE_TYPE >= 0 and ACTFUNC_INSTANCE_TYPE <= 3)
		report "ACTFUNC_INSTANCE_TYPE is out of range.";

	assert (DATABUS_POW2_NUMBER >= 5 and DATABUS_POW2_NUMBER <= 8)
		report "DATABUS_POW2_NUMBER is out of range.";

	assert (MAXCONVSIZE_POW2_NUMBER >= 8 and MAXCONVSIZE_POW2_NUMBER <= 12)
		report "MAXCONVSIZE_POW2_NUMBER is out of range.";

	assert (WBFIFODEPTH_POW2_NUMBER >= 7 and WBFIFODEPTH_POW2_NUMBER <= 12)
		report "WBFIFODEPTH_POW2_NUMBER is out of range.";

	assert (WBMAXBURST_POW2_NUMBER >= 3 and WBMAXBURST_POW2_NUMBER <= (WB_SCFIFO_WIDTHU-1))
		report "WBMAXBURST_POW2_NUMBER is out of range. Equal or less than " & integer'image(WB_SCFIFO_WIDTHU-1);

	assert (write_burstcount'length <= 11)
		report "Avalon-MM burstcount port width is out of range. Equal or less than 11.";



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
	-- データ入力ブロック(書き戻し/活性化関数/プーリング)
	----------------------------------------------------------------------

	sti_ready <= proc_enable_sig when is_false(ready_sig) and is_false(finalize_reg) else '0';


	-- レジスタラッチ 

	process (clk) begin
		if rising_edge(clk) then
			-- 全体開始信号で動作モード確定 
			if is_true(start_sig) then
				activation_ena_reg <= activation_ena;
				actfunc_type_reg <= actfunc_type;
				decimal_pos_reg <= decimal_pos;
				pooling_mode_reg <= pooling_mode;
				pooling_sign_reg <= actfunc_type(0);	-- 001,011,101,111は符号付きデータ 
			end if;

			 -- ファイナライズ信号生成 
			if is_true(ready_sig) then
				finalize_reg <= '0';
			elsif is_true(proc_enable_sig) and is_true(sti_valid) and is_true(sti_endofframe) then
				finalize_reg <= '1';
			end if;

			-- データ有効ディレイ信号生成 
			if is_true(ready_sig) then
				sti_valid_reg <= '0';
				sti_eol_reg <= '0';
				sti_eof_reg <= '0';
				sti_finally_reg <= '0';

			elsif is_true(proc_enable_sig) then
				if is_true(finalize_reg) then	-- ファイナライズ中はvalidを無視 (ソース側はreadyで待機する) 
					sti_valid_reg <= '0';
					sti_eol_reg <= '0';
					sti_eof_reg <= '0';
				else
					sti_valid_reg <= sti_valid;
					sti_eol_reg <= sti_endofline and sti_valid;
					sti_eof_reg <= sti_endofframe and sti_valid;
				end if;

				sti_finally_reg <= sti_eof_reg;	-- 1クロック後のsti_eof_reg信号 
			end if;

			-- 入力データラッチ 
			if is_true(proc_enable_sig) then
				sti_data_reg <= sti_data;
			end if;

		end if;
	end process;

	submodule_init_sig <= ready_sig when is_true(activation_ena_reg) else '1';


	-- 活性化関数モジュールインスタンス 

	u_actfunc : peridot_cnn_writeback_actfunc
	generic map (
		ACTFUNC_INSTANCE_TYPE	=> ACTFUNC_INSTANCE_TYPE,
		AFLUT_SET_INITIALVALUE	=> AFLUT_SET_INITIALVALUE
	)
	port map (
		clk				=> clk,
		actfunc_type	=> actfunc_type_reg,
		decimal_pos		=> decimal_pos_reg,

		init			=> submodule_init_sig,
		enable			=> proc_enable_sig,
		sti_valid		=> sti_valid_reg,
		sti_data		=> sti_data_reg,
		sti_eol			=> sti_eol_reg,
		sti_eof			=> sti_eof_reg,

		activate_valid	=> activate_valid_sig,
		activate_data	=> activate_data_sig,
		activate_eol	=> activate_eol_sig,
		activate_eof	=> activate_eof_sig,

		aflut_wrclk		=> aflut_wrclk,
		aflut_wrad		=> aflut_wrad,
		aflut_wrena		=> aflut_wrena
	);


	-- プーリングモジュールインスタンス 

	u_pooling : peridot_cnn_writeback_pooling
	generic map (
		MAXCONVSIZE_POW2_NUMBER	=> MAXCONVSIZE_POW2_NUMBER,
		FIFO_FLOW_CHECKING		=> FIFO_FLOW_CHECKING,
		FIFO_SPEED_OPTION		=> FIFO_SPEED_OPTION
	)
	port map (
		clk				=> clk,
		pooling_mode	=> pooling_mode_reg,
		sign_ena		=> pooling_sign_reg,

		init			=> submodule_init_sig,
		enable			=> proc_enable_sig,
		activate_valid	=> activate_valid_sig,
		activate_data	=> activate_data_sig,
		activate_eol	=> activate_eol_sig,
		activate_eof	=> activate_eof_sig,

		pooling_valid	=> pool_valid_sig,
		pooling_data	=> pool_data_sig,
		pooling_finally	=> pool_finally_sig
	);



	----------------------------------------------------------------------
	-- データアライメントFIFO (32bitデータ/8bitデータをバス幅に整列) 
	----------------------------------------------------------------------
	-- sti_valid_reg   : sti_data_regが有効であることを示す 
	-- sti_data_reg    : 入力データ 
	-- sti_finally_reg : フレームの終了をリクエスト (必ず最後のデータの後にアサートされる)
	-- pool_valid_sig  : pool_data_sigが有効であることを示す 
	-- pool_data_sig   : pooling後のピクセルデータ 
	-- pool_finally_sig: フレームの終了をリクエスト (必ず最後のピクセルデータの後にアサートされる)

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
					when "11" =>
						wa_worddata_reg(3*8+7 downto 3*8+0) <= wa_data_reg;
						wa_byteenable_reg(3) <= '1';
					when "10" =>
						wa_worddata_reg(2*8+7 downto 2*8+0) <= wa_data_reg;
						wa_byteenable_reg(2) <= '1';
					when "01" =>
						wa_worddata_reg(1*8+7 downto 1*8+0) <= wa_data_reg;
						wa_byteenable_reg(1) <= '1';
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


	-- データアライメントFIFO制御 

	worddata_sig <= (wa_byteenable_reg & wa_worddata_reg) when is_true(activation_ena_reg) else ("1111" & sti_data_reg);
	wordvalid_sig <= wa_wordvalid_reg when is_true(activation_ena_reg) else sti_valid_reg;
	finalize_req_sig <= wa_finally_reg(2) when is_true(activation_ena_reg) else sti_finally_reg;

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


	-- データアライメントFIFOインスタンス 
	-- (9bit幅単位のfifoはwriteポート/readポートのデータ幅が違うものはマクロ割り当てが悪いので自作で用意)

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
			lpm_type			=> "scfifo",
			lpm_showahead		=> "ON",
			lpm_numwords		=> 2**WB_SCFIFO_WIDTHU,
			lpm_widthu			=> WB_SCFIFO_WIDTHU,
			lpm_width			=> 36,
			add_ram_output_register => FIFO_SPEED_OPTION,
			overflow_checking	=> FIFO_FLOW_CHECKING,
			underflow_checking	=> FIFO_FLOW_CHECKING
		)
		port map (
			clock	=> clk,
			sclr	=> ready_sig,

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

		-- ※wbfifo_usedw_sigのMSBは下位よりも1クロック遅れる。n-1→fullの時に1クロック分だけ0が指示されるので注意 
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
