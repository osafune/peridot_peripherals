// ===================================================================
// TITLE : PERIDOT-NG / Byte to Avalon-MM Bridge
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2014/03/10 -> 2014/03/27
//   UPDATE : 2017/01/23
//
// ===================================================================
// *******************************************************************
//    (C)2014-2017, J-7SYSTEM WORKS LIMITED.  All rights Reserved.
//
// * This module is a free sourcecode and there is NO WARRANTY.
// * No restriction on use. You can use, modify and redistribute it
//   for personal, non-profit or commercial products UNDER YOUR
//   RESPONSIBILITY.
// * Redistributions of source code must retain the above copyright
//   notice.
// *******************************************************************

`timescale 1ns / 100ps

module peridot_mm_master (
	// Interface: clk
	input			clk,
	input			reset,

	// Interface: ST in
	output			in_ready,
	input  [7:0]	in_data,
	input			in_valid,

	// Interface: ST out
	input			out_ready,
	output [7:0]	out_data,
	output			out_valid,

	// Interface: MM master
	output [31:0]	avm_address,
	input  [31:0]	avm_readdata,
	output			avm_read,
	output			avm_write,
	output [ 3:0]	avm_byteenable,
	output [31:0]	avm_writedata,
	input			avm_waitrequest,
	input			avm_readdatavalid
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
