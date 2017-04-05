-- ===================================================================
-- TITLE : Loreley-WSG Slot Engine
--
--     DESIGN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2009/01/01 -> 2009/01/04
--            : 2009/01/14 (FIXED)
--     MODIFY : 2011/06/10 PCMポートを分離 
--            : 2011/06/25 パン設定を変更 → 元に戻す(2012/06/05)
--            : 2012/05/29 FREQレジスタ仕様を変更 
--            : 2012/06/05 位相変調を追加 
--
--     MODIFY : 2016/10/25 CycloneIV/MAX10用アップデート 
--
-- ===================================================================
-- *******************************************************************
--    (C) 2009-2016, J-7SYSTEM WORKS LIMITED.  All rights Reserved.
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
use IEEE.std_logic_unsigned.all;
use IEEE.std_logic_arith.all;

entity wsg_slotengine is
	generic(
--		MAXSLOTNUM		: integer := 64		-- max slot(polyphonic) number
		MAXSLOTNUM		: integer := 8		-- for test
	);
	port(
		test_freq_oct	: out std_logic_vector(2 downto 0);
		test_freq_step	: out std_logic_vector(8 downto 0);
		test_playaddr_zf: out std_logic;
		test_addrstep	: out std_logic_vector(16 downto 0);
		test_tableaddr	: out std_logic_vector(17 downto 0);
		test_nextaddr	: out std_logic_vector(17 downto 0);
		test_mul_q		: out std_logic_vector(15 downto 0);


		clk				: in  std_logic;	-- slotengine drive clock
		reset			: in  std_logic;	-- async reset

	--==== System register I/F signal ================================

		slot_start		: in  std_logic;	-- Async slot start signal (need rise edge detect)
		slot_done		: out std_logic;	-- engine process done
		start_sync		: out std_logic;	-- slot_start synchronized signal (a one-clock width)

		key_sync		: in  std_logic :='1';

	--==== RegisterBUS I/F signal ====================================

		reg_address		: out std_logic_vector(8 downto 1);
		reg_readdata	: in  std_logic_vector(17 downto 0);
		reg_writedata	: out std_logic_vector(17 downto 0);
		reg_write		: out std_logic;

	--==== WaveROM BUS I/F signal ====================================

		wav_address		: out std_logic_vector(8 downto 0);
		wav_readdata	: in  std_logic_vector(7 downto 0);

	--==== External PCM I/F signal ===================================

		extpcm_ch		: out std_logic_vector(3 downto 0);
		extpcm_data		: in  std_logic_vector(7 downto 0) := (others=>'0');

	--==== Wave output I/F signal ====================================

		pcmdata_l		: out std_logic_vector(15 downto 0);
		pcmdata_r		: out std_logic_vector(15 downto 0)
	);
end wsg_slotengine;

architecture RTL of wsg_slotengine is
	type SLOT_STATE is (IDLE, REGREAD0,REGREAD1,REGREAD2,REGREAD3,
							WAVEREAD,REGWRITE,WAVEADD0,WAVEADD1);
	signal state : SLOT_STATE;
	signal slotcount_reg	: std_logic_vector(5 downto 0);
	signal keysync_reg		: std_logic;

	signal start0_reg		: std_logic;
	signal start1_reg		: std_logic;
	signal start_in_reg		: std_logic;
	signal start_sig		: std_logic;

	signal reg_vol_sig		: std_logic_vector(7 downto 0);
	signal reg_play_sig		: std_logic;
	signal reg_pan_sig		: std_logic_vector(6 downto 0);
	signal reg_bank_sig		: std_logic_vector(3 downto 0);
	signal reg_freq_sig		: std_logic_vector(11 downto 0);
	signal reg_playaddr_sig	: std_logic_vector(17 downto 0);

	signal vol_reg			: std_logic_vector(7 downto 0);
	signal play_reg			: std_logic;
	signal pan_reg			: std_logic_vector(6 downto 0);
	signal bank_reg			: std_logic_vector(3 downto 0);
	signal freq_reg			: std_logic_vector(11 downto 0);
	signal pcmsel_reg		: std_logic;
	signal playaddr_reg		: std_logic_vector(17 downto 0);

	signal freq_zf_sig		: std_logic;
	signal freq_oct_sig		: std_logic_vector(2 downto 0);
	signal freq_step_sig	: std_logic_vector(8 downto 0);
	signal playaddr_zf_sig	: std_logic;
	signal nextaddr_sig		: std_logic_vector(17 downto 0);
	signal addrstep_sig		: std_logic_vector(16 downto 0);
	signal tableaddr_sig	: std_logic_vector(17 downto 0);

	signal phaseoffs_sig	: std_logic_vector(15 downto 0);
	signal phaseoffs_reg	: std_logic_vector(15 downto 0);
	signal pan_zf_sig		: std_logic;
	signal pan_l_sig		: std_logic_vector(7 downto 0);
	signal pan_r_sig		: std_logic_vector(7 downto 0);
	signal vol_l_reg		: std_logic_vector(7 downto 0);
	signal vol_r_reg		: std_logic_vector(7 downto 0);
	signal voldata_sig		: std_logic_vector(7 downto 0);
	signal wavedata_sig		: std_logic_vector(21 downto 0);
	signal waveadd_l_reg	: std_logic_vector(21 downto 0);
	signal waveadd_r_reg	: std_logic_vector(21 downto 0);

	signal wavesat_l_sig	: std_logic_vector(15 downto 0);
	signal wavesat_r_sig	: std_logic_vector(15 downto 0);
	signal pcmdata_l_reg	: std_logic_vector(15 downto 0);
	signal pcmdata_r_reg	: std_logic_vector(15 downto 0);


	component wsg_mul_s9x9
	PORT
	(
		dataa		: IN STD_LOGIC_VECTOR (8 DOWNTO 0);
		datab		: IN STD_LOGIC_VECTOR (8 DOWNTO 0);
		result		: OUT STD_LOGIC_VECTOR (17 DOWNTO 0)
	);
	end component;
	signal mul_a_reg		: std_logic_vector(7 downto 0);
	signal mul_b_reg		: std_logic_vector(7 downto 0);
	signal mul_q_sig		: std_logic_vector(17 downto 0);

begin

	test_freq_oct	<= freq_oct_sig;
	test_freq_step	<= freq_step_sig;
	test_playaddr_zf<= playaddr_zf_sig;
	test_addrstep	<= addrstep_sig;
	test_tableaddr	<= tableaddr_sig;
	test_nextaddr	<= nextaddr_sig;
	test_mul_q		<= mul_q_sig(15 downto 0);


--==== スロット処理ステートマシン ====================================

	-- スロットエンジンキック信号の同期化 (slot_startの立ち上がりエッジを検出)

	start_sig <= '1' when(start0_reg = '1' and start1_reg = '0') else '0';

	start_sync <= start_sig;	-- 外部モジュール同期用 

	process (clk, reset) begin
		if (reset = '1') then
			start0_reg   <= '0';
			start1_reg   <= '0';
			start_in_reg <= '0';

		elsif rising_edge(clk) then
			start1_reg   <= start0_reg;
			start0_reg   <= start_in_reg;
			start_in_reg <= slot_start;

		end if;
	end process;

	-- スロットエンジン終了信号を生成 

	slot_done <= '1' when(state = IDLE) else '0';


	-- 波形合成エンジン 

	process (clk, reset) begin
		if (reset = '1') then
			state <= IDLE;
			pcmdata_l_reg <= (others=>'0');
			pcmdata_r_reg <= (others=>'0');
			waveadd_l_reg <= (others=>'0');
			waveadd_r_reg <= (others=>'0');

		elsif rising_edge(clk) then

		-- スロット処理ステートを起動 --------
			case state is
			when IDLE =>
				if (start_sig = '1') then
					state <= REGREAD0;
					keysync_reg   <= key_sync;
					slotcount_reg <= (others=>'0');
					pcmdata_l_reg <= wavesat_l_sig;
					pcmdata_r_reg <= wavesat_r_sig;
					waveadd_l_reg <= (others=>'0');
					waveadd_r_reg <= (others=>'0');
					mul_a_reg     <= (others=>'0');
					mul_b_reg     <= (others=>'0');
				else 
					state <= IDLE;
				end if;

		-- スロット毎に波形を合成 --------
		
			-- STATUSレジスタのロードリクエスト 
			when REGREAD0 =>
				state <= REGREAD1;


			-- FREQレジスタのロードリクエスト 
			when REGREAD1 =>
				state <= REGREAD2;

				vol_reg  <= reg_vol_sig;
				play_reg <= reg_play_sig;
				pan_reg  <= reg_pan_sig;

				phaseoffs_reg <= phaseoffs_sig;		-- 前段からの位相変調値 


			-- WORKレジスタのロードリクエスト 
			when REGREAD2 =>
				state <= REGREAD3;

				bank_reg <= reg_bank_sig;
				freq_reg <= reg_freq_sig;

				mul_a_reg <= "0" & pan_l_sig(6 downto 0);

				if (pan_zf_sig = '0') then
					mul_b_reg <= vol_reg;
				else
					mul_b_reg <= (others=>'0');
				end if;


			-- アドレスよびスロット動作状態確定 
			when REGREAD3 =>
				state <= WAVEREAD;

				playaddr_reg <= reg_playaddr_sig;

				pcmsel_reg <= freq_zf_sig;			-- FREQレジスタ=0ならPCMチャネルを再生 

				vol_l_reg <= voldata_sig;
				mul_a_reg <= "0" & pan_r_sig(6 downto 0);


			-- WaveTableのリードリクエスト 
			when WAVEREAD =>
				state <= REGWRITE;

				if (keysync_reg = '0') then
					play_reg <= not playaddr_zf_sig;	-- キーSYNCが無効なら現状の動作を継続 
				end if;

				playaddr_reg <= playaddr_reg + ("000" & addrstep_sig(16 downto 2));

				vol_r_reg <= voldata_sig;


			-- WORKレジスタのライトバック 
			when REGWRITE =>
				state <= WAVEADD0;

				if (play_reg = '1') then
					if (pcmsel_reg = '1') then		-- PCM再生設定の場合 
						mul_a_reg <= extpcm_data;
					else
						mul_a_reg <= wav_readdata;
					end if;
				else
					mul_a_reg <= (others=>'0');
				end if;
				mul_b_reg <= vol_l_reg;


			-- 左チャネル波形出力加算 
			when WAVEADD0 =>
				state <= WAVEADD1;

				mul_b_reg <= vol_r_reg;
				waveadd_l_reg <= waveadd_l_reg + wavedata_sig;


			-- 右チャネル波形出力加算 
			when WAVEADD1 =>
				if (slotcount_reg = (MAXSLOTNUM-1)) then
					state <= IDLE;
				else
					state <= REGREAD0;
				end if;
				slotcount_reg <= slotcount_reg + 1;

				if (pan_zf_sig = '0') then
					mul_b_reg <= (others=>'0');		-- PAN設定が有効の場合は後段の位相変調量を0にする 
				else
					mul_b_reg <= vol_reg;
				end if;
				waveadd_r_reg <= waveadd_r_reg + wavedata_sig;


			when others =>
				state <= IDLE;
			end case;

		end if;
	end process;


--==== レジスタバス入出力 ============================================

	-- ロードレジスタビット構成 --

	reg_vol_sig  <= reg_readdata(16 downto 9);
	reg_play_sig <= reg_readdata(7);
	reg_pan_sig  <= reg_readdata(6 downto 0);
	reg_bank_sig <= reg_readdata(16 downto 13);
	reg_freq_sig <= reg_readdata(12 downto 9) & reg_readdata(7 downto 0);
	reg_playaddr_sig <= reg_readdata(17 downto 0);


	-- FREQレジスタ設定→ADDRSTEP値変換 --

	freq_zf_sig   <= '1' when(freq_reg = 0) else '0';
	freq_oct_sig  <= freq_reg(11 downto 9);
	freq_step_sig <= freq_reg(8 downto 0);

	with freq_oct_sig select addrstep_sig <=
		"1" & freq_step_sig & "0000000"	when "111",
		"01" & freq_step_sig & "000000"	when "110",
		"001" & freq_step_sig & "00000"	when "101",
		"0001" & freq_step_sig & "0000"	when "100",
		"00001" & freq_step_sig & "000"	when "011",
		"000001" & freq_step_sig & "00"	when "010",
		"0000001" & freq_step_sig & "0"	when "001",
		"00000001" & freq_step_sig		when others;


	-- ライトバックレジスタビット構成 --

	playaddr_zf_sig <= '1' when(playaddr_reg = 0) else '0';
	nextaddr_sig <= (0=>'1',others=>'0') when(playaddr_zf_sig = '1') else playaddr_reg;

	reg_writedata <= nextaddr_sig when(play_reg = '1') else (others=>'0');
	reg_write <= '1' when(state = REGWRITE) else '0';


	-- アドレス出力 --

	reg_address <=	("1" & slotcount_reg & "0") when(state = REGREAD0) else
					("1" & slotcount_reg & "1") when(state = REGREAD1) else
					("01" & slotcount_reg);

	tableaddr_sig <= playaddr_reg + (phaseoffs_reg & "00");
	wav_address   <= bank_reg & tableaddr_sig(17 downto 13);

	extpcm_ch <= bank_reg;


--==== 波形・音量値乗算 ==============================================

	phaseoffs_sig <= mul_q_sig(15 downto 0);

	pan_zf_sig <= '1' when(pan_reg = 0) else '0';
	pan_l_sig  <= 127 - ("0" & pan_reg);
	pan_r_sig  <= ("0" & pan_reg) - 1;

	voldata_sig <= mul_q_sig(14 downto 7);

	wsg_mul_s9x9_inst : wsg_mul_s9x9
	PORT MAP (
		dataa	 => (mul_a_reg(7) & mul_a_reg),
		datab	 => ('0' & mul_b_reg),
		result	 => mul_q_sig
	);

	wavedata_sig(21 downto 15)<= (others=>mul_q_sig(15));
	wavedata_sig(14 downto 0) <= mul_q_sig(14 downto 0);

	wavesat_l_sig <= waveadd_l_reg(15 downto 0) when(waveadd_l_reg(21 downto 15) = "1111111" or waveadd_l_reg(21 downto 15) = "0000000") else
					(15=>waveadd_l_reg(21),others=>(not waveadd_l_reg(21)));
	wavesat_r_sig <= waveadd_r_reg(15 downto 0) when(waveadd_r_reg(21 downto 15) = "1111111" or waveadd_r_reg(21 downto 15) = "0000000") else
					(15=>waveadd_r_reg(21),others=>(not waveadd_r_reg(21)));

	pcmdata_l <= pcmdata_l_reg;
	pcmdata_r <= pcmdata_r_reg;



end RTL;
