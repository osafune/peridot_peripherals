// ===================================================================
// TITLE : PERIDOT-NGS / UART reciever phy
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2015/12/27 -> 2015/12/27
//   UPDATE : 2017/03/01
//
// ===================================================================
// *******************************************************************
//    (C)2015-2017, J-7SYSTEM WORKS LIMITED.  All rights Reserved.
//
// * This module is a free sourcecode and there is NO WARRANTY.
// * No restriction on use. You can use, modify and redistribute it
//   for personal, non-profit or commercial products UNDER YOUR
//   RESPONSIBILITY.
// * Redistributions of source code must retain the above copyright
//   notice.
// *******************************************************************

`timescale 1ns / 100ps

module peridot_phy_rxd #(
	parameter CLOCK_FREQUENCY	= 50000000,
	parameter UART_BAUDRATE		= 115200
) (
	// Interface: clk
	input wire			clk,
	input wire			reset,

	// Interface: ST out
	output wire			out_valid,
	output wire [7:0]	out_data,

	// interface UART
	input wire			rxd
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam CLOCK_DIVNUM = (CLOCK_FREQUENCY / UART_BAUDRATE) - 1;
	localparam BIT_CAPTURE  = (CLOCK_DIVNUM / 2);


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = reset;				// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;				// モジュール内部駆動クロック 

	reg [2:0]		rxdin_reg;

	reg [11:0]		divcount_reg;
	reg [3:0]		bitcount_reg;
	reg [7:0]		shift_reg;
	reg [7:0]		outdata_reg;
	reg				outvalid_reg;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			rxdin_reg <= 3'b111;
			divcount_reg <= 1'd0;
			bitcount_reg <= 1'd0;
			shift_reg <= 8'h00;
			outvalid_reg <= 1'b0;
			outdata_reg  <= 8'h00;

		end
		else begin
			rxdin_reg <= {rxdin_reg[1:0], rxd};

			if (bitcount_reg == 4'd0) begin
				outvalid_reg <= 1'b0;

				if (rxdin_reg[2:1] == 2'b10) begin
					divcount_reg <= BIT_CAPTURE[11:0];
					bitcount_reg <= 4'd10;
				end
			end
			else begin
				if (divcount_reg == 0) begin
					divcount_reg <= CLOCK_DIVNUM[11:0];

					if (bitcount_reg == 4'd10) begin			// start bit check
						if (rxdin_reg[2] == 1'b0) begin
							bitcount_reg <= bitcount_reg - 1'd1;
						end
						else begin
							bitcount_reg <= 4'd0;
						end
					end
					else if (bitcount_reg == 4'd1) begin		// stop bit check
						bitcount_reg <= bitcount_reg - 1'd1;

						if (rxdin_reg[2] == 1'b1) begin
							outvalid_reg <= 1'b1;
							outdata_reg  <= shift_reg;
						end
					end
					else begin
						bitcount_reg <= bitcount_reg - 1'd1;
						shift_reg <= {rxdin_reg[2], shift_reg[7:1]};
					end

				end
				else begin
					divcount_reg <= divcount_reg - 1'd1;
				end
			end

		end
	end

	assign out_valid = outvalid_reg;
	assign out_data  = outdata_reg;



endmodule
