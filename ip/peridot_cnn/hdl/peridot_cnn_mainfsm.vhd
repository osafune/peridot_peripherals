-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - main FSM
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/08/30 -> 2020/09/23
--            : 2020/09/23 (FIXED)
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

-- ・実装残り
-- ■ カーネルパラメータ読み込み後に2クロックのウェイト挿入(リードフュージョン判定の時間待ち用)

-- ・検証残り
-- ■ init信号アボート 
-- ■ エラーインジェクションテスト → 確認(ただし詳細は全体テストが必要) 
-- ■ フィルターセットループ動作の確認 (カーネル数1,4で確認) 
-- ■ カーネル数変更時の動作 
-- ■ 境界条件1:フィルターセット1、チャネル1の場合 
-- ■ 境界条件2:チャネルの最終ループがちょうどカーネル数の場合 
-- ■ バス幅変更時の動作 

-- ・リソース概算
-- 330LE (32bit幅,1カーネル時)
-- 340LE (32bit幅,4カーネル時)
-- 320LE (256bit幅,8カーネル時)

-- pd_address_top : デスクリプタの先頭アドレス (32バイト境界のみ指定可能) 
-- pd_setnumber : デスクリプタの処理セット数 (0を指定した場合の動作は今は不定) 


-- VHDL 1993 / IEEE 1076-1993
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_misc.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity peridot_cnn_mainfsm is
	generic(
		MAXKERNEL_NUMBER		: integer := 4;		-- カーネルインスタンス数 (1～8)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)

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
		pd_address_top	: in  std_logic_vector(31 downto 0);
		pd_setnumber	: in  std_logic_vector(15 downto 0);

		read_request	: out std_logic;
		read_complete	: out std_logic;
		read_address	: out std_logic_vector(31 downto 0);
		read_burstcount	: out std_logic_vector(3+(8-DATABUS_POW2_NUMBER) downto 0);
		read_data		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		read_datavalid	: in  std_logic;

		kernel_ready	: in  std_logic;
		kernel_error	: in  std_logic;
		conv_x_size		: out std_logic_vector(11 downto 0);
		conv_y_size		: out std_logic_vector(11 downto 0);
		padding_mode	: out std_logic_vector(1 downto 0);
		unpooling_mode	: out std_logic_vector(1 downto 0);
		precision		: out std_logic;
		decimal_pos		: out std_logic_vector(1 downto 0);
		param_data		: out std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		param_valid		: out std_logic;

		accum_ready		: in  std_logic;
		accum_start		: out std_logic;
		accum_error		: in  std_logic;
		biasinit_ena	: out std_logic;
		bias_data		: out std_logic_vector(31 downto 0);
		rd_address_top	: out std_logic_vector(31 downto 0);
		rd_totalnum		: out std_logic_vector(22 downto 0);
		kernel_ena		: out std_logic_vector(MAXKERNEL_NUMBER-1 downto 0);

		writeback_ready	: in  std_logic;
		writeback_start	: out std_logic;
		relu_ena		: out std_logic;
		pooling_ena		: out std_logic;
		pooling_mode	: out std_logic_vector(1 downto 0);
		wb_address_top	: out std_logic_vector(31 downto 0);
		wb_totalnum		: in  std_logic_vector(22 downto 0)
	);
end peridot_cnn_mainfsm;

architecture RTL of peridot_cnn_mainfsm is
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
	constant PARAM_BLOCK_SIZE	: integer := 8;			-- パラメータデスクリプタのワード数(32bit×8ワードで固定)
	constant ARBITER_WAIT_CYCLE	: integer := 4;			-- アービタのリードフュージョン判定待ちサイクル 
	constant ALIGN_ADDR_WIDTH	: integer := DATABUS_POW2_NUMBER-3;		-- ワード境界のアドレスビット幅 
	constant BURST_MINLENGTH	: integer := 2**(PARAM_BLOCK_SIZE-DATABUS_POW2_NUMBER);						-- フィルターセットバースト長 
	constant BURST_MAXLENGTH	: integer := MAXKERNEL_NUMBER * 2**(PARAM_BLOCK_SIZE-DATABUS_POW2_NUMBER);	-- カーネルパラメータバースト長 


	-- 全体制御 
	signal init_sig				: std_logic;
	signal start_sig			: std_logic;
	signal ready_sig			: std_logic;
	signal error_deviated_reg	: std_logic;

	-- メインステートマシン 
	type DEF_STATE_MAIN is (MAINIDLE, MAINSTART, MAINLOAD, MAINKERNELSTART, MAINKERNELLOAD, MAINPROCESSING, MAINFINALLY);
	signal state_main : DEF_STATE_MAIN;
	signal ready_reg			: std_logic;
	signal setnumber_reg		: std_logic_vector(pd_setnumber'range);
	signal module_start_reg		: std_logic;
	signal do_activation_reg	: std_logic;
	signal do_biasinit_reg		: std_logic;
	signal module_ready_sig		: std_logic;
	signal finally_sig			: std_logic;
	signal fsparam_req_sig		: std_logic;
	signal kernelparam_req_sig	: std_logic;
	signal update_cnum_sig		: std_logic;
	signal kernel_ena_sig		: std_logic_vector(7 downto 0);
	signal kernel_ena_reg		: std_logic_vector(kernel_ena'range);

	-- デスクリプタ読み込み制御 
	type DEF_STATE_MEMREAD is (READIDLE, READDATA, READDONE);
	signal state_memread : DEF_STATE_MEMREAD;
	signal arbiter_wait_counter	: integer range 0 to ARBITER_WAIT_CYCLE-1;
	signal memread_ready_sig	: std_logic;
	signal read_request_reg		: std_logic;
	signal read_complete_sig	: std_logic;
	signal pd_address_reg		: std_logic_vector(31 downto ALIGN_ADDR_WIDTH);
	signal pd_datanum_reg		: std_logic_vector(read_burstcount'range);
	signal pd_datanum_sig		: std_logic_vector(pd_datanum_reg'range);
	signal read_data_sig		: std_logic_vector(param_data'range);
	signal read_datavalid_sig	: std_logic;

	-- フィルターセットパラメータ読み込みブロック 
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

	signal channel_num_reg		: std_logic_vector(15 downto 0);
	signal conv_x_size_reg		: std_logic_vector(11 downto 0);
	signal conv_y_size_reg		: std_logic_vector(11 downto 0);
	signal padding_mode_reg		: std_logic_vector(1 downto 0);
	signal unpooling_mode_reg	: std_logic_vector(1 downto 0);
	signal precision_reg		: std_logic;
	signal decimal_pos_reg		: std_logic_vector(1 downto 0);
	signal bias_data_reg		: std_logic_vector(31 downto 0);
	signal buf_address_reg		: std_logic_vector(31 downto 0);
	signal wb_address_reg		: std_logic_vector(31 downto 0);
	signal pooling_ena_reg		: std_logic;
	signal pooling_mode_reg		: std_logic_vector(1 downto 0);
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
		report "MAXKERNEL_NUMBER is out of range.";

	assert (DATABUS_POW2_NUMBER >= 5 and DATABUS_POW2_NUMBER <= 8)
		report "DATABUS_POW2_NUMBER is out of range.";

	assert (read_burstcount'length <= 11)
		report "Avalon-MM burstcount port width is out of range. Less then 11.";



	----------------------------------------------------------------------
	-- モジュール全体制御 
	----------------------------------------------------------------------

	init_sig <= init;
	ready <= ready_sig;
	error <= error_deviated_reg;
	finally <= finally_sig;


	-- 開始信号と終了信号生成 

	ready_sig <= ready_reg when is_false(error_deviated_reg) else '0';
	start_sig <= start when is_true(ready_sig) else '0';


	-- 他のモジュールから復帰不能なエラーが報告されている 

	process (clk, reset) begin
		if is_true(reset) then
			error_deviated_reg <= '0';

		elsif rising_edge(clk) then
			if is_true(kernel_error) or is_true(accum_error) then
				error_deviated_reg <= '1';
			end if;

		end if;
	end process;



	----------------------------------------------------------------------
	-- メインステートマシン 
	----------------------------------------------------------------------

	finally_sig <= '1' when(state_main = MAINFINALLY) else '0';


	-- メインステート制御 

	module_ready_sig <= '1' when is_true(kernel_ready) and is_true(accum_ready) and is_true(writeback_ready) else '0';

	fsparam_req_sig <= '1' when(state_main = MAINLOAD) else '0';
	kernelparam_req_sig <= '1' when(state_main = MAINKERNELLOAD) else '0';
	update_cnum_sig <= read_complete_sig when(state_main = MAINKERNELLOAD) else '0';


	process (clk, reset) begin
		if is_true(reset) then
			state_main <= MAINIDLE;
			ready_reg <= '1';
			setnumber_reg <= (others=>'0');
			module_start_reg <= '0';

		elsif rising_edge(clk) then
			if is_true(init_sig) then
				state_main <= MAINIDLE;
				ready_reg <= module_ready_sig and memread_ready_sig;
				setnumber_reg <= (others=>'0');
				module_start_reg <= '0';

			else
				case state_main is

				-- 開始信号を待つ 
				when MAINIDLE =>
					if is_true(start_sig) and is_true(module_ready_sig) then
						state_main <= MAINSTART;
						ready_reg <= '0';
						setnumber_reg <= pd_setnumber;
					end if;

				-- フィルターセットパラメータのロード 
				when MAINSTART =>
					state_main <= MAINLOAD;
					do_biasinit_reg <= '1';

				when MAINLOAD =>
					if is_true(read_complete_sig) then
						state_main <= MAINKERNELSTART;
					end if;

				-- カーネルループ処理 
				when MAINKERNELSTART =>
					state_main <= MAINKERNELLOAD;
					module_start_reg <= '1';

					if is_true(block_finally_sig) then		-- 最終ループならカーネルdoneマスクを設定する 
						kernel_ena_reg <= kernel_ena_sig(kernel_ena_reg'range);
						do_activation_reg <= '1';
					else
						kernel_ena_reg <= (others=>'1');
						do_activation_reg <= '0';
					end if;

				when MAINKERNELLOAD =>
					if is_true(read_complete_sig) then
						state_main <= MAINPROCESSING;
					end if;

					module_start_reg <= '0';
					do_biasinit_reg <= '0';

				when MAINPROCESSING =>
					if is_true(module_ready_sig) then		-- エラー報告時はここのステートでホールドする 
						if is_true(block_done_sig) then
							state_main <= MAINFINALLY;
						else
							state_main <= MAINKERNELSTART;
						end if;
					end if;

				-- 終了処置 
				when MAINFINALLY =>
					if (setnumber_reg = 1) then				-- 全てのフィルターセットを処理したら終了 
						state_main <= MAINIDLE;
						ready_reg <= '1';
					else
						state_main <= MAINSTART;
					end if;

					setnumber_reg <= setnumber_reg - 1;

				when others =>
				end case;

			end if;
		end if;
	end process;


	-- 各モジュールへの制御信号 

	accum_start <= module_start_reg;
	writeback_start <= module_start_reg;
	kernel_ena <= kernel_ena_reg;
	biasinit_ena <= do_biasinit_reg;
	relu_ena <= do_activation_reg;



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
	param_valid <= read_datavalid_sig when is_true(fsparam_loaddone_sig) else '0';


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

				-- フィルターセットパラメータの読み込みをリクエスト 
				elsif is_true(fsparam_req_sig) then
					state_memread <= READDATA;
					arbiter_wait_counter <= 0;
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
						pd_datanum_reg <= to_vector(BURST_MAXLENGTH, pd_datanum_reg'length);
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
	-- フィルターセットパラメータ読み込み 
	----------------------------------------------------------------------

	fsparam_init_sig <= init_sig when is_true(memread_ready_sig) else '0';
	fsparam_loaddone_sig <= fsparam_latchena_reg(fsparam_latchena_reg'left);


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
			-- フィルターセットレジスタのロード 
			if is_true(fsparam_init_sig) or is_true(finally_sig) then
				fsparam_latchena_reg <= (0=>'1', others=>'0');
			else
				if is_true(read_datavalid_sig) and is_false(fsparam_loaddone_sig) then

					-- レジスタラッチ選択信号 (シフトレジスタ)
					fsparam_latchena_reg <= shiftin(fsparam_latchena_reg, '0');

					-- reg0:処理チャネル数(channel_num)のロード 
					if is_true(reg0_latch_sig) then
						channel_num_reg <= slice(fsparam_bit_sig, channel_num_reg'length, 0*32);
					end if;

					-- reg1:カーネル処理サイズのロード 
					if is_true(reg1_latch_sig) then
						conv_x_size_reg <= slice(fsparam_bit_sig, conv_x_size_reg'length, 1*32+ 0);
						conv_y_size_reg <= slice(fsparam_bit_sig, conv_y_size_reg'length, 1*32+16);
					end if;

					-- reg2:カーネル処理モードのロード 
					if is_true(reg2_latch_sig) then
						padding_mode_reg 	<= slice(fsparam_bit_sig, 2, 2*32+ 0);
						unpooling_mode_reg	<= slice(fsparam_bit_sig, 2, 2*32+ 2);
						pooling_mode_reg	<= slice(fsparam_bit_sig, 2, 2*32+ 4);
						pooling_ena_reg		<= fsparam_bit_sig(2*32+ 6);
						decimal_pos_reg		<= slice(fsparam_bit_sig, 2, 2*32+ 8);
						precision_reg		<= fsparam_bit_sig(2*32+10);
					end if;

					-- reg3:バイアス値のロード 
					if is_true(reg3_latch_sig) then
						bias_data_reg <= slice(fsparam_bit_sig, 32, 3*32);
					end if;

					-- reg4:結果書き戻し先アドレスのロード 
					if is_true(reg4_latch_sig) then
						wb_address_reg <= slice(fsparam_bit_sig, 32, 4*32);
					end if;

					-- reg5:アキュムレーターバッファアドレスのロード 
					if is_true(reg5_latch_sig) then
						buf_address_reg <= slice(fsparam_bit_sig, 32, 5*32);
					end if;

				-- 残りチャネル数の更新 
				elsif is_true(update_cnum_sig) then
					if is_true(block_finally_sig) then
						channel_num_reg <= (others=>'0');
					else
						channel_num_reg <= channel_num_reg - MAXKERNEL_NUMBER;
					end if;
				end if;

			end if;
		end if;
	end process;


	block_finally_sig <= '1' when(channel_num_reg <= MAXKERNEL_NUMBER) else '0';
	block_done_sig <= '1' when(channel_num_reg = 0) else '0';

	with channel_num_reg(2 downto 0) select kernel_ena_sig <=
		"00000001"	when "001",
		"00000011"	when "010",
		"00000111"	when "011",
		"00001111"	when "100",
		"00011111"	when "101",
		"00111111"	when "110",
		"01111111"	when "111",
		"11111111"	when others;


	-- レジスタパラメータ出力 

	conv_x_size <= conv_x_size_reg;
	conv_y_size <= conv_y_size_reg;
	padding_mode <= padding_mode_reg;
	unpooling_mode <= unpooling_mode_reg;
	precision <= precision_reg;
	decimal_pos <= decimal_pos_reg;

	bias_data <= bias_data_reg;
	rd_address_top <= buf_address_reg;
	rd_totalnum <= totaldatanum_sig;

	pooling_ena <= pooling_ena_reg;
	pooling_mode <= pooling_mode_reg;
	wb_address_top <= wb_address_reg when is_true(do_activation_reg) else buf_address_reg;
	totaldatanum_sig <= wb_totalnum;



end RTL;
