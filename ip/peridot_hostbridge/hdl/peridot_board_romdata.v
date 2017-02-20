// ===================================================================
// TITLE : PERIDOT-NG / board serial-rom contents
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2017/01/20 -> 2017/01/25
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

// sdcに追加 
// set_false_path -from [get_registers \{*\|altchip_id:*\|regout_wire\}] -to [get_registers \{*\|altchip_id:*\|lpm_shiftreg:shift_reg\|dffs\[63\]\}]

`timescale 1ns / 100ps

module peridot_board_romdata #(
	parameter CHIPUID_FEATURE	= "ENABLE",
	parameter DEVICE_FAMILY		= "",
	parameter PERIDOT_GENCODE	= 8'h4e,				// generation code
	parameter UID_VALUE			= 64'hffffffffffffffff
) (
	// Interface: clk & reset
	input			clk,
	input			reset,
	output			ready,

	// Interface: seral-rom byteread
	input  [4:0]	byteaddr,
	output [7:0]	bytedata,

	// Interface: Condit (UID)
	output			uid_enable,			// uid functon valid = '1' / invalid = '0'
	output [63:0]	uid,				// uid data
	output			uid_valid			// uid datavalid = '1' / invalid = '0'
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */



/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = reset;				// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;				// モジュール内部駆動クロック 

	reg  [4:0]		resetcount_reg;
	reg				romready_reg;
	wire			uid_enable_sig;
	wire [63:0]		uid_data_sig;
	wire			uid_valid_sig;

	wire [4:0]		nibbleaddr_sig;
	wire [7:0]		headerdata_sig;
	wire [3:0]		uidnibble_sig;
	wire [7:0]		serialdata_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	///// UIDリードシーケンス処理 /////
	// リセット後、ID値が確定するまで80クロックかかる 

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			resetcount_reg <= 1'b0;
			romready_reg <= 1'b0;
		end
		else begin
			if (resetcount_reg == 5'd15) begin
				romready_reg <= uid_valid_sig;
			end
			else begin
				resetcount_reg <= resetcount_reg - 1'd1;
			end
		end
	end

	assign ready = romready_reg;


	///// UIDモジュールインスタンス /////

generate
	if (CHIPUID_FEATURE == "ENABLE" && DEVICE_FAMILY == "MAX 10") begin
		assign uid_enable_sig = 1'b1;

		altchip_id #(
			.DEVICE_FAMILY	("MAX 10"),
			.ID_VALUE		(64'hffffffffffffffff),
			.ID_VALUE_STR	("00000000ffffffff")
		)
		u1_max10_uid (
			.clkin			(clock_sig),
			.reset			(~resetcount_reg[3]),
			.data_valid		(uid_valid_sig),
			.chip_id		(uid_data_sig)
		);
	end
	else if (CHIPUID_FEATURE == "ENABLE" && DEVICE_FAMILY == "Cyclone V") begin
		assign uid_enable_sig = 1'b1;

		altchip_id #(
			.DEVICE_FAMILY	("Cyclone V"),
			.ID_VALUE		(64'hffffffffffffffff)
		)
		u1_cyclone5_uid (
			.clkin			(clock_sig),
			.reset			(~resetcount_reg[3]),
			.data_valid		(uid_valid_sig),
			.chip_id		(uid_data_sig)
		);
	end
	else begin	// CycloneIV E or other
		assign uid_enable_sig = 1'b0;
		assign uid_valid_sig = 1'b1;
		assign uid_data_sig = UID_VALUE;
	end
endgenerate

	assign uid_enable = uid_enable_sig;
	assign uid = uid_data_sig;
	assign uid_valid = uid_valid_sig;



	///// PERIDOTシリアルデータへ変換 /////

	function [7:0] conv_hex2ascii(
			input [3:0]		hex
		);
	begin
		case (hex)
		4'h0 : conv_hex2ascii = 8'h30;
		4'h1 : conv_hex2ascii = 8'h31;
		4'h2 : conv_hex2ascii = 8'h32;
		4'h3 : conv_hex2ascii = 8'h33;
		4'h4 : conv_hex2ascii = 8'h34;
		4'h5 : conv_hex2ascii = 8'h35;
		4'h6 : conv_hex2ascii = 8'h36;
		4'h7 : conv_hex2ascii = 8'h37;
		4'h8 : conv_hex2ascii = 8'h38;
		4'h9 : conv_hex2ascii = 8'h39;
		4'ha : conv_hex2ascii = 8'h41;
		4'hb : conv_hex2ascii = 8'h42;
		4'hc : conv_hex2ascii = 8'h43;
		4'hd : conv_hex2ascii = 8'h44;
		4'he : conv_hex2ascii = 8'h45;
		4'hf : conv_hex2ascii = 8'h46;
		default : conv_hex2ascii = {8{1'bx}};
		endcase
	end
	endfunction


	assign headerdata_sig =
		(byteaddr[3:0] == 4'd0)? 8'h4a :	// 'J'
		(byteaddr[3:0] == 4'd1)? 8'h37 :	// '7'
		(byteaddr[3:0] == 4'd2)? 8'h57 :	// 'W'
		(byteaddr[3:0] == 4'd3)? 8'h02 :	// バージョン番号(v2)
		(byteaddr[3:0] == 4'd4)? 8'h4a :	// 'J'
		(byteaddr[3:0] == 4'd5)? 8'h37 :	// '7'
		(byteaddr[3:0] == 4'd6)? 8'h32 :	// '2'
		(byteaddr[3:0] == 4'd7)? PERIDOT_GENCODE[7:0] :	// 世代コード('A'=PERIDOT,'N'=PERIDOT-NG,'X'=Generic I/F)
		(byteaddr[3:0] == 4'd8)? 8'h39 :	// '9'
		(byteaddr[3:0] == 4'd9)? 8'h33 :	// '3'
		{8{1'bx}};

	assign nibbleaddr_sig = byteaddr - 5'd10;
	assign uidnibble_sig = 
		(nibbleaddr_sig[3:0] == 4'd0 )? uid_data_sig[15*4+3:15*4] :
		(nibbleaddr_sig[3:0] == 4'd1 )? uid_data_sig[14*4+3:14*4] :
		(nibbleaddr_sig[3:0] == 4'd2 )? uid_data_sig[13*4+3:13*4] :
		(nibbleaddr_sig[3:0] == 4'd3 )? uid_data_sig[12*4+3:12*4] :
		(nibbleaddr_sig[3:0] == 4'd4 )? uid_data_sig[11*4+3:11*4] :
		(nibbleaddr_sig[3:0] == 4'd5 )? uid_data_sig[10*4+3:10*4] :
		(nibbleaddr_sig[3:0] == 4'd6 )? uid_data_sig[ 9*4+3: 9*4] :
		(nibbleaddr_sig[3:0] == 4'd7 )? uid_data_sig[ 8*4+3: 8*4] :
		(nibbleaddr_sig[3:0] == 4'd8 )? uid_data_sig[ 7*4+3: 7*4] :
		(nibbleaddr_sig[3:0] == 4'd9 )? uid_data_sig[ 6*4+3: 6*4] :
		(nibbleaddr_sig[3:0] == 4'd10)? uid_data_sig[ 5*4+3: 5*4] :
		(nibbleaddr_sig[3:0] == 4'd11)? uid_data_sig[ 4*4+3: 4*4] :
		(nibbleaddr_sig[3:0] == 4'd12)? uid_data_sig[ 3*4+3: 3*4] :
		(nibbleaddr_sig[3:0] == 4'd13)? uid_data_sig[ 2*4+3: 2*4] :
		(nibbleaddr_sig[3:0] == 4'd14)? uid_data_sig[ 1*4+3: 1*4] :
		(nibbleaddr_sig[3:0] == 4'd15)? uid_data_sig[ 0*4+3: 0*4] :
		{4{1'bx}};

	assign serialdata_sig = conv_hex2ascii(uidnibble_sig);

	assign bytedata = 	(byteaddr < 5'd10)? headerdata_sig :
						(byteaddr < 5'd26)? serialdata_sig :
						8'hff;



endmodule
