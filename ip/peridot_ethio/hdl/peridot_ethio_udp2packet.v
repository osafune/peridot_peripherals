// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / UDP to Packet Transaction
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/08/19 -> 2022/09/21
//            : 2022/09/23 (FIXED)
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
// RXFIFOに積まれるパケットは、受信時にARPリクエスト(全MAC/自分IP宛),ICMPエコー要求(フラグメント無し/自分IP宛),
// UDP/IP(フラグメント無し/自分IP宛/自分ポート宛)のみにフィルタリングされている。
// 
// UDPペイロード長 = IPヘッダのLENフィールド - 28 とみなす（UDPヘッダのLENフィールドは無視する）。
//
// IPヘッダ、ICMPヘッダのチェックサムは誤りがないものとする。
// UDPヘッダのチェックサムはリクエスト側は無視される。
// レスポンス側は ENABLE_UDP_CHECKSUM = 1 のときチェックサムを計算する。
//

// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_ethio_udp2packet #(
	parameter RXFIFO_BLOCKNUM_BITWIDTH	= 6,	// 受信FIFOブロック数のビット値 (2^nで個数を指定) : 4～
	parameter TXFIFO_BLOCKNUM_BITWIDTH	= 6,	// 送信FIFOブロック数のビット値 (2^nで個数を指定) : 4～
	parameter FIFO_BLOCKSIZE_BITWIDTH	= 6,	// ブロックサイズ幅ビット値 (2^nでバイトサイズを指定) : 2～
	parameter UDPPAYLOAD_LENGTH_MAX		= 1472,	// 最大UDPペイロード長(512～1472, 1500-(IPヘッダ+UDPヘッダ))
	parameter ENABLE_UDP_CHECKSUM		= 1		// 1=UDPのチェックサムを行う 
) (
	input wire			reset,
	input wire			clk,
	input wire			enable,			// 1=パケット処理イネーブル 
	output wire			busy,			// パケット処理中ビジーフラグ 

	input wire  [47:0]	macaddr,		// 自分のMACアドレス 
	input wire  [31:0]	ipaddr,			// 自分のIPアドレス 
	input wire  [15:0]	udp_port,		// 自分のUDPポート 

	// 受信FIFOインターフェース 
	input wire			rxfifo_ready,
	output wire			rxfifo_update,
	output wire [RXFIFO_BLOCKNUM_BITWIDTH-1:0] rxfifo_blocknum,
	input wire			rxfifo_empty,
	output wire [10:0]	rxfifo_address,
	input wire  [31:0]	rxfifo_readdata,

	// 送信FIFOインターフェース 
	input wire			txfifo_ready,
	output wire			txfifo_update,
	output wire [TXFIFO_BLOCKNUM_BITWIDTH-1:0] txfifo_blocknum,
	input wire  [TXFIFO_BLOCKNUM_BITWIDTH-1:0] txfifo_free,
	output wire [10:0]	txfifo_address,
	output wire [31:0]	txfifo_writedata,
	output wire [3:0]	txfifo_writeenable,

	// Avalon-ST Sourceインターフェース(UDPリクエストペイロード) 
	input wire			out_ready,
	output wire			out_valid,
	output wire [7:0]	out_data,
	output wire			out_sop,
	output wire			out_eop,

	// Avalon-ST Sinkインターフェース(UDPレスポンスペイロード) 
	output wire			in_ready,
	input wire			in_valid,
	input wire [7:0]	in_data,
	input wire			in_sop,
	input wire			in_eop,
	input wire			in_error	// eop時にアサートすると応答パケットを破棄する 
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam	STATE_RXIDLE	= 5'd0,
				STATE_RXSTART1	= 5'd1,
				STATE_RXSTART2	= 5'd2,
				STATE_RXARP		= 5'd3,
				STATE_RXIP		= 5'd4,
				STATE_RXICMP	= 5'd5,
				STATE_RXUDP		= 5'd6,
				STATE_RXPAYLOAD	= 5'd7,
				STATE_RXDONE	= 5'd31;

	localparam	STATE_TXIDLE	= 5'd0,
				STATE_TXHEADER	= 5'd1,
				STATE_TXPAYLOAD	= 5'd2,
				STATE_TXUDPEND	= 5'd3,
				STATE_TXUDPLEN	= 5'd4,
				STATE_TXIPLEN	= 5'd5,
				STATE_TXIPSUM	= 5'd6,
				STATE_TXCLOSE	= 5'd7,
				STATE_TXDONE	= 5'd31;

	localparam RX_SOP_BYTEADDR		= 20 + 8;		// UDPペイロード先頭のオフセット(IPヘッダ先頭から) 
	localparam RX_EOP_DATACOUNT		= 20 + 8 + 1;	// UDPペイロード最後のデータカウント値 
	localparam TX_PACKET_BYTENUM	= (36 + UDPPAYLOAD_LENGTH_MAX + (2 ** FIFO_BLOCKSIZE_BITWIDTH) - 1) / (2 ** FIFO_BLOCKSIZE_BITWIDTH);
	localparam TX_PACKET_BLOCKNUM	= TX_PACKET_BYTENUM[TXFIFO_BLOCKNUM_BITWIDTH-1:0];
	localparam TX_ARPDATANUM		= 36 - 8;		// ARPパケット長 
	localparam TX_DATANUM_MAX		= UDPPAYLOAD_LENGTH_MAX - 1;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 
	wire			clock_sig = clk;		// モジュール内部駆動クロック 

	reg  [4:0]		rxstate_reg;
	reg				arp_reg;
	reg				udp_reg;
	reg				no_payload_reg;
	reg				rxaddr_inv_reg;
	reg  [10:0]		rxdatanum_reg;
	reg  [1:0]		rxfifo_hold_reg;
	reg  [31:8]		rx_data_reg;
	reg				out_sop_reg;
	reg  [8:0]		rxfifo_addr_reg;
	reg  [1:0]		rxdata_ena_reg;
	reg  [RXFIFO_BLOCKNUM_BITWIDTH-1:0] rxfifo_blocknum_reg;
	wire [10:0]		icmp_endaddr_sig;
	wire [10:0]		total_rxbytenum_sig;
	wire [RXFIFO_BLOCKNUM_BITWIDTH-1:0] update_rxblocknum_sig, rxfifo_blocknum_sig;
	wire [31:0]		readdata_sig;
	wire			readdatavalid_sig;

	reg  [4:0]		txstate_reg;
	reg				header_reg;
	reg				err_reject_reg;
	reg				packet_reg;
	reg  [10:0]		txdatanum_reg;
	reg  [15:0]		databuff_reg;
	reg  [31:0]		writedata_reg;
	reg  [3:0]		writeenable_reg;
	reg  [8:0]		txfifo_addr_reg;
	reg  [TXFIFO_BLOCKNUM_BITWIDTH-1:0] txfifo_blocknum_reg;
	wire			txstate_ready_sig;
	wire [10:0]		txdatanum_add_sig;
	wire [TXFIFO_BLOCKNUM_BITWIDTH-1:0] update_txblocknum_sig, txfifo_blocknum_sig;
	wire [8:0]		txfifo_addr_sig;
	wire [31:0]		txfifo_data_sig;
	wire [3:0]		txfifo_writeena_sig, byte_ena_sig;
	wire [15:0]		sum_data_sig, sum_result_sig;

	reg  [15:0]		sumadd_buff_reg;
	reg  [15:0]		udpsum_reg;
	wire [15:0]		udpsum_lenadd_sig, udpsum_result_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	// 受信パケット処理 

	assign busy = (rxstate_reg != STATE_RXIDLE || txstate_reg != STATE_TXIDLE);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			rxstate_reg <= STATE_RXIDLE;
			arp_reg <= 1'b0;
			udp_reg <= 1'b0;
			no_payload_reg <= 1'b0;
			out_sop_reg <= 1'b0;
			rxaddr_inv_reg <= 1'b0;
			rxdata_ena_reg <= 2'b00;
		end
		else begin
			case (rxstate_reg)

			// RXFIFOにパケットが到着していて、TXFIFOに最大パケット長分の空きがあればスタート 
			STATE_RXIDLE : begin
				if (enable && rxfifo_ready && !rxfifo_empty && txstate_ready_sig) begin
					rxstate_reg <= STATE_RXSTART1;
				end

				rxfifo_hold_reg <= 2'd0;
			end

			// キューされたパケットデータの取り出し : RXFIFO[0]
			STATE_RXSTART1 : begin
				rxstate_reg <= STATE_RXSTART2;
				arp_reg <= 1'b0;
				udp_reg <= 1'b0;
			end
			STATE_RXSTART2 : begin
				rxfifo_blocknum_reg <= rxfifo_blocknum_sig;

				if (rxfifo_readdata[16]) begin
					rxstate_reg <= STATE_RXARP;
					arp_reg <= 1'b1;
				end
				else if (rxfifo_readdata[21]) begin
					rxstate_reg <= STATE_RXIP;
				end
				else if (rxfifo_readdata[23]) begin
					rxstate_reg <= STATE_RXIP;
					udp_reg <= 1'b1;
				end
				else begin
					rxstate_reg <= STATE_RXDONE;
				end
			end

			// Ethernet v2ヘッダ＋ARPリクエスト : RXFIFO[1]～RXFIFO[7]([5]で2クロック待つ)
			STATE_RXARP : begin
				if (rxfifo_addr_reg[2:0] == 3'd7) begin
					rxstate_reg <= STATE_RXDONE;
				end

				if (rxfifo_addr_reg[2:0] == 3'd4) begin
					rxfifo_hold_reg <= 2'd2;
				end
				else if (rxfifo_hold_reg) begin
					rxfifo_hold_reg <= rxfifo_hold_reg + 1'd1;
				end
			end

			// Ethernet v2ヘッダ＋IPヘッダ＋ICMP,UDPヘッダ : RXFIFO[1]～[9]
			STATE_RXIP : begin
				if (rxfifo_addr_reg[3:0] == 4'd9) begin
					if (no_payload_reg) begin
						rxstate_reg <= STATE_RXDONE;
					end
					else if (udp_reg) begin
						rxstate_reg <= STATE_RXUDP;
						rxfifo_hold_reg <= 2'd2;
					end
					else begin
						rxstate_reg <= STATE_RXICMP;
					end
				end

				// IPパケット長を取得 : RXFIFO[3] + readdata latency 2
				if (rxfifo_addr_reg[2:0] == 3'd5) begin
					rxdatanum_reg <= {rxfifo_readdata[18:16], rxfifo_readdata[31:24]};
				end

				no_payload_reg <= (rxdatanum_reg == 11'd28);	// ICMPメッセージまたはUDPペイロードがない 

				// 送信元IP(RXFIFO[6])と受信先IP(RXFIFO[7])の読み出し順を入れ替え 
				if (rxfifo_addr_reg[2:0] == 3'd5) begin
					rxaddr_inv_reg <= 1'b1;
				end
				else if (rxfifo_addr_reg[2:0] == 3'd7) begin
					rxaddr_inv_reg <= 1'b0;
				end
			end

			// ICMPエコー要求パケット(メッセージ部) 
			STATE_RXICMP : begin
				if (rxfifo_addr_reg == icmp_endaddr_sig[10:2]) begin
					rxstate_reg <= STATE_RXDONE;
				end
			end

			// UDPパケット(ペイロード部先頭データ待ち) 
			STATE_RXUDP : begin
				rxfifo_hold_reg <= rxfifo_hold_reg + 1'd1;

				if (rxfifo_hold_reg == 2'd3) begin
					rxstate_reg <= STATE_RXPAYLOAD;
					out_sop_reg <= 1'b1;
				end
			end

			// UDPペイロード 
			STATE_RXPAYLOAD : begin
				if (out_ready) begin
					out_sop_reg <= 1'b0;
					rxdatanum_reg <= rxdatanum_reg - 1'd1;

					if (rxdatanum_reg == RX_EOP_DATACOUNT[10:0]) begin
						rxstate_reg <= STATE_RXDONE;
					end

					rxfifo_hold_reg <= rxfifo_hold_reg + 1'd1;

					if (!rxfifo_hold_reg) begin
						rx_data_reg <= rxfifo_readdata[31:8];
					end
					else begin
						rx_data_reg <= {8'h00, rx_data_reg[31:16]};
					end
				end

			end

			// RXFIFOのクローズ処理 
			STATE_RXDONE : begin
				rxstate_reg <= STATE_RXIDLE;
			end

			endcase


			// 受信FIFOアドレスカウンタ 
			if (rxstate_reg == STATE_RXIDLE) begin
				rxfifo_addr_reg <= 1'd0;
			end
			else if (!rxfifo_hold_reg && !(rxstate_reg == STATE_RXPAYLOAD && !out_ready)) begin
				rxfifo_addr_reg <= rxfifo_addr_reg + 1'd1;
			end

			// 受信FIFO読み出しデータイネーブル信号(2クロックレイテンシ) 
			if (rxstate_reg == STATE_RXSTART2 || rxstate_reg == STATE_RXARP || rxstate_reg == STATE_RXIP || rxstate_reg == STATE_RXICMP) begin
				rxdata_ena_reg[0] <= 1'b1;
			end
			else begin
				rxdata_ena_reg[0] <= 1'b0;
			end
			rxdata_ena_reg[1] <= rxdata_ena_reg[0];
		end
	end

	assign icmp_endaddr_sig = rxdatanum_reg + 4'd11;	// 6(SA) + 2(TYPE) + 3(padding)

	assign total_rxbytenum_sig = rxfifo_readdata[10:0] + 11'd4;
	assign update_rxblocknum_sig = total_rxbytenum_sig[10:FIFO_BLOCKSIZE_BITWIDTH];
	assign rxfifo_blocknum_sig = (total_rxbytenum_sig[FIFO_BLOCKSIZE_BITWIDTH-1:0])? update_rxblocknum_sig + 1'd1 : update_rxblocknum_sig;

	assign rxfifo_update = (rxstate_reg == STATE_RXDONE);
	assign rxfifo_blocknum = rxfifo_blocknum_reg;
	assign rxfifo_address = {rxfifo_addr_reg ^ {8'b0, rxaddr_inv_reg}, 2'b00};

	assign readdata_sig = rxfifo_readdata;
	assign readdatavalid_sig = rxdata_ena_reg[1];

	assign out_valid = (rxstate_reg == STATE_RXPAYLOAD);
	assign out_data = (!rxfifo_hold_reg)? rxfifo_readdata[7:0] : rx_data_reg[15:8];
	assign out_sop = out_sop_reg;
	assign out_eop = (rxdatanum_reg == RX_EOP_DATACOUNT[10:0]);


	// 返信パケット処理 

	assign txstate_ready_sig = (txstate_reg == STATE_TXIDLE && txfifo_ready && txfifo_free >= TX_PACKET_BLOCKNUM);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			txstate_reg <= STATE_TXIDLE;
			writeenable_reg <= 4'b0000;
		end
		else begin
			case (txstate_reg)

			// 受信処理が動作し始めたらスタート 
			STATE_TXIDLE : begin
				if (rxstate_reg == STATE_RXSTART1) begin
					txstate_reg <= STATE_TXHEADER;
					header_reg <= 1'b1;
					txfifo_addr_reg <= 1'd1;
				end

				err_reject_reg <= 1'b0;
				packet_reg <= 1'b0;
				txdatanum_reg <= 1'd0;
			end

			// ARP,ICMP,UDP/IPヘッダ部の受信 
			STATE_TXHEADER : begin
				writeenable_reg <= {4{readdatavalid_sig}};

				if (writeenable_reg[0]) begin
					txfifo_addr_reg <= txfifo_addr_reg + 1'd1;

					if (!readdatavalid_sig) begin
						if (udp_reg) begin
							if (!no_payload_reg) begin
								txstate_reg <= STATE_TXPAYLOAD;
							end
							else begin
								txstate_reg <= STATE_TXIDLE;	// ペイロードのないUDPなら応答パケット破棄 
							end
						end
						else begin
							txstate_reg <= STATE_TXCLOSE;

							if (arp_reg) begin
								txdatanum_reg <= TX_ARPDATANUM[10:0];
							end
							else begin
								txdatanum_reg <= rxdatanum_reg;
							end
						end
					end

					if (txfifo_addr_reg[3:0] == 4'd9) begin
						header_reg <= 1'b0;
					end
				end

				if (header_reg) begin
					if (arp_reg) begin
						// ARPパケットの組み替え 
						case (txfifo_addr_reg[3:0])
						4'd3 : writedata_reg <= {8'h02, readdata_sig[23:0]};			// ARP要求(0x0001)をARP応答(0x0002)へ 
						4'd4 : writedata_reg <= {macaddr[23:16], macaddr[31:24], macaddr[39:32], macaddr[47:40]};
						4'd5 : {databuff_reg, writedata_reg} <= {ipaddr[7:0], ipaddr[15:8], ipaddr[23:16], ipaddr[31:24], macaddr[7:0], macaddr[15:8]};
						4'd6 : {databuff_reg, writedata_reg} <= {readdata_sig, databuff_reg};
						4'd7 : {databuff_reg, writedata_reg} <= {readdata_sig, databuff_reg};
						4'd8 : writedata_reg <= {readdata_sig[15:0], databuff_reg};
						default : writedata_reg <= readdata_sig;
						endcase
					end
					else if (udp_reg) begin
						// UDP/IPパケットの組み替え 
						case (txfifo_addr_reg[3:0])
						4'd2 : {databuff_reg, writedata_reg} <= {readdata_sig[23:16], readdata_sig[31:24], readdata_sig};	// IPパケット長を読み込み 
						4'd4 : {databuff_reg, writedata_reg} <= {sum_result_sig, readdata_sig};								// チェックサムの補正 
						4'd7 : writedata_reg <= {readdata_sig[15:0], {udp_port[7:0], udp_port[15:8]}};						// 送信元ポートを宛先へ 
						default : writedata_reg <= readdata_sig;
						endcase
					end
					else begin
						// ICMP/IPパケットの組み替え 
						case (txfifo_addr_reg[3:0])
						4'd1 : {databuff_reg, writedata_reg} <= {readdata_sig[23:16], readdata_sig[31:24], readdata_sig};	// 0x0800を読み込み 
						4'd7 : writedata_reg <= {sum_result_sig[7:0], sum_result_sig[15:8], readdata_sig[15:0] ^ 16'h8};	// エコー要求(0x08)をエコー応答(0x00)へ 
						default : writedata_reg <= readdata_sig;
						endcase
					end
				end
				else begin
					writedata_reg <= readdata_sig;
				end
			end


			// UDPレスポンスパケットのペイロード部を受信 
			STATE_TXPAYLOAD : begin
				if (in_valid && in_sop) begin
					packet_reg <= 1'b1;
				end

				if (in_valid && (packet_reg || in_sop)) begin
					txdatanum_reg <= txdatanum_reg + 1'd1;

					if (txdatanum_reg[1:0] == 2'd3) begin
						txfifo_addr_reg <= txfifo_addr_reg + 1'd1;
					end

					if (txdatanum_reg == TX_DATANUM_MAX[10:0]) begin
						err_reject_reg <= 1'b1;
					end

					if (in_eop) begin
						if (!err_reject_reg && !in_error) begin
							txstate_reg <= STATE_TXUDPEND;
						end
						else begin	// ペイロード長が規定値以上またはeop時にin_errorアサートなら応答パケット破棄 
							txstate_reg <= STATE_TXIDLE;
						end
					end
				end
			end

			// UDPレスポンスパケットクローズ処理 
			STATE_TXUDPEND : begin
				txstate_reg <= STATE_TXUDPLEN;
				txdatanum_reg <= txdatanum_reg + 11'd8;
				writeenable_reg <= 4'b1111;
			end
			STATE_TXUDPLEN : begin
				txstate_reg <= STATE_TXIPLEN;
				txdatanum_reg <= txdatanum_reg + 11'd20;
				writeenable_reg <= 4'b1100;
			end
			STATE_TXIPLEN : begin
				txstate_reg <= STATE_TXIPSUM;
				databuff_reg <= sum_result_sig;
			end
			STATE_TXIPSUM : begin
				txstate_reg <= STATE_TXCLOSE;
				writeenable_reg <= 4'b0000;
			end

			// TXFIFOのクローズ処理 
			STATE_TXCLOSE : begin
				txstate_reg <= STATE_TXDONE;
				txdatanum_reg <= txdatanum_reg + 11'd8;
				writeenable_reg <= 4'b1111;
				txfifo_blocknum_reg <= txfifo_blocknum_sig;
			end
			STATE_TXDONE : begin
				txstate_reg <= STATE_TXIDLE;
				writeenable_reg <= 4'b0000;
			end

			endcase
		end
	end

	assign update_txblocknum_sig = txfifo_addr_reg[8:FIFO_BLOCKSIZE_BITWIDTH-2];
	assign txfifo_blocknum_sig = (txfifo_addr_reg[(FIFO_BLOCKSIZE_BITWIDTH-2)-1:0])? update_txblocknum_sig + 1'd1 : update_txblocknum_sig;

	assign txfifo_addr_sig =
				(txstate_reg == STATE_TXUDPLEN)? 9'd9 :		// UDPチェックサム/UDPパケット長 : TXFIFO[9]
				(txstate_reg == STATE_TXIPLEN)? 9'd3 :		// IPパケット長  : TXFIFO[3]
				(txstate_reg == STATE_TXIPSUM)? 9'd5 :		// IPパケットSUM : TXFIFO[5]
				(txstate_reg == STATE_TXDONE)? 9'd0 :		// TXFIFOヘッダ  : TXFIFO[0]
				txfifo_addr_reg;

	assign txfifo_data_sig =
				(txstate_reg == STATE_TXPAYLOAD)? {4{in_data}} :
				(txstate_reg == STATE_TXUDPLEN)? {udpsum_result_sig[7:0], udpsum_result_sig[15:8], txdatanum_reg[7:0], 5'b0, txdatanum_reg[10:8]} :
				(txstate_reg == STATE_TXIPLEN)? {txdatanum_reg[7:0], 5'b0, txdatanum_reg[10:8], {16{1'bx}}} :
				(txstate_reg == STATE_TXIPSUM)? {databuff_reg[7:0], databuff_reg[15:8], {16{1'bx}}} :
				(txstate_reg == STATE_TXDONE)? {21'b0, txdatanum_reg} :
				writedata_reg;

	assign byte_ena_sig =
				(in_valid && txdatanum_reg[1:0] == 2'd0)? 4'b0001 :
				(in_valid && txdatanum_reg[1:0] == 2'd1)? 4'b0010 :
				(in_valid && txdatanum_reg[1:0] == 2'd2)? 4'b0100 :
				(in_valid && txdatanum_reg[1:0] == 2'd3)? 4'b1000 :
				4'b0000;
	assign txfifo_writeena_sig =
				(txstate_reg == STATE_TXPAYLOAD)? byte_ena_sig :
				writeenable_reg;

	assign txfifo_update = (txstate_reg == STATE_TXDONE);
	assign txfifo_blocknum = txfifo_blocknum_reg;
	assign txfifo_address = {txfifo_addr_sig, 2'b00};
	assign txfifo_writedata = txfifo_data_sig;
	assign txfifo_writeenable = txfifo_writeena_sig;

	assign in_ready = (txstate_reg == STATE_TXPAYLOAD);


	// IPヘッダ,ICMPチェックサム再計算 

	function [15:0] checksum_adder (input [15:0] sum1, input [15:0] sum2);
		reg [16:0]	temp_sum;
	begin
		temp_sum = sum1 + sum2;
		checksum_adder = temp_sum[15:0] + temp_sum[16];
	end
	endfunction

	assign sum_data_sig =
				(txstate_reg == STATE_TXHEADER)? {readdata_sig[23:16], readdata_sig[31:24]} :
				~{5'b0, txdatanum_reg};
	assign sum_result_sig = checksum_adder(databuff_reg, sum_data_sig);


	// UDPチェックサム計算 

	always @(posedge clock_sig) begin
		case (txstate_reg)
		STATE_TXHEADER : begin
			if (txfifo_addr_reg[3:0] == 4'd6) begin
				sumadd_buff_reg <= {readdata_sig[23:16], readdata_sig[31:24]};			// 送信元IPアドレス(下位ワードを一時保存)
			end

			case (txfifo_addr_reg[3:0])
			4'd3 : udpsum_reg <= checksum_adder(ipaddr[31:16], ipaddr[15:0]);			// 自局IPアドレス 
			4'd4 : udpsum_reg <= checksum_adder(udpsum_reg, udp_port);					// 自局ポート 
			4'd5 : udpsum_reg <= checksum_adder(udpsum_reg, 16'h0011 + 16'd8 + 16'd8);	// UDPタイプ + ヘッダバイト数(ペイロードデータ長分は後で加算) 
			4'd6 : udpsum_reg <= checksum_adder(udpsum_reg, {readdata_sig[7:0], readdata_sig[15:8]});	// 送信元IPアドレス(上位ワード)
			4'd7 : udpsum_reg <= checksum_adder(udpsum_reg, {readdata_sig[7:0], readdata_sig[15:8]});	// 送信元ポート 
			4'd8 : udpsum_reg <= checksum_adder(udpsum_reg, sumadd_buff_reg);							// 送信元IPアドレス(下位ワード)
			endcase
		end

		STATE_TXPAYLOAD : begin
			if (in_valid && (packet_reg || in_sop)) begin
				udpsum_reg <= checksum_adder(udpsum_reg, (txdatanum_reg[0])? {8'h00, in_data} : {in_data, 8'h00});
			end
		end

		STATE_TXUDPEND : begin
			udpsum_reg <= (udpsum_lenadd_sig == 16'hffff)? udpsum_lenadd_sig : ~udpsum_lenadd_sig;
		end
		endcase
	end

	assign udpsum_lenadd_sig = checksum_adder(udpsum_reg, {4'b0, txdatanum_reg, 1'b0});
	assign udpsum_result_sig = (!ENABLE_UDP_CHECKSUM)? 16'h0000 : udpsum_reg;



endmodule

`default_nettype wire
