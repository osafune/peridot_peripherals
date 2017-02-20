// ===================================================================
// TITLE : PERIDOT-NG / Host bridge including SWI
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2015/04/30 -> 2015/05/23
//   UPDATE : 2017/02/05
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

// reg00(+0)  bit31-0:class index(RO)
// reg01(+4)  bit31-0:generation time(RO)
// reg02(+8)  bit31-0:lower unique id(RO)
// reg03(+C)  bit31-0:upper unique id(RO)
// reg04(+10) bit31-16:deadkey(WO), bit15:uidvalid(RO), bit14:uidena(RO), bit13:epcsena(RO), bit12:mesena(RO),
//				bit11:bootsel(RO), bit8:niosreset(RW), bit3-0:led(RW)
// reg05(+14) bit15:irqena(RW), bit9:start(W)/ready(R), bit8:select(RW), bit7-0:txdata(W)/rxdata(R)
// reg06(+18) bit31-0:mutexmessage(RW)
// reg07(+1C) bit0:swi(RW)

//	CPURESET_KEY = 0の時はレジスタロックをしない 

module peridot_csr_swi #(
	parameter EPCSBOOT_FEATURE	= "ENABLE",			// EPCS access register enable
	parameter UIDREAD_FEATURE	= "ENABLE",			// chip uid readout register enable
	parameter MESSAGE_FEATURE	= "ENABLE",			// message and swi register enable
	parameter CLOCKFREQ			= 25000000,			// peripheral drive clock freq(Hz)
	parameter CLASSID			= 32'h72A00000,		// PERIDOT Class ID
	parameter TIMECODE			= 32'd1234567890,	// Generation Time stamp
	parameter CPURESET_KEY		= 16'hdead,			// cpureset register assert key
	parameter CPURESET_INIT		= 0					// Initialize coe_cpureset condition
) (
	// Interface: clk & reset
	input			csi_clk,
	input			rsi_reset,

	// Interface: Avalon-MM slave
	input  [2:0]	avs_address,
	input			avs_read,
	output [31:0]	avs_readdata,
	input			avs_write,
	input  [31:0]	avs_writedata,

	// Interface: Avalon-MM Interrupt sender
	output			ins_irq,

	// External:
	output			coe_cpureset,
	output [3:0]	coe_led,
	output			coe_cso_n,
	output			coe_dclk,
	output			coe_asdo,
	input			coe_data0,

	// Internal signal
	input			ru_bootsel,
	input			uid_enable,
	input [63:0]	uid,
	input			uid_valid
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam	SPIFLASH_MAXFREQ	= 40000000;		// EPCS/EPCQ maximum freq(Hz)

	localparam	TEMP_CLKDIV			= CLOCKFREQ / (SPIFLASH_MAXFREQ * 2);
	localparam	TEMP_DEC			= (TEMP_CLKDIV > 0 && (CLOCKFREQ %(SPIFLASH_MAXFREQ * 2)) == 0)? 1 : 0;
	localparam	SPI_REG_CLKDIV		= TEMP_CLKDIV - TEMP_DEC;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = rsi_reset;				// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = csi_clk;				// モジュール内部駆動クロック 

	reg				rreq_reg;
	reg  [3:0]		led_reg;
	reg  [31:0]		message_reg;
	reg				irq_reg;

	wire			uid_enable_sig;
	wire [63:0]		uid_sig;
	wire			uid_valid_sig;
	wire			bootsel_sig;

	wire			mes_enable_sig;
	wire [31:0]		message_sig;
	wire [31:0]		irq_readdata_sig;
	wire			swi_irq_sig;

	wire			epcs_enable_sig;
	wire [31:0]		spi_readdata_sig;
	wire			spi_irq_sig;
	wire			spi_write_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	///// Avalon-MM レジスタ処理 /////

generate
	if (UIDREAD_FEATURE == "ENABLE") begin
		assign uid_enable_sig = uid_enable;
		assign uid_sig = uid;
		assign uid_valid_sig = uid_valid;
	end
	else begin
		assign uid_enable_sig = 1'b0;
		assign uid_sig = {64{1'bx}};
		assign uid_valid_sig = 1'b0;
	end
endgenerate

generate
	if (MESSAGE_FEATURE == "ENABLE") begin
		assign mes_enable_sig = 1'b1;
		assign message_sig = message_reg;
		assign irq_readdata_sig = {31'b0, irq_reg};
		assign swi_irq_sig = irq_reg;
	end
	else begin
		assign mes_enable_sig = 1'b0;
		assign message_sig = {32{1'bx}};
		assign irq_readdata_sig = {32{1'bx}};
		assign swi_irq_sig = 1'b0;
	end
endgenerate

	assign bootsel_sig = ru_bootsel;

	assign avs_readdata =
			(avs_address == 3'd0)? CLASSID :
			(avs_address == 3'd1)? TIMECODE :
			(avs_address == 3'd2)? uid_sig[31:0] :
			(avs_address == 3'd3)? uid_sig[63:32] :
			(avs_address == 3'd4)? {16'b0, uid_valid_sig, uid_enable_sig, epcs_enable_sig, mes_enable_sig, bootsel_sig, 2'b0, rreq_reg, 4'b0, led_reg} :
			(avs_address == 3'd5)? spi_readdata_sig :
			(avs_address == 3'd6)? message_sig :
			(avs_address == 3'd7)? irq_readdata_sig :
			{32{1'bx}};

	assign ins_irq = swi_irq_sig | spi_irq_sig;
	assign coe_cpureset = rreq_reg;
	assign coe_led = led_reg;

	assign spi_write_sig = (avs_write && avs_address == 3'd5)? 1'b1 : 1'b0;

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			rreq_reg <= CPURESET_INIT[0];
			led_reg <= 4'b0000;
			irq_reg <= 1'b0;
		end
		else begin
			if (avs_write) begin
				case (avs_address)
				3'd4 : begin
					if (CPURESET_KEY[15:0] == 0 || avs_writedata[31:16] == CPURESET_KEY[15:0]) begin
						rreq_reg <= avs_writedata[8];
					end
					led_reg <= avs_writedata[3:0];
				end
				3'd6 : begin
					if (MESSAGE_FEATURE == "ENABLE") begin
						message_reg <= avs_writedata;
					end
				end
				3'd7 : begin
					if (MESSAGE_FEATURE == "ENABLE") begin
						irq_reg <= avs_writedata[0];
					end
				end
				endcase
			end
		end
	end


	///// ブート用SPI-Flashペリフェラル /////

generate
	if (EPCSBOOT_FEATURE == "ENABLE") begin
		assign epcs_enable_sig = 1'b1;

		peridot_csr_spi #(
			.DEFAULT_REG_BITRVS		(0),
			.DEFAULT_REG_MODE		(0),
			.DEFAULT_REG_CLKDIV		(SPI_REG_CLKDIV)
		)
		u0 (
			.csi_clk		(clock_sig),
			.rsi_reset		(reset_sig),
			.avs_address	(1'b0),
			.avs_read		(1'b1),
			.avs_readdata	(spi_readdata_sig),
			.avs_write		(spi_write_sig),
			.avs_writedata	(avs_writedata),
			.ins_irq		(spi_irq_sig),

			.spi_ss_n		(coe_cso_n),
			.spi_sclk		(coe_dclk),
			.spi_mosi		(coe_asdo),
			.spi_miso		(coe_data0)
		);
	end
	else begin
		assign epcs_enable_sig = 1'b0;
		assign spi_readdata_sig = {32{1'bx}};
		assign spi_irq_sig = 1'b0;
		assign coe_cso_n = 1'b1;
		assign coe_dclk = 1'b0;
		assign coe_asdo = 1'b0;
	end
endgenerate



endmodule
