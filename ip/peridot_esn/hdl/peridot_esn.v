// ===================================================================
// TITLE : PERIDOT ESN - Reservoir core
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

module peridot_esn #(
	parameter MAX_NODE_BITWIDTH = 9,	// リザバーの最大ノード数(9=511nodes, 10=1023nodes, 11=2047nodes, 12=4095nodes)
	parameter MAX_INPUT_BITWIDTH = 8,	// 入力の最大次元数(7=127, 8=255, 9=511, 10=1023)
	parameter MAX_OUTPUT_BITWIDTH = 6,	// 出力の最大次元数(5=32, 6=63, 7=127, 8=255)
	parameter WOUTMEM_BITWIDTH = 12,	// Wout重みテーブルメモリのワード数(10=1024words, 11=2048words, 12=4096words, 13=8192words)
	parameter VERSION_VALUE = 'h7a99,	// ペリフェラルIDとバージョン (16bit幅)
	parameter USE_REDUCED_CSR = "OFF",	// 値読み出しをstatusと入出力バッファのみに制限する

	// SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone 10 GX" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
	parameter DEVICE_FAMILY = "Cyclone III"
) (
	// Interface: Clock sink
	input wire			csi_coreclock_clk,

	// Interface: Avalon-MM agent
	input wire			csi_csrclock_clk,
	input wire			csi_csrclock_reset,

	input wire  [2:0]	avs_csr_address,
	input wire			avs_csr_read,		// setup:2, read:1, hold:0
	output wire [31:0]	avs_csr_readdata,
	input wire			avs_csr_write,		// setup:2, write:1, hold:0
	input wire  [31:0]	avs_csr_writedata,

	// Interface: Avalon Interrupt sender
	output wire			ins_avsirq_irq
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */



/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = csi_coreclock_clk;		// モジュール内部駆動クロック 

	wire			reset_sig;
	wire			start_sig;
	wire			busy_sig;
	wire			working_page_sig;
	wire			state_clear_sig;
	wire [11:0]		n_node_sig;
	wire [9:0]		n_input_sig;
	wire [9:0]		n_output_sig;
	wire [31:0]		seed_sig;
	wire [8:0]		density_sig;
	wire [16:0]		scale_in_sig;
	wire [16:0]		scale_fb_sig;
	wire [16:0]		scale_wres_sig;
	wire [16:0]		scale_lr_sig;

	wire			input_ready_sig;
	wire			input_valid_sig;
	wire [47:0]		input_data_sig;
	wire			input_sop_sig;
	wire			input_eop_sig;
	wire [MAX_INPUT_BITWIDTH:0] input_mem_addr_sig;
	wire [17:0]		input_mem_data_sig;
	wire			input_mem_wren_sig;
	wire [17:0]		input_mem_q_sig;

	wire			reservoir_ready_sig;
	wire			reservoir_valid_sig;
	wire [17:0]		reservoir_data_sig;
	wire			reservoir_sop_sig;
	wire			reservoir_eop_sig;
	wire [MAX_NODE_BITWIDTH-1:0] xit_mem_addr_sig;
	wire [17:0]		xit_mem_q_sig;

	wire			readout_valid_sig;
	wire [17:0]		readout_data_sig;
	wire			readout_sop_sig;
	wire			readout_eop_sig;
	wire [WOUTMEM_BITWIDTH-1:0] readout_mem_addr_sig;
	wire [17:0]		readout_mem_data_sig;
	wire			readout_mem_wren_sig;
	wire [17:0]		readout_mem_q_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	// 制御レジスタモジュール

	peridot_esn_csr #(
		.MAX_NODE_BITWIDTH		(MAX_NODE_BITWIDTH),
		.MAX_INPUT_BITWIDTH		(MAX_INPUT_BITWIDTH),
		.MAX_OUTPUT_BITWIDTH	(MAX_OUTPUT_BITWIDTH),
		.WOUTMEM_BITWIDTH		(WOUTMEM_BITWIDTH),
		.VERSION_VALUE			(VERSION_VALUE),
		.USE_REDUCED_CSR		(USE_REDUCED_CSR),
		.DEVICE_FAMILY			(DEVICE_FAMILY)
	)
	u_csr (
		.csi_csrclock_clk	(csi_csrclock_clk),
		.csi_csrclock_reset	(csi_csrclock_reset),

		.avs_csr_address	(avs_csr_address),
		.avs_csr_read		(avs_csr_read),
		.avs_csr_readdata	(avs_csr_readdata),
		.avs_csr_write		(avs_csr_write),
		.avs_csr_writedata	(avs_csr_writedata),
		.ins_avsirq_irq		(ins_avsirq_irq),

		.csi_coreclock_clk	(clock_sig),
		.reset_out			(reset_sig),

		.start				(start_sig),
		.busy				(busy_sig),
		.working_page		(working_page_sig),
		.state_clear		(state_clear_sig),
		.n_node				(n_node_sig),
		.n_input			(n_input_sig),
		.n_output			(n_output_sig),
		.seed				(seed_sig),
		.density			(density_sig),
		.scale_in			(scale_in_sig),
		.scale_fb			(scale_fb_sig),
		.scale_wres			(scale_wres_sig),
		.scale_lr			(scale_lr_sig),

		.input_mem_addr		(input_mem_addr_sig),
		.input_mem_data		(input_mem_data_sig),
		.input_mem_wren		(input_mem_wren_sig),
		.input_mem_q		(input_mem_q_sig),

		.readout_mem_addr	(readout_mem_addr_sig),
		.readout_mem_data	(readout_mem_data_sig),
		.readout_mem_wren	(readout_mem_wren_sig),
		.readout_mem_q		(readout_mem_q_sig),

		.xit_mem_addr		(xit_mem_addr_sig),
		.xit_mem_q			(xit_mem_q_sig)
	);


	// 入力・フィードバックモジュール

	peridot_esn_input #(
		.RESERVOIR_NODE_BITWIDTH	(MAX_NODE_BITWIDTH),
		.INPUTBUFFER_BITWIDTH		(MAX_INPUT_BITWIDTH),
		.DEVICE_FAMILY				(DEVICE_FAMILY)
	)
	u_input (
		.reset				(reset_sig),
		.clk				(clock_sig),

		.start				(start_sig),
		.busy				(busy_sig),
		.working_page		(working_page_sig),
		.state_clear		(state_clear_sig),
		.n_node				(n_node_sig),
		.n_input			(n_input_sig),
		.n_output			(n_output_sig),
		.seed				(seed_sig),
		.scale_in			(scale_in_sig),
		.scale_fb			(scale_fb_sig),

		.sto_ready			(input_ready_sig),
		.sto_valid			(input_valid_sig),
		.sto_data			(input_data_sig),
		.sto_startofpacket	(input_sop_sig),
		.sto_endofpacket	(input_eop_sig),

		.sti_ready			(),
		.sti_valid			(readout_valid_sig),
		.sti_data			(readout_data_sig),
		.sti_startofpacket	(readout_sop_sig),
		.sti_endofpacket	(readout_eop_sig),

		.mem_clk			(csi_csrclock_clk),
		.mem_addr			(input_mem_addr_sig),
		.mem_data			(input_mem_data_sig),
		.mem_wren			(input_mem_wren_sig),
		.mem_q				(input_mem_q_sig)
	);


	// リザバー状態更新モジュール

	peridot_esn_reservoir #(
		.RESERVOIR_NODE_BITWIDTH	(MAX_NODE_BITWIDTH),
		.DEVICE_FAMILY				(DEVICE_FAMILY)
	)
	u_reservoir (
		.reset				(reset_sig),
		.clk				(clock_sig),

		.state_clear		(state_clear_sig),
		.n_node				(n_node_sig),
		.seed				(seed_sig),
		.density			(density_sig),
		.scale_wres			(scale_wres_sig),
		.scale_lr			(scale_lr_sig),

		.sti_ready			(input_ready_sig),
		.sti_valid			(input_valid_sig),
		.sti_data			(input_data_sig),
		.sti_startofpacket	(input_sop_sig),
		.sti_endofpacket	(input_eop_sig),

		.sto_ready			(reservoir_ready_sig),
		.sto_valid			(reservoir_valid_sig),
		.sto_data			(reservoir_data_sig),
		.sto_startofpacket	(reservoir_sop_sig),
		.sto_endofpacket	(reservoir_eop_sig),

		.mem_clk			(csi_csrclock_clk),
		.mem_addr			(xit_mem_addr_sig),
		.mem_data			(1'd0),
		.mem_wren			(1'b0),
		.mem_q				(xit_mem_q_sig)
	);


	// リードアウトモジュール

	peridot_esn_readout #(
		.RESERVOIR_NODE_BITWIDTH	(MAX_NODE_BITWIDTH),
		.ACCUMFIFO_DEPTH_BITWIDTH	(MAX_OUTPUT_BITWIDTH),
		.WOUTMEM_BITWIDTH			(WOUTMEM_BITWIDTH),
		.DEVICE_FAMILY				(DEVICE_FAMILY)
	)
	u_readout (
		.reset				(reset_sig),
		.clk				(clock_sig),

		.n_output			(n_output_sig),

		.sti_ready			(reservoir_ready_sig),
		.sti_valid			(reservoir_valid_sig),
		.sti_data			(reservoir_data_sig),
		.sti_startofpacket	(reservoir_sop_sig),
		.sti_endofpacket	(reservoir_eop_sig),

		.sto_valid			(readout_valid_sig),
		.sto_data			(readout_data_sig),
		.sto_startofpacket	(readout_sop_sig),
		.sto_endofpacket	(readout_eop_sig),

		.mem_clk			(csi_csrclock_clk),
		.mem_addr			(readout_mem_addr_sig),
		.mem_data			(readout_mem_data_sig),
		.mem_wren			(readout_mem_wren_sig),
		.mem_q				(readout_mem_q_sig)
	);


endmodule

`default_nettype wire
