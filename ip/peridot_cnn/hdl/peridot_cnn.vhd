-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/09/06 -> 2020/09/19
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
-- ■ カーネル1,32bitのフィルターセットループ動作確認(中間値バッファRmWあり/なし,アボート動作) 
-- □ カーネル2,32bitのフィルターセットループ(中間値バッファRmWあり/なし) → リードフュージョンに問題あり 
-- □ 実機テスト 

-- ・リソース概算
--  2,100LE + 6DSP +  6M9k (32bit幅, 1カーネル, 256x256, 128ワードFIFO)
--  5,200LE +22DSP + 21M9k (32bit幅, 4カーネル, 512x512, 512ワードFIFO, リードフュージョンあり)
-- 10,300LE +44DSP +163M9k (256bit幅, 8カーネル, 2048x2048, 4096ワードFIFO, リードフュージョンあり)
-- fmax 110～130MHz (C8)


-- VHDL 1993 / IEEE 1076-1993
library ieee;
use ieee.std_logic_1164.all;

entity peridot_cnn is
	generic(
		MAXKERNEL_NUMBER		: integer := 4;		-- カーネルインスタンス数 (1～8)
		SETNUMBER_POW2_NUMBER	: integer := 16;	-- 最大フィルターセット数 (10:1023 ～ 16:65535)
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		MAXCONVSIZE_POW2_NUMBER	: integer := 9;		-- 畳み込み画像の最大値 (8:256x256 / 9:512x512 / 10:1024x1024 / 11:2048x2048)
		MAXLINEBYTES_POW2_NUMBER: integer := 15;	-- ラインデータ増分値の最大バイト数 (10:±1kbyte ～ 15:±32kbyte)
		FIFODEPTH_POW2_NUMBER	: integer := 9;		-- 累算/書き戻しFIFOの深さ (7:128ワード ～ 12:4096ワード)
		USE_KERNELREAD_FUSION	: string := "ON";	-- カーネルリード要求の融合を行う 
		USE_FIFO_FLOW_CHECKING	: string := "ON";	-- FIFOのoverflow/underflowチェックオプション 

		-- SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
		DEVICE_FAMILY			: string := "Cyclone 10 LP"
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

		avs_csr_address		: in  std_logic_vector(1 downto 0);
		avs_csr_read		: in  std_logic;						-- setup:0,readwait1,hold0
		avs_csr_readdata	: out std_logic_vector(31 downto 0);
		avs_csr_write		: in  std_logic;						-- setup:0,writewait0,hold0
		avs_csr_writedata	: in  std_logic_vector(31 downto 0);

		ins_csr_irq			: out std_logic
	);
end peridot_cnn;

architecture RTL of peridot_cnn is

	component peridot_cnn_core is
	generic(
		MAXKERNEL_NUMBER		: integer;
		DATABUS_POW2_NUMBER		: integer;
		MAXCONVSIZE_POW2_NUMBER	: integer;
		MAXLINEBYTES_POW2_NUMBER: integer;
		FIFODEPTH_POW2_NUMBER	: integer;
		USE_KERNELREAD_FUSION	: string;
		USE_FIFO_FLOW_CHECKING	: string;
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
	end component;
	signal init_sig				: std_logic;
	signal start_sig			: std_logic;
	signal ready_sig			: std_logic;
	signal error_sig			: std_logic;
	signal finally_sig			: std_logic;
	signal status_sig			: std_logic_vector(35 downto 0);
	signal pd_address_top_sig	: std_logic_vector(31 downto 0);
	signal pd_setnumber_sig		: std_logic_vector(15 downto 0);

	component peridot_cnn_ctrlregs is
	generic(
		MAXKERNEL_NUMBER		: integer;
		SETNUMBER_POW2_NUMBER	: integer;
		DATABUS_POW2_NUMBER		: integer;
		MAXCONVSIZE_POW2_NUMBER	: integer;
		MAXLINEBYTES_POW2_NUMBER: integer;
		DEVICE_FAMILY			: string
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
	end component;

begin


	----------------------------------------------------------------------
	-- CNN演算コアモジュール 
	----------------------------------------------------------------------

	u_core : peridot_cnn_core
	generic map(
		MAXKERNEL_NUMBER		=> MAXKERNEL_NUMBER,
		DATABUS_POW2_NUMBER		=> DATABUS_POW2_NUMBER,
		MAXCONVSIZE_POW2_NUMBER	=> MAXCONVSIZE_POW2_NUMBER,
		MAXLINEBYTES_POW2_NUMBER=> MAXLINEBYTES_POW2_NUMBER,
		FIFODEPTH_POW2_NUMBER	=> FIFODEPTH_POW2_NUMBER,
		USE_KERNELREAD_FUSION	=> USE_KERNELREAD_FUSION,
		USE_FIFO_FLOW_CHECKING	=> USE_FIFO_FLOW_CHECKING,
		DEVICE_FAMILY			=> DEVICE_FAMILY
	)
	port map(
		reset				=> csi_m1_reset,
		clk					=> csi_m1_clk,

		init				=> init_sig,
		start				=> start_sig,
		ready				=> ready_sig,
		error				=> error_sig,
		finally				=> finally_sig,
		status				=> status_sig,
		pd_address_top		=> pd_address_top_sig,
		pd_setnumber		=> pd_setnumber_sig,

		avm_address			=> avm_m1_address,
		avm_burstcount		=> avm_m1_burstcount,
		avm_waitrequest		=> avm_m1_waitrequest,
		avm_read			=> avm_m1_read,
		avm_readdata		=> avm_m1_readdata,
		avm_readdatavalid	=> avm_m1_readdatavalid,
		avm_write			=> avm_m1_write,
		avm_writedata		=> avm_m1_writedata,
		avm_byteenable		=> avm_m1_byteenable
	);



	----------------------------------------------------------------------
	-- コントロールレジスタモジュール 
	----------------------------------------------------------------------

	u_csr : peridot_cnn_ctrlregs
	generic map(
		MAXKERNEL_NUMBER		=> MAXKERNEL_NUMBER,
		SETNUMBER_POW2_NUMBER	=> SETNUMBER_POW2_NUMBER,
		DATABUS_POW2_NUMBER		=> DATABUS_POW2_NUMBER,
		MAXCONVSIZE_POW2_NUMBER	=> MAXCONVSIZE_POW2_NUMBER,
		MAXLINEBYTES_POW2_NUMBER=> MAXLINEBYTES_POW2_NUMBER,
		DEVICE_FAMILY			=> DEVICE_FAMILY
	)
	port map(
		reset			=> csi_m1_reset,
		clk				=> csi_m1_clk,

		init			=> init_sig,
		start			=> start_sig,
		ready			=> ready_sig,
		error			=> error_sig,
		finally			=> finally_sig,
		status			=> status_sig,
		pd_address_top	=> pd_address_top_sig,
		pd_setnumber	=> pd_setnumber_sig,

		avs_reset		=> csi_csr_reset,
		avs_clk			=> csi_csr_clk,
		avs_address		=> avs_csr_address,
		avs_read		=> avs_csr_read,
		avs_readdata	=> avs_csr_readdata,
		avs_write		=> avs_csr_write,
		avs_writedata	=> avs_csr_writedata,
		ins_irq			=> ins_csr_irq
	);



end RTL;
