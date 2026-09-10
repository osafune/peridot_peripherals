// ===================================================================
// TITLE : PERIDOT ESN - True dual clock / dual port RAM
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2026/03/12 -> 2026/03/14
//            : 2026/06/09 (FIXED)
//
// ===================================================================
//
// The MIT License (MIT)
// Copyright (c) 2026 J-7SYSTEM WORKS LIMITED.
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

module peridot_esn_dcdpram #(
	parameter RAM_NUMWORD_BITWIDTH = 12,			// メモリのワード数 = 2^RAM_NUMWORD_BITWIDTH (10～14)
	parameter USE_READDATA_B_OUTPUT_REG = "OFF",	// ポートb側の出力レジスタの有無("ON"=readdata_bの出力レジスタを使う)

	// SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone 10 GX" "Cyclone V" "Cyclone IV E" "Cyclone IV GX"}
	parameter DEVICE_FAMILY = "Cyclone III"
) (
	input wire			clk_a,
	input wire  [RAM_NUMWORD_BITWIDTH-1:0]	address_a,
	input wire  [17:0]	writedata_a,
	input wire			writeenable_a,
	output wire [17:0]	readdata_a,

	input wire			clk_b,
	input wire  [RAM_NUMWORD_BITWIDTH-1:0]	address_b,
	input wire  [17:0]	writedata_b,
	input wire  		writeenable_b,
	output wire [17:0]	readdata_b
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */



/* ===== モジュール構造記述 ============== */

generate if (RAM_NUMWORD_BITWIDTH == 11) begin

	// 2048ワードの場合は36bit×1024構成をインスタンス

	wire [3:0]		byteena_a_sig, byteena_b_sig;
	wire [35:0]		q_a_sig, q_b_sig;
	wire [17:0]		readdata_a_sig, readdata_b_sig;
	reg				readsel_a_reg, readsel_b_reg;
	reg  [17:0]		readdata_a_reg, readdata_b_reg;

	assign byteena_a_sig  = (address_a[0])? 4'b1100 : 4'b0011;
	assign readdata_a_sig = (readsel_a_reg)? q_a_sig[35:18] : q_a_sig[17:0];

	always @(posedge clk_a) begin
		readsel_a_reg <= address_a[0];
		readdata_a_reg <= readdata_a_sig;
	end
	assign readdata_a = readdata_a_reg;

	assign byteena_b_sig  = (address_b[0])? 4'b1100 : 4'b0011;
	assign readdata_b_sig = (readsel_b_reg)? q_b_sig[35:18] : q_b_sig[17:0];

	always @(posedge clk_b) begin
		readsel_b_reg <= address_b[0];
		readdata_b_reg <= readdata_b_sig;
	end
	assign readdata_b = (USE_READDATA_B_OUTPUT_REG == "ON")? readdata_b_reg : readdata_b_sig;

	altsyncram #(
		.lpm_type				("altsyncram"),
		.operation_mode			("BIDIR_DUAL_PORT"),
		.intended_device_family	(DEVICE_FAMILY),
		.byte_size				(9),
		.width_a				(36),
		.widthad_a				(10),
		.numwords_a				(1024),
		.width_byteena_a		(4),
		.clock_enable_input_a	("BYPASS"),
		.clock_enable_output_a	("BYPASS"),
		.outdata_reg_a			("UNREGISTERED"),
		.read_during_write_mode_port_a ("OLD_DATA"),
		.width_b				(36),
		.widthad_b				(10),
		.numwords_b				(1024),
		.width_byteena_b		(4),
		.clock_enable_input_b	("BYPASS"),
		.clock_enable_output_b	("BYPASS"),
		.address_reg_b			("CLOCK1"),
		.byteena_reg_b			("CLOCK1"),
		.indata_reg_b			("CLOCK1"),
		.outdata_reg_b			("UNREGISTERED"),
		.wrcontrol_wraddress_reg_b ("CLOCK1"),
		.read_during_write_mode_port_b ("OLD_DATA"),
		.power_up_uninitialized	("FALSE")
	)
	u_dpram36 (
		.clock0		(clk_a),
		.address_a	(address_a[10:1]),
		.byteena_a	(byteena_a_sig),
		.data_a		({writedata_a, writedata_a}),
		.wren_a		(writeenable_a),
		.q_a		(q_a_sig),

		.clock1		(clk_b),
		.address_b	(address_b[10:1]),
		.byteena_b	(byteena_b_sig),
		.data_b		({writedata_b, writedata_b}),
		.wren_b		(writeenable_b),
		.q_b		(q_b_sig)
	);
end
else if (RAM_NUMWORD_BITWIDTH == 12) begin

	// 4096ワードの場合は72bit×1024構成をインスタンス

	wire [7:0]		byteena_a_sig, byteena_b_sig;
	wire [71:0]		q_a_sig, q_b_sig;
	wire [17:0]		readdata_a_sig, readdata_b_sig;
	reg  [1:0]		readsel_a_reg, readsel_b_reg;
	reg  [17:0]		readdata_a_reg, readdata_b_reg;

	assign byteena_a_sig =
				(address_a[1:0] == 2'd3)? 8'b11000000 :
				(address_a[1:0] == 2'd2)? 8'b00110000 :
				(address_a[1:0] == 2'd1)? 8'b00001100 :
				8'b00000011;

	assign readdata_a_sig =
				(readsel_a_reg == 2'd3)? q_a_sig[71:54] :
				(readsel_a_reg == 2'd2)? q_a_sig[53:36] :
				(readsel_a_reg == 2'd1)? q_a_sig[35:18] :
				q_a_sig[17:0];

	always @(posedge clk_a) begin
		readsel_a_reg <= address_a[1:0];
		readdata_a_reg <= readdata_a_sig;
	end
	assign readdata_a = readdata_a_reg;

	assign byteena_b_sig =
				(address_b[1:0] == 2'd3)? 8'b11000000 :
				(address_b[1:0] == 2'd2)? 8'b00110000 :
				(address_b[1:0] == 2'd1)? 8'b00001100 :
				8'b00000011;

	assign readdata_b_sig =
				(readsel_b_reg == 2'd3)? q_b_sig[71:54] :
				(readsel_b_reg == 2'd2)? q_b_sig[53:36] :
				(readsel_b_reg == 2'd1)? q_b_sig[35:18] :
				q_b_sig[17:0];

	always @(posedge clk_b) begin
		readsel_b_reg <= address_b[1:0];
		readdata_b_reg <= readdata_b_sig;
	end
	assign readdata_b = (USE_READDATA_B_OUTPUT_REG == "ON")? readdata_b_reg : readdata_b_sig;

	altsyncram #(
		.lpm_type				("altsyncram"),
		.operation_mode			("BIDIR_DUAL_PORT"),
		.intended_device_family	(DEVICE_FAMILY),
		.byte_size				(9),
		.width_a				(72),
		.widthad_a				(10),
		.numwords_a				(1024),
		.width_byteena_a		(8),
		.clock_enable_input_a	("BYPASS"),
		.clock_enable_output_a	("BYPASS"),
		.outdata_reg_a			("UNREGISTERED"),
		.read_during_write_mode_port_a ("OLD_DATA"),
		.width_b				(72),
		.widthad_b				(10),
		.numwords_b				(1024),
		.width_byteena_b		(8),
		.clock_enable_input_b	("BYPASS"),
		.clock_enable_output_b	("BYPASS"),
		.address_reg_b			("CLOCK1"),
		.byteena_reg_b			("CLOCK1"),
		.indata_reg_b			("CLOCK1"),
		.outdata_reg_b			("UNREGISTERED"),
		.wrcontrol_wraddress_reg_b ("CLOCK1"),
		.read_during_write_mode_port_b ("OLD_DATA"),
		.power_up_uninitialized	("FALSE")
	)
	u_dpram72 (
		.clock0		(clk_a),
		.address_a	(address_a[11:2]),
		.byteena_a	(byteena_a_sig),
		.data_a		({writedata_a, writedata_a, writedata_a, writedata_a}),
		.wren_a		(writeenable_a),
		.q_a		(q_a_sig),

		.clock1		(clk_b),
		.address_b	(address_b[11:2]),
		.byteena_b	(byteena_b_sig),
		.data_b		({writedata_b, writedata_b, writedata_b, writedata_b}),
		.wren_b		(writeenable_b),
		.q_b		(q_b_sig)
	);
end
else begin

	// それ以外の場合は18bit幅の構成をインスタンス

	altsyncram #(
		.lpm_type				("altsyncram"),
		.operation_mode			("BIDIR_DUAL_PORT"),
		.intended_device_family	(DEVICE_FAMILY),
		.width_a				(18),
		.widthad_a				(RAM_NUMWORD_BITWIDTH),
		.numwords_a				(2**RAM_NUMWORD_BITWIDTH),
		.clock_enable_input_a	("BYPASS"),
		.clock_enable_output_a	("BYPASS"),
		.outdata_reg_a			("CLOCK0"),
		.read_during_write_mode_port_a ("OLD_DATA"),
		.width_b				(18),
		.widthad_b				(RAM_NUMWORD_BITWIDTH),
		.numwords_b				(2**RAM_NUMWORD_BITWIDTH),
		.clock_enable_input_b	("BYPASS"),
		.clock_enable_output_b	("BYPASS"),
		.address_reg_b			("CLOCK1"),
		.indata_reg_b			("CLOCK1"),
		.outdata_reg_b			((USE_READDATA_B_OUTPUT_REG == "ON")? "CLOCK1" : "UNREGISTERED"),
		.wrcontrol_wraddress_reg_b ("CLOCK1"),
		.read_during_write_mode_port_b ("OLD_DATA"),
		.power_up_uninitialized	("FALSE")
	)
	u_dpram18 (
		.clock0		(clk_a),
		.address_a	(address_a),
		.data_a		(writedata_a),
		.wren_a		(writeenable_a),
		.q_a		(readdata_a),

		.clock1		(clk_b),
		.address_b	(address_b),
		.data_b		(writedata_b),
		.wren_b		(writeenable_b),
		.q_b		(readdata_b)
	);
end
endgenerate

endmodule

`default_nettype wire
