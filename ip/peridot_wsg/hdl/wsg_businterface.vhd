-- ===================================================================
-- TITLE : PERIDOT-NGS / Loreley-WSG BUS Interface
--
--     DESIGN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2009/01/01 -> 2009/01/09
--            : 2009/01/15 (FIXED)
--
--     MODIFY : 2009/06/12 外部音源ポートを追加 
--            : 2009/06/25 タイマBの分解能を変更(2ms→1ms) 
--            : 2009/06/27 拡張音源ポートのバイトアクセス不具合を修正 
--            : 2011/09/13 マスターボリュームレジスタを追加 
--
--     MODIFY : 2016/10/25 CycloneIV/MAX10用アップデート 
--            : 2017/04/06 スロットレジスタ、波形テーブルのインスタンス変更 
--            : 2017/05/08 システムレジスタアドレス変更、アクセス不具合を修正、キー入力追加 
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

-- リードは３クロック幅（アドレス確定後２クロックwait）以上 
-- ライトは１クロック幅 
-- ウェイト・ホールドなし 
-- 拡張音源モジュールも同様のアクセスで行えること 


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use IEEE.std_logic_arith.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity wsg_businterface is
	generic(
		WAVETABLE_INIT_FILE	: string := "UNUSED"
--		WAVETABLE_INIT_FILE	: string := "wsg_wavetable.mif"
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

	--==== AvalonMM Slave signal =====================================

		address			: in  std_logic_vector(9 downto 0);
		readdata		: out std_logic_vector(15 downto 0);
		read			: in  std_logic;
		writedata		: in  std_logic_vector(15 downto 0);
		write			: in  std_logic;
		byteenable		: in  std_logic_vector(1 downto 0);
		irq				: out std_logic;

	--==== External module signal ====================================

		ext_address		: out std_logic_vector(5 downto 0);		-- External address space
		ext_readdata	: in  std_logic_vector(7 downto 0);
		ext_writedata	: out std_logic_vector(7 downto 0);
		ext_write		: out std_logic;
		ext_irq			: in  std_logic := '0';					-- External interrupt input

	--==== Slotengine signal =========================================

		slot_start		: out std_logic;	-- engine process start ('clk' domain)
		slot_done		: in  std_logic;	-- Async slot done signal (need rise edge detect)
		keysync_out		: out std_logic;

		slot_clk		: in  std_logic;	-- slot engine drive clock

		reg_address		: in  std_logic_vector(8 downto 1);
		reg_readdata	: out std_logic_vector(17 downto 0);
		reg_writedata	: in  std_logic_vector(17 downto 0);
		reg_write		: in  std_logic;

		wav_address		: in  std_logic_vector(8 downto 0);
		wav_readdata	: out std_logic_vector(7 downto 0)
	);
end wsg_businterface;

architecture RTL of wsg_businterface is
	signal extfs0_reg		: std_logic;
	signal extfs1_reg		: std_logic;
	signal extfs_in_reg		: std_logic;
	signal fssync_sig		: std_logic;

	signal start_reg		: std_logic;
	signal done_in_reg		: std_logic;
	signal done0_reg		: std_logic;
	signal done1_reg		: std_logic;
	signal slotack_sig		: std_logic;

	signal sys_rddata_sig	: std_logic_vector(15 downto 0);
	signal sys_setup_sig	: std_logic_vector(15 downto 0);
	signal sys_timer_sig	: std_logic_vector(15 downto 0);
	signal sys_wrena_sig	: std_logic;

	signal mute_reg			: std_logic;
	signal keysync_reg		: std_logic;
	signal keysync_fs_reg	: std_logic;
	signal timairq_reg		: std_logic;
	signal timaovf_reg		: std_logic;
	signal timastart_reg	: std_logic;
	signal timaref_reg		: std_logic_vector(7 downto 0);
	signal timacount_reg	: std_logic_vector(7 downto 0);
	signal timatimeup_sig	: std_logic;
	signal timbirq_reg		: std_logic;
	signal timbovf_reg		: std_logic;
	signal timbstart_reg	: std_logic;
	signal timbref_reg		: std_logic_vector(7 downto 0);
	signal timbref_sig		: std_logic_vector(12 downto 0);
	signal timbcount_reg	: std_logic_vector(12 downto 0);
	signal timbtimeup_sig	: std_logic;
	signal seqcount_reg		: std_logic_vector(15 downto 0);

	signal inkeycount_reg	: std_logic_vector(5 downto 0);
	signal inkeyshift_reg	: std_logic_vector(31 downto 0);
	signal inkey_reg		: std_logic_vector(31 downto 0);

	signal mvol_l_reg		: std_logic_vector(14 downto 0);
	signal mvol_r_reg		: std_logic_vector(14 downto 0);
	signal readdata_reg		: std_logic_vector(15 downto 0);
	signal reg_rddata_sig	: std_logic_vector(17 downto 0);
	signal reg_wrdata_sig	: std_logic_vector(17 downto 0);
	signal reg_wrena_sig	: std_logic;
	signal wav_rddata_sig	: std_logic_vector(15 downto 0);
	signal wav_wrena_sig	: std_logic;

begin


--==== AvalonBUS 入出力 ==============================================

	-- 読み出しレジスタ選択 
		--	00_0XXX_XXXX : システムレジスタ(128バイト) 
		--	00_1XXX_XXXX : 拡張音源レジスタ(128バイト、※ただしデータは下位8bitのみのマッピング) 
		--	01_XXXX_XXXX : スロットレジスタ(256バイト)
		--	1X_XXXX_XXXX : 波形テーブルメモリ(512バイト)

	readdata <= ("00000000" & ext_readdata) when (address(9 downto 7)="001") else readdata_reg;

	process (clk) begin
		if rising_edge(clk) then

			if (address(9) = '1') then
				readdata_reg <= wav_rddata_sig;
			else
				if (address(8) = '0') then
					readdata_reg <= sys_rddata_sig;
				else
					readdata_reg( 7 downto 0) <= reg_rddata_sig( 7 downto 0);
					readdata_reg(15 downto 8) <= reg_rddata_sig(16 downto 9);
				end if;
			end if;

		end if;
	end process;


	-- 割り込み信号出力 

	irq <= (timaovf_reg and timairq_reg) or (timbovf_reg and timbirq_reg) or ext_irq;


	-- 書き込みレジスタ選択 

	sys_wrena_sig <= write when (address(9 downto 7)="000") else '0';
	reg_wrena_sig <= write when (address(9 downto 8)="01") else '0';
	wav_wrena_sig <= write when (address(9)='1') else '0';


	-- 拡張音源バス出力

	ext_address   <= address(6 downto 1);
	ext_writedata <= writedata(7 downto 0);
	ext_write     <= write when (address(9 downto 7)="001" and byteenable(0)='1') else '0';


	-- スロットレジスタのインスタンス 

	reg_wrdata_sig( 8 downto 0) <= '0' & writedata( 7 downto 0);
	reg_wrdata_sig(17 downto 9) <= '0' & writedata(15 downto 8);

	wsg_slotregister_inst : altsyncram
	generic map (
		lpm_type => "altsyncram",
		operation_mode => "BIDIR_DUAL_PORT",
		byte_size => 9,
		numwords_a => 256,
		widthad_a => 8,
		width_a => 18,
		width_byteena_a => 2,
		numwords_b => 256,
		widthad_b => 8,
		width_b => 18,
		width_byteena_b => 1,
		address_reg_b => "CLOCK1",
		indata_reg_b => "CLOCK1",
		wrcontrol_wraddress_reg_b => "CLOCK1",
		clock_enable_input_a => "BYPASS",
		clock_enable_input_b => "BYPASS",
		clock_enable_output_a => "BYPASS",
		clock_enable_output_b => "BYPASS",
		outdata_aclr_a => "NONE",
		outdata_aclr_b => "NONE",
		outdata_reg_a => "UNREGISTERED",
		outdata_reg_b => "UNREGISTERED",
		read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
		read_during_write_mode_port_b => "NEW_DATA_WITH_NBE_READ",
		power_up_uninitialized => "FALSE"
	)
	port map (
		clock0		 => clk,
		address_a	 => address(8 downto 1),
		q_a			 => reg_rddata_sig,
		data_a		 => reg_wrdata_sig,
		wren_a		 => reg_wrena_sig,
		byteena_a	 => byteenable,

		clock1		 => slot_clk,
		address_b	 => reg_address,
		q_b			 => reg_readdata,
		data_b		 => reg_writedata,
		wren_b		 => reg_write
	);


	-- 波形テーブルのインスタンス 

	wsg_wavetable_inst : altsyncram
	generic map (
		lpm_type => "altsyncram",
		operation_mode => "BIDIR_DUAL_PORT",
		byte_size => 8,
		numwords_a => 256,
		widthad_a => 8,
		width_a => 16,
		width_byteena_a => 2,
		numwords_b => 512,
		widthad_b => 9,
		width_b => 8,
		width_byteena_b => 1,
		address_reg_b => "CLOCK1",
		indata_reg_b => "CLOCK1",
		wrcontrol_wraddress_reg_b => "CLOCK1",
		clock_enable_input_a => "BYPASS",
		clock_enable_input_b => "BYPASS",
		clock_enable_output_a => "BYPASS",
		clock_enable_output_b => "BYPASS",
		outdata_aclr_a => "NONE",
		outdata_aclr_b => "NONE",
		outdata_reg_a => "UNREGISTERED",
		outdata_reg_b => "UNREGISTERED",
		read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
		read_during_write_mode_port_b => "NEW_DATA_WITH_NBE_READ",
		init_file => WAVETABLE_INIT_FILE,
		init_file_layout => "PORT_B",
		power_up_uninitialized => "FALSE"
	)
	port map (
		clock0		 => clk,
		address_a	 => address(8 downto 1),
		q_a			 => wav_rddata_sig,
		data_a		 => writedata,
		wren_a		 => wav_wrena_sig,
		byteena_a	 => byteenable,

		clock1		 => slot_clk,
		address_b	 => wav_address,
		q_b			 => wav_readdata,
		data_b		 => (others=>'0'),
		wren_b		 => '0'
	);


	-- システムレジスタ読み出し選択 

	with address(3 downto 1) select sys_rddata_sig <=
		sys_setup_sig			when "000",
		sys_timer_sig			when "001",
		seqcount_reg			when "010",
		'0' & mvol_l_reg		when "100",
		'0' & mvol_r_reg		when "101",
		inkey_reg(15 downto 0)	when "110",
		inkey_reg(31 downto 16)	when "111",
		(others=>'X')			when others;

	sys_setup_sig(15) <= keysync_reg;
	sys_setup_sig(14 downto 8) <= (others=>'0');
	sys_setup_sig(7)  <= timbirq_reg;
	sys_setup_sig(6)  <= timbovf_reg;
	sys_setup_sig(5)  <= timbstart_reg;
	sys_setup_sig(4)  <= timairq_reg;
	sys_setup_sig(3)  <= timaovf_reg;
	sys_setup_sig(2)  <= timastart_reg;
	sys_setup_sig(1)  <= '0';
	sys_setup_sig(0)  <= mute_reg;

	sys_timer_sig <= timbref_reg & timaref_reg;


	-- システムレジスタ書き込み 

	process (clk, reset) begin
		if (reset = '1') then
			keysync_reg    <= '0';
			keysync_fs_reg <= '0';
			mute_reg       <= '1';
			timairq_reg    <= '0';
			timaovf_reg    <= '0';
			timastart_reg  <= '0';
			timaref_reg    <= (others=>'0');
			timbirq_reg    <= '0';
			timbovf_reg    <= '0';
			timbstart_reg  <= '0';
			timbref_reg    <= (others=>'0');
			seqcount_reg   <= (others=>'0');
			mvol_l_reg     <= (others=>'0');
			mvol_r_reg     <= (others=>'0');

		elsif rising_edge(clk) then

			-- keysyncビットの処理 
			if (fssync_sig = '1') then
				keysync_fs_reg <= keysync_reg;
			end if;

			if (sys_wrena_sig = '1' and address(3 downto 1) = "000" and byteenable(1) = '1') then
				keysync_reg <= keysync_reg or writedata(15);
			elsif (slotack_sig = '1' and keysync_fs_reg = keysync_reg) then
				keysync_reg <= '0';
			end if;

			-- fsインターバルタイマとオーバーフロービットの処理 
			if (sys_wrena_sig = '1' and address(3 downto 1) = "000" and byteenable(0) = '1') then
				timaovf_reg <= timaovf_reg and writedata(3);
			elsif (sys_wrena_sig = '1' and address(3 downto 1) = "010") then
				timaovf_reg <= '0';
			elsif (fssync_sig = '1' and timacount_reg = timaref_reg and seqcount_reg = 0) then
				timaovf_reg <= '1';
			end if;

			if (sys_wrena_sig = '1' and address(3 downto 1) = "000" and byteenable(0) = '1') then
				timbovf_reg <= timbovf_reg and writedata(6);
			elsif (fssync_sig = '1' and timbcount_reg = timbref_sig) then
				timbovf_reg <= '1';
			end if;

			-- シーケンスカウンタの処理 
			if (sys_wrena_sig = '1' and address(3 downto 1) = "010") then
				if (byteenable(1) = '1') then
					seqcount_reg(15 downto 8) <= writedata(15 downto 8);
				end if;
				if (byteenable(0) = '1') then
					seqcount_reg(7 downto 0) <= writedata(7 downto 0);
				end if;
			elsif (fssync_sig = '1' and timacount_reg = timaref_reg and seqcount_reg /= 0) then
				seqcount_reg <= seqcount_reg - 1;
			end if;

			-- それ以外のレジスタの処理 
			if (sys_wrena_sig = '1') then
				case address(3 downto 1) is
				when "000" =>
					if (byteenable(0) = '1') then
						timbirq_reg   <= writedata(7);
						timbstart_reg <= writedata(5);
						timairq_reg   <= writedata(4);
						timastart_reg <= writedata(2);
						mute_reg      <= writedata(0);
					end if;

				when "001" =>
					if (byteenable(1) = '1') then
						timbref_reg <= writedata(15 downto 8);
					end if;
					if (byteenable(0) = '1') then
						timaref_reg <= writedata(7 downto 0);
					end if;

				when "100" =>
					if (byteenable(1) = '1') then
						mvol_l_reg(14 downto 8) <= writedata(14 downto 8);
					end if;
					if (byteenable(0) = '1') then
						mvol_l_reg(7 downto 0)  <= writedata(7 downto 0);
					end if;

				when "101" =>
					if (byteenable(1) = '1') then
						mvol_r_reg(14 downto 8) <= writedata(14 downto 8);
					end if;
					if (byteenable(0) = '1') then
						mvol_r_reg(7 downto 0)  <= writedata(7 downto 0);
					end if;

				when others =>
				end case;
			end if;

		end if;
	end process;


	-- システムレジスタ出力 

	mute_out    <= mute_reg;
	keysync_out <= keysync_reg;
	mastervol_l <= mvol_l_reg;
	mastervol_r <= mvol_r_reg;



--==== fs同期信号生成ブロック ========================================

	-- スロットエンジンキック信号を生成 

	slot_start <= start_reg;

	process (clk, reset) begin
		if (reset = '1') then
			start_reg <= '0';

		elsif rising_edge(clk) then
			if (fssync_sig = '1') then
				start_reg <= '1';
			elsif (done0_reg = '0' and done1_reg = '1') then	-- slot_doneの立下りでstartを解除 
				start_reg <= '0';
			end if;

		end if;
	end process;


	-- スロットエンジン終了信号の同期化 (slot_doneの立ち上がりエッジを検出)

	slotack_sig <= '1' when(done0_reg = '1' and done1_reg = '0') else '0';

	process (clk, reset) begin
		if (reset = '1') then
			done0_reg   <= '0';
			done1_reg   <= '0';
			done_in_reg <= '0';

		elsif rising_edge(clk) then
			done1_reg   <= done0_reg;
			done0_reg   <= done_in_reg;
			done_in_reg <= slot_done;

		end if;
	end process;


	-- fs信号の同期化 (async_fsの立ち上がりエッジを検出)

	fssync_sig <= '1' when(extfs0_reg = '1' and extfs1_reg = '0') else '0';

	process (clk, reset) begin
		if (reset = '1') then
			extfs0_reg   <= '0';
			extfs1_reg   <= '0';
			extfs_in_reg <= '0';

		elsif rising_edge(clk) then
			extfs1_reg   <= extfs0_reg;
			extfs0_reg   <= extfs_in_reg;
			extfs_in_reg <= async_fs_in;

		end if;
	end process;


	-- fsインターバルタイマ 

	timbref_sig <= timbref_reg & "00000";	-- タイマBはfs/32でカウントする 

	process (clk, reset) begin
		if (reset = '1') then
			timacount_reg <= (others=>'0');
			timbcount_reg <= (others=>'0');

		elsif rising_edge(clk) then

			-- タイマＡのカウント処理 
			if (timastart_reg = '1') then
				if (fssync_sig = '1') then
					if (timacount_reg = timaref_reg) then
						timacount_reg <= (others=>'0');
					else
						timacount_reg <= timacount_reg + 1;
					end if;
				end if;
			else
				timacount_reg <= (others=>'0');
			end if;

			-- タイマＢのカウント処理 
			if (timbstart_reg = '1') then
				if (fssync_sig = '1') then
					if (timbcount_reg = timbref_sig) then
						timbcount_reg <= (others=>'0');
					else
						timbcount_reg <= timbcount_reg + 1;
					end if;
				end if;
			else
				timbcount_reg <= (others=>'0');
			end if;

		end if;
	end process;


	-- 外部キー入力シフトレジスタ 

	process (clk, reset) begin
		if (reset = '1') then
			inkeycount_reg <= (others=>'0');

		elsif rising_edge(clk) then
			if (fssync_sig = '1') then
				inkeycount_reg <= inkeycount_reg + 1;

				if (inkeycount_reg = "000000") then
					inkey_reg <= inkeyshift_reg;
				elsif (inkeycount_reg(0) = '1') then
					inkeyshift_reg <= inkey_sdin & inkeyshift_reg(31 downto 1);
				end if;

			end if;
		end if;
	end process;

	inkey_scko   <= inkeycount_reg(0);
	inkey_load_n <= '0' when(inkeycount_reg(5 downto 1) = "00000") else '1';



end RTL;
