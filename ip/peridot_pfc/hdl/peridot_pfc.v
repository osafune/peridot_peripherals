// ===================================================================
// TITLE : PERIDOT-NGS / Pin function controller
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2015/04/19 -> 2015/05/17
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

// reg00  din:bit7-0(RO)
// reg01  mask:bit15-8(WO) / dout:bit7-0
// reg02  pin0func:bit3-0 / pin1func:bit7-4 / ‥‥ / pin7func:bit31-28
// reg03  func0pin:bit3-0 / func1pin:bit7-4 / ‥‥ / func7pin:bit31-28

module peridot_pfc #(
	parameter PIN_WIDTH = 8,						// output port width :1-8
	parameter DEFAULT_PINREGS  = 32'h00000000,		// init pinreg value
	parameter DEFAULT_FUNCREGS = 32'h00000000		// init funcreg value
) (
	// Interface: clk
	input wire			csi_clk,
	input wire			rsi_reset,

	// Interface: Avalon-MM slave
	input wire  [1:0]	avs_address,
	input wire			avs_read,
	output wire [31:0]	avs_readdata,
	input wire			avs_write,
	input wire  [31:0]	avs_writedata,

	// External Interface
	output wire [7:0]	coe_function_din,
	input wire  [7:0]	coe_function_dout,
	input wire  [7:0]	coe_function_oe,
	input wire  [7:0]	coe_function_aux0,
	input wire  [7:0]	coe_function_aux1,
	input wire  [7:0]	coe_function_aux2,
	input wire  [7:0]	coe_function_aux3,

	output wire [7:0]	coe_pin_through,
	input wire  [5:0]	coe_pin_aux_in,

	inout wire  [PIN_WIDTH-1:0]	coe_pin
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */



/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = rsi_reset;				// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = csi_clk;				// モジュール内部駆動クロック 

	reg  [7:0]		pin_din_reg, pin_dout_reg;
	reg  [31:0]		pinsel_reg, funcsel_reg;
	wire [7:0]		pin_dout_sig, pin_oe_sig, pin_din_sig;

	genvar			i;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	///// Avalon-MM レジスタ処理 /////

	assign avs_readdata =
			(avs_address == 2'd0)? {24'b0, pin_din_reg} :
			(avs_address == 2'd1)? {24'b0, pin_dout_reg} :
			(avs_address == 2'd2)? pinsel_reg :
			(avs_address == 2'd3)? funcsel_reg :
			{32{1'bx}};

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			pinsel_reg  <= DEFAULT_PINREGS;
			funcsel_reg <= DEFAULT_FUNCREGS;
		end
		else begin
			pin_din_reg <= pin_din_sig;

			if (avs_write) begin
				case (avs_address)
					2'd1 : pin_dout_reg <= (pin_dout_reg & avs_writedata[15:8])|(avs_writedata[7:0] & ~avs_writedata[15:8]);
					2'd2 : pinsel_reg <= avs_writedata;
					2'd3 : funcsel_reg <= avs_writedata;
				endcase
			end

		end
	end



	///// ファンクションクロスバー /////

	// ファンクション→ピン出力 

	generate
		for (i=0 ; i<PIN_WIDTH ; i=i+1) begin : xb_tx
			assign pin_dout_sig[i] =
					(pinsel_reg[i*4+3:i*4] == 4'd1)? pin_dout_reg[i] :

					(pinsel_reg[i*4+3:i*4] == 4'd4)? coe_function_aux0[i] :
					(pinsel_reg[i*4+3:i*4] == 4'd5)? coe_function_aux1[i] :
					(pinsel_reg[i*4+3:i*4] == 4'd6)? coe_function_aux2[i] :
					(pinsel_reg[i*4+3:i*4] == 4'd7)? coe_function_aux3[i] :

					(pinsel_reg[i*4+3:i*4] == 4'd8)?  coe_function_dout[0] :
					(pinsel_reg[i*4+3:i*4] == 4'd9)?  coe_function_dout[1] :
					(pinsel_reg[i*4+3:i*4] == 4'd10)? coe_function_dout[2] :
					(pinsel_reg[i*4+3:i*4] == 4'd11)? coe_function_dout[3] :
					(pinsel_reg[i*4+3:i*4] == 4'd12)? coe_function_dout[4] :
					(pinsel_reg[i*4+3:i*4] == 4'd13)? coe_function_dout[5] :
					(pinsel_reg[i*4+3:i*4] == 4'd14)? coe_function_dout[6] :
					(pinsel_reg[i*4+3:i*4] == 4'd15)? coe_function_dout[7] :
					1'bx;

			assign pin_oe_sig[i] =
					(pinsel_reg[i*4+3:i*4] == 4'd1)? 1'b1 :

					(pinsel_reg[i*4+3:i*4] == 4'd4)? 1'b1 :
					(pinsel_reg[i*4+3:i*4] == 4'd5)? 1'b1 :
					(pinsel_reg[i*4+3:i*4] == 4'd6)? 1'b1 :
					(pinsel_reg[i*4+3:i*4] == 4'd7)? 1'b1 :

					(pinsel_reg[i*4+3:i*4] == 4'd8)?  coe_function_oe[0] :
					(pinsel_reg[i*4+3:i*4] == 4'd9)?  coe_function_oe[1] :
					(pinsel_reg[i*4+3:i*4] == 4'd10)? coe_function_oe[2] :
					(pinsel_reg[i*4+3:i*4] == 4'd11)? coe_function_oe[3] :
					(pinsel_reg[i*4+3:i*4] == 4'd12)? coe_function_oe[4] :
					(pinsel_reg[i*4+3:i*4] == 4'd13)? coe_function_oe[5] :
					(pinsel_reg[i*4+3:i*4] == 4'd14)? coe_function_oe[6] :
					(pinsel_reg[i*4+3:i*4] == 4'd15)? coe_function_oe[7] :
					1'b0;
		end
	endgenerate


	// ピンIOE 

	generate
		for (i=0 ; i<PIN_WIDTH ; i=i+1) begin : ioe
			peridot_pfc_ioe
			u_ioe (
				.datain		(pin_dout_sig[i]),
				.oe			(pin_oe_sig[i]),
				.dataio		(coe_pin[i]),
				.dataout	(pin_din_sig[i])
			);
		end

		for (i=PIN_WIDTH ; i<8 ; i=i+1) begin : dummy
			assign pin_din_sig[i] = 1'bx;
		end
	endgenerate

	assign coe_pin_through = pin_din_sig;


	// ピン入力→ファンクション 

	generate
		for (i=0 ; i<8 ; i=i+1) begin : xb_rx
			assign coe_function_din[i] =
					(funcsel_reg[i*4+3:i*4] == 4'd0)? 1'b0 :
					(funcsel_reg[i*4+3:i*4] == 4'd1)? 1'b1 :
					(funcsel_reg[i*4+3:i*4] == 4'd2)? coe_pin_aux_in[0] :
					(funcsel_reg[i*4+3:i*4] == 4'd3)? coe_pin_aux_in[1] :
					(funcsel_reg[i*4+3:i*4] == 4'd4)? coe_pin_aux_in[2] :
					(funcsel_reg[i*4+3:i*4] == 4'd5)? coe_pin_aux_in[3] :
					(funcsel_reg[i*4+3:i*4] == 4'd6)? coe_pin_aux_in[4] :
					(funcsel_reg[i*4+3:i*4] == 4'd7)? coe_pin_aux_in[5] :

					(funcsel_reg[i*4+3:i*4] == 4'd8)?  pin_din_sig[0] :
					(funcsel_reg[i*4+3:i*4] == 4'd9)?  pin_din_sig[1] :
					(funcsel_reg[i*4+3:i*4] == 4'd10)? pin_din_sig[2] :
					(funcsel_reg[i*4+3:i*4] == 4'd11)? pin_din_sig[3] :
					(funcsel_reg[i*4+3:i*4] == 4'd12)? pin_din_sig[4] :
					(funcsel_reg[i*4+3:i*4] == 4'd13)? pin_din_sig[5] :
					(funcsel_reg[i*4+3:i*4] == 4'd14)? pin_din_sig[6] :
					(funcsel_reg[i*4+3:i*4] == 4'd15)? pin_din_sig[7] :
					1'bx;
		end
	endgenerate



endmodule
