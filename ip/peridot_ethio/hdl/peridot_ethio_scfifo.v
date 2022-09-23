// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / Single Clock FIFO
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/09/15 -> 2022/09/16
//            : 2022/09/19 (FIXED)
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

module peridot_ethio_scfifo #(
	parameter FIFO_DEPTH			= 2048,
	parameter FIFO_DATA_BITWIDTH	= 8
) (
	input wire			clk,
	input wire			init,		// Sync reset
	output wire [10:0]	free,
	output wire [10:0]	remain,

	input wire			wen,
	input wire  [FIFO_DATA_BITWIDTH-1:0] data,
	output wire			full,

	input wire			rdack,
	output wire [FIFO_DATA_BITWIDTH-1:0] q,
	output wire			empty
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

// Vivado用インスタンスをするオプション 
//`define GENERATE_VIVADO_XPM

// GowinEDA用インスタンスをするオプション 
//`define GENERATE_GOWINEDA


/* ===== モジュール構造記述 ============== */

	// 格納データ、空き数出力 (2047で飽和)

	localparam FIFO_DEPTH_BITWIDTH =
					(FIFO_DEPTH > 32768)? 16 :
					(FIFO_DEPTH > 16384)? 15 :
					(FIFO_DEPTH >  8192)? 14 :
					(FIFO_DEPTH >  4096)? 13 :
					(FIFO_DEPTH >  2048)? 12 :
					(FIFO_DEPTH >  1024)? 11 :
					10;

	localparam DATANUM_BITWIDTH = (FIFO_DEPTH_BITWIDTH > 11)? FIFO_DEPTH_BITWIDTH : 11;

	wire [DATANUM_BITWIDTH:0] datanum_sig, freenum_sig;
	reg  [10:0]		free_reg, remain_reg;

	assign freenum_sig = (1'b1 << FIFO_DEPTH_BITWIDTH) - datanum_sig;

	always @(posedge clk) begin
		if (freenum_sig[DATANUM_BITWIDTH:11]) free_reg <= 11'd2047;
		else free_reg <= freenum_sig[10:0];

		if (datanum_sig[DATANUM_BITWIDTH:11]) remain_reg <= 11'd2047;
		else remain_reg <= datanum_sig[10:0];
	end

	assign free = free_reg;
	assign remain = remain_reg;


	// QuartusPrime用インスタンス (Cyclone III/IV/V/10LP, MAX10)
	// https://www.intel.com/content/www/us/en/docs/programmable/683522/18-0/fifo-user-guide.html

`ifdef GENERATE_VIVADO_XPM
`elsif GENERATE_GOWINEDA
`else
	wire			full_sig;
	wire [FIFO_DEPTH_BITWIDTH-1:0] usedw_sig;

	scfifo #(
		.lpm_type			("scfifo"),
		.lpm_showahead		("ON"),
		.lpm_numwords		(2**FIFO_DEPTH_BITWIDTH),
		.lpm_width			(FIFO_DATA_BITWIDTH),
		.lpm_widthu			(FIFO_DEPTH_BITWIDTH)
	)
	u_scfifo (
		.aclr	(1'b0),
		.clock	(clk),
		.sclr	(init),
		.wrreq	(wen),
		.data	(data),
		.full	(full_sig),
		.rdreq	(rdack),
		.q		(q),
		.empty	(empty),
		.usedw	(usedw_sig)
	);

	assign full = full_sig;
	assign datanum_sig = {full_sig, usedw_sig};
`endif


	// Vivado用インスタンス (Vivado XPM support)
	// https://docs.xilinx.com/r/en-US/ug974-vivado-ultrascale-libraries/XPM_FIFO_SYNC

`ifdef GENERATE_VIVADO_XPM
	wire [FIFO_DEPTH_BITWIDTH:0] datacount_sig;

	xpm_fifo_sync #(
		.READ_MODE				("fwft"),	// First-Word-Fall-Through mode
		.FIFO_WRITE_DEPTH		(2**FIFO_DEPTH_BITWIDTH),
		.WRITE_DATA_WIDTH		(FIFO_DATA_BITWIDTH),
		.READ_DATA_WIDTH		(FIFO_DATA_BITWIDTH),
		.RD_DATA_COUNT_WIDTH	(1)
	)
	u_scfifo (
		.wr_clk			(clk),
		.rst			(init),
		.wr_en			(wen),
		.din			(data),
		.full			(full),
		.rd_en			(rdack),
		.dout			(q),
		.empty			(empty),
		.rd_data_count	(datacount_sig),

		.injectdbiterr	(1'b0),
		.injectsbiterr	(1'b0),
		.sleep			(1'b0)
	);

	assign datanum_sig = datacount_sig;
`endif


	// GowinEDA用インスタンス (GW1N)
	// FIFO_DATA_BITWIDTH = 8, FIFO_DEPTH_BITWIDTH = 11で固定 
	// https://www.gowinsemi.com/upload/database_doc/1339/document_ja/6100b4d76c49f.pdf

`ifdef GENERATE_GOWINEDA
	wire [11:0]		wnum_sig;

	// IP Core Generator
	//
	// * FIFO SC HS
	//
	//   [ ] Output Register Selected
	//   Write Depth : 2048, Write Data Width : 8
	//   FIFO Implementation : BSRAM
	//   Read Mode : First-Word Fall-Through
	//   Data Number : [X] Write Data Num
	//   Output Flags : [ ] Almost Full Flag
	//                  [ ] Almost Empty Flag
	//   [ ] ECC Selected
	//
	gowin_fifo_sc_2048x8
	u_scfifo (
		.Clk	(clk),
		.Reset	(init),
		.WrEn	(wen),
		.Data	(data),
		.Full	(full),
		.RdEn	(rdack),
		.Q		(q),
		.Empty	(empty),
		.Wnum	(wnum_sig)
	);

	assign datanum_sig = wnum_sig;
`endif


endmodule

`default_nettype wire
