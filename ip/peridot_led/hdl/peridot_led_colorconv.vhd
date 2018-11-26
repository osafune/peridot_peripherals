-- ===================================================================
-- TITLE : PERIDOT-NGS / color gamma convert
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2018/11/24 -> 2018/11/25
--
-- ===================================================================

-- The MIT License (MIT)
-- Copyright (c) 2018 J-7SYSTEM WORKS LIMITED.
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

library ieee;
library lpm;
library altera_mf;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_misc.all;
use lpm.lpm_components.all;
use altera_mf.altera_mf_components.all;


entity peridot_led_colorconv is
	generic(
		LED_COLOR_TRANSOEDER	: string := "GRB"	-- LEDへ転送する色順序 
--		LED_COLOR_TRANSOEDER	: string := "RGB"	-- LEDへ転送する色順序 
	);
	port(
--		test_mul_a		: out std_logic_vector(8 downto 0);
--		test_mul_b		: out std_logic_vector(8 downto 0);
--		test_cdata		: out std_logic_vector(9 downto 0);


		clk			: in  std_logic;

		sel			: in  std_logic_vector(1 downto 0);
		br_red		: in  std_logic_vector(7 downto 0);
		br_green	: in  std_logic_vector(7 downto 0);
		br_blue		: in  std_logic_vector(7 downto 0);

		pixel_in	: in  std_logic_vector(17 downto 0);
		data_out	: out std_logic_vector(7 downto 0)
	);
end peridot_led_colorconv;

architecture RTL of peridot_led_colorconv is
	function CSTD(NUM:integer; WID:integer) return std_logic_vector is
	begin
		return conv_std_logic_vector(NUM, WID);
	end CSTD;

	signal bright_sig		: std_logic_vector(7 downto 0);
	signal csub_sig			: std_logic_vector(5 downto 0);

	signal mul_a_sig		: std_logic_vector(8 downto 0);
	signal mul_b_sig		: std_logic_vector(8 downto 0);
	signal mul_result_sig	: std_logic_vector(17 downto 0);
	signal mul_result_reg	: std_logic_vector(17 downto 0);

	signal cdata_sig		: std_logic_vector(9 downto 0);
	signal gconv0_sig		: std_logic_vector(9 downto 0);
	signal gconv1_sig		: std_logic_vector(10 downto 0);
	signal gconv2_sig		: std_logic_vector(11 downto 0);

begin

--	test_mul_a <= mul_a_sig;
--	test_mul_b <= mul_b_sig;
--	test_cdata <= cdata_sig;


	-- 色要素選択 

	trans_grb : if LED_COLOR_TRANSOEDER = "GRB" generate	-- GRB順で転送 
		bright_sig <=
			br_blue when(sel = "10") else
			br_red when(sel = "01") else
			br_green;

		csub_sig <=
			pixel_in( 5 downto  0) when(sel = "10") else	-- B
			pixel_in(17 downto 12) when(sel = "01") else	-- R
			pixel_in(11 downto  6);							-- G
	end generate;

	trans_rgb : if LED_COLOR_TRANSOEDER = "RGB" generate	-- RGB順で転送 
		bright_sig <=
			br_blue when(sel = "10") else
			br_green when(sel = "01") else
			br_red;

		csub_sig <=
			pixel_in( 5 downto  0) when(sel = "10") else	-- B
			pixel_in(11 downto  6) when(sel = "01") else	-- G
			pixel_in(17 downto 12);							-- R
	end generate;


	-- 輝度変換 

	mul_a_sig <= "0" & bright_sig;
	mul_b_sig <= "000" & csub_sig;

	u0 : lpm_mult
	generic map (
		lpm_hint => "MAXIMIZE_SPEED=5",
		lpm_representation => "SIGNED",
		lpm_type => "LPM_MULT",
		lpm_widtha => mul_a_sig'length,
		lpm_widthb => mul_b_sig'length,
		lpm_widthp => mul_result_sig'length
	)
	port map (
		dataa => mul_a_sig,
		datab => mul_b_sig,
		result => mul_result_sig
	);

	process (clk) begin
		if rising_edge(clk) then
			mul_result_reg <= mul_result_sig;
		end if;
	end process;


	-- 三乗近似変換 

	cdata_sig <= mul_result_reg(13 downto 4);	-- 範囲は0～1004 

	gconv0_sig <= ("0" & cdata_sig(8 downto 0)) + CSTD(15, 10);		-- 0～511区間 
	gconv1_sig <= ("0" & cdata_sig(7 downto 0) & "00") + ("000" & cdata_sig(7 downto 0)) + CSTD(528, 11);		-- 512～767区間 
	gconv2_sig <= ("0" & cdata_sig(7 downto 0) & "000") + ("0000" & cdata_sig(7 downto 0)) + CSTD(1816, 12);	-- 768～1004区間 

	data_out <=
		gconv2_sig(11 downto 4)			when(cdata_sig(9 downto 8) = "11") else
		("0" & gconv1_sig(10 downto 4))	when(cdata_sig(9 downto 8) = "10") else
		("00" & gconv0_sig(9 downto 4));



end RTL;
