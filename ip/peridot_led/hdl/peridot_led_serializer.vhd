-- ===================================================================
-- TITLE : PERIDOT-NGS / WS2812B/SK6812 data serializer
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2018/10/21 -> 2018/10/25
--     MODIFY : 2019/06/01 s.osafune@j7system.jp
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
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity peridot_led_serializer is
	generic(
		PROPAGATION_DELAY	: integer := 2	-- 次のチャネルへ伝搬するタイミング信号の遅延量
	);
	port(
		clk			: in  std_logic;
		init		: in  std_logic := '0';

		timing		: in  std_logic;
		load		: in  std_logic;
		timing_next	: out std_logic;
		load_next	: out std_logic;

		data_in		: in  std_logic_vector(7 downto 0);
		led_out		: out std_logic
	);
end peridot_led_serializer;

architecture RTL of peridot_led_serializer is
	type SYMBOL_STATE is (S0, S1, SHIFT);
	signal state : SYMBOL_STATE;

	signal data_reg			: std_logic_vector(7 downto 0);
	signal led_reg			: std_logic := '0';
	signal timing_reg		: std_logic_vector(PROPAGATION_DELAY-1 downto 0);
	signal load_reg			: std_logic_vector(PROPAGATION_DELAY-1 downto 0);

begin

	-- LED信号のエンコード 

	process (clk) begin
		if rising_edge(clk) then
			if (init = '1') then
				timing_reg <= (others=>'0');
				load_reg <= (others=>'0');
				led_reg <= '0';

			else
				if (PROPAGATION_DELAY > 1) then
					timing_reg <= timing_reg(timing_reg'left-1 downto 0) & timing;
					load_reg <= load_reg(load_reg'left-1 downto 0) & load;
				else
					timing_reg(0) <= timing;
					load_reg(0) <= load;
				end if;

				if (timing = '1') then
					if (load = '1') then
						state <= S0;
						data_reg <= data_in;
						led_reg <= '1';

					else
						case (state) is
						when S0 =>
							state <= S1;
							if (data_reg(7) = '0') then
								led_reg <= '0';
							end if;

						when S1 =>
							state <= SHIFT;
							if (data_reg(7) = '1') then
								led_reg <= '0';
							end if;

						when SHIFT =>
							state <= S0;
							data_reg <= data_reg(6 downto 0) & '0';
							led_reg <= '1';

						when others =>
						end case;

					end if;
				end if;

			end if;
		end if;
	end process;

	timing_next <= timing_reg(timing_reg'left);
	load_next <= load_reg(load_reg'left);

	led_out <= led_reg;



end RTL;
