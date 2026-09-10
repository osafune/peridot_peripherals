// ===================================================================
// TITLE : PERIDOT ESN - Reservoir status update unit
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2026/03/09 -> 2026/03/25
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

module peridot_esn_reservoir #(
	parameter RESERVOIR_NODE_BITWIDTH = 9,	// リザバーの最大ノード数(9=511nodes, 10=1023nodes, 11=2047nodes, 12=4095nodes)
	parameter USE_XITMEM_OUTPUT_REG = "OFF",	// "ON"=mem_qの出力レジスタを使う

	parameter TEST_WORKING_PAGE_OVERWRITE = 0,
	// SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone 10 GX" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
	parameter DEVICE_FAMILY = "Cyclone III"
) (
	input wire			test_working_page,
	output wire			test_rand_update,
	output wire			test_addr_delta_latch,
	output wire			test_addr_prev_latch,
	output wire			test_xit_sum_latch,
	output wire			test_blend_sel_clear,
	output wire			test_xit_writeback,
	output wire			test_is_processing,
	output wire			test_saturation,
	output wire			test_init,
	output wire			test_start,
	output wire			test_end,
	output wire [12:0]	test_mem_addr,
	output wire [17:0]	test_mem_q,
	output wire [17:0]	test_mem_data,
	output wire			test_mem_wren,


	input wire			reset,
	input wire			clk,

	// Interfce: Module operation settings
	input wire			state_clear,	// 1=内部状態を初期化
	input wire  [11:0]	n_node,			// 符号無し12bit整数(S0.INT12), 設定値:1～(2^RESERVOIR_NODE_BITWIDTH)-1
	input wire  [31:0]	seed,			// 符号無し32bit整数(S0.INT32)
	input wire  [8:0]	density,		// 符号無し9bit整数(S0.INT9), 設定範囲:0～496
	input wire  [16:0]	scale_wres,		// 符号無し17bit固定小数(S0.INT1.DEC16), 設定範囲:0～1.0
	input wire  [16:0]	scale_lr,		// 符号無し17bit固定小数(S0.INT1.DEC16), 設定範囲:0～1.0

	// Interface: Avalon-ST Sink
	output wire			sti_ready,
	input wire			sti_valid,
	input wire  [47:0]	sti_data,			// ΣWin * u(t) + ΣWfb * y(t-1)
	input wire			sti_startofpacket,
	input wire			sti_endofpacket,

	// Interface: Avalon-ST Source
	input wire			sto_ready,
	output wire			sto_valid,
	output wire [17:0]	sto_data,			// xi(t)
	output wire			sto_startofpacket,
	output wire			sto_endofpacket,

	// Interface: state vector read/write (csr clock domain)
	input wire			mem_clk,
	input wire  [RESERVOIR_NODE_BITWIDTH-1:0] mem_addr,
	input wire  [17:0]	mem_data,
	input wire			mem_wren,
	output wire [17:0]	mem_q
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam	RAND_TAP1	= 13,	// Xorshiftの生成パラメーター
				RAND_TAP2	= 17,
				RAND_TAP3	= 5;

	localparam ACCUMREG_BITWIDTH = (35+1 + RESERVOIR_NODE_BITWIDTH);


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
	wire			out_ready_sig;
	reg				busy_reg;
	reg  [6:0]		state_reg;
	reg  [2:0]		xit_sum_delay_reg;
	reg				sop_reg;
	reg				eop_reg;
	reg				initdone_reg;
	reg  [RESERVOIR_NODE_BITWIDTH-1:0] row_num_reg;
	reg  [RESERVOIR_NODE_BITWIDTH-1:0] n_node_reg;
	reg  [8:0]		density_reg;
	reg  [16:0]		scale_wres_reg;
	reg  [16:0]		scale_lr_reg;
	reg				state_clear_reg;
	reg				working_page_reg;
	wire			is_processing_sig;

	wire			rand_update_sig;
	wire [31:0]		rand_q_sig;

	wire [8:0]		density_data_sig;
	wire [17:0]		density_mult_sig;
	wire [17:0]		addr_delta_sig;
	reg  [17:0]		addr_delta_reg;
	wire			addr_delta_latch_sig;
	reg  [RESERVOIR_NODE_BITWIDTH:0] addr_prev_reg;
	wire			addr_prev_latch_sig;
	wire [RESERVOIR_NODE_BITWIDTH:0] addr_next_sig;

	wire [RESERVOIR_NODE_BITWIDTH-1:0] mem_xit_addr_sig;
	wire			mem_xit_page_sig;
	wire [17:0]		mem_xit_q_sig;
	reg				mem_page_reg;

	wire [17:0]		wres_data_sig;
	reg  [17:0]		wres_data_reg;
	wire [35:0]		wres_mult_sig;
	reg  [17:0]		wres_mult_reg;
	wire [35:0]		xit_mult_sig;
	reg  [34:0]		xit_mult_reg;

	wire [ACCUMREG_BITWIDTH-1:0] xit_add_sig;
	reg  [ACCUMREG_BITWIDTH-1:0] xit_sum_reg;
	wire			xit_sum_latch_sig;
	wire			xit_saturation_sig;
	wire [17:0]		xit_activation_sig;

	reg				blend_sel_reg;
	wire			blend_sel_clear_sig;
	wire [17:0]		blend_a_sig;
	reg  [17:0]		blend_a_reg;
	wire [16:0]		blend_b_sig;
	reg  [16:0]		blend_b_reg;
	wire [35:0]		blend_mult_sig;
	reg  [33:0]		blend_mult_reg;
	wire [33:0]		blend_add_sig;
	reg  [33:0]		blend_add_reg;
	wire			blend_add_latch_sig;
	reg				blend_add_latch_reg;
	wire [17:0]		xit_new_sig;
	wire			xit_writeback_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */

	assign test_init = init_sig;
	assign test_start = start_sig;
	assign test_end = end_sig;
	assign test_rand_update = rand_update_sig;
	assign test_addr_delta_latch = addr_delta_latch_sig;
	assign test_addr_prev_latch = addr_prev_latch_sig;
	assign test_xit_sum_latch = xit_sum_latch_sig;
	assign test_blend_sel_clear = blend_sel_clear_sig;
	assign test_xit_writeback = xit_writeback_sig;
	assign test_is_processing = is_processing_sig;
	assign test_saturation = xit_saturation_sig;

	assign test_mem_addr = {mem_xit_page_sig, mem_xit_addr_sig};
	assign test_mem_q = mem_xit_q_sig;
	assign test_mem_data = xit_new_sig;
	assign test_mem_wren = xit_writeback_sig;


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
	assign end_sig = (state_reg[6] && out_ready_sig);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			busy_reg <= 1'b0;
			state_reg <= 7'b000000;
			xit_sum_delay_reg <= 3'b000;
			initdone_reg <= 1'b0;
			working_page_reg <= 1'b0;	// simでx伝搬を回避するために必要 
		end
		else begin
			if (start_sig) begin
				busy_reg <= 1'b1;
			end
			else if (end_sig) begin
				busy_reg <= 1'b0;
			end

			if (!((state_reg[3] && xit_sum_delay_reg[2]) || (state_reg[6] && !out_ready_sig))) begin
				state_reg <= {state_reg[5:0], start_sig};
			end

			xit_sum_delay_reg <= {xit_sum_delay_reg[1:0], is_processing_sig};

			if (start_sig) begin
				sop_reg <= sti_startofpacket;
				eop_reg <= sti_endofpacket;
			end

			if (init_sig) begin
				initdone_reg <= 1'b1;
				row_num_reg <= 1'd0;
			end
			else if (end_sig) begin
				initdone_reg <= 1'b0;
				row_num_reg <= row_num_reg + 1'd1;
			end

			if (init_sig) begin
				n_node_reg <= n_node[RESERVOIR_NODE_BITWIDTH-1:0];
				density_reg <= density;
				scale_wres_reg <= scale_wres;
				scale_lr_reg <= scale_lr;
				state_clear_reg <= state_clear;
				working_page_reg <= (TEST_WORKING_PAGE_OVERWRITE)? test_working_page : ~working_page_reg;
			end
		end
	end

	assign is_processing_sig = (!state_clear_reg && busy_reg && addr_next_sig < n_node_reg);

	assign rand_update_sig = start_sig | is_processing_sig;
	assign addr_delta_latch_sig = start_sig | is_processing_sig;
	assign addr_prev_latch_sig = is_processing_sig;
	assign xit_sum_latch_sig = xit_sum_delay_reg[2];
	assign blend_sel_clear_sig = state_reg[1];
	assign blend_add_latch_sig = state_reg[2] | state_reg[4];
	assign xit_writeback_sig = end_sig;

	assign out_ready_sig = sto_ready;
	assign sto_valid = state_reg[6];
	assign sto_data = xit_new_sig;
	assign sto_startofpacket = sop_reg;
	assign sto_endofpacket = eop_reg;


	// リカレント結合重み行列用の乱数生成 

	peridot_esn_xorshift32 #(
		.SHIFT_SET_PARAM1	(RAND_TAP1),
		.SHIFT_SET_PARAM2	(RAND_TAP2),
		.SHIFT_SET_PARAM3	(RAND_TAP3)
	)
	u_rand (
		.clk			(clock_sig),
		.init			(init_sig),
		.seed			(seed),
		.update			(rand_update_sig),
		.data			(rand_q_sig)
	);

	assign density_data_sig = rand_q_sig[31:31-8];
	assign wres_data_sig = correct(rand_q_sig[17:0]);


	// xi(t-1)の読み出しアドレスの計算 

	lpm_mult #(
		.lpm_type			("LPM_MULT"),
		.lpm_hint			("MAXIMIZE_SPEED=5"),
		.lpm_representation	("UNSIGNED"),
		.lpm_widtha			(9),
		.lpm_widthb			(9),
		.lpm_widthp			(18)
	)
	u_mul_rand (
		.dataa	(density_data_sig),
		.datab	(density_reg),
		.result	(density_mult_sig)
	);

	assign addr_delta_sig = density_mult_sig + {1'b1, addr_delta_reg[11:0]};
	assign addr_next_sig = addr_prev_reg + addr_delta_reg[17:12];

	always @(posedge clock_sig) begin
		if (init_sig) begin
			addr_delta_reg <= 1'd0;
		end
		else if (addr_delta_latch_sig) begin
			addr_delta_reg <= addr_delta_sig;
		end

		if (start_sig) begin
			addr_prev_reg <= $signed(1'b1);		// -1(=全ビット1)を代入 
		end
		else if (addr_prev_latch_sig) begin
			addr_prev_reg <= addr_next_sig;
		end
	end


	// 状態ベクトル格納用メモリマクロ 

	assign mem_xit_addr_sig = (start_sig || xit_writeback_sig)? row_num_reg : addr_next_sig[RESERVOIR_NODE_BITWIDTH-1:0];
	assign mem_xit_page_sig = (xit_writeback_sig)? working_page_reg : ~working_page_reg;

	peridot_esn_dcdpram #(
		.RAM_NUMWORD_BITWIDTH		(RESERVOIR_NODE_BITWIDTH+1),
		.USE_READDATA_B_OUTPUT_REG	(USE_XITMEM_OUTPUT_REG),
		.DEVICE_FAMILY				(DEVICE_FAMILY)
	)
	u_mem (
		.clk_a			(clock_sig),
		.address_a		({mem_xit_page_sig, mem_xit_addr_sig}),
		.writedata_a	(xit_new_sig),
		.writeenable_a	(xit_writeback_sig),
		.readdata_a		(mem_xit_q_sig),

		.clk_b			(mem_clk),
		.address_b		({mem_page_reg, mem_addr}),
		.writedata_b	(mem_data),
		.writeenable_b	(mem_wren),
		.readdata_b		(mem_q)
	);

	always @(posedge mem_clk) begin
		mem_page_reg <= working_page_reg;	// clk_b側のクロックドメインブリッジ
	end


	// W_resの値の計算 

	lpm_mult #(
		.lpm_type			("LPM_MULT"),
		.lpm_hint			("MAXIMIZE_SPEED=5"),
		.lpm_representation	("SIGNED"),
		.lpm_widtha			(18),
		.lpm_widthb			(18),
		.lpm_widthp			(36)
	)
	u_mul_wres (
		.dataa	(wres_data_reg),
		.datab	({1'b0, scale_wres_reg}),
		.result	(wres_mult_sig)
	);

	always @(posedge clock_sig) begin
		wres_data_reg <= wres_data_sig;
		wres_mult_reg <= wres_mult_sig[16+18-1:16];
	end


	// W_res * xi(t-1)の計算 

	lpm_mult #(
		.lpm_type			("LPM_MULT"),
		.lpm_hint			("MAXIMIZE_SPEED=5"),
		.lpm_representation	("SIGNED"),
		.lpm_widtha			(18),
		.lpm_widthb			(18),
		.lpm_widthp			(36)
	)
	u_mul_xit (
		.dataa	(wres_mult_reg),
		.datab	(mem_xit_q_sig),
		.result	(xit_mult_sig)
	);

	assign xit_add_sig = $signed(xit_sum_reg) + $signed(xit_mult_reg);

	always @(posedge clock_sig) begin
		xit_mult_reg <= xit_mult_sig[34:0];

		if (start_sig) begin
			xit_sum_reg <= sti_data[ACCUMREG_BITWIDTH-1:0];
		end
		else if (xit_sum_latch_sig) begin
			xit_sum_reg <= xit_add_sig;
		end
	end


	// 活性化関数適用とリークレート合成 

	assign xit_saturation_sig = (&xit_sum_reg[ACCUMREG_BITWIDTH-1:17+18-1] != |xit_sum_reg[ACCUMREG_BITWIDTH-1:17+18-1]);
	assign xit_activation_sig = (!xit_saturation_sig)? correct(xit_sum_reg[17+18-1:17]) :	// 飽和していない
							(xit_sum_reg[ACCUMREG_BITWIDTH-1])? 18'h20001 : 18'h1ffff;		// 正負で飽和 

	assign blend_a_sig = (blend_sel_reg)? mem_xit_q_sig : xit_activation_sig;
	assign blend_b_sig = (blend_sel_reg)? (state_clear_reg)? 1'd0 : 17'h10000 - scale_lr_reg : scale_lr_reg;

	always @(posedge clock_sig) begin
		blend_a_reg <= blend_a_sig;
		blend_b_reg <= blend_b_sig;
	end

	lpm_mult #(
		.lpm_type			("LPM_MULT"),
		.lpm_hint			("MAXIMIZE_SPEED=5"),
		.lpm_representation	("SIGNED"),
		.lpm_widtha			(18),
		.lpm_widthb			(18),
		.lpm_widthp			(36)
	)
	u_mul_blend (
		.dataa	(blend_a_reg),
		.datab	({1'b0, blend_b_reg}),
		.result	(blend_mult_sig)
	);

	assign blend_add_sig = blend_mult_reg + blend_add_reg;

	always @(posedge clock_sig) begin
		if (start_sig) begin
			blend_sel_reg <= 1'b1;
		end
		else if (blend_sel_clear_sig) begin
			blend_sel_reg <= 1'b0;
		end

		blend_mult_reg <= blend_mult_sig[16+18-1:0];
		blend_add_latch_reg <= blend_add_latch_sig;

		if (start_sig) begin
			blend_add_reg <= 1'd0;
		end
		else if (blend_add_latch_reg) begin
			blend_add_reg <= blend_add_sig;
		end
	end

	assign xit_new_sig = blend_add_reg[16+18-1:16];


endmodule

`default_nettype wire
