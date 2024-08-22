-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - Activate function
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2023/11/30 -> 2023/12/07
--            : 2023/12/12 (FIXED)
--
-- ===================================================================
--
-- The MIT License (MIT)
-- Copyright (c) 2023 J-7SYSTEM WORKS LIMITED.
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

-- フィルター累算器から出力されるフレームデータを decimal_pos の指示に従って
-- 小数位置より上位を取り出し、actfunc_type で指示される活性化関数で処理を行う。 
--
-- 入力データはまず整数部を-512～+511に飽和した注目範囲をとりだす。 
-- 注目範囲データから以下の活性化処理を行う。 
--
-- ・actfunc_type = 000 : ReLU (符号無し8bit飽和,出力はUINT8)
--     f(x) = 0    (x < 0)
--          = x    (0 < x <= 255)
--          = 255  (x > 255)
--
-- ・actfunc_type = 001 : Hard-tanh (符号付き8bit飽和,出力はINT8)
--     f(x) = -128 (x < -128)
--          = x    (-128 <= x <= 127)
--          = 127  (x > 127)
--
-- ・actfunc_type = 010 : Step (符号によるステップ,出力はUINT8)
--     f(x) = 0    (x < 0)
--          = 255  (x >= 0)
--
-- ・actfunc_type = 011 : Leaky-ReLU (出力はINT8)
--     f(x) = -1   (x < 0)
--          = x    (0 <= x <= 127)
--          = 127  (x > 127)
--
-- ・actfunc_type = 100 : sigmoid (出力はUINT8)
--     f(x) = {1 / (1 + exp(-x')) } * s
--            ただし x' = x/128 * 5/4, s = 256
--            入力範囲を1.25倍に拡大しているので、カーネルスケールを4/5倍にしておくこと 
--
-- ・actfunc_type = 101 : tanh (出力はINT8)
--     f(x) = {(exp(x') - exp(-'x)) / (exp(x') + exp(-'x)) } * s
--            ただし x' = x/128, s = 128
--            出力は-128～127の範囲で飽和する 
--
-- ・actfunc_type = 110 : LUT set1 (出力はUINT8)
--     f(x) = LUT(2048 + (x + 512))
--            出力は0～255の範囲 
--
-- ・actfunc_type = 111 : LUT set2 (出力はINT8)
--     f(x) = LUT(3072 + (x + 512))
--            出力は-128～127の範囲で飽和する 
--
--
-- actfunc_type=100～111の4つはテーブル参照で計算する。実装される数は ACTFUNC_INSTANCE_TYPE で 
-- 指定する。 
-- 
-- ・ACTFUNC_INSTANCE_TYPE = 0
--     テーブル参照なし 
--     実装される活性化関数 : ReLU, Hard-tanh, Step, Leaky-ReLU
--
-- ・ACTFUNC_INSTANCE_TYPE = 1
--     1セットのテーブル参照 
--     実装される活性化関数 : ReLU, Hard-tanh, Step, Leaky-ReLU, sigmoid/LUT0
--
-- ・ACTFUNC_INSTANCE_TYPE = 2
--     2セットのテーブル参照 
--     実装される活性化関数 : ReLU, Hard-tanh, Step, Leaky-ReLU, sigmoid/LUT0, tanh
--
-- ・ACTFUNC_INSTANCE_TYPE = 3
--     4セットのテーブル参照 
--     実装される活性化関数 : ReLU, Hard-tanh, Step, Leaky-ReLU, sigmoid, tanh, LUT1, LUT2
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

entity peridot_cnn_writeback_actfunc is
	generic(
		ACTFUNC_INSTANCE_TYPE	: integer := 3;		-- 活性化関数実装タイプ (0:ReLU,Hard-tanh,Step,Leaky-ReLU / 1:0+sigmoid / 2:0+1+tanh / 3:0+1+2+LUT)
		AFLUT_SET_INITIALVALUE	: string := "ON"	-- LUTの初期値を設定オプション (メモリマクロの初期値を持てないデバイスではOFFにする)
	);
	port(
		test_af_result	: out std_logic_vector(7 downto 0);
		test_rom_addr	: out std_logic_vector(11 downto 0);
		test_rom_q		: out std_logic_vector(7 downto 0);


		clk				: in  std_logic;
		actfunc_type	: in  std_logic_vector(2 downto 0);		-- Avtivate function type
		decimal_pos		: in  std_logic_vector(1 downto 0);		-- Decimal position

		init			: in  std_logic;
		enable			: in  std_logic;
		sti_valid		: in  std_logic;
		sti_data		: in  std_logic_vector(31 downto 0);
		sti_eol			: in  std_logic;
		sti_eof			: in  std_logic;

		activate_valid	: out std_logic;
		activate_data	: out std_logic_vector(7 downto 0);
		activate_eol	: out std_logic;
		activate_eof	: out std_logic;

		aflut_wrclk		: in  std_logic;						-- Avtivate function LUT write-port clock
		aflut_wrad		: in  std_logic_vector(19 downto 0);	-- LUT address/data
		aflut_wrena		: in  std_logic							-- LUT write enable
	);
end peridot_cnn_writeback_actfunc;

architecture RTL of peridot_cnn_writeback_actfunc is
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
	function sel(B:boolean; T,F:string) return string is begin if B then return T; else return F; end if; end;
	constant LUT_INITFILE		: string := sel(AFLUT_SET_INITIALVALUE = "ON", "peridot_cnn_writeback_actfunc_rom.mif", ""); -- メモリ初期値 
	constant AF_CALC_DELAY		: integer := 2;			-- 活性化関数の出力レイテンシ(2クロックで固定) 

	-- 活性化関数タイプの設定値 
	constant PARAM_AF_RELU		: std_logic_vector(2 downto 0) := "000";	-- ReLU (UINT8出力) *デフォルト 
	constant PARAM_AF_HARDTANH	: std_logic_vector(2 downto 0) := "001";	-- Hard-tanh
	constant PARAM_AF_STEP		: std_logic_vector(2 downto 0) := "010";	-- Step (UINT8出力)
	constant PARAM_AF_LEAKYRELU	: std_logic_vector(2 downto 0) := "011";	-- Leaky-ReLU
	constant PARAM_AF_SIGMOID	: std_logic_vector(2 downto 0) := "100";	-- sigmoid/LUT0 (UINT8出力)
	constant PARAM_AF_TANH		: std_logic_vector(2 downto 0) := "101";	-- tanh
	constant PARAM_AF_LUTSET1	: std_logic_vector(2 downto 0) := "110";	-- LUT1 (UINT8出力)
	constant PARAM_AF_LUTSET2	: std_logic_vector(2 downto 0) := "111";	-- LUT2

	-- decposの設定値 
	constant PARAM_DECPOS_19	: std_logic_vector(1 downto 0) := "00";		-- 19bit小数モード *デフォルト 
	constant PARAM_DECPOS_14	: std_logic_vector(1 downto 0) := "01";		-- 14bit小数モード 
	constant PARAM_DECPOS_9		: std_logic_vector(1 downto 0) := "10";		--  9bit小数モード 

	-- signal
	signal sti_data_sig			: std_logic_vector(31 downto 0);
	signal sti_valid_delay_reg	: std_logic_vector(AF_CALC_DELAY-1 downto 0);
	signal sti_eol_delay_reg	: std_logic_vector(AF_CALC_DELAY-1 downto 0);
	signal sti_eof_delay_reg	: std_logic_vector(AF_CALC_DELAY-1 downto 0);

	signal af_pos_sig			: std_logic_vector(22 downto 0);
	signal af_sign_sig			: std_logic_vector(22 downto 9);
	signal af_focus_sig			: std_logic_vector(9 downto 0);
	signal af_focus_reg			: std_logic_vector(9 downto 0);

	signal relu_q_sig			: std_logic_vector(7 downto 0);
	signal hardtanh_q_sig		: std_logic_vector(7 downto 0);
	signal step_q_sig			: std_logic_vector(7 downto 0);
	signal leakyrelu_q_sig		: std_logic_vector(7 downto 0);
	signal af_result_sig		: std_logic_vector(7 downto 0);
	signal af_result_reg		: std_logic_vector(7 downto 0);

	signal lut_wraddr_sig		: std_logic_vector(11 downto 0);
	signal rom_addr_sig			: std_logic_vector(11 downto 0);
	signal rom_q_sig			: std_logic_vector(7 downto 0);

begin

	test_af_result <= af_result_reg;
	test_rom_addr <= rom_addr_sig;
	test_rom_q <= rom_q_sig;


	-- 活性化処理 

	sti_data_sig <= sti_data;

	with actfunc_type(1 downto 0) select af_result_sig <=
		leakyrelu_q_sig	when "11",
		step_q_sig		when "10",
		hardtanh_q_sig	when "01",
		relu_q_sig		when others;

	process (clk) begin
		if rising_edge(clk) then
			-- データ有効ディレイ信号生成 
			if is_true(init) then
				sti_valid_delay_reg <= (others=>'0');
				sti_eol_delay_reg <= (others=>'0');
				sti_eof_delay_reg <= (others=>'0');
			elsif is_true(enable) then
				sti_valid_delay_reg <= shiftin(sti_valid_delay_reg, sti_valid);
				sti_eol_delay_reg <= shiftin(sti_eol_delay_reg, sti_eol);
				sti_eof_delay_reg <= shiftin(sti_eof_delay_reg, sti_eof);
			end if;

			-- パイプラインレジスタ 
			if is_true(enable) then
				af_focus_reg  <= af_focus_sig;
				af_result_reg <= af_result_sig;
			end if;

		end if;
	end process;


	-- 小数位置での切り出しと飽和 

	with decimal_pos select af_pos_sig <=
		slice_sxt(sti_data_sig, 23, 9)	when PARAM_DECPOS_9,
		slice_sxt(sti_data_sig, 23, 14)	when PARAM_DECPOS_14,
		slice_sxt(sti_data_sig, 23, 19)	when others;

	af_sign_sig <= af_pos_sig(af_sign_sig'range);
	af_focus_sig <=
		(9=>af_sign_sig(22), others=>not af_sign_sig(22)) when(or_reduce(af_sign_sig) /= and_reduce(af_sign_sig)) else	-- 符号ビットが同値ではない 
		af_pos_sig(af_focus_sig'range);


	-- ReLU (符号無し飽和) 

	with af_focus_reg(9 downto 8) select relu_q_sig <=
		af_focus_reg(7 downto 0)	when "00",		-- 0～255
		(others=>'1')				when "01",		-- 255以上のとき 
		(others=>'0')				when others;	-- 0以下のとき 

	-- Hard-tanh (符号付き飽和) 

	hardtanh_q_sig <=
		(7=>af_focus_reg(9), others=>not af_focus_reg(9)) when(or_reduce(af_focus_reg(9 downto 7)) /= and_reduce(af_focus_reg(9 downto 7))) else
		af_focus_reg(7 downto 0);

	-- Step

	step_q_sig <= (others=>'0') when(af_focus_reg(9) = '1') else (others=>'1');		-- 負数のとき0、正数のとき255

	-- Leaky-ReLU

	leakyrelu_q_sig <=
		(others=>'1') when(af_focus_reg(9) = '1') else	-- 0以下のとき 
		(7=>'0', others=>'1') when(af_focus_reg(9) = '0' and af_focus_reg(8 downto 7) /= "00") else	-- 127以上のとき 
		af_focus_reg(7 downto 0);


	-- LUTベース活性化関数のインスタンス (sigmoid, tanh, LUT1, LUT2)

	gen_rom : if (ACTFUNC_INSTANCE_TYPE > 0) generate
		lut_wraddr_sig(9 downto 0) <= aflut_wrad(17 downto 8);
		lut_wraddr_sig(10) <= aflut_wrad(18) when(ACTFUNC_INSTANCE_TYPE > 1) else '0';
		lut_wraddr_sig(11) <= aflut_wrad(19) when(ACTFUNC_INSTANCE_TYPE > 2) else '0';

		rom_addr_sig(9 downto 0) <= (not af_focus_sig(9)) & af_focus_sig(8 downto 0);	-- 2の補数表記→セロオフセット変換 
		rom_addr_sig(10) <= actfunc_type(0) when(ACTFUNC_INSTANCE_TYPE > 1) else '0';
		rom_addr_sig(11) <= actfunc_type(1) when(ACTFUNC_INSTANCE_TYPE > 2) else '0';

		-- Table ROM : 2clock latency
		u_aflut : altsyncram
		generic map (
--			intended_device_family	=> DEVICE_FAMILY,
			lpm_type				=> "altsyncram",
			operation_mode			=> "DUAL_PORT",
			clock_enable_input_a	=> "NORMAL",
			clock_enable_input_b	=> "NORMAL",
			clock_enable_output_b	=> "NORMAL",
			address_aclr_b			=> "NONE",
			address_reg_b			=> "CLOCK1",
			outdata_aclr_b			=> "NONE",
			outdata_reg_b			=> "CLOCK1",
			power_up_uninitialized	=> "FALSE",
			init_file				=> LUT_INITFILE,
			numwords_a				=> 4096,
			widthad_a				=> 12,
			width_a					=> 8,
			width_byteena_a			=> 1,
			numwords_b				=> 4096,
			widthad_b				=> 12,
			width_b					=> 8
		)
		port map (
			clock0		=> aflut_wrclk,
			clocken0	=> '1',
			address_a	=> lut_wraddr_sig,
			data_a		=> aflut_wrad(7 downto 0),
			wren_a		=> aflut_wrena,

			clock1		=> clk,
			clocken1	=> enable,
			address_b	=> rom_addr_sig,
			q_b			=> rom_q_sig
		);
	end generate;
	gen_norom : if (ACTFUNC_INSTANCE_TYPE = 0) generate
		rom_addr_sig <= (others=>'X');
		rom_q_sig <= (others=>'0');
	end generate;


	-- 結果出力 

	activate_valid <= shiftout(sti_valid_delay_reg);
	activate_data <= rom_q_sig when(actfunc_type(2) = '1') else af_result_reg;
	activate_eol <= shiftout(sti_eol_delay_reg);
	activate_eof <= shiftout(sti_eof_delay_reg);


end RTL;
