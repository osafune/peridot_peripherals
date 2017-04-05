-- ===================================================================
-- TITLE : Loreley-WSG DAC I/F module
--
--     DESIGN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2008/07/01 -> 2008/07/01
--            : 2008/07/01 (FIXED)
--     MODIFY : 2016/10/25 CycloneIV E/MAX10アップデート 
--
-- ===================================================================
-- *******************************************************************
--    (C) 2008-2016, J-7SYSTEM WORKS LIMITED.  All rights Reserved.
--
-- * This module is a free sourcecode and there is NO WARRANTY.
-- * No restriction on use. You can use, modify and redistribute it
--   for personal, non-profit or commercial products UNDER YOUR
--   RESPONSIBILITY.
-- * Redistributions of source code must retain the above copyright
--   notice.
-- *******************************************************************

-- 16bitPCMデータと15bitボリューム値から16bitのデータを生成 
-- 右詰め、MSBファースト、LRCK:Lch='H',Rch='L'、32bitデータ長で送信 

-- ボリューム値は0x4000(16384)が最大 
-- 0x4000を越えるデータを設定した場合はPCMデータのラップアラウンドを 
-- 起こすため、ボリューム値は前段で適宜マスクすること 
-- pcmdata入力およびvolume入力はレジスタ受けではないので、前段は 
-- レジスタ出力にすること 


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_signed.all;
use IEEE.std_logic_arith.all;

entity wsg_audout is
	generic(
		DSDAC_PCMBITWIDTH	: integer := 12		-- 1bitDSDAC valid bit width
	);
	port(
		test_fstiming		: out  std_logic;
		test_fs8timing		: out  std_logic;

		reset		: in  std_logic;
		clk			: in  std_logic;
		clk_ena		: in  std_logic := '1';		-- Pulse width 1clock time (128fs)
		fs_timing	: out std_logic;

		volume_l	: in  std_logic_vector(14 downto 0);	-- 符号なし 
		volume_r	: in  std_logic_vector(14 downto 0);
		pcmdata_l	: in  std_logic_vector(15 downto 0);	-- 符号付き 
		pcmdata_r	: in  std_logic_vector(15 downto 0);

		dac_bclk	: out std_logic;
		dac_lrck	: out std_logic;
		dac_data	: out std_logic;
		aud_l		: out std_logic;
		aud_r		: out std_logic
	);
end wsg_audout;

architecture RTL of wsg_audout is
	signal bclkcount		: std_logic_vector(6 downto 0);
	signal datshift_reg		: std_logic_vector(31 downto 0);
	signal pcmdata_l_reg	: std_logic_vector(15 downto 0);
	signal pcmdata_r_reg	: std_logic_vector(15 downto 0);
	signal fs_timing_sig	: std_logic;
	signal fs8_timing_sig	: std_logic;


	component wsg_mul_s16x16
	PORT (
		dataa		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		datab		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		result		: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
	end component;
	signal mul_l_sig		: std_logic_vector(31 downto 0);
	signal mul_r_sig		: std_logic_vector(31 downto 0);


	component wsg_dsdac8 is
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
	end component;


begin

	test_fstiming  <= fs_timing_sig;
	test_fs8timing <= fs8_timing_sig;


--==== マスターボリュームとI2S出力部 ================================

	-- マスターボリューム 

	vol_l : wsg_mul_s16x16
	port map (
		dataa	=> pcmdata_l,
		datab	=> ('0' & volume_l),
		result	=> mul_l_sig
	);

	vol_r : wsg_mul_s16x16
	port map (
		dataa	=> pcmdata_r,
		datab	=> ('0' & volume_r),
		result	=> mul_r_sig
	);


	-- 16bit-RJ信号生成 

	process(clk, reset)begin
		if (reset = '1') then
			bclkcount <= (others=>'0');
			pcmdata_l_reg <= (others=>'0');
			pcmdata_r_reg <= (others=>'0');

		elsif rising_edge(clk) then
			if (clk_ena = '1') then
				bclkcount <= bclkcount + '1';

				if (bclkcount(1 downto 0) = "11") then
					if (bclkcount(6 downto 2) = "11111") then
						pcmdata_l_reg <= mul_l_sig(29 downto 14);
						pcmdata_r_reg <= mul_r_sig(29 downto 14);

						datshift_reg <= pcmdata_l_reg & pcmdata_r_reg;
					else
						datshift_reg <= datshift_reg(30 downto 0) & 'X';
					end if;
				end if;
			end if;

		end if;
	end process;

	fs_timing <= bclkcount(6);

	dac_bclk <= bclkcount(1);
	dac_lrck <= bclkcount(6);
	dac_data <= datshift_reg(31);



--==== 1bitDAC出力部 ================================================

	fs_timing_sig  <= '1' when(clk_ena = '1' and bclkcount = 0) else '0';
	fs8_timing_sig <= '1' when(clk_ena = '1' and bclkcount(3 downto 0) = "0000") else '0';


	-- 1bitDACのインスタンス 

	dac_l : wsg_dsdac8
	generic map (
		PCMBITWIDTH		=> DSDAC_PCMBITWIDTH
	)
	port map (
		reset			=> reset,
		clk				=> clk,
		fs_timing		=> fs_timing_sig,
		fs8_timing		=> fs8_timing_sig,
		pcmdata_in		=> pcmdata_l_reg(15 downto 16-DSDAC_PCMBITWIDTH),
		dac_out			=> aud_l
	);

	dac_r : wsg_dsdac8
	generic map (
		PCMBITWIDTH		=> DSDAC_PCMBITWIDTH
	)
	port map (
		reset			=> reset,
		clk				=> clk,
		fs_timing		=> fs_timing_sig,
		fs8_timing		=> fs8_timing_sig,
		pcmdata_in		=> pcmdata_r_reg(15 downto 16-DSDAC_PCMBITWIDTH),
		dac_out			=> aud_r
	);



end RTL;
