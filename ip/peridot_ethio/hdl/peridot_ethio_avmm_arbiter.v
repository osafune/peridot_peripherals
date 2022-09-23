// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / Packet stream arbiter
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/09/01 -> 2022/09/18
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

// [パケット構造]
// ・1つのペイロードヘッダ、複数のコマンドパケット、1つのエンドパケットで構成。 
// ・コマンドはネットワークバイトオーダー、データペイロードはバイトアドレス順で格納する。 
//
// [コマンドパケット]
// ・ヘッダ部＋データ部で構成され、コマンドパケット長は常に4バイト単位。 
// ・ヘッダ部は1バイトのコマンドフィールド、1バイトのパティング、2バイトのサイズフィールドで構成。 
// ・データ部はシングルライト、バーストライト、FIFOストアにのみ存在する。 
// ・データ部が4nバイト未満ならば、残りの1～3バイトは0x00でパティングする。 
// ・コマンドは以下の7種類
//     0x40 : シングルライト。データ部は1,2,4バイト。非アライメントアドレスは指定禁止。 
//     0x44 : バーストライト。データ部は1～32768バイト。 
//     0x50 : シングルリード。リクエスト可能データ長は1,2,4バイト。非アライメントアドレスは指定禁止。 
//     0x54 : バーストリード。リクエスト可能データ長は1～32768バイト。 
//     0x2x : FIFOストア。下位4bitでストア先FIFOを指定。データ部は1～32768バイト。 
//     0x3x : FIFOロード。下位4bitでロード元FIFOを指定。リクエスト可能データ長は1～32768バイト。 
//     0x7f : エンドコマンド。パケットの最後に必要。
//
//         0     1     2     3
//      +-----+-----+-----+-----+
// +0   | 'A' | 'V' | 'M' | 'M' | -- ペイロードヘッダ(FOURCC)
//      |-----+-----+-----------|
// +4   | CMD | 0x00|   SIZE    | -+
//      |-----+-----+-----------|  |
// +8   |        ADDRESS        |  | コマンドパケット1
//      |-----+-----+-----+-----|  |
// +12  |  D0 |  D1 |  D2 |  D3 |  |
//      |-----+-----+-----+-----|  |
// +16  |  D4 |   ‥‥          | -+
//      |-----+-----+-----+-----|
//  :
//  :
//      |-----+-----+-----+-----|
// +20  | CMD | 0x00|   SIZE    | -+
//      |-----+-----+-----------|  |
// +24  |        ADDRESS        |  | コマンドパケット2
//      |-----+-----+-----+-----|  |
// +28  |  D0 |   ‥‥          | -+
//      |-----+-----+-----+-----|
//  :
//  :
//      |-----+-----+-----+-----|
// 4m+0 | 0x7f| 0x00| 0xff| 0xff| -- エンドパケット(エンドコマンドパケット)
//      +-----+-----+-----+-----+
//

// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_ethio_avmm_arbiter #(
	parameter SUPPORT_AVALONMM_CMD	= 1,	// 1=Avalon-MM Hostコマンドを処理する 
	parameter SUPPORT_AVALONST_CMD	= 1,	// 1=Avalon-ST Src/Sinkコマンドを処理する 
	parameter ENABLE_AVALONMM_HOST	= 1,	// 1=Avalon-MM Hostポートを使う (SUPPORT_AVALONMM_CMD=1の場合のみ)
	parameter ENABLE_AVALONST_SRC	= 1,	// 1=Avalon-ST Src FIFOポートを使う (SUPPORT_AVALONST_CMD=1の場合のみ)
	parameter ENABLE_AVALONST_SINK	= 1		// 1=Avalon-ST Sink FIFOポートを使う (SUPPORT_AVALONST_CMD=1の場合のみ)
) (
	input wire			reset,
	input wire			clk,

	// UDPペイロードインターフェース 
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
	output wire			out_error,	// eop時にアサートすると応答パケットを破棄する 

	// Packet to Avalon-MM Host (altera_avalon_packet_to_master)
	input wire			mmreq_ready,
	output wire			mmreq_valid,
	output wire [7:0]	mmreq_data,
	output wire			mmreq_sop,
	output wire			mmreq_eop,

	output wire			mmrsp_ready,
	input wire			mmrsp_valid,
	input wire  [7:0]	mmrsp_data,
	input wire			mmrsp_sop,
	input wire			mmrsp_eop,

	// Avalon-ST Source FIFO (CLI→DEV)
	output wire [3:0]	srcfifo_ch,
	output wire			srcfifo_wen,
	output wire [7:0]	srcfifo_data,
	input wire  [10:0]	srcfifo_free,

	// Avalon-ST Sink FIFO (DEV→CLI)
	output wire [3:0]	sinkfifo_ch,
	output wire			sinkfifo_ack,
	input wire  [7:0]	sinkfifo_q,
	input wire  [10:0]	sinkfifo_remain
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam MM_PORT_ENABLE = (SUPPORT_AVALONMM_CMD && ENABLE_AVALONMM_HOST);
	localparam ST_SRC_ENABLE = (SUPPORT_AVALONST_CMD && ENABLE_AVALONST_SRC);
	localparam ST_SINK_ENABLE = (SUPPORT_AVALONST_CMD && ENABLE_AVALONST_SINK);

	localparam FOURCC_AVMM = {8'h41, 8'h56, 8'h4d, 8'h4d};	// 'A' 'V' 'M' 'M'

	localparam CMD_AVMM_WRITE		= 8'h40;
	localparam CMD_AVMM_WRITE_INC	= 8'h44;
	localparam CMD_AVMM_READ		= 8'h50;
	localparam CMD_AVMM_READ_INC	= 8'h54;
	localparam CMD_AVST_OUT			= 8'h20;
	localparam CMD_AVST_IN			= 8'h30;
	localparam CMD_END				= 8'h7f;

	localparam	RES_OK				= 2'd0,
				RES_UNDEFINED_CMD	= 2'd1,
				RES_PACKET_INCORRECT= 2'd2,
				RES_EOP_NOT_EXIST	= 2'd3;

	localparam	STATE_IDLE			= 5'd0,
				STATE_FOURCC		= 5'd1,
				STATE_FOURCC_RESP	= 5'd2,
				STATE_CHECKCMD		= 5'd3,
				STATE_AVMM			= 5'd4,
				STATE_AVMM_DATA		= 5'd5,
				STATE_AVMM_RESP		= 5'd6,
				STATE_AVMM_TRANS	= 5'd7,
				STATE_AVST			= 5'd8,
				STATE_AVST_WRITE	= 5'd9,
				STATE_AVST_RESP		= 5'd10,
				STATE_AVST_READ		= 5'd11,
				STATE_PADDING		= 5'd12,
				STATE_END			= 5'd13,
				STATE_CLOSE			= 5'd14,
				STATE_CLOSE_RESP	= 5'd15;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 
	wire			clock_sig = clk;		// モジュール内部駆動クロック 

	reg  [1:0]		in_bytepos_reg, out_bytepos_reg;
	reg  [4:0]		state_reg;
	reg				ready_reg;
	reg  [1:0]		error_reg;
	reg				accept_reg;
	reg				out_valid_reg, out_sop_reg, out_eop_reg;
	reg  [7:0]		out_data_reg;
	wire			in_ready_sig, in_enable_sig;
	wire			out_ready_sig;

	reg				mm_resp_reg;
	reg  [2:0]		mm_count_reg;
	reg				mm_write_reg, mm_inc_reg;
	reg  [10:0]		mm_datalen_reg;
	reg				mmreq_valid_reg, mmreq_sop_reg, mmreq_eop_reg;
	reg  [7:0]		mmreq_data_reg;
	wire			mmreq_ready_sig;
	wire			mmrsp_ready_sig, mmrsp_valid_sig, mmrsp_sop_sig, mmrsp_eop_sig;
	wire [7:0]		mmrsp_data_sig;

	reg				st_enqueue_reg;
	reg  [3:0]		st_channel_reg;
	reg  [10:0]		st_datalen_reg, st_wrlen_reg, st_datanum_reg;
	reg				stin_eop_reg;
	reg  [7:0]		stin_data_reg;
	reg				stin_datavalid_reg;
	reg				stin_fifowen_reg;
	reg				stout_fifoack_reg;
	wire			srcfifo_wen_sig;
	wire [7:0]		srcfifo_data_sig;
	wire [10:0]		srcfifo_free_sig;
	wire [7:0]		sinkfifo_q_sig;
	wire [10:0]		sinkfifo_remain_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	// ポート入出力 

	assign in_ready_sig = ready_reg & ((state_reg == STATE_AVMM || state_reg == STATE_AVMM_DATA)? mmreq_ready_sig : 1'b1);
	assign in_ready = in_ready_sig;

	assign out_ready_sig = out_ready;
	assign out_valid = out_valid_reg;
	assign out_data = out_data_reg;
	assign out_sop = out_sop_reg;
	assign out_eop = out_eop_reg;
	assign out_error = ~accept_reg;

	assign mmreq_ready_sig = (MM_PORT_ENABLE)? mmreq_ready : 1'b1;
	assign mmreq_valid = (MM_PORT_ENABLE)? mmreq_valid_reg : 1'b0;
	assign mmreq_data = (MM_PORT_ENABLE)? mmreq_data_reg : 1'd0;
	assign mmreq_sop = (MM_PORT_ENABLE && mmreq_valid_reg)? mmreq_sop_reg : 1'b0;
	assign mmreq_eop = (MM_PORT_ENABLE && mmreq_valid_reg)? mmreq_eop_reg : 1'b0;

	assign mmrsp_ready_sig = (state_reg == STATE_AVMM_TRANS && (!out_valid_reg || out_ready_sig));
	assign mmrsp_ready = (MM_PORT_ENABLE)? mmrsp_ready_sig : 1'b0;
	assign mmrsp_valid_sig = (MM_PORT_ENABLE)? mmrsp_valid : 1'b1;
	assign mmrsp_data_sig = (MM_PORT_ENABLE)? mmrsp_data : 1'd0;
	assign mmrsp_sop_sig = (MM_PORT_ENABLE)? mmrsp_sop : 1'b1;
	assign mmrsp_eop_sig = (MM_PORT_ENABLE)? mmrsp_eop : 1'b0;

	assign srcfifo_ch = (ST_SRC_ENABLE)? st_channel_reg : 1'd0;
	assign srcfifo_wen = (ST_SRC_ENABLE && stin_fifowen_reg && stin_datavalid_reg);
	assign srcfifo_data = (ST_SRC_ENABLE)? stin_data_reg : 1'd0;
	assign srcfifo_free_sig = (ST_SRC_ENABLE)? srcfifo_free : 1'd0;

	assign sinkfifo_ch = (ST_SINK_ENABLE)? st_channel_reg : 1'd0;
	assign sinkfifo_ack = (ST_SINK_ENABLE && stout_fifoack_reg && out_ready_sig);
	assign sinkfifo_q_sig = (ST_SINK_ENABLE)? sinkfifo_q : 1'd0;
	assign sinkfifo_remain_sig = (ST_SINK_ENABLE)? sinkfifo_remain : 1'd0;


	// メインステートマシン 

	assign in_enable_sig = (in_ready_sig && in_valid);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			state_reg <= STATE_IDLE;
			ready_reg <= 1'b0;
			out_valid_reg <= 1'b0;
			mmreq_valid_reg <= 1'b0;
			stin_fifowen_reg <= 1'b0;
			stout_fifoack_reg <= 1'b0;
		end
		else begin
			if (in_enable_sig && in_sop) begin
				in_bytepos_reg <= 2'd1;
				out_bytepos_reg <= 2'd0;
				state_reg <= STATE_FOURCC;
				ready_reg <= 1'b1;
				error_reg <= RES_OK;
				accept_reg <= (in_data == FOURCC_AVMM[31:24]);
				out_valid_reg <= 1'b0;
				out_sop_reg <= 1'b0;
				out_eop_reg <= 1'b0;
				mmreq_valid_reg <= 1'b0;
				mmreq_sop_reg <= 1'b0;
				mmreq_eop_reg <= 1'b0;
				stin_fifowen_reg <= 1'b0;
				stout_fifoack_reg <= 1'b0;
			end
			else begin
				// バイトカウンタ(4バイト境界チェック用)
				if (in_enable_sig) begin
					in_bytepos_reg <= in_bytepos_reg + 1'd1;
				end

				if (out_ready_sig && out_valid_reg) begin
					out_bytepos_reg <= out_bytepos_reg + 1'd1;
				end


				case (state_reg)
				STATE_IDLE : begin
					ready_reg <= 1'b1;
				end

				// パケットヘッダチェック 
				STATE_FOURCC : begin
					if (in_enable_sig) begin
						if (in_bytepos_reg == 2'd3 || in_eop) begin
							state_reg <= STATE_FOURCC_RESP;
							ready_reg <= 1'b0;
							out_valid_reg <= 1'b1;
							out_data_reg <= FOURCC_AVMM[31:24];
							out_sop_reg <= 1'b1;
						end

						if (in_eop) begin
							accept_reg <= 1'b0;		// FOURCCチェック中に中断した場合はパケット破棄 
						end
						else begin
							case (in_bytepos_reg)	// FOURCCのチェック 
							2'd1 : if (in_data != FOURCC_AVMM[23:16]) accept_reg <= 1'b0;
							2'd2 : if (in_data != FOURCC_AVMM[15: 8]) accept_reg <= 1'b0;
							default : if (in_data != FOURCC_AVMM[ 7: 0]) accept_reg <= 1'b0;
							endcase
						end
					end
				end
				STATE_FOURCC_RESP : begin
					if (out_ready_sig) begin
						out_sop_reg <= 1'b0;

						if (out_bytepos_reg == 2'd3) begin
							ready_reg <= 1'b1;
							out_valid_reg <= 1'b0;

							if (out_eop_reg) begin
								state_reg <= STATE_IDLE;
							end
							else begin
								state_reg <= STATE_CHECKCMD;
							end
						end

						if (out_eop_reg) begin
							 out_eop_reg <= 1'b0;
						end
						else if (out_bytepos_reg == 2'd2 && !accept_reg) begin
							out_eop_reg <= 1'b1;
						end

						case (out_bytepos_reg)
						2'd0 : out_data_reg <= FOURCC_AVMM[23:16];
						2'd1 : out_data_reg <= FOURCC_AVMM[15: 8];
						default : out_data_reg <= FOURCC_AVMM[ 7: 0];
						endcase
					end
				end

				// コマンド分岐 
				STATE_CHECKCMD : begin
					if (in_enable_sig) begin
						if (in_eop) begin
							state_reg <= STATE_CLOSE;
							error_reg <= RES_PACKET_INCORRECT;
						end
						else if (in_bytepos_reg == 2'd0) begin
							mm_count_reg <= 3'd7;
							mm_write_reg <= ~in_data[4];		// 40h,44h : AVMM_WRITE / 50h,54h : AVMM_READ
							mm_inc_reg <= in_data[2];			// 44h,54h : addr inc
							mmreq_data_reg <= in_data ^ 8'h40;	// AvalonMMトランザクションコマンドに変換 
							mmreq_sop_reg <= 1'b1;
							mmreq_eop_reg <= 1'b0;

							st_enqueue_reg <= ~in_data[4];		// 2xh : AVST_OUT / 3xh : AVST_IN
							st_channel_reg <= in_data[3:0];		// xnh : fifo channel
							stin_eop_reg <= 1'b0;

							if (SUPPORT_AVALONST_CMD && in_data[7:5] == 3'b001) begin
								state_reg <= STATE_AVST;
								mmreq_valid_reg <= 1'b0;
							end
							else if (SUPPORT_AVALONMM_CMD && (in_data & ~8'h14) == 8'h40) begin
								state_reg <= STATE_AVMM;
								mmreq_valid_reg <= 1'b1;
							end
							else begin
								state_reg <= STATE_END;
								error_reg <= (in_data == CMD_END)? RES_OK : RES_UNDEFINED_CMD;
								mmreq_valid_reg <= 1'b0;
							end
						end
					end
				end

				// Avalon-MM Hostパケット 
				STATE_AVMM : begin
					if (mmreq_ready_sig) begin
						if (in_ready_sig) begin
							mmreq_valid_reg <= in_valid;
						end
						else if (mmreq_eop_reg && !mm_count_reg && !mm_write_reg) begin
							mmreq_valid_reg <= 1'b0;
						end
					end

					if (in_enable_sig && in_eop) begin
						state_reg <= STATE_CLOSE;
						error_reg <= RES_EOP_NOT_EXIST;		// 未終端エラー 
					end
					else if (mmreq_ready_sig && (in_enable_sig || mmreq_eop_reg)) begin
						mm_count_reg <= mm_count_reg - 1'd1;
						mmreq_data_reg <= in_data;
						mmreq_sop_reg <= 1'b0;
						mm_resp_reg <= 1'b0;

						if (mm_count_reg == 3'd5) begin
							mm_datalen_reg <= {mmreq_data_reg[2:0], in_data};
						end

						if (mmreq_eop_reg) begin
							mmreq_eop_reg <= 1'b0;
						end
						else if ((mm_count_reg == 3'd1 && !mm_write_reg) || (!mm_count_reg && mm_datalen_reg == 11'd1)) begin
							ready_reg <= 1'b0;
							mmreq_eop_reg <= 1'b1;
						end

						if (!mm_count_reg) begin
							if (mm_write_reg) begin
								state_reg <= STATE_AVMM_DATA;
							end
							else begin
								state_reg <= STATE_AVMM_RESP;
								out_valid_reg <= 1'b1;
								out_data_reg <= {3'b110, ~mm_write_reg, 1'b0, mm_inc_reg, 2'b00};
							end
						end
					end
				end
				STATE_AVMM_DATA : begin
					if (mmreq_ready_sig) begin
						if (in_ready_sig) begin
							mmreq_valid_reg <= in_valid;
						end
						else if (mmreq_eop_reg) begin
							mmreq_valid_reg <= 1'b0;
						end
					end

					if (in_enable_sig && in_eop) begin
						state_reg <= STATE_CLOSE;
						error_reg <= RES_EOP_NOT_EXIST;		// 未終端エラー 
					end
					else if (mmreq_ready_sig && (in_enable_sig || mmreq_eop_reg)) begin
						mm_datalen_reg <= mm_datalen_reg - 1'd1;
						mmreq_data_reg <= in_data;

						if (mmreq_eop_reg) begin
							mmreq_eop_reg <= 1'b0;
						end
						else if (mm_datalen_reg == 11'd2) begin
							ready_reg <= 1'b0;
							mmreq_eop_reg <= 1'b1;
						end

						if (mmreq_eop_reg) begin
							if (ENABLE_AVALONMM_HOST) begin
								state_reg <= STATE_AVMM_TRANS;
							end
							else begin
								state_reg <= STATE_AVMM_RESP;
								out_valid_reg <= 1'b1;
								out_data_reg <= {3'b110, ~mm_write_reg, 1'b0, mm_inc_reg, 2'b00};
							end
						end
					end
				end
				STATE_AVMM_RESP : begin
					if (out_ready_sig) begin
						if (out_bytepos_reg == 2'd3) begin
							out_valid_reg <= 1'b0;

							if (ENABLE_AVALONMM_HOST) begin
								state_reg <= STATE_AVMM_TRANS;
							end
							else begin
								state_reg <= STATE_CHECKCMD;
								ready_reg <= 1'b1;
							end
						end

						if (ENABLE_AVALONMM_HOST) begin
							case (out_bytepos_reg)
							2'd1 : out_data_reg <= {5'b0, mm_datalen_reg[10:8]};
							2'd2 : out_data_reg <= mm_datalen_reg[7:0];
							default : out_data_reg <= 8'h00;
							endcase
						end
						else begin
							out_data_reg <= 8'h00;
						end
					end
				end
				STATE_AVMM_TRANS : begin
					if (!mm_resp_reg) begin
						if (mmrsp_ready_sig && mmrsp_sop_sig) begin
							mm_resp_reg <= 1'b1;
						end
					end

					if (mmrsp_ready_sig && (mm_resp_reg || mmrsp_sop_sig)) begin
						out_valid_reg <= mmrsp_valid_sig;

						if (mm_write_reg && mmrsp_sop_sig) begin
							out_data_reg <= mmrsp_data_sig ^ 8'h40;		// ライトコマンドのレスポンスを変換 
						end
						else begin
							out_data_reg <= mmrsp_data_sig;
						end

						if (mmrsp_eop_sig) begin
							state_reg <= STATE_PADDING;
						end
					end
				end

				// Avalon-ST FIFOパケット 
				STATE_AVST : begin
					if (in_enable_sig && in_eop) begin
						state_reg <= STATE_CLOSE;
						error_reg <= RES_EOP_NOT_EXIST;		// 未終端エラー 
					end
					else if (in_enable_sig || stin_eop_reg) begin
						stin_data_reg <= in_data;

						if (in_bytepos_reg == 2'd3) begin
							st_datalen_reg <= {stin_data_reg[2:0], in_data};
						end

						if (in_bytepos_reg == 2'd0) begin
							if (st_enqueue_reg) begin
								stin_fifowen_reg <= (srcfifo_free_sig != 1'd0);
								stin_datavalid_reg <= 1'b1;

								if (srcfifo_free_sig > st_datalen_reg) begin
									st_datanum_reg <= st_datalen_reg;
									st_wrlen_reg <= st_datalen_reg;
								end
								else begin
									st_datanum_reg <= srcfifo_free_sig;
									st_wrlen_reg <= srcfifo_free_sig;
								end
							end
							else begin
								if (sinkfifo_remain_sig > st_datalen_reg) begin
									st_datanum_reg <= st_datalen_reg;
								end
								else begin
									st_datanum_reg <= sinkfifo_remain_sig;
								end
							end
						end

						if (stin_eop_reg) begin
							stin_eop_reg <= 1'b0;
						end
						else if ((in_bytepos_reg == 2'd3 && !st_enqueue_reg) || (in_bytepos_reg == 2'd0 && st_datalen_reg == 11'd1)) begin
							ready_reg <= 1'b0;
							stin_eop_reg <= 1'b1;
						end

						if (in_bytepos_reg == 2'd0) begin
							if (st_enqueue_reg) begin
								state_reg <= STATE_AVST_WRITE;
							end
							else begin
								state_reg <= STATE_AVST_RESP;
								out_valid_reg <= 1'b1;
								out_data_reg <= {3'b101, ~st_enqueue_reg, st_channel_reg};
							end
						end
					end
				end
				STATE_AVST_WRITE : begin
					stin_data_reg <= in_data;
					stin_datavalid_reg <= in_enable_sig;

					if (in_enable_sig && in_eop) begin
						state_reg <= STATE_CLOSE;
						error_reg <= RES_EOP_NOT_EXIST;			// 未終端エラー 
					end
					else if (in_enable_sig || stin_eop_reg) begin
						st_datalen_reg <= st_datalen_reg - 1'd1;

						if (st_wrlen_reg) begin
							st_wrlen_reg <= st_wrlen_reg - 1'd1;
						end

						if (st_wrlen_reg == 11'd1) begin
							stin_fifowen_reg <= 1'b0;
						end

						if (stin_eop_reg) begin
							stin_eop_reg <= 1'b0;
						end
						else if (st_datalen_reg == 11'd2) begin
							ready_reg <= 1'b0;
							stin_eop_reg <= 1'b1;
						end

						if (stin_eop_reg) begin
							state_reg <= STATE_AVST_RESP;
							out_valid_reg <= 1'b1;
							out_data_reg <= {3'b101, ~st_enqueue_reg, st_channel_reg};
						end
					end
				end
				STATE_AVST_RESP : begin
					if (out_ready_sig) begin
						if (out_bytepos_reg == 2'd3) begin
							if (st_enqueue_reg || !st_datanum_reg) begin
								state_reg <= STATE_CHECKCMD;
								ready_reg <= 1'b1;
								out_valid_reg <= 1'b0;
							end
							else begin
								state_reg <= STATE_AVST_READ;
								out_valid_reg <= 1'b0;
								stout_fifoack_reg <= 1'b1;
							end
						end

						case (out_bytepos_reg)
						2'd1 : out_data_reg <= {5'b0, st_datanum_reg[10:8]};
						2'd2 : out_data_reg <= st_datanum_reg[7:0];
						default : out_data_reg <= 8'h00;
						endcase
					end
				end
				STATE_AVST_READ : begin
					if (out_ready_sig) begin
						st_datanum_reg <= st_datanum_reg - 1'd1;
						out_valid_reg <= stout_fifoack_reg;
						out_data_reg <= sinkfifo_q_sig;

						if (st_datanum_reg == 11'd1) begin
							state_reg <= STATE_PADDING;
							stout_fifoack_reg <= 1'b0;
						end
					end
				end

				// 出力パケットパディング 
				STATE_PADDING : begin
					if (out_ready_sig) begin
						out_data_reg <= 8'h00;

						if (out_bytepos_reg == 2'd3) begin
							state_reg <= STATE_CHECKCMD;
							ready_reg <= 1'b1;
							out_valid_reg <= 1'b0;
						end
					end
				end

				// パケットクローズ処理 
				STATE_END : begin
					if (in_enable_sig && in_eop) begin		// EOPまで読み捨て 
						state_reg <= STATE_CLOSE;
					end
				end
				STATE_CLOSE : begin
					state_reg <= STATE_CLOSE_RESP;
					out_valid_reg <= 1'b1;
					out_data_reg <= CMD_END | 8'h80;		// レスポンスIDLEコード 
					mmreq_valid_reg <= 1'b0;
					stin_fifowen_reg <= 1'b0;
					stout_fifoack_reg <= 1'b0;
				end
				STATE_CLOSE_RESP : begin
					if (out_ready_sig) begin
						if (out_bytepos_reg == 2'd0) begin
							out_data_reg <= {6'b0, error_reg};
						end
						else begin
							out_data_reg <= 8'h00;
						end

						if (out_eop_reg) begin
							state_reg <= STATE_IDLE;
							out_valid_reg <= 1'b0;
							out_eop_reg <= 1'b0;
						end
						else if (out_bytepos_reg == 2'd2) begin
							out_eop_reg <= 1'b1;
						end
					end
				end
				endcase
			end

		end
	end



endmodule

`default_nettype wire
