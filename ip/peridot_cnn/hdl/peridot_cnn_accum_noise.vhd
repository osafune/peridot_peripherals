-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - noise generator
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2023/12/08 -> 2023/12/09
--            : 2023/12/09 (FIXED)
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

-- フィルターバイアス値(Bf)に乱数項(εN)を加える。乱数種別は noise_type で指定。 
-- 加算量は noise_gain で調整できる。 
--
--   f(x) = Bf + εN  (εN = rand * gain)
--
--   noise_type = 00 : 一様乱数 
--              = 01 : cos^19 (3点折れ線で近似)
--
--   noise_gain : 符号付き15bit固定小数で指定。65536 = 1.0 で、このとき8bit整数+8bit小数の 
--                値が小数位置19bit部分に加算される(19bit decimalで最大値255.99609375になる)


-- VHDL 1993 / IEEE 1076-1993
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_misc.all;

library lpm;
use lpm.lpm_components.all;

entity peridot_cnn_accum_noise is
	generic(
		RANDGEN_INSTANCE_TYPE	: integer := 1		-- 乱数生成器実装タイプ (0:なし / 1:一様乱数,近似cos^19)
	);
	port(
		test_urand	: out std_logic_vector(15 downto 0);
		test_cos19	: out std_logic_vector(15 downto 0);


		reset		: in  std_logic;
		clk			: in  std_logic;

		bias_data	: in  std_logic_vector(31 downto 0);
		noise_type	: in  std_logic_vector(1 downto 0);
		noise_gain	: in  std_logic_vector(17 downto 0);

		result		: out std_logic_vector(32 downto 0)
	);
end peridot_cnn_accum_noise;

architecture RTL of peridot_cnn_accum_noise is
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

	-- Seed定数 
	constant XORSHIFT32_SEED	: std_logic_vector(31 downto 0) := X"92D68CA2";	-- 2463534242UL


	-- signal
	signal x_reg		: std_logic_vector(31 downto 0);
	signal a_sig		: std_logic_vector(31 downto 0);
	signal b_sig		: std_logic_vector(31 downto 0);
	signal c_sig		: std_logic_vector(31 downto 0);
	signal urand_sig	: std_logic_vector(15 downto 0);
	signal cos19_sig	: std_logic_vector(15 downto 0);

	signal noise_sig	: std_logic_vector(17 downto 0);
	signal mulans_sig	: std_logic_vector(35 downto 0);
	signal adder_sig	: std_logic_vector(32 downto 0);
	signal result_reg	: std_logic_vector(32 downto 0);

begin

	test_urand <= urand_sig;
	test_cos19 <= cos19_sig;


	-- パイプラインレジスタ 

	process (clk, reset) begin
		if is_true(reset) then
			x_reg <= XORSHIFT32_SEED;
		elsif rising_edge(clk) then
			x_reg <= c_sig;
			result_reg <= adder_sig;
		end if;
	end process;


	-- xorshift32

	a_sig <= x_reg xor (x_reg(18 downto 0) & "0000000000000");
	b_sig <= a_sig xor ("00000000000000000" & a_sig(31 downto 17));
	c_sig <= b_sig xor (b_sig(16 downto 0) & "000000000000000");

	-- 一様乱数 

	urand_sig <= x_reg(31 downto 16) xor x_reg(15 downto 0);

	-- 近似cos^19 (ハイライト状ノイズ)

	cos19_sig <= (others=>'0') when(x_reg(17) = '0') else
			"000" & x_reg(15 downto 3) when(x_reg(17 downto 16) = "10") else
			"111" & x_reg(13 downto 1) when(x_reg(17 downto 14) = "1111") else
			x_reg(15 downto 0) + to_vector(8192, 16);

	-- ノイズ選択 

	with noise_type select noise_sig <=
		("00" & urand_sig)	when "00",
		("00" & cos19_sig)	when "01",
		(others=>'X')		when others;

	-- ノイズゲイン乗算 

	u_eg : lpm_mult
	generic map(
		lpm_type			=> "LPM_MULT",
		lpm_representation	=> "SIGNED",
		lpm_pipeline		=> 2,
		lpm_widtha			=> 18,
		lpm_widthb			=> 18,
		lpm_widthp			=> 36
	)
	port map(
		clock	=> clk,
		clken	=> '1',
		dataa	=> noise_sig,
		datab	=> noise_gain,
		result	=> mulans_sig
	);

	adder_sig <= slice_sxt(bias_data, 33, 0) + slice_sxt(mulans_sig, 33, 5);

	-- 結果出力 

	result <= result_reg;



end RTL;
