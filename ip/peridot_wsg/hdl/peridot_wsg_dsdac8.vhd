-- ===================================================================
-- TITLE : PERIDOT-NGS / Loreley-WSG Delta-Sigma DAC output module
--
--     DESIGN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2007/02/18 -> 2007/02/18
--            : 2007/02/21 (FIXED)
--     MODIFY : 2016/10/25 CycloneIV/MAX10アップデート 
--
-- ===================================================================

-- The MIT License (MIT)
-- Copyright (c) 2008,2018 J-7SYSTEM WORKS LIMITED.
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


-- ●８倍線形補間ステージ 
--   線形補間のため、原信号f(t)に対して、1/(2n-1)^2 * f((2n-1)*t)の 
--   高次ノイズが重畳する。 
--
--    原信号  ３次  ５次  ７次  ９次  11次  13次  ‥‥ 
--      0dB  -19dB -27dB -33dB -38dB -41dB -44dB 
--
-- ●出力⊿∑変調ステージ 
--   フルスピードで動作する１ビット１次⊿∑変調ブロック。 
--
-- ●ポップノイズ 
--   ⊿∑変調の構造上、電源投入時のポップノイズは回避不可（できなくは 
--   ないが、ロジックリソースとのトレードオフ）。 
--   ポップノイズが不都合になる場合、ACカップリングコンデンサの後段に 
--   ミュートトランジスタを配置することで改善可能。 


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use IEEE.std_logic_arith.all;

entity peridot_wsg_dsdac8 is
	generic(
		PCMBITWIDTH		: integer := 12
	);
	port(
		reset		: in  std_logic;
		clk			: in  std_logic;
		fs_timing	: in  std_logic;
		fs8_timing	: in  std_logic;

		pcmdata_in	: in  std_logic_vector(PCMBITWIDTH-1 downto 0);
		dac_out		: out std_logic
	);
end peridot_wsg_dsdac8;

architecture RTL of peridot_wsg_dsdac8 is
	signal pcmin_reg	: std_logic_vector(PCMBITWIDTH-1 downto 0);
	signal delta_reg	: std_logic_vector(PCMBITWIDTH downto 0);
	signal osvpcm_reg	: std_logic_vector(PCMBITWIDTH+2 downto 0);

	signal pcm_sig		: std_logic_vector(PCMBITWIDTH-1 downto 0);
	signal add_sig		: std_logic_vector(PCMBITWIDTH downto 0);
	signal dse_reg		: std_logic_vector(PCMBITWIDTH-1 downto 0);
	signal dacout_reg	: std_logic;

begin


-- 線形８倍オーバーサンプリングステージ -----

	process(clk, reset)begin
		if (reset = '1') then
			pcmin_reg  <= (others=>'0');
			delta_reg  <= (others=>'0');
			osvpcm_reg <= (others=>'0');

		elsif rising_edge(clk) then
			if (fs_timing = '1') then
				pcmin_reg  <= pcmdata_in;
				delta_reg  <=(pcmdata_in(pcmdata_in'left)& pcmdata_in) - (pcmin_reg(pcmin_reg'left) & pcmin_reg);
				osvpcm_reg <= pcmin_reg & "000";

			elsif (fs8_timing = '1') then
				osvpcm_reg <= osvpcm_reg + (delta_reg(delta_reg'left) & delta_reg(delta_reg'left) & delta_reg);

			end if;

		end if;
	end process;


-- ⊿∑変調ステージ -----

	pcm_sig(pcm_sig'left) <= not osvpcm_reg(osvpcm_reg'left);
	pcm_sig(pcm_sig'left-1 downto 0) <= osvpcm_reg(osvpcm_reg'left-1 downto 3);

	add_sig <= ('0' & pcm_sig) + ('0' & dse_reg);

	process(clk, reset)begin
		if (reset = '1') then
			dse_reg    <= (others=>'0');
			dacout_reg <= '0';

		elsif rising_edge(clk) then
			dse_reg    <= add_sig(add_sig'left-1 downto 0);
			dacout_reg <= add_sig(add_sig'left);

		end if;
	end process;


	-- DAC出力 

	dac_out <= dacout_reg;



end RTL;
