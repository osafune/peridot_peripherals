// ===================================================================
// TITLE : PERIDOT ESN - Reservoir readout unit
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2026/03/09 -> 2026/03/17
//            : 2026/03/26 (FIXED)
//
// ===================================================================
//
// The MIT License (MIT)
// Copyright (c) 2026 J-7SYSTEM WORKS LIMITED.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is furnished to do
// so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_esn_readout #(
	parameter RESERVOIR_NODE_BITWIDTH = 9,	// リザバーの最大ノード数(9=511nodes, 10=1023nodes, 11=2047nodes, 12=4095nodes)
	parameter ACCUMFIFO_DEPTH_BITWIDTH = 6,	// アキュムレーターFIFOの最大ワード数(6=64words, 7=128words, 8=256words, 9=512words)
	parameter WOUTMEM_BITWIDTH = 12,		// Wout重みテーブルメモリのワード数(10=1024words, 11=2048words, 12=4096words, 13=8192words)
	parameter USE_FIFOFLOW_CHECKING = "ON",	// "ON"=fifoのフローチェック機能を使う
	parameter USE_WOUTMEM_OUTPUT_REG = "OFF",	// "ON"=mem_qの出力レジスタを使う

	// SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone 10 GX" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
	parameter DEVICE_FAMILY = "Cyclone III"
) (
	output wire [9:0]	test_fifo_usedw,
	output wire			test_fifo_full,
	output wire			test_fifo_empty,
	output wire [25:0]	test_fifo_data,
	output wire [25:0]	test_fifo_q,
	output wire [17:0]	test_wout_b,
	output wire			test_init,
	output wire			test_start,
	output wire			test_end,
	output wire			test_wout_rdaddrinc,
	output wire			test_fifo_rdreq,
	output wire			test_fifo_wrreq,


	input wire			reset,
	input wire			clk,

	// Interfce: Module operation settings
	input wire  [9:0]	n_output,		// 符号無し10bit整数(S0.INT10), 設定値:1～(2^ACCUMFIFO_DEPTH_BITWIDTH)-1

	// Interface: Avalon-ST Sink
	output wire			sti_ready,
	input wire			sti_valid,
	input wire  [17:0]	sti_data,			// xi(t)
	input wire			sti_startofpacket,
	input wire			sti_endofpacket,

	// Interface: Avalon-ST Source
	output wire			sto_valid,
	output wire [17:0]	sto_data,			// yk(t)
	output wire			sto_startofpacket,
	output wire			sto_endofpacket,

	// Interface: Wout tablemem read/write (csr clock domain)
	input wire			mem_clk,
	input wire  [WOUTMEM_BITWIDTH-1:0] mem_addr,
	input wire  [17:0]	mem_data,
	input wire			mem_wren,
	output wire [17:0]	mem_q
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam ACCUMREG_BITWIDTH = (32+7 + RESERVOIR_NODE_BITWIDTH);
	localparam FIFO_DATA_BITWIDTH = (ACCUMREG_BITWIDTH + 1) >> 1;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;		// モジュール内部駆動クロック 

	wire			init_sig;
	wire			start_sig;
	wire			end_sig;
	wire			in_ready_sig;
	reg				busy_reg;
	reg				sop_reg;
	reg				eop_reg;
	reg				initdone_reg;
	reg  [3:0]		state_reg;
	reg  [ACCUMFIFO_DEPTH_BITWIDTH:0] y_count_reg;
	reg  [ACCUMFIFO_DEPTH_BITWIDTH-1:0] n_output_reg;
	wire			is_processing_sig;

	reg  [WOUTMEM_BITWIDTH-1:0] mem_wout_rdaddr_reg;
	wire			wout_rdaddrinc_sig;
	wire [17:0]		wout_q_sig;

	reg  [17:0]		xit_reg;
	wire [17:0]		wout_b_sig;
	wire [35:0]		wout_mult_sig;
	reg  [31:0]		wout_mult_reg;
	reg  [2:0]		wout_exp_reg;
	reg  [38:0]		wout_reg;

	wire [ACCUMREG_BITWIDTH-1:0] y_add_sig;
	reg  [ACCUMREG_BITWIDTH-1:0] y_add_reg;
	reg				y_add_latch_reg;
	wire			y_saturation_sig;
	wire [17:0]		y_activation_sig;
	reg  [17:0]		y_out_reg;
	reg				y_out_valid_reg;

	reg				fifo_datasel_reg;
	wire			fifo_wrreq_sig;
	wire [FIFO_DATA_BITWIDTH-1:0] fifo_data_sig;
	wire			fifo_rdreq_sig;
	wire [FIFO_DATA_BITWIDTH-1:0] fifo_q_sig;
	wire [ACCUMFIFO_DEPTH_BITWIDTH:0] fifo_usedw_sig;
	wire			fifo_full_sig;
	wire			fifo_empty_sig;
	wire [FIFO_DATA_BITWIDTH-1:0] y_halfdata_sig;
	reg  [ACCUMREG_BITWIDTH-1:0] y_accum_reg = 1'd0;	// Warning回避のため明示的に初期値を付けておく 


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */

	assign test_fifo_usedw = fifo_usedw_sig;
	assign test_fifo_full = fifo_full_sig;
	assign test_fifo_empty = fifo_empty_sig;
	assign test_init = init_sig;
	assign test_start = start_sig;
	assign test_end = end_sig;
	assign test_wout_rdaddrinc = wout_rdaddrinc_sig;
	assign test_fifo_rdreq = fifo_rdreq_sig;
	assign test_fifo_wrreq = fifo_wrreq_sig;

	assign test_wout_b = wout_b_sig;
	assign test_fifo_data = fifo_data_sig;
	assign test_fifo_q = fifo_q_sig;


/* ===== モジュール構造記述 ============== */

	// 確率補正用の関数 

	function [17:0] correct(input [17:0] data);
	begin
		correct = data | ((data == 18'h20000)? 1'b1 : 1'b0);
	end
	endfunction


	// モジュールパイプライン制御 

	assign in_ready_sig = (init_sig || busy_reg)? 1'b0 : 1'b1;
	assign sti_ready = in_ready_sig;

	assign init_sig = (!busy_reg && !initdone_reg && sti_valid && sti_startofpacket);
	assign start_sig = (in_ready_sig && sti_valid);
	assign end_sig = (state_reg == 4'b1000);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			busy_reg <= 1'b0;
			initdone_reg <= 1'b0;
			state_reg <= 4'b0000;
		end
		else begin
			if (start_sig) begin
				busy_reg <= 1'b1;
			end
			else if (end_sig) begin
				busy_reg <= 1'b0;
			end

			if (init_sig) begin
				initdone_reg <= 1'b1;
			end
			else if (end_sig) begin
				initdone_reg <= 1'b0;
			end

			state_reg <= {state_reg[2:0], is_processing_sig};
			y_add_latch_reg <= (state_reg[1] && !y_add_latch_reg);
			fifo_datasel_reg <= y_add_latch_reg;
			y_out_valid_reg <= (eop_reg && fifo_datasel_reg);

			if (start_sig) begin
				y_count_reg <= {n_output_reg, 1'b0};
			end
			else if (y_count_reg != 1'd0) begin
				y_count_reg <= y_count_reg - 1'd1;
			end

			if (init_sig) begin
				sop_reg <= 1'b1;
			end
			else if (y_out_valid_reg) begin
				sop_reg <= 1'b0;
			end

			if (init_sig) begin
				eop_reg <= 1'b0;
			end
			else if (start_sig) begin
				eop_reg <= sti_endofpacket;
			end

			if (init_sig) begin
				n_output_reg <= n_output[ACCUMFIFO_DEPTH_BITWIDTH-1:0];
			end
		end
	end

	assign is_processing_sig = (busy_reg && y_count_reg != 1'd0);

	assign wout_rdaddrinc_sig = (start_sig || (y_count_reg[0] && y_count_reg[ACCUMFIFO_DEPTH_BITWIDTH:1] != 1'd0));
	assign fifo_rdreq_sig = (!initdone_reg && is_processing_sig);
	assign fifo_wrreq_sig = (!eop_reg && state_reg[3]);

	assign sto_valid = y_out_valid_reg;
	assign sto_data = y_out_reg;
	assign sto_startofpacket = sop_reg;
	assign sto_endofpacket = (eop_reg && end_sig);


	// リードアウト重みテーブル用メモリマクロ 

	always @(posedge clock_sig) begin
		if (init_sig) begin
			mem_wout_rdaddr_reg <= 1'd0;
		end
		else if (wout_rdaddrinc_sig) begin
			mem_wout_rdaddr_reg <= mem_wout_rdaddr_reg + 1'd1;
		end
	end

	peridot_esn_dcdpram #(
		.RAM_NUMWORD_BITWIDTH		(WOUTMEM_BITWIDTH),
		.USE_READDATA_B_OUTPUT_REG	(USE_WOUTMEM_OUTPUT_REG),
		.DEVICE_FAMILY				(DEVICE_FAMILY)
	)
	u_mem (
		.clk_a			(clock_sig),
		.address_a		(mem_wout_rdaddr_reg),
		.writedata_a	(18'd0),
		.writeenable_a	(1'b0),
		.readdata_a		(wout_q_sig),

		.clk_b			(mem_clk),
		.address_b		(mem_addr),
		.writedata_b	(mem_data),
		.writeenable_b	(mem_wren),
		.readdata_b		(mem_q)
	);


	// Wout * xi(t)の値の計算 

	lpm_mult #(
		.lpm_type			("LPM_MULT"),
		.lpm_hint			("MAXIMIZE_SPEED=5"),
		.lpm_representation	("SIGNED"),
		.lpm_widtha			(18),
		.lpm_widthb			(18),
		.lpm_widthp			(36)
	)
	u_mul_wout (
		.dataa	(xit_reg),
		.datab	(wout_b_sig),
		.result	(wout_mult_sig)
	);

	assign wout_b_sig = $signed(wout_q_sig[14:0]);

	always @(posedge clock_sig) begin
		if (start_sig) begin
			xit_reg <= sti_data;
		end

		wout_mult_reg <= wout_mult_sig[31:0];
		wout_exp_reg <= wout_q_sig[17:15];

		case (wout_exp_reg)
		3'd7 : wout_reg <= $signed({wout_mult_reg, 7'b0});	// 16
		3'd6 : wout_reg <= $signed({wout_mult_reg, 6'b0});	//  8
		3'd5 : wout_reg <= $signed({wout_mult_reg, 5'b0});	//  4
		3'd4 : wout_reg <= $signed({wout_mult_reg, 4'b0});	//  2
		3'd3 : wout_reg <= $signed({wout_mult_reg, 3'b0});	//  1 (S1.INT0.DEC34)
		3'd2 : wout_reg <= $signed({wout_mult_reg, 2'b0});	// 1/2
		3'd1 : wout_reg <= $signed({wout_mult_reg, 1'b0});	// 1/4
		default : wout_reg <= $signed(wout_mult_reg);		// 1/8
		endcase
	end


	// yk(t)の累算と活性化関数適用

	assign y_add_sig = $signed(y_accum_reg) + $signed(wout_reg);

	assign y_saturation_sig = (&y_add_reg[ACCUMREG_BITWIDTH-1:17+18-1] != |y_add_reg[ACCUMREG_BITWIDTH-1:17+18-1]);
	assign y_activation_sig = (!y_saturation_sig)? correct(y_add_reg[17+18-1:17]) :	// 飽和していない
						(y_add_reg[ACCUMREG_BITWIDTH-1])? 18'h20001 : 18'h1ffff;	// 正負で飽和 

	always @(posedge clock_sig) begin
		if (y_add_latch_reg) begin
			y_add_reg <= y_add_sig;
		end

		y_out_reg <= y_activation_sig;
	end


	// アキュムレーター用FIFO 

	assign fifo_data_sig = (fifo_datasel_reg)? y_add_reg[ACCUMREG_BITWIDTH-1:FIFO_DATA_BITWIDTH] : y_add_reg[FIFO_DATA_BITWIDTH-1:0];

	scfifo #(
		.lpm_type			("scfifo"),
		.intended_device_family (DEVICE_FAMILY),
		.lpm_width			(FIFO_DATA_BITWIDTH),
		.lpm_widthu			(ACCUMFIFO_DEPTH_BITWIDTH+1),
		.lpm_numwords		(2**(ACCUMFIFO_DEPTH_BITWIDTH+1)),
		.lpm_showahead		("OFF"),
		.overflow_checking	(USE_FIFOFLOW_CHECKING),
		.underflow_checking	(USE_FIFOFLOW_CHECKING),
		.add_ram_output_register ("OFF"),
		.use_eab			("ON")
	)
	u_fifo (
		.usedw	(fifo_usedw_sig),
		.full	(fifo_full_sig),
		.empty	(fifo_empty_sig),

		.clock	(clock_sig),
		.sclr	(init_sig),
		.wrreq	(fifo_wrreq_sig),
		.data	(fifo_data_sig),
		.rdreq	(fifo_rdreq_sig),
		.q		(fifo_q_sig)
	);

	assign y_halfdata_sig = (initdone_reg)? 1'd0 : fifo_q_sig;

	always @(posedge clock_sig) begin
		y_accum_reg <= {y_accum_reg[(ACCUMREG_BITWIDTH-FIFO_DATA_BITWIDTH)-1:0], y_halfdata_sig};
	end


endmodule

`default_nettype wire
