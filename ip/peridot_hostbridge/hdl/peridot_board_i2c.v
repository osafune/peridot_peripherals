// ===================================================================
// TITLE : PERIDOT-NG / I2C Serial Interface
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM Works)
//   DATE   : 2016/01/04 -> 2016/01/05
//   UPDATE : 2017/01/20
//
// ===================================================================
// *******************************************************************
//    (C)2016-2017, J-7SYSTEM WORKS LIMITED.  All rights Reserved.
//
// * This module is a free sourcecode and there is NO WARRANTY.
// * No restriction on use. You can use, modify and redistribute it
//   for personal, non-profit or commercial products UNDER YOUR
//   RESPONSIBILITY.
// * Redistributions of source code must retain the above copyright
//   notice.
// *******************************************************************


`timescale 1ns / 100ps

module peridot_board_i2c (
	// Interface: clk
	input			clk,
	input			reset,

	// Interface: Condit (I2C)
	input			i2c_scl_i,
	output			i2c_scl_o,
	input			i2c_sda_i,
	output			i2c_sda_o,

	// Interface: state
	output			condi_start,		// Pulse : Start condition detect
	output			condi_stop,			// Pulse : Stop condition detect
	output			done_byte,			// Pulse : Byte transaction done (recieve data valid)
	input			ackwaitrequest,		// Level : '1' is acknowledge transaction wait request
	output			done_ack,			// Pulse : Acknowledge transaction done pulse
	input  [7:0]	send_bytedata,
	input			send_bytedatavalid,
	output [7:0]	recieve_bytedata,
	input			send_ackdata,
	output			recieve_ackdata
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */



/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = reset;				// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;				// モジュール内部駆動クロック 

	reg  [2:0]		scl_in_reg;
	reg  [2:0]		sda_in_reg;
	wire			condi_start_sig;
	wire			condi_stop_sig;
	wire			scl_rise_sig;
	wire			scl_fall_sig;

	reg  [3:0]		bitcount_reg;
	reg				scl_out_reg;
	reg				ack_reg;
	reg  [7:0]		txdata_reg;
	reg  [7:0]		rxdata_reg;

	(* altera_attribute = "-name CUT ON -to scl_in_reg[0]" *)
	(* altera_attribute = "-name CUT ON -to sda_in_reg[0]" *)


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	// I2C信号の同期化と状態検出 

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			scl_in_reg <= 3'b111;
			sda_in_reg <= 3'b111;
		end
		else begin
			scl_in_reg <= {scl_in_reg[1:0], i2c_scl_i};
			sda_in_reg <= {sda_in_reg[1:0], i2c_sda_i};
		end
	end

	assign condi_start_sig = (sda_in_reg[2] && !sda_in_reg[1] && scl_in_reg[2] && scl_in_reg[1]);
	assign condi_stop_sig  = (!sda_in_reg[2] && sda_in_reg[1] && scl_in_reg[2] && scl_in_reg[1]);
	assign scl_rise_sig = (!scl_in_reg[2] && scl_in_reg[1]);
	assign scl_fall_sig = (scl_in_reg[2] && !scl_in_reg[1]);


	// バイト送受信 

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			bitcount_reg <= 4'd0;
			scl_out_reg  <= 1'b1;
			ack_reg      <= 1'b0;
			txdata_reg   <= 8'hff;
		end
		else begin
			if (condi_start_sig) begin
				bitcount_reg <= 4'd9;
			end
			else begin
				if (bitcount_reg == 4'd9) begin
					if (scl_fall_sig) begin
						bitcount_reg <= 4'd0;
					end
				end
				else if (bitcount_reg == 4'd8) begin
					if (scl_out_reg == 1'b0) begin
						txdata_reg[7] <= ~send_ackdata;

						if (!ackwaitrequest) begin
							scl_out_reg <= 1'b1;
						end
					end
					else begin
						if (scl_rise_sig) begin
							ack_reg <= ~sda_in_reg[1];
						end

						if (scl_fall_sig) begin
							bitcount_reg <= 4'd0;
							if (send_bytedatavalid) begin
								txdata_reg <= send_bytedata;
							end
							else begin
								txdata_reg <= 8'hff;
							end
						end
					end
				end
				else begin
					if (scl_rise_sig) begin
						rxdata_reg <= {rxdata_reg[6:0], sda_in_reg[1]};
					end

					if (scl_fall_sig) begin
						if (bitcount_reg == 4'd7) begin
							scl_out_reg <= 1'b0;
						end

						bitcount_reg <= bitcount_reg + 1'd1;
						txdata_reg <= {txdata_reg[6:0], 1'b1};
					end
				end
			end

		end
	end


	assign i2c_scl_o = scl_out_reg;
	assign i2c_sda_o = txdata_reg[7];

	assign condi_start = condi_start_sig;
	assign condi_stop  = condi_stop_sig;
	assign done_byte   = (scl_fall_sig && bitcount_reg == 4'd7)? 1'b1 : 1'b0;
	assign done_ack    = (scl_fall_sig && bitcount_reg == 4'd8)? 1'b1 : 1'b0;
	assign recieve_bytedata = rxdata_reg;
	assign recieve_ackdata  = ack_reg;




endmodule
