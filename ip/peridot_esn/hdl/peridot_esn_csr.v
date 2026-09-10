// ===================================================================
// TITLE : PERIDOT ESN - Reservoir control register unit
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2026/03/15 -> 2026/03/17
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

// レジスタマップ 
// reg00 : [31:16] version(R), [15] reset(RW), [4] IRQenable(RW), [3] done(RW0), [2] clear(RW1), [1] start(W1), [0] ready(R)
// reg01 : [30:14] scale_wres(RW), [8:0] density(RW)
// reg02 : [30:14] scale_lr(RW), [11:0] n_node(RW)
// reg03 : [30:14] scale_in(RW), [9:0] n_input(RW)
// reg04 : [30:14] scale_fb(RW), [9:0] n_output(RW)
// reg05 : [31:0] seed(RW)
// reg06 : [25:24] memsel(RW), [13:0] mem_addr(RW)
// reg07 : [17:0] data(RW)


// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_esn_csr #(
	parameter MAX_NODE_BITWIDTH = 9,	// リザバーの最大ノード数(9=511nodes, 10=1023nodes, 11=2047nodes, 12=4095nodes)
	parameter MAX_INPUT_BITWIDTH = 8,	// 入力の最大次元数(7=127, 8=255, 9=511, 10=1023)
	parameter MAX_OUTPUT_BITWIDTH = 6,	// 出力の最大次元数(5=32, 6=63, 7=127, 8=255)
	parameter WOUTMEM_BITWIDTH = 12,	// Wout重みテーブルメモリのワード数(10=1024words, 11=2048words, 12=4096words, 13=8192words)
	parameter VERSION_VALUE = 'h7a99,	// ペリフェラルIDとバージョン (16bit幅)
	parameter USE_REDUCED_CSR = "OFF",	// 値読み出しをstatusと入出力バッファのみに制限する

	// SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone 10 GX" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
	parameter DEVICE_FAMILY = "Cyclone III"
) (
	// Interface: Avalon-MM agent
	input wire			csi_csrclock_clk,
	input wire			csi_csrclock_reset,

	input wire  [2:0]	avs_csr_address,
	input wire			avs_csr_read,		// setup:2, wait:0, hold:0
	output wire [31:0]	avs_csr_readdata,
	input wire			avs_csr_write,		// setup:2, wait:0, hold:0
	input wire  [31:0]	avs_csr_writedata,

	// Interface: Avalon Interrupt sender
	output wire			ins_avsirq_irq,

	// Interface: Clock sink
	input wire			csi_coreclock_clk,

	// Interface: Reservoir core signal
	output wire			reset_out,
	output wire			start,
	input wire			busy,
	output wire 		working_page,
	output wire			state_clear,
	output wire [11:0]	n_node,
	output wire [9:0]	n_input,
	output wire [9:0]	n_output,
	output wire [31:0]	seed,
	output wire [8:0]	density,
	output wire [16:0]	scale_in,
	output wire [16:0]	scale_fb,
	output wire [16:0]	scale_wres,
	output wire [16:0]	scale_lr,

	output wire [MAX_INPUT_BITWIDTH:0] input_mem_addr,
	output wire [17:0]	input_mem_data,
	output wire			input_mem_wren,
	input wire  [17:0]	input_mem_q,

	output wire [WOUTMEM_BITWIDTH-1:0] readout_mem_addr,
	output wire [17:0]	readout_mem_data,
	output wire			readout_mem_wren,
	input wire  [17:0]	readout_mem_q,

	output wire [MAX_NODE_BITWIDTH-1:0] xit_mem_addr,
	input wire  [17:0]	xit_mem_q
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */



/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = csi_csrclock_reset;		// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = csi_csrclock_clk;		// モジュール内部駆動クロック 

	reg  [2:0]		reset_n_out_reg;
	wire			reset_out_sig;
	reg  [1:0]		start_out_reg;
	reg  [2:0]		busy_in_reg;
	wire			busy_rise_sig;
	wire			busy_fall_sig;

	reg  [31:0]		readdata_reg;
	wire [31:0]		readdata_sig;
	wire [31:0]		status_sig;

	wire			start_sig;
	wire			done_sig;
	reg				ready_reg;
	reg				start_reg;
	reg				done_reg;
	reg				clear_reg;
	reg				active_page_reg;
	reg				working_page_reg;
	reg				param_error_reg;

	reg				core_reset_n_reg;
	reg				irq_ena_reg;
	reg  [8:0]		density_reg;
	reg  [16:0]		scale_wres_reg;
	reg  [16:0]		scale_lr_reg;
	reg  [16:0]		scale_in_reg;
	reg  [16:0]		scale_fb_reg;
	reg  [MAX_NODE_BITWIDTH-1:0] n_node_reg = 1'd0;		// 初期値不定でsimが進まなくなるのを回避
	reg  [MAX_INPUT_BITWIDTH-1:0] n_input_reg = 1'd0;	//
	reg  [MAX_OUTPUT_BITWIDTH-1:0] n_output_reg = 1'd0;	//
	reg  [31:0]		seed_reg;
	wire [11:0]		n_node_sig;
	wire [9:0]		n_input_sig;
	wire [9:0]		n_output_sig;

	reg  [1:0]		mem_sel_reg;
	reg  [13:0]		mem_addr_reg;
	wire [31:0]		input_mem_q_sig;
	wire [31:0]		readout_mem_q_sig;
	wire [31:0]		xit_mem_q_sig;
	wire [31:0]		mem_q_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	// リセットの同期化と信号のクロックドメインブリッジ

	always @(posedge csi_coreclock_clk or negedge core_reset_n_reg) begin
		if (!core_reset_n_reg) begin
			reset_n_out_reg <= 3'b000;
		end
		else begin
			reset_n_out_reg <= {reset_n_out_reg[1:0], 1'b1};
		end
	end

	assign reset_out_sig = ~reset_n_out_reg[2];

	always @(posedge csi_coreclock_clk or posedge reset_out_sig) begin
		if (reset_out_sig) begin
			start_out_reg <= 2'b00;
		end
		else begin
			start_out_reg <= {start_out_reg[0], start_reg};
		end
	end

	assign reset_out = reset_out_sig;
	assign start = start_out_reg[1];

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			busy_in_reg <= 3'b000;
		end
		else begin
			busy_in_reg <= {busy_in_reg[1:0], busy};
		end
	end

	assign busy_rise_sig = (!busy_in_reg[2] && busy_in_reg[1]);
	assign busy_fall_sig = (busy_in_reg[2] && !busy_in_reg[1]);


	// Avalon-MMインターフェース

	assign ins_avsirq_irq = (irq_ena_reg && done_reg)? 1'b1 : 1'b0;
	assign avs_csr_readdata = readdata_reg;

	assign status_sig = {
			VERSION_VALUE[15:0],// [31:16] version
			~core_reset_n_reg,	// [15] core reset (1:assert / 0:negate)
			10'b0,				// [14:5] reserved
			irq_ena_reg,		// [4] irq enable (1:enable / 0:disable)
			done_reg,			// [3] done (W0)
			clear_reg,			// [2] state clear (W1)
			start_reg,			// [1] start (W1)
			ready_reg			// [0] ready (1:ready / 0:busy)
		};

generate if (USE_REDUCED_CSR == "ON") begin
	assign readdata_sig =
			(avs_csr_address == 3'd7)? input_mem_q_sig : 
			status_sig;
end
else begin
	assign readdata_sig =
			(avs_csr_address == 3'd1)? {1'b0, scale_wres_reg, 5'b0, density_reg} :
			(avs_csr_address == 3'd2)? {1'b0, scale_lr_reg, 2'b0, n_node_sig} :
			(avs_csr_address == 3'd3)? {1'b0, scale_in_reg, 4'b0, n_input_sig} :
			(avs_csr_address == 3'd4)? {1'b0, scale_fb_reg, 4'b0, n_output_sig} :
			(avs_csr_address == 3'd5)? seed_reg :
			(avs_csr_address == 3'd6)? {6'b0, mem_sel_reg, 10'b0, mem_addr_reg} :
			(avs_csr_address == 3'd7)? mem_q_sig : 
			status_sig;
end
endgenerate

	assign start_sig = (!param_error_reg && ready_reg && avs_csr_write && avs_csr_address == 3'd0 && avs_csr_writedata[1]);
	assign done_sig = (!ready_reg && busy_fall_sig);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			core_reset_n_reg <= 1'b0;
			ready_reg <= 1'b0;
			start_reg <= 1'b0;
			done_reg <= 1'b0;
			irq_ena_reg <= 1'b0;
		end
		else begin
			readdata_reg <= readdata_sig;

			if (avs_csr_write && avs_csr_address == 3'd0) begin
				core_reset_n_reg <= ~avs_csr_writedata[15];
			end

			if (!core_reset_n_reg) begin
				ready_reg <= 1'b0;
				start_reg <= 1'b0;
				done_reg <= 1'b0;
				clear_reg <= 1'b0;
				active_page_reg <= 1'b0;
				irq_ena_reg <= 1'b0;
			end
			else begin
				if (start_sig) begin
					ready_reg <= 1'b0;
				end
				else begin
					ready_reg <= (!start_reg && !busy_in_reg[1]);
				end

				if (start_sig) begin
					start_reg <= 1'b1;
				end
				else if (busy_rise_sig) begin
					start_reg <= 1'b0;
				end

				if (done_sig) begin
					done_reg <= 1'b1;
				end
				else if (avs_csr_write && avs_csr_address == 3'd0 && !avs_csr_writedata[3]) begin
					done_reg <= 1'b0;
				end

				if (start_sig) begin
					clear_reg <= avs_csr_writedata[2];
				end
				else if (done_sig) begin
					clear_reg <= 1'b0;
				end

				if (start_sig) begin
					working_page_reg <= active_page_reg;
					active_page_reg <= ~active_page_reg;
				end

				if (avs_csr_write && avs_csr_address == 3'd0) begin
					irq_ena_reg <= avs_csr_writedata[4];
				end
			end

			if (ready_reg && avs_csr_write) begin
				case(avs_csr_address)
				3'd1: begin
					scale_wres_reg <= avs_csr_writedata[30:14];
					density_reg <= avs_csr_writedata[8:0];
				end
				3'd2: begin
					scale_lr_reg <= avs_csr_writedata[30:14];
					n_node_reg <= avs_csr_writedata[MAX_NODE_BITWIDTH-1:0];
				end
				3'd3: begin
					scale_in_reg <= avs_csr_writedata[30:14];
					n_input_reg <= avs_csr_writedata[MAX_INPUT_BITWIDTH-1:0];
				end
				3'd4: begin
					scale_fb_reg <= avs_csr_writedata[30:14];
					n_output_reg <= avs_csr_writedata[MAX_OUTPUT_BITWIDTH-1:0];
				end
				3'd5: begin
					seed_reg <= avs_csr_writedata;
				end
				endcase
			end

			param_error_reg <= (n_node_reg == 1'd0 || n_input_reg == 1'd0 || n_output_reg == 1'd0);

			if (avs_csr_write && avs_csr_address == 3'd6) begin
				mem_sel_reg <= avs_csr_writedata[25:24];
				mem_addr_reg <= avs_csr_writedata[13:0];
			end
			else if ((avs_csr_write || avs_csr_read) && avs_csr_address == 3'd7) begin
				mem_addr_reg <= mem_addr_reg + 1'd1;
			end
		end
	end


	// 制御信号の入出力

	assign n_node_sig = n_node_reg;
	assign n_input_sig = n_input_reg;
	assign n_output_sig = n_output_reg;

	assign working_page = working_page_reg;
	assign state_clear = clear_reg;
	assign n_node = n_node_sig;
	assign n_input = n_input_sig;
	assign n_output = n_output_sig;
	assign seed = seed_reg;
	assign density = density_reg;
	assign scale_in = scale_in_reg;
	assign scale_fb = scale_fb_reg;
	assign scale_wres = scale_wres_reg;
	assign scale_lr = scale_lr_reg;

	assign input_mem_addr = {active_page_reg, mem_addr_reg[MAX_INPUT_BITWIDTH-1:0]};
	assign input_mem_data = avs_csr_writedata[17:0];
	assign input_mem_wren = (avs_csr_write && avs_csr_address == 3'd7 && mem_sel_reg == 2'd0 && mem_addr_reg[MAX_INPUT_BITWIDTH-1:0] < n_input_reg);

	assign readout_mem_addr = mem_addr_reg[WOUTMEM_BITWIDTH-1:0];
	assign readout_mem_data = avs_csr_writedata[17:0];
	assign readout_mem_wren = (avs_csr_write && avs_csr_address == 3'd7 && mem_sel_reg == 2'd1);

	assign xit_mem_addr = mem_addr_reg[MAX_NODE_BITWIDTH-1:0];

	assign input_mem_q_sig = $signed(input_mem_q);
	assign readout_mem_q_sig = readout_mem_q;
	assign xit_mem_q_sig = $signed(xit_mem_q);
	assign mem_q_sig =	(mem_sel_reg == 2'd0)? input_mem_q_sig :
						(mem_sel_reg == 2'd1)? readout_mem_q_sig :
						xit_mem_q_sig;


endmodule

`default_nettype wire
