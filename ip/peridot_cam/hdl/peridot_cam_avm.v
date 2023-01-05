// ===================================================================
// TITLE : PERIDOT-NGS / DVP Avalon-MM master(32bit×n-burst)
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2017/04/04 -> 2017/04/06
//   MODIFY : 2023/01/04 バースト長可変に変更 
//
// ===================================================================
//
// The MIT License (MIT)
// Copyright (c) 2017,2018 J-7SYSTEM WORKS LIMITED.
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

module peridot_cam_avm #(
	parameter BURSTCOUNT_WIDTH		= 4,			// バースト長単位(2^BURSTCOUNT_WIDTH)
	parameter TRANSCYCLE_WIDTH		= 22			// 最大転送回数(2^TRANSCYCLE_WIDTH-1)
) (
	// Interface: clk
	input wire			csi_global_reset,
	input wire			avm_m1_clk,

	// Interface: Avalon-MM master
	output wire [31:0]	avm_m1_address,
	output wire			avm_m1_write,
	output wire [31:0]	avm_m1_writedata,
	output wire [3:0]	avm_m1_byteenable,
	output wire [BURSTCOUNT_WIDTH:0] avm_m1_burstcount,
	input wire			avm_m1_waitrequest,

	// External Interface
	input wire [31:0]	address_top,					// ストア先頭アドレス(下位2bit無効) 
	input wire [TRANSCYCLE_WIDTH-1:0] transcycle_num,	// データ全長(32bitワード単位) 
	input wire			start,
	output wire			done,

	input wire [BURSTCOUNT_WIDTH:0] writedata_usedw,	// データFIFOに詰まれた数 (0～2^BURSTCOUNT_WIDTH)
	input wire [31:0]	writedata,
	output wire			writedata_rdack
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam BURSTUNIT		= 2**BURSTCOUNT_WIDTH;

	localparam STATE_IDLE		= 5'd0;
	localparam STATE_SETUP		= 5'd1;
	localparam STATE_START		= 5'd2;
	localparam STATE_BURSTWRITE	= 5'd3;
	localparam STATE_LOOP		= 5'd4;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = csi_global_reset;	// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			avm_clk_sig = avm_m1_clk;		// Avalonバス駆動クロック 

	reg  [4:0]		avmstate_reg;
	reg				done_reg;
	reg  [TRANSCYCLE_WIDTH-1:0] chunkcount_reg;
	reg  [BURSTCOUNT_WIDTH:0] datacount_reg;
	reg  [31:0]		address_reg;
	reg				write_reg;

	wire [31:0]		avm_writedata_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	///// AvalonMMトランザクション処理 /////

	assign done = done_reg;

	assign avm_m1_address = {address_reg[31:2], 2'b0};
	assign avm_m1_write = write_reg;
	assign avm_m1_writedata = writedata;
	assign avm_m1_byteenable = 4'b1111;				// 32bitライト固定 
	assign avm_m1_burstcount = datacount_reg;		// バーストカウント 

	assign writedata_rdack = (!avm_m1_waitrequest)? write_reg : 1'b0;	// データ要求 

	always @(posedge avm_clk_sig or posedge reset_sig) begin
		if (reset_sig) begin
			avmstate_reg <= STATE_IDLE;
			done_reg <= 1'b1;
			write_reg <= 1'b0;
		end
		else begin
			case (avmstate_reg)
				STATE_IDLE : begin					// IDLE 
					if (start) begin
						avmstate_reg <= STATE_SETUP;
						done_reg <= 1'b0;
						chunkcount_reg <= transcycle_num;
						address_reg <= address_top;
					end
				end

				STATE_SETUP : begin					// バーストセットアップ 
					avmstate_reg <= STATE_START;
					if (chunkcount_reg > BURSTUNIT[TRANSCYCLE_WIDTH-1:0]) begin
						datacount_reg <= BURSTUNIT[BURSTCOUNT_WIDTH:0];
					end
					else begin
						datacount_reg <= chunkcount_reg[BURSTCOUNT_WIDTH:0];
					end
				end

				STATE_START : begin					// FIFOデータ到着待ち 
					if (writedata_usedw >= datacount_reg) begin
						avmstate_reg <= STATE_BURSTWRITE;
						write_reg <= 1'b1;
					end
				end

				STATE_BURSTWRITE : begin			// データバーストライト 
					if (!avm_m1_waitrequest) begin
						if (datacount_reg == 1'd1) begin
							avmstate_reg <= STATE_LOOP;
							write_reg <= 1'b0;
						end

						datacount_reg <= datacount_reg - 1'd1;
						chunkcount_reg <= chunkcount_reg - 1'd1;
					end
				end

				STATE_LOOP : begin					// ループチェック 
					if (chunkcount_reg) begin
						avmstate_reg <= STATE_SETUP;
						address_reg <= address_reg + (BURSTUNIT<<2);
					end
					else begin
						avmstate_reg <= STATE_IDLE;
						done_reg <= 1'b1;
					end
				end
			endcase

		end
	end



endmodule
