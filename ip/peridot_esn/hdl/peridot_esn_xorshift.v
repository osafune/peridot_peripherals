// ===================================================================
// TITLE : PERIDOT ESN - Xorshift32 unit
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2026/03/09 -> 2026/03/09
//            : 2026/03/14 (FIXED)
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

module peridot_esn_xorshift32 #(
	parameter SHIFT_SET_PARAM1 = 13,
	parameter SHIFT_SET_PARAM2 = 17,
	parameter SHIFT_SET_PARAM3 = 5
) (
	input wire			clk,
	input wire			init,
	input wire  [31:0]	seed,
	input wire			update,
	output wire [31:0]	data
);


/* ===== 外部変更可能パラメータ ========== */


/* ----- 内部パラメータ ------------------ */


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;		// モジュール内部駆動クロック 

	reg  [31:0]		x_reg;
	wire [31:0]		a_sig, b_sig, c_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	assign a_sig = x_reg ^ (x_reg << SHIFT_SET_PARAM1);
	assign b_sig = a_sig ^ (a_sig >> SHIFT_SET_PARAM2);
	assign c_sig = b_sig ^ (b_sig << SHIFT_SET_PARAM3);

	always @(posedge clock_sig) begin
		if (init) begin
			x_reg <= seed;
		end
		else if (update) begin
			x_reg <= c_sig;
		end
	end

	assign data = x_reg;


endmodule

`default_nettype wire
