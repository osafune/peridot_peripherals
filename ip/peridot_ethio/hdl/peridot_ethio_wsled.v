// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / WSLED Serializer
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/09/28 -> 2022/09/28
//            : 2022/09/28 (FIXED)
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

module peridot_ethio_wsled #(
	parameter BIT_PERIOD_COUNT		= 17,	// 1bitのカウント（クロック数） 
	parameter SYMBOL1_COUNT			= 9,	// シンボル1のTH1カウント（クロック数） 
	parameter SYMBOL0_COUNT			= 4,	// シンボル0のTH1カウント（クロック数） 
	parameter RESET_BITCOUNT		= 7		// リセット期間のカウント（ビット数） 
) (
	output wire [6:0]	test_symcounter,
	output wire [8:0]	test_rstcounter,


	input wire			reset,
	input wire			clk,

	output wire			in_ready,
	input wire			in_valid,
	input wire  [7:0]	in_data,

	output wire			wsled
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	function integer fnlog2 (input integer x);
	begin
		x = x - 1;
		for (fnlog2 = 0 ; x > 0 ; fnlog2 = fnlog2 + 1) x = x >> 1;
	end
	endfunction

	localparam SYMBOLCOUNTER_WIDTH = fnlog2(BIT_PERIOD_COUNT);
	localparam SYMCOUNT_MAX = BIT_PERIOD_COUNT[SYMBOLCOUNTER_WIDTH-1:0] - 1'd1;
	localparam S1_COUNT_VALUE = SYMBOL1_COUNT[SYMBOLCOUNTER_WIDTH-1:0];
	localparam S0_COUNT_VALUE = SYMBOL0_COUNT[SYMBOLCOUNTER_WIDTH-1:0];

	localparam RESETCOUNTER_WIDTH = fnlog2(RESET_BITCOUNT);
	localparam RST_COUNT_VALUE = RESET_BITCOUNT[RESETCOUNTER_WIDTH-1:0] - 2'd2;

	localparam	STATE_IDLE		= 2'd0,
				STATE_START		= 2'd1,
				STATE_RESET		= 2'd3;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 
	wire			clock_sig = clk;		// モジュール内部駆動クロック 

	reg  [SYMBOLCOUNTER_WIDTH-1:0] symcounter_reg;
	reg				symbol_reg;
	reg				wsled_reg;
	reg  [2:0]		bitcount_reg;
	reg  [7:0]		data_reg;
	reg  [RESETCOUNTER_WIDTH-1:0] rstcounter_reg;

	reg  [1:0]		state_reg;
	wire			bit_timing_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */

	assign test_symcounter = symcounter_reg;
	assign test_rstcounter = rstcounter_reg;


/* ===== モジュール構造記述 ============== */

	assign in_ready = (state_reg == STATE_IDLE || (state_reg == STATE_START && bitcount_reg == 3'd7))? bit_timing_sig : 1'b0;

	assign bit_timing_sig = (symcounter_reg == 1'd0);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			symcounter_reg <= 1'd0;
			symbol_reg <= 1'b0;
			wsled_reg <= 1'b0;

			state_reg <= STATE_IDLE;
			bitcount_reg <= 1'd0;
			rstcounter_reg <= 1'd0;
		end
		else begin

			// シリアルLEDのビットシンボルの生成 
			if (symcounter_reg == SYMCOUNT_MAX) begin
				symcounter_reg <= 1'd0;
			end
			else begin
				symcounter_reg <= symcounter_reg + 1'd1;
			end

			if (bit_timing_sig) begin
				symbol_reg <= 1'b1;
			end
			else begin
				if ((data_reg[7] && symcounter_reg == S1_COUNT_VALUE) || (!data_reg[7] && symcounter_reg == S0_COUNT_VALUE)) begin
					symbol_reg <= 1'b0;
				end
			end

			wsled_reg <= (state_reg == STATE_START)? symbol_reg : 1'b0;


			// バイトストリームデータ受信 
			if (bit_timing_sig) begin
				case (state_reg)
				STATE_IDLE : begin
					rstcounter_reg <= 1'd0;

					if (in_valid) begin
						data_reg <= in_data;

						if (in_data == 8'hff) begin
							state_reg <= STATE_RESET;
						end
						else begin
							state_reg <= STATE_START;
						end
					end
				end

				STATE_START : begin
					bitcount_reg <= bitcount_reg + 1'd1;
					rstcounter_reg <= 1'd0;

					if (bitcount_reg == 3'd7) begin
						data_reg <= in_data;

						if (!in_valid || in_data == 8'hff) begin
							state_reg <= STATE_RESET;
						end
					end
					else begin
						data_reg <= {data_reg[6:0], 1'b1};
					end
				end

				STATE_RESET : begin
					rstcounter_reg <= rstcounter_reg + 1'd1;

					if (rstcounter_reg == RST_COUNT_VALUE) begin
						state_reg <= STATE_IDLE;
					end
				end
				endcase
			end
		end
	end

	assign wsled = wsled_reg;



endmodule

`default_nettype wire
