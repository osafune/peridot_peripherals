-- ===================================================================
-- TITLE : PERIDOT-NGS / Loreley-WSG DAC I/F module
--
--     DESIGN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2008/07/01 -> 2008/07/01
--            : 2008/07/01 (FIXED)
--     MODIFY : 2016/10/25 CycloneIV E/MAX10アップデート 
--            : 2017/06/29 LPM_MULTのインスタンス変更 
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


-- 16bitPCMデータと15bitボリューム値から16bitのデータを生成 
-- 右詰め、MSBファースト、LRCK:Lch='H',Rch='L'、32bitデータ長で送信 

-- ボリューム値は0x4000(16384)が最大 
-- 0x4000を越えるデータを設定した場合はPCMデータのラップアラウンドを 
-- 起こすため、ボリューム値は前段で適宜マスクすること 
-- pcmdata入力はレジスタ受けではないので、前段はレジスタ出力にすること 


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_signed.all;
use IEEE.std_logic_arith.all;

LIBRARY lpm;
USE lpm.lpm_components.all;

entity peridot_wsg_audout is
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
end peridot_wsg_audout;

architecture RTL of peridot_wsg_audout is
	signal bclkcount		: std_logic_vector(6 downto 0);
	signal datshift_reg		: std_logic_vector(31 downto 0);
	signal volume_l_reg		: std_logic_vector(14 downto 0);
	signal volume_r_reg		: std_logic_vector(14 downto 0);
	signal pcmdata_l_reg	: std_logic_vector(15 downto 0);
	signal pcmdata_r_reg	: std_logic_vector(15 downto 0);
	signal fs_timing_sig	: std_logic;
	signal fs8_timing_sig	: std_logic;
	signal mul_l_sig		: std_logic_vector(31 downto 0);
	signal mul_r_sig		: std_logic_vector(31 downto 0);


	component peridot_wsg_dsdac8 is
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

	process(clk)begin
		if rising_edge(clk) then
			volume_l_reg <= volume_l;
			volume_r_reg <= volume_r;
		end if;
	end process;

	vol_l : lpm_mult
	generic map (
		lpm_type			=> "LPM_MULT",
		lpm_representation	=> "SIGNED",
		lpm_widtha			=> 16,
		lpm_widthb			=> 16,
		lpm_widthp			=> 32
	)
	port map (
		dataa	=> pcmdata_l,
		datab	=> ('0' & volume_l_reg),
		result	=> mul_l_sig
	);

	vol_r : lpm_mult
	generic map (
		lpm_type			=> "LPM_MULT",
		lpm_representation	=> "SIGNED",
		lpm_widtha			=> 16,
		lpm_widthb			=> 16,
		lpm_widthp			=> 32
	)
	port map (
		dataa	=> pcmdata_r,
		datab	=> ('0' & volume_r_reg),
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

	dac_l : peridot_wsg_dsdac8
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

	dac_r : peridot_wsg_dsdac8
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
