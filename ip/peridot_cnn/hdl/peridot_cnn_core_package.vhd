-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - core package
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/09/25 -> 2020/09/25
--            : 2020/09/25 (FIXED)
--
--     UPDATE : 2023/11/30 -> 2024/03/12
--
-- ===================================================================
--
-- The MIT License (MIT)
-- Copyright (c) 2020-2024 J-7SYSTEM WORKS LIMITED.
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

package peridot_cnn_core_package is

	-- メインFSMモジュール 

	component peridot_cnn_mainfsm
	generic(
		MAXKERNEL_NUMBER		: integer := 4;		-- カーネルインスタンス数 (1～8)
		FCFUNC_INSTANCE_TYPE	: integer := 1;		-- 全結合実装タイプ (0:なし / 1:INT8xINT16)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		INTRBUFFER_POW2_NUMBER	: integer := 10;	-- 内蔵バッファのサイズ (0:なし / 10:1kワード / 12:4kワード / 14:16kワード)
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: in  std_logic := '0';
		start			: in  std_logic;
		ready			: out std_logic;
		error			: out std_logic;
		finally			: out std_logic;
		pause			: out std_logic;
		restart			: in  std_logic := '1';
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
	end component;


	-- 畳み込みモジュール 

	component peridot_cnn_kernel
	generic(
		PARAMWORD_POW2_NUMBER	: integer := 5;		-- パラメータワード幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		MAXCONVSIZE_POW2_NUMBER	: integer := 9;		-- 畳み込み画像の最大値 (8:256x256 / 9:512x512 / 10:1024x1024 / 11:2048x2048)
		MAXLINEBYTES_POW2_NUMBER: integer := 15;	-- ラインデータ増分値の最大バイト数 (10:±1kbyte ～ 15:±32kbyte)
		FIFO_FLOW_CHECKING		: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 
		FIFO_SPEED_OPTION		: string := "ON";	-- FIFOのインスタンスオプション(ON=speed / OFF=area)
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: in  std_logic;
		ready			: out std_logic;
		error			: out std_logic;
		status			: out std_logic_vector(2 downto 0);
		conv_x_size		: in  std_logic_vector(MAXCONVSIZE_POW2_NUMBER downto 0);
		conv_y_size		: in  std_logic_vector(MAXCONVSIZE_POW2_NUMBER downto 0);
		padding_mode	: in  std_logic_vector(1 downto 0);
		bytepacking		: in  std_logic;

		param_valid		: in  std_logic;
		param_data		: in  std_logic_vector(2**PARAMWORD_POW2_NUMBER-1 downto 0);
		param_done		: out std_logic;

		read_request	: out std_logic;
		read_complete	: out std_logic;
		read_address	: out std_logic_vector(31 downto 0);
		read_burstcount	: out std_logic_vector(MAXCONVSIZE_POW2_NUMBER-(DATABUS_POW2_NUMBER-3) downto 0);
		read_datavalid	: in  std_logic;
		read_data		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);

		sto_ready		: in  std_logic;
		sto_valid		: out std_logic;
		sto_data		: out std_logic_vector(31 downto 0);
		sto_endofline	: out std_logic;
		sto_endofframe	: out std_logic
	);
	end component;


	-- フィルター演算モジュール 

	component peridot_cnn_accum
	generic(
		MAXKERNEL_NUMBER		: integer := 4;		-- カーネルインスタンス数 (1～8)
		RANDGEN_INSTANCE_TYPE	: integer := 1;		-- 乱数生成器実装タイプ (0:なし / 1:一様乱数,近似cos^19)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		RDFIFODEPTH_POW2_NUMBER	: integer := 8;		-- 読み出しFIFOの深さ (7:128ワード ～ 12:4096ワード *出力ワード単位)
		RDMAXBURST_POW2_NUMBER	: integer := 4;		-- 読み出しバースト長 (3:8ワード ～ RD_DCFIFO_WIDTHU-1 *バースト上限はFIFO読み出し側の半分まで)
		INTRBUFFER_POW2_NUMBER	: integer := 10;	-- 内蔵バッファのサイズ (0:なし / 10:1kワード / 12:4kワード / 14:16kワード)
		FIFO_FLOW_CHECKING		: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 
		FIFO_SPEED_OPTION		: string := "ON";	-- FIFOのインスタンスオプション(ON=speed / OFF=area)
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: in  std_logic;
		start			: in  std_logic;
		ready			: out std_logic;
		error			: out std_logic;
		status			: out std_logic_vector(2 downto 0);
		firstchunk		: in  std_logic;
		lastchunk		: in  std_logic;
		intrbuff_ena	: in  std_logic;
		multcalc_ena	: in  std_logic;
		bias_data		: in  std_logic_vector(31 downto 0);
		noise_type		: in  std_logic_vector(1 downto 0);
		noise_gain		: in  std_logic_vector(17 downto 0);
		rd_address_top	: in  std_logic_vector(31 downto 0);
		rd_totalnum		: in  std_logic_vector(22 downto 0);

		read_request	: out std_logic;
		read_complete	: out std_logic;
		read_address	: out std_logic_vector(31 downto 0);
		read_burstcount	: out std_logic_vector(RDMAXBURST_POW2_NUMBER downto 0);
		read_datavalid	: in  std_logic;
		read_data		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);

		kernel_ena		: in  std_logic_vector(MAXKERNEL_NUMBER-1 downto 0);
		sti_ready		: out std_logic;
		sti_valid		: in  std_logic_vector(MAXKERNEL_NUMBER-1 downto 0);
		sti_data		: in  std_logic_vector(MAXKERNEL_NUMBER*32-1 downto 0);
		sti_endofline	: in  std_logic;
		sti_endofframe	: in  std_logic;

		sto_ready		: in  std_logic;
		sto_valid		: out std_logic;
		sto_data		: out std_logic_vector(31 downto 0);
		sto_endofline	: out std_logic;
		sto_endofframe	: out std_logic
	);
	end component;


	-- 全結合モジュール 

	component peridot_cnn_fullyconn
	generic(
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		RDMAXBURST_POW2_NUMBER	: integer := 4;		-- 読み出しバースト長 (3:8ワード ～ 11:2048 *バス幅単位)
		FIFO_FLOW_CHECKING		: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 
		FIFO_SPEED_OPTION		: string := "ON";	-- FIFOのインスタンスオプション(ON=speed / OFF=area)
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: in  std_logic := '0';
		start			: in  std_logic;
		ready			: out std_logic;
		error			: out std_logic;
		status			: out std_logic_vector(2 downto 0);
		fc_calc_mode	: in  std_logic_vector(1 downto 0);
		fc_channel_num	: in  std_logic_vector(12 downto 0);
		vectordata_num	: in  std_logic_vector(17 downto 0);
		vectordata_top	: in  std_logic_vector(31 downto 0);
		weightdata_top	: in  std_logic_vector(31 downto 0);
		matmulbias		: in  std_logic_vector(31 downto 0);

		read_request	: out std_logic;
		read_complete	: out std_logic;
		read_address	: out std_logic_vector(31 downto 0);
		read_burstcount	: out std_logic_vector(RDMAXBURST_POW2_NUMBER downto 0);
		read_datavalid	: in  std_logic;
		read_data		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);

		sto_ready		: in  std_logic;
		sto_valid		: out std_logic;
		sto_data		: out std_logic_vector(31 downto 0);
		sto_endofline	: out std_logic;
		sto_endofframe	: out std_logic
	);
	end component;


	-- データ書き戻し／活性化モジュール 

	component peridot_cnn_writeback
	generic(
		ACTFUNC_INSTANCE_TYPE	: integer := 1;		-- 活性化関数実装タイプ (0:ReLU,Hard-tanh,Step,Leaky-ReLU / 1:0+sigmoid / 2:0+1+tanh / 3:0+1+2+LUT)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		MAXCONVSIZE_POW2_NUMBER	: integer := 9;		-- 畳み込み画像の最大値 (8:256x256 / 9:512x512 / 10:1024x1024 / 11:2048x2048)
		WBFIFODEPTH_POW2_NUMBER	: integer := 8;		-- 書き戻しFIFOの深さ (7:128ワード ～ 12:4096ワード *入力ワード単位)
		WBMAXBURST_POW2_NUMBER	: integer := 4;		-- 書き戻しバースト長 (3:8ワード ～ WB_SCFIFO_WIDTHU-1 *バースト上限はFIFO読み出し側の半分まで)
		FIFO_FLOW_CHECKING		: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 
		FIFO_SPEED_OPTION		: string := "ON";	-- FIFOのインスタンスオプション(ON=speed / OFF=area)
		AFLUT_SET_INITIALVALUE	: string := "ON";	-- LUTの初期値を設定オプション (メモリマクロの初期値を持てないデバイスではOFFにする)
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
		reset			: in  std_logic;
		clk				: in  std_logic;

		init			: in  std_logic := '0';
		start			: in  std_logic;
		ready			: out std_logic;
		activation_ena	: in  std_logic;
		actfunc_type	: in  std_logic_vector(2 downto 0);
		decimal_pos		: in  std_logic_vector(1 downto 0);
		pooling_mode	: in  std_logic_vector(1 downto 0);
		wb_address_top	: in  std_logic_vector(31 downto 0);
		wb_totalnum		: out std_logic_vector(22 downto 0);

		sti_ready		: out std_logic;
		sti_valid		: in  std_logic;
		sti_data		: in  std_logic_vector(31 downto 0);
		sti_endofline	: in  std_logic;
		sti_endofframe	: in  std_logic;

		write_request	: out std_logic;
		write_burstend	: out std_logic;
		write_address	: out std_logic_vector(31 downto 0);
		write_burstcount: out std_logic_vector(WBMAXBURST_POW2_NUMBER downto 0);
		write_data		: out std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		write_byteenable: out std_logic_vector(2**(DATABUS_POW2_NUMBER-3)-1 downto 0);
		write_dataack	: in  std_logic;

		aflut_wrclk		: in  std_logic;
		aflut_wrad		: in  std_logic_vector(19 downto 0);
		aflut_wrena		: in  std_logic := '0'
	);
	end component;


	-- バスアービタモジュール 

	component peridot_cnn_arbiter
	generic(
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		MAXBURST_POW2_NUMBER	: integer := 8;		-- バースト長 (3:8ワード ～ 10:1024ワード)
		USE_KERNELREAD_FUSION	: string := "ON";	-- カーネルリード要求の融合を行う 
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
		reset				: in  std_logic;
		clk					: in  std_logic;

		avm_address			: out std_logic_vector(31 downto 0);
		avm_burstcount		: out std_logic_vector(MAXBURST_POW2_NUMBER downto 0);
		avm_waitrequest		: in  std_logic;
		avm_read			: out std_logic;
		avm_readdatavalid	: in  std_logic;
		avm_readdata		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		avm_write			: out std_logic;
		avm_writedata		: out std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		avm_byteenable		: out std_logic_vector(2**(DATABUS_POW2_NUMBER-3)-1 downto 0);

		wbwrite_request		: in  std_logic;
		wbwrite_burstend	: in  std_logic;
		wbwrite_address		: in  std_logic_vector(31 downto 0);
		wbwrite_burstcount	: in  std_logic_vector(MAXBURST_POW2_NUMBER downto 0);
		wbwrite_data		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		wbwrite_byteenable	: in  std_logic_vector(2**(DATABUS_POW2_NUMBER-3)-1 downto 0);
		wbwrite_dataack		: out std_logic;

		paramread_request	: in  std_logic;
		paramread_complete	: in  std_logic;
		paramread_address	: in  std_logic_vector(31 downto 0);
		paramread_burstcount: in  std_logic_vector(MAXBURST_POW2_NUMBER downto 0);
		paramread_datavalid	: out std_logic;
		paramread_data		: out std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);

		accumread_request	: in  std_logic;
		accumread_complete	: in  std_logic;
		accumread_address	: in  std_logic_vector(31 downto 0);
		accumread_burstcount: in  std_logic_vector(MAXBURST_POW2_NUMBER downto 0);
		accumread_datavalid	: out std_logic;
		accumread_data		: out std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);

		fcread_request		: in  std_logic;
		fcread_complete		: in  std_logic;
		fcread_address		: in  std_logic_vector(31 downto 0);
		fcread_burstcount	: in  std_logic_vector(MAXBURST_POW2_NUMBER downto 0);
		fcread_datavalid	: out std_logic;
		fcread_data			: out std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);

		read_request		: in  std_logic_vector(7 downto 0);
		read_complete		: in  std_logic_vector(7 downto 0);
		read_datavalid		: out std_logic_vector(7 downto 0);
		read_data			: out std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);

		read_0_address		: in  std_logic_vector(31 downto 0);
		read_0_burstcount	: in  std_logic_vector(MAXBURST_POW2_NUMBER downto 0);
		read_1_address		: in  std_logic_vector(31 downto 0);
		read_1_burstcount	: in  std_logic_vector(MAXBURST_POW2_NUMBER downto 0);
		read_2_address		: in  std_logic_vector(31 downto 0);
		read_2_burstcount	: in  std_logic_vector(MAXBURST_POW2_NUMBER downto 0);
		read_3_address		: in  std_logic_vector(31 downto 0);
		read_3_burstcount	: in  std_logic_vector(MAXBURST_POW2_NUMBER downto 0);
		read_4_address		: in  std_logic_vector(31 downto 0);
		read_4_burstcount	: in  std_logic_vector(MAXBURST_POW2_NUMBER downto 0);
		read_5_address		: in  std_logic_vector(31 downto 0);
		read_5_burstcount	: in  std_logic_vector(MAXBURST_POW2_NUMBER downto 0);
		read_6_address		: in  std_logic_vector(31 downto 0);
		read_6_burstcount	: in  std_logic_vector(MAXBURST_POW2_NUMBER downto 0);
		read_7_address		: in  std_logic_vector(31 downto 0);
		read_7_burstcount	: in  std_logic_vector(MAXBURST_POW2_NUMBER downto 0)
	);
	end component;


end peridot_cnn_core_package;
