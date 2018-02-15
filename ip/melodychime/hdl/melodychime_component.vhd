-- ===================================================================
-- TITLE : Melody Chime component
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2012/08/17 -> 2012/08/28
--            : 2012/08/28 (FIXED)
--
--     UPDATE : 2018/02/16
-- ===================================================================
-- *******************************************************************
--    (C) 2012-2018 J-7SYSTEM WORKS LIMITED. All rights Reserved.
--
-- * This module is a free sourcecode and there is NO WARRANTY.
-- * No restriction on use. You can use, modify and redistribute it
--   for personal, non-profit or commercial products UNDER YOUR
--   RESPONSIBILITY.
-- * Redistributions of source code must retain the above copyright
--   notice.
-- *******************************************************************


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
