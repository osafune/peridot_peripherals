-- ===================================================================
-- TITLE : PERIDOT-NGS / ILI9325 LCDC i80-8bit Interface
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

entity peridot_glcd_wrstate is
	generic(
		LCDC_WAITCOUNT_MAX	: integer := 15;
		LCDC_WRSETUP_COUNT	: integer := 4;
		LCDC_WRWIDTH_COUNT	: integer := 8;
		LCDC_WRHOLD_COUNT	: integer := 4
	);
	port(
		clk			: in  std_logic;
		reset		: in  std_logic;

		wrreq		: in  std_logic;
		wrack		: out std_logic;
		regsel		: in  std_logic;
		data		: in  std_logic_vector(7 downto 0);

		lcd_rs		: out std_logic;
		lcd_wr_n	: out std_logic;
		lcd_d		: out std_logic_vector(7 downto 0)
	);
end peridot_glcd_wrstate;

architecture RTL of peridot_glcd_wrstate is
	type DEF_LCDC_STATE is (IDLE, RSETWAIT, WRASSERT, WRNEGATE, DONE);
	signal lcdc_state : DEF_LCDC_STATE;
	signal waitcount		: integer range 0 to LCDC_WAITCOUNT_MAX-1;
	signal lcdc_rs_reg		: std_logic;
	signal lcdc_wr_reg		: std_logic;
	signal lcdc_d_reg		: std_logic_vector(7 downto 0);
	signal lcdc_wrreq_sig	: std_logic;

begin

-- wrreqのアサートでリクエスト 
-- segselとdataはwrreqをアサートしている間は変更しない 
-- 処理が終了後、１クロック幅のwrackが返る 
-- wrreqのネゲートはwrack受信後、１クロック以内に行うこと 

--==== ILI9325 i80-8bit接続 ==========================================

	lcdc_wrreq_sig <= wrreq;
	wrack <= '1' when(lcdc_state = DONE) else '0';	-- ACKは１クロック幅 

	lcd_rs   <= lcdc_rs_reg;
	lcd_wr_n <= not lcdc_wr_reg;
	lcd_d    <= lcdc_d_reg;

	process (clk, reset) begin
		if (reset = '1') then
			lcdc_state <= IDLE;
			lcdc_rs_reg <= '0';
			lcdc_wr_reg <= '0';

		elsif rising_edge(clk) then
			case lcdc_state is
			when IDLE =>
				if (lcdc_wrreq_sig = '1') then
					lcdc_state <= RSETWAIT;
					waitcount  <= LCDC_WRSETUP_COUNT-1;
					lcdc_rs_reg <= regsel;
					lcdc_d_reg  <= data;
				end if;

			when RSETWAIT =>	-- nWRのセットアップ待ち 
				if (waitcount = 0) then
					lcdc_state <= WRASSERT;
					waitcount  <= LCDC_WRWIDTH_COUNT-1;
					lcdc_wr_reg <= '1';
				else
					waitcount <= waitcount - 1;
				end if;

			when WRASSERT =>	-- nWRアサートとパルス待ち 
				if (waitcount = 0) then
					lcdc_state <= WRNEGATE;
					waitcount  <= LCDC_WRHOLD_COUNT-1;
					lcdc_wr_reg <= '0';
				else
					waitcount <= waitcount - 1;
				end if;

			when WRNEGATE =>	-- nWRネゲートとホールドおよびサイクル待ち 
				if (waitcount = 0) then
					lcdc_state <= DONE;
				else
					waitcount <= waitcount - 1;
				end if;

			when DONE =>
				lcdc_state <= IDLE;

			end case;

		end if;
	end process;



end RTL;
