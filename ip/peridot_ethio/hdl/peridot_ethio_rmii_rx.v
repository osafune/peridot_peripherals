// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / RMII-RX
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/07/01 -> 2022/08/09
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

// [メモ]
//
// 下流側へのインターフェースはAvalon-STとなっているが、sop～eopまでは受信レートで 
// データ出力されなければならない。（ready='1'のときに valid は'1'でなければならない） 
// フレーム受信中 ready='1'かつ valid='0'を検出すると out_error[0] をアサートする。 
//
// 受信フレーム異常のうち、プリアンブル異常、SFD未検出はフレーム出力がキャンセルされる。
// FCS不一致、オクテット境界不一致、フレームオクテット数不足の場合は、eopアサートの
// タイミングで out_error[1] をアサートする。 
//
// rx_enable='0'の場合は受信動作を停止する。（受信中のフレームはそのまま受信する） 
//
// IGNORE_MACADDR_FIELD = 0 の場合はmacaddr一致またはブロードキャストアドレスの
// フレームのみを出力する。
// このときフレーム先頭の6バイト(宛先アドレス)は削除される。 
// さらに、ACCEPT_PAUSE_FRAME = 1 の場合PAUSEフレームの受信処理をする。 
// PAUSEフレームデータは内部で使用され、Avalon-STには出力されない。
//

// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_ethio_rmii_rx #(
	parameter IGNORE_FCS_CHECK		= 0,	// 1=FCSチェックをしない 
	parameter IGNORE_MACADDR_FIELD	= 0,	// 1=MACアドレスフィールド挿入/破棄をしない 
	parameter ACCEPT_PAUSE_FRAME	= 0		// 1=PAUSEフレームを受け入れる 
) (
	output wire [2:0]	test_frame,		// [2] start, [1] enable, [0] stop
	output wire			test_minoctet,
	output wire			test_macaddr,
	output wire			test_macaccept,

	output wire			test_sfd_detect,
	output wire			test_crc_valid,
	output wire [1:0]	test_crc_indata,
	output wire [31:0]	test_fcs,
	output wire [31:0]	test_crc,
	output wire [7:0]	test_data,
	output wire			test_valid,


	input wire			reset,
	input wire			clk,
	input wire  [47:0]	macaddr,
	input wire			rx_enable,

	// PAUSE受信リクエスト 
	output wire			pause_req,
	output wire [15:0]	pause_value,
	input wire			pause_ack,

	// 受信データストリーム 
	input wire			out_ready,
	output wire			out_valid,
	output wire [7:0]	out_data,
	output wire			out_sop,
	output wire			out_eop,
	output wire [1:0]	out_error,		// [0] 1=オーバーフロー発生, 次のフレーム開始でクリア 
										// [1] 1=フレームエラー発生, EOPのとき有効 
	// RMII受信 
	input wire			timing,			// ビット受信タイミング 
	output wire			frame,			// データ受信中にアサート 
	output wire			crs,			// キャリア検出 
	input wire  [1:0]	rmii_rxd,
	input wire			rmii_crsdv
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam MIN_FRAMEOCTET_VALUE		= 64 - 4 - 1;	// 64 - FCS - 1
	localparam BEGIN_MACADDR_OCTET		= MIN_FRAMEOCTET_VALUE;
	localparam END_MACADDR_OCTET		= BEGIN_MACADDR_OCTET - 6;
	localparam MACADDR_OCTECT_1			= BEGIN_MACADDR_OCTET - 1;
	localparam MACADDR_OCTECT_2			= BEGIN_MACADDR_OCTET - 2;
	localparam MACADDR_OCTECT_3			= BEGIN_MACADDR_OCTET - 3;
	localparam MACADDR_OCTECT_4			= BEGIN_MACADDR_OCTET - 4;
	localparam MACADDR_OCTECT_5			= BEGIN_MACADDR_OCTET - 5;
	localparam MACADDR_OCTECT_6			= BEGIN_MACADDR_OCTET - 6;

	localparam PAUSEFRAME_TYPE_1		= BEGIN_MACADDR_OCTET - 13;
	localparam PAUSEFRAME_TYPE_2		= BEGIN_MACADDR_OCTET - 14;
	localparam PAUSEFRAME_CODE_1		= BEGIN_MACADDR_OCTET - 15;
	localparam PAUSEFRAME_CODE_2		= BEGIN_MACADDR_OCTET - 16;
	localparam PAUSE_VALUE_LATCH		= BEGIN_MACADDR_OCTET - (18 - 1);


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 
	wire			clock_sig = clk;		// モジュール内部駆動クロック 

	wire			rxtimig_sig;
	reg  [1:0]		rxd_in_reg		/* synthesis altera_attribute = "-name FAST_INPUT_REGISTER ON" */;
	reg				crsdv_in_reg	/* synthesis altera_attribute = "-name FAST_INPUT_REGISTER ON" */;
	reg  [35:0]		data_shift_reg;
	reg  [2:0]		data_ena_reg;
	reg				rx_ena_reg;
	wire			frame_start_sig;
	wire			frame_stop_sig;
	wire			frame_enable_sig;

	reg  [2:0]		data_count_reg;
	reg  [6:0]		octet_count_reg;
	reg  [7:0]		octet_reg;
	reg				octet_enable_reg;
	reg				sfd_error_reg;
	reg				fcs_error_reg;
	wire			octet_latch_sig;
	wire			octet_valid_sig;

	reg				macaddr_field_reg;
	reg				broadcast_reg;
	reg				ownmacaddr_reg;
	reg				pauseframe_reg;
	wire			accept_sig;
	wire [7:0]		macaddr_octet_sig;

	reg				pause_ena_reg;
	reg				pause_req_reg;
	reg  [15:0]		pause_value_reg;
	wire [7:0]		pause_octet_sig;

	wire			crc_init_sig;
	wire			in_vaild_sig;
	wire [1:0]		in_data_sig;
	wire [31:0]		fcs_sig, crc_sig;
	wire			fcs_equal_sig;

	wire			valid_sig;
	wire			start_sig;
	wire			stop_sig;
	reg				start_reg;
	reg				reject_reg;
	reg				overflow_reg;
	reg  [7:0]		out_data_reg;
	reg				out_valid_reg;
	reg				out_sop_reg;
	reg				out_eop_reg;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */

	assign test_frame = {frame_start_sig, frame_enable_sig, frame_stop_sig};
	assign test_minoctet = octet_count_reg[6];
	assign test_macaddr = macaddr_field_reg;
	assign test_macaccept = accept_sig;

	assign test_sfd_detect = (!data_count_reg && data_shift_reg[7:0] == 8'hd5);
	assign test_crc_valid = in_vaild_sig;
	assign test_crc_indata = in_data_sig;
	assign test_fcs = fcs_sig;
	assign test_crc = crc_sig;

	assign test_data = octet_reg;
	assign test_valid = valid_sig;


/* ===== モジュール構造記述 ============== */

	// 受信データラッチとシフトレジスタ 

	assign rxtimig_sig = timing;

	always @(posedge clock_sig) begin
		rxd_in_reg <= rmii_rxd;
		crsdv_in_reg <= rmii_crsdv;
	end

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			data_shift_reg <= 1'd0;
			data_ena_reg <= 1'b0;
			rx_ena_reg <= 1'b0;
		end
		else begin
			if (rxtimig_sig) begin
				data_shift_reg <= {rxd_in_reg, data_shift_reg[35:2]};
				data_ena_reg <= {crsdv_in_reg, data_ena_reg[2:1]};
			end

			if (!data_ena_reg) begin
				rx_ena_reg <= rx_enable;
			end
		end
	end

	assign frame = frame_enable_sig;
	assign crs = (data_ena_reg[2] && data_ena_reg[1:0] != 2'b01);

	assign frame_start_sig = (rx_ena_reg && data_ena_reg == 3'b100);
	assign frame_stop_sig = (rx_ena_reg && data_ena_reg == 3'b001);
	assign frame_enable_sig = (rx_ena_reg && ((data_ena_reg[2] && data_ena_reg[1:0]) || data_ena_reg[1]));

	//   rxd_in_reg : xx  00  00  00  01  ‥‥ dd  dd  dd  dd  dd  xx  xx  xx  xx
	// crsdv_in_reg : ___|~~~~~~~~~~~~~~~ ‥‥ ~~~|___|~~~|___|~~~|_______________
	// data_ena_reg : 000 000 100 110 111 ‥‥ 111 111 011 101 010 101 010 001 000
	//                        CRS CRS CRS      CRS CRS
	//                        STA
	//                            ENA ENA      ENA ENA ENA ENA ENA ENA ENA
	//                                                                     STO


	// データオクテット復元 

	assign octet_latch_sig = (data_count_reg == {1'b1, 2'd0});
	assign octet_valid_sig = (octet_enable_reg && octet_latch_sig);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			data_count_reg <= 1'd0;
			octet_count_reg <= 1'd0;
			octet_enable_reg <= 1'b0;
			macaddr_field_reg <= 1'b0;
			sfd_error_reg <= 1'b0;
			fcs_error_reg <= 1'b0;
		end
		else begin
			if (rxtimig_sig) begin

				// SFD検出 
				if (!frame_enable_sig) begin
					data_count_reg <= 1'd0;
				end
				else begin
					if (!data_count_reg) begin
						if (data_shift_reg[7:0] == 8'hd5) begin
							data_count_reg <= {1'b0, 2'd1};
						end
					end
					else begin
						if (data_count_reg[1:0] == 2'd3) begin
							data_count_reg <= {1'b1, 2'd0};
						end
						else begin
							data_count_reg <= data_count_reg + 1'd1;
						end
					end
				end

				// オクテットデータラッチ 
				if (octet_latch_sig) begin
					octet_reg <= data_shift_reg[7:0];
				end

				if (frame_stop_sig) begin
					octet_enable_reg <= 1'b0;
				end
				else if (data_count_reg[2]) begin
					octet_enable_reg <= 1'b1;
				end

				// 最小オクテット数のカウント(FCS以外の60オクテット分)
				if (frame_start_sig) begin
					octet_count_reg <= {1'b1, MIN_FRAMEOCTET_VALUE[5:0]};
				end
				else if (octet_latch_sig && octet_count_reg[6]) begin
					octet_count_reg <= octet_count_reg - 1'd1;
				end

				// MACアドレス一致判定 
				if (frame_start_sig) begin
					macaddr_field_reg <= 1'b1;
				end
				else if (octet_count_reg[5:0] == END_MACADDR_OCTET[5:0] && octet_latch_sig) begin
					macaddr_field_reg <= 1'b0;
				end

				if (frame_start_sig) begin
					broadcast_reg <= 1'b1;
					ownmacaddr_reg <= 1'b1;
					pauseframe_reg <= 1'b1;
				end
				else if (macaddr_field_reg && octet_valid_sig) begin
					if (octet_reg != 8'hff) begin
						broadcast_reg <= 1'b0;
					end

					if (octet_reg != macaddr_octet_sig) begin
						ownmacaddr_reg <= 1'b0;
					end

					if (octet_reg != pause_octet_sig) begin
						pauseframe_reg <= 1'b0;
					end
				end

				// PAUSEフレーム判定 
				if (octet_count_reg[5:0] == PAUSEFRAME_TYPE_1[5:0] && octet_reg != 8'h88) begin
					pauseframe_reg <= 1'b0;
				end

				if (octet_count_reg[5:0] == PAUSEFRAME_TYPE_2[5:0] && octet_reg != 8'h08) begin
					pauseframe_reg <= 1'b0;
				end

				if (octet_count_reg[5:0] == PAUSEFRAME_CODE_2[5:0] && octet_reg != 8'h01) begin
					pauseframe_reg <= 1'b0;
				end

				// エラー信号生成 (プリアンブル異常、SFD未検出、FCS不一致、オクテット境界不一致、フレームオクテット数不足） 
				if (frame_start_sig) begin
					sfd_error_reg <= 1'b0;
				end
				else if (frame_enable_sig && !data_count_reg[2] && data_shift_reg[1:0] == 2'b10) begin
					sfd_error_reg <= 1'b1;
				end

				if (frame_start_sig) begin
					fcs_error_reg <= 1'b0;
				end
				else if (frame_stop_sig) begin
					fcs_error_reg <= (!fcs_equal_sig || !octet_latch_sig || octet_count_reg[6]);
				end
			end
		end
	end

	assign accept_sig = (IGNORE_MACADDR_FIELD || (!macaddr_field_reg && (broadcast_reg || ownmacaddr_reg)));


	// MACアドレスオクテット取得 

	assign macaddr_octet_sig = 
				(octet_count_reg[2:0] == MACADDR_OCTECT_1[2:0])? macaddr[47:40] :
				(octet_count_reg[2:0] == MACADDR_OCTECT_2[2:0])? macaddr[39:32] :
				(octet_count_reg[2:0] == MACADDR_OCTECT_3[2:0])? macaddr[31:24] :
				(octet_count_reg[2:0] == MACADDR_OCTECT_4[2:0])? macaddr[23:16] :
				(octet_count_reg[2:0] == MACADDR_OCTECT_5[2:0])? macaddr[15: 8] :
				(octet_count_reg[2:0] == MACADDR_OCTECT_6[2:0])? macaddr[ 7: 0] :
				{8{1'bx}};


	// PAUSEフレーム処理 

	assign pause_octet_sig = 
				(octet_count_reg[2:0] == MACADDR_OCTECT_1[2:0])? 8'h01 :
				(octet_count_reg[2:0] == MACADDR_OCTECT_2[2:0])? 8'h80 :
				(octet_count_reg[2:0] == MACADDR_OCTECT_3[2:0])? 8'hc2 :
				(octet_count_reg[2:0] == MACADDR_OCTECT_4[2:0])? 8'h00 :
				(octet_count_reg[2:0] == MACADDR_OCTECT_5[2:0])? 8'h00 :
				(octet_count_reg[2:0] == MACADDR_OCTECT_6[2:0])? 8'h01 :
				{8{1'bx}};

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			pause_ena_reg <= 1'b0;
			pause_req_reg <= 1'b0;
		end
		else begin
			pause_ena_reg <= rxtimig_sig & frame_stop_sig & pauseframe_reg;

			if (pause_req_reg) begin
				if (pause_ack) begin
					pause_req_reg <= 1'b0;
				end
			end
			else if (pause_ena_reg && !sfd_error_reg && !fcs_error_reg) begin
				pause_req_reg <= 1'b1;
			end

			if (rxtimig_sig && octet_latch_sig && octet_count_reg[5:0] == PAUSE_VALUE_LATCH[5:0] && pauseframe_reg) begin
				pause_value_reg <= {octet_reg, data_shift_reg[7:0]};
			end
		end
	end

	assign pause_req = (!IGNORE_MACADDR_FIELD && ACCEPT_PAUSE_FRAME)? pause_req_reg : 1'b0;
	assign pause_value = (!IGNORE_MACADDR_FIELD && ACCEPT_PAUSE_FRAME)? pause_value_reg : 1'd0;


	// フレームFCS計算 

	assign fcs_sig = ~data_shift_reg[31:0];
	assign fcs_equal_sig = (IGNORE_FCS_CHECK || fcs_sig == crc_sig);

	assign crc_init_sig = ~data_count_reg[2];
	assign in_vaild_sig = (frame_enable_sig && data_count_reg[2]);
	assign in_data_sig = data_shift_reg[1:0];

	peridot_ethio_crc32
	u_crc (
		.clk		(clock_sig),
		.clk_ena	(rxtimig_sig),
		.init		(crc_init_sig),
		.crc		(crc_sig),
		.in_valid	(in_vaild_sig),
		.in_data	(in_data_sig),
		.shift		(1'b0),
		.out_data	()
	);


	// Avalon-ST インターフェース 

	assign valid_sig = (rxtimig_sig && !sfd_error_reg && accept_sig && octet_valid_sig);
	assign start_sig = (rxtimig_sig && frame_start_sig);
	assign stop_sig = (rxtimig_sig && frame_stop_sig);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			start_reg <= 1'b0;
			overflow_reg <= 1'b0;
			out_valid_reg <= 1'b0;
			out_sop_reg <= 1'b0;
			out_eop_reg <= 1'b0;
		end
		else begin

			// パケット開始検出 
			if (start_sig && !stop_sig) begin
				start_reg <= 1'b1;
			end
			else if (valid_sig) begin
				start_reg <= 1'b0;
			end

			// オーバーフローエラー検出 
			if (valid_sig && start_reg) begin
				overflow_reg <= 1'b0;
			end
			else if (out_valid_reg && valid_sig && !out_ready) begin
				overflow_reg <= 1'b1;
			end

			// データラッチ 
			if (valid_sig) begin
				out_data_reg <= octet_reg;
			end

			if (valid_sig || (!start_reg && stop_sig)) begin
				out_valid_reg <= 1'b1;
			end
			else if (out_valid_reg && out_ready) begin
				out_valid_reg <= 1'b0;
			end

			// sop信号生成 
			if (valid_sig && (!out_valid_reg || out_ready)) begin
				out_sop_reg <= start_reg;
			end
			else if (out_valid_reg && out_ready) begin
				out_sop_reg <= 1'b0;
			end

			// eop信号生成 
			if (!start_sig && stop_sig) begin
				out_eop_reg <= 1'b1;
			end
			else if (start_sig) begin
				out_eop_reg <= 1'b0;
			end
		end
	end

	assign out_valid = out_valid_reg;
	assign out_data = out_data_reg;
	assign out_sop = out_sop_reg;
	assign out_eop = out_eop_reg & out_valid_reg;
	assign out_error = {(sfd_error_reg | fcs_error_reg), overflow_reg};



endmodule

`default_nettype wire
