// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / Avalon-MM Bridge
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/09/19 -> 2022/09/19
//            : 2022/09/20 (FIXED)
//
// ===================================================================
//
// The MIT License (MIT)
// Copyright (c) 2022 J-7SYSTEM WORKS LIMITED.
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

module peridot_ethio_avmm #(
	parameter SUPPORT_MEMORYHOST	= 1,	// 1=メモリバスマスター機能を有効にする 
	parameter AVALONMM_FASTMODE		= 0,	// 1=Avalon-MM Hostのファーストアクセスモード有効 

	parameter SUPPORT_STREAMFIFO	= 1,	// 1=ストリームFIFO機能を有効にする 
	parameter SRCFIFO_NUMBER		= 4,	// 有効にするSRCFIFOの数 (0～4)
	parameter SINKFIFO_NUMBER		= 4,	// 有効にするSINKFIFOの数 (0～4)
	parameter SRCFIFO_0_SIZE		= 2048,	// SRCFIFO 0 バイト数(1024, 2048, 4096, 8192, 16384, 32768, 65536 のどれか)
	parameter SRCFIFO_1_SIZE		= 2048,	// SRCFIFO 1 バイト数( 〃 )
	parameter SRCFIFO_2_SIZE		= 2048,	// SRCFIFO 2 バイト数( 〃 )
	parameter SRCFIFO_3_SIZE		= 2048,	// SRCFIFO 3 バイト数( 〃 )
	parameter SINKFIFO_0_SIZE		= 2048,	// SINKFIFO 0 バイト数(1024, 2048, 4096, 8192, 16384, 32768, 65536 のどれか)
	parameter SINKFIFO_1_SIZE		= 2048,	// SINKFIFO 1 バイト数( 〃 )
	parameter SINKFIFO_2_SIZE		= 2048,	// SINKFIFO 2 バイト数( 〃 )
	parameter SINKFIFO_3_SIZE		= 2048	// SINKFIFO 3 バイト数( 〃 )
) (
	input wire			reset,
	input wire			clk,

	// UDPペイロードインターフェース 
	output wire			in_ready,
	input wire			in_valid,
	input wire  [7:0]	in_data,
	input wire			in_sop,
	input wire			in_eop,

	input wire			out_ready,
	output wire			out_valid,
	output wire [7:0]	out_data,
	output wire			out_sop,
	output wire			out_eop,
	output wire			out_error,	// eop時にアサートすると応答パケットを破棄する 

	// Avalon-MM Host インターフェース 
	input wire			avm_waitrequest,
	output wire [31:0]	avm_address,
	output wire			avm_read,
	input wire  [31:0]	avm_readdata,
	input wire			avm_readdatavalid,
	output wire			avm_write,
	output wire [31:0]	avm_writedata,
	output wire [3:0]	avm_byteenable,

	// Avalon-ST Source インターフェース 
	input wire			aso_0_ready,
	output wire			aso_0_valid,
	output wire [7:0]	aso_0_data,

	input wire			aso_1_ready,
	output wire			aso_1_valid,
	output wire [7:0]	aso_1_data,

	input wire			aso_2_ready,
	output wire			aso_2_valid,
	output wire [7:0]	aso_2_data,

	input wire			aso_3_ready,
	output wire			aso_3_valid,
	output wire [7:0]	aso_3_data,

	// Avalon-ST Sink インターフェース 
	output wire			asi_0_ready,
	input wire			asi_0_valid,
	input wire  [7:0]	asi_0_data,

	output wire			asi_1_ready,
	input wire			asi_1_valid,
	input wire  [7:0]	asi_1_data,

	output wire			asi_2_ready,
	input wire			asi_2_valid,
	input wire  [7:0]	asi_2_data,

	output wire			asi_3_ready,
	input wire			asi_3_valid,
	input wire  [7:0]	asi_3_data
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam ENABLE_AVALONST_SRC = (SRCFIFO_NUMBER > 0)? 1 : 0;
	localparam ENABLE_AVALONST_SINK = (SINKFIFO_NUMBER > 0)? 1 : 0;

	localparam FIFO_MAX_NUM = 4;

	localparam SRCFIFO_INST_NUM =
					(!SUPPORT_STREAMFIFO)? 0 :
					(SRCFIFO_NUMBER > FIFO_MAX_NUM)? FIFO_MAX_NUM :
					SRCFIFO_NUMBER;
	localparam SRCFIFO_SIZE_VECTOR =
					{SRCFIFO_3_SIZE[31:0], SRCFIFO_2_SIZE[31:0], SRCFIFO_1_SIZE[31:0], SRCFIFO_0_SIZE[31:0]};

	localparam SINKFIFO_INST_NUM =
					(!SUPPORT_STREAMFIFO)? 0 :
					(SINKFIFO_NUMBER > FIFO_MAX_NUM)? FIFO_MAX_NUM :
					SINKFIFO_NUMBER;
	localparam SINKFIFO_SIZE_VECTOR =
					{SINKFIFO_3_SIZE[31:0], SINKFIFO_2_SIZE[31:0], SINKFIFO_1_SIZE[31:0], SINKFIFO_0_SIZE[31:0]};


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 
	wire			clock_sig = clk;		// モジュール内部駆動クロック 
	wire			init_sig;

	wire			mmreq_ready_sig, mmreq_valid_sig, mmreq_sop_sig, mmreq_eop_sig;
	wire [7:0]		mmreq_data_sig;
	wire			mmrsp_ready_sig, mmrsp_valid_sig, mmrsp_sop_sig, mmrsp_eop_sig;
	wire [7:0]		mmrsp_data_sig;

	wire [3:0]		srcfifo_ch_sig, sinkfifo_ch_sig;
	wire			srcfifo_wen_sig, sinkfifo_ack_sig;
	wire [7:0]		srcfifo_data_sig, sinkfifo_q_sig;
	wire [10:0]		srcfifo_free_sig, sinkfifo_remain_sig;

	wire			scfifo_wen_sig[0:FIFO_MAX_NUM-1];
	wire [10:0]		scfifo_free_sig[0:FIFO_MAX_NUM-1];
	wire			aso_ready_sig[0:FIFO_MAX_NUM-1];
	wire			aso_valid_n_sig[0:FIFO_MAX_NUM-1];
	wire [7:0]		aso_data_sig[0:FIFO_MAX_NUM-1];

	wire			scfifo_rdack_sig[0:FIFO_MAX_NUM-1];
	wire [7:0]		scfifo_q_sig[0:FIFO_MAX_NUM-1];
	wire [10:0]		scfifo_remain_sig[0:FIFO_MAX_NUM-1];
	wire			asi_ready_n_sig[0:FIFO_MAX_NUM-1];
	wire			asi_valid_sig[0:FIFO_MAX_NUM-1];
	wire [7:0]		asi_data_sig[0:FIFO_MAX_NUM-1];

	genvar i;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	// FIFO用の同期リセット信号 

	peridot_ethio_cdb_areset
	u_init (
		.areset		(reset_sig),
		.clk		(clock_sig),
		.reset_out	(init_sig)
	);


	// AVMMアービター 

	peridot_ethio_avmm_arbiter #(
		.SUPPORT_AVALONMM_CMD	(SUPPORT_MEMORYHOST),
		.SUPPORT_AVALONST_CMD	(SUPPORT_STREAMFIFO),
		.ENABLE_AVALONST_SRC	(ENABLE_AVALONST_SRC),
		.ENABLE_AVALONST_SINK	(ENABLE_AVALONST_SINK)
	)
	u_arbiter (
		.reset			(reset_sig),
		.clk			(clock_sig),

		.in_ready		(in_ready),
		.in_valid		(in_valid),
		.in_data		(in_data),
		.in_sop			(in_sop),
		.in_eop			(in_eop),
		.out_ready		(out_ready),
		.out_valid		(out_valid),
		.out_data		(out_data),
		.out_sop		(out_sop),
		.out_eop		(out_eop),
		.out_error		(out_error),

		.mmreq_ready	(mmreq_ready_sig),
		.mmreq_valid	(mmreq_valid_sig),
		.mmreq_data		(mmreq_data_sig),
		.mmreq_sop		(mmreq_sop_sig),
		.mmreq_eop		(mmreq_eop_sig),
		.mmrsp_ready	(mmrsp_ready_sig),
		.mmrsp_valid	(mmrsp_valid_sig),
		.mmrsp_data		(mmrsp_data_sig),
		.mmrsp_sop		(mmrsp_sop_sig),
		.mmrsp_eop		(mmrsp_eop_sig),

		.srcfifo_ch		(srcfifo_ch_sig),
		.srcfifo_wen	(srcfifo_wen_sig),
		.srcfifo_data	(srcfifo_data_sig),
		.srcfifo_free	(srcfifo_free_sig),

		.sinkfifo_ch	(sinkfifo_ch_sig),
		.sinkfifo_ack	(sinkfifo_ack_sig),
		.sinkfifo_q		(sinkfifo_q_sig),
		.sinkfifo_remain(sinkfifo_remain_sig)
	);


	// Packet to Avalon-MM Host

	generate
	if (SUPPORT_MEMORYHOST) begin
		altera_avalon_packets_to_master #(
			.FAST_VER	(AVALONMM_FASTMODE)
		)
		u_avmm (
			.reset_n			(~reset_sig),
			.clk				(clock_sig),

			.in_ready			(mmreq_ready_sig),
			.in_valid			(mmreq_valid_sig),
			.in_data			(mmreq_data_sig),
			.in_startofpacket	(mmreq_sop_sig),
			.in_endofpacket		(mmreq_eop_sig),
			.out_ready			(mmrsp_ready_sig),
			.out_valid			(mmrsp_valid_sig),
			.out_data			(mmrsp_data_sig),
			.out_startofpacket	(mmrsp_sop_sig),
			.out_endofpacket	(mmrsp_eop_sig),

			.waitrequest		(avm_waitrequest),
			.address			(avm_address),
			.read				(avm_read),
			.readdata			(avm_readdata),
			.readdatavalid		(avm_readdatavalid),
			.write				(avm_write),
			.writedata			(avm_writedata),
			.byteenable			(avm_byteenable)
		);
	end
	else begin
		assign {mmreq_ready_sig, mmrsp_valid_sig, mmrsp_data_sig, mmrsp_sop_sig, mmrsp_eop_sig} = 1'd0;
		assign avm_read = 1'b0;
		assign avm_write = 1'b0;
		assign avm_address = {32{1'bx}};
		assign avm_writedata = {32{1'bx}};
		assign avm_byteenable = 4'b0000;
	end
	endgenerate


	// SRCFIFO

	assign srcfifo_free_sig = 
				(srcfifo_ch_sig == 4'd0)? scfifo_free_sig[0] :
				(srcfifo_ch_sig == 4'd1)? scfifo_free_sig[1] :
				(srcfifo_ch_sig == 4'd2)? scfifo_free_sig[2] :
				(srcfifo_ch_sig == 4'd3)? scfifo_free_sig[3] :
				11'd0;

	assign aso_ready_sig[0] = aso_0_ready;
	assign aso_ready_sig[1] = aso_1_ready;
	assign aso_ready_sig[2] = aso_2_ready;
	assign aso_ready_sig[3] = aso_3_ready;

	assign aso_0_valid = ~aso_valid_n_sig[0];
	assign aso_1_valid = ~aso_valid_n_sig[1];
	assign aso_2_valid = ~aso_valid_n_sig[2];
	assign aso_3_valid = ~aso_valid_n_sig[3];

	assign aso_0_data = aso_data_sig[0];
	assign aso_1_data = aso_data_sig[1];
	assign aso_2_data = aso_data_sig[2];
	assign aso_3_data = aso_data_sig[3];

	generate
	for(i=0 ; i<FIFO_MAX_NUM ; i=i+1) begin : srcfifo
		if (i < SRCFIFO_INST_NUM) begin
			assign scfifo_wen_sig[i] = (srcfifo_ch_sig == i && srcfifo_wen_sig);

			peridot_ethio_scfifo #(
				.FIFO_DEPTH			(SRCFIFO_SIZE_VECTOR[(i+1)*32-1 -: 32]),
				.FIFO_DATA_BITWIDTH	(8)
			)
			u_srcfifo (
				.clk	(clock_sig),
				.init	(init_sig),

				.wen	(scfifo_wen_sig[i]),
				.data	(srcfifo_data_sig),
				.free	(scfifo_free_sig[i]),

				.rdack	(aso_ready_sig[i] & ~aso_valid_n_sig[i]),
				.q		(aso_data_sig[i]),
				.empty	(aso_valid_n_sig[i])
			);
		end
		else begin
			assign scfifo_free_sig[i] = 11'd0;
			assign aso_valid_n_sig[i] = 1'b0;
			assign aso_data_sig[i] = {8{1'bx}};
		end
	end
	endgenerate


	// SINKFIFO

	assign sinkfifo_q_sig = 
				(sinkfifo_ch_sig == 4'd0)? scfifo_q_sig[0] :
				(sinkfifo_ch_sig == 4'd1)? scfifo_q_sig[1] :
				(sinkfifo_ch_sig == 4'd2)? scfifo_q_sig[2] :
				(sinkfifo_ch_sig == 4'd3)? scfifo_q_sig[3] :
				{8{1'bx}};

	assign sinkfifo_remain_sig = 
				(sinkfifo_ch_sig == 4'd0)? scfifo_remain_sig[0] :
				(sinkfifo_ch_sig == 4'd1)? scfifo_remain_sig[1] :
				(sinkfifo_ch_sig == 4'd2)? scfifo_remain_sig[2] :
				(sinkfifo_ch_sig == 4'd3)? scfifo_remain_sig[3] :
				11'd0;

	assign asi_0_ready = ~asi_ready_n_sig[0];
	assign asi_1_ready = ~asi_ready_n_sig[1];
	assign asi_2_ready = ~asi_ready_n_sig[2];
	assign asi_3_ready = ~asi_ready_n_sig[3];

	assign asi_valid_sig[0] = asi_0_valid;
	assign asi_valid_sig[1] = asi_1_valid;
	assign asi_valid_sig[2] = asi_2_valid;
	assign asi_valid_sig[3] = asi_3_valid;

	assign asi_data_sig[0] = asi_0_data;
	assign asi_data_sig[1] = asi_1_data;
	assign asi_data_sig[2] = asi_2_data;
	assign asi_data_sig[3] = asi_3_data;

	generate
	for(i=0 ; i<FIFO_MAX_NUM ; i=i+1) begin : sinkfifo
		if (i < SINKFIFO_INST_NUM) begin
			assign scfifo_rdack_sig[i] = (sinkfifo_ch_sig == i && sinkfifo_ack_sig);

			peridot_ethio_scfifo #(
				.FIFO_DEPTH			(SINKFIFO_SIZE_VECTOR[(i+1)*32-1 -: 32]),
				.FIFO_DATA_BITWIDTH	(8)
			)
			u_sinkfifo (
				.clk	(clock_sig),
				.init	(init_sig),

				.rdack	(scfifo_rdack_sig[i]),
				.q		(scfifo_q_sig[i]),
				.remain	(scfifo_remain_sig[i]),

				.wen	(~asi_ready_n_sig[i] & asi_valid_sig[i]),
				.data	(asi_data_sig[i]),
				.full	(asi_ready_n_sig[i])
			);
		end
		else begin
			assign scfifo_q_sig[i] = {8{1'bx}};
			assign scfifo_remain_sig[i] = 11'd0;
			assign asi_ready_n_sig[i] = 1'b1;
		end
	end
	endgenerate



endmodule

`default_nettype wire
