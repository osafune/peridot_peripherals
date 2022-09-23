// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / Packet Sender Control
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/08/01 -> 2022/08/17
//            : 2022/08/29 (FIXED)
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
// MEMFIFOに格納されるデータフォーマットは以下の通り
//   +0 : FIFOヘッダ(bit10-0:データグラムのバイト数len)
//   +4 : データグラム0～3(リトルエンディアン)
//   +8 : データグラム4～5
//    :
//   +n : データグラム(n-1)*4～(len-1)
//
// 占有ブロック数はFIFOヘッダ分が加算されるため、以下のようになる
//   blocknum = (len + 4 + (BLOCKSIZE - 1)) / BLOCKSIZE
//
// rxpauseインターフェースはAvalon-STを以下のように読み替えて接続できる
//   rxpause_req   → valid
//   rxpause_value → data
//   rxpause_ack   → ready
//

// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_ethio_txctrl #(
	parameter PACKET_LENGTH_MIN			= 8,	// 最低パケット長(8～64, DA+TYPE)
	parameter PACKET_LENGTH_MAX			= 1508,	// 最大パケット長(512～1508, DA+TYPE+データグラム)
	parameter PACKET_RESENDNUM_MAX		= 15,	// 最大再送回数(1～15, IGNORE_COLLISION_DETECT=0のときのみ有効)
	parameter BACKOFF_TIMESLOT_UNIT		= 1,	// バックオフの基準タイムスロット時間(通常は1)
	parameter FIFO_BLOCKNUM_BITWIDTH	= 6,	// FIFOブロック数のビット値 (2^nで個数を指定) : 4～
	parameter FIFO_BLOCKSIZE_BITWIDTH	= 6,	// ブロックサイズ幅ビット値 (2^nでバイトサイズを指定) : 2～
	parameter IGNORE_LENGTH_CHECK		= 0,	// 1=パケット長チェックを無視する
	parameter IGNORE_COLLISION_DETECT	= 0,	// 1=コリジョン検出を無視する(再送処理をしない)
	parameter ACCEPT_PAUSE_FRAME		= 0		// 1=PAUSEフレームの処理をする(0の時はPAUSEフレーム待ちをしない)
) (
	input wire			reset,
	input wire			clk,
	input wire			sel_speed10m,	// 0=100Mbps, 1=10Mbps
	output wire			cancel_resend,	// 再送中止フラグ : 指定回数の再送失敗してパケット破棄が起こるごとに反転する 
	output wire			error_header,	// FIFOヘッダエラー : パケット長が指定範囲以外の場合にアサート(復帰はリセットのみ)

	// PAUSEフレーム制御 
	input wire			rxpause_req,	// PAUSEフレーム受信 
	input wire  [15:0]	rxpause_value,
	output wire			rxpause_ack,

	// 送信FIFOインターフェース 
	input wire			txfifo_ready,
	output wire			txfifo_update,
	output wire [FIFO_BLOCKNUM_BITWIDTH-1:0] txfifo_blocknum,
	input wire			txfifo_empty,
	output wire [10:0]	txfifo_address,
	input wire  [31:0]	txfifo_readdata,

	// MAC送信データストリーム 
	input wire			txmac_ready,
	output wire			txmac_valid,
	output wire [7:0]	txmac_data,
	output wire			txmac_sop,
	output wire			txmac_eop,
	input wire			txmac_error		// 1=コリジョン発生による再送要求(半二重のとき有効), SOPでクリア 
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam	STATE_IDLE		= 5'd0,
				STATE_BACKOFF	= 5'd1,
				STATE_START1	= 5'd2,
				STATE_START2	= 5'd3,
				STATE_START3	= 5'd4,
				STATE_TXDATA	= 5'd5,
				STATE_RESEND	= 5'd6,
				STATE_ABORT		= 5'd31;

	localparam EOP_DATACOUNT	= 1 + 1;	// TXFIFO最後のデータカウント値 


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 
	wire			clock_sig = clk;		// モジュール内部駆動クロック 

	wire			txmac_error_sig;
	wire			tx_ready_sig;
	wire			tx_valid_sig, tx_sop_sig, tx_eop_sig;
	wire [7:0]		tx_data_sig;
	wire			rxpause_req_sig;

	reg  [4:0]		txstate_reg;
	reg				tx_sop_reg;
	reg				tx_eop_reg;
	reg  [10:0]		data_count_reg;
	reg  [1:0]		byte_sel_reg;
	reg  [8:0]		memfifo_addr_reg;
	reg  [31:8]		memfifo_data_reg;
	reg  [3:0]		resend_count_reg;
	reg				err_toggle_reg;
	wire [FIFO_BLOCKNUM_BITWIDTH-1:0] update_blocknum_sig;

	reg  [3:0]		clkdiv_count_reg;
	reg  [23:0]		wait_count_reg;
	wire			wait_done_sig;

	reg  [9:0]		lfsr_reg;
	wire [15:0]		wait_value_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */

//	assign test_tx_ready = tx_ready_sig;
//	assign test_wait_done = wait_done_sig;



/* ===== モジュール構造記述 ============== */

	// MAC-TXストリームインターフェース 

	assign txmac_error_sig = (!IGNORE_COLLISION_DETECT && txmac_error);

	assign txmac_valid = tx_valid_sig;
	assign txmac_data = tx_data_sig;
	assign txmac_sop = tx_sop_sig;
	assign txmac_eop = tx_eop_sig;


	// フレーム送信FSM 

	assign tx_ready_sig = txmac_ready;
	assign rxpause_req_sig = (ACCEPT_PAUSE_FRAME && rxpause_req);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			txstate_reg <= STATE_IDLE;
			tx_sop_reg <= 1'b0;
			tx_eop_reg <= 1'b0;
			memfifo_addr_reg <= 1'd0;
			resend_count_reg <= 1'd0;
			err_toggle_reg <= 1'b0;
		end
		else begin
			case (txstate_reg)

			STATE_IDLE : begin
				if (tx_ready_sig) begin
					if (rxpause_req_sig) begin
						txstate_reg <= STATE_BACKOFF;
					end
					else if (txfifo_ready && !txfifo_empty) begin
						txstate_reg <= STATE_START1;
					end
				end
			end

			// バックオフタイマー待ち 
			STATE_BACKOFF : begin
				if (wait_done_sig) begin
					txstate_reg <= STATE_IDLE;
				end
			end

			// フレームデータ送信 
			STATE_START1 : begin
				txstate_reg <= STATE_START2;
				memfifo_addr_reg <= memfifo_addr_reg + 1'd1;
			end
			STATE_START2 : begin
				data_count_reg <= txfifo_readdata[10:0];

				if (IGNORE_LENGTH_CHECK || (txfifo_readdata[10:0] >= PACKET_LENGTH_MIN[10:0] && txfifo_readdata[10:0] <= PACKET_LENGTH_MAX[10:0])) begin
					txstate_reg <= STATE_START3;
				end
				else begin
					txstate_reg <= STATE_ABORT;
				end
			end
			STATE_START3 : begin
				txstate_reg <= STATE_TXDATA;
				tx_sop_reg <= 1'b1;
				byte_sel_reg <= 2'b00;
			end

			STATE_TXDATA : begin
				if (tx_ready_sig) begin
					tx_sop_reg <= 1'b0;
					data_count_reg <= data_count_reg - 1'd1;

					if (tx_eop_reg) begin
						txstate_reg <= STATE_RESEND;
					end

					if (data_count_reg == EOP_DATACOUNT[10:0]) begin
						tx_eop_reg <= 1'b1;
					end
					else begin
						tx_eop_reg <= 1'b0;
					end

					byte_sel_reg <= byte_sel_reg + 1'd1;

					if (!byte_sel_reg) begin
						memfifo_addr_reg <= memfifo_addr_reg + 1'd1;
						memfifo_data_reg <= txfifo_readdata[31:8];
					end
					else begin
						memfifo_data_reg <= {8'h00, memfifo_data_reg[31:16]};
					end
				end
			end

			// フレーム再送判定 
			STATE_RESEND : begin
				if (tx_ready_sig) begin
					memfifo_addr_reg <= 1'd0;

					if (!txmac_error_sig || resend_count_reg == PACKET_RESENDNUM_MAX[3:0]) begin
						txstate_reg <= STATE_IDLE;
						resend_count_reg <= 1'd0;
					end
					else begin
						txstate_reg <= STATE_BACKOFF;
						resend_count_reg <= resend_count_reg + 1'd1;
					end

					if (txmac_error_sig && resend_count_reg == PACKET_RESENDNUM_MAX[3:0]) begin
						err_toggle_reg <= ~err_toggle_reg;
					end
				end
			end

			// 続行不可能のエラーが発生(復帰はリセット)
			STATE_ABORT : begin
			end

			endcase
		end
	end

	assign cancel_resend = (!IGNORE_COLLISION_DETECT && err_toggle_reg);
	assign error_header = (txstate_reg == STATE_ABORT);

	assign rxpause_ack = (rxpause_req_sig && txstate_reg == STATE_BACKOFF);

	assign txfifo_update = (txstate_reg == STATE_RESEND && tx_ready_sig && (!txmac_error_sig || resend_count_reg == PACKET_RESENDNUM_MAX[3:0]));
	assign update_blocknum_sig = memfifo_addr_reg[8:FIFO_BLOCKSIZE_BITWIDTH-2];
	assign txfifo_blocknum = (memfifo_addr_reg[(FIFO_BLOCKSIZE_BITWIDTH-2)-1:0])? update_blocknum_sig + 1'd1 : update_blocknum_sig;
	assign txfifo_address = {memfifo_addr_reg, 2'b00};

	assign tx_valid_sig = (txstate_reg == STATE_TXDATA);
	assign tx_data_sig = (!byte_sel_reg)? txfifo_readdata[7:0] : memfifo_data_reg[15:8];
	assign tx_sop_sig = tx_sop_reg;
	assign tx_eop_sig = tx_eop_reg;


	// バックオフタイマー 

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			clkdiv_count_reg <= 1'd0;
			wait_count_reg <= 1'd0;
		end
		else begin
			if (sel_speed10m) begin
				if (!clkdiv_count_reg) begin
					clkdiv_count_reg <= 4'd9;
				end
				else begin
					clkdiv_count_reg <= clkdiv_count_reg - 1'd1;
				end
			end
			else begin
				clkdiv_count_reg <= 4'd0;
			end

			if (rxpause_req_sig && txstate_reg == STATE_BACKOFF) begin
				wait_count_reg <= {rxpause_value, 8'h00};
			end
			else if (txmac_error_sig && tx_ready_sig && txstate_reg == STATE_RESEND && resend_count_reg != PACKET_RESENDNUM_MAX[3:0]) begin
				wait_count_reg <= {wait_value_sig, 8'h00};
			end
			else if (!clkdiv_count_reg && wait_count_reg) begin
				wait_count_reg <= wait_count_reg - BACKOFF_TIMESLOT_UNIT[7:0];
			end
		end
	end

	assign wait_done_sig = ((IGNORE_COLLISION_DETECT && !ACCEPT_PAUSE_FRAME) || (!rxpause_req_sig && !wait_count_reg));


	// 再送待ち時間 

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			lfsr_reg <= {10{1'b1}};
		end
		else begin
			lfsr_reg <= {1'b0, lfsr_reg[9:1]} ^ ((lfsr_reg[0])? 10'b10_0100_0000 : 10'd0);
		end
	end

	assign wait_value_sig =
			(resend_count_reg == 4'd0 )? {15'b0, lfsr_reg[0]} :
			(resend_count_reg == 4'd1 )? {14'b0, lfsr_reg[1:0]} :
			(resend_count_reg == 4'd2 )? {13'b0, lfsr_reg[2:0]} :
			(resend_count_reg == 4'd3 )? {12'b0, lfsr_reg[3:0]} :
			(resend_count_reg == 4'd4 )? {11'b0, lfsr_reg[4:0]} :
			(resend_count_reg == 4'd5 )? {10'b0, lfsr_reg[5:0]} :
			(resend_count_reg == 4'd6 )? { 9'b0, lfsr_reg[6:0]} :
			(resend_count_reg == 4'd7 )? { 8'b0, lfsr_reg[7:0]} :
			(resend_count_reg == 4'd8 )? { 7'b0, lfsr_reg[8:0]} :
			{6'b0, lfsr_reg};



endmodule

`default_nettype wire
