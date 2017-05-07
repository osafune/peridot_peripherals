-- ===================================================================
-- TITLE : PERIDOT-NGS / WaveTable Sound Genarator
--
--     DESIGN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2009/01/01 -> 2009/01/09
--            : 2009/01/15 (FIXED)
--
--     MODIFY : 2016/10/25 CycloneIV/MAX10用アップデート 
--            : 2017/04/06 PERIDOTペリフェラル対応 
--            : 2017/05/08 アドレス修正、キー入力対応 
--
-- ===================================================================
-- *******************************************************************
--    (C) 2009-2017, J-7SYSTEM WORKS LIMITED.  All rights Reserved.
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
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;

entity wsg_component is
	generic(
		AUDIOCLOCKFREQ		: integer := 24576000;	-- input audio_clk freq
		SAMPLINGFREQ		: integer := 32000;		-- output sampleing freq
		MAXSLOTNUM			: integer := 64;		-- generate slot number(32～64)
		PCM_CHANNEL_GENNUM	: integer := 2;			-- PCM instance number(0～8) 
		WAVETABLE_INIT_FILE	: string := "UNUSED"
	);
	port(
		csi_global_reset	: in  std_logic;

		----- AvalonMM信号(メモリスレーブ) -----------
		avs_s1_clk			: in  std_logic;

		avs_s1_address		: in  std_logic_vector(9 downto 1);
		avs_s1_read			: in  std_logic;
		avs_s1_readdata		: out std_logic_vector(15 downto 0);
		avs_s1_write		: in  std_logic;
		avs_s1_writedata	: in  std_logic_vector(15 downto 0);
		avs_s1_byteenable	: in  std_logic_vector(1 downto 0);

		avs_s1_irq			: out std_logic;

		----- オーディオ信号 -----------
		audio_clk			: in  std_logic;		-- 24.576MHz typ

		dac_bclk			: out std_logic;
		dac_lrck			: out std_logic;
		dac_data			: out std_logic;
		aud_l				: out std_logic;
		aud_r				: out std_logic;
		mute				: out std_logic;

		----- 外部キー入力 -----------
		kb_scko				: out std_logic;
		kb_load_n			: out std_logic;
		kb_sdin				: in  std_logic
	);
end wsg_component;

architecture RTL of wsg_component is
	constant FS128FREQ		: integer := SAMPLINGFREQ * 128;
	constant CLOCKDIV		: integer := (AUDIOCLOCKFREQ / FS128FREQ) - 1;
--	constant CLOCKDIV		: integer := 1;				-- test
	signal divcount			: integer range 0 to CLOCKDIV;
	signal fs128_timing_sig	: std_logic;
	signal async_fs_sig		: std_logic;

	signal audio_clk_sig	: std_logic;
	signal audio_reset_sig	: std_logic;
	signal audio_reset_reg	: std_logic;
	signal audio_mute_reg	: std_logic;


	component wsg_businterface
	generic(
		WAVETABLE_INIT_FILE	: string
	);
	port(
		clk				: in  std_logic;	-- system clock
		reset			: in  std_logic;	-- async reset
		async_fs_in		: in  std_logic;	-- Async fs signal input
		mute_out		: out std_logic;
		mastervol_l		: out std_logic_vector(14 downto 0);
		mastervol_r		: out std_logic_vector(14 downto 0);
		inkey_scko		: out std_logic;	-- external key serial-input
		inkey_load_n	: out std_logic;
		inkey_sdin		: in  std_logic;

		address			: in  std_logic_vector(9 downto 0);
		readdata		: out std_logic_vector(15 downto 0);
		read			: in  std_logic;
		writedata		: in  std_logic_vector(15 downto 0);
		write			: in  std_logic;
		byteenable		: in  std_logic_vector(1 downto 0);
		irq				: out std_logic;
		ext_address		: out std_logic_vector(5 downto 0);		-- External address space
		ext_readdata	: in  std_logic_vector(7 downto 0);
		ext_writedata	: out std_logic_vector(7 downto 0);
		ext_write		: out std_logic;
		ext_irq			: in  std_logic := '0';					-- External interrupt input

		slot_clk		: in  std_logic;	-- slot engine drive clock
		slot_start		: out std_logic;
		slot_done		: in  std_logic;
		keysync_out		: out std_logic;

		reg_address		: in  std_logic_vector(8 downto 1);
		reg_readdata	: out std_logic_vector(17 downto 0);
		reg_writedata	: in  std_logic_vector(17 downto 0);
		reg_write		: in  std_logic;
		wav_address		: in  std_logic_vector(8 downto 0);
		wav_readdata	: out std_logic_vector(7 downto 0)
	);
	end component;
	signal mute_sig			: std_logic;
	signal mastervol_l_sig	: std_logic_vector(14 downto 0);
	signal mastervol_r_sig	: std_logic_vector(14 downto 0);
	signal ext_address_sig	: std_logic_vector(5 downto 0);
	signal ext_rddata_sig	: std_logic_vector(7 downto 0);
	signal ext_wrdata_sig	: std_logic_vector(7 downto 0);
	signal ext_write_sig	: std_logic;
	signal ext_irq_sig		: std_logic;
	signal slot_start_sig	: std_logic;
	signal slot_done_sig	: std_logic;
	signal keysync_sig		: std_logic;
	signal reg_addr_sig		: std_logic_vector(8 downto 1);
	signal reg_rddata_sig	: std_logic_vector(17 downto 0);
	signal reg_wrdata_sig	: std_logic_vector(17 downto 0);
	signal reg_write_sig	: std_logic;
	signal wav_addr_sig		: std_logic_vector(8 downto 0);
	signal wav_rddata_sig	: std_logic_vector(7 downto 0);


	component wsg_extmodule
	generic(
		PCM_CHANNEL_GENNUM	: integer			-- PCM音源実装数(0～8) 
	);
	port(
		clk				: in  std_logic;		-- system clock
		reset			: in  std_logic;		-- async reset
		address			: in  std_logic_vector(5 downto 0);		-- External address space
		readdata		: out std_logic_vector(7 downto 0);
		writedata		: in  std_logic_vector(7 downto 0);
		write			: in  std_logic;
		irq				: out std_logic;
		slot_clk		: in  std_logic;		-- slot engine drive clock
		start_sync		: in  std_logic;		-- slot engine fs sync signal (need one-clock width)
		extpcm_ch		: in  std_logic_vector(3 downto 0);
		extpcm_data		: out std_logic_vector(7 downto 0)
	);
	end component;
	signal ext_pcmch_sig	: std_logic_vector(3 downto 0);
	signal ext_pcmdata_sig	: std_logic_vector(7 downto 0);
	signal start_sync_sig	: std_logic;


	component wsg_slotengine
	generic(
		MAXSLOTNUM		: integer			-- max slot(polyphonic) number
	);
	port(
		clk				: in  std_logic;	-- slotengine drive clock
		reset			: in  std_logic;	-- async reset

		slot_start		: in  std_logic;	-- slot start signal (1clk pulse width)
		slot_done		: out std_logic;	-- engine process done (1clk pulse width)
		start_sync		: out std_logic;	-- slot_start synchronized signal
		key_sync		: in  std_logic;

		reg_address		: out std_logic_vector(8 downto 1);
		reg_readdata	: in  std_logic_vector(17 downto 0);
		reg_writedata	: out std_logic_vector(17 downto 0);
		reg_write		: out std_logic;
		wav_address		: out std_logic_vector(8 downto 0);
		wav_readdata	: in  std_logic_vector(7 downto 0);
		extpcm_ch		: out std_logic_vector(3 downto 0);
		extpcm_data		: in  std_logic_vector(7 downto 0) := (others=>'0');

		pcmdata_l		: out std_logic_vector(15 downto 0);
		pcmdata_r		: out std_logic_vector(15 downto 0)
	);
	end component;
	signal pcmdata_l_sig	: std_logic_vector(15 downto 0);
	signal pcmdata_r_sig	: std_logic_vector(15 downto 0);


	component wsg_audout
	generic(
		DSDAC_PCMBITWIDTH	: integer := 12		-- 1bitDSDAC valid bit width
	);
	port(
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
	end component;


begin

--==== タイミング信号生成 ===========================================

	-- オーディオクロック系リセット信号を生成 

	audio_clk_sig   <= audio_clk;
	audio_reset_sig <= audio_reset_reg;

	process (audio_clk_sig) begin
		if rising_edge(audio_clk_sig) then
			audio_reset_reg <= csi_global_reset;
		end if;
	end process;


	-- fsタイミング信号を生成 

	process (audio_clk_sig, audio_reset_sig) begin
		if (audio_reset_sig = '1') then
			divcount <= 0;

		elsif rising_edge(audio_clk_sig) then
			if (divcount = CLOCKDIV) then
				divcount <= 0;
			else
				divcount <= divcount + 1;
			end if;

		end if;
	end process;

	fs128_timing_sig <= '1' when (divcount = 0) else '0';


--==== レジスタおよびバスインターフェース ===========================

	U_BUSIF : wsg_businterface
	generic map (
		WAVETABLE_INIT_FILE	=> WAVETABLE_INIT_FILE
	)
	port map (
		clk				=> avs_s1_clk,
		reset			=> csi_global_reset,
		async_fs_in		=> async_fs_sig,
		mute_out		=> mute_sig,
		mastervol_l		=> mastervol_l_sig,
		mastervol_r		=> mastervol_r_sig,
		inkey_scko		=> kb_scko,
		inkey_load_n	=> kb_load_n,
		inkey_sdin		=> kb_sdin,

		address			=> (avs_s1_address & '0'),
		readdata		=> avs_s1_readdata,
		read			=> avs_s1_read,
		writedata		=> avs_s1_writedata,
		write			=> avs_s1_write,
		byteenable		=> avs_s1_byteenable,
		irq				=> avs_s1_irq,

		ext_address		=> ext_address_sig,
		ext_readdata	=> ext_rddata_sig,
		ext_writedata	=> ext_wrdata_sig,
		ext_write		=> ext_write_sig,
		ext_irq			=> ext_irq_sig,

		slot_clk		=> audio_clk_sig,
		slot_start		=> slot_start_sig,
		slot_done		=> slot_done_sig,
		keysync_out		=> keysync_sig,

		reg_address		=> reg_addr_sig,
		reg_readdata	=> reg_rddata_sig,
		reg_writedata	=> reg_wrdata_sig,
		reg_write		=> reg_write_sig,
		wav_address		=> wav_addr_sig,
		wav_readdata	=> wav_rddata_sig
	);


--==== 拡張音源ユニット（オプション）================================

	U_EXT : wsg_extmodule
	generic map (
		PCM_CHANNEL_GENNUM	=> PCM_CHANNEL_GENNUM
	)
	port map (
		clk				=> avs_s1_clk,
		reset			=> csi_global_reset,

		address			=> ext_address_sig,
		readdata		=> ext_rddata_sig,
		writedata		=> ext_wrdata_sig,
		write			=> ext_write_sig,
		irq				=> ext_irq_sig,

		slot_clk		=> audio_clk_sig,
		start_sync		=> start_sync_sig,
		extpcm_ch		=> ext_pcmch_sig,
		extpcm_data		=> ext_pcmdata_sig
	);


--==== 波形合成エンジン =============================================

	U_SLOT : wsg_slotengine
	generic map (
		MAXSLOTNUM		=> MAXSLOTNUM
	)
	port map (
		clk				=> audio_clk_sig,
		reset			=> audio_reset_sig,

		slot_start		=> slot_start_sig,
		slot_done		=> slot_done_sig,
		start_sync		=> start_sync_sig,
		key_sync		=> keysync_sig,

		reg_address		=> reg_addr_sig,
		reg_readdata	=> reg_rddata_sig,
		reg_writedata	=> reg_wrdata_sig,
		reg_write		=> reg_write_sig,
		wav_address		=> wav_addr_sig,
		wav_readdata	=> wav_rddata_sig,
		extpcm_ch		=> ext_pcmch_sig,
		extpcm_data		=> ext_pcmdata_sig,

		pcmdata_l		=> pcmdata_l_sig,
		pcmdata_r		=> pcmdata_r_sig
	);



--==== オーディオ出力部 =============================================

	U_AUD : wsg_audout
	generic map (
		DSDAC_PCMBITWIDTH	=> 12
	)
	port map (
		reset			=> audio_reset_sig,
		clk				=> audio_clk_sig,
		clk_ena			=> fs128_timing_sig,
		fs_timing		=> async_fs_sig,

		volume_l		=> mastervol_l_sig,
		volume_r		=> mastervol_r_sig,
		pcmdata_l		=> pcmdata_l_sig,
		pcmdata_r		=> pcmdata_r_sig,

		dac_bclk		=> dac_bclk,
		dac_lrck		=> dac_lrck,
		dac_data		=> dac_data,
		aud_l			=> aud_l,
		aud_r			=> aud_r
	);

	mute <= mute_sig;



end RTL;
