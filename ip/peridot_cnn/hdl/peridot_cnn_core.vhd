-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - core module
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/09/04 -> 2020/09/18
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

-- ・検証残り
-- ■ カーネル1,32bitのフィルターセットループ動作確認(中間値バッファRmWあり/なし) 
-- □ カーネル2,32bitのフィルターセットループ(中間値バッファRmWあり/なし) → 全体結合でテスト 

-- ・リソース概算
--  2,200LE + 6DSP +  6M9k (32bit幅, 1カーネル, 256x256, 128ワードFIFO)
--  5,300LE +24DSP + 21M9k (32bit幅, 4カーネル, 512x512, 512ワードFIFO, リードフュージョンあり)
-- 10,500LE +48DSP +163M9k (256bit幅, 8カーネル, 2048x2048, 4096ワードFIFO, リードフュージョンあり)


-- VHDL 1993 / IEEE 1076-1993
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_misc.all;

use work.peridot_cnn_core_package.all;

entity peridot_cnn_core is
	generic(
		MAXKERNEL_NUMBER		: integer := 1;		-- カーネルインスタンス数 (1～8)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		MAXCONVSIZE_POW2_NUMBER	: integer := 8;		-- 畳み込み画像の最大値 (8:256x256 / 9:512x512 / 10:1024x1024 / 11:2048x2048)
		MAXLINEBYTES_POW2_NUMBER: integer := 15;	-- ラインデータ増分値の最大バイト数 (10:±1kbyte ～ 15:±32kbyte)
		FIFODEPTH_POW2_NUMBER	: integer := 7;		-- 累算/書き戻しFIFOの深さ (7:128ワード ～ 12:4096ワード)
		USE_KERNELREAD_FUSION	: string := "ON";	-- カーネルリード要求の融合を行う 
		USE_FIFO_FLOW_CHECKING	: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 

		-- SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
		reset				: in  std_logic;
		clk					: in  std_logic;

		init				: in  std_logic := '0';
		start				: in  std_logic;
		ready				: out std_logic;
		error				: out std_logic;
		finally				: out std_logic;
		status				: out std_logic_vector(35 downto 0);

		pd_address_top		: in  std_logic_vector(31 downto 0);
		pd_setnumber		: in  std_logic_vector(15 downto 0);

		avm_address			: out std_logic_vector(31 downto 0);
		avm_burstcount		: out std_logic_vector(MAXCONVSIZE_POW2_NUMBER-(DATABUS_POW2_NUMBER-3) downto 0);
		avm_waitrequest		: in  std_logic;
		avm_read			: out std_logic;
		avm_readdata		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		avm_readdatavalid	: in  std_logic;
		avm_write			: out std_logic;
		avm_writedata		: out std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		avm_byteenable		: out std_logic_vector(2**(DATABUS_POW2_NUMBER-3)-1 downto 0)
	);
end peridot_cnn_core;

architecture RTL of peridot_cnn_core is
	function is_true(S:std_logic) return boolean is begin return(S='1'); end;
	function is_false(S:std_logic) return boolean is begin return(S='0'); end;
	function to_vector(N,W:integer) return std_logic_vector is begin return conv_std_logic_vector(N,W); end;
	function repbit(S:std_logic; W:integer) return std_logic_vector is variable a:std_logic_vector(W-1 downto 0); begin a:=(others=>S); return a; end;

	function slice(V:std_logic_vector; W,N:integer) return std_logic_vector is variable a:std_logic_vector(V'length+W+N-2 downto 0);
	begin a:=repbit('0',W+N-1)&V; return a(W+N-1 downto N); end;

	-- バースト長の設定 
	function min(A,B:integer) return integer is begin if A<B then return A; else return B; end if; end;
	function max(A,B:integer) return integer is begin if A>B then return A; else return B; end if; end;
	constant AVMM_BURST_WIDTH		: integer := avm_burstcount'length-1;
	constant MAINFSM_BURST_WIDTH	: integer := 3+(8-DATABUS_POW2_NUMBER);
	constant KERNEL_BURST_WIDTH		: integer := AVMM_BURST_WIDTH;
	constant FIFO_BURST_WIDTH		: integer := max(3, FIFODEPTH_POW2_NUMBER-(DATABUS_POW2_NUMBER-5)-2);
	constant ACCUM_BURST_WIDTH		: integer := min(FIFO_BURST_WIDTH, AVMM_BURST_WIDTH);
	constant WRITEBACK_BURST_WIDTH	: integer := min(FIFO_BURST_WIDTH, AVMM_BURST_WIDTH);


	-- メインFSMモジュール 
	signal init_sig				: std_logic;
	signal main_rdreq_sig		: std_logic;
	signal main_rdcomplete_sig	: std_logic;
	signal main_rdaddress_sig	: std_logic_vector(31 downto 0);
	signal main_rdburst_sig		: std_logic_vector(MAINFSM_BURST_WIDTH downto 0);
	signal main_rddata_sig		: std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
	signal main_rddatavalid_sig	: std_logic;

	signal kernel_readyall_sig	: std_logic;
	signal kernel_errorall_sig	: std_logic;
	signal conv_x_size_sig		: std_logic_vector(11 downto 0);
	signal conv_y_size_sig		: std_logic_vector(11 downto 0);
	signal padding_mode_sig		: std_logic_vector(1 downto 0);
	signal unpooling_mode_sig	: std_logic_vector(1 downto 0);
	signal precision_sig		: std_logic;
	signal decimal_pos_sig		: std_logic_vector(1 downto 0);
	signal param_data_sig		: std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
	signal param_valid_sig		: std_logic;

	signal accum_ready_sig		: std_logic;
	signal accum_start_sig		: std_logic;
	signal accum_error_sig		: std_logic;
	signal biasinit_ena_sig		: std_logic;
	signal bias_data_sig		: std_logic_vector(31 downto 0);
	signal rd_address_top_sig	: std_logic_vector(31 downto 0);
	signal rd_totalnum_sig		: std_logic_vector(22 downto 0);
	signal kernel_ena_sig		: std_logic_vector(MAXKERNEL_NUMBER-1 downto 0);

	signal writeback_ready_sig	: std_logic;
	signal writeback_start_sig	: std_logic;
	signal relu_ena_sig			: std_logic;
	signal pooling_ena_sig		: std_logic;
	signal pooling_mode_sig		: std_logic_vector(1 downto 0);
	signal wb_address_top_sig	: std_logic_vector(31 downto 0);
	signal wb_totalnum_sig		: std_logic_vector(22 downto 0);


	-- 畳み込みモジュール 
	signal kernel_ready_sig		: std_logic_vector(MAXKERNEL_NUMBER-1 downto 0);
	signal kernel_error_sig		: std_logic_vector(MAXKERNEL_NUMBER-1 downto 0);
	signal kernel_status_sig	: std_logic_vector(MAXKERNEL_NUMBER*4-1 downto 0);
	signal kernel_paramvalid_sig: std_logic_vector(MAXKERNEL_NUMBER-1 downto 0);
	signal kernel_paramdone_sig	: std_logic_vector(MAXKERNEL_NUMBER downto 0);

	signal kernel_rdreq_sig		: std_logic_vector(7 downto 0) := (others=>'0');
	signal kernel_rdcomplete_sig: std_logic_vector(7 downto 0) := (others=>'0');
	signal kernel_rddata_sig	: std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
	signal kernel_rddatavalid_sig: std_logic_vector(7 downto 0);
	type DEF_KERNEL_ADDRESS is array(0 to 7) of std_logic_vector(31 downto 0);
	signal kernel_rdaddress_sig	: DEF_KERNEL_ADDRESS := (others=>(others=>'0'));
	type DEF_KERNEL_BURSTCOUNT is array(0 to 7) of std_logic_vector(KERNEL_BURST_WIDTH downto 0);
	signal kernel_rdburst_sig	: DEF_KERNEL_BURSTCOUNT := (others=>(others=>'0'));

	signal kernel_sto_ready_sig	: std_logic;
	signal kernel_sto_valid_sig	: std_logic_vector(MAXKERNEL_NUMBER-1 downto 0);
	signal kernel_sto_data_sig	: std_logic_vector(MAXKERNEL_NUMBER*32-1 downto 0);
	signal kernel_sto_eol_sig	: std_logic_vector(MAXKERNEL_NUMBER-1 downto 0);
	signal kernel_sto_eof_sig	: std_logic_vector(MAXKERNEL_NUMBER-1 downto 0);


	-- 累算モジュール 
	signal accum_status_sig		: std_logic_vector(1 downto 0);
	signal accum_rdreq_sig		: std_logic;
	signal accum_rdcomplete_sig	: std_logic;
	signal accum_rdaddress_sig	: std_logic_vector(31 downto 0);
	signal accum_rdburst_sig	: std_logic_vector(ACCUM_BURST_WIDTH downto 0);
	signal accum_rddata_sig		: std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
	signal accum_rddatavalid_sig: std_logic;

	signal accum_sto_ready_sig	: std_logic;
	signal accum_sto_valid_sig	: std_logic;
	signal accum_sto_data_sig	: std_logic_vector(31 downto 0);
	signal accum_sto_eof_sig	: std_logic;
	signal accum_sto_eol_sig	: std_logic;


	-- 活性化モジュール 
	signal wb_wrreq_sig			: std_logic;
	signal wb_burstend_sig		: std_logic;
	signal wb_wraddress_sig		: std_logic_vector(31 downto 0);
	signal wb_wrburst_sig		: std_logic_vector(WRITEBACK_BURST_WIDTH downto 0);
	signal wb_wrdata_sig		: std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
	signal wb_wrbyteenable_sig	: std_logic_vector(2**(DATABUS_POW2_NUMBER-3)-1 downto 0);
	signal wb_wrdataack_sig		: std_logic;


	-- バスアービタモジュール 
	signal paramread_burst_sig	: std_logic_vector(AVMM_BURST_WIDTH downto 0);
	signal wbwrite_burst_sig	: std_logic_vector(AVMM_BURST_WIDTH downto 0);
	signal accumread_burst_sig	: std_logic_vector(AVMM_BURST_WIDTH downto 0);
	signal read_0_burst_sig		: std_logic_vector(AVMM_BURST_WIDTH downto 0);
	signal read_1_burst_sig		: std_logic_vector(AVMM_BURST_WIDTH downto 0);
	signal read_2_burst_sig		: std_logic_vector(AVMM_BURST_WIDTH downto 0);
	signal read_3_burst_sig		: std_logic_vector(AVMM_BURST_WIDTH downto 0);
	signal read_4_burst_sig		: std_logic_vector(AVMM_BURST_WIDTH downto 0);
	signal read_5_burst_sig		: std_logic_vector(AVMM_BURST_WIDTH downto 0);
	signal read_6_burst_sig		: std_logic_vector(AVMM_BURST_WIDTH downto 0);
	signal read_7_burst_sig		: std_logic_vector(AVMM_BURST_WIDTH downto 0);


begin

	-- テスト記述 


	-- パラメータ範囲チェック 



	----------------------------------------------------------------------
	-- メインFSMモジュール 
	----------------------------------------------------------------------

	init_sig <= init;
	status <= writeback_ready_sig & (accum_status_sig & accum_ready_sig) & slice(kernel_status_sig, 32, 0);


	u_mainfsm : peridot_cnn_mainfsm
	generic map(
		MAXKERNEL_NUMBER		=> MAXKERNEL_NUMBER,
		DATABUS_POW2_NUMBER		=> DATABUS_POW2_NUMBER,
		DEVICE_FAMILY			=> DEVICE_FAMILY
	)
	port map(
		reset			=> reset,
		clk				=> clk,

		init			=> init_sig,
		start			=> start,
		ready			=> ready,
		error			=> error,
		finally			=> finally,
		pd_address_top	=> pd_address_top,
		pd_setnumber	=> pd_setnumber,

		read_request	=> main_rdreq_sig,
		read_complete	=> main_rdcomplete_sig,
		read_address	=> main_rdaddress_sig,
		read_burstcount	=> main_rdburst_sig,
		read_data		=> main_rddata_sig,
		read_datavalid	=> main_rddatavalid_sig,

		kernel_ready	=> kernel_readyall_sig,
		kernel_error	=> kernel_errorall_sig,
		conv_x_size		=> conv_x_size_sig,
		conv_y_size		=> conv_y_size_sig,
		padding_mode	=> padding_mode_sig,
		unpooling_mode	=> unpooling_mode_sig,
		precision		=> precision_sig,
		decimal_pos		=> decimal_pos_sig,
		param_data		=> param_data_sig,
		param_valid		=> param_valid_sig,

		accum_ready		=> accum_ready_sig,
		accum_start		=> accum_start_sig,
		accum_error		=> accum_error_sig,
		biasinit_ena	=> biasinit_ena_sig,
		bias_data		=> bias_data_sig,
		rd_address_top	=> rd_address_top_sig,
		rd_totalnum		=> rd_totalnum_sig,
		kernel_ena		=> kernel_ena_sig,

		writeback_ready	=> writeback_ready_sig,
		writeback_start	=> writeback_start_sig,
		relu_ena		=> relu_ena_sig,
		pooling_ena		=> pooling_ena_sig,
		pooling_mode	=> pooling_mode_sig,
		wb_address_top	=> wb_address_top_sig,
		wb_totalnum		=> wb_totalnum_sig
	);



	----------------------------------------------------------------------
	-- 畳み込みモジュール 
	----------------------------------------------------------------------

	kernel_readyall_sig <= and_reduce(kernel_ready_sig);
	kernel_errorall_sig <= or_reduce(kernel_error_sig);

	kernel_paramdone_sig(0) <= '1';


	gen_conv : for i in 0 to MAXKERNEL_NUMBER-1 generate
		u : peridot_cnn_kernel
		generic map(
			PARAMWORD_POW2_NUMBER	=> DATABUS_POW2_NUMBER,
			DATABUS_POW2_NUMBER		=> DATABUS_POW2_NUMBER,
			MAXCONVSIZE_POW2_NUMBER	=> MAXCONVSIZE_POW2_NUMBER,
			MAXLINEBYTES_POW2_NUMBER=> MAXLINEBYTES_POW2_NUMBER,
			FIFO_FLOW_CHECKING		=> USE_FIFO_FLOW_CHECKING,
			DEVICE_FAMILY			=> DEVICE_FAMILY
		)
		port map(
			reset			=> reset,
			clk				=> clk,

			init			=> init_sig,
			ready			=> kernel_ready_sig(i),
			error			=> kernel_error_sig(i),
			status			=> kernel_status_sig(i*4+3 downto i*4+1),
			conv_x_size		=> conv_x_size_sig(MAXCONVSIZE_POW2_NUMBER downto 0),
			conv_y_size		=> conv_y_size_sig(MAXCONVSIZE_POW2_NUMBER downto 0),
			padding_mode	=> padding_mode_sig,
			unpooling_mode	=> unpooling_mode_sig,
			precision		=> precision_sig,
			decimal_pos		=> decimal_pos_sig,

			param_data		=> param_data_sig,
			param_valid		=> kernel_paramvalid_sig(i),
			param_done		=> kernel_paramdone_sig(i+1),

			read_request	=> kernel_rdreq_sig(i),
			read_complete	=> kernel_rdcomplete_sig(i),
			read_address	=> kernel_rdaddress_sig(i),
			read_burstcount	=> kernel_rdburst_sig(i),
			read_data		=> kernel_rddata_sig,
			read_datavalid	=> kernel_rddatavalid_sig(i),

			sto_ready		=> kernel_sto_ready_sig,
			sto_valid		=> kernel_sto_valid_sig(i),
			sto_data		=> kernel_sto_data_sig(i*32+31 downto i*32+0),
			sto_endofline	=> kernel_sto_eol_sig(i),
			sto_endofframe	=> kernel_sto_eof_sig(i)
		);

		kernel_status_sig(i*4+0) <= kernel_ready_sig(i);
		kernel_paramvalid_sig(i) <= param_valid_sig when is_true(kernel_paramdone_sig(i)) else '0';
	end generate;



	----------------------------------------------------------------------
	-- 累算モジュール 
	----------------------------------------------------------------------

	u_accum : peridot_cnn_accum
	generic map(
		MAXKERNEL_NUMBER		=> MAXKERNEL_NUMBER,
		DATABUS_POW2_NUMBER		=> DATABUS_POW2_NUMBER,
		RDFIFODEPTH_POW2_NUMBER	=> FIFODEPTH_POW2_NUMBER,
		RDMAXBURST_POW2_NUMBER	=> ACCUM_BURST_WIDTH,
		FIFO_FLOW_CHECKING		=> USE_FIFO_FLOW_CHECKING,
		DEVICE_FAMILY			=> DEVICE_FAMILY
	)
	port map(
		reset			=> reset,
		clk				=> clk,

		init			=> init_sig,
		start			=> accum_start_sig,
		ready			=> accum_ready_sig,
		error			=> accum_error_sig,
		status			=> accum_status_sig,
		biasinit_ena	=> biasinit_ena_sig,
		bias_data		=> bias_data_sig,
		rd_address_top	=> rd_address_top_sig,
		rd_totalnum		=> rd_totalnum_sig,

		read_request	=> accum_rdreq_sig,
		read_complete	=> accum_rdcomplete_sig,
		read_address	=> accum_rdaddress_sig,
		read_burstcount	=> accum_rdburst_sig,
		read_data		=> accum_rddata_sig,
		read_datavalid	=> accum_rddatavalid_sig,

		kernel_ena		=> kernel_ena_sig,
		sti_ready		=> kernel_sto_ready_sig,
		sti_valid		=> kernel_sto_valid_sig,
		sti_data		=> kernel_sto_data_sig,
		sti_endofline	=> kernel_sto_eol_sig(0),
		sti_endofframe	=> kernel_sto_eof_sig(0),

		sto_ready		=> accum_sto_ready_sig,
		sto_valid		=> accum_sto_valid_sig,
		sto_data		=> accum_sto_data_sig,
		sto_endofline	=> accum_sto_eol_sig,
		sto_endofframe	=> accum_sto_eof_sig
	);



	----------------------------------------------------------------------
	-- 活性化モジュール 
	----------------------------------------------------------------------

	u_writeback : peridot_cnn_writeback
	generic map(
		DATABUS_POW2_NUMBER		=> DATABUS_POW2_NUMBER,
		MAXCONVSIZE_POW2_NUMBER	=> MAXCONVSIZE_POW2_NUMBER,
		WBFIFODEPTH_POW2_NUMBER	=> FIFODEPTH_POW2_NUMBER,
		WBMAXBURST_POW2_NUMBER	=> WRITEBACK_BURST_WIDTH,
		FIFO_FLOW_CHECKING		=> USE_FIFO_FLOW_CHECKING,
		DEVICE_FAMILY			=> DEVICE_FAMILY
	)
	port map(
		reset			=> reset,
		clk				=> clk,

		init			=> init_sig,
		start			=> writeback_start_sig,
		ready			=> writeback_ready_sig,
		relu_ena		=> relu_ena_sig,
		decimal_pos		=> decimal_pos_sig,
		pooling_ena		=> pooling_ena_sig,
		pooling_mode	=> pooling_mode_sig,
		wb_address_top	=> wb_address_top_sig,
		wb_totalnum		=> wb_totalnum_sig,

		sti_ready		=> accum_sto_ready_sig,
		sti_valid		=> accum_sto_valid_sig,
		sti_data		=> accum_sto_data_sig,
		sti_endofline	=> accum_sto_eol_sig,
		sti_endofframe	=> accum_sto_eof_sig,

		write_request	=> wb_wrreq_sig,
		write_burstend	=> wb_burstend_sig,
		write_address	=> wb_wraddress_sig,
		write_burstcount=> wb_wrburst_sig,
		write_data		=> wb_wrdata_sig,
		write_byteenable=> wb_wrbyteenable_sig,
		write_dataack	=> wb_wrdataack_sig
	);



	----------------------------------------------------------------------
	-- バスアービタモジュール 
	----------------------------------------------------------------------

	paramread_burst_sig <= slice(main_rdburst_sig, AVMM_BURST_WIDTH+1, 0);
	wbwrite_burst_sig <= slice(wb_wrburst_sig ,AVMM_BURST_WIDTH+1, 0);
	accumread_burst_sig <= slice(accum_rdburst_sig ,AVMM_BURST_WIDTH+1, 0);

	read_0_burst_sig <= slice(kernel_rdburst_sig(0) ,AVMM_BURST_WIDTH+1, 0);
	read_1_burst_sig <= slice(kernel_rdburst_sig(1) ,AVMM_BURST_WIDTH+1, 0);
	read_2_burst_sig <= slice(kernel_rdburst_sig(2) ,AVMM_BURST_WIDTH+1, 0);
	read_3_burst_sig <= slice(kernel_rdburst_sig(3) ,AVMM_BURST_WIDTH+1, 0);
	read_4_burst_sig <= slice(kernel_rdburst_sig(4) ,AVMM_BURST_WIDTH+1, 0);
	read_5_burst_sig <= slice(kernel_rdburst_sig(5) ,AVMM_BURST_WIDTH+1, 0);
	read_6_burst_sig <= slice(kernel_rdburst_sig(6) ,AVMM_BURST_WIDTH+1, 0);
	read_7_burst_sig <= slice(kernel_rdburst_sig(7) ,AVMM_BURST_WIDTH+1, 0);


	u_arbiter : peridot_cnn_arbiter
	generic map(
		DATABUS_POW2_NUMBER		=> DATABUS_POW2_NUMBER,
		MAXBURST_POW2_NUMBER	=> AVMM_BURST_WIDTH,
		USE_KERNELREAD_FUSION	=> USE_KERNELREAD_FUSION,
		DEVICE_FAMILY			=> DEVICE_FAMILY
	)
	port map(
		reset				=> reset,
		clk					=> clk,

		avm_address			=> avm_address,
		avm_burstcount		=> avm_burstcount,
		avm_waitrequest		=> avm_waitrequest,
		avm_read			=> avm_read,
		avm_readdata		=> avm_readdata,
		avm_readdatavalid	=> avm_readdatavalid,
		avm_write			=> avm_write,
		avm_writedata		=> avm_writedata,
		avm_byteenable		=> avm_byteenable,

		paramread_request	=> main_rdreq_sig,
		paramread_complete	=> main_rdcomplete_sig,
		paramread_address	=> main_rdaddress_sig,
		paramread_burstcount=> paramread_burst_sig,
		paramread_data		=> main_rddata_sig,
		paramread_datavalid	=> main_rddatavalid_sig,

		wbwrite_request		=> wb_wrreq_sig,
		wbwrite_burstend	=> wb_burstend_sig,
		wbwrite_address		=> wb_wraddress_sig,
		wbwrite_burstcount	=> wbwrite_burst_sig,
		wbwrite_data		=> wb_wrdata_sig,
		wbwrite_byteenable	=> wb_wrbyteenable_sig,
		wbwrite_dataack		=> wb_wrdataack_sig,

		accumread_request	=> accum_rdreq_sig,
		accumread_complete	=> accum_rdcomplete_sig,
		accumread_address	=> accum_rdaddress_sig,
		accumread_burstcount=> accumread_burst_sig,
		accumread_data		=> accum_rddata_sig,
		accumread_datavalid	=> accum_rddatavalid_sig,

		read_data			=> kernel_rddata_sig,
		read_request		=> kernel_rdreq_sig,
		read_complete		=> kernel_rdcomplete_sig,
		read_datavalid		=> kernel_rddatavalid_sig,

		read_0_address		=> kernel_rdaddress_sig(0),
		read_0_burstcount	=> read_0_burst_sig,
		read_1_address		=> kernel_rdaddress_sig(1),
		read_1_burstcount	=> read_1_burst_sig,
		read_2_address		=> kernel_rdaddress_sig(2),
		read_2_burstcount	=> read_2_burst_sig,
		read_3_address		=> kernel_rdaddress_sig(3),
		read_3_burstcount	=> read_3_burst_sig,
		read_4_address		=> kernel_rdaddress_sig(4),
		read_4_burstcount	=> read_4_burst_sig,
		read_5_address		=> kernel_rdaddress_sig(5),
		read_5_burstcount	=> read_5_burst_sig,
		read_6_address		=> kernel_rdaddress_sig(6),
		read_6_burstcount	=> read_6_burst_sig,
		read_7_address		=> kernel_rdaddress_sig(7),
		read_7_burstcount	=> read_7_burst_sig
	);



end RTL;
