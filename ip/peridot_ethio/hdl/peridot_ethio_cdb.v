// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / Clock Domain Bridge
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/07/01 -> 2022/08/05
//            : 2022/09/05 (FIXED)
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


// SDCに以下の3行を追加する 
//
// set_false_path -to [get_registers {*|peridot_ethio_cdb_areset:*|in_areset_reg[0]}]
// set_false_path -to [get_registers {*|peridot_ethio_cdb_signal:*|in_sig_reg[0]}]
// set_false_path -to [get_registers {*|peridot_ethio_cdb_vector:*|in_data_reg[*]}]



/* ===== クロックドメインブリッジの隠蔽スコープ ============== */

module peridot_ethio_cdb_areset (
	input wire			areset,
	input wire			clk,
	output wire			reset_out
);

	reg  [1:0]		in_areset_reg;

	always @(posedge clk) begin
		in_areset_reg <= {in_areset_reg[0], areset};
	end

	assign reset_out = areset | in_areset_reg[0] | in_areset_reg[1];

endmodule


module peridot_ethio_cdb_signal (
	input wire			reset,
	input wire			clk,
	input wire			in_sig,
	output wire			out_sig,
	output wire			riseedge,
	output wire			falledge
);

	reg [2:0]		in_sig_reg;

	always @(posedge clk or posedge reset) begin
		if (reset) in_sig_reg <= 3'b000;
		else in_sig_reg <= {in_sig_reg[1:0], in_sig};
	end

	assign out_sig = in_sig_reg[1];
	assign riseedge = (in_sig_reg[2:1] == 2'b01);
	assign falledge = (in_sig_reg[2:1] == 2'b10);

endmodule


module peridot_ethio_cdb_vector #(
	parameter DATA_BITWIDTH		= 8,
	parameter DATA_INITVALUE	= 0
) (
	input wire			reset,
	input wire			clk,
	input wire			latch,
	input wire  [DATA_BITWIDTH-1:0] in_data,
	output wire [DATA_BITWIDTH-1:0] out_data
);

	reg [DATA_BITWIDTH-1:0] in_data_reg;

	always @(posedge clk or posedge reset) begin
		if (reset) in_data_reg <= (DATA_INITVALUE)? DATA_INITVALUE[DATA_BITWIDTH-1:0] : 1'd0;
		else if (latch) in_data_reg <= in_data;
	end

	assign out_data = in_data_reg;

endmodule



/* ===== Avalon-STによる信号伝送 ============== */

module peridot_ethio_cdb_stream #(
	parameter USE_PORT_DATA		= "ON",			// in_data,out_dataポート("ON"=データ転送機能あり / "OFF"=なし)
	parameter DATA_BITWIDTH		= 8,			// データビット幅 
	parameter DATA_INITVALUE	= 0				// reset_b時の出力側初期値(テスト用)
) (
	input wire			reset_a,
	input wire			clk_a,
	output wire			in_ready,
	input wire			in_valid,
	input wire  [DATA_BITWIDTH-1:0] in_data,

	input wire			reset_b,
	input wire			clk_b,
	input wire			out_ready,
	output wire			out_valid,
	output wire [DATA_BITWIDTH-1:0] out_data
);

	reg				in_ready_reg, in_req_reg;
	wire			in_ack_sig;
	reg				out_valid_reg, out_ack_reg;
	wire			out_req_sig;


	peridot_ethio_cdb_signal
	u_cdb1 (
		.reset		(reset_a),
		.clk		(clk_a),
		.in_sig		(out_ack_reg),
		.out_sig	(in_ack_sig)
	);

	always @(posedge clk_a or posedge reset_a) begin
		if (reset_a) begin
			in_ready_reg <= 1'b0;
			in_req_reg <= 1'b0;
		end
		else begin
			if (!in_ready_reg) begin
				if (!in_req_reg && !in_ack_sig) begin
					in_ready_reg <= 1'b1;
				end
				else if (in_req_reg && in_ack_sig) begin
					in_req_reg <= 1'b0;
				end
			end
			else if (in_valid) begin
				in_ready_reg <= 1'b0;
				in_req_reg <= 1'b1;
			end
		end
	end

	assign in_ready = in_ready_reg;


	peridot_ethio_cdb_signal
	u_cdb2 (
		.reset		(reset_b),
		.clk		(clk_b),
		.in_sig		(in_req_reg),
		.out_sig	(out_req_sig)
	);

	always @(posedge clk_b or posedge reset_b) begin
		if (reset_b) begin
			out_valid_reg <= 1'b0;
			out_ack_reg <= 1'b0;
		end
		else begin
			if (!out_valid_reg) begin
				if (!out_ack_reg && out_req_sig) begin
					out_valid_reg <= 1'b1;
				end
				else if (out_ack_reg && !out_req_sig) begin
					out_ack_reg <= 1'b0;
				end
			end
			else if (out_ready) begin
				out_valid_reg <= 1'b0;
				out_ack_reg <= 1'b1;
			end
		end
	end

	assign out_valid = out_valid_reg;


generate
	if (USE_PORT_DATA == "ON") begin
		reg  [DATA_BITWIDTH-1:0] in_data_reg;

		always @(posedge clk_a) begin
			if (in_ready_reg && in_valid) in_data_reg <= in_data;
		end

		peridot_ethio_cdb_vector #(
			.DATA_BITWIDTH	(DATA_BITWIDTH),
			.DATA_INITVALUE	(DATA_INITVALUE)
		)
		u_cdb3 (
			.reset		(reset_b),
			.clk		(clk_b),
			.latch		(~out_valid_reg & ~out_ack_reg & out_req_sig),
			.in_data	(in_data_reg),
			.out_data	(out_data)
		);
	end
	else begin
		assign out_data = 1'd0;
	end
endgenerate

endmodule


/* ===== out側からの取得要求による信号伝送 ============== */

module peridot_ethio_cdb_get #(
	parameter USE_PORT_DATA		= "ON",			// in_data,out_dataポート("ON"=データ転送機能あり / "OFF"=なし)
	parameter DATA_BITWIDTH		= 8,			// データビット幅 
	parameter DATA_INITVALUE	= 0				// reset_b時の出力側初期値(テスト用)
) (
	input wire			reset_a,
	input wire			clk_a,
	output wire			in_ack,					// '1'のときにin_dataを取り込み 
	input wire  [DATA_BITWIDTH-1:0] in_data,

	input wire			reset_b,
	input wire			clk_b,
	input wire			get_req,				// '1'パルス入力でin_data信号取得をリクエスト
	output wire			out_ack,				// '1'のときにout_dataを更新 
	output wire [DATA_BITWIDTH-1:0] out_data
);

	reg				in_ack_reg;
	wire			in_ack_sig, in_riseedge_sig;
	reg				get_req_reg, out_req_reg;
	wire			out_ack_sig, out_risedge_sig;


	peridot_ethio_cdb_signal
	u_cdb1 (
		.reset		(reset_a),
		.clk		(clk_a),
		.in_sig		(out_req_reg),
		.out_sig	(in_ack_sig),
		.riseedge	(in_riseedge_sig)
	);

	always @(posedge clk_a or posedge reset_a) begin
		if (reset_a) begin
			in_ack_reg <= 1'b0;
		end
		else begin
			in_ack_reg <= in_ack_sig;
		end
	end

	assign in_ack = in_riseedge_sig;


	peridot_ethio_cdb_signal
	u_cdb2 (
		.reset		(reset_b),
		.clk		(clk_b),
		.in_sig		(in_ack_reg),
		.out_sig	(out_ack_sig),
		.riseedge	(out_risedge_sig)
	);

	always @(posedge clk_b or posedge reset_b) begin
		if (reset_b) begin
			get_req_reg <= 1'b0;
			out_req_reg <= 1'b0;
		end
		else begin
			get_req_reg <= get_req;

			if (out_req_reg) begin
				if (out_risedge_sig) begin
					out_req_reg <= 1'b0;
				end
			end
			else if (get_req && !get_req_reg) begin
				out_req_reg <= 1'b1;
			end
		end
	end

	assign out_ack = out_risedge_sig;


generate
	if (USE_PORT_DATA == "ON") begin
		reg  [DATA_BITWIDTH-1:0] in_data_reg;

		always @(posedge clk_a) begin
			if (in_riseedge_sig) in_data_reg <= in_data;
		end

		peridot_ethio_cdb_vector #(
			.DATA_BITWIDTH	(DATA_BITWIDTH),
			.DATA_INITVALUE	(DATA_INITVALUE)
		)
		u_cdb3 (
			.reset		(reset_b),
			.clk		(clk_b),
			.latch		(out_risedge_sig),
			.in_data	(in_data_reg),
			.out_data	(out_data)
		);
	end
	else begin
		assign out_data = 1'd0;
	end
endgenerate

endmodule



/* ===== ハンドシェークによる信号伝送 ============== */

module peridot_ethio_cdb_handshake  #(
	parameter USE_PORT_OUTACK	= "ON",			// out_ack入力ポート("ON"=有効 / "OFF"=内部折り返し)
	parameter USE_PORT_DATA		= "ON",			// in_data,out_dataポート("ON"=データ転送機能あり / "OFF"=なし)
	parameter DATA_BITWIDTH		= 8,			// データビット幅 
	parameter DATA_INITVALUE	= 0				// リセット時初期値(テスト用)
) (
	input wire			reset_a,
	input wire			clk_a,
	input wire			in_req,
	output wire			in_ack,

	input wire			reset_b,
	input wire			clk_b,
	output wire			out_req,
	input wire			out_ack,				// USE_PORT_OUTACK="ON"のときに入力有効 
	output wire			out_riseedge,			// out_req信号の↑エッジ検出 
	output wire			out_falledge,			// out_req信号の↓エッジ検出 

	input wire  [DATA_BITWIDTH-1:0] in_data,	// in_dataはin_reqの↑エッジでラッチ 
	output wire [DATA_BITWIDTH-1:0] out_data	// out_dataはout_reqの↑エッジでラッチ 
);

	reg				in_req_reg;
	wire			out_req_sig, out_ack_sig, out_riseedge_sig;

	always @(posedge clk_a or posedge reset_a) begin
		if (reset_a) in_req_reg <= 1'b0;
		else in_req_reg <= in_req;
	end

	peridot_ethio_cdb_signal
	u_cdb1 (
		.reset		(reset_a),
		.clk		(clk_a),
		.in_sig		(out_ack_sig),
		.out_sig	(in_ack)
	);

generate
	if (USE_PORT_OUTACK == "ON") begin
		reg				out_ack_reg;

		always @(posedge clk_b or posedge reset_b) begin
			if (reset_b) out_ack_reg <= 1'b0;
			else out_ack_reg <= out_ack;
		end

		assign out_ack_sig = out_ack_reg;
	end
	else begin
		assign out_ack_sig = out_req_sig;
	end
endgenerate

	peridot_ethio_cdb_signal
	u_cdb2 (
		.reset		(reset_b),
		.clk		(clk_b),
		.in_sig		(in_req_reg),
		.out_sig	(out_req_sig),
		.riseedge	(out_riseedge_sig),
		.falledge	(out_falledge)
	);

	assign out_req = out_req_sig;
	assign out_riseedge = out_riseedge_sig;

generate
	if (USE_PORT_DATA == "ON") begin
		reg  [DATA_BITWIDTH-1:0] in_data_reg;

		always @(posedge clk_a) begin
			if (in_req && !in_req_reg) in_data_reg <= in_data;
		end

		peridot_ethio_cdb_vector #(
			.DATA_BITWIDTH	(DATA_BITWIDTH),
			.DATA_INITVALUE	(DATA_INITVALUE)
		)
		u_cdb3 (
			.reset		(reset_b),
			.clk		(clk_b),
			.latch		(out_riseedge_sig),
			.in_data	(in_data_reg),
			.out_data	(out_data)
		);
	end
	else begin
		assign out_data = 1'd0;
	end
endgenerate


endmodule

`default_nettype wire
