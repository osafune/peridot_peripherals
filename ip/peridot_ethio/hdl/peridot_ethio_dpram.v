// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / True Dual Port RAM
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/07/01 -> 2022/07/30
//            : 2022/09/08 (FIXED)
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

module peridot_ethio_dpram #(
	parameter RAM_NUMWORD_BITWIDTH	= 14,		// メモリのワード数 = 2^RAM_NUMWORD_BITWIDTH (8～14)
	parameter RAM_READOUT_REGISTER	= "ON"		// 読み出しレジスタの有無 "ON"=あり / "OFF"=なし
) (
	input wire			clk_a,
	input wire			clkena_a,
	input wire  [RAM_NUMWORD_BITWIDTH-1:0]	address_a,
	input wire  [7:0]	writedata_a,
	input wire			writeenable_a,
	output wire [7:0]	readdata_a,			// RAM_READOUT_REGISTER : "ON"=registered / "OFF"=unregisterd

	input wire			clk_b,
	input wire			clkena_b,
	input wire  [RAM_NUMWORD_BITWIDTH-1:0]	address_b,
	input wire  [7:0]	writedata_b,
	input wire  		writeenable_b,
	output wire [7:0]	readdata_b			// RAM_READOUT_REGISTER : "ON"=registered / "OFF"=unregisterd
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

// Vivado用インスタンスをするオプション 
//`define GENERATE_VIVADO_XPM

// GowinEDA用インスタンスをするオプション 
//`define GENERATE_GOWINEDA


/* ===== モジュール構造記述 ============== */

	// QuartusPrime用インスタンス (Cyclone III/IV/V/10LP, MAX10)

`ifdef GENERATE_VIVADO_XPM
`elsif GENERATE_GOWINEDA
`else
	localparam DPRAM_OUTDATA_REG_A	= (RAM_READOUT_REGISTER == "ON")? "CLOCK0" : "UNREGISTERED";
	localparam DPRAM_OUTDATA_REG_B	= (RAM_READOUT_REGISTER == "ON")? "CLOCK1" : "UNREGISTERED";

	localparam DPRAM_ENA_OUTPUT_A	= (RAM_READOUT_REGISTER == "ON")? "NORMAL" : "BYPASS";
	localparam DPRAM_ENA_OUTPUT_B	= (RAM_READOUT_REGISTER == "ON")? "NORMAL" : "BYPASS";

	altsyncram #(
		.lpm_type				("altsyncram"),
		.operation_mode			("BIDIR_DUAL_PORT"),
		.width_a				(8),
		.widthad_a				(RAM_NUMWORD_BITWIDTH),
		.numwords_a				(2**RAM_NUMWORD_BITWIDTH),
		.outdata_reg_a			(DPRAM_OUTDATA_REG_A),
		.clock_enable_input_a	("NORMAL"),
		.clock_enable_output_a	(DPRAM_ENA_OUTPUT_A),
		.width_b				(8),
		.widthad_b				(RAM_NUMWORD_BITWIDTH),
		.numwords_b				(2**RAM_NUMWORD_BITWIDTH),
		.outdata_reg_b			(DPRAM_OUTDATA_REG_B),
		.clock_enable_input_b	("NORMAL"),
		.clock_enable_output_b	(DPRAM_ENA_OUTPUT_B),
		.address_reg_b			("CLOCK1"),
		.indata_reg_b			("CLOCK1"),
		.wrcontrol_wraddress_reg_b ("CLOCK1")
	)
	u_dpram (
		.clock0			(clk_a),
		.clocken0		(clkena_a),
		.address_a		(address_a),
		.data_a			(writedata_a),
		.wren_a			(writeenable_a),
		.q_a			(readdata_a),

		.clock1			(clk_b),
		.clocken1		(clkena_b),
		.address_b		(address_b),
		.data_b			(writedata_b),
		.wren_b			(writeenable_b),
		.q_b			(readdata_b)
	);
`endif


	// Vivado用インスタンス (Vivado XPM support)

`ifdef GENERATE_VIVADO_XPM
	localparam DPRAM_READ_LATENCY	= (RAM_READOUT_REGISTER == "ON")? 2 : 1;

	xpm_memory_tdpram #(
		.ADDR_WIDTH_A		(RAM_NUMWORD_BITWIDTH),
		.ADDR_WIDTH_B		(RAM_NUMWORD_BITWIDTH),
		.BYTE_WRITE_WIDTH_A	(8),
		.BYTE_WRITE_WIDTH_B	(8),
		.CLOCKING_MODE		("independent_clock"),
		.MEMORY_SIZE		(2**(RAM_NUMWORD_BITWIDTH+3)),
		.READ_DATA_WIDTH_A	(8),
		.READ_DATA_WIDTH_B	(8),
		.READ_LATENCY_A		(DPRAM_READ_LATENCY),
		.READ_LATENCY_B		(DPRAM_READ_LATENCY),
		.WRITE_DATA_WIDTH_A	(8),
		.WRITE_DATA_WIDTH_B	(8)
	)
	u_dpram (
		.clka			(clk_a),
		.ena			(clkena_a),
		.addra			(address_a),
		.dina			(writedata_a),
		.wea			({writeenable_a}),
		.douta			(readdata_a),

		.clkb			(clk_b),
		.enb			(clkena_b),
		.addrb			(address_b),
		.dinb			(writedata_b),
		.web			({writeenable_b}),
		.doutb			(readdata_b),

		.rsta			(1'b0),
		.rstb			(1'b0),
		.regcea			(1'b1),
		.regceb			(1'b1),
		.injectdbiterra	(1'b0),
		.injectdbiterrb	(1'b0),
		.injectsbiterra	(1'b0),
		.injectsbiterrb	(1'b0),
		.sleep			(1'b0)
	);
`endif


	// GowinEDA用インスタンス (GW1N)

`ifdef GENERATE_GOWINEDA
	localparam DPRAM_BITWIDTH =	(RAM_NUMWORD_BITWIDTH >= 14)? 1 :
								(RAM_NUMWORD_BITWIDTH == 13)? 2 :
								(RAM_NUMWORD_BITWIDTH == 12)? 4 :
								8;
	localparam DPRAM_ADDRBIT =	(RAM_NUMWORD_BITWIDTH >= 14)? 16 :
								(RAM_NUMWORD_BITWIDTH == 13)? 15 :
								(RAM_NUMWORD_BITWIDTH == 12)? 14 :
								13;
	localparam DPRAM_INSTNUM = 	8 / DPRAM_BITWIDTH;
	localparam DPRAM_READ_MODE = (RAM_READOUT_REGISTER == "ON")? 1'b1 : 1'b0;

	wire [16:0]		address_a_sig = {address_a, 3'b000};
	wire [16:0]		address_b_sig = {address_b, 3'b000};

	wire [15:0]		readdata_a_sig[DPRAM_INSTNUM-1:0];
	wire [15:0]		readdata_b_sig[DPRAM_INSTNUM-1:0];
	wire [15:0]		writedata_a_sig[DPRAM_INSTNUM-1:0];
	wire [15:0]		writedata_b_sig[DPRAM_INSTNUM-1:0];

	genvar	i;

	generate
	for(i=0 ; i<DPRAM_INSTNUM ; i=i+1) begin : u_dpram

		assign writedata_a_sig[i] = {{(16-DPRAM_BITWIDTH){1'b0}}, writedata_a[(i+1)*DPRAM_BITWIDTH-1 -: DPRAM_BITWIDTH]};
		assign writedata_b_sig[i] = {{(16-DPRAM_BITWIDTH){1'b0}}, writedata_b[(i+1)*DPRAM_BITWIDTH-1 -: DPRAM_BITWIDTH]};
		assign readdata_a[(i+1)*DPRAM_BITWIDTH-1 -: DPRAM_BITWIDTH] = readdata_a_sig[i][DPRAM_BITWIDTH-1:0];
		assign readdata_b[(i+1)*DPRAM_BITWIDTH-1 -: DPRAM_BITWIDTH] = readdata_b_sig[i][DPRAM_BITWIDTH-1:0];

		DPB #(
			.BIT_WIDTH_0	(DPRAM_BITWIDTH),
			.BIT_WIDTH_1	(DPRAM_BITWIDTH),
			.READ_MODE0		(DPRAM_READ_MODE),
			.READ_MODE1		(DPRAM_READ_MODE),
			.WRITE_MODE0	(2'b00),	// normal
			.WRITE_MODE1	(2'b00),	// normal
			.BLK_SEL_0		(3'b000),
			.BLK_SEL_1		(3'b000),
			.RESET_MODE		("SYNC")
		)
		u (
			.CLKA		(clk_a),
			.CEA		(clkena_a),
			.OCEA		(clkena_a),
			.ADA		(address_a_sig[DPRAM_ADDRBIT -: 14]),
			.DIA		(writedata_a_sig[i]),
			.WREA		(writeenable_a),
			.DOA		(readdata_a_sig[i]),

			.CLKB		(clk_b),
			.CEB		(clkena_b),
			.OCEB		(clkena_b),
			.ADB		(address_b_sig[DPRAM_ADDRBIT -: 14]),
			.DIB		(writedata_b_sig[i]),
			.WREB		(writeenable_b),
			.DOB		(readdata_b_sig[i]),

			.RESETA		(1'b0),
			.RESETB		(1'b0),
			.BLKSELA	(3'b000),
			.BLKSELB	(3'b000)
		);
	end
	endgenerate
`endif



endmodule

`default_nettype wire
