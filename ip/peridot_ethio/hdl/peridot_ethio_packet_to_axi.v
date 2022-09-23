// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / Packet to AXI4-Lite Host
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/09/18 -> 2022/09/18
//            : 2022/09/18 (FIXED)
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

module peridot_ethio_packet_to_axi (
	input wire			reset,
	input wire			clk,

	// Avmm arbiter
	output wire			in_ready,
	input wire			in_valid,
	input wire  [7:0]	in_data,
	input wire			in_sop,
	input wire			in_eop,

	input wire			out_ready,
	output wire			out_valid,
	output wire [7:0]	out_data,
	output wire			out_sop,
	output wire			out_eop,

	// Interface: AXI4-Lite Host
	input wire			axm_awready,
	output wire			axm_awvalid,
	output wire [31:0]	axm_awaddr,
	input wire			axm_wready,
	output wire			axm_wvalid,
	output wire [31:0]	axm_wdata,
	output wire [3:0]	axm_wstrb,
	output wire			axm_bready,
	input wire			axm_bvalid,

	input wire			axm_arready,
	output wire			axm_arvalid,
	output wire [31:0]	axm_araddr,
	output wire			axm_rready,
	input wire			axm_rvalid,
	input wire  [31:0]	axm_rdata
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam CMD_WRITE		= 8'h00;
	localparam CMD_WRITE_INCR	= 8'h04;
	localparam CMD_READ			= 8'h10;
	localparam CMD_READ_INCR	= 8'h14;

	localparam	STATE_IDLE			= 5'd0,
				STATE_GET_EXTRA		= 5'd1,
				STATE_GET_SIZE1		= 5'd2,
				STATE_GET_SIZE2		= 5'd3,
				STATE_GET_ADDR1		= 5'd4,
				STATE_GET_ADDR2		= 5'd5,
				STATE_GET_ADDR3		= 5'd6,
				STATE_GET_ADDR4		= 5'd7,
				STATE_GET_DATA		= 5'd8,
				STATE_WRITE_WAIT	= 5'd9,
				STATE_SEND_RESP		= 5'd10,
				STATE_READ_ASSERT	= 5'd11,
				STATE_READ_WAIT		= 5'd12,
				STATE_READ_RESP		= 5'd13,
				STATE_READ_SEND		= 5'd14;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 
	wire			clock_sig = clk;		// モジュール内部駆動クロック 

	reg  [4:0]		state_reg;
	reg				ready_reg;
	reg				first_reg;
	reg				last_reg;
	reg  [7:0]		command_reg;
	reg  [15:0]		datalen_reg;
	reg  [1:0]		current_byte_reg;
	wire			enable_sig;
	wire			cmd_read_sig;
	wire			addr_inc_sig;

	reg  [31:2]		addr_reg;
	reg				write_req_reg;
	reg  [31:0]		writedata_reg;
	reg  [3:0]		byteenable_reg;
	reg				read_req_reg;
	reg  [31:8]		readdata_reg;

	reg				awvalid_reg;
	reg				wvalid_reg;
	reg				arvalid_reg;

	reg				out_valid_reg, out_sop_reg, out_eop_reg;
	reg  [7:0]		out_data_reg;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	// ポート信号接続 

	assign in_ready = ready_reg;

	assign out_valid = out_valid_reg;
	assign out_data = out_data_reg;
	assign out_sop = out_sop_reg;
	assign out_eop = out_eop_reg;

	assign axm_awvalid = awvalid_reg;
	assign axm_awaddr = {addr_reg, 2'b00};
	assign axm_wvalid = wvalid_reg;
	assign axm_wdata = writedata_reg;
	assign axm_wstrb = byteenable_reg;
	assign axm_bready = write_req_reg;

	assign axm_arvalid = arvalid_reg;
	assign axm_araddr = {addr_reg, 2'b00};
	assign axm_rready = read_req_reg;


	// メインステートマシン 

	assign enable_sig = (ready_reg && in_valid);
	assign cmd_read_sig = command_reg[4];
	assign addr_inc_sig = command_reg[2];

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			state_reg <= STATE_IDLE;
			ready_reg <= 1'b0;
		end
		else begin
			// AXIチャネルvalidクリア 
			if (awvalid_reg && axm_awready) awvalid_reg <= 1'b0;
			if (wvalid_reg && axm_wready) wvalid_reg <= 1'b0;
			if (arvalid_reg && axm_arready) arvalid_reg <= 1'b0;


			// AvMMトランザクション処理 
			if (enable_sig && in_sop) begin
				state_reg <= STATE_GET_EXTRA;
				ready_reg <= 1'b1;
				command_reg <= in_data;
			end
			else begin
				case (state_reg)

				STATE_IDLE : begin
					ready_reg <= 1'b1;
				end

				// コマンド拡張部 
				STATE_GET_EXTRA : begin
					if (enable_sig) begin
						state_reg <= STATE_GET_SIZE1;
					end
				end

				// サイズフィールド 
				STATE_GET_SIZE1 : begin
					datalen_reg[15:8] <= (cmd_read_sig)? in_data : 1'd0;
					if (enable_sig) state_reg <= STATE_GET_SIZE2;
				end
				STATE_GET_SIZE2 : begin
					datalen_reg[7:0] <= (cmd_read_sig)? in_data : 1'd0;
					if (enable_sig) state_reg <= STATE_GET_ADDR1;
				end

				// アドレスフィールド 
				STATE_GET_ADDR1 : begin
					first_reg <= 1'b1;
					last_reg <= 1'b0;
					addr_reg[31:24] <= in_data;
					if (enable_sig) state_reg <= STATE_GET_ADDR2;
				end
				STATE_GET_ADDR2 : begin
					addr_reg[23:16] <= in_data;
					if (enable_sig) state_reg <= STATE_GET_ADDR3;
				end
				STATE_GET_ADDR3 : begin
					addr_reg[15:8] <= in_data;
					if (enable_sig) state_reg <= STATE_GET_ADDR4;
				end
				STATE_GET_ADDR4 : begin
					addr_reg[7:2] <= in_data[7:2];
					current_byte_reg <= in_data[1:0];

					if (enable_sig) begin
						if (command_reg == CMD_WRITE || command_reg == CMD_WRITE_INCR) begin
							state_reg <= STATE_GET_DATA;
						end
						else if (command_reg == CMD_READ || command_reg == CMD_READ_INCR) begin
							state_reg <= STATE_READ_ASSERT;
							ready_reg <= 1'b0;
						end
						else begin
							state_reg <= STATE_SEND_RESP;
							ready_reg <= 1'b0;
							current_byte_reg <= 1'd0;
							out_valid_reg <= 1'b1;
							out_data_reg <= command_reg | 8'h80;
							out_sop_reg <= 1'b1;
						end
					end
				end

				// データ書き込み 
				STATE_GET_DATA : begin
					if (in_eop) last_reg = 1'b1;

					if (enable_sig) begin
						datalen_reg <= datalen_reg + 1'd1;
						current_byte_reg <= current_byte_reg + 1'd1;

						if (in_eop || current_byte_reg == 2'd3) begin
							state_reg <= STATE_WRITE_WAIT;
							ready_reg <= 1'b0;
							write_req_reg <= 1'b1;
							awvalid_reg <= 1'b1;
							wvalid_reg <= 1'b1;
						end
					end

					case (current_byte_reg)
					2'd3 : begin
						writedata_reg[31:24] <= in_data;
						byteenable_reg[3] <= 1'b1;
					end
					2'd2 : begin
						writedata_reg[23:16] <= in_data;
						byteenable_reg[2] <= 1'b1;
					end
					2'd1 : begin
						writedata_reg[15:8] <= in_data;
						byteenable_reg[1] <= 1'b1;
					end
					default : begin
						writedata_reg[7:0] <= in_data;
						byteenable_reg[0] <= 1'b1;
					end
					endcase
				end
				STATE_WRITE_WAIT : begin
					if (axm_bvalid) begin
						write_req_reg <= 1'b0;
						byteenable_reg <= 4'b0000;
						addr_reg[31:2] <= addr_reg[31:2] + addr_inc_sig;

						if (last_reg) begin
							state_reg <= STATE_SEND_RESP;
							ready_reg <= 1'b0;
							current_byte_reg <= 1'd0;
							out_valid_reg <= 1'b1;
							out_data_reg <= command_reg | 8'h80;
							out_sop_reg <= 1'b1;
						end
						else begin
							state_reg <= STATE_GET_DATA;
							ready_reg <= 1'b1;
						end
					end
				end

				// 書き込み・不定コマンド応答 
				STATE_SEND_RESP : begin
					if (out_ready) begin
						current_byte_reg <= current_byte_reg + 1'd1;
						out_sop_reg <= 1'b0;

						if (current_byte_reg == 2'd3) begin
							state_reg <= STATE_IDLE;
							out_valid_reg <= 1'b0;
						end

						if (out_eop_reg) begin
							out_eop_reg <= 1'b0;
						end
						else if (current_byte_reg == 2'd2) begin
							out_eop_reg <= 1'b1;
						end

						case (current_byte_reg)
						2'd1 : out_data_reg <= datalen_reg[15:8];
						2'd2 : out_data_reg <= datalen_reg[7:0];
						default : out_data_reg <= 8'h00;
						endcase
					end
				end

				// データ読み出し 
				STATE_READ_ASSERT : begin
					state_reg <= STATE_READ_WAIT;
					read_req_reg <= 1'b1;
					arvalid_reg <= 1'b1;
				end
				STATE_READ_WAIT : begin
					readdata_reg <= axm_rdata[31:8];
					out_data_reg <= axm_rdata[7:0];

					if (axm_rvalid) begin
						state_reg <= STATE_READ_RESP;
						read_req_reg <= 1'b0;
					end
				end
				STATE_READ_RESP : begin
					state_reg <= STATE_READ_SEND;
					out_valid_reg <= 1'b1;
					out_sop_reg <= first_reg;
					out_eop_reg <= (datalen_reg == 16'd1);
					first_reg <= 1'b0;

					case (current_byte_reg)
					2'd3 : out_data_reg <= readdata_reg[31:24];
					2'd2 : out_data_reg <= readdata_reg[23:16];
					2'd1 : out_data_reg <= readdata_reg[15:8];
					endcase
				end
				STATE_READ_SEND : begin
					if (out_ready) begin
						datalen_reg <= datalen_reg - 1'd1;
						current_byte_reg <= current_byte_reg + 1'd1;
						out_valid_reg <= 1'b0;
						out_sop_reg <= 1'b0;
						out_eop_reg <= 1'b0;

						if (datalen_reg == 16'd1) begin
							state_reg <= STATE_IDLE;
						end
						else if (current_byte_reg == 2'd3) begin
							state_reg <= STATE_READ_ASSERT;
							addr_reg[31:2] <= addr_reg[31:2] + addr_inc_sig;
						end
						else begin
							state_reg <= STATE_READ_RESP;
						end
					end
				end
				endcase
			end

		end
	end



endmodule

`default_nettype wire
