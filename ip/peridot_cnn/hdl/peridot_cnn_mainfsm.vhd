-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - main FSM
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/08/30 -> 2020/09/23
--            : 2020/09/23 (FIXED)
--
--     UPDATE : 2023/11/30 -> 2024/03/11
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

-- ・実装toto
-- [X] レジスタ場所入れ替え 
-- [X] 全結合パラメータ追加 
-- [X] アンプーリング機能をカーネル側処理に変更 
-- [X] 内蔵バッファ有効信号の自動切り替え 
-- [X] シリアライズパラメータ追加 
-- [X] 全結合バイアス項追加 
-- [X] 乗算モードと一時停止パラメータ追加 
--
-- ・検証todo
-- [X] init信号アボート 
-- [X] エラーインジェクションテスト → 確認(ただし詳細は全体テストが必要) 
-- [X] フィルター数ループ動作の確認 (カーネル数1,4で確認) 
-- [X] カーネル数変更時の動作 
-- [X] 境界条件1:フィルター数1、チャネル1の場合 
-- [X] 境界条件2:チャネルの最終ループがちょうどカーネル数の場合 
-- [X] バス幅変更時の動作 
-- [X] 一時停止パラメータの動作 
--
-- ・リソース概算 
-- 420LE + 0DSP (32bit幅,1カーネル時,内蔵バッファなし)
-- 480LE + 2DSP (32bit幅,4カーネル時,内蔵バッファ1k)
-- 450LE + 2DSP (256bit幅,8カーネル時,内蔵バッファ4k)


-- pd_address_top : デスクリプタの先頭アドレス (32バイト境界のみ指定可能) 
-- pd_address_cur : 現在処理中のフィルターパラメーター先頭 


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

entity peridot_cnn_mainfsm is
	generic(
		MAXKERNEL_NUMBER		: integer := 4;		-- カーネルインスタンス数 (1～8)
		FCFUNC_INSTANCE_TYPE	: integer := 1;		-- 全結合実装タイプ (0:なし / 1:INT8xINT16)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		INTRBUFFER_POW2_NUMBER	: integer := 10;	-- 内蔵バッファのサイズ (0:なし / 10:1kワード / 12:4kワード / 14:16kワード)

		-- SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
		test_fs_loaddone	: out std_logic;
		test_block_finally	: out std_logic;
		test_block_done		: out std_logic;
		test_update_cnum	: out std_logic;


		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: in  std_logic := '0';
		start			: in  std_logic;
		ready			: out std_logic;
		error			: out std_logic;						-- どれかerrorがアサートされたらreadyには戻らない 
		finally			: out std_logic;
		pause			: out std_logic;
		restart			: in  std_logic := '1';					-- restart応答はfinallyアサートでクリアすること 
		pd_address_top	: in  std_logic_vector(31 downto 0);
		pd_address_cur	: out std_logic_vector(31 downto 0);

		read_request	: out std_logic;
		read_complete	: out std_logic;
		read_address	: out std_logic_vector(31 downto 0);
		read_burstcount	: out std_logic_vector(3+(8-DATABUS_POW2_NUMBER) downto 0);
		read_datavalid	: in  std_logic;
		read_data		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);

		kernel_ready	: in  std_logic;
		kernel_error	: in  std_logic;
		conv_x_size		: out std_logic_vector(15 downto 0);
		conv_y_size		: out std_logic_vector(15 downto 0);
		padding_mode	: out std_logic_vector(1 downto 0);
		bytepacking		: out std_logic;
		param_valid		: out std_logic;
		param_data		: out std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);

		accum_ready		: in  std_logic;
		accum_start		: out std_logic;
		accum_error		: in  std_logic;
		firstchunk		: out std_logic;
		lastchunk		: out std_logic;
		intrbuff_ena	: out std_logic;
		multcalc_ena	: out std_logic;
		bias_data		: out std_logic_vector(31 downto 0);
		noise_type		: out std_logic_vector(1 downto 0);
		noise_gain		: out std_logic_vector(17 downto 0);
		rd_address_top	: out std_logic_vector(31 downto 0);
		rd_totalnum		: out std_logic_vector(22 downto 0);
		kernel_ena		: out std_logic_vector(MAXKERNEL_NUMBER-1 downto 0);

		fc_ready		: in  std_logic := '1';
		fc_start		: out std_logic;
		fc_error		: in  std_logic := '0';
		fc_calc_mode	: out std_logic_vector(1 downto 0);
		fc_channel_num	: out std_logic_vector(12 downto 0);
		fc_data_num		: out std_logic_vector(17 downto 0);
		vectordata_top	: out std_logic_vector(31 downto 0);
		weightdata_top	: out std_logic_vector(31 downto 0);
		matmulbias		: out std_logic_vector(31 downto 0);
		fc_processing	: out std_logic;

		writeback_ready	: in  std_logic;
		writeback_start	: out std_logic;
		eof_ignore		: out std_logic;
		activation_ena	: out std_logic;
		actfunc_type	: out std_logic_vector(2 downto 0);
		decimal_pos		: out std_logic_vector(1 downto 0);
		pooling_mode	: out std_logic_vector(1 downto 0);
		wb_address_top	: out std_logic_vector(31 downto 0);
		wb_totalnum		: in  std_logic_vector(22 downto 0)
	);
end peridot_cnn_mainfsm;

architecture RTL of peridot_cnn_mainfsm is
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
	constant PARAM_BLOCK_SIZE	: integer := 8;			-- パラメータデスクリプタのビット長(256bit=32bit×8ワードで固定)
	constant REGLOAD_WAIT_CYCLE	: integer := 1;			-- フィルターパラメータ読み込み後のフラグ確定待ちサイクル(1～) 
	constant ARBITER_WAIT_CYCLE	: integer := 4;			-- カーネルパラメータ読み込み後のアービタのリードフュージョン判定待ちサイクル(1～) 
	constant ALIGN_ADDR_WIDTH	: integer := DATABUS_POW2_NUMBER-3;		-- ワード境界のアドレスビット幅 
	constant BURST_MINLENGTH	: integer := 2**(PARAM_BLOCK_SIZE-DATABUS_POW2_NUMBER);						-- フィルターパラメータバースト長 
	constant BURST_MAXLENGTH	: integer := MAXKERNEL_NUMBER * 2**(PARAM_BLOCK_SIZE-DATABUS_POW2_NUMBER);	-- カーネルパラメータバースト長 

	-- パラメータヘッダ識別子 
	constant PARAM_CODE_FILTER	: std_logic_vector(2 downto 0) := "100";	-- フィルターパラメータ先頭 
	constant PARAM_CODE_FLAT	: std_logic_vector(2 downto 0) := "101";	-- シリアライズパラメータ先頭 
	constant PARAM_CODE_FC		: std_logic_vector(2 downto 0) := "110";	-- 全結合パラメータ先頭 
	constant PARAM_CODE_PAUSE	: std_logic_vector(2 downto 0) := "111";	-- 一時停止パラメータ先頭 
	constant PARAM_CODE_KERNEL	: std_logic_vector(2 downto 0) := "001";	-- カーネルパラメータ先頭 

	constant PAUSE_OPCODE_EXIT	: std_logic_vector(2 downto 0) := "000";	-- 終了オペコード 
	constant PAUSE_OPCODE_IRQ	: std_logic_vector(2 downto 0) := "001";	-- CPU割り込みリクエスト 


	-- 全体制御 
	signal init_sig				: std_logic;
	signal start_sig			: std_logic;
	signal ready_sig			: std_logic;
	signal error_deviated_reg	: std_logic;

	-- メインステートマシン 
	type DEF_STATE_MAIN is (MAINIDLE, MAINSTART, MAINLOAD, MAINFINALLY, MAINPAUSEREQ,
							MAINFCSTART, MAINFCLOAD, MAINFCPROCESSING,
							MAINKERNELSTART, MAINKERNELLOAD, MAINPROCESSING);
	signal state_main : DEF_STATE_MAIN;
	signal ready_reg			: std_logic;
	signal exit_reg				: std_logic;
	signal module_start_reg		: std_logic;
	signal lastchunk_reg		: std_logic;
	signal firstchunk_reg		: std_logic;
	signal module_ready_sig		: std_logic;
	signal finally_sig			: std_logic;
	signal pause_req_sig		: std_logic;
	signal restart_ack_sig		: std_logic;
	signal fsparam_req_sig		: std_logic;
	signal kernelparam_req_sig	: std_logic;
	signal update_cnum_sig		: std_logic;
	signal kernel_ena_sig		: std_logic_vector(7 downto 0);
	signal kernel_ena_reg		: std_logic_vector(kernel_ena'range);
	signal wb_ready_sig			: std_logic;

	-- デスクリプタ読み込み制御 
	type DEF_STATE_MEMREAD is (READIDLE, READDATA, READDONE);
	signal state_memread : DEF_STATE_MEMREAD;
	signal arbiter_wait_counter	: integer range 0 to ARBITER_WAIT_CYCLE-1;
	signal memread_ready_sig	: std_logic;
	signal read_request_reg		: std_logic;
	signal read_complete_sig	: std_logic;
	signal pd_address_reg		: std_logic_vector(31 downto ALIGN_ADDR_WIDTH);
	signal cur_address_reg		: std_logic_vector(31 downto 5);
	signal pd_datanum_reg		: std_logic_vector(read_burstcount'range);
	signal pd_datanum_sig		: std_logic_vector(pd_datanum_reg'range);
	signal read_data_sig		: std_logic_vector(param_data'range);
	signal read_datavalid_sig	: std_logic;

	-- フィルターパラメータ読み込みブロック 
	signal fsparam_init_sig		: std_logic;
	signal fsparam_bit_sig		: std_logic_vector(2**PARAM_BLOCK_SIZE-1 downto 0);
	signal fsparam_latchena_reg	: std_logic_vector(2**(PARAM_BLOCK_SIZE-DATABUS_POW2_NUMBER) downto 0);
	signal fsparam_loaddone_sig	: std_logic;
	signal reg0_latch_sig		: std_logic;
	signal reg1_latch_sig		: std_logic;
	signal reg2_latch_sig		: std_logic;
	signal reg3_latch_sig		: std_logic;
	signal reg4_latch_sig		: std_logic;
	signal reg5_latch_sig		: std_logic;

	signal flat_processing_reg	: std_logic;
	signal fc_processing_reg	: std_logic;
	signal pause_processing_reg	: std_logic;
	signal channel_num_reg		: std_logic_vector(12 downto 0);
	signal padding_mode_reg		: std_logic_vector(1 downto 0);
	signal bytepacking_reg		: std_logic;
	signal multcalc_ena_reg		: std_logic;
	signal decimal_pos_reg		: std_logic_vector(1 downto 0);
	signal actfunc_type_reg		: std_logic_vector(2 downto 0);
	signal pooling_mode_reg		: std_logic_vector(1 downto 0);
	signal conv_size_reg		: std_logic_vector(31 downto 0);	-- 上位16bit:CONV_Y_SIZE, 下位16bit:CONV_X_SIZE
	signal bias_data_reg		: std_logic_vector(31 downto 0);
	signal noise_type_reg		: std_logic_vector(1 downto 0);
	signal noise_gain_reg		: std_logic_vector(17 downto 0);
	signal wb_address_reg		: std_logic_vector(31 downto 5);
	signal rd_address_reg		: std_logic_vector(31 downto 5);
	signal pause_opcode_sig		: std_logic_vector(2 downto 0);
	signal intrbuff_ena_reg		: std_logic;
	signal intrbuff_permit_reg	: std_logic;
	signal intrbuff_permit_sig	: std_logic;
	signal ib_multans_sig		: std_logic_vector(31 downto 0);

	signal totaldatanum_sig		: std_logic_vector(22 downto 0);
	signal block_finally_sig	: std_logic;
	signal block_done_sig		: std_logic;

begin

	-- テスト記述 

	test_fs_loaddone <= fsparam_loaddone_sig;
	test_block_finally <= block_finally_sig;
	test_block_done <= block_done_sig;
	test_update_cnum <= update_cnum_sig;


	-- パラメータ範囲チェック 

	assert (MAXKERNEL_NUMBER >= 1 and MAXKERNEL_NUMBER <= 8)
		report "MAXKERNEL_NUMBER is out of range." severity FAILURE;

	assert (DATABUS_POW2_NUMBER >= 5 and DATABUS_POW2_NUMBER <= 8)
		report "DATABUS_POW2_NUMBER is out of range." severity FAILURE;

	assert (read_burstcount'length <= 11)
		report "Avalon-MM burstcount port width is out of range. Equal or less than 11." severity FAILURE;



	----------------------------------------------------------------------
	-- モジュール全体制御 
	----------------------------------------------------------------------

	init_sig <= init;
	ready <= ready_sig;
	error <= error_deviated_reg;
	finally <= finally_sig;
	pause <= pause_req_sig;
	pd_address_cur <= cur_address_reg & "00000";


	-- 開始信号と終了信号生成 

	ready_sig <= ready_reg when is_false(error_deviated_reg) else '0';
	start_sig <= start when is_true(ready_sig) else '0';
	restart_ack_sig <= restart;


	-- 他のモジュールから復帰不能なエラーが報告されている 

	process (clk, reset) begin
		if is_true(reset) then
			error_deviated_reg <= '0';

		elsif rising_edge(clk) then
			if is_true(kernel_error) or is_true(accum_error) or is_true(fc_error) then
				error_deviated_reg <= '1';
			end if;

		end if;
	end process;



	----------------------------------------------------------------------
	-- メインステートマシン 
	----------------------------------------------------------------------

	finally_sig <= '1' when(state_main = MAINFINALLY) else '0';
	pause_req_sig <= '1' when(state_main = MAINPAUSEREQ) else '0';


	-- メインステート制御 

	module_ready_sig <= '1' when is_true(kernel_ready) and is_true(accum_ready) and is_true(fc_ready) and is_true(wb_ready_sig) else '0';

	fsparam_req_sig <= '1' when(state_main = MAINLOAD) else '0';
	kernelparam_req_sig <= '1' when(state_main = MAINKERNELLOAD) else '0';
	update_cnum_sig <= read_complete_sig when(state_main = MAINKERNELLOAD) else '0';


	process (clk, reset) begin
		if is_true(reset) then
			state_main <= MAINIDLE;
			ready_reg <= '1';
			exit_reg <= '0';
			module_start_reg <= '0';

		elsif rising_edge(clk) then
			if is_true(init_sig) then
				state_main <= MAINIDLE;
				ready_reg <= module_ready_sig and memread_ready_sig;
				exit_reg <= '0';
				module_start_reg <= '0';

			else
				case state_main is

				-- 開始信号を待つ 
				when MAINIDLE =>
					if is_true(start_sig) and is_true(module_ready_sig) then
						state_main <= MAINSTART;
						ready_reg <= '0';
					end if;

				-- フィルターパラメータのロード 
				when MAINSTART =>
					state_main <= MAINLOAD;
					firstchunk_reg <= '1';

				when MAINLOAD =>
					if is_true(read_complete_sig) then
						if is_true(pause_processing_reg) then
							if (pause_opcode_sig = PAUSE_OPCODE_EXIT) then
								state_main <= MAINFINALLY;	-- 終了オペコードの場合 
								exit_reg <= '1';
							else
								state_main <= MAINPAUSEREQ;	-- CPU割り込みオペコードの場合 
							end if;
						elsif is_true(fc_processing_reg) then
							if (FCFUNC_INSTANCE_TYPE > 0) then
								state_main <= MAINFCSTART;	-- 全結合パラメータの場合 
							else
								state_main <= MAINPAUSEREQ;	-- FC未実装の場合 
							end if;
						else
							state_main <= MAINKERNELSTART;
						end if;
					end if;


				-- 一時停止処理 
				when MAINPAUSEREQ =>
					if is_true(restart_ack_sig) then		-- CPUから処理が委譲されたら再開 
						state_main <= MAINFINALLY;
					end if;

				-- 全結合演算の処理 
				when MAINFCSTART =>
					state_main <= MAINFCLOAD;
					module_start_reg <= '1';
					lastchunk_reg <= '1';					-- 全結合の場合は常に最終ループ扱い 

				when MAINFCLOAD =>
					if is_false(module_ready_sig) then		-- 処理開始を確認 
						state_main <= MAINFCPROCESSING;
					end if;

					module_start_reg <= '0';

				when MAINFCPROCESSING =>
					if is_true(module_ready_sig) then		-- エラー報告時はここのステートでホールドする 
						state_main <= MAINFINALLY;
						firstchunk_reg <= '0';
					end if;

				-- カーネルループ処理 
				when MAINKERNELSTART =>
					state_main <= MAINKERNELLOAD;
					module_start_reg <= '1';

					if is_true(block_finally_sig) then		-- 最終ループならカーネルdoneマスクを設定する 
						kernel_ena_reg <= kernel_ena_sig(kernel_ena_reg'range);
						lastchunk_reg <= '1';
					else
						if is_true(flat_processing_reg) then
							kernel_ena_reg <= (0=>'1', others=>'0');	-- シリアライズの場合は1カーネル固定 
						else
							kernel_ena_reg <= (others=>'1');			-- それ以外はインスタンスの全カーネル 
						end if;

						lastchunk_reg <= '0';
					end if;

				when MAINKERNELLOAD =>
					if is_true(read_complete_sig) then
						state_main <= MAINPROCESSING;
					end if;

					module_start_reg <= '0';

				when MAINPROCESSING =>
					if is_true(module_ready_sig) then		-- エラー報告時はここのステートでホールドする 
						if is_true(block_done_sig) then
							state_main <= MAINFINALLY;
						else
							state_main <= MAINKERNELSTART;
						end if;

						firstchunk_reg <= '0';
					end if;


				-- 終了処置 
				when MAINFINALLY =>
					if is_true(exit_reg) then				-- 終了オペコードを検出していたら終了 
						state_main <= MAINIDLE;
						ready_reg <= '1';
						exit_reg <= '0';
					else
						state_main <= MAINSTART;
					end if;

				when others =>
				end case;

			end if;
		end if;
	end process;


	-- 各モジュールへの制御信号 

		-- 全結合のときはフィルター累算開始信号をマスク 
	accum_start <= '0' when is_true(fc_processing_reg) else module_start_reg;

		-- シリアライズのときはフィルター累算をパススルー (常にバイアス加算処理) 
	firstchunk <= '1' when is_true(flat_processing_reg) else firstchunk_reg;
	lastchunk <= '1' when is_true(flat_processing_reg) else lastchunk_reg;
	kernel_ena <= kernel_ena_reg;

		-- 全結合処理開始信号 
	fc_start <= module_start_reg when is_true(fc_processing_reg) else '0';

		-- 内蔵バッファモードのときは最終ループ以外は書き戻し開始信号をマスク (全結合のときはintrbuff_permit_sigは必ずネゲート) 
		-- シリアライズのときは最初のループ以外は書き戻し開始信号をマスク 
	writeback_start <=
			'0' when is_true(intrbuff_permit_sig) and is_false(lastchunk_reg) else
			'0' when is_true(flat_processing_reg) and is_false(firstchunk_reg) else
			module_start_reg;

		-- シリアライズのときは最後のループ以外はReady信号を無視 
	wb_ready_sig <= '1' when is_true(flat_processing_reg) and is_false(lastchunk_reg) else writeback_ready;

		-- シリアライズのときは最後のループ以外はeof信号を無視 
	eof_ignore <= '1' when is_true(flat_processing_reg) and is_false(lastchunk_reg) else '0';

		-- バイトパッキングモード(全結合ではaf_throughに読み替え)のときは活性化信号をマスク (中間値書き戻しと同じ処理) 
		-- シリアライズのときは常に活性化信号をアサート 
	activation_ena <=
			'0' when is_true(bytepacking_reg) else
			'1' when is_true(flat_processing_reg) else
			lastchunk_reg;



	----------------------------------------------------------------------
	-- デスクリプタ読み込み制御 
	----------------------------------------------------------------------

	memread_ready_sig <= '1' when(state_memread = READIDLE) else '0';


	-- メモリリードリクエスト

	read_request <= read_request_reg;
	read_complete <= read_complete_sig;
	read_address <= pd_address_reg(31 downto ALIGN_ADDR_WIDTH) & repbit('0', ALIGN_ADDR_WIDTH);
	read_burstcount <= pd_datanum_reg;
	read_data_sig <= read_data;
	read_datavalid_sig <= read_datavalid;

	param_data <= read_data_sig;
	param_valid <= read_datavalid_sig when is_true(fsparam_loaddone_sig) else '0';	-- カーネルパラメータのデータ到着で動作開始 


	-- バーストリード制御 

	read_complete_sig <= '1' when(state_memread = READDONE and arbiter_wait_counter = 0) else '0';

	process (clk, reset) begin
		if is_true(reset) then
			state_memread <= READIDLE;
			read_request_reg <= '0';

		elsif rising_edge(clk) then
			case state_memread is

			-- 開始信号を待つ 
			when READIDLE =>
					-- 読み出し先頭アドレスのロード 
				if is_true(start_sig) then
					pd_address_reg <= pd_address_top(pd_address_reg'range);

				-- フィルターパラメータの読み込みをリクエスト 
				elsif is_true(fsparam_req_sig) then
					state_memread <= READDATA;
					cur_address_reg <= pd_address_reg(cur_address_reg'range);
					arbiter_wait_counter <= REGLOAD_WAIT_CYCLE-1;
					read_request_reg <= '1';
					pd_datanum_reg <= to_vector(BURST_MINLENGTH, pd_datanum_reg'length);

				-- カーネルパラメータの読み込みをリクエスト 
				elsif is_true(kernelparam_req_sig) then
					state_memread <= READDATA;
					arbiter_wait_counter <= ARBITER_WAIT_CYCLE-1;
					read_request_reg <= '1';

					if is_true(block_finally_sig) then
						pd_datanum_reg <= pd_datanum_sig;
					else
						if is_true(flat_processing_reg) then
							pd_datanum_reg <= to_vector(BURST_MINLENGTH, pd_datanum_reg'length);	-- シリアライズ時は1カーネルずつ 
						else
							pd_datanum_reg <= to_vector(BURST_MAXLENGTH, pd_datanum_reg'length);
						end if;
					end if;
				end if;

			when READDATA =>
				-- データが送られてきたら処理 
				if is_true(read_datavalid_sig) then
					if (pd_datanum_reg = 1) then
						state_memread <= READDONE;
					end if;

					read_request_reg <= '0';
					pd_address_reg <= pd_address_reg + 1;	-- アドレスを更新 
					pd_datanum_reg <= pd_datanum_reg - 1;
				end if;

			when READDONE =>
				if (arbiter_wait_counter = 0) then
					state_memread <= READIDLE;
				else
					arbiter_wait_counter <= arbiter_wait_counter - 1;
				end if;

			end case;
		end if;
	end process;



	----------------------------------------------------------------------
	-- フィルターパラメータ読み込み 
	----------------------------------------------------------------------

	fsparam_init_sig <= init_sig when is_true(memread_ready_sig) else '0';
	fsparam_loaddone_sig <= fsparam_latchena_reg(fsparam_latchena_reg'left) when is_false(fc_processing_reg) and is_false(pause_processing_reg) else '0';


	-- バス幅変換 

	gen_param32 : if (DATABUS_POW2_NUMBER = 5) generate
		pd_datanum_sig <= slice(channel_num_reg, pd_datanum_sig'length-3, 0) & repbit('0',3);
		fsparam_bit_sig <= read_data_sig & read_data_sig & read_data_sig & read_data_sig &
						read_data_sig & read_data_sig & read_data_sig & read_data_sig;
		reg0_latch_sig <= fsparam_latchena_reg(0);
		reg1_latch_sig <= fsparam_latchena_reg(1);
		reg2_latch_sig <= fsparam_latchena_reg(2);
		reg3_latch_sig <= fsparam_latchena_reg(3);
		reg4_latch_sig <= fsparam_latchena_reg(4);
		reg5_latch_sig <= fsparam_latchena_reg(5);
	end generate;

	gen_param64 : if (DATABUS_POW2_NUMBER = 6) generate
		pd_datanum_sig <= slice(channel_num_reg, pd_datanum_sig'length-2, 0) & repbit('0',2);
		fsparam_bit_sig <= read_data_sig & read_data_sig & read_data_sig & read_data_sig;
		reg0_latch_sig <= fsparam_latchena_reg(0);
		reg1_latch_sig <= fsparam_latchena_reg(0);
		reg2_latch_sig <= fsparam_latchena_reg(1);
		reg3_latch_sig <= fsparam_latchena_reg(1);
		reg4_latch_sig <= fsparam_latchena_reg(2);
		reg5_latch_sig <= fsparam_latchena_reg(2);
	end generate;

	gen_param128 : if (DATABUS_POW2_NUMBER = 7) generate
		pd_datanum_sig <= slice(channel_num_reg, pd_datanum_sig'length-1, 0) & repbit('0',1);
		fsparam_bit_sig <= read_data_sig & read_data_sig;
		reg0_latch_sig <= fsparam_latchena_reg(0);
		reg1_latch_sig <= fsparam_latchena_reg(0);
		reg2_latch_sig <= fsparam_latchena_reg(0);
		reg3_latch_sig <= fsparam_latchena_reg(0);
		reg4_latch_sig <= fsparam_latchena_reg(1);
		reg5_latch_sig <= fsparam_latchena_reg(1);
	end generate;

	gen_param256 : if (DATABUS_POW2_NUMBER = 8) generate
		pd_datanum_sig <= slice(channel_num_reg, pd_datanum_sig'length, 0);
		fsparam_bit_sig <= read_data_sig;
		reg0_latch_sig <= fsparam_latchena_reg(0);
		reg1_latch_sig <= fsparam_latchena_reg(0);
		reg2_latch_sig <= fsparam_latchena_reg(0);
		reg3_latch_sig <= fsparam_latchena_reg(0);
		reg4_latch_sig <= fsparam_latchena_reg(0);
		reg5_latch_sig <= fsparam_latchena_reg(0);
	end generate;


	-- レジスタラッチと更新 

	process (clk, reset) begin
		if is_true(reset) then
			fsparam_latchena_reg <= (0=>'1', others=>'0');

		elsif rising_edge(clk) then
			-- フィルターパラメータレジスタのロード 
			if is_true(fsparam_init_sig) or is_true(finally_sig) then
				fsparam_latchena_reg <= (0=>'1', others=>'0');
				flat_processing_reg <= '0';
				fc_processing_reg <= '0';
				pause_processing_reg <= '0';
			else
				if is_true(read_datavalid_sig) and is_false(fsparam_loaddone_sig) then

					-- レジスタラッチ選択信号 (シフトレジスタ)
					fsparam_latchena_reg <= shiftin(fsparam_latchena_reg, '0');

					-- reg0:フィルター動作設定のロード 
					if is_true(reg0_latch_sig) then
						if (slice(fsparam_bit_sig, 3, 0*32+29) = PARAM_CODE_FLAT) then
							flat_processing_reg <= '1';
						else
							flat_processing_reg <= '0';
						end if;

						if (slice(fsparam_bit_sig, 3, 0*32+29) = PARAM_CODE_FC) then
							fc_processing_reg <= '1';
						else
							fc_processing_reg <= '0';
						end if;

						if (slice(fsparam_bit_sig, 3, 0*32+29) = PARAM_CODE_PAUSE) then
							pause_processing_reg <= '1';
						else
							pause_processing_reg <= '0';
						end if;

						pooling_mode_reg	<= slice(fsparam_bit_sig,  2, 0*32+26);	-- FC時未使用(00にマスクされる)
						actfunc_type_reg	<= slice(fsparam_bit_sig,  3, 0*32+23);
						decimal_pos_reg		<= slice(fsparam_bit_sig,  2, 0*32+21);
						bytepacking_reg		<= fsparam_bit_sig(0*32+ 20);			-- FC時はaf_through 
						multcalc_ena_reg	<= fsparam_bit_sig(0*32+ 19);
						padding_mode_reg	<= slice(fsparam_bit_sig,  2, 0*32+16);	-- FC時はfc_calc_mode 
						channel_num_reg		<= slice(fsparam_bit_sig, 13, 0*32+ 0);	-- FC時はfc_channel_num, PAUSE時はopcodeとusercode 
					end if;

					-- reg1:結果書き戻し先アドレスのロード 
					if is_true(reg1_latch_sig) then
						wb_address_reg <= slice(fsparam_bit_sig, 27, 1*32+ 5);
					end if;

					-- reg2:アキュムレーターバッファアドレスのロード 
					if is_true(reg2_latch_sig) then
						rd_address_reg		<= slice(fsparam_bit_sig, 27, 2*32+ 5);	-- FC時は重みデータ先頭アドレス 
						intrbuff_ena_reg	<= fsparam_bit_sig(2*32+ 0);			-- FC時は重みデータ相対アドレス指定 
					end if;

					-- reg3:フィルターバイアス値のロード 
					if is_true(reg3_latch_sig) then
						bias_data_reg <= slice(fsparam_bit_sig, 32, 3*32+ 0);		-- FC時は積和行列バイアス値 
					end if;

					-- reg4:フィルター乱数項設定値のロード 
					if is_true(reg4_latch_sig) then
						noise_type_reg <= slice(fsparam_bit_sig,  2, 4*32+24);		-- FC時未使用 
						noise_gain_reg <= slice(fsparam_bit_sig, 18, 4*32+ 0);		-- FC時は入力データ数 
					end if;

					-- reg5:カーネル処理サイズのロード 
					if is_true(reg5_latch_sig) then
						conv_size_reg <= slice(fsparam_bit_sig, 32, 5*32+ 0);		-- FC時は入力データ先頭アドレス 
					end if;


				-- 残りチャネル数の更新 (カーネルパラメータの場合のみ)
				elsif is_true(update_cnum_sig) then
					if is_true(block_finally_sig) then
						channel_num_reg <= (others=>'0');
					else
						if is_true(flat_processing_reg) then
							channel_num_reg <= channel_num_reg - 1;
						else
							channel_num_reg <= channel_num_reg - MAXKERNEL_NUMBER;
						end if;
					end if;
				end if;

			end if;
		end if;
	end process;

	pause_opcode_sig <= slice(channel_num_reg, pause_opcode_sig'length, 8);

	block_finally_sig <= '1' when(
			(is_true(flat_processing_reg) and channel_num_reg = 1) or 
			(is_false(flat_processing_reg) and channel_num_reg <= MAXKERNEL_NUMBER)) else '0';
	block_done_sig <= '1' when(channel_num_reg = 0) else '0';

	with channel_num_reg(2 downto 0) select kernel_ena_sig <=	-- 最終ループ時のカーネルイネーブル 
		"00000001"	when "001",
		"00000011"	when "010",
		"00000111"	when "011",
		"00001111"	when "100",
		"00011111"	when "101",
		"00111111"	when "110",
		"01111111"	when "111",
		(others=>'X') when others;


	-- 内蔵バッファ有効の判別 (conv_x,conv_yレジスタロードから2クロック後に確定,start信号のタイミングに注意)

	gen_becheck : if (INTRBUFFER_POW2_NUMBER > 0) generate
		u : lpm_mult
		generic map(
			lpm_type			=> "LPM_MULT",
			lpm_representation	=> "UNSIGNED",
			lpm_pipeline		=> 1,
			lpm_widtha			=> 16,
			lpm_widthb			=> 16,
			lpm_widthp			=> 32
		)
		port map(
			clock	=> clk,
			dataa	=> conv_size_reg(15 downto 0),		-- CONV_X_SIZE
			datab	=> conv_size_reg(31 downto 16),		-- CONV_Y_SIZE
			result	=> ib_multans_sig
		);

		process (clk) begin
			if rising_edge(clk) then
					-- データサイズが 2^INTRBUFFER_POW2_NUMBER 以下のとき 
				if ((ib_multans_sig(24 downto INTRBUFFER_POW2_NUMBER) = 0) or
					-- データサイズが 2^INTRBUFFER_POW2_NUMBER のとき 
					(ib_multans_sig(24 downto INTRBUFFER_POW2_NUMBER+1) = 0 and ib_multans_sig(INTRBUFFER_POW2_NUMBER-1 downto 0) = 0)
				) then
					intrbuff_permit_reg <= intrbuff_ena_reg;
				else
					intrbuff_permit_reg <= '0';
				end if;
			end if;
		end process;

		intrbuff_permit_sig <= intrbuff_permit_reg when is_false(fc_processing_reg) else '0';	-- 全結合時は必ずネゲートさせる 
	end generate;
	gen_nobecheck : if (INTRBUFFER_POW2_NUMBER = 0) generate
		intrbuff_permit_sig <= '0';
	end generate;


	-- 各モジュールへパラメータ出力 

	conv_x_size <= conv_size_reg(15 downto 0);
	conv_y_size <= conv_size_reg(31 downto 16);
	padding_mode <= padding_mode_reg;
	bytepacking <= bytepacking_reg;

	intrbuff_ena <= intrbuff_permit_sig;
	multcalc_ena <= multcalc_ena_reg;
	bias_data <= bias_data_reg;
	noise_type <= noise_type_reg;
	noise_gain <= noise_gain_reg;
	rd_address_top <= rd_address_reg & "00000";
	rd_totalnum <= totaldatanum_sig;	-- フィルター累算器の読み出しデータ数は一つ前の処理時の書き戻しデータ数 

	fc_calc_mode <= padding_mode_reg;							-- 全結合のときはレジスタを読み替える 
	fc_channel_num <= channel_num_reg;
	fc_data_num <= noise_gain_reg;								-- 全結合の場合はレジスタを読み替える 
	vectordata_top <= conv_size_reg(31 downto 5) & "00000";		-- 全結合の場合はレジスタを読み替える 
	weightdata_top <=
			rd_address_reg & "00000" when is_false(intrbuff_ena_reg) else	-- 全結合の場合はintrbuff_ena_regを相対アドレスフラグに読み替える 
			(cur_address_reg + rd_address_reg) & "00000";

	matmulbias <= bias_data_reg;
	fc_processing <= fc_processing_reg;

	actfunc_type <= actfunc_type_reg;
	decimal_pos <= decimal_pos_reg;
	pooling_mode <= "00" when is_true(fc_processing_reg) else pooling_mode_reg;	-- 全結合の場合はプーリング設定をマスク 
	wb_address_top <=					-- 最終ループ以外では中間値バッファアドレスを出力 
			wb_address_reg & "00000" when is_true(lastchunk_reg) else
			rd_address_reg & "00000";

	totaldatanum_sig <= wb_totalnum;



end RTL;
