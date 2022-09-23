// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / MAC CRC32
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/07/01 -> 2022/07/25
//            : 2022/09/01 (FIXED)
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

module peridot_ethio_crc32 (
	input wire			clk,
	input wire			clk_ena,

	input wire			init,
	output wire [31:0]	crc,

	input wire			in_valid,
	input wire  [1:0]	in_data,
	input wire			shift,
	output wire [1:0]	out_data
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */



/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			clock_sig = clk;		// モジュール内部駆動クロック 

	reg  [31:0]		crc_reg;
	wire [31:0]		data0_crc_sig, data1_crc_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	function [31:0] calc_crc32 (input [31:0] crc, input data);
		calc_crc32 = {1'b0, crc[31:1]} ^ ((crc[0] ^ data)? 32'hedb88320 : 32'b0);
	endfunction

	assign data0_crc_sig = calc_crc32(crc_reg, in_data[0]);
	assign data1_crc_sig = calc_crc32(data0_crc_sig, in_data[1]);

	always @(posedge clock_sig) begin
		if (clk_ena) begin
			if (init) begin
				crc_reg <= {32{1'b1}};
			end
			else if (in_valid) begin
				crc_reg <= data1_crc_sig;
			end
			else if (shift) begin
				crc_reg <= {2'b00, crc_reg[31:2]};
			end
		end
	end

	assign crc = crc_reg;
	assign out_data = ~crc_reg[1:0];


endmodule

`default_nettype wire
