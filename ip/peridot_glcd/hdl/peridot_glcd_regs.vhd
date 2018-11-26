-- ===================================================================
-- TITLE : PERIDOT-NGS / Component Register file
--
--     DESIGN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2014/05/10 -> 2014/05/12
--     UPDATE : 2018/11/26
--
-- ===================================================================

-- The MIT License (MIT)
-- Copyright (c) 2014,2018 J-7SYSTEM WORKS LIMITED.
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
use IEEE.std_logic_unsigned.all;
use IEEE.std_logic_arith.all;

entity peridot_glcd_regs is
	port(
		clk			: in  std_logic;
		reset		: in  std_logic;

		address		: in  std_logic_vector(1 downto 0);
		read		: in  std_logic;
		readdata	: out std_logic_vector(31 downto 0);
		write		: in  std_logic;
		writedata	: in  std_logic_vector(31 downto 0);
		irq			: out std_logic;

		topaddr		: out std_logic_vector(30 downto 0);
		start		: out std_logic;
		ready		: in  std_logic;

		wrreq		: out std_logic;
		wrack		: in  std_logic;
		regsel		: out std_logic;
		data		: out std_logic_vector(7 downto 0);

		lcd_reset	: out std_logic;
		lcd_select	: out std_logic
	);
end peridot_glcd_regs;

architecture RTL of peridot_glcd_regs is
	signal ready_in_reg		: std_logic_vector(2 downto 0);
	signal dmabegin_sig		: std_logic;
	signal dmaend_sig		: std_logic;

	signal readdata_0_sig	: std_logic_vector(31 downto 0);
	signal readdata_2_sig	: std_logic_vector(31 downto 0);
	signal readdata_3_sig	: std_logic_vector(31 downto 0);
	signal start_reg		: std_logic;
	signal busy_reg			: std_logic;
	signal doneirqena_reg	: std_logic;
	signal doneirq_reg		: std_logic;
	signal fbaddr_reg		: std_logic_vector(30 downto 0);

	signal iowrreq_reg		: std_logic;
	signal lcdrst_reg		: std_logic;
	signal lcdsel_reg		: std_logic;
	signal iors_reg			: std_logic;
	signal iodata_reg		: std_logic_vector(7 downto 0);

begin


--==== コントロールレジスタ ==========================================

	-- レディ信号のエッジ検出＆同期化 

	process (clk, reset) begin
		if (reset = '1') then
			ready_in_reg <= "111";
		elsif rising_edge(clk) then
			ready_in_reg <= ready_in_reg(1 downto 0) & ready;
		end if;
	end process;

	dmabegin_sig <= '1' when(ready_in_reg(2 downto 1) = "10") else '0';		-- DMA開始 
	dmaend_sig   <= '1' when(ready_in_reg(2 downto 1) = "01") else '0';		-- DMA終了 


	-- レジスタリードライト処理 

	readdata_0_sig <= (	31=>iowrreq_reg,		-- reg0 : LCDダイレクトライトレジスタ 
						30=>lcdrst_reg,
						19=>lcdsel_reg,			-- lcdselビットはDMA終了時に自動クリアされる 
						18=>iors_reg,
						7 =>iodata_reg(7),
						6 =>iodata_reg(6),
						5 =>iodata_reg(5),
						4 =>iodata_reg(4),
						3 =>iodata_reg(3),
						2 =>iodata_reg(2),
						1 =>iodata_reg(1),
						0 =>iodata_reg(0),
						others=>'0');

	readdata_2_sig <= (	15=>doneirqena_reg,		-- reg2 : DMAステータスレジスタ 
						14=>doneirq_reg,
						0 =>busy_reg,			-- bit0に1を書き込むとDMAスタート 
						others=>'0');

	readdata_3_sig <= '0' & fbaddr_reg;			-- reg3 : DMAアドレスレジスタ 

	with address select readdata <=
		readdata_0_sig when "00",
		readdata_2_sig when "10",
		readdata_3_sig when "11",
		(others=>'X') when others;

	irq <= doneirq_reg when(doneirqena_reg = '1') else '0';


	-- I/Oダイレクトライトレジスタ 

	wrreq  <= iowrreq_reg;
	regsel <= iors_reg;
	data   <= iodata_reg;

	lcd_reset  <= lcdrst_reg;
	lcd_select <= lcdsel_reg;

	process (clk, reset) begin
		if (reset='1') then
			iowrreq_reg <= '0';
			lcdrst_reg  <= '1';
			lcdsel_reg  <= '0';

		elsif rising_edge(clk) then
			if (iowrreq_reg = '1') then
				if (wrack = '1') then
					iowrreq_reg <= '0';
				end if;

			elsif (dmaend_sig = '1') then
				lcdsel_reg <= '0';

			elsif (address = "00" and write = '1') then
				iowrreq_reg <= writedata(31);
				lcdrst_reg  <= writedata(30);
				lcdsel_reg  <= writedata(19);
				iors_reg    <= writedata(18);
				iodata_reg  <= writedata(7 downto 0);

			end if;

		end if;
	end process;


	-- DMAコントロールレジスタ 

	topaddr <= fbaddr_reg;
	start <= start_reg;

	process (clk, reset) begin
		if (reset='1') then
			start_reg <= '0';
			busy_reg <= '0';
			doneirqena_reg <= '0';
			doneirq_reg <= '0';

		elsif rising_edge(clk) then
			if (busy_reg = '0') then
				if (address = "10" and write = '1' and writedata(0) = '1') then
					start_reg <= '1';
					busy_reg <= '1';
				end if;
			else
				if (dmabegin_sig = '1') then
					start_reg <= '0';
				end if;
				if (dmaend_sig = '1') then
					busy_reg <= '0';
				end if;
			end if;

			if (dmaend_sig = '1') then
				doneirq_reg <= '1';
			elsif (address = "10" and write = '1' and writedata(14) = '0') then
				doneirq_reg <= '0';
			end if;

			if (write = '1') then
				case address is
				when "10" =>
					doneirqena_reg <= writedata(15);

				when "11" =>
					fbaddr_reg <= writedata(30 downto 2) & "00";

				when others =>
				end case;
			end if;

		end if;
	end process;



end RTL;
