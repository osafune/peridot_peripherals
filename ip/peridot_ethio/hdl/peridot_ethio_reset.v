// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / Reset control
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/09/21 -> 2022/09/21
//            : 2022/09/21 (FIXED)
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

module peridot_ethio_reset #(
	parameter RESET_COUNTER_BITWIDTH	= 4	// リセットタイマーのビット長 (2**RESET_COUNTER_BITWIDTHクロック待つ)
) (
	input wire			reset,
	input wire			clk,
	input wire			enable,
	output wire			active,				// 1=MAC側動作中(非リセット)

	input wire			packet_busy,		// udp2packetのビジー信号 
	output wire			packet_enable_out,	// udp2packetのイネーブル 
	output wire			fifo_reset_out,		// rxfifo,txfifoのAvalon-ST側リセット出力 

	input wire			mac_clk,
	output wire			mac_reset_out		// MAC側リセット出力 
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */



/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 
	wire			clock_sig = clk;		// モジュール内部駆動クロック 
	wire			mac_clk_sig = mac_clk;

	reg				enable_reg;
	reg  [RESET_COUNTER_BITWIDTH:0] reset_count_reg;
	wire			mac_enable_sig;
	wire			mac_reset_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	// udp2packetイネーブル信号 

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			enable_reg <= 1'b0;
		end
		else begin
			if (!packet_busy) enable_reg <= enable;
		end
	end

	assign packet_enable_out = enable_reg;


	// rxfifo,txfifoのAvalon-ST側リセット信号 

	peridot_ethio_cdb_areset
	u_rst1 (
		.areset		(reset_sig | ~enable_reg),
		.clk		(clock_sig),
		.reset_out	(fifo_reset_out)
	);


	// MAC側リセット信号 

	peridot_ethio_cdb_signal
	u_cdb1 (
		.reset		(1'b0),
		.clk		(mac_clk_sig),
		.in_sig		(enable_reg),
		.out_sig	(mac_enable_sig)
	);

	peridot_ethio_cdb_areset
	u_rst2 (
		.areset		(reset_sig | ~mac_enable_sig),
		.clk		(mac_clk_sig),
		.reset_out	(mac_reset_sig)
	);

	always @(posedge mac_clk_sig or posedge mac_reset_sig) begin
		if (mac_reset_sig) begin
			reset_count_reg <= 1'd0;
		end
		else begin
			if (!reset_count_reg[RESET_COUNTER_BITWIDTH]) reset_count_reg <= reset_count_reg + 1'd1;
		end
	end

	assign mac_reset_out = ~reset_count_reg[RESET_COUNTER_BITWIDTH];


	// Avtive信号 

	peridot_ethio_cdb_signal
	u_cdb2 (
		.reset		(reset_sig),
		.clk		(clock_sig),
		.in_sig		(reset_count_reg[RESET_COUNTER_BITWIDTH]),
		.out_sig	(active)
	);



endmodule

`default_nettype wire
