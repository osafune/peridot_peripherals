-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - control register
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/09/06 -> 2020/09/19
--            : 2020/09/20 (FIXED)
--
-- ===================================================================
--
-- The MIT License (MIT)
-- Copyright (c) 2020 J-7SYSTEM WORKS LIMITED.
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
--


-- VHDL 1993 / IEEE 1076-1993
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_misc.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity peridot_cnn_ctrlregs is
	generic(
		MAXKERNEL_NUMBER		: integer := 4;		-- カーネルインスタンス数 (1～8)
		SETNUMBER_POW2_NUMBER	: integer := 16;	-- 最大フィルターセット数 (10:1023 ～ 16:65535)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		MAXCONVSIZE_POW2_NUMBER	: integer := 9;		-- 畳み込み画像の最大値 (8:256x256 / 9:512x512 / 10:1024x1024 / 11:2048x2048)
		MAXLINEBYTES_POW2_NUMBER: integer := 15;	-- ラインデータ増分値の最大バイト数 (10:±1kbyte ～ 15:±32kbyte)

		-- SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
		DEVICE_FAMILY			: string := "Cyclone 10 LP"
	);
	port(
		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: out std_logic;
		start			: out std_logic;
		ready			: in  std_logic;
		error			: in  std_logic;
		finally			: in  std_logic := '0';
		status			: in  std_logic_vector(35 downto 0) := (others=>'0');

		pd_address_top	: out std_logic_vector(31 downto 0);
		pd_setnumber	: out std_logic_vector(15 downto 0);

		avs_reset		: in  std_logic;
		avs_clk			: in  std_logic;
		avs_address		: in  std_logic_vector(1 downto 0);
		avs_read		: in  std_logic;
		avs_readdata	: out std_logic_vector(31 downto 0);
		avs_write		: in  std_logic;
		avs_writedata	: in  std_logic_vector(31 downto 0);
		ins_irq			: out std_logic
	);
end peridot_cnn_ctrlregs;

architecture RTL of peridot_cnn_ctrlregs is
	function is_true(S:std_logic) return boolean is begin return(S='1'); end;
	function is_false(S:std_logic) return boolean is begin return(S='0'); end;
	function to_vector(N,W:integer) return std_logic_vector is begin return conv_std_logic_vector(N,W); end;
	function repbit(S:std_logic; W:integer) return std_logic_vector is variable a:std_logic_vector(W-1 downto 0); begin a:=(others=>S); return a; end;
	function shiftin(V:std_logic_vector; S:std_logic) return std_logic_vector is begin return V(V'left-1 downto 0)&S; end;
	function shiftout(V:std_logic_vector) return std_logic is begin return V(V'left); end;

	function slice(V:std_logic_vector; W,N:integer) return std_logic_vector is variable a:std_logic_vector(V'length+W+N-2 downto 0);
	begin a:=repbit('0',W+N-1)&V; return a(W+N-1 downto N); end;
	function slice_sxt(V:std_logic_vector; W,N:integer) return std_logic_vector is variable a:std_logic_vector(V'length+W+N-2 downto 0);
	begin a:=repbit(V(V'left),W+N-1)&V; return a(W+N-1 downto N); end;

	-- モジュール固定値 
	constant ALIGN_ADDR_WIDTH	: integer := DATABUS_POW2_NUMBER-3;		-- ワード境界のアドレスビット幅 


	-- レジスタブロック 
	signal start_reg			: std_logic;
	signal abort_reg			: std_logic;
	signal ready_reg			: std_logic;
	signal error_reg			: std_logic;
	signal toggle_reg			: std_logic;
	signal out_start_reg		: std_logic_vector(1 downto 0);		-- avs→avm クロックブリッジ 
	signal out_abort_reg		: std_logic_vector(1 downto 0);		-- avs→avm クロックブリッジ 
	signal start_ack_reg		: std_logic;
	signal abort_ack_reg		: std_logic;
	signal in_start_reg			: std_logic_vector(1 downto 0);		-- avs←avm クロックブリッジ 
	signal in_abort_reg			: std_logic_vector(1 downto 0);		-- avs←avm クロックブリッジ 
	signal in_ready_reg			: std_logic_vector(2 downto 0);		-- avs←avm クロックブリッジ 
	signal in_error_reg			: std_logic_vector(2 downto 0);		-- avs←avm クロックブリッジ 
	signal in_toggle_reg		: std_logic_vector(2 downto 0);		-- avs←avm クロックブリッジ 
	signal irq_ena_reg			: std_logic;
	signal irq_reg				: std_logic;
	signal pd_address_reg		: std_logic_vector(31 downto ALIGN_ADDR_WIDTH);	-- avs→avm クロックブリッジ 
	signal pd_setnumber_reg		: std_logic_vector(SETNUMBER_POW2_NUMBER-1 downto 0); -- avs→avm クロックブリッジ 
	signal status_reg			: std_logic_vector(35 downto 0);				-- avs←avm クロックブリッジ 
	signal ready_rise_sig		: std_logic;
	signal error_rise_sig		: std_logic;
	signal toggle_change_sig	: std_logic;
	signal status_sig			: std_logic_vector(35 downto 0);
	signal reg_0_sig			: std_logic_vector(31 downto 0) := (others=>'0');
	signal reg_1_sig			: std_logic_vector(31 downto 0) := (others=>'0');
	signal reg_2_sig			: std_logic_vector(31 downto 0) := (others=>'0');
	signal reg_3_sig			: std_logic_vector(31 downto 0) := (others=>'0');


	-- タイミング解析除外パス設定 
	attribute altera_attribute : string;
	attribute altera_attribute of RTL : architecture is
	(
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|start_reg] -to [get_registers *peridot_cnn_ctrlregs:*\|out_start_reg\[0\]]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|abort_reg] -to [get_registers *peridot_cnn_ctrlregs:*\|out_abort_reg\[0\]]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|start_ack_reg] -to [get_registers *peridot_cnn_ctrlregs:*\|in_start_reg\[0\]]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|abort_ack_reg] -to [get_registers *peridot_cnn_ctrlregs:*\|in_abort_reg\[0\]]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|ready_reg] -to [get_registers *peridot_cnn_ctrlregs:*\|in_ready_reg\[0\]]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|error_reg] -to [get_registers *peridot_cnn_ctrlregs:*\|in_error_reg\[0\]]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|toggle_reg] -to [get_registers *peridot_cnn_ctrlregs:*\|in_toggle_reg\[0\]]"";" & 

		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|pd_address_reg\[*\]] -to [get_registers *peridot_cnn_core:*\|*]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|pd_setnumber_reg\[*\]] -to [get_registers *peridot_cnn_core:*\|*]"";" & 
		"-name SDC_STATEMENT ""set_false_path -to [get_registers *peridot_cnn_ctrlregs:*\|status_reg\[*\]]"""
	);


begin

	-- テスト記述 


	-- パラメータ範囲チェック 

	assert (SETNUMBER_POW2_NUMBER >= 10 and SETNUMBER_POW2_NUMBER <= 16)
		report "SETNUMBER_POW2_NUMBER is out of range.";



	----------------------------------------------------------------------
	-- 制御信号 
	----------------------------------------------------------------------

	start <= out_start_reg(1);
	init <= out_abort_reg(1);
	status_sig <= status;

	pd_address_top <= pd_address_reg & repbit('0', ALIGN_ADDR_WIDTH);
	pd_setnumber <= slice(pd_setnumber_reg, pd_setnumber'length, 0);

	process (clk, reset) begin
		if is_true(reset) then
			ready_reg <= '0';
			error_reg <= '0';
			toggle_reg <= '0';
			out_start_reg <= (others=>'0');
			out_abort_reg <= (others=>'0');
			start_ack_reg <= '0';
			abort_ack_reg <= '0';

		elsif rising_edge(clk) then
			error_reg <= error;
			out_start_reg <= shiftin(out_start_reg, start_reg);
			out_abort_reg <= shiftin(out_abort_reg, abort_reg);

			if is_false(out_abort_reg(1)) and is_true(ready) then	-- abortがアサートされている間はreadyをマスク 
				ready_reg <= '1';
			else
				ready_reg <= '0';
			end if;

			if is_true(finally) then								-- フィルターセット処理毎に反転する信号 
				toggle_reg <= not toggle_reg;
			end if;

			if is_true(out_start_reg(1)) and is_false(ready) then	-- startアサートしてreadyが下がったら受理 
				start_ack_reg <= '1';
			else
				start_ack_reg <= '0';
			end if;

			if is_true(out_abort_reg(1)) and is_true(ready) then	-- abortアサートしてreadyが指示されたら完了 
				abort_ack_reg <= '1';
			else
				abort_ack_reg <= '0';
			end if;

		end if;
	end process;



	----------------------------------------------------------------------
	-- AvalonMM レジスタスレーブ 
	----------------------------------------------------------------------

	-- レジスタ読み出し 

	with avs_address select avs_readdata <=
		reg_1_sig	when "01",
		reg_2_sig	when "10",
		reg_3_sig	when "11",
		reg_0_sig	when others;

	reg_0_sig(31) <= irq_ena_reg;					-- bit31:irq enable
	reg_0_sig(30) <= irq_reg;						-- bit30:irq factor(w0)
	reg_0_sig(29) <= abort_reg;						-- bit29:abort request(w1)
	reg_0_sig(25) <= in_error_reg(1);				-- bit25:error (ro)
	reg_0_sig(24) <= in_ready_reg(1) when is_false(start_reg) else '0';	-- bit24:ready (ro)
	reg_0_sig(pd_setnumber_reg'range) <= pd_setnumber_reg;	-- bit15-0:setnumber

	reg_1_sig <= pd_address_reg & repbit('0', ALIGN_ADDR_WIDTH);

	reg_2_sig <= status_reg(35 downto 32) &			-- bit31:wb ready, bit30-29:accum status, bit28:accum ready
		repbit('0', 12) &
		to_vector(MAXLINEBYTES_POW2_NUMBER-10, 4) &	-- bit15-12: MAXLINEBYTES_POW2_NUMBER-10
		to_vector(MAXCONVSIZE_POW2_NUMBER, 4) &		-- bit11-8 : MAXCONVSIZE_POW2_NUMBER
		to_vector(SETNUMBER_POW2_NUMBER-10, 4) &	-- bit7-4  : SETNUMBER_POW2_NUMBER-10
		to_vector(MAXKERNEL_NUMBER, 4);				-- bit3-0  : MAXKERNEL_NUMBER

	reg_3_sig <= status_reg(31 downto 0);			-- bit31-29:kernel7 status, bit28:kernel7 ready
													-- bit27-25:kernel6 status, bit24:kernel6 ready
													-- bit23-21:kernel5 status, bit20:kernel5 ready
													-- bit19-17:kernel4 status, bit16:kernel4 ready
													-- bit15-13:kernel3 status, bit12:kernel3 ready
													-- bit11-9 :kernel2 status, bit8 :kernel2 ready
													-- bit7-5  :kernel1 status, bit4 :kernel1 ready
													-- bit3-1  :kernel0 status, bit0 :kernel0 ready

	ins_irq <= irq_reg and irq_ena_reg;


	-- レジスタ書き込みとフラグ処理 

	ready_rise_sig <= '1' when(in_ready_reg(2 downto 1) = "01") else '0';
	error_rise_sig <= '1' when(in_error_reg(2 downto 1) = "01") else '0';
	toggle_change_sig <= '1' when(in_toggle_reg(2) /= in_toggle_reg(1)) else '0';

	process (avs_clk, avs_reset) begin
		if is_true(avs_reset) then
			start_reg <= '0';
			abort_reg <= '0';
			irq_ena_reg <= '0';
			irq_reg <= '0';
			in_start_reg <= (others=>'0');
			in_abort_reg <= (others=>'0');
			in_ready_reg <= (others=>'0');
			in_error_reg <= (others=>'0');
			in_toggle_reg <= (others=>'0');

			pd_setnumber_reg <= (others=>'0');

		elsif rising_edge(avs_clk) then
			status_reg <= status_sig;
			in_start_reg <= shiftin(in_start_reg, start_ack_reg);
			in_abort_reg <= shiftin(in_abort_reg, abort_ack_reg);
			in_ready_reg <= shiftin(in_ready_reg, ready_reg);
			in_error_reg <= shiftin(in_error_reg, error_reg);
			in_toggle_reg <= shiftin(in_toggle_reg, toggle_reg);


			-- 処理開始信号 
			if is_true(start_reg) then
				if is_true(in_start_reg(1)) then
					start_reg <= '0';
				end if;
			elsif is_true(in_ready_reg(1)) then
				if (is_true(avs_write) and avs_address = 0 and avs_writedata(pd_setnumber_reg'range) /= 0) then
					start_reg <= '1';
				end if;
			end if;

			-- 処理回数レジスタ 
			if (is_false(start_reg) and is_true(in_ready_reg(1)) and is_true(avs_write) and avs_address = 0) then
				pd_setnumber_reg <= avs_writedata(pd_setnumber_reg'range);
			elsif is_true(toggle_change_sig) then
				pd_setnumber_reg <= pd_setnumber_reg - 1;
			end if;


			-- 中断要求 
			if is_true(abort_reg) then
				if is_true(in_abort_reg(1)) then
					abort_reg <= '0';
				end if;
			else
				if (is_true(avs_write) and avs_address = 0 and avs_writedata(29) = '1') then
					abort_reg <= '1';
				end if;
			end if;

			-- 割り込み要求 
			if is_true(ready_rise_sig) or is_true(error_rise_sig) then
				irq_reg <= '1';
			elsif (is_true(avs_write) and avs_address = 0 and avs_writedata(30) = '0') then
				irq_reg <= '0';
			end if;

			if (is_true(avs_write) and avs_address = 0) then
				irq_ena_reg <= avs_writedata(31);
			end if;


			-- デスクリプタ先頭アドレス 
			if (is_true(avs_write) and avs_address = 1) then
				pd_address_reg <= avs_writedata(pd_address_reg'range);
			end if;

		end if;
	end process;



end RTL;
