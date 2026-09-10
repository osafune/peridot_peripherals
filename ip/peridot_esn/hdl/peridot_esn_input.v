// ===================================================================
// TITLE : PERIDOT ESN - Reservoir input/feedback unit
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2026/03/09 -> 2026/03/17
//            : 2026/03/26 (FIXED)
//     UPDATE : 2026/06/09
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

module peridot_esn_input #(
	parameter RESERVOIR_NODE_BITWIDTH = 9,	// リザバーの最大ノード数(9=511nodes, 10=1023nodes, 11=2047nodes, 12=4095nodes)
	parameter INPUTBUFFER_BITWIDTH = 8,		// 入出力バッファの最大ワード数(8=256words, 9=512words, 10=1024words)
	parameter USE_INPUTBUFFER_OUTPUT_REG = "OFF",	// "ON"=mem_qの出力レジスタを使う

	// SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone 10 GX" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
	parameter DEVICE_FAMILY = "Cyclone III"
) (
	output wire			test_rand_update,
	output wire			test_uy_sum_latch,
	output wire			test_start,
	output wire			test_end,
	output wire			test_row_begin,
	output wire			test_row_end,
	output wire [10:0]	test_mem_uv_addr,
	output wire [17:0]	test_mem_uy_q,
	output wire			test_mem_uy_wren,


	input wire			reset,
	input wire			clk,

	input wire			start,			// 1=処理開始リクエスト(busy=0のときのみ有効)
	output wire			busy,			// 1=処理中 / 0=待機

	// Interfce: Module operation settings
	input wire			working_page,
	input wire			state_clear,	// 1=内部状態を初期化
	input wire  [11:0]	n_node,			// 符号無し12bit整数(S0.INT12), 設定値:1～(2^RESERVOIR_NODE_BITWIDTH)-1
	input wire  [9:0]	n_input,		// 符号無し10bit整数(S0.INT10), 設定値:1～(2^INPUTBUFFER_BITWIDTH)-1
	input wire  [9:0]	n_output,		// 符号無し10bit整数(S0.INT10), 設定値:1～(2^ACCUMFIFO_DEPTH_BITWIDTH)-1
	input wire  [31:0]	seed,			// 符号無し32bit整数(S0.INT32)
	input wire  [16:0]	scale_in,		// 符号無し17bit固定小数(S0.INT1.DEC16), 設定範囲:0～1.0
	input wire  [16:0]	scale_fb,		// 符号無し17bit固定小数(S0.INT1.DEC16), 設定範囲:0～1.0

	// Interface: Avalon-ST Source
	input wire			sto_ready,
	output wire			sto_valid,
	output wire [47:0]	sto_data,			// ΣWin * u(t) + ΣWfb * y(t-1)
	output wire			sto_startofpacket,
	output wire			sto_endofpacket,

	// Interface: Avalon-ST Sink
	output wire			sti_ready,
	input wire			sti_valid,
	input wire  [17:0]	sti_data,			// y(t)
	input wire			sti_startofpacket,	// 未使用
	input wire			sti_endofpacket,

	// Interface: Input buffer read/write (csr clock domain)
	input wire			mem_clk,
	input wire  [INPUTBUFFER_BITWIDTH:0] mem_addr,
	input wire  [17:0]	mem_data,
	input wire			mem_wren,
	output wire [17:0]	mem_q
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam	RAND_TAP1	= 3,	// Xorshiftの生成パラメーター
				RAND_TAP2	= 13,
				RAND_TAP3	= 7;

	localparam ACCUMREG_BITWIDTH = (35 + INPUTBUFFER_BITWIDTH);


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;		// モジュール内部駆動クロック 

	wire			start_sig;
	wire			end_sig;
	wire			row_begin_sig;
	wire			row_end_sig;
	wire			in_valid_sig;
	reg				busy_reg;
	reg				uy_countup_reg;
	reg				y_writeback_reg;
	reg  [2:0]		uy_sum_delay_reg;
	reg				uv_sum_valid_reg;
	reg  [INPUTBUFFER_BITWIDTH-1:0] uy_count_reg;
	reg  [RESERVOIR_NODE_BITWIDTH-1:0] row_count_reg;
	reg				sop_reg;

	reg  [INPUTBUFFER_BITWIDTH-1:0] n_input_reg;
	reg  [INPUTBUFFER_BITWIDTH-1:0] n_output_reg;
	reg  [16:0]		scale_in_reg;
	reg  [16:0]		scale_fb_reg;
	reg				state_clear_reg;
	reg				working_page_reg;

	wire			rand_update_sig;
	wire [31:0]		rand_q_sig;

	reg				scale_sel_reg;
	wire			scale_sel_clear_sig;
	wire [16:0]		scale_b_sig;
	reg  [16:0]		scale_b_reg;
	wire [17:0]		winfb_data_sig;
	reg  [17:0]		winfb_data_reg;
	wire [35:0]		winfb_mult_sig;
	reg  [17:0]		winfb_mult_reg;

	reg  [INPUTBUFFER_BITWIDTH-1:0] mem_y_wraddr_reg;
	wire [INPUTBUFFER_BITWIDTH:0] mem_uy_addr_sig;
	wire [17:0]		mem_uy_q_sig;

	wire [35:0]		uy_mult_sig;
	reg  [34:0]		uy_mult_reg;
	wire [ACCUMREG_BITWIDTH-1:0] uy_add_sig;
	reg  [ACCUMREG_BITWIDTH-1:0] uy_sum_reg;
	wire			uy_sum_latch_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */

	assign test_start = start_sig;
	assign test_end = end_sig;
	assign test_row_begin = row_begin_sig;
	assign test_row_end = row_end_sig;
	assign test_rand_update = rand_update_sig;
	assign test_uy_sum_latch = uy_sum_latch_sig;

	assign test_mem_uv_addr = mem_uy_addr_sig;
	assign test_mem_uy_q = mem_uy_q_sig;
	assign test_mem_uy_wren = in_valid_sig;


/* ===== モジュール構造記述 ============== */

	// 確率補正用の関数 

	function [17:0] correct(input [17:0] data);
	begin
		correct = data | ((data == 18'h20000)? 1'b1 : 1'b0);
	end
	endfunction


	// モジュールパイプライン制御 

	assign busy = busy_reg;
	assign start_sig = (!busy_reg && start);
	assign end_sig = (busy_reg && in_valid_sig && sti_endofpacket);
	assign row_begin_sig = (busy_reg && uy_count_reg == 1'd0);
	assign row_end_sig = (sto_ready && uv_sum_valid_reg);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			busy_reg <= 1'b0;
			uy_countup_reg <= 1'b0;
			y_writeback_reg <= 1'b0;
			uy_sum_delay_reg <= 3'b000;
			uv_sum_valid_reg <= 1'b0;
		end
		else begin
			if (start_sig) begin
				busy_reg <= 1'b1;
			end
			else if (end_sig) begin
				busy_reg <= 1'b0;
			end

			if (start_sig || (row_end_sig && row_count_reg != 1'd1)) begin
				uy_countup_reg <= 1'b1;
			end
			else if (uy_countup_reg && uy_count_reg == n_input_reg + n_output_reg - 1'd1) begin
				uy_countup_reg <= 1'b0;
			end

			if (start_sig || row_end_sig) begin
				uy_count_reg <= 1'd0;
			end
			else if (uy_countup_reg) begin
				uy_count_reg <= uy_count_reg + 1'd1;
			end

			uy_sum_delay_reg <= {uy_sum_delay_reg[1:0], uy_countup_reg};

			if (uy_sum_delay_reg == 3'b100) begin
				uv_sum_valid_reg <= 1'b1;
			end
			else if (row_end_sig) begin
				uv_sum_valid_reg <= 1'b0;
			end

			if (start_sig || end_sig) begin
				y_writeback_reg <= 1'b0;
			end
			else if (!y_writeback_reg && row_end_sig && row_count_reg == 1'd1) begin
				y_writeback_reg <= 1'b1;
			end

			if (start_sig) begin
				row_count_reg <= n_node[RESERVOIR_NODE_BITWIDTH-1:0];
			end
			else if (!y_writeback_reg && row_end_sig) begin
				row_count_reg <= row_count_reg - 1'd1;
			end

			if (start_sig) begin
				sop_reg <= 1'b1;
			end
			else if (row_end_sig) begin
				sop_reg <= 1'b0;
			end

			if (start_sig) begin
				n_input_reg <= n_input[INPUTBUFFER_BITWIDTH-1:0];
				n_output_reg <= n_output[INPUTBUFFER_BITWIDTH-1:0];
				scale_in_reg <= scale_in;
				scale_fb_reg <= scale_fb;
				state_clear_reg <= state_clear;
				working_page_reg <= working_page;
			end
		end
	end

	assign rand_update_sig = uy_countup_reg;
	assign scale_sel_clear_sig = (uy_count_reg == n_input_reg - 1'd1);
	assign uy_sum_latch_sig = uy_sum_delay_reg[2];

	assign sto_valid = uv_sum_valid_reg;
	assign sto_data = $signed(uy_sum_reg);
	assign sto_startofpacket = sop_reg;
	assign sto_endofpacket = (row_count_reg == 1'd1)? 1'b1 : 1'b0;

	assign sti_ready = y_writeback_reg;
	assign in_valid_sig = (y_writeback_reg && sti_valid);


	// 入力・フィードバック結合重み行列用の乱数生成 

	peridot_esn_xorshift32 #(
		.SHIFT_SET_PARAM1	(RAND_TAP1),
		.SHIFT_SET_PARAM2	(RAND_TAP2),
		.SHIFT_SET_PARAM3	(RAND_TAP3)
	)
	u_rand (
		.clk			(clock_sig),
		.init			(start_sig),
		.seed			(seed),
		.update			(rand_update_sig),
		.data			(rand_q_sig)
	);

	assign winfb_data_sig = correct(rand_q_sig[17:0]);


	// W_in/W_fbの値の計算 

	assign scale_b_sig = (scale_sel_reg)? scale_in_reg : (state_clear_reg)? 1'd0 : scale_fb_reg;

	lpm_mult #(
		.lpm_type			("LPM_MULT"),
		.lpm_hint			("MAXIMIZE_SPEED=5"),
		.lpm_representation	("SIGNED"),
		.lpm_widtha			(18),
		.lpm_widthb			(18),
		.lpm_widthp			(36)
	)
	u_mul_winfb (
		.dataa	(winfb_data_reg),
		.datab	({1'b0, scale_b_reg}),
		.result	(winfb_mult_sig)
	);

	always @(posedge clock_sig) begin
		if (start_sig || row_end_sig) begin
			scale_sel_reg <= 1'b1;
		end
		else if (scale_sel_clear_sig) begin
			scale_sel_reg <= 1'b0;
		end

		winfb_data_reg <= winfb_data_sig;
		scale_b_reg <= scale_b_sig;
		winfb_mult_reg <= winfb_mult_sig[16+18-1:16];
	end


	// 入出力バッファ用メモリマクロ 

	assign mem_uy_addr_sig = (y_writeback_reg)? {~working_page_reg, mem_y_wraddr_reg} : {working_page_reg, uy_count_reg};

	always @(posedge clock_sig) begin
		if (!y_writeback_reg) begin
			mem_y_wraddr_reg <= n_input_reg;
		end
		else if (in_valid_sig) begin
			mem_y_wraddr_reg <= mem_y_wraddr_reg + 1'd1;
		end
	end

	peridot_esn_dcdpram #(
		.RAM_NUMWORD_BITWIDTH		(INPUTBUFFER_BITWIDTH+1),
		.USE_READDATA_B_OUTPUT_REG	(USE_INPUTBUFFER_OUTPUT_REG),
		.DEVICE_FAMILY				(DEVICE_FAMILY)
	)
	u_mem (
		.clk_a			(clock_sig),
		.address_a		(mem_uy_addr_sig),
		.writedata_a	(sti_data),
		.writeenable_a	(in_valid_sig),
		.readdata_a		(mem_uy_q_sig),

		.clk_b			(mem_clk),
		.address_b		(mem_addr),
		.writedata_b	(mem_data),
		.writeenable_b	(mem_wren),
		.readdata_b		(mem_q)
	);


	// W_in * u(t) + W_fb * y(t-1)の計算 

	lpm_mult #(
		.lpm_type			("LPM_MULT"),
		.lpm_hint			("MAXIMIZE_SPEED=5"),
		.lpm_representation	("SIGNED"),
		.lpm_widtha			(18),
		.lpm_widthb			(18),
		.lpm_widthp			(36)
	)
	u_mul_uy (
		.dataa	(winfb_mult_reg),
		.datab	(mem_uy_q_sig),
		.result	(uy_mult_sig)
	);

	assign uy_add_sig = $signed(uy_sum_reg) + $signed(uy_mult_reg);

	always @(posedge clock_sig) begin
		uy_mult_reg <= uy_mult_sig[34:0];

		if (row_begin_sig) begin
			uy_sum_reg <= 1'd0;
		end
		else if (uy_sum_latch_sig) begin
			uy_sum_reg <= uy_add_sig;
		end
	end


endmodule

`default_nettype wire
