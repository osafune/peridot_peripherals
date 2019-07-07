-- ===================================================================
-- TITLE : PERIDOT-NGS / color gamma convert
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2018/11/24 -> 2018/11/25
--     MODIFY : 2019/06/08 s.osafune@j7system.jp
--
-- ===================================================================

-- The MIT License (MIT)
-- Copyright (c) 2018,2019 J-7SYSTEM WORKS LIMITED.
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


----------------------------------------------------------------------
--  mult_u8xu6 sub module
----------------------------------------------------------------------

library ieee;
library lpm;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use lpm.lpm_components.all;

entity peridot_led_colorconv_mult_u8xu6 is
	port(
		clk			: in  std_logic;
		dataa_in	: in  std_logic_vector(7 downto 0);
		datab_in	: in  std_logic_vector(5 downto 0);
		result		: out std_logic_vector(9 downto 0)
	);
end peridot_led_colorconv_mult_u8xu6;

architecture RTL of peridot_led_colorconv_mult_u8xu6 is
	signal mul_a_sig		: std_logic_vector(8 downto 0);
	signal mul_b_sig		: std_logic_vector(8 downto 0);
	signal mul_result_sig	: std_logic_vector(17 downto 0);
	signal mul_result_reg	: std_logic_vector(17 downto 0);

begin

	mul_a_sig <= dataa_in & dataa_in(7);
	mul_b_sig <= datab_in & datab_in(5 downto 3);

	u : lpm_mult
	generic map (
		lpm_type			=> "LPM_MULT",
		lpm_representation	=> "UNSIGNED",
		lpm_hint			=> "MAXIMIZE_SPEED=5",
		lpm_widtha			=> 9,
		lpm_widthb			=> 9,
		lpm_widthp			=> 18
	)
	port map (
		dataa	=> mul_a_sig,
		datab	=> mul_b_sig,
		result	=> mul_result_sig
	);

	process (clk) begin
		if rising_edge(clk) then
			mul_result_reg <= mul_result_sig;
		end if;
	end process;

	result <= mul_result_reg(17 downto 8);

end RTL;



----------------------------------------------------------------------
--  top module
----------------------------------------------------------------------
-- パイプライン演算処理でdata_out確定は2クロックレイテンシ 
-- ov_modeは非パイプラインなので、演算処理中は固定させておくこと 

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use work.peridot_led_colorconv_mult_u8xu6;

entity peridot_led_colorconv is
	generic(
		LED_COLOR_TRANSORDER	: string := "GRB";	-- LEDへ転送する色順序 
--		LED_COLOR_TRANSORDER	: string := "RGB";	-- LEDへ転送する色順序 
		USE_LAYER_BLEND			: string := "ON"	-- レイヤ合成を行う 
--		USE_LAYER_BLEND			: string := "OFF"	-- レイヤ合成を行わない(ov_～のポートは無視) 
	);
	port(
		test_base_res	: out std_logic_vector(9 downto 0);
		test_layer_res	: out std_logic_vector(9 downto 0);

		clk			: in  std_logic;

		calc_req	: in  std_logic;
		sel			: in  std_logic_vector(1 downto 0);

		br_red		: in  std_logic_vector(7 downto 0);
		br_green	: in  std_logic_vector(7 downto 0);
		br_blue		: in  std_logic_vector(7 downto 0);
		br_pixel_in	: in  std_logic_vector(17 downto 0);

		ov_mode		: in  std_logic_vector(1 downto 0) := "00";
		ov_red		: in  std_logic_vector(7 downto 0) := (others=>'0');
		ov_green	: in  std_logic_vector(7 downto 0) := (others=>'0');
		ov_blue		: in  std_logic_vector(7 downto 0) := (others=>'0');
		ov_pixel_in	: in  std_logic_vector(17 downto 0) := (others=>'0');

		valid		: out std_logic;
		data_out	: out std_logic_vector(7 downto 0)
	);
end peridot_led_colorconv;

architecture RTL of peridot_led_colorconv is
	function CSTD(NUM:integer; WID:integer) return std_logic_vector is
	begin
		return conv_std_logic_vector(NUM, WID);
	end CSTD;

	signal valid_delay_reg	: std_logic_vector(1 downto 0) := (others=>'0');
	signal bright_sig		: std_logic_vector(7 downto 0);
	signal csub_sig			: std_logic_vector(5 downto 0);
	signal alpha_sig		: std_logic_vector(7 downto 0);
	signal ovsub_sig		: std_logic_vector(5 downto 0);
	signal ov_zero_sig		: std_logic;

	signal ov_zero_reg		: std_logic;
	signal base_res_sig		: std_logic_vector(9 downto 0);
	signal layer_res_sig	: std_logic_vector(9 downto 0);
	signal blend_add_sig	: std_logic_vector(10 downto 0);
	signal blend_sub_sig	: std_logic_vector(10 downto 0);
	signal blend0_sig		: std_logic_vector(9 downto 0);
	signal blend1_sig		: std_logic_vector(9 downto 0);
	signal blend2_sig		: std_logic_vector(9 downto 0);
	signal blend3_sig		: std_logic_vector(9 downto 0);
	signal blend_reg		: std_logic_vector(9 downto 0);
	signal cdata_sig		: std_logic_vector(9 downto 0);

	signal gconv0_sig		: std_logic_vector(9 downto 0);
	signal gconv1_sig		: std_logic_vector(10 downto 0);
	signal gconv2_sig		: std_logic_vector(11 downto 0);

begin

	test_base_res <= base_res_sig;
	test_layer_res <= layer_res_sig;


	--------------------
	-- タイミング信号 --
	--------------------

	process (clk) begin
		if rising_edge(clk) then
			valid_delay_reg <= valid_delay_reg(valid_delay_reg'left-1 downto 0) & calc_req;
		end if;
	end process;

	valid <= valid_delay_reg(1);


	----------------
	-- 色要素選択 --
	----------------

	-- GRB順で転送する場合 
	trans_grb : if (LED_COLOR_TRANSORDER = "GRB") generate
		with (sel) select bright_sig <=
			br_blue		when "10",
			br_red		when "01",
			br_green	when others;

		with (sel) select csub_sig <=
			br_pixel_in( 5 downto  0) when "10",	-- B
			br_pixel_in(17 downto 12) when "01",	-- R
			br_pixel_in(11 downto  6) when others;	-- G

		with (sel) select alpha_sig <=
			ov_blue		when "10",
			ov_red		when "01",
			ov_green	when others;

		with (sel) select ovsub_sig <=
			ov_pixel_in( 5 downto  0) when "10",	-- B
			ov_pixel_in(17 downto 12) when "01",	-- R
			ov_pixel_in(11 downto  6) when others;	-- G
	end generate;

	-- RGB順で転送する場合 
	trans_rgb : if (LED_COLOR_TRANSORDER = "RGB") generate
		with (sel) select bright_sig <=
			br_blue		when "10",
			br_green	when "01",
			br_red		when others;

		with (sel) select csub_sig <=
			br_pixel_in( 5 downto  0) when "10",	-- B
			br_pixel_in(11 downto  6) when "01",	-- G
			br_pixel_in(17 downto 12) when others;	-- R

		with (sel) select alpha_sig <=
			ov_blue		when "10",
			ov_green	when "01",
			ov_red		when others;

		with (sel) select ovsub_sig <=
			ov_pixel_in( 5 downto  0) when "10",	-- B
			ov_pixel_in(11 downto  6) when "01",	-- G
			ov_pixel_in(17 downto 12) when others;	-- R
	end generate;

	ov_zero_sig <= '1' when(ov_pixel_in = 0) else '0';


	----------------------------
	-- 輝度変換とレイヤー合成 --
	----------------------------

	u0 : peridot_led_colorconv_mult_u8xu6
	port map (
		clk			=> clk,
		dataa_in	=> bright_sig,
		datab_in	=> csub_sig,
		result		=> base_res_sig
	);

	-- レイヤー合成を使う場合 
	use_blend : if (USE_LAYER_BLEND = "ON") generate
		u1 : peridot_led_colorconv_mult_u8xu6
		port map (
			clk			=> clk,
			dataa_in	=> alpha_sig,
			datab_in	=> ovsub_sig,
			result		=> layer_res_sig
		);

		process (clk) begin
			if rising_edge(clk) then
				ov_zero_reg <= ov_zero_sig;
			end if;
		end process;

		-- MODE=00 : キー合成(RGB=000のピクセルは透明と見なす)
		blend0_sig <= base_res_sig when(ov_zero_reg = '1') else layer_res_sig;

		-- MODE=01 : 加算合成 
		blend_add_sig <= ('0' & base_res_sig) + ('0' & layer_res_sig);
		blend1_sig <= blend_add_sig(9 downto 0) when(blend_add_sig(10) = '0') else (others=>'1');

		-- MODE=10 : 減算合成 
		blend_sub_sig <= ('1' & base_res_sig) - ('0' & layer_res_sig);
		blend2_sig <= blend_sub_sig(9 downto 0) when(blend_sub_sig(10) = '1') else (others=>'0');

		-- MODE=11 : 比較(明)
		blend3_sig <= base_res_sig when(blend_sub_sig(10) = '1') else layer_res_sig;

		process (clk) begin
			if rising_edge(clk) then
				case ov_mode is
				when "01" =>
					blend_reg <= blend1_sig;
				when "10" =>
					blend_reg <= blend2_sig;
				when "11" =>
					blend_reg <= blend3_sig;
				when others =>
					blend_reg <= blend0_sig;
				end case;
			end if;
		end process;

		cdata_sig <= blend_reg;	-- 範囲は0～1023 
	end generate;

	-- レイヤー合成を使わない場合 
	no_blend : if (USE_LAYER_BLEND /= "ON") generate
		process (clk) begin
			if rising_edge(clk) then
				blend_reg <= base_res_sig;
			end if;
		end process;

		cdata_sig <= blend_reg;	-- 範囲は0～1020 
	end generate;


	------------------
	-- 三乗近似変換 --
	------------------

	-- 0～511区間 
	gconv0_sig <= ("0" & cdata_sig(8 downto 0)) + CSTD(15, 10);

	-- 512～767区間 
	gconv1_sig <= ("0" & cdata_sig(7 downto 0) & "00") + ("000" & cdata_sig(7 downto 0)) + CSTD(526, 11);

	-- 768～1023区間 
	gconv2_sig <= ("0" & cdata_sig(7 downto 0) & "000") + ("0000" & cdata_sig(7 downto 0)) + CSTD(1800, 12);

	data_out <=
		gconv2_sig(11 downto 4)			when(cdata_sig(9 downto 8) = "11") else
		("0" & gconv1_sig(10 downto 4))	when(cdata_sig(9 downto 8) = "10") else
		("00" & gconv0_sig(9 downto 4));



end RTL;
