// ===================================================================
// TITLE : PERIDOT-NGS / SWI SPI-Flash unique id readout
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2017/05/12 -> 2017/05/13
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


module peridot_csr_swi_ruid #(
	parameter RUID_COMMAND		= 8'h4b,	// RUID command
	parameter RUID_DUMMYBYTES	= 4,		// RUID dymmy bytes length : 3 or 4
	parameter RUID_UDATABYTES	= 16		// UID data bytes length : 8 to 16
) (
	// Interface: clk
	input wire			clk,
	input wire			reset,

	// Interface: SPI Peripheral control
	input wire  [31:0]	ruid_readata,
	output wire 		ruid_write,
	output wire [31:0]	ruid_writedata,

	// Internal signal
	output wire [63:0]	spiuid,
	output wire 		spiuid_valid
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam CS_ASSERT_BYTES	= 1;
	localparam UDATA_TOP_BYTES	= 1 + RUID_DUMMYBYTES + 2;
	localparam UDATA_LAST_BYTES	= 1 + RUID_DUMMYBYTES + 2 + RUID_UDATABYTES - 1;
	localparam UID_DONE_BYTES	= 1 + RUID_DUMMYBYTES + 2 + RUID_UDATABYTES;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = reset;					// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;					// モジュール内部駆動クロック 

	reg  [4:0]		bytecount_reg;
	reg				write_reg;
	reg  [63:0]		uid_data_reg;

	wire			spi_ready_sig;
	wire [7:0]		spi_recvdata_sig;
	wire [7:0]		spi_senddata_sig;
	wire			spi_assert_sig;



/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	assign spi_ready_sig = ruid_readata[9];
	assign spi_recvdata_sig = ruid_readata[7:0];
	assign spi_senddata_sig = (bytecount_reg == CS_ASSERT_BYTES[4:0])? RUID_COMMAND : 8'h00;
	assign spi_assert_sig = (bytecount_reg >= CS_ASSERT_BYTES[4:0] && bytecount_reg < UDATA_LAST_BYTES[4:0])? 1'b1 : 1'b0;

	assign ruid_writedata = {22'b0, 1'b1, spi_assert_sig, spi_senddata_sig};
	assign ruid_write = write_reg;

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			bytecount_reg <= 1'd0;
			write_reg <= 1'b0;
			uid_data_reg <= 64'h0;
		end
		else begin
			if (bytecount_reg != UID_DONE_BYTES[4:0]) begin
				if (write_reg) begin
					write_reg <= 1'b0;
					bytecount_reg <= bytecount_reg + 1'd1;
				end
				else if (spi_ready_sig) begin
					write_reg <= 1'b1;

					if (bytecount_reg >= UDATA_TOP_BYTES[4:0]) begin
						uid_data_reg <= {uid_data_reg[55:0], (uid_data_reg[63:56] ^ spi_recvdata_sig)};
					end
				end
			end
		end
	end

	assign spiuid = uid_data_reg;
	assign spiuid_valid = (bytecount_reg == UID_DONE_BYTES[4:0])? 1'b1 : 1'b0;



endmodule
