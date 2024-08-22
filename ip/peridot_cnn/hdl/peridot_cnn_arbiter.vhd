-- ===================================================================
-- TITLE : PERIDOT-NGS / Compact CNN Accelerator - avmm arbiter
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2020/09/02 -> 2020/09/23
--            : 2020/09/23 (FIXED)
--
--     UPDATE : 2023/11/30 -> 2023/12/12
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
-- [X] 全結合モジュールのリードポート追加 
-- [X] ポートの優先順変更 (wbwrite→param→accum/fc→kernelの順)
--
-- ・検証残り 
-- [X] AvalonMMバーストマスタの動作 
-- [X] 各ポートの調停動作 
-- [X] ReadおよびWriteのバースト動作 → writebackモジュール側の1ワードバースト時の動作を確認する 
-- [X] カーネルポートの調停動作 
-- [X] カーネルポートのリードフュージョン動作 
--
-- ・リソース概算 
--   300LE (32bit幅, 64バースト, リードフュージョンなし)
--   480LE (32bit幅, 256バースト, 4カーネル, リードフュージョンあり)
--  1070LE (256bit幅, 1024バースト, 8カーネル, リードフュージョンあり)


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

entity peridot_cnn_arbiter is
	generic(
		DATABUS_POW2_NUMBER		: integer := 5;		-- データバス幅 (5:32bit / 6:64bit / 7:128bit / 8:256bit)
		MAXBURST_POW2_NUMBER	: integer := 8;		-- バースト長 (3:8ワード ～ 10:1024ワード)
		USE_KERNELREAD_FUSION	: string := "ON";	-- カーネルリード要求の融合を行う 

		-- SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
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
end peridot_cnn_arbiter;

architecture RTL of peridot_cnn_arbiter is
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
	constant MAX_ARBITRATION	: integer := 8;							-- 調停数上限(テスト以外は8で固定)
	constant ALIGN_ADDR_WIDTH	: integer := DATABUS_POW2_NUMBER-3;		-- ワード境界のアドレスビット幅 


	-- AvalonMMバーストマスタブロック 
	type DEF_STATE_AVMM is (AVMM_IDLE, AVMM_WRITEDATA, AVMM_READREQ, AVMM_READDATA);
	signal state_avmm : DEF_STATE_AVMM;
	signal read_reg				: std_logic;
	signal write_reg			: std_logic;
	signal address_reg			: std_logic_vector(31 downto ALIGN_ADDR_WIDTH);
	signal burstcount_reg		: std_logic_vector(avm_burstcount'range);
	signal paramvalid_reg		: std_logic;
	signal accumvalid_reg		: std_logic;
	signal fcvalid_reg			: std_logic;
	signal kernelvalid_reg		: std_logic_vector(read_datavalid'range);
	signal waitrequest_sig		: std_logic;
	signal readdatavalid_sig	: std_logic;
	signal readdata_sig			: std_logic_vector(avm_readdata'range);
	signal param_complete_sig	: std_logic;
	signal accum_complete_sig	: std_logic;
	signal fc_complete_sig		: std_logic;

	-- カーネルリード要求統合ブロック 
	signal kernel_req_reg		: std_logic;
	signal kernel_address_reg	: std_logic_vector(31 downto ALIGN_ADDR_WIDTH);
	signal kernel_burst_reg		: std_logic_vector(avm_burstcount'range);
	signal kernel_complete_sig	: std_logic;

	type DEF_KERNEL_ADDRESS is array(0 to 7) of std_logic_vector(kernel_address_reg'range);
	signal kernel_address_sig	: DEF_KERNEL_ADDRESS;
	type DEF_KERNEL_BURSTCOUNT is array(0 to 7) of std_logic_vector(kernel_burst_reg'range);
	signal kernel_burst_sig		: DEF_KERNEL_BURSTCOUNT;
	signal fusion_valid_sig		: std_logic_vector(7*7+6 downto 1*7+0) := (others=>'0');
	signal fusion_valid_reg		: std_logic_vector(fusion_valid_sig'range);
	signal read_request_reg		: std_logic_vector(read_request'range);
	signal datavalid_ena_reg	: std_logic_vector(read_datavalid'range);

begin

	-- テスト記述 


	-- パラメータ範囲チェック 

	assert (DATABUS_POW2_NUMBER >= 5 and DATABUS_POW2_NUMBER <= 8)
		report "DATABUS_POW2_NUMBER is out of range.";

	assert (MAXBURST_POW2_NUMBER >= 3 and MAXBURST_POW2_NUMBER <= 10)
		report "MAXBURST_POW2_NUMBER is out of range.";



	----------------------------------------------------------------------
	-- AvalonMMバーストマスタ制御 
	----------------------------------------------------------------------

	-- AvalonMM信号 

	avm_address <= address_reg & repbit('0', ALIGN_ADDR_WIDTH);
	avm_burstcount <= burstcount_reg;
	waitrequest_sig <= avm_waitrequest;

	avm_read <= read_reg;
	readdatavalid_sig <= avm_readdatavalid;
	readdata_sig <= avm_readdata;

	avm_write <= write_reg;
	avm_writedata <= wbwrite_data;
	avm_byteenable <= wbwrite_byteenable when is_true(write_reg) else (others=>'1');


	-- AvalonMMへの調停 

	param_complete_sig <= paramread_complete;-- when is_true(paramvalid_reg) else '0';
	paramread_datavalid <= readdatavalid_sig when is_true(paramvalid_reg) else '0';
	paramread_data <= readdata_sig;

	accum_complete_sig <= accumread_complete;-- when is_true(accumvalid_reg) else '0';
	accumread_datavalid <= readdatavalid_sig when is_true(accumvalid_reg) else '0';
	accumread_data <= readdata_sig;

	fc_complete_sig <= fcread_complete;-- when is_true(fcvalid_reg) else '0';
	fcread_datavalid <= readdatavalid_sig when is_true(fcvalid_reg) else '0';
	fcread_data <= readdata_sig;

	wbwrite_dataack <= write_reg when is_false(waitrequest_sig) else '0';

	process (clk, reset) begin
		if is_true(reset) then
			state_avmm <= AVMM_IDLE;
			read_reg <= '0';
			write_reg <= '0';
			paramvalid_reg <= '0';
			accumvalid_reg <= '0';
			fcvalid_reg <= '0';
			kernelvalid_reg <= (others=>'0');

		elsif rising_edge(clk) then
			case state_avmm is

			-- 各ポートからの要求を待つ 
			when AVMM_IDLE =>
				if is_true(paramread_request) then
					state_avmm <= AVMM_READREQ;
					read_reg <= '1';
					address_reg <= paramread_address(address_reg'range);
					burstcount_reg <= paramread_burstcount;
					paramvalid_reg <= '1';

				elsif is_true(kernel_req_reg) then
					state_avmm <= AVMM_READREQ;
					read_reg <= '1';
					address_reg <= kernel_address_reg;
					burstcount_reg <= kernel_burst_reg;
					kernelvalid_reg <= datavalid_ena_reg;

				elsif is_true(accumread_request) then
					state_avmm <= AVMM_READREQ;
					read_reg <= '1';
					address_reg <= accumread_address(address_reg'range);
					burstcount_reg <= accumread_burstcount;
					accumvalid_reg <= '1';

				elsif is_true(fcread_request) then
					state_avmm <= AVMM_READREQ;
					read_reg <= '1';
					address_reg <= fcread_address(address_reg'range);
					burstcount_reg <= fcread_burstcount;
					fcvalid_reg <= '1';

				elsif is_true(wbwrite_request) then
					state_avmm <= AVMM_WRITEDATA;
					write_reg <= '1';
					address_reg <= wbwrite_address(address_reg'range);
					burstcount_reg <= wbwrite_burstcount;

				end if;


			-- バーストライトアクセス 
			when AVMM_WRITEDATA =>
				if is_true(wbwrite_burstend) then
					state_avmm <= AVMM_IDLE;
					write_reg <= '0';
				end if;

			-- バーストリードアクセス 
			when AVMM_READREQ =>
				if is_false(waitrequest_sig) then
					state_avmm <= AVMM_READDATA;
					read_reg <= '0';
				end if;

			when AVMM_READDATA =>
				if is_true(param_complete_sig) or is_true(accum_complete_sig) or is_true(fc_complete_sig) or is_true(kernel_complete_sig) then
					state_avmm <= AVMM_IDLE;
					paramvalid_reg <= '0';
					accumvalid_reg <= '0';
					fcvalid_reg <= '0';
					kernelvalid_reg <= (others=>'0');
				end if;

			when others =>
			end case;
		end if;
	end process;



	----------------------------------------------------------------------
	-- カーネルリード要求を統合 
	----------------------------------------------------------------------
	-- * read fusion時はリクエスト→avmm受理に3クロック分必要 

	-- アドレスおよびバースト長の一致判定 

	kernel_address_sig(0) <= read_0_address(31 downto ALIGN_ADDR_WIDTH);
	kernel_address_sig(1) <= read_1_address(31 downto ALIGN_ADDR_WIDTH);
	kernel_address_sig(2) <= read_2_address(31 downto ALIGN_ADDR_WIDTH);
	kernel_address_sig(3) <= read_3_address(31 downto ALIGN_ADDR_WIDTH);
	kernel_address_sig(4) <= read_4_address(31 downto ALIGN_ADDR_WIDTH);
	kernel_address_sig(5) <= read_5_address(31 downto ALIGN_ADDR_WIDTH);
	kernel_address_sig(6) <= read_6_address(31 downto ALIGN_ADDR_WIDTH);
	kernel_address_sig(7) <= read_7_address(31 downto ALIGN_ADDR_WIDTH);

	kernel_burst_sig(0) <= read_0_burstcount;
	kernel_burst_sig(1) <= read_1_burstcount;
	kernel_burst_sig(2) <= read_2_burstcount;
	kernel_burst_sig(3) <= read_3_burstcount;
	kernel_burst_sig(4) <= read_4_burstcount;
	kernel_burst_sig(5) <= read_5_burstcount;
	kernel_burst_sig(6) <= read_6_burstcount;
	kernel_burst_sig(7) <= read_7_burstcount;

	gen_fusion : if (USE_KERNELREAD_FUSION = "ON" and MAX_ARBITRATION > 1) generate
		gen_loop_i : for i in 1 to MAX_ARBITRATION-1 generate
			gen_loop_j : for j in 0 to i-1 generate
				fusion_valid_sig(i*7+j) <=
					'1' when(kernel_address_sig(i) = kernel_address_sig(j) and kernel_burst_sig(i) = kernel_burst_sig(j)) else '0';
			end generate;
		end generate;
	end generate;


	-- カーネルリード要求の調停 

	read_datavalid <= kernelvalid_reg when is_true(readdatavalid_sig) else (others=>'0');
	read_data <= readdata_sig;
	kernel_complete_sig <= or_reduce(read_complete and kernelvalid_reg);


	process (clk, reset) begin
		if is_true(reset) then
			read_request_reg <= (others=>'0');
			datavalid_ena_reg <= (others=>'0');
			kernel_req_reg <= '0';

		elsif rising_edge(clk) then
			read_request_reg <= read_request and(not kernelvalid_reg);
			fusion_valid_reg <= fusion_valid_sig;

			-- リードリクエストの発行 
			kernel_req_reg <= or_reduce(read_request_reg);

			-- 優先度の低いリクエストの中に同じ領域をアクセスするものがあれば融合する 
			if is_true(read_request_reg(7)) then
				kernel_address_reg <= kernel_address_sig(7);
				kernel_burst_reg <= kernel_burst_sig(7);
				datavalid_ena_reg <= '1' & (fusion_valid_reg(7*7+6 downto 7*7+0) and read_request_reg(6 downto 0));

			elsif is_true(read_request_reg(6)) then
				kernel_address_reg <= kernel_address_sig(6);
				kernel_burst_reg <= kernel_burst_sig(6);
				datavalid_ena_reg <= "01" & (fusion_valid_reg(6*7+5 downto 6*7+0) and read_request_reg(5 downto 0));

			elsif is_true(read_request_reg(5)) then
				kernel_address_reg <= kernel_address_sig(5);
				kernel_burst_reg <= kernel_burst_sig(5);
				datavalid_ena_reg <= "001" & (fusion_valid_reg(5*7+4 downto 5*7+0) and read_request_reg(4 downto 0));

			elsif is_true(read_request_reg(4)) then
				kernel_address_reg <= kernel_address_sig(4);
				kernel_burst_reg <= kernel_burst_sig(4);
				datavalid_ena_reg <= "0001" & (fusion_valid_reg(4*7+3 downto 4*7+0) and read_request_reg(3 downto 0));

			elsif is_true(read_request_reg(3)) then
				kernel_address_reg <= kernel_address_sig(3);
				kernel_burst_reg <= kernel_burst_sig(3);
				datavalid_ena_reg <= "00001" & (fusion_valid_reg(3*7+2 downto 3*7+0) and read_request_reg(2 downto 0));

			elsif is_true(read_request_reg(2)) then
				kernel_address_reg <= kernel_address_sig(2);
				kernel_burst_reg <= kernel_burst_sig(2);
				datavalid_ena_reg <= "000001" & (fusion_valid_reg(2*7+1 downto 2*7+0) and read_request_reg(1 downto 0));

			elsif is_true(read_request_reg(1)) then
				kernel_address_reg <= kernel_address_sig(1);
				kernel_burst_reg <= kernel_burst_sig(1);
				datavalid_ena_reg <= "0000001" & (fusion_valid_reg(1*7+0) and read_request_reg(0));

			elsif is_true(read_request_reg(0)) then
				kernel_address_reg <= kernel_address_sig(0);
				kernel_burst_reg <= kernel_burst_sig(0);
				datavalid_ena_reg <= "00000001";

			end if;

		end if;
	end process;



end RTL;
