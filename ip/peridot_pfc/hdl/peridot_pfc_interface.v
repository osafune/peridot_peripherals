// ===================================================================
// TITLE : PERIDOT-NGS / Pin function controller Qsys interface
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2015/04/19 -> 2015/05/17
//   MODIFY : 2017/05/13 17.0 beta
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

// BANK0(D0-D7)
//   reg00(+00)  din:bit7-0(RO)
//   reg01(+04)  mask:bit15-8(WO) / dout:bit7-0
//   reg02(+08)  pin0func:bit3-0 / pin1func:bit7-4 / ‥‥ / pin7func:bit31-28
//   reg03(+0C)  func0pin:bit3-0 / func1pin:bit7-4 / ‥‥ / func7pin:bit31-28
//
// BANK1(D8-D15)
//   reg04(+10)  din:bit7-0(RO)
//   reg05(+14)  mask:bit15-8(WO) / dout:bit7-0
//   reg06(+18)  pin0func:bit3-0 / pin1func:bit7-4 / ‥‥ / pin7func:bit31-28
//   reg07(+1C)  func0pin:bit3-0 / func1pin:bit7-4 / ‥‥ / func7pin:bit31-28
//
// BANK2(D16-D21)
//   reg08(+20)  din:bit7-0(RO)
//   reg09(+24)  mask:bit15-8(WO) / dout:bit7-0
//   reg10(+28)  pin0func:bit3-0 / pin1func:bit7-4 / ‥‥ / pin7func:bit31-28
//   reg11(+2C)  func0pin:bit3-0 / func1pin:bit7-4 / ‥‥ / func7pin:bit31-28
//
// BANK3(D22-D27)
//   reg12(+30)  din:bit7-0(RO)
//   reg13(+34)  mask:bit15-8(WO) / dout:bit7-0
//   reg14(+38)  pin0func:bit3-0 / pin1func:bit7-4 / ‥‥ / pin7func:bit31-28
//   reg15(+3C)  func0pin:bit3-0 / func1pin:bit7-4 / ‥‥ / func7pin:bit31-28

module peridot_pfc_interface(
	// Interface: clk and reset
	input wire			csi_clk,
	input wire			rsi_reset,

	// Interface: Avalon-MM slave
	input wire  [3:0]	avs_address,
	input wire			avs_read,		// read  : 0-setup,1-wait,0-hold
	output wire [31:0]	avs_readdata,
	input wire			avs_write,		// write : 0-setup,0-wait,0-hold
	input wire  [31:0]	avs_writedata,

	// External Interface
	output wire			coe_pfc_clk,
	output wire			coe_pfc_reset,
	output wire [36:0]	coe_pfc_cmd,
	input wire  [31:0]	coe_pfc_resp
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */



/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */

	reg  [31:0]		readdata_reg;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	assign avs_readdata = readdata_reg;

	always @(posedge csi_clk) begin
		readdata_reg <= coe_pfc_resp;
	end

	assign coe_pfc_clk = csi_clk;
	assign coe_pfc_reset = rsi_reset;

	assign coe_pfc_cmd[36] = avs_write;
	assign coe_pfc_cmd[35:32] = avs_address;
	assign coe_pfc_cmd[31:0] = avs_writedata;



endmodule
