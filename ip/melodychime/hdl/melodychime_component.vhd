-- ===================================================================
-- TITLE : Melody Chime component
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2012/08/17 -> 2012/08/28
--            : 2012/08/28 (FIXED)
--
--     UPDATE : 2018/11/26
-- ===================================================================

-- The MIT License (MIT)
-- Copyright (c) 2012,2018 J-7SYSTEM WORKS LIMITED.
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


library IEEE;
use IEEE.std_logic_1164.all;

entity melodychime_component is
	generic(
		CLOCKFREQ	: integer := 50000000
	);
	port(
	--==== Avalon clock/reset ========================================
		csi_clk				: in  std_logic;
		rsi_reset			: in  std_logic;

	--==== Avalon-MM slave ===========================================
		avs_read			: in  std_logic;
		avs_readdata		: out std_logic_vector(31 downto 0);
		avs_write			: in  std_logic;
		avs_writedata		: in  std_logic_vector(31 downto 0);

	--==== user conduit ==============================================
		coe_tempo			: out std_logic;
		coe_aud				: out std_logic

	);
end melodychime_component;

architecture RTL of melodychime_component is

	component melodychime
	generic(
		CLOCK_FREQ_HZ	: integer
	);
	port(
		reset		: in  std_logic;
		clk			: in  std_logic;

		start		: in  std_logic;

		timing_1ms	: out std_logic;
		tempo_led	: out std_logic;
		aud_out		: out std_logic
	);
	end component;

begin

	u : melodychime
	generic map (
		CLOCK_FREQ_HZ => CLOCKFREQ
	)
	port map (
		reset		=> rsi_reset,
		clk			=> csi_clk,
		start		=> avs_write,
		tempo_led	=> coe_tempo,
		aud_out		=> coe_aud
	);

	avs_readdata <= (others=>'X');



end RTL;
