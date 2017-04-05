-- ===================================================================
-- TITLE : Loreley-WSG (External sound module)
--
--     DESIGN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2011/06/11 -> 2011/06/11
--            : 2012/06/12 (FIXED)
--     MODIFY : 2016/10/30 CycloneIV/MAX10アップデート 
--
-- ===================================================================
-- *******************************************************************
--    (C) 2011-2016, J-7SYSTEM WORKS LIMITED.  All rights Reserved.
--
-- * This module is a free sourcecode and there is NO WARRANTY.
-- * No restriction on use. You can use, modify and redistribute it
--   for personal, non-profit or commercial products UNDER YOUR
--   RESPONSIBILITY.
-- * Redistributions of source code must retain the above copyright
--   notice.
-- *******************************************************************

--	0	: PCMCH0 FSDIVレジスタ 
--	1	: PCMCH0 FIFOレジスタ(WO) / STATUSレジスタ(RO)
--	2	: PCMCH1 FSDIVレジスタ 
--	3	: PCMCH1 FIFOレジスタ(WO) / STATUSレジスタ(RO)
--	4	: PCMCH2 FSDIVレジスタ 
--	5	: PCMCH2 FIFOレジスタ(WO) / STATUSレジスタ(RO)
--	6	: PCMCH3 FSDIVレジスタ 
--	7	: PCMCH3 FIFOレジスタ(WO) / STATUSレジスタ(RO)
--	8	: PCMCH4 FSDIVレジスタ 
--	9	: PCMCH4 FIFOレジスタ(WO) / STATUSレジスタ(RO)
--	10	: PCMCH5 FSDIVレジスタ 
--	11	: PCMCH5 FIFOレジスタ(WO) / STATUSレジスタ(RO)
--	12	: PCMCH6 FSDIVレジスタ 
--	13	: PCMCH6 FIFOレジスタ(WO) / STATUSレジスタ(RO)
--	14	: PCMCH7 FSDIVレジスタ 
--	15	: PCMCH7 FIFOレジスタ(WO) / STATUSレジスタ(RO)
--	16	: PCMIRQレジスタ (RO)
--	17	: PCMIRQENAレジスタ 
--	18-63: reserved

-- ext ch0  : PCMCH0
-- ext ch1  : PCMCH1
-- ext ch2  : PCMCH2
-- ext ch3  : PCMCH3
-- ext ch4  : PCMCH4
-- ext ch5  : PCMCH5
-- ext ch6  : PCMCH6
-- ext ch7  : PCMCH7
-- ext ch8  : reserved
-- ext ch9  : reserved
-- ext ch10 : reserved
-- ext ch11 : reserved
-- ext ch12 : reserved
-- ext ch13 : reserved
-- ext ch14 : NOISE (ホワイトノイズ / 読み込むたびに違う値を返す)
-- ext ch15 : reserved


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;

entity wsg_extmodule is
	generic(
		PCM_CHANNEL_GENNUM	: integer := 4			-- PCM音源実装数(0～8) 
	);
	port(
		clk				: in  std_logic;		-- system clock
		reset			: in  std_logic;		-- async reset

	--==== External module I/F signal ================================

		address			: in  std_logic_vector(5 downto 0);		-- External address space
		readdata		: out std_logic_vector(7 downto 0);
		writedata		: in  std_logic_vector(7 downto 0);
		write			: in  std_logic;
		irq				: out std_logic;

	--==== Slot engine I/F signal ====================================

		slot_clk		: in  std_logic;		-- slot engine drive clock
		start_sync		: in  std_logic;		-- slot engine fs sync signal (need one-clock width)

		extpcm_ch		: in  std_logic_vector(3 downto 0);
		extpcm_data		: out std_logic_vector(7 downto 0)
	);
end wsg_extmodule;

architecture RTL of wsg_extmodule is

	-- 拡張音源生成パラメータ 
	constant PCM_CHANNEL_MAXNUM		: integer := 8;			-- PCM音源最大数 

	constant LFSR_BITLENGTH			: integer := 17;		-- ノイズ音パラメータ 
	constant LFSR_XORTAP1			: integer := 17;
	constant LFSR_XORTAP2			: integer := 14;


	-- 内部ノードおよびコンポーネント宣言 
	signal slot_clk_sig			: std_logic;
	signal slot_reset_reg		: std_logic;
	signal slot_reset_sig		: std_logic;
	signal readdata_sig			: std_logic_vector(7 downto 0);
	signal readdata_reg			: std_logic_vector(7 downto 0);
	signal pcm_regwrite_sig		: std_logic;

	signal pcm_irq_reg			: std_logic;
	signal pcm_fifoirqena_reg	: std_logic_vector(7 downto 0);
	signal pcm_irqena_sig		: std_logic_vector(7 downto 0);
	signal pcm_irqreaddata_sig	: std_logic_vector(7 downto 0);

	signal lfsrbit_reg			: std_logic_vector(LFSR_BITLENGTH-1 downto 0);
	signal noise_out_sig		: std_logic_vector(7 downto 0);

	signal extpcmmpx_sig		: std_logic_vector(7 downto 0);
	signal extpcmout_reg		: std_logic_vector(7 downto 0);


	component wsg_pcm8
	port(
		clk				: in  std_logic;		-- system clock
		reset			: in  std_logic;		-- async reset
		address			: in  std_logic_vector(0 downto 0);
		readdata		: out std_logic_vector(7 downto 0);
		writedata		: in  std_logic_vector(7 downto 0);
		write			: in  std_logic;
		fifo_irq		: out std_logic;
		slot_clk		: in  std_logic;		-- slot engine drive clock
		start_sync		: in  std_logic;		-- slot engine fs sync signal (need one-clock width)
		pcm_out			: out std_logic_vector(7 downto 0)
	);
	end component;
	type DEF_FIFODATA is array(0 to 7) of std_logic_vector(7 downto 0);
	signal pcm_write_sig		: std_logic_vector(7 downto 0);
	signal pcm_irq_sig			: std_logic_vector(7 downto 0);
	signal pcm_fifoirq_sig		: std_logic_vector(7 downto 0);
	signal pcm_readdata_sig		: DEF_FIFODATA;
	signal pcm_ch_out_sig		: DEF_FIFODATA;

begin


--==== タイミング信号生成 ===========================================

	-- slot_clk系リセット信号を生成 

	process (slot_clk) begin
		if rising_edge(slot_clk) then
			slot_reset_reg <= reset;
		end if;
	end process;

	slot_clk_sig   <= slot_clk;
	slot_reset_sig <= slot_reset_reg;


--==== バスインターフェース =========================================

	-- レジスタ読み出し制御 

	with address(5 downto 1) select readdata_sig <=
		pcm_readdata_sig(0)		when "00000",
		pcm_readdata_sig(1)		when "00001",
		pcm_readdata_sig(2)		when "00010",
		pcm_readdata_sig(3)		when "00011",
		pcm_readdata_sig(4)		when "00100",
		pcm_readdata_sig(5)		when "00101",
		pcm_readdata_sig(6)		when "00110",
		pcm_readdata_sig(7)		when "00111",
		pcm_irqreaddata_sig		when "01000",
		(others=>'X')	when others;

	process (clk) begin
		if rising_edge(clk) then
			readdata_reg <= readdata_sig;
		end if;
	end process;

	readdata <= readdata_reg;


	-- レジスタ書き込み制御 

	pcm_regwrite_sig <= write;


	-- 割り込み信号制御 

	irq  <= pcm_irq_reg;


--==== PCM音源ブロック (PCM8) =======================================

	-- PCM音源割り込み制御ブロック 

	pcm_irqreaddata_sig <= pcm_fifoirq_sig when(address(0 downto 0)="0") else pcm_irqena_sig;

	process (clk,reset) begin
		if (reset = '1') then
			pcm_irq_reg <= '0';
			pcm_fifoirqena_reg <= (others=>'0');

		elsif rising_edge(clk) then
			if (pcm_regwrite_sig = '1') then
				case address is
				when "010001" =>
					pcm_fifoirqena_reg(7 downto 0) <= writedata(7 downto 0);
				when others =>
				end case;
			end if;

			if (pcm_irq_sig /= 0) then
				pcm_irq_reg <= '1';
			else
				pcm_irq_reg <= '0';
			end if;

		end if;
	end process;


	-- PCM音源のインスタンス 

GEN_PCM : if PCM_CHANNEL_GENNUM > 0 generate
	GEN_PCMLOOP : for i in 0 to PCM_CHANNEL_GENNUM-1 generate

		pcm_write_sig(i) <= pcm_regwrite_sig when(address(4 downto 1)=i) else '0';
		pcm_irq_sig(i)   <= pcm_fifoirqena_reg(i) and pcm_fifoirq_sig(i);
		pcm_irqena_sig(i)<= pcm_fifoirqena_reg(i);

		U_PCM8 : wsg_pcm8
		port map (
			clk			=> clk,
			reset		=> reset,
			address		=> address(0 downto 0),
			readdata	=> pcm_readdata_sig(i),
			writedata	=> writedata,
			write		=> pcm_write_sig(i),
			fifo_irq	=> pcm_fifoirq_sig(i),
			slot_clk	=> slot_clk_sig,
			start_sync	=> start_sync,
			pcm_out		=> pcm_ch_out_sig(i)
		);

	end generate;
end generate;
GEN_PCMDUMMYSIG : if PCM_CHANNEL_GENNUM < PCM_CHANNEL_MAXNUM generate
	GEN_DUMMYLOOP : for i in PCM_CHANNEL_GENNUM to PCM_CHANNEL_MAXNUM-1 generate

		pcm_irq_sig(i)     <= '0';				-- 存在しないPCMチャネルからの割り込みはかからない 
		pcm_fifoirq_sig(i) <= '1';				-- 存在しないPCMチャネルは常にEMPTYになる 
		pcm_irqena_sig(i)  <= '0';				-- 存在しないPCMチャネルのIRQENAレジスタは常に'0'を読み出す 
		pcm_write_sig(i)   <= 'X';
		pcm_readdata_sig(i)<= (others=>'X');
		pcm_ch_out_sig(i)  <= (others=>'0');

	end generate;
end generate;



--==== ノイズブロック (LFSR) ========================================

	process (slot_clk_sig, slot_reset_sig) begin
		if (slot_reset_sig = '1') then
			lfsrbit_reg <= (others=>'1');

		elsif rising_edge(slot_clk_sig) then
			lfsrbit_reg <= lfsrbit_reg(LFSR_BITLENGTH-2 downto 0) & (lfsrbit_reg(LFSR_XORTAP1-1) xor lfsrbit_reg(LFSR_XORTAP2-1));

		end if;
	end process;

	noise_out_sig  <= lfsrbit_reg(7 downto 0);



--==== スロットエンジンへの出力 =====================================

	with extpcm_ch select extpcmmpx_sig <=
		pcm_ch_out_sig(0)	when "0000",		-- ext ch0 : pcm0
		pcm_ch_out_sig(1)	when "0001",		-- ext ch1 : pcm1
		pcm_ch_out_sig(2)	when "0010",		-- ext ch2 : pcm2
		pcm_ch_out_sig(3)	when "0011",		-- ext ch3 : pcm3
		pcm_ch_out_sig(4)	when "0100",		-- ext ch4 : pcm4
		pcm_ch_out_sig(5)	when "0101",		-- ext ch5 : pcm5
		pcm_ch_out_sig(6)	when "0110",		-- ext ch6 : pcm6
		pcm_ch_out_sig(7)	when "0111",		-- ext ch7 : pcm7
		noise_out_sig		when "1110",		-- ext ch14: noise
		(others=>'0')		when others;

	process (slot_clk_sig) begin
		if rising_edge(slot_clk_sig) then
			extpcmout_reg <= extpcmmpx_sig;
		end if;
	end process;

	extpcm_data <= extpcmout_reg;



end RTL;
