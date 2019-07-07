-- ===================================================================
-- TITLE : PERIDOT-NGS / 1/f fluctuator module
--
--     DESIGN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2019/05/15 -> 2019/06/12
--
-- ===================================================================

-- The MIT License (MIT)
-- Copyright (c) 2019 J-7SYSTEM WORKS LIMITED.
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
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use lpm.lpm_components.all;

entity peridot_led_fluctuator is
	port(
		test_pow_ans	: out std_logic_vector(35 downto 0);
		test_mult_ans	: out std_logic_vector(17 downto 0);
		test_ov_color	: out std_logic_vector(7 downto 0);
		test_add_color	: out std_logic_vector(8 downto 0);


		clk			: in  std_logic;
		init		: in  std_logic;

		ov_red		: in  std_logic_vector(7 downto 0);
		ov_green	: in  std_logic_vector(7 downto 0);
		ov_blue		: in  std_logic_vector(7 downto 0);

		fl_seed		: in  std_logic_vector(31 downto 0);
		fl_mode		: in  std_logic_vector(1 downto 0);
		fl_red		: in  std_logic_vector(7 downto 0);
		fl_green	: in  std_logic_vector(7 downto 0);
		fl_blue		: in  std_logic_vector(7 downto 0);

		start		: in  std_logic;

		pix_red		: out std_logic_vector(7 downto 0);
		pix_green	: out std_logic_vector(7 downto 0);
		pix_blue	: out std_logic_vector(7 downto 0);
		pix_valid	: out std_logic
	);
end peridot_led_fluctuator;

architecture RTL of peridot_led_fluctuator is
	type DEF_STATE_CALC is (IDLE, F_POW, MULT_RED, MULT_GREEN, MULT_BLUE, DONE);
	signal state		: DEF_STATE_CALC;

	signal x_reg		: std_logic_vector(31 downto 0);
	signal a_sig		: std_logic_vector(31 downto 0);
	signal b_sig		: std_logic_vector(31 downto 0);
	signal c_sig		: std_logic_vector(31 downto 0);
	signal rand_sig		: std_logic_vector(31 downto 0);

	signal f_reg		: std_logic_vector(17 downto 0);
	signal inv_f_sig	: std_logic_vector(18 downto 0);
	signal pow_a_reg	: std_logic_vector(17 downto 0);
	signal pow_ans_sig	: std_logic_vector(35 downto 0);
	signal add_2f_sig	: std_logic_vector(17 downto 0);
	signal cos19_sig	: std_logic_vector(15 downto 0);

	signal mult_a_reg	: std_logic_vector(8 downto 0);
	signal mult_b_reg	: std_logic_vector(8 downto 0);
	signal mult_ans_sig	: std_logic_vector(17 downto 0);
	signal ov_color_sig	: std_logic_vector(7 downto 0);
	signal add_color_sig: std_logic_vector(8 downto 0);
	signal add_sat_sig	: std_logic_vector(7 downto 0);
	signal fl_red_reg	: std_logic_vector(7 downto 0);
	signal fl_green_reg	: std_logic_vector(7 downto 0);
	signal fl_blue_reg	: std_logic_vector(7 downto 0);
	signal valid_reg	: std_logic;

begin

	-- テスト入出力 

	test_pow_ans <= pow_ans_sig;
	test_mult_ans <= mult_ans_sig;
	test_ov_color <= ov_color_sig;
	test_add_color <= add_color_sig;


	----------------------------------------------------------------------
	-- Main control
	----------------------------------------------------------------------

	-- Xorshift32

	a_sig <= x_reg xor (x_reg(18 downto 0) & "0000000000000");
	b_sig <= a_sig xor ("00000000000000000" & a_sig(31 downto 17));
	c_sig <= b_sig xor (b_sig(16 downto 0) & "000000000000000");
	rand_sig <= x_reg;


	-- pow_u18

	inv_f_sig <= conv_std_logic_vector(262144, 19) - ('0' & f_reg);

	u_pow : lpm_mult
	generic map(
		lpm_type			=> "LPM_MULT",
		lpm_representation	=> "UNSIGNED",
		lpm_hint			=> "MAXIMIZE_SPEED=5",
		lpm_widtha			=> 18,
		lpm_widthb			=> 18,
		lpm_widthp			=> 36
	)
	port map(
		dataa	=> pow_a_reg,
		datab	=> pow_a_reg,
		result	=> pow_ans_sig
	);

	add_2f_sig <= pow_ans_sig(34 downto 18) & (pow_ans_sig(17) xor rand_sig(31));


	-- mult_u9xu9

	u_mult : lpm_mult
	generic map(
		lpm_type			=> "LPM_MULT",
		lpm_representation	=> "UNSIGNED",
		lpm_hint			=> "MAXIMIZE_SPEED=5",
		lpm_widtha			=> 9,
		lpm_widthb			=> 9,
		lpm_widthp			=> 18
	)
	port map(
		dataa	=> mult_a_reg,
		datab	=> mult_b_reg,
		result	=> mult_ans_sig
	);

	with (state) select ov_color_sig <=
		ov_red		when MULT_GREEN,
		ov_green	when MULT_BLUE,
		ov_blue		when others;

	add_color_sig <= ('0' & mult_ans_sig(17 downto 10)) + ('0' & ov_color_sig);
	add_sat_sig <= add_color_sig(7 downto 0) when(add_color_sig(8) = '0') else (others=>'1');


	-- cos^19近似（ハイライト）

	cos19_sig <= (others=>'0') when(rand_sig(17) = '0') else
			"000" & rand_sig(15 downto 3) when(rand_sig(17 downto 16) = "10") else
			"111" & rand_sig(13 downto 1) when(rand_sig(17 downto 14) = "1111") else
			rand_sig(15 downto 0) + conv_std_logic_vector(8192, 16);


	-- main FSM

	process (clk) begin
		if rising_edge(clk) then
			if (init = '1') then
				state <= IDLE;
--				x_reg <= conv_std_logic_vector(2463534242, 32);
				x_reg <= fl_seed;
				f_reg <= fl_seed(17 downto 0);
				valid_reg <= '0';

			else
				case state is
				when IDLE =>
					valid_reg <= '0';

					if (start = '1') then
						state <= F_POW;

						if (f_reg(17) = '1') then
							pow_a_reg <= inv_f_sig(17 downto 0);
						else
							pow_a_reg <= f_reg;
						end if;
					end if;

				-- 間欠カオス法の演算 
				when F_POW =>
					state <= MULT_RED;

					pow_a_reg <= rand_sig(17 downto 0);

					if (f_reg(17 downto 14) = "1111") then
						f_reg <= f_reg - ("000000" & rand_sig(11 downto 0));
					elsif (f_reg(17 downto 14) = "0000") then
						f_reg <= f_reg + ("000000" & rand_sig(11 downto 0));
					else
						if (f_reg(17) = '1') then
							f_reg <= f_reg - add_2f_sig;
						else
							f_reg <= f_reg + add_2f_sig;
						end if;
					end if;

				-- レイヤー色輝度の演算 
				when MULT_RED =>
					state <= MULT_GREEN;

					case fl_mode is
					-- FLMODE=00 : RAND値でレイヤー合成輝度を変化 
					when "00" => mult_a_reg <= rand_sig(17 downto 9);

					-- FLMODE=01 : RAND^2値でレイヤー合成輝度を変化 
					when "01" => mult_a_reg <= pow_ans_sig(35 downto 27);

					-- FLMODE=10 : 1/f値でレイヤー合成輝度を変化 
					when "10" => mult_a_reg <= f_reg(17 downto 9);

					-- FLMODE=11 : cos^19近似値でレイヤー合成輝度を変化 
					when others => mult_a_reg <= cos19_sig(15 downto 7);
					end case;

					mult_b_reg <= fl_red & fl_red(7);

				when MULT_GREEN =>
					state <= MULT_BLUE;

					mult_b_reg <= fl_green & fl_green(7);
					fl_red_reg <= add_sat_sig;

				when MULT_BLUE =>
					state <= DONE;

					mult_b_reg <= fl_blue & fl_blue(7);
					fl_green_reg <= add_sat_sig;

				when DONE =>
					state <= IDLE;

					x_reg <= c_sig;
					fl_blue_reg <= add_sat_sig;
					valid_reg <= '1';

				end case;
			end if;

		end if;
	end process;


	-- data output

	pix_red <= fl_red_reg;
	pix_green <= fl_green_reg;
	pix_blue <= fl_blue_reg;
	pix_valid <= valid_reg;



end RTL;
