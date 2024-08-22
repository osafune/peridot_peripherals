-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - Inner product
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2023/11/30 -> 2023/12/13
--            : 2024/02/18 (FIXED)
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

-- 重み係数行列の列ベクトルW(j,i)と入力データベクトルV(i)を入力し、内積演算を行う。 
-- V(i)はsign_enaで符号無し8bit/符号付き8bitを選択できる。W(j,i)は符号付き16bit幅。 
--
--     res = Σ( V(i) * W(j,i) ) + Bm  i=0→n, j=このモジュール内では固定, Bm=バイアス値 
--
-- 積算レジスタは39bit幅で行い、出力時に32bit幅に符号付き飽和で出力される。 


-- 計算結果まではバス幅ごとに異なり、32bit幅で5クロック, 64/128bit幅で6クロック、
-- 256bit幅では7クロックの固定パイプラインとなる。 
-- sign_enaは即時更新（非パイプライン）となるため計算データが投入されている間は
-- 変化しないようにすること。 
-- biasはinitアサート時に初期値としてアキュムレーターに取り込まれる。 


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

entity peridot_cnn_fullyconn_product is
	generic(
		DATABUS_POW2_NUMBER		: integer := 5	-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
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
end peridot_cnn_fullyconn_product;

architecture RTL of peridot_cnn_fullyconn_product is
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

	-- データの並列数 
	constant PALLAREL_NUMBER	: integer := 2**(DATABUS_POW2_NUMBER-4);

	-- 積和器のパイプライン数 
		-- PALLAREL_NUMBER = 2   : 3-stage mult-adder
		-- PALLAREL_NUMBER = 4,8 : 4-stage mult-adder
		-- PALLAREL_NUMBER = 16  : 5-stage mult-adder
	function sel(F:boolean; A,B:integer) return integer is begin if F then return A; else return B; end if; end;
	constant MAC_PIPELINE		: integer := sel(PALLAREL_NUMBER = 2, 3, sel(PALLAREL_NUMBER <= 8, 4, 5));


	-- signal 
	signal valid_delay_reg		: std_logic_vector(MAC_PIPELINE-1 downto 0);

	signal vdata_sig			: std_logic_vector(PALLAREL_NUMBER*9-1 downto 0);
	signal multresult_sig		: std_logic_vector(PALLAREL_NUMBER*25-1 downto 0);
	signal adder_tmp0_reg		: std_logic_vector(23+1 downto 0);
	signal adder_tmp1_reg		: std_logic_vector(23+1 downto 0);
	signal adder_tmp2_reg		: std_logic_vector(23+2 downto 0);
	signal adder_tmp3_reg		: std_logic_vector(23+2 downto 0);
	signal adder_tmp4_reg		: std_logic_vector(23+2 downto 0);
	signal adder_tmp5_reg		: std_logic_vector(23+2 downto 0);
	signal adder_tmp6_reg		: std_logic_vector(23+3 downto 0);
	signal adder_tmp7_reg		: std_logic_vector(23+3 downto 0);
	signal adder_result_reg		: std_logic_vector(23+4 downto 0);

	signal sum_reg				: std_logic_vector(38 downto 0);
	signal sat_sum_reg			: std_logic;
	signal sum_adder_sig		: std_logic_vector(sum_reg'length downto 0);
	signal sum_adder_sign_sig	: std_logic_vector(sum_adder_sig'left downto sum_reg'left);
	signal sum_adder_sat_sig	: std_logic;
	signal sim_sig				: std_logic_vector(sum_reg'range);

	signal result_reg			: std_logic_vector(result'range);
	signal sat_res_reg			: std_logic;
	signal result_sign_sig		: std_logic_vector(sum_reg'left downto result_reg'left);
	signal result_sat_sig		: std_logic;
	signal result_sig			: std_logic_vector(result_reg'range);

begin

	-- パイプライン乗算器 (stage 1～2)

	gen_loop_i : for i in 0 to PALLAREL_NUMBER-1 generate
		-- 入力符号ビット拡張処理 (符号拡張) 
			-- vdata_sig : vdn .. vd3 vd2 vd1 vd0
		vdata_sig(i*9+8 downto i*9+0) <= (vector(i*8+7) and sign_ena) & vector(i*8+7 downto i*8+0);

		-- (s9 x s16) -> s25 *resultの上位2bitは必ず符号ビットになる 
		u : lpm_mult
		generic map(
			lpm_type			=> "LPM_MULT",
			lpm_representation	=> "SIGNED",
			lpm_pipeline		=> 2,
			lpm_widtha			=> 9,
			lpm_widthb			=> 16,
			lpm_widthp			=> 25
		)
		port map(
			clock	=> clk,
			clken	=> enable,
			dataa	=> vdata_sig(i*9+8 downto i*9+0),
			datab	=> weight(i*16+15 downto i*16+0),
			result	=> multresult_sig(i*25+24 downto i*25+0)
		);
	end generate;


	-- パイプライン加算器 (stage 3～5)

	process (clk) begin
		if rising_edge(clk) then
			if is_true(enable) then
				if (PALLAREL_NUMBER = 2) then
					-- stage3
					adder_result_reg <=
						slice_sxt(slice(multresult_sig, 24, 0*25), adder_result_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 1*25), adder_result_reg'length, 0);

				elsif (PALLAREL_NUMBER = 4) then
					-- stage3
					adder_tmp0_reg <=
						slice_sxt(slice(multresult_sig, 24, 0*25), adder_tmp0_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 1*25), adder_tmp0_reg'length, 0);

					adder_tmp1_reg <=
						slice_sxt(slice(multresult_sig, 24, 2*25), adder_tmp1_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 3*25), adder_tmp1_reg'length, 0);

					-- stage4
					adder_result_reg <=
						slice_sxt(adder_tmp0_reg, adder_result_reg'length, 0) +
						slice_sxt(adder_tmp1_reg, adder_result_reg'length, 0);

				elsif (PALLAREL_NUMBER = 8) then
					-- stage3
					adder_tmp0_reg <=
						slice_sxt(slice(multresult_sig, 24, 0*25), adder_tmp0_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 1*25), adder_tmp0_reg'length, 0);

					adder_tmp2_reg <=
						slice_sxt(slice(multresult_sig, 24, 2*25), adder_tmp2_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 3*25), adder_tmp2_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 4*25), adder_tmp2_reg'length, 0);

					adder_tmp3_reg <=
						slice_sxt(slice(multresult_sig, 24, 5*25), adder_tmp3_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 6*25), adder_tmp3_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 7*25), adder_tmp3_reg'length, 0);

					-- stage4
					adder_result_reg <=
						slice_sxt(adder_tmp0_reg, adder_result_reg'length, 0) +
						slice_sxt(adder_tmp2_reg, adder_result_reg'length, 0) +
						slice_sxt(adder_tmp3_reg, adder_result_reg'length, 0);

				else
					-- stage3
					adder_tmp0_reg <=
						slice_sxt(slice(multresult_sig, 24, 0*25), adder_tmp0_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 1*25), adder_tmp0_reg'length, 0);

					adder_tmp2_reg <=
						slice_sxt(slice(multresult_sig, 24, 2*25), adder_tmp2_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 3*25), adder_tmp2_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 4*25), adder_tmp2_reg'length, 0);

					adder_tmp3_reg <=
						slice_sxt(slice(multresult_sig, 24, 5*25), adder_tmp3_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 6*25), adder_tmp3_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 7*25), adder_tmp3_reg'length, 0);

					adder_tmp1_reg <=
						slice_sxt(slice(multresult_sig, 24, 8*25), adder_tmp1_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24, 9*25), adder_tmp1_reg'length, 0);

					adder_tmp4_reg <=
						slice_sxt(slice(multresult_sig, 24,10*25), adder_tmp4_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24,11*25), adder_tmp4_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24,12*25), adder_tmp4_reg'length, 0);

					adder_tmp5_reg <=
						slice_sxt(slice(multresult_sig, 24,13*25), adder_tmp5_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24,14*25), adder_tmp5_reg'length, 0) +
						slice_sxt(slice(multresult_sig, 24,15*25), adder_tmp5_reg'length, 0);

					-- stage4
					adder_tmp6_reg <=
						slice_sxt(adder_tmp0_reg, adder_tmp6_reg'length, 0) +
						slice_sxt(adder_tmp2_reg, adder_tmp6_reg'length, 0) +
						slice_sxt(adder_tmp3_reg, adder_tmp6_reg'length, 0);

					adder_tmp7_reg <=
						slice_sxt(adder_tmp1_reg, adder_tmp7_reg'length, 0) +
						slice_sxt(adder_tmp4_reg, adder_tmp7_reg'length, 0) +
						slice_sxt(adder_tmp5_reg, adder_tmp7_reg'length, 0);

					-- stage5
					adder_result_reg <=
						slice_sxt(adder_tmp6_reg, adder_result_reg'length, 0) +
						slice_sxt(adder_tmp7_reg, adder_result_reg'length, 0);

				end if;
			end if;
		end if;
	end process;


	-- 積算レジスタ (stage 4～6)

	sum_adder_sig <= slice_sxt(sum_reg, sum_adder_sig'length, 0) + slice_sxt(adder_result_reg, sum_adder_sig'length, 0);

	sum_adder_sign_sig <= sum_adder_sig(sum_adder_sign_sig'range);
	sum_adder_sat_sig <= '1' when(or_reduce(sum_adder_sign_sig) /= and_reduce(sum_adder_sign_sig)) else '0';	-- 符号ビットが同値ではない 

	sim_sig <=
		sum_adder_sig(sim_sig'range) when is_false(sum_adder_sat_sig) else
		(sim_sig'left=>sum_adder_sign_sig(sum_adder_sign_sig'left), others=>not sum_adder_sign_sig(sum_adder_sign_sig'left));	-- 正負の最大値に飽和 

	process (clk) begin
		if rising_edge(clk) then
			if is_true(init) then
				valid_delay_reg <= (others=>'0');
				sum_reg <= bias;
				sat_sum_reg <= '0';

			elsif is_true(enable) then
				valid_delay_reg <= shiftin(valid_delay_reg, valid);

				if is_true(shiftout(valid_delay_reg)) then
					sum_reg <= sim_sig;

					if is_true(sum_adder_sat_sig) then
						sat_sum_reg <= '1';		-- 積算レジスタが飽和した(initでクリアするまで保持) 
					end if;
				end if;

			end if;
		end if;
	end process;


	-- データ出力の飽和演算 (stage 5～7)

	result_sign_sig <= sum_reg(result_sign_sig'range);
	result_sat_sig <= '1' when(or_reduce(result_sign_sig) /= and_reduce(result_sign_sig)) else '0';	-- 符号ビットが同値ではない 

	result_sig <=
		sum_reg(result_sig'range) when is_false(result_sat_sig) else
		(result_sig'left=>result_sign_sig(result_sign_sig'left), others=>not result_sign_sig(result_sign_sig'left));	-- 正負の最大値に飽和 

	process (clk) begin
		if rising_edge(clk) then
			if is_true(init) then
				sat_res_reg <= '0';

			elsif is_true(enable) then
				result_reg <= result_sig;
				sat_res_reg <= result_sat_sig;	-- 出力レジスタの飽和はロードした時点のみ監視 

			end if;
		end if;
	end process;

	result <= result_reg;
	saturated <= sat_sum_reg or sat_res_reg;



end RTL;
