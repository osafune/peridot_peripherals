-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - kernel convolution
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2023/11/30 -> 2023/12/04
--            : 2023/12/28 (FIXED)
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

-- y0,y1,y2の3ライン分の同期したx方向連続のバイトデータpを入力し、入力パラメーターを
-- もとに次の3x3演算を行う。
-- pはsign_enaで符号無し8bit/符号付き8bitを選択できる。
-- * 9bitの符号付き係数で256倍を行うため、係数は正負反転した値を入力すること。
--
--     res = Sk * { Σ(Wk(i,j) * -p(y+i,x+j)) + Bk}  i,j=0→2
--
--
-- バイトパッキングモード（pack_ena='1'）の時は次の3x3演算とバイトアライメントを行う。 
-- パラメーターSkは無視される。 
-- 
-- ・符号なしデータの場合（sign_ena='0'） 
--
--     b = SAT_UINT8( Σ(Wk(i,j) * -p(y+i,x+j)) + Bk )  i,j=0→2
--     res = b << (byte_pos * 8)
--
-- ・符号付きデータの場合（sign_ena='0'） 
--
--     b = SAT_INT8( Σ(Wk(i,j) * -p(y+i,x+j)) + Bk )  i,j=0→2
--     res = b << (byte_pos * 8)
--
--
-- 計算結果までは8クロックの固定パイプライン。 
-- 入力データy0,y1,y2以外のパラメーターは即時更新（非パイプライン）となるため 
-- 計算データが投入されている間はパラメーターが変化しないようにすること。 


-- VHDL 1993 / IEEE 1076-1993
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_misc.all;

library lpm;
use lpm.lpm_components.all;

entity peridot_cnn_kernel_conv is
	port(
		test_y0		: out std_logic_vector(8 downto 0);
		test_y1		: out std_logic_vector(8 downto 0);
		test_y2		: out std_logic_vector(8 downto 0);


		clk			: in  std_logic;
		enable		: in  std_logic := '1';		-- clock enable

		sign_ena	: in  std_logic;			-- Line data sign extension : '1'=signed 8bit / '0'=unsigned 8bit
		pack_ena	: in  std_logic;			-- Function mode : '1'=Byte Packing mode / '0'=normal mode(CNN)
		byte_pos	: in  std_logic_vector(1 downto 0);		-- Indicates the byte position when byte packing mode.
		wk00		: in  std_logic_vector(8 downto 0);		-- Kernel wait Wk00～ Wk22 : s9
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
end peridot_cnn_kernel_conv;

architecture RTL of peridot_cnn_kernel_conv is
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

	-- signal
	signal linedata_sig			: std_logic_vector(3*9-1 downto 0);
	signal linedelay_reg		: std_logic_vector(3*9*3-1 downto 0);

	signal multdataa_sig		: std_logic_vector(3*3*9-1 downto 0);
	signal multdatab_sig		: std_logic_vector(3*3*9-1 downto 0);
	signal multresult_sig		: std_logic_vector(3*3*18-1 downto 0);
	signal multadd1_sig			: std_logic_vector(3*19-1 downto 0);
	signal multadd2_sig			: std_logic_vector(21-1 downto 0);
	signal multadd1_reg			: std_logic_vector(multadd1_sig'range);
	signal multadd2_reg			: std_logic_vector(multadd2_sig'range);

	signal u8sat_sig			: std_logic_vector(7 downto 0);
	signal s8sat_sig			: std_logic_vector(7 downto 0);
	signal s18data_sig			: std_logic_vector(17 downto 0);
	signal u8sat_reg			: std_logic_vector(u8sat_sig'range);
	signal s8sat_reg			: std_logic_vector(s8sat_sig'range);
	signal s18data_reg			: std_logic_vector(s18data_sig'range);

	signal scalebyte_sig		: std_logic_vector(7 downto 0);
	signal scaledataa_sig		: std_logic_vector(17 downto 0);
	signal scaledatab_sig		: std_logic_vector(17 downto 0);
	signal scaleresult_sig		: std_logic_vector(35 downto 0);

begin

	test_y0 <= linedata_sig(2*9+8 downto 2*9+0);
	test_y1 <= linedata_sig(1*9+8 downto 1*9+0);
	test_y2 <= linedata_sig(0*9+8 downto 0*9+0);


	-- パイプラインレジスタ 

	process (clk) begin
		if rising_edge(clk) then
			if is_true(enable) then
				-- stage1
				linedelay_reg <= linedelay_reg(3*9*2-1 downto 0) & linedata_sig;

				-- stage2
				-- (mult_dataa, mult_datab)

				-- stage3
				-- (mult_result)

				-- stage4
				multadd1_reg <= multadd1_sig;

				-- stage5
				multadd2_reg <= multadd2_sig;

				-- stage6
				u8sat_reg <= u8sat_sig;
				s8sat_reg <= s8sat_sig;
				s18data_reg <= s18data_sig;

				-- stage7
				-- (mult_dataa, mult_datab)

				-- stage8
				-- (mult_result)
			end if;
		end if;
	end process;


	-- 入力符号ビット拡張処理 (符号拡張＋正負反転) 
		-- linedata_sig : y0n y1n y2n

	linedata_sig(2*9+8 downto 2*9+0) <= 0 - ((y0(7) and sign_ena) & y0);
	linedata_sig(1*9+8 downto 1*9+0) <= 0 - ((y1(7) and sign_ena) & y1);
	linedata_sig(0*9+8 downto 0*9+0) <= 0 - ((y2(7) and sign_ena) & y2);


	-- 3x3カーネル演算処理 
		-- multdataa_sig :  y00  y10  y20  y01  y11  y21  y02  y12  y22
		-- multdatab_sig : wk00 wk10 wk20 wk01 wk11 wk21 wk02 wk12 wk22

	multdataa_sig <= linedelay_reg;
	multdatab_sig <=	wk00 & wk10 & wk20 &
						wk01 & wk11 & wk21 &
						wk02 & wk12 & wk22;

	gen_loop_i : for i in 0 to 2 generate
		gen_loop_j : for j in 0 to 2 generate
			-- (s9 x s9) -> s18 *resultの上位2bitは必ず符号ビットになる 
			u_wk : lpm_mult
			generic map(
				lpm_type			=> "LPM_MULT",
				lpm_representation	=> "SIGNED",
				lpm_pipeline		=> 2,
				lpm_widtha			=> 9,
				lpm_widthb			=> 9,
				lpm_widthp			=> 18
			)
			port map(
				clock	=> clk,
				clken	=> enable,
				dataa	=> multdataa_sig((i*3+j)*9+8 downto (i*3+j)*9+0),
				datab	=> multdatab_sig((i*3+j)*9+8 downto (i*3+j)*9+0),
				result	=> multresult_sig((i*3+j)*18+17 downto (i*3+j)*18+0)
			);
		end generate;

		-- s17 + s17 + s17 -> s19
		multadd1_sig(i*19+18 downto i*19+0) <=
			slice_sxt(slice(multresult_sig, 17, (i*3+2)*18), 17+2, 0) +
			slice_sxt(slice(multresult_sig, 17, (i*3+1)*18), 17+2, 0) +
			slice_sxt(slice(multresult_sig, 17, (i*3+0)*18), 17+2, 0);
	end generate;

		-- s19 + s19 + s19 + bk(s20) -> s21
	multadd2_sig <=
		slice_sxt(slice(multadd1_reg, 19, 2*19), 19+2, 0) +
		slice_sxt(slice(multadd1_reg, 19, 1*19), 19+2, 0) +
		slice_sxt(slice(multadd1_reg, 19, 0*19), 19+2, 0) +
		slice_sxt(bk, 19+2, 0);


	-- バイトパッキングモード時の飽和処理 

		-- s21 -> u8
	u8sat_sig <=
		(others=>'0') when(multadd2_reg(20) = '1') else					-- 負数なら0に丸め 
		(others=>'1') when(slice(multadd2_reg, 4, 16) /= "0000") else	-- 255以上なら255に丸め 
		slice(multadd2_reg, 8, 8);

		-- s21 -> s8 *符号付きデータは整数部が7bitしかないのでMSBは無視 
	s8sat_sig <=
		(7=>multadd2_reg(19), others=>not multadd2_reg(19)) when(or_reduce(slice(multadd2_reg, 4, 15)) /= and_reduce(slice(multadd2_reg, 4, 15))) else	-- 正負の最大値に丸め 
		slice(multadd2_reg, 8, 8);

		-- s21 -> s18
	s18data_sig <= slice_sxt(multadd2_reg, 18, 3);


	-- ポストスケーリング処理 

	scalebyte_sig <= s8sat_reg when is_true(sign_ena) else u8sat_reg;

	scaledataa_sig <=
		repbit('0', 9) & scalebyte_sig & '0' when(is_true(pack_ena) and byte_pos(0) = '0') else
		'0' & scalebyte_sig & repbit('0', 9) when(is_true(pack_ena) and byte_pos(0) = '1') else
		s18data_reg;

	scaledatab_sig <=
		( 0=>'1', others=>'0') when(is_true(pack_ena) and byte_pos(1) = '0') else
		(16=>'1', others=>'0') when(is_true(pack_ena) and byte_pos(1) = '1') else
		sk;

		-- (s18 x s18) -> s36 *resultの上位2bitは必ず符号ビットになる 
	u_sk : lpm_mult
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
		clken	=> enable,
		dataa	=> scaledataa_sig,
		datab	=> scaledatab_sig,
		result	=> scaleresult_sig
	);

		-- s35 -> s32 *Skで範囲制限しているので[34:31]は全て符号ビットになっている 
	result <= slice(scaleresult_sig, 32, 1);



end RTL;
