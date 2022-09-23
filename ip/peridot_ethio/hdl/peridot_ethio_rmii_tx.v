// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / RMII-TX
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/07/01 -> 2022/08/04
//            : 2022/09/03 (FIXED)
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

// [メモ]
//
// 上流側のインターフェースはAvalon-STとなっているが、sopからeopまでは送信レートで 
// データ入力しなければならない。（ready='1'のときに valid は'1'でなければならない） 
// sop～eopの区間以外の valid アサートは無視される。
// フレーム送信中 ready='1'かつ valid='0'を検出するとアンダーフローエラーをアサートする。 
//
// 半二重でコリジョン検出をした場合は直ちにeopを入力し、フレーム送信が終了するまで 
// jam をアサートすること。 
//
// tx_enable='0'の場合は送信動作を停止する。（送信中のフレームはそのまま送信する） 
//
// IGNORE_MACADDR_FIELD = 0 の場合、送信フレームの6～11バイトには自分のMACアドレスが 
// 挿入される。（データ入力側で6バイト目と7バイト目の間に挿入）
// さらに、ACCEPT_PAUSE_FRAME = 1 の場合はPAUSEフレームの送信処理をする。 
//

// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_ethio_rmii_tx #(
	parameter INTERFRAMEGAP_COUNT	= 48,	// フレーム間ギャップのカウント数 
	parameter IGNORE_MACADDR_FIELD	= 0,	// 1=MACアドレスフィールド挿入/破棄をしない 
	parameter ACCEPT_PAUSE_FRAME	= 0		// 1=PAUSEフレーム送信を行う 
) (
	output wire			test_ready,
	output wire			test_valid,
	output wire [7:0]	test_data,
	output wire			test_start,
	output wire			test_stop,

	output wire			test_enable,
	output wire			test_preamble,
	output wire			test_datavalid,
	output wire			test_macaddr,
	output wire			test_padding,
	output wire			test_fcs,
	output wire			test_interframe,

	output wire			test_crc_init,
	output wire			test_in_valid,
	output wire [1:0]	test_in_data,
	output wire [31:0]	test_crc,
	output wire			test_crc_shift,
	output wire [1:0]	test_crc_data,


	input wire			reset,
	input wire			clk,			// RMII_CLK (50MHz)
	input wire  [47:0]	macaddr,
	input wire			tx_enable,

	// PAUSE送信リクエスト 
	input wire			pause_req,
	input wire [15:0]	pause_value,
	output wire			pause_ack,

	// 送信データストリーム 
	output wire			in_ready,
	input wire  [7:0]	in_data,
	input wire			in_valid,
	input wire			in_sop,
	input wire			in_eop,
	output wire [0:0]	in_error,		// [0] 1=アンダーフロー発生, SOP入力でクリア 

	// RMII送信 
	input wire			timing,			// ビット送出タイミング 
	output wire			frame,			// データ送信中にアサート 
	input wire			jam,			// 無効フレームにする場合にアサートする(frameアサートの間保持する) 
	output wire [1:0]	rmii_txd,
	output wire			rmii_txen
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam MIN_FRAMEOCTET_VALUE		= 64 - 4 - 2;	// 64 - FCS - 2
	localparam BEGIN_MACADDR_OCTET		= MIN_FRAMEOCTET_VALUE - (6 - 2);
	localparam END_MACADDR_OCTET		= BEGIN_MACADDR_OCTET - 6;
	localparam MACADDR_OCTECT_1			= BEGIN_MACADDR_OCTET - 1;
	localparam MACADDR_OCTECT_2			= BEGIN_MACADDR_OCTET - 2;
	localparam MACADDR_OCTECT_3			= BEGIN_MACADDR_OCTET - 3;
	localparam MACADDR_OCTECT_4			= BEGIN_MACADDR_OCTET - 4;
	localparam MACADDR_OCTECT_5			= BEGIN_MACADDR_OCTET - 5;
	localparam MACADDR_OCTECT_6			= BEGIN_MACADDR_OCTET - 6;

	localparam BEGIN_PAUSEFRAME_OCTET	= MIN_FRAMEOCTET_VALUE - (0 - 2);
	localparam PAUSEFRAME_OCTET_2		= BEGIN_PAUSEFRAME_OCTET - 2;
	localparam PAUSEFRAME_OCTET_3		= BEGIN_PAUSEFRAME_OCTET - 3;
	localparam PAUSEFRAME_OCTET_4		= BEGIN_PAUSEFRAME_OCTET - 4;
	localparam PAUSEFRAME_OCTET_5		= BEGIN_PAUSEFRAME_OCTET - 5;
	localparam PAUSEFRAME_OCTET_6		= BEGIN_PAUSEFRAME_OCTET - 6;
	localparam PAUSEFRAME_TYPE_1		= BEGIN_PAUSEFRAME_OCTET - 13;
	localparam PAUSEFRAME_TYPE_2		= BEGIN_PAUSEFRAME_OCTET - 14;
	localparam PAUSEFRAME_CODE_1		= BEGIN_PAUSEFRAME_OCTET - 15;
	localparam PAUSEFRAME_CODE_2		= BEGIN_PAUSEFRAME_OCTET - 16;
	localparam PAUSEFRAME_VALUE_1		= BEGIN_PAUSEFRAME_OCTET - 17;
	localparam PAUSEFRAME_VALUE_2		= BEGIN_PAUSEFRAME_OCTET - 18;

	localparam PREAMBLE_COUNT_VALUE		= (8*8)/2 - 1;	// 64bit分 
	localparam FRAMEFCS_COUNT_VALUE		= (4*8)/2 - 1;	// 32bit分 
	localparam INTERFRAME_COUNT_VALUE	= (INTERFRAMEGAP_COUNT > 62)? 62 : INTERFRAMEGAP_COUNT-1;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 
	wire			clock_sig = clk;		// モジュール内部駆動クロック 

	wire			valid_sig;
	wire [7:0]		data_sig;
	wire			sop_sig;
	wire			eop_sig;

	wire			pause_grant_sig;
	wire			pause_req_sig;
	wire [7:0]		pause_data_sig;
	wire			pause_eop_sig;
	reg				pause_sel_reg;
	reg				pause_sop_reg;

	wire			txtimig_sig;
	wire			ready_sig;
	wire			enable_sig;
	wire			start_sig;
	wire			stop_sig;
	reg				packet_reg;
	reg				underflow_reg;
	reg				macaddr_field_reg;
	reg  [5:0]		preamble_count_reg;
	reg  [2:0]		data_count_reg;
	reg  [6:0]		octet_count_reg;
	reg  [4:0]		fcs_count_reg;
	reg  [6:0]		interframe_count_reg;
	reg  [7:0]		octet_reg;
	wire [7:0]		macaddr_octet_sig;

	wire			crc_init_sig;
	wire			in_valid_sig;
	wire [1:0]		in_data_sig;
	wire			crc_shift_sig;
	wire [1:0]		crc_data_sig;
	wire [31:0]		crc_sig;

	wire [1:0]		tx_data_sig;
	reg  [1:0]		txd_reg			/* synthesis altera_attribute = "-name FAST_OUTPUT_REGISTER ON" */;
	reg				txen_reg		/* synthesis altera_attribute = "-name FAST_OUTPUT_REGISTER ON" */;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */

	assign test_ready = ready_sig;
	assign test_valid = valid_sig;
	assign test_data = data_sig;
	assign test_start = start_sig;
	assign test_stop = stop_sig;

	assign test_enable = enable_sig;
	assign test_preamble = preamble_count_reg[5];
	assign test_datavalid = data_count_reg[2];
	assign test_macaddr = macaddr_field_reg;
	assign test_padding = octet_count_reg[6];
	assign test_fcs = fcs_count_reg[4];
	assign test_interframe = interframe_count_reg[6];

	assign test_crc_init = crc_init_sig;
	assign test_in_valid = in_valid_sig;
	assign test_in_data = in_data_sig;
	assign test_crc = crc_sig;
	assign test_crc_shift = crc_shift_sig;
	assign test_crc_data = crc_data_sig;


/* ===== モジュール構造記述 ============== */

	// Avalon-ST インターフェース 

	assign txtimig_sig = timing;

	assign in_ready = ((tx_enable || packet_reg) && txtimig_sig && !pause_grant_sig)? ready_sig : 1'b0;
	assign in_error = {underflow_reg};

	assign valid_sig = (pause_sel_reg)? 1'b1 : in_valid;
	assign data_sig = (pause_sel_reg)? pause_data_sig : in_data;
	assign sop_sig = (pause_sel_reg)? pause_sop_reg : in_sop;
	assign eop_sig = (pause_sel_reg)? pause_eop_sig : in_eop;


	// PAUSEフレーム生成 

	assign pause_grant_sig = ((!packet_reg && ready_sig && txtimig_sig && pause_req_sig) || pause_sel_reg);
	assign pause_req_sig = (!IGNORE_MACADDR_FIELD && ACCEPT_PAUSE_FRAME)? pause_req : 1'b0;
	assign pause_ack = (ready_sig && txtimig_sig && pause_sel_reg && pause_eop_sig);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			pause_sel_reg <= 1'b0;
			pause_sop_reg <= 1'b0;
		end
		else begin
			if (ready_sig && txtimig_sig) begin
				if (pause_sel_reg) begin
					if (pause_eop_sig) begin
						pause_sel_reg <= 1'b0;
					end
				end
				else begin
					if (!packet_reg && pause_req_sig) begin
						pause_sel_reg <= 1'b1;
					end
				end
			end

			if (pause_sop_reg) begin
				if (start_sig && txtimig_sig) begin
					pause_sop_reg <= 1'b0;
				end
			end
			else begin
				if (!packet_reg && pause_req_sig) begin
					pause_sop_reg <= 1'b1;
				end
			end
		end
	end

	assign pause_data_sig =
				(octet_count_reg[4:0] == PAUSEFRAME_OCTET_2[4:0])? 8'h80 :
				(octet_count_reg[4:0] == PAUSEFRAME_OCTET_3[4:0])? 8'hc2 :
				(octet_count_reg[4:0] == PAUSEFRAME_OCTET_4[4:0])? 8'h00 :
				(octet_count_reg[4:0] == PAUSEFRAME_OCTET_5[4:0])? 8'h00 :
				(octet_count_reg[4:0] == PAUSEFRAME_OCTET_6[4:0])? 8'h01 :
				(octet_count_reg[4:0] == PAUSEFRAME_TYPE_1[4:0] )? 8'h88 :
				(octet_count_reg[4:0] == PAUSEFRAME_TYPE_2[4:0] )? 8'h08 :
				(octet_count_reg[4:0] == PAUSEFRAME_CODE_1[4:0] )? 8'h00 :
				(octet_count_reg[4:0] == PAUSEFRAME_CODE_2[4:0] )? 8'h01 :
				(octet_count_reg[4:0] == PAUSEFRAME_VALUE_1[4:0])? pause_value[15:8] :
				(octet_count_reg[4:0] == PAUSEFRAME_VALUE_2[4:0])? pause_value[ 7:0] :
				8'h01;

	assign pause_eop_sig = (octet_count_reg[4:0] == PAUSEFRAME_VALUE_2[4:0]);


	// フレームデータ生成カウンタ 

	assign ready_sig = (!interframe_count_reg[6] && !(macaddr_field_reg || fcs_count_reg[4]) && (!data_count_reg[2] || !data_count_reg[1:0]) && !preamble_count_reg[5]);
	assign enable_sig = (ready_sig && packet_reg);
	assign start_sig = (ready_sig && valid_sig && sop_sig && tx_enable);
	assign stop_sig = (enable_sig && valid_sig && eop_sig);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			packet_reg <= 1'b0;
			underflow_reg <= 1'b0;
			macaddr_field_reg <= 1'b0;
			preamble_count_reg <= 1'd0;
			data_count_reg <= 1'd0;
			octet_count_reg <= 1'd0;
			fcs_count_reg <= 1'd0;
			interframe_count_reg <= 1'd0;
		end
		else begin
			if (txtimig_sig) begin

				// Avalon-ST パケット期間フラグ 
				if (start_sig) begin
					packet_reg <= 1'b1;
				end
				else if (stop_sig) begin
					packet_reg <= 1'b0;
				end

				// Avalon-ST アンダーフローエラー検出 
				if (start_sig) begin
					underflow_reg <= 1'b0;
				end
				else if (packet_reg && ready_sig && !valid_sig) begin
					underflow_reg <= 1'b1;
				end

				// MACアドレスフィールドフラグ 
				if (start_sig || (octet_count_reg[5:0] == END_MACADDR_OCTET[5:0] && !data_count_reg[1:0])) begin
					macaddr_field_reg <= 1'b0;
				end
				else if (octet_count_reg[5:0] == BEGIN_MACADDR_OCTET[5:0] && !data_count_reg[1:0]) begin
					macaddr_field_reg <= (!IGNORE_MACADDR_FIELD);
				end

				// PREAMBLE + SFD のカウント(32クロック)
				if (start_sig) begin
					preamble_count_reg <= {1'b1, PREAMBLE_COUNT_VALUE[4:0]};
				end
				else if (preamble_count_reg[5]) begin
					preamble_count_reg <= preamble_count_reg - 1'd1;
				end

				// 送信データのラッチとビットシフト(4クロック×データ数)
				if (start_sig || enable_sig) begin
					octet_reg <= data_sig;
					data_count_reg <= {1'b1, 2'd3};
				end
				else if (octet_count_reg[6] && (macaddr_field_reg || fcs_count_reg[4]) && !data_count_reg[1:0]) begin
					octet_reg <= (macaddr_field_reg)? macaddr_octet_sig : 8'h00;
					data_count_reg <= {1'b1, 2'd3};
				end
				else if (!preamble_count_reg[5] && data_count_reg[2]) begin
					octet_reg <= {2'b00, octet_reg[7:2]};
					data_count_reg <= data_count_reg - 1'd1;
				end

				// 最小オクテット数のカウント(FCS以外の60オクテット分)
				if (start_sig) begin
					octet_count_reg <= {1'b1, MIN_FRAMEOCTET_VALUE[5:0]};
				end
				else if (enable_sig && octet_count_reg[6]) begin
					octet_count_reg <= octet_count_reg - 1'd1;
				end
				else if (octet_count_reg[6] && (macaddr_field_reg || fcs_count_reg[4]) && !data_count_reg[1:0]) begin
					octet_count_reg <= octet_count_reg - 1'd1;
				end

				// FCSのカウント(16クロック)
				if (stop_sig) begin
					fcs_count_reg <= {1'b1, FRAMEFCS_COUNT_VALUE[3:0]};
				end
				else if (!octet_count_reg[6] && !data_count_reg[2] && fcs_count_reg[4]) begin
					fcs_count_reg <= fcs_count_reg - 1'd1;
				end

				// インターフレームのカウント(48クロック)
				if (stop_sig) begin
					interframe_count_reg <= {1'b1, INTERFRAME_COUNT_VALUE[5:0]};
				end
				else if (!fcs_count_reg[4] && interframe_count_reg[6]) begin
					interframe_count_reg <= interframe_count_reg - 1'd1;
				end

			end
		end
	end


	// MACアドレスオクテット取得 

	assign macaddr_octet_sig = 
				(octet_count_reg[2:0] == MACADDR_OCTECT_1[2:0])? macaddr[47:40] :
				(octet_count_reg[2:0] == MACADDR_OCTECT_2[2:0])? macaddr[39:32] :
				(octet_count_reg[2:0] == MACADDR_OCTECT_3[2:0])? macaddr[31:24] :
				(octet_count_reg[2:0] == MACADDR_OCTECT_4[2:0])? macaddr[23:16] :
				(octet_count_reg[2:0] == MACADDR_OCTECT_5[2:0])? macaddr[15: 8] :
				(octet_count_reg[2:0] == MACADDR_OCTECT_6[2:0])? macaddr[ 7: 0] :
				{8{1'bx}};


	// フレームFCS計算 

	assign crc_init_sig = preamble_count_reg[5];
	assign in_valid_sig = (!preamble_count_reg[5] && data_count_reg[2]);
	assign in_data_sig = octet_reg[1:0];
	assign crc_shift_sig = (!data_count_reg[2] && fcs_count_reg[4]);

	peridot_ethio_crc32
	u_crc (
		.clk		(clock_sig),
		.clk_ena	(txtimig_sig),
		.init		(crc_init_sig),
		.crc		(crc_sig),
		.in_valid	(in_valid_sig),
		.in_data	(in_data_sig),
		.shift		(crc_shift_sig),
		.out_data	(crc_data_sig)
	);


	// 送信データラッチ 

	assign frame = (data_count_reg[2] || fcs_count_reg[4]);

	assign tx_data_sig =
				(preamble_count_reg[5])? ((preamble_count_reg[4:0])? 2'b01 : 2'b11) :
				(in_valid_sig)? in_data_sig :
				(crc_shift_sig)? crc_data_sig ^ {2{jam}} :
				2'b00;

	always @(posedge clock_sig) begin
		txd_reg <= tx_data_sig;
		txen_reg <= data_count_reg[2] | fcs_count_reg[4];
	end

	assign rmii_txd = txd_reg;
	assign rmii_txen = txen_reg;



endmodule

`default_nettype wire
