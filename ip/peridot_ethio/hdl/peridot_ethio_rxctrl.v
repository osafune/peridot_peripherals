// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / Packet Receiver Control
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/08/01 -> 2022/08/19
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
// MEMFIFOに格納されるデータフォーマットは以下の通り
//   +0 : FIFOヘッダ
//          bit31-24: reserved(all 0)
//          bit23   : UDPパケット(udp_port≠0ならポート一致もチェック)
//          bit22   : TCPパケット(ACCEPT_TCP_PACKETS=1で有効)
//          bit21   : ICMPエコー要求パケット(IGNORE_ICMP_ECHO_CHECK=1なら全てのICMPタイプ)
//          bit20   : ブロードキャストアドレスで来たIPパケット(ACCEPT_BROADCAST_IPADDR=1で有効)
//          bit19   : 自分のIPアドレス宛に来たARPまたはIPパケット(ipaddr≠0で有効)
//          bit18   : フラグメント化されたIPパケット(ACCEPT_FRAGMENT_PACKETS=1で有効)
//          bit17   : IPパケット 
//          bit16   : ARPリクエストパケット(IGNORE_ARP_REQUEST_CHECK=1なら全てのARPオペコード)
//          bit15-11: reserved(all 0)
//          bit10-0 : データグラムのバイト数len
//   +4 : データグラム0～3(リトルエンディアン)
//   +8 : データグラム4～5
//    :
//   +n : データグラム(n-1)*4～(len-1)
//
// 占有ブロック数はFIFOヘッダ分が加算されるため、以下のようになる 
//   blocknum = (len + 4 + (BLOCKSIZE - 1)) / BLOCKSIZE
//

// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_ethio_rxctrl #(
	parameter PACKET_LENGTH_MAX			= 1508,	// 最大パケット長(512～1508, DA+TYPE+データグラム)
	parameter FIFO_BLOCKNUM_BITWIDTH	= 6,	// FIFOブロック数のビット値 (2^nで個数を指定) : 4～
	parameter FIFO_BLOCKSIZE_BITWIDTH	= 6,	// ブロックサイズ幅ビット値 (2^nでバイトサイズを指定) : 2～
	parameter ACCEPT_PAUSE_FRAME		= 0,	// 1=PAUSEフレームの処理をする(0の時はPAUSEフレーム送信をしない)
	parameter IGNORE_LENGTH_CHECK		= 0,	// 1=パケット長チェックを無視する 
	parameter IGNORE_PACKET_FILTERING	= 0,	// 1=パケットフィルタを無視する(全てのパケットをキューする) 
	parameter ACCEPT_ARP_PACKETS		= 1,	// 1=ARPパケットを受け入れる 
	parameter ACCEPT_FRAGMENT_PACKETS	= 0,	// 1=フラグメント化されたIPパケットを受け入れる 
	parameter ACCEPT_BROADCAST_IPADDR	= 1,	// 1=ブロードキャストアドレスのIPパケットを受け入れる 
	parameter ACCEPT_ICMP_PACKETS		= 1,	// 1=ICMPパケットを受け入れる 
	parameter ACCEPT_UDP_PACKETS		= 1,	// 1=UDPパケットを受け入れる 
	parameter ACCEPT_TCP_PACKETS		= 0,	// 1=TCPパケットを受け入れる 
	parameter IGNORE_ARP_REQUEST_CHECK	= 0,	// 1=ARPパケットのオペコードチェックを無視する 
	parameter IGNORE_ICMP_ECHO_CHECK	= 0		// 1=ICMPパケットのタイプチェックを無視する 
) (
	input wire			reset,
	input wire			clk,
	output wire			reject_overflow,	// 最大パケット長以上またはFIFO_FULL,FIFO非READY時SOPでパケット破棄が起こるごとに反転する 
	input wire  [7:0]	pause_less,			// フレーム受信完了時にFIFO空きがこの値以下ならPAUSE送信 
	input wire  [15:0]	pause_value,		// リクエストする待ち時間 
	input wire  [31:0]	ipaddr,				// 自分のIPアドレス(0の場合は全てのIPアドレスを受信)
	input wire  [31:0]	subnet,				// サブネットマスク(リミテッドブロードキャストのみ使う場合は0にする) 
	input wire  [15:0]	udp_port,			// UDPポートの指定(0の場合は全てのポートを受信)

	// PAUSEフレーム制御 
	output wire			txpause_req,		// PAUSEフレーム送信 
	output wire [15:0]	txpause_value,
	input wire			txpause_ack,

	// MAC受信データストリーム 
	output wire			rxmac_ready,
	input wire  [7:0]	rxmac_data,
	input wire			rxmac_valid,
	input wire			rxmac_sop,
	input wire			rxmac_eop,
	input wire			rxmac_error,		// 1=フレームエラーまたはリジェクト要求発生, EOPのとき有効 

	// 受信FIFOインターフェース 
	input wire			rxfifo_ready,
	output wire			rxfifo_update,
	output wire [FIFO_BLOCKNUM_BITWIDTH-1:0] rxfifo_blocknum,
	input wire  [FIFO_BLOCKNUM_BITWIDTH-1:0] rxfifo_free,
	output wire [10:0]	rxfifo_address,
	output wire [31:0]	rxfifo_writedata,
	output wire [3:0]	rxfifo_writeenable,
	input wire			rxfifo_writeerror
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam	STATE_INIT		= 5'd0,
				STATE_IDLE		= 5'd1,
				STATE_RXDATA	= 5'd2,
				STATE_CLOSE		= 5'd31;

	localparam PAUSE_LESS_BITWIDTH = (FIFO_BLOCKNUM_BITWIDTH < 8)? FIFO_BLOCKNUM_BITWIDTH : 8;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 
	wire			clock_sig = clk;		// モジュール内部駆動クロック 

	reg  [4:0]		rxstate_reg;
	reg  [10:0]		data_count_reg;
	reg				err_toggle_reg;
	reg				err_write_reg;

	wire [10:0]		total_bytenum_sig;
	wire [FIFO_BLOCKNUM_BITWIDTH-1:0] update_blocknum_sig;
	wire [3:0]		writeenable_sig;
	wire [31:0]		fifo_header_sig;
	wire [15:0]		packet_status_sig;

	wire			pause_latch_sig, pause_check_sig;
	wire [FIFO_BLOCKNUM_BITWIDTH-1:0] pause_less_sig;
	wire [15:0]		pause_value_sig;
	reg				pause_req_reg, pause_check_reg;

	wire			reject_sig, accept_sig;
	wire			ipaddr_ena_sig;
	wire [7:0]		ipaddr_byte_sig;
	wire [31:0]		broadaddr_sig;
	wire [7:0]		broadaddr_byte_sig;
	wire			udpport_ena_sig;
	reg				done_reg;
	reg				arp_reg, ip_reg, icmp_reg, tcp_reg, udp_reg;
	reg				fragment_reg, ipbyte_valid_reg, ipaddr_own_reg, ipaddr_broad_reg;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	// MAC-RXストリームインターフェース 

//	assign rxmac_ready = (rxstate_reg == STATE_IDLE || rxstate_reg == STATE_RXDATA);
	assign rxmac_ready = 1'b1;


	// フレーム受信FSM 

	assign reject_sig = (!IGNORE_PACKET_FILTERING && !accept_sig);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			rxstate_reg <= STATE_INIT;
			data_count_reg <= 1'd0;
			err_toggle_reg <= 1'b0;
			err_write_reg <= 1'b0;
		end
		else begin
			case (rxstate_reg)

			STATE_INIT : begin
				if (rxfifo_ready) begin
					rxstate_reg <= STATE_IDLE;
				end
			end

			STATE_IDLE : begin
				if (rxmac_valid) begin
					if (rxmac_sop) begin
						rxstate_reg <= STATE_RXDATA;
					end
					else if (rxmac_eop) begin
						rxstate_reg <= STATE_INIT;
					end
				end
			end

			STATE_RXDATA : begin
				if (rxmac_valid && rxmac_eop) begin
					if (rxmac_error || reject_sig) begin
						rxstate_reg <= STATE_INIT;
					end
					else begin
						rxstate_reg <= STATE_CLOSE;
					end
				end
			end

			STATE_CLOSE : begin
				rxstate_reg <= STATE_INIT;
			end

			endcase


			// フレームデータカウンタ 
			if (rxstate_reg == STATE_INIT) begin
				data_count_reg <= 1'd0;
			end
			else if (rxmac_valid) begin
				data_count_reg <= data_count_reg + 1'd1;
			end

			// FIFO書き込みエラーフラグ 
			if (rxstate_reg == STATE_INIT) begin
				err_write_reg <= 1'b0;
			end
			else if (rxmac_valid) begin
				if (rxfifo_writeerror || (!IGNORE_LENGTH_CHECK && data_count_reg == PACKET_LENGTH_MAX[10:0])) begin
					err_write_reg <= 1'b1;
				end
			end

			// FIFOエラーフラグ 
			if ((rxstate_reg != STATE_IDLE && rxmac_valid && rxmac_sop) || (rxstate_reg == STATE_CLOSE && err_write_reg)) begin
				err_toggle_reg <= ~err_toggle_reg;
			end
		end
	end

	assign reject_overflow = err_toggle_reg;

	assign total_bytenum_sig = data_count_reg + 11'd4;
	assign update_blocknum_sig = total_bytenum_sig[10:FIFO_BLOCKSIZE_BITWIDTH];
	assign rxfifo_blocknum = (total_bytenum_sig[FIFO_BLOCKSIZE_BITWIDTH-1:0])? update_blocknum_sig + 1'd1 : update_blocknum_sig;
	assign rxfifo_update = (rxstate_reg == STATE_CLOSE && !err_write_reg);

	assign rxfifo_address = (rxstate_reg == STATE_CLOSE)? 11'h0 : {total_bytenum_sig[10:2], 2'b00};

	assign fifo_header_sig = {packet_status_sig, 5'b0, data_count_reg};
	assign rxfifo_writedata = (rxstate_reg == STATE_CLOSE)? fifo_header_sig : {4{rxmac_data}};

	assign writeenable_sig =
				(rxmac_valid && data_count_reg[1:0] == 2'd0)? 4'b0001 :
				(rxmac_valid && data_count_reg[1:0] == 2'd1)? 4'b0010 :
				(rxmac_valid && data_count_reg[1:0] == 2'd2)? 4'b0100 :
				(rxmac_valid && data_count_reg[1:0] == 2'd3)? 4'b1000 :
				4'b0000;
	assign rxfifo_writeenable = (rxstate_reg == STATE_CLOSE)? {4{~err_write_reg}} : writeenable_sig;


	// PAUSEフレーム処理 

	assign pause_less_sig = pause_less[PAUSE_LESS_BITWIDTH-1:0];

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			pause_req_reg <= 1'b0;
			pause_check_reg <= 1'b0;
		end
		else begin
			if (rxstate_reg == STATE_CLOSE && !err_write_reg) begin
				pause_check_reg <= 1'b1;
			end
			else begin
				pause_check_reg <= 1'b0;
			end

			if (pause_req_reg) begin
				if (txpause_ack) begin
					pause_req_reg <= 1'b0;
				end
			end
			else if (ACCEPT_PAUSE_FRAME && pause_check_reg && pause_less_sig > rxfifo_free) begin
				pause_req_reg <= 1'b1;
			end
		end
	end

	assign txpause_req = (ACCEPT_PAUSE_FRAME)? pause_req_reg : 1'b0;
	assign txpause_value = (ACCEPT_PAUSE_FRAME)? pause_value : 1'd0;


	// 受信フレームのチェック 

	assign ipaddr_ena_sig = (ipaddr)? 1'b1 : 1'b0;
	assign ipaddr_byte_sig =
				(data_count_reg[1:0] == 2'd0)? ipaddr[31:24] :	// +24,+32 : IPアドレス 0
				(data_count_reg[1:0] == 2'd1)? ipaddr[23:16] :	// +25,+33 : IPアドレス 1
				(data_count_reg[1:0] == 2'd2)? ipaddr[15: 8] :	// +26,+34 : IPアドレス 2
				(data_count_reg[1:0] == 2'd3)? ipaddr[ 7: 0] :	// +27,+35 : IPアドレス 3
				{8{1'bx}};

	assign broadaddr_sig = (ipaddr & subnet) | ~subnet;
	assign broadaddr_byte_sig =
				(data_count_reg[1:0] == 2'd0)? broadaddr_sig[31:24] :	// +24 : IPアドレス 0
				(data_count_reg[1:0] == 2'd1)? broadaddr_sig[23:16] :	// +25 : IPアドレス 1
				(data_count_reg[1:0] == 2'd2)? broadaddr_sig[15: 8] :	// +26 : IPアドレス 2
				(data_count_reg[1:0] == 2'd3)? broadaddr_sig[ 7: 0] :	// +27 : IPアドレス 3
				{8{1'bx}};

	assign udpport_ena_sig = (udp_port)? 1'b1 : 1'b0;

	always @(posedge clock_sig) begin
		if (rxstate_reg == STATE_INIT) begin
			done_reg <= 1'b0;
			arp_reg <= 1'b1;
			ip_reg <= 1'b1;
			fragment_reg <= 1'b1;
			ipbyte_valid_reg <= 1'b0;
			ipaddr_own_reg <= 1'b1;
			ipaddr_broad_reg <= 1'b1;
			icmp_reg <= 1'b0;
			tcp_reg <= 1'b0;
			udp_reg <= 1'b0;
		end
		else begin
			if (!done_reg && rxmac_valid) begin
				case (data_count_reg[4:0])

				// Ethernetフレーム タイプチェック 
				5'd6 : begin
					if (rxmac_data != 8'h08) begin
						arp_reg <= 1'b0;
						ip_reg <= 1'b0;
					end
				end
				5'd7 : begin
					if (rxmac_data != 8'h06) begin
						arp_reg <= 1'b0;
					end

					if (rxmac_data != 8'h00) begin
						ip_reg <= 1'b0;
					end
				end

				// IPパケットヘッダチェック 
				5'd8 : begin
					if (rxmac_data != 8'h45) begin
						ip_reg <= 1'b0;
					end
				end

				// ARPリクエストMACサイズ/IPサイズチェック 
				5'd12 : begin
					if (rxmac_data != 8'h06) begin
						arp_reg <= 1'b0;
					end
				end
				5'd13 : begin
					if (rxmac_data != 8'h04) begin
						arp_reg <= 1'b0;
					end
				end

				// IPパケットフラグメントチェック, ARPリクエストオペコードチェック 
				5'd14 : begin
					if (rxmac_data[5:0]) begin
						fragment_reg <= 1'b0;
					end
				end
				5'd15 : begin
					if (rxmac_data) begin
						fragment_reg <= 1'b0;
					end

					if (!IGNORE_ARP_REQUEST_CHECK && rxmac_data != 8'h01) begin
						arp_reg <= 1'b0;
					end
				end

				// IPサービスタイプチェック 
				5'd17 : begin
					if (rxmac_data == 8'h01) begin
						icmp_reg <= 1'b1;
					end

					if (rxmac_data == 8'h11) begin
						udp_reg <= 1'b1;
					end

					if (rxmac_data == 8'h06) begin
						tcp_reg <= 1'b1;
					end
				end

				// ICMPエコー要求チェック 
				5'd28 : begin
					if (!IGNORE_ICMP_ECHO_CHECK && rxmac_data != 8'h08) begin
						icmp_reg <= 1'b0;
					end
				end

				// UDPポートチェック 
				5'd30 : begin
					if (udpport_ena_sig && rxmac_data != udp_port[15:8]) begin
						udp_reg <= 1'b0;
					end
				end
				5'd31 : begin
					if (udpport_ena_sig && rxmac_data != udp_port[7:0]) begin
						udp_reg <= 1'b0;
					end
				end

				default : begin
				end

				endcase


				// ヘッダチェック終了 
				if (data_count_reg[5:0] == 6'd35) begin
					done_reg <= 1'b1;
				end

				// IPアドレスチェック 
				if ((arp_reg && data_count_reg[4:0] == 5'd31) || (ip_reg && data_count_reg[4:0] == 5'd23)) begin
					ipbyte_valid_reg <= 1'b1;
				end
//				else if (data_count_reg[5:0] == 6'd35 || data_count_reg[4:0] == 5'd27) begin
				else if (data_count_reg[1:0] == 2'd3) begin
					ipbyte_valid_reg <= 1'b0;
				end

				if (ipbyte_valid_reg && rxmac_data != ipaddr_byte_sig) begin
					ipaddr_own_reg <= 1'b0;
				end

				if (ipbyte_valid_reg && rxmac_data != broadaddr_byte_sig && rxmac_data != 8'd255) begin
					ipaddr_broad_reg <= 1'b0;
				end
			end
		end
	end

	// パケット受理条件 
	assign accept_sig = 
			// ARPパケット 
			((ACCEPT_ARP_PACKETS && arp_reg) && (!ipaddr_ena_sig || ipaddr_own_reg)) || 

			// IPパケット 
			(ip_reg &&
				(ACCEPT_FRAGMENT_PACKETS || fragment_reg) &&
				(!ipaddr_ena_sig || ipaddr_own_reg || (ACCEPT_BROADCAST_IPADDR && ipaddr_broad_reg)) &&
				((ACCEPT_ICMP_PACKETS && icmp_reg) || (ACCEPT_UDP_PACKETS && udp_reg) || (ACCEPT_TCP_PACKETS && tcp_reg))
			);

	// パケットステータス 
	assign packet_status_sig = { 8'b0,
			// [7] : UDPパケット(udp_port≠0で指定のポート宛のみ)のときに1
			(!IGNORE_PACKET_FILTERING && ACCEPT_UDP_PACKETS && udp_reg),

			// [6] : TCPパケットのときに1
			(!IGNORE_PACKET_FILTERING && ACCEPT_TCP_PACKETS && tcp_reg),

			// [5] : ICMPエコー要求パケット(IGNORE_ICMP_ECHO_CHECK=1なら全てのICMPタイプ)のときに1
			(!IGNORE_PACKET_FILTERING && ACCEPT_ICMP_PACKETS && icmp_reg),

			// [4] : ACCEPT_BROADCAST_IPADDR=1でブロードキャストアドレス宛のIPパケットのときに1
			(!IGNORE_PACKET_FILTERING && ip_reg && ACCEPT_BROADCAST_IPADDR && ipaddr_broad_reg),

			// [3] : ipaddr≠0でARPまたはIPの該当フィールドと一致したときに1
			(!IGNORE_PACKET_FILTERING && ipaddr_own_reg),

			// [2] : ACCEPT_FRAGMENT_PACKETS=1でフラグメント化されたIPパケットのときに1
			(!IGNORE_PACKET_FILTERING && ip_reg && ACCEPT_FRAGMENT_PACKETS && !fragment_reg),

			// [1] : IPパケットのときに1
			(!IGNORE_PACKET_FILTERING && ip_reg),

			// [0] : ARPリクエストパケット(IGNORE_ARP_REQUEST_CHECK=1なら全てのARPオペコード)のときに1
			(!IGNORE_PACKET_FILTERING && ACCEPT_ARP_PACKETS && arp_reg)
		};



endmodule

`default_nettype wire
