-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - writeback pooling
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2023/11/30 -> 2023/12/06
--            : 2024/01/17 (FIXED)
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

-- 活性化関数から出力されるフレームデータを2x2の区域で分割し、pooling_modeの指示に
-- 従って以下のように1/4に間引く 
-- 
--   pooling_mode = 00 :  p00 p01  ->  p00 p01
--                        p10 p11      p10 p11
--
--   pooling_mode = 01 :  p00 p01  ->  p00  X
--                        p10 p11       X   X
--
--   pooling_mode = 10 :  p00 p01  ->  pmax X   pmax = max(p00, p01, p10, p11)
--                        p10 p11       X   X
--
--   pooling_mode = 11 :  p00 p01  ->  pavg X   pavg = (p00 + p01 + p10 + p11) / 4
--                        p10 p11       X   X
--

-- pooling_mode, sign_enaは内部で保持されないためinit=0の間は固定しておくこと
--
-- pooling_mode   : none(=00)
--                : simple pooling(=01) *(0,0)を返す(Conv2D stride=2と等価)
--                : max pooling(=10) *(0,0)～(1,1)の最大値を返す 
--                : avg pooling(=11) *(0,0)～(1,1)の平均値を返す 
-- sign_ena       : 入力データが符号付きであることを示す INT8(=1) / UINT8(=0)
--
-- init           : 初期化信号。データ投入前に1クロック以上アサートする 
-- enable         : 処理イネーブル信号 (backpuressure制御用)
--
-- activate_valid : activate_dataが有効であることを示す 
-- activate_data  : 活性化関数から出力されるデータ(UINT8 or INT8) 
-- activate_eol   : ラインの最後のデータを示す 
-- activate_eof   : フレームの最後のデータを示す。フレーム終了後はinitアサートまで入力しないこと 
--
-- pooling_valid  : pooling_dataが有効であることを示す (enableでマスクされることに注意)
-- pooling_data   : 処理後のデータ 
-- pooling_finally: フレーム終了を示す。必ず最終データ出力の後にアサートされる 


-- VHDL 1993 / IEEE 1076-1993
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_misc.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity peridot_cnn_writeback_pooling is
	generic(
		MAXCONVSIZE_POW2_NUMBER	: integer := 9;		-- 畳み込み画像の最大値 (8:256x256 / 9:512x512 / 10:1024x1024 / 11:2048x2048 / 12:4096x4096)
		FIFO_FLOW_CHECKING		: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 
		FIFO_SPEED_OPTION		: string := "ON"	-- FIFOのインスタンスオプション(ON=speed / OFF=area)
	);
	port(
		test_pool_x0		: out std_logic_vector(8 downto 0);
		test_pool_x1		: out std_logic_vector(8 downto 0);
		test_pool_x			: out std_logic_vector(9 downto 0);
		test_pool_y0		: out std_logic_vector(9 downto 0);
		test_pool_y1		: out std_logic_vector(9 downto 0);
		test_pool_y			: out std_logic_vector(8 downto 0);
		test_linefifo_wrreq	: out std_logic;
		test_linefifo_rdack	: out std_logic;
		test_linefifo_q		: out std_logic_vector(8 downto 0);
		test_linefifo_full	: out std_logic;
		test_linefifo_empty	: out std_logic;


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
end peridot_cnn_writeback_pooling;

architecture RTL of peridot_cnn_writeback_pooling is
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

	-- poolingの設定値 
	constant PARAM_POOL_NONE	: std_logic_vector(1 downto 0) := "00";	-- プーリングなし *デフォルト 
	constant PARAM_POOL_SYM		: std_logic_vector(1 downto 0) := "01";	-- p(0,0)を返す 
	constant PARAM_POOL_MAX		: std_logic_vector(1 downto 0) := "10";	-- 最大値を返す 
	constant PARAM_POOL_AVG		: std_logic_vector(1 downto 0) := "11";	-- 平均値を返す 

	-- signal
	signal enable_sig			: std_logic;
	signal finalize_reg			: std_logic;
	signal pool_delay_x_reg		: std_logic;
	signal pool_delay_y_reg		: std_logic;
	signal pool_eol_reg			: std_logic;
	signal pool_eof_reg			: std_logic_vector(2 downto 0);
	signal pool_x_valid_reg		: std_logic;
	signal pool_y_valid_reg		: std_logic;
	signal pool_x0_reg			: std_logic_vector(7 downto 0);
	signal pool_x1_reg			: std_logic_vector(pool_x0_reg'range);
	signal pool_y0_reg			: std_logic_vector(pool_x0_reg'left+1 downto 0);
	signal pool_y1_reg			: std_logic_vector(pool_y0_reg'range);

	signal pool_x0_comp_sig		: std_logic_vector(pool_x0_reg'left+1 downto 0);
	signal pool_x1_comp_sig		: std_logic_vector(pool_x0_comp_sig'range);
	signal pool_x_sub_sig		: std_logic_vector(pool_x0_comp_sig'range);
	signal pool_x_sel_sig		: std_logic_vector(pool_x0_comp_sig'range);
	signal pool_x_add_sig		: std_logic_vector(pool_x0_comp_sig'range);
	signal pool_x_sig			: std_logic_vector(pool_x0_comp_sig'range);
	signal pool_y_sub_sig		: std_logic_vector(pool_y0_reg'range);
	signal pool_y_sel_sig		: std_logic_vector(pool_y0_reg'range);
	signal pool_y_add_sig		: std_logic_vector(pool_y0_reg'left+1 downto 0);
	signal pool_y_sig			: std_logic_vector(pool_x0_reg'range);
	signal pool_delay_sig		: std_logic;
	signal linefifo_wrreq_sig	: std_logic;
	signal linefifo_rdack_sig	: std_logic;
	signal linefifo_q_sig		: std_logic_vector(pool_x_sig'range);
	signal linefifo_full_sig	: std_logic;
	signal linefifo_empty_sig	: std_logic;

begin

	test_pool_x0 <= pool_x0_comp_sig;
	test_pool_x1 <= pool_x1_comp_sig;
	test_pool_x <= (pool_x_sig(8) and sign_ena) & pool_x_sig;
	test_pool_y0 <= (pool_y0_reg(8) and sign_ena) & pool_y0_reg;
	test_pool_y1 <= (pool_y1_reg(8) and sign_ena) & pool_y1_reg;
	test_pool_y <= (pool_y_sig(7) and sign_ena) & pool_y_sig;
	test_linefifo_wrreq <= linefifo_wrreq_sig;
	test_linefifo_rdack <= linefifo_rdack_sig;
	test_linefifo_q <= linefifo_q_sig;
	test_linefifo_full <= linefifo_full_sig;
	test_linefifo_empty <= linefifo_empty_sig;


	-- プーリング処理 

	enable_sig <= enable when is_true(activate_valid) or is_true(finalize_reg) else '0';	-- validが有効な時に進める 

	process (clk) begin
		if rising_edge(clk) then
			 -- ファイナライズ信号生成 
			if is_true(init) then
				finalize_reg <= '0';
			elsif is_true(enable) and is_true(activate_valid) and is_true(activate_eof) then
				finalize_reg <= '1';
			end if;

			-- データ有効ディレイ信号生成 
			if is_true(init) then
				pool_delay_x_reg <= '0';
				pool_delay_y_reg <= '0';
				pool_eol_reg <= '0';
				pool_eof_reg <= (others=>'0');
			elsif is_true(enable_sig) then
				pool_delay_x_reg <= activate_valid;
				pool_delay_y_reg <= pool_delay_x_reg and pool_x_valid_reg and pool_y_valid_reg;	-- 有効データを1/4に間引き 
				pool_eol_reg <= activate_eol;							-- eol,eofのvalidマスクは上位コンポーネントで行われているのでここでは不要 
				pool_eof_reg <= shiftin(pool_eof_reg, activate_eof);	-- 
			end if;

			-- 間引き信号生成 
			if is_true(init) then
				pool_x_valid_reg <= '0';
				pool_y_valid_reg <= '0';
			elsif is_true(enable_sig) then
				if is_true(pool_eol_reg) then
					pool_x_valid_reg <= '0';
					pool_y_valid_reg <= not pool_y_valid_reg;
				elsif is_true(pool_delay_x_reg) then
					pool_x_valid_reg <= not pool_x_valid_reg;
				end if;
			end if;

			-- データラッチ 
			if is_true(enable_sig) then
				pool_x1_reg <= activate_data;
				pool_x0_reg <= pool_x1_reg;
				pool_y1_reg <= pool_x_sig;
				pool_y0_reg <= linefifo_q_sig;
			end if;
		end if;
	end process;


	-- MAX値,平均値,指定値の選択 
		-- x0, x1の整形 : u8/s8 -> s9
	pool_x0_comp_sig <= (pool_x0_reg(pool_x0_reg'left) and sign_ena) & pool_x0_reg;
	pool_x1_comp_sig <= (pool_x1_reg(pool_x1_reg'left) and sign_ena) & pool_x1_reg;

		-- x0, x1の比較と選択 : (s9 - s9) -> s9 (符号ビットのみ使う), max pooling/simple pooling
	pool_x_sub_sig <= pool_x0_comp_sig - pool_x1_comp_sig;
	pool_x_sel_sig <= pool_x1_comp_sig when(pooling_mode(1) = '1' and pool_x_sub_sig(pool_x_sub_sig'left) = '1') else pool_x0_comp_sig;

		-- x0, x1の加算と選択 : (s9 + s9) -> u9/s9 (符号無しモードの場合は符号ビットが落ちる), avg pooling
	pool_x_add_sig <= pool_x0_comp_sig + pool_x1_comp_sig;
	pool_x_sig <= pool_x_add_sig when(pooling_mode = PARAM_POOL_AVG) else pool_x_sel_sig;

		-- ラインFIFOに格納されるデータはMax/Simpleではx0またはx1のs9、Avgはx0+x1のu9/s9
		-- y0, y1の比較と選択 : (s9 - s9) -> s9 (符号ビットのみ使う), max pooling/simple pooling
	pool_y_sub_sig <= pool_y0_reg - pool_y1_reg;
	pool_y_sel_sig <= pool_y1_reg when(pooling_mode(1) = '1' and pool_y_sub_sig(pool_y_sub_sig'left) = '1') else pool_y0_reg;

		-- y0, y1の加算と選択 : (u9/s9 + u9/s9) -> u10/s10 (符号無しモードの場合は符号ビットが落ちる), avg pooling
	pool_y_add_sig <=
		('0' & pool_y0_reg) + ('0' & pool_y1_reg) when is_false(sign_ena) else
		(pool_y0_reg(pool_y0_reg'left) & pool_y0_reg) + (pool_y1_reg(pool_y1_reg'left) & pool_y1_reg);
	pool_y_sig <= pool_y_add_sig(pool_y_sig'left+2 downto 2) when(pooling_mode = PARAM_POOL_AVG) else pool_y_sel_sig(pool_y_sig'range); -- avgなら加算値を選択 


	-- ラインFIFOインスタンス (書き込みは奇数ピクセル時のみ) 

	linefifo_wrreq_sig <= enable_sig when is_true(pool_x_valid_reg) and is_false(pool_y_valid_reg) and is_true(pool_delay_x_reg) else '0';
	linefifo_rdack_sig <= enable_sig when is_true(pool_x_valid_reg) and is_true(pool_y_valid_reg) and is_true(pool_delay_x_reg) else '0';

	u : scfifo
	generic map (
		lpm_type			=> "scfifo",
		lpm_showahead		=> "ON",
		lpm_numwords		=> 2**(MAXCONVSIZE_POW2_NUMBER-1),
		lpm_widthu			=> MAXCONVSIZE_POW2_NUMBER-1,
		lpm_width			=> pool_x_sig'length,
		add_ram_output_register => FIFO_SPEED_OPTION,
		overflow_checking	=> FIFO_FLOW_CHECKING,
		underflow_checking	=> FIFO_FLOW_CHECKING
	)
	port map (
		clock	=> clk,
		sclr	=> init,

		wrreq	=> linefifo_wrreq_sig,
		data	=> pool_x_sig,
		full	=> linefifo_full_sig,

		rdreq	=> linefifo_rdack_sig,	-- ack
		q		=> linefifo_q_sig,
		empty	=> linefifo_empty_sig
	);


	pool_delay_sig <= pool_delay_x_reg when(pooling_mode = PARAM_POOL_NONE) else pool_delay_y_reg;

	pooling_valid <= pool_delay_sig when is_true(enable_sig) else '0';
	pooling_data <= pool_x1_reg when(pooling_mode = PARAM_POOL_NONE) else  pool_y_sig;
	pooling_finally <= pool_eof_reg(1) when(pooling_mode = PARAM_POOL_NONE) else pool_eof_reg(2);



end RTL;
