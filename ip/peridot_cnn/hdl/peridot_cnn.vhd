-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/09/06 -> 2020/09/19
--            : 2020/09/23 (FIXED)
--
--     UPDATE : 2023/11/30 -> 2024/03/15
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

-- ・検証todo 
-- [ ] 実機テスト 
--
-- ・リソース概算
-- 2200LE + 13DSP + 7M9k (32bit幅,1カーネル,256x256,128ワードFIFO,内蔵バッファなし,NF=0,FC=0,AF=0, FIFOチェックOFF, Area, ReducedREG)
--   fmax : 268MHz(Cyclone10GX E5), 149MHz(Cyclone10LP C6), 154MHz(MAX10 C6), 158MHz(CycloneV C7), 
--
-- 6700LE + 52DSP + 29M9k (32bit幅,4カーネル,1024x1024,256ワードFIFO,内蔵バッファ1k,NF=0,FC=1,AF=1, リードフュージョンあり)
--   fmax : 311MHz(Cyclone10GX E5), 156MHz(Cyclone10LP C6), 148MHz(MAX10 C6), 161MHz(CycloneV C7), 
--
-- 12800LE + 126DSP + 165M9k (256bit幅,8カーネル,2048x2048,4096ワードFIFO,内蔵バッファ4k,NF=1,FC=1,AF=3, リードフュージョンあり)
--   fmax : 282MHz(Cyclone10GX E5), 147MHz(Cyclone10LP C6), 140MHz(MAX10 C6), 138MHz(CycloneV C7)


-- VHDL 1993 / IEEE 1076-1993
library ieee;
use ieee.std_logic_1164.all;

entity peridot_cnn is
	generic(
		MAXKERNEL_NUMBER		: integer := 4;		-- カーネルインスタンス数 (1～8)
		RANDGEN_INSTANCE_TYPE	: integer := 1;		-- 乱数生成器実装タイプ (0:なし / 1:一様乱数,近似cos^19)
		FCFUNC_INSTANCE_TYPE	: integer := 1;		-- 全結合実装タイプ (0:なし / 1:INT8xINT16)
		ACTFUNC_INSTANCE_TYPE	: integer := 1;		-- 活性化関数実装タイプ (0:ReLU,Hard-tanh,Step,Leaky-ReLU / 1:0+sigmoid / 2:0+1+tanh / 3:0+1+2+LUT)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		MAXCONVSIZE_POW2_NUMBER	: integer := 9;		-- 畳み込みデータの最大値 (8:256x256 / 9:512x512 / 10:1024x1024 / 11:2048x2048)
		MAXLINEBYTES_POW2_NUMBER: integer := 15;	-- ラインアドレス増分値の最大バイト数 (10:±1kbyte ～ 15:±32kbyte)
		INTRBUFFER_POW2_NUMBER	: integer := 10;	-- 内蔵バッファのサイズ (0:なし / 10:1kワード / 12:4kワード / 14:16kワード)
		FIFODEPTH_POW2_NUMBER	: integer := 9;		-- 読み出し/書き戻しFIFOの深さ (7:128ワード ～ 12:4096ワード)
		USE_KERNELREAD_FUSION	: string := "ON";	-- カーネルリード要求統合のオプション 
		USE_FIFO_FLOW_CHECKING	: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 
		USE_FIFO_SPEED_OPTION	: string := "ON";	-- FIFOのインスタンスオプション(ON=speed / OFF=area)
		USE_LUT_INITIALVALUE	: string := "ON";	-- LUTの初期値設定オプション (メモリマクロの初期値を持てないデバイスではOFFにする)
		USE_REDUCED_REGMAP		: string := "OFF";	-- reg4～7のステータスレジスタを削除した縮小レジスタマップオプション 

		-- SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone 10 GX" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
		DEVICE_FAMILY			: string := "Cyclone III"
	);
	port(
	-- CNN Memory access I/F
		csi_m1_clk			: in  std_logic;
		csi_m1_reset		: in  std_logic;

		avm_m1_address		: out std_logic_vector(31 downto 0);
		avm_m1_burstcount	: out std_logic_vector(MAXCONVSIZE_POW2_NUMBER-(DATABUS_POW2_NUMBER-3) downto 0);
		avm_m1_waitrequest	: in  std_logic;
		avm_m1_read			: out std_logic;
		avm_m1_readdata		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		avm_m1_readdatavalid: in  std_logic;
		avm_m1_write		: out std_logic;
		avm_m1_writedata	: out std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		avm_m1_byteenable	: out std_logic_vector(2**(DATABUS_POW2_NUMBER-3)-1 downto 0);

	-- Control/Status Register I/F
		csi_csr_clk			: in  std_logic;
		csi_csr_reset		: in  std_logic;

		avs_csr_address		: in  std_logic_vector(2 downto 0);
		avs_csr_read		: in  std_logic;						-- setup:0,readwait1,hold0
		avs_csr_readdata	: out std_logic_vector(31 downto 0);
		avs_csr_write		: in  std_logic;						-- setup:0,writewait0,hold0
		avs_csr_writedata	: in  std_logic_vector(31 downto 0);

		ins_csr_irq			: out std_logic;

	-- Conduit Status signal
		coe_status			: out std_logic_vector(2 downto 0)
	);
end peridot_cnn;

architecture RTL of peridot_cnn is

	component peridot_cnn_core is
	generic(
		MAXKERNEL_NUMBER		: integer;
		RANDGEN_INSTANCE_TYPE	: integer;
		FCFUNC_INSTANCE_TYPE	: integer;
		ACTFUNC_INSTANCE_TYPE	: integer;
		DATABUS_POW2_NUMBER		: integer;
		MAXCONVSIZE_POW2_NUMBER	: integer;
		MAXLINEBYTES_POW2_NUMBER: integer;
		INTRBUFFER_POW2_NUMBER	: integer;
		FIFODEPTH_POW2_NUMBER	: integer;
		USE_KERNELREAD_FUSION	: string;
		USE_FIFO_FLOW_CHECKING	: string;
		USE_FIFO_SPEED_OPTION	: string;
		USE_LUT_INITIALVALUE	: string;
		DEVICE_FAMILY			: string
	);
	port(
		reset				: in  std_logic;
		clk					: in  std_logic;

		init				: in  std_logic := '0';
		start				: in  std_logic;
		ready				: out std_logic;
		error				: out std_logic;
		finally				: out std_logic;
		pause				: out std_logic;
		restart				: in  std_logic;
		status				: out std_logic_vector(40 downto 0);

		pd_address_top		: in  std_logic_vector(31 downto 0);
		pd_address_cur		: out std_logic_vector(31 downto 0);

		avm_address			: out std_logic_vector(31 downto 0);
		avm_burstcount		: out std_logic_vector(MAXCONVSIZE_POW2_NUMBER-(DATABUS_POW2_NUMBER-3) downto 0);
		avm_waitrequest		: in  std_logic;
		avm_read			: out std_logic;
		avm_readdatavalid	: in  std_logic;
		avm_readdata		: in  std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		avm_write			: out std_logic;
		avm_writedata		: out std_logic_vector(2**DATABUS_POW2_NUMBER-1 downto 0);
		avm_byteenable		: out std_logic_vector(2**(DATABUS_POW2_NUMBER-3)-1 downto 0);

		aflut_wrclk			: in  std_logic;
		aflut_wrad			: in  std_logic_vector(19 downto 0);
		aflut_wrena			: in  std_logic := '0'
	);
	end component;
	signal init_sig				: std_logic;
	signal start_sig			: std_logic;
	signal ready_sig			: std_logic;
	signal error_sig			: std_logic;
	signal pause_sig			: std_logic;
	signal restart_sig			: std_logic;
	signal status_sig			: std_logic_vector(40 downto 0);
	signal pd_address_top_sig	: std_logic_vector(31 downto 0);
	signal pd_address_cur_sig	: std_logic_vector(31 downto 0);
	signal aflut_wrclk_sig		: std_logic;
	signal aflut_wrad_sig		: std_logic_vector(19 downto 0);
	signal aflut_wrena_sig		: std_logic;


	component peridot_cnn_ctrlregs is
	generic(
		MAXKERNEL_NUMBER		: integer;
		RANDGEN_INSTANCE_TYPE	: integer;
		FCFUNC_INSTANCE_TYPE	: integer;
		ACTFUNC_INSTANCE_TYPE	: integer;
		DATABUS_POW2_NUMBER		: integer;
		MAXCONVSIZE_POW2_NUMBER	: integer;
		MAXLINEBYTES_POW2_NUMBER: integer;
		INTRBUFFER_POW2_NUMBER	: integer;
		USE_REDUCED_REGMAP		: string;
		DEVICE_FAMILY			: string
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
	end component;

begin


	----------------------------------------------------------------------
	-- CNN演算コアモジュール 
	----------------------------------------------------------------------

	u_core : peridot_cnn_core
	generic map (
		MAXKERNEL_NUMBER		=> MAXKERNEL_NUMBER,
		RANDGEN_INSTANCE_TYPE	=> RANDGEN_INSTANCE_TYPE,
		FCFUNC_INSTANCE_TYPE	=> FCFUNC_INSTANCE_TYPE,
		ACTFUNC_INSTANCE_TYPE	=> ACTFUNC_INSTANCE_TYPE,
		DATABUS_POW2_NUMBER		=> DATABUS_POW2_NUMBER,
		MAXCONVSIZE_POW2_NUMBER	=> MAXCONVSIZE_POW2_NUMBER,
		MAXLINEBYTES_POW2_NUMBER=> MAXLINEBYTES_POW2_NUMBER,
		INTRBUFFER_POW2_NUMBER	=> INTRBUFFER_POW2_NUMBER,
		FIFODEPTH_POW2_NUMBER	=> FIFODEPTH_POW2_NUMBER,
		USE_KERNELREAD_FUSION	=> USE_KERNELREAD_FUSION,
		USE_FIFO_FLOW_CHECKING	=> USE_FIFO_FLOW_CHECKING,
		USE_FIFO_SPEED_OPTION	=> USE_FIFO_SPEED_OPTION,
		USE_LUT_INITIALVALUE	=> USE_LUT_INITIALVALUE,
		DEVICE_FAMILY			=> DEVICE_FAMILY
	)
	port map(
		reset				=> csi_m1_reset,
		clk					=> csi_m1_clk,

		init				=> init_sig,
		start				=> start_sig,
		ready				=> ready_sig,
		error				=> error_sig,
		finally				=> open,
		pause				=> pause_sig,
		restart				=> restart_sig,
		status				=> status_sig,

		pd_address_top		=> pd_address_top_sig,
		pd_address_cur		=> pd_address_cur_sig,

		avm_address			=> avm_m1_address,
		avm_burstcount		=> avm_m1_burstcount,
		avm_waitrequest		=> avm_m1_waitrequest,
		avm_read			=> avm_m1_read,
		avm_readdatavalid	=> avm_m1_readdatavalid,
		avm_readdata		=> avm_m1_readdata,
		avm_write			=> avm_m1_write,
		avm_writedata		=> avm_m1_writedata,
		avm_byteenable		=> avm_m1_byteenable,

		aflut_wrclk			=> aflut_wrclk_sig,
		aflut_wrad			=> aflut_wrad_sig,
		aflut_wrena			=> aflut_wrena_sig
	);



	----------------------------------------------------------------------
	-- コントロールレジスタモジュール 
	----------------------------------------------------------------------

	u_csr : peridot_cnn_ctrlregs
	generic map (
		MAXKERNEL_NUMBER		=> MAXKERNEL_NUMBER,
		RANDGEN_INSTANCE_TYPE	=> RANDGEN_INSTANCE_TYPE,
		FCFUNC_INSTANCE_TYPE	=> FCFUNC_INSTANCE_TYPE,
		ACTFUNC_INSTANCE_TYPE	=> ACTFUNC_INSTANCE_TYPE,
		DATABUS_POW2_NUMBER		=> DATABUS_POW2_NUMBER,
		MAXCONVSIZE_POW2_NUMBER	=> MAXCONVSIZE_POW2_NUMBER,
		MAXLINEBYTES_POW2_NUMBER=> MAXLINEBYTES_POW2_NUMBER,
		INTRBUFFER_POW2_NUMBER	=> INTRBUFFER_POW2_NUMBER,
		USE_REDUCED_REGMAP		=> USE_REDUCED_REGMAP,
		DEVICE_FAMILY			=> DEVICE_FAMILY
	)
	port map (
		reset			=> csi_m1_reset,
		clk				=> csi_m1_clk,

		init			=> init_sig,
		start			=> start_sig,
		ready			=> ready_sig,
		error			=> error_sig,
		pause			=> pause_sig,
		restart			=> restart_sig,
		status			=> status_sig,

		pd_address_top	=> pd_address_top_sig,
		pd_address_cur	=> pd_address_cur_sig,

		aflut_wrclk		=> aflut_wrclk_sig,
		aflut_wrad		=> aflut_wrad_sig,
		aflut_wrena		=> aflut_wrena_sig,

		avs_reset		=> csi_csr_reset,
		avs_clk			=> csi_csr_clk,
		avs_address		=> avs_csr_address,
		avs_read		=> avs_csr_read,
		avs_readdata	=> avs_csr_readdata,
		avs_write		=> avs_csr_write,
		avs_writedata	=> avs_csr_writedata,
		ins_irq			=> ins_csr_irq,

		coe_status		=> coe_status
	);



end RTL;
