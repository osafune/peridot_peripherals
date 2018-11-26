// ===================================================================
// TITLE : PERIDOT-NGS / Byte to Avalon-MM Bridge
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2014/03/10 -> 2014/03/27
//   UPDATE : 2017/03/01
//
// ===================================================================
//
// The MIT License (MIT)
// Copyright (c) 2014,2018 J-7SYSTEM WORKS LIMITED.
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

module peridot_mm_master (
	// Interface: clk
	input wire			clk,
	input wire			reset,

	// Interface: ST in
	output wire			in_ready,
	input wire  [7:0]	in_data,
	input wire			in_valid,

	// Interface: ST out
	input wire			out_ready,
	output wire [7:0]	out_data,
	output wire			out_valid,

	// Interface: MM master
	output wire [31:0]	avm_address,
	input wire  [31:0]	avm_readdata,
	output wire			avm_read,
	output wire			avm_write,
	output wire [ 3:0]	avm_byteenable,
	output wire [31:0]	avm_writedata,
	input wire			avm_waitrequest,
	input wire			avm_readdatavalid
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */



/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = reset;				// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;				// モジュール内部駆動クロック 

	wire			avm_in_ready_sig;
	wire			avm_in_valid_sig;
	wire [7:0]		avm_in_data_sig;
	wire			avm_in_startofpacket_sig;
	wire			avm_in_endofpacket_sig;
	wire			avm_out_ready_sig;
	wire			avm_out_valid_sig;
	wire [7:0]		avm_out_data_sig;
	wire			avm_out_startofpacket_sig;
	wire			avm_out_endofpacket_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	altera_avalon_st_bytes_to_packets #(
		.CHANNEL_WIDTH (8),
		.ENCODING      (0)
	)
	u0_by2pk (
		.clk				(clock_sig),
		.reset_n			(~reset_sig),

		.out_ready			(avm_in_ready_sig),
		.out_valid			(avm_in_valid_sig),
		.out_data			(avm_in_data_sig),
		.out_channel		(),
		.out_startofpacket	(avm_in_startofpacket_sig),
		.out_endofpacket	(avm_in_endofpacket_sig),

		.in_ready			(in_ready),
		.in_valid			(in_valid),
		.in_data			(in_data)
	);


	altera_avalon_st_packets_to_bytes #(
		.CHANNEL_WIDTH (8),
		.ENCODING      (0)
	)
	u1_pk2by (
		.clk				(clock_sig),
		.reset_n			(~reset_sig),

		.in_ready			(avm_out_ready_sig),
		.in_valid			(avm_out_valid_sig),
		.in_data			(avm_out_data_sig),
		.in_channel			(1'd0),
		.in_startofpacket	(avm_out_startofpacket_sig),
		.in_endofpacket		(avm_out_endofpacket_sig),

		.out_ready			(out_ready),
		.out_valid			(out_valid),
		.out_data			(out_data)
	);


	altera_avalon_packets_to_master #(
		.FAST_VER    (0),
		.FIFO_DEPTHS (2),
		.FIFO_WIDTHU (1)
	)
	u2_pk2mm (
		.clk				(clock_sig),
		.reset_n			(~reset_sig),

		.in_ready			(avm_in_ready_sig),
		.in_valid			(avm_in_valid_sig),
		.in_data			(avm_in_data_sig),
		.in_startofpacket	(avm_in_startofpacket_sig),
		.in_endofpacket		(avm_in_endofpacket_sig),
		.out_ready			(avm_out_ready_sig),
		.out_valid			(avm_out_valid_sig),
		.out_data			(avm_out_data_sig),
		.out_startofpacket	(avm_out_startofpacket_sig),
		.out_endofpacket	(avm_out_endofpacket_sig),

		.address			(avm_address),
		.readdata			(avm_readdata),
		.read				(avm_read),
		.write				(avm_write),
		.byteenable			(avm_byteenable),
		.writedata			(avm_writedata),
		.waitrequest		(avm_waitrequest),
		.readdatavalid		(avm_readdatavalid)
	);



endmodule
