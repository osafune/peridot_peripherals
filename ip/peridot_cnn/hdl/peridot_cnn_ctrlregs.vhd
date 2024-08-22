-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - control register
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/09/06 -> 2020/09/19
--            : 2020/09/20 (FIXED)
--
--     UPDATE : 2023/11/30 -> 2024/03/15
--
-- ===================================================================
--
-- The MIT License (MIT)
-- Copyright (c) 2020,2023 J-7SYSTEM WORKS LIMITED.
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

library lpm;
use lpm.lpm_components.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity peridot_cnn_ctrlregs is
	generic(
		MAXKERNEL_NUMBER		: integer := 4;		-- カーネルインスタンス数 (1～8)
		RANDGEN_INSTANCE_TYPE	: integer := 1;		-- 乱数生成器実装タイプ (0:なし / 1:一様乱数,近似cos^19)
		FCFUNC_INSTANCE_TYPE	: integer := 1;		-- 全結合実装タイプ (0:なし / 1:INT8xINT16)
		ACTFUNC_INSTANCE_TYPE	: integer := 3;		-- 活性化関数実装タイプ (0:ReLU,Hard-tanh,Step,Leaky-ReLU / 1:0+sigmoid / 2:0+1+tanh / 3:0+1+2+LUT)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		MAXCONVSIZE_POW2_NUMBER	: integer := 10;	-- 畳み込み画像の最大値 (8:256x256 / 9:512x512 / 10:1024x1024 / 11:2048x2048)
		MAXLINEBYTES_POW2_NUMBER: integer := 15;	-- ラインデータ増分値の最大バイト数 (10:±1kbyte ～ 15:±32kbyte)
		INTRBUFFER_POW2_NUMBER	: integer := 10;	-- 内蔵バッファのサイズ (0:なし / 10:1kワード / 12:4kワード / 14:16kワード)
		USE_REDUCED_REGMAP		: string := "OFF";	-- reg4～7のステータスレジスタを削除した縮小レジスタマップオプション 

		-- SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: out std_logic;
		start			: out std_logic;
		ready			: in  std_logic;
		error			: in  std_logic;
		pause			: in  std_logic;
		restart			: out std_logic;
		status			: in  std_logic_vector(40 downto 0);

		pd_address_top	: out std_logic_vector(31 downto 0);
		pd_address_cur	: in  std_logic_vector(31 downto 0);

		aflut_wrclk		: out std_logic;
		aflut_wrad		: out std_logic_vector(19 downto 0);
		aflut_wrena		: out std_logic;

		avs_reset		: in  std_logic;
		avs_clk			: in  std_logic;
		avs_address		: in  std_logic_vector(2 downto 0);
		avs_read		: in  std_logic;
		avs_readdata	: out std_logic_vector(31 downto 0);
		avs_write		: in  std_logic;
		avs_writedata	: in  std_logic_vector(31 downto 0);
		ins_irq			: out std_logic;

		coe_status		: out std_logic_vector(2 downto 0)
	);
end peridot_cnn_ctrlregs;

architecture RTL of peridot_cnn_ctrlregs is
	-- Misc function
	function is_true(S:std_logic) return boolean is begin return(S='1'); end;
	function is_false(S:std_logic) return boolean is begin return(S='0'); end;
	function to_vector(N,W:integer) return std_logic_vector is begin return conv_std_logic_vector(N,W); end;
	function shiftin(V:std_logic_vector; S:std_logic) return std_logic_vector is variable a:std_logic_vector(V'length downto 0); begin a:=V&S; return a(V'range); end;
	function shiftout(V:std_logic_vector) return std_logic is begin return V(V'left); end;
	function repbit(S:std_logic; W:integer) return std_logic_vector is variable a:std_logic_vector(W-1 downto 0); begin a:=(others=>S); return a; end;
	function slice(V:std_logic_vector; W,N:integer) return std_logic_vector is variable a:std_logic_vector(V'length+W+N-2 downto 0);
		begin a:=repbit('0',W+N-1)&V; return a(W+N-1 downto N); end;
	function slice_sxt(V:std_logic_vector; W,N:integer) return std_logic_vector is variable a:std_logic_vector(V'length+W+N-2 downto 0);
		begin a:=repbit(V(V'left),W+N-1)&V; return a(W+N-1 downto N); end;

	-- モジュール固定値 
	function sel(F:boolean; A,B:integer) return integer is begin if F then return A; else return B; end if; end;
	constant ACCUMBUFF_SIZE		: integer := sel(INTRBUFFER_POW2_NUMBER = 0, 0, INTRBUFFER_POW2_NUMBER/2-4);
	constant COMPONENT_ID		: integer := 16#7A#;	-- 7Ah : PERIDOT_CNN Rev.1


	-- レジスタブロック 
	signal error_cap_reg		: std_logic;	-- cnn_core error信号キャプチャ 
	signal ready_cap_reg		: std_logic;	-- cnn_core ready信号キャプチャ 
	signal pause_cap_reg		: std_logic;	-- cnn_core pause信号キャプチャ 
	signal out_abort_reg		: std_logic_vector(1 downto 0);		-- avs→avm クロックブリッジ 
	signal out_start_reg		: std_logic_vector(2 downto 0);		-- avs→avm クロックブリッジ 
	signal out_restart_reg		: std_logic_vector(2 downto 0);		-- avs→avm クロックブリッジ 
	signal start_req_reg		: std_logic;
	signal ready_mask_reg		: std_logic;
	signal restart_req_reg		: std_logic;
	signal pause_mask_reg		: std_logic;
	signal in_error_reg			: std_logic_vector(2 downto 0);		-- avs←avm クロックブリッジ 
	signal in_ready_reg			: std_logic_vector(2 downto 0);		-- avs←avm クロックブリッジ 
	signal in_pause_reg			: std_logic_vector(2 downto 0);		-- avs←avm クロックブリッジ 
	signal in_pdcur_reg			: std_logic_vector(31 downto 5);	-- avs←avm クロックブリッジ 
	signal in_status_reg		: std_logic_vector(40 downto 0);	-- avs←avm クロックブリッジ 
	signal error_rise_sig		: std_logic;
	signal error_sig			: std_logic;
	signal ready_rise_sig		: std_logic;
	signal ready_sig			: std_logic;
	signal pause_rise_sig		: std_logic;
	signal pause_sig			: std_logic;

	signal start_reg			: std_logic;
	signal exec_reg				: std_logic;
	signal restart_reg			: std_logic;
	signal abort_reg			: std_logic;
	signal done_reg				: std_logic;
	signal yield_reg			: std_logic;
	signal halt_reg				: std_logic;
	signal irq_ena_reg			: std_logic;
	signal pd_address_reg		: std_logic_vector(31 downto 5);	-- avs→avm クロックブリッジ 

	signal reg_0_sig			: std_logic_vector(31 downto 0);
	signal reg_1_sig			: std_logic_vector(31 downto 0);
	signal reg_2_sig			: std_logic_vector(31 downto 0);
	signal reg_3_sig			: std_logic_vector(31 downto 0);
	signal reg_4_sig			: std_logic_vector(31 downto 0);
	signal reg_5_sig			: std_logic_vector(31 downto 0);
	signal reg_6_sig			: std_logic_vector(31 downto 0);
	signal reg_7_sig			: std_logic_vector(31 downto 0);


	-- タイミング解析除外パス設定 
	attribute altera_attribute : string;
	attribute altera_attribute of RTL : architecture is
	(
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|abort_reg] -to [get_registers *peridot_cnn_ctrlregs:*\|out_abort_reg\[0\]]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|start_reg] -to [get_registers *peridot_cnn_ctrlregs:*\|out_start_reg\[0\]]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|restart_reg] -to [get_registers *peridot_cnn_ctrlregs:*\|out_restart_reg\[0\]]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|error_cap_reg] -to [get_registers *peridot_cnn_ctrlregs:*\|in_error_reg\[0\]]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|ready_cap_reg] -to [get_registers *peridot_cnn_ctrlregs:*\|in_ready_reg\[0\]]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|pause_cap_reg] -to [get_registers *peridot_cnn_ctrlregs:*\|in_pause_reg\[0\]]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_ctrlregs:*\|pd_address_reg\[*\]] -to [get_registers *peridot_cnn_core:*\|*]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_core:*\|*] -to [get_registers *peridot_cnn_ctrlregs:*\|in_pdcur_reg\[*\]]"";" & 
		"-name SDC_STATEMENT ""set_false_path -from [get_registers *peridot_cnn_core:*\|*] -to [get_registers *peridot_cnn_ctrlregs:*\|in_status_reg\[*\]]"""
	);

begin

	-- テスト記述 


	-- パラメータ範囲チェック 



	----------------------------------------------------------------------
	-- クロックブリッジ 
	----------------------------------------------------------------------

	-- avs → avm クロックブリッジ 
	process (clk, reset) begin
		if is_true(reset) then
			error_cap_reg <= '0';
			ready_cap_reg <= '0';
			pause_cap_reg <= '0';
			out_abort_reg <= (others=>'0');
			out_start_reg <= (others=>'0');
			out_restart_reg <= (others=>'0');
			start_req_reg <= '0';
			ready_mask_reg <= '0';
			restart_req_reg <= '0';
			pause_mask_reg <= '0';

		elsif rising_edge(clk) then
			error_cap_reg <= error;
			ready_cap_reg <= ready and(not ready_mask_reg);
			pause_cap_reg <= pause and(not pause_mask_reg);
			out_abort_reg <= shiftin(out_abort_reg, abort_reg);
			out_start_reg <= shiftin(out_start_reg, start_reg);
			out_restart_reg <= shiftin(out_restart_reg, restart_reg);

			if is_true(start_req_reg) then
				if is_false(ready) then
					start_req_reg <= '0';		-- readyネゲートでクリア 
					ready_mask_reg <= '1';		-- csr側に伝搬するまでreadyマスク 
				end if;
			else
				if (out_start_reg(2 downto 1) = "01") then
					start_req_reg <= '1';		-- startレジスタの↑(1書き込み検出)でセット 
				end if;

				if (out_start_reg(2 downto 1) = "10") then
					ready_mask_reg <= '0';		-- startレジスタの↓(クリア検出)でreadyマスク解除 
				end if;
			end if;

			if is_true(restart_req_reg) then
				if is_false(pause) then
					restart_req_reg <= '0';		-- pauseネゲートでクリア 
					pause_mask_reg <= '1';		-- csr側に伝搬するまでpauseマスク 
				end if;
			else
				if (out_restart_reg(2 downto 1) = "01") then
					restart_req_reg <= '1';		-- restartレジスタの↑(1書き込み検出)でセット 
				end if;

				if (out_restart_reg(2 downto 1) = "10") then
					pause_mask_reg <= '0';		-- restartレジスタの↓(クリア検出)でpauseマスク解除 
				end if;
			end if;

		end if;
	end process;

	init <= out_abort_reg(1);
	start <= start_req_reg;
	restart <= restart_req_reg;

	pd_address_top <= pd_address_reg & repbit('0', 5);


	-- avs ← avm クロックブリッジ 
	process (avs_clk, avs_reset) begin
		if is_true(avs_reset) then
			in_error_reg <= (others=>'0');
			in_ready_reg <= (others=>'0');
			in_pause_reg <= (others=>'0');

		elsif rising_edge(avs_clk) then
			in_error_reg <= shiftin(in_error_reg, error_cap_reg);
			in_ready_reg <= shiftin(in_ready_reg, ready_cap_reg);
			in_pause_reg <= shiftin(in_pause_reg, pause_cap_reg);

			in_pdcur_reg <= pd_address_cur(31 downto 5);
			in_status_reg <= status;

		end if;
	end process;

	error_rise_sig <= '1' when(in_error_reg(2 downto 1) = "01") else '0';
	error_sig <= in_error_reg(1);

	ready_rise_sig <= '1' when(in_ready_reg(2 downto 1) = "01") else '0';
	ready_sig <= in_ready_reg(1);

	pause_rise_sig <= '1' when(in_pause_reg(2 downto 1) = "01") else '0';
	pause_sig <= in_pause_reg(1);



	----------------------------------------------------------------------
	-- AvalonMM レジスタエージェント 
	----------------------------------------------------------------------

	-- レジスタ読み出し 

	gen_rmap : if (USE_REDUCED_REGMAP = "ON") generate
		with avs_address select avs_readdata <=
			reg_0_sig	when "000",
			reg_1_sig	when "001",
			reg_2_sig	when "010",
			(others=>'X') when others;
	end generate;
	gen_normap : if (USE_REDUCED_REGMAP /= "ON") generate
		with avs_address select avs_readdata <=
			reg_0_sig	when "000",
			reg_1_sig	when "001",
			reg_2_sig	when "010",
			reg_3_sig	when "011",
			reg_4_sig	when "100",
			reg_5_sig	when "101",
			reg_6_sig	when "110",
			reg_7_sig	when "111",
			(others=>'X') when others;
	end generate;

	reg_0_sig <= (
		15 => irq_ena_reg,		-- bit15: irq enable
		10 => halt_reg,			-- bit10: error halt(w0)
		9  => yield_reg,		-- bit9 : pause halt(w0)
		8  => done_reg,			-- bit8 : done(w0)
		6  => abort_reg,		-- bit6 : abort request(w1)
		5  => restart_reg,		-- bit5 : restart request(w1)
		4  => start_reg,		-- bit4 : start requrst(w1)
		2  => error_sig,		-- bit2 : error(ro)
		1  => pause_sig,		-- bit1 : pause(ro)
		0  => ready_sig,		-- bit0 : ready(ro)
		others => 'X'
	);

	reg_1_sig <= pd_address_reg & repbit('0', 5);

	reg_2_sig <= in_pdcur_reg & repbit('0', 5);

	reg_3_sig <= (others=>'X');

	reg_4_sig <=
		to_vector(COMPONENT_ID, 8) &				-- bit31-24: COMPONENT ID
		"XXXXX" & 
		to_vector(FCFUNC_INSTANCE_TYPE, 2) &		-- bit18-17: FCFUNC_INSTANCE_TYPE
		to_vector(ACTFUNC_INSTANCE_TYPE, 2) &		-- bit16-15: ACTFUNC_INSTANCE_TYPE
		to_vector(RANDGEN_INSTANCE_TYPE, 2) &		-- bit14-13: RANDGEN_INSTANCE_TYPE
		to_vector(ACCUMBUFF_SIZE, 3) &				-- bit12-10: INTRBUFFER_POW2_NUMBER/2-4 (>0のとき)
		to_vector(MAXLINEBYTES_POW2_NUMBER-10, 3) &	-- bit9-7  : MAXLINEBYTES_POW2_NUMBER-10
		to_vector(MAXCONVSIZE_POW2_NUMBER-8, 3) &	-- bit6-4  : MAXCONVSIZE_POW2_NUMBER-8
		to_vector(MAXKERNEL_NUMBER, 4);				-- bit3-0  : MAXKERNEL_NUMBER

	reg_5_sig <= (others=>'X');

	reg_6_sig <= in_status_reg(31 downto 0);		-- bit31-28: kernel7 status
													-- bit27-24: kernel6 status
													-- bit23-20: kernel5 status
													-- bit19-16: kernel4 status
													-- bit15-12: kernel3 status
													-- bit11-8 : kernel2 status
													-- bit7-4  : kernel1 status
													-- bit3-0  : kernel0 status

	reg_7_sig <=
		"XXX" &
		in_status_reg(40 downto 32) &				-- bit28   : writeback status
													-- bit27-24: fc status
													-- bit23-20: accum status
		repbit('X', 20);

	ins_irq <= irq_ena_reg when is_true(halt_reg) or is_true(yield_reg) or is_true(done_reg) else '0';


	-- レジスタ書き込みとフラグ処理 

	process (avs_clk, avs_reset) begin
		if is_true(avs_reset) then
			start_reg <= '0';
			exec_reg <= '0';
			restart_reg <= '0';
			abort_reg <= '0';
			done_reg <= '0';
			yield_reg <= '0';
			halt_reg <= '0';
			irq_ena_reg <= '0';

		elsif rising_edge(avs_clk) then

			-- 処理開始信号 
			if is_false(ready_sig) then
				start_reg <= '0';
			elsif (is_true(avs_write) and avs_address = 0) then
				start_reg <= start_reg or avs_writedata(4);
				exec_reg <= '1';	-- 最初の処理が始まるまではdoneをマスクする 
			end if;

			-- 処理再開信号 
			if is_false(pause_sig) then
				restart_reg <= '0';
			elsif (is_true(avs_write) and avs_address = 0) then
				restart_reg <= restart_reg or avs_writedata(5);
			end if;

			-- 中止要求信号 
			if is_true(ready_sig) then
				abort_reg <= '0';
			elsif (is_true(avs_write) and avs_address = 0) then
				abort_reg <= abort_reg or avs_writedata(6);
			end if;


			-- 処理完了割り込み要因 
			if is_true(ready_rise_sig) then
				done_reg <= exec_reg;
			elsif (is_true(avs_write) and avs_address = 0) then
				done_reg <= done_reg and avs_writedata(8);
			end if;

			-- 一時停止割り込み要因 
			if is_true(pause_rise_sig) then
				yield_reg <= '1';
			elsif (is_true(avs_write) and avs_address = 0) then
				yield_reg <= yield_reg and avs_writedata(9);
			end if;

			-- エラー割り込み要因 
			if is_true(error_rise_sig) then
				halt_reg <= '1';
			elsif (is_true(avs_write) and avs_address = 0) then
				halt_reg <= halt_reg and avs_writedata(10);
			end if;

			-- 割り込みイネーブル 
			if (is_true(avs_write) and avs_address = 0) then
				irq_ena_reg <= avs_writedata(15);
			end if;


			-- デスクリプタ先頭アドレス 
			if (is_true(avs_write) and avs_address = 1 and is_true(ready_sig) and is_false(start_reg)) then
				pd_address_reg <= avs_writedata(pd_address_reg'range);
			end if;

		end if;
	end process;


	-- AFLUT書き換え信号 

	gen_lut0 : if (ACTFUNC_INSTANCE_TYPE = 1 or ACTFUNC_INSTANCE_TYPE = 2) generate
		aflut_wrclk <= avs_clk;
		aflut_wrad <= "00" & avs_writedata(17 downto 0);
		aflut_wrena <= '1' when(is_true(avs_write) and avs_address = 3 and avs_writedata(27 downto 24) = "1100") else '0';
	end generate;
	gen_lut1 : if (ACTFUNC_INSTANCE_TYPE = 3) generate
		aflut_wrclk <= avs_clk;
		aflut_wrad <= '1' & avs_writedata(24) & avs_writedata(17 downto 0);
		aflut_wrena <= '1' when(is_true(avs_write) and avs_address = 3 and avs_writedata(27 downto 25) = "101") else '0';
	end generate;
	gen_nolut : if (ACTFUNC_INSTANCE_TYPE = 0) generate
		aflut_wrclk <= '0';
		aflut_wrad <= (others=>'0');
		aflut_wrena <= '0';
	end generate;


	-- 内部ステータス信号モニタ 

	coe_status <= error_cap_reg & pause_cap_reg & ready_cap_reg;



end RTL;
