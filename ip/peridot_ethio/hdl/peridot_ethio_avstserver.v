// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / Avavlon-ST Server
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/07/01 -> 2022/09/23
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
//
// PAUSEフレームによるフロー制御は sel_halfduplex=0(全二重) の場合のみ動作する。
//
// パケット送信コントローラー部の復帰不能エラーは現状無視。
//


// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_ethio_avstserver #(
	parameter RXFIFO_SIZE			= 4096,	// 受信FIFOバイト数(4096, 8192, 16384, 32768, 65536 のどれか)
	parameter TXFIFO_SIZE			= 4096,	// 送信FIFOバイト数(4096, 8192, 16384, 32768, 65536 のどれか)
	parameter FIFO_BLOCKSIZE		= 64,	// FIFOの1ブロックのバイト数(64, 128, 256 のどれか)

	parameter SUPPORT_SPEED_10M		= 1,	// 0=100Mbpsのみ / 1=10Mbpsをサポート 
	parameter SUPPORT_HARFDUPLEX	= 1,	// 0=全二重のみ / 1=半二重およびコリジョン検出をサポート
	parameter SUPPORT_PAUSEFRAME	= 0,	// 0=PAUSEフレームを使わない / 1=PAUSEフレームによるフロー制御を行う 
	parameter UDPPAYLOAD_LENGTH_MAX	= 1472,	// UDPペイロードの最大データグラム数(512～1472, 1500-(IPヘッダ+UDPヘッダ))
	parameter ENABLE_UDP_CHECKSUM	= 0,	// 1=UDPのチェックサムを行う 
	parameter IGNORE_RXFCS_CHECK	= 0,	// 1=受信FCSチェックを無視する 

	parameter FIXED_MAC_ADDRESS		= 48'h0,	// ≠0 ならコンパイル時に固定(macaddrポートは無視)
	parameter FIXED_IP_ADDRESS		= 32'h0,	// ≠0 ならコンパイル時に固定(ipaddrポートは無視)
	parameter FIXED_UDP_PORT		= 16'h0,	// ≠0 ならコンパイル時に固定(udp_portポートは無視)
	parameter FIXED_PAUSE_LESS		=  8'd0,	// ≠0 ならコンパイル時に固定(pause_lessポートは無視)
	parameter FIXED_PAUSE_VALUE		= 16'd0		// ≠0 ならコンパイル時に固定(pause_valueポートは無視)
) (
	// リセットとクロック 
	input wire			reset,
	input wire			clk,				// Avalon-ST側クロック(50～150MHz)
	input wire			enable,				// 動作イネーブル 
	output wire [2:0]	status,				// [0] MACアクティブ 
											// [1] RXフレーム受信中 
											// [2] TXフレーム送信中 

	// ネットワーク制御信号					(変更はstatus[0]がネゲートの場合のみ) 
	input wire			sel_speed10m,		// 0=100Mbps, 1=10Mbps (SUPPORT_SPEED_10M=1の時のみ)
	input wire			sel_halfduplex,		// 0=Full-duplex, 1=Half-duplex (SUPPORT_HARFDUPLEX=1の時のみ)
	input wire  [47:0]	macaddr,			// 自分のMACアドレス 
	input wire  [31:0]	ipaddr,				// 自分のIPアドレス 
	input wire  [15:0]	udp_port,			// 自分のUDPポート番号 (リクエストを受信するポート)

	// PAUSE制御信号 
	input wire  [7:0]	pause_less,			// フレーム受信完了時にFIFO空きがこの値以下ならPAUSE送信 
	input wire  [15:0]	pause_value,		// リクエストする待ち時間 

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
	input wire			in_error,			// eop時にアサートすると応答パケットを破棄する 

	// RMII信号 
	input wire			rmii_clk,			// RMII/MAC側クロック(50MHz)
	input wire  [1:0]	rmii_rxd,
	input wire			rmii_crsdv,
	output wire [1:0]	rmii_txd,
	output wire			rmii_txen
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam FIFO_BLOCKSIZE_BITWIDTH =
				(FIFO_BLOCKSIZE > 128)? 8 :
				(FIFO_BLOCKSIZE >  64)? 7 :
				(FIFO_BLOCKSIZE >  32)? 6 :
				(FIFO_BLOCKSIZE >  16)? 5 :
				4;

	localparam RXFIFO_BLOCKNUM_BITWIDTH =
				(RXFIFO_SIZE > 32768)? 16 - FIFO_BLOCKSIZE_BITWIDTH :
				(RXFIFO_SIZE > 16384)? 15 - FIFO_BLOCKSIZE_BITWIDTH :
				(RXFIFO_SIZE >  8192)? 14 - FIFO_BLOCKSIZE_BITWIDTH :
				(RXFIFO_SIZE >  4096)? 13 - FIFO_BLOCKSIZE_BITWIDTH :
				12 - FIFO_BLOCKSIZE_BITWIDTH;

	localparam TXFIFO_BLOCKNUM_BITWIDTH =
				(TXFIFO_SIZE > 32768)? 16 - FIFO_BLOCKSIZE_BITWIDTH :
				(TXFIFO_SIZE > 16384)? 15 - FIFO_BLOCKSIZE_BITWIDTH :
				(TXFIFO_SIZE >  8192)? 14 - FIFO_BLOCKSIZE_BITWIDTH :
				(TXFIFO_SIZE >  4096)? 13 - FIFO_BLOCKSIZE_BITWIDTH :
				12 - FIFO_BLOCKSIZE_BITWIDTH;

	localparam IGNORE_COLLISION_DETECT = (SUPPORT_HARFDUPLEX)? 0 : 1;

	localparam PACKET_LENGTH_MAX = UDPPAYLOAD_LENGTH_MAX + 36;

	localparam RX_PACKET_BYTENUM	= (PACKET_LENGTH_MAX + (2 ** FIFO_BLOCKSIZE_BITWIDTH) - 1) / (2 ** FIFO_BLOCKSIZE_BITWIDTH);
	localparam RX_PACKET_BLOCKNUM	= RX_PACKET_BYTENUM[RXFIFO_BLOCKNUM_BITWIDTH-1:0];


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 
	wire			clock_sig = clk;		// モジュール内部駆動クロック 
	wire			clk_mac_sig = rmii_clk;

	wire [2:0]		status_sig;
	wire			busy_sig, enable_sig;
	wire			rst_fifo_sig, rst_mac_sig;

	wire			speed10m_sig, speed10m_cdb_sig;
	wire			halfduplex_sig, halfduplex_cdb_sig;
	wire [47:0]		macaddr_sig, macaddr_cdb_sig;
	wire [31:0]		ipaddr_sig, ipaddr_cdb_sig;
	wire [15:0]		udpport_sig, udpport_cdb_sig;
	wire [47:0]		packet_macaddr_sig;
	wire [31:0]		packet_ipaddr_sig;
	wire [15:0]		packet_udpport_sig;

	wire [7:0]		pause_less_sig, pause_less_cdb_sig;
	wire [15:0]		pause_value_sig, pause_value_cdb_sig;

	wire			rxfifo_ready_a_sig, rxfifo_ready_b_sig;
	wire			rxfifo_update_a_sig, rxfifo_update_b_sig;
	wire [RXFIFO_BLOCKNUM_BITWIDTH-1:0] rxfifo_blocknum_a_sig, rxfifo_blocknum_b_sig;
	wire [RXFIFO_BLOCKNUM_BITWIDTH-1:0] rxfifo_free_a_sig;
	wire			rxfifo_empty_b_sig;
	wire [10:0]		rxfifo_address_a_sig, rxfifo_address_b_sig;
	wire [31:0]		rxfifo_writedata_a_sig, rxfifo_readdata_b_sig;
	wire [3:0]		rxfifo_writeenable_a_sig;
	wire			rxfifo_writeerror_a_sig;

	wire			txfifo_ready_a_sig, txfifo_ready_b_sig;
	wire			txfifo_update_a_sig, txfifo_update_b_sig;
	wire [TXFIFO_BLOCKNUM_BITWIDTH-1:0] txfifo_blocknum_a_sig, txfifo_blocknum_b_sig;
	wire [TXFIFO_BLOCKNUM_BITWIDTH-1:0] txfifo_free_a_sig;
	wire			txfifo_empty_b_sig;
	wire [10:0]		txfifo_address_a_sig, txfifo_address_b_sig;
	wire [31:0]		txfifo_writedata_a_sig, txfifo_readdata_b_sig;
	wire [3:0]		txfifo_writeenable_a_sig;

	wire			rx_ready_sig, tx_ready_sig;
	wire			rx_valid_sig, tx_valid_sig;
	wire [7:0]		rx_data_sig, tx_data_sig;
	wire			rx_sop_sig, tx_sop_sig;
	wire			rx_eop_sig, tx_eop_sig;
	wire [1:0]		rx_error_sig, tx_error_sig;

	wire			rxpause_req_sig, txpause_req_sig;
	wire			rxpause_ack_sig, txpause_ack_sig;
	wire [15:0]		rxpause_value_sig, txpause_value_sig;

	wire			error_header_sig;
	wire			rx_frame_sig, tx_frame_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	// イネーブルとリセット信号の制御 

	peridot_ethio_reset
	u_reset (
		.reset				(reset_sig),
		.clk				(clock_sig),

		.enable				(enable),
		.active				(status_sig[0]),
		.packet_busy		(busy_sig),
		.packet_enable_out	(enable_sig),
		.fifo_reset_out		(rst_fifo_sig),

		.mac_clk			(clk_mac_sig),
		.mac_reset_out		(rst_mac_sig)
	);

	peridot_ethio_cdb_vector #(
		.DATA_BITWIDTH	(2)
	)
	u_cdb_status (
		.reset		(1'b0),
		.clk		(clock_sig),
		.latch		(1'b1),
		.in_data	({tx_frame_sig, rx_frame_sig}),
		.out_data	(status_sig[2:1])
	);

	assign status = status_sig;


	// 制御信号のクロックブリッジとデータマスク 

	peridot_ethio_cdb_vector #(
		.DATA_BITWIDTH	(2+48+32+16)
	)
	u_cdb_param (
		.reset		(1'b0),
		.clk		(clk_mac_sig),
		.latch		(~rst_mac_sig),
		.in_data	({sel_speed10m, sel_halfduplex, macaddr, ipaddr, udp_port}),
		.out_data	({speed10m_cdb_sig, halfduplex_cdb_sig, macaddr_cdb_sig, ipaddr_cdb_sig, udpport_cdb_sig})
	);

	assign speed10m_sig = (SUPPORT_SPEED_10M)? speed10m_cdb_sig : 1'b0;
	assign halfduplex_sig = (SUPPORT_HARFDUPLEX)? halfduplex_cdb_sig : 1'b0;
	assign macaddr_sig = (FIXED_MAC_ADDRESS)? FIXED_MAC_ADDRESS[47:0] : macaddr_cdb_sig;
	assign ipaddr_sig = (FIXED_IP_ADDRESS)? FIXED_IP_ADDRESS[31:0] : ipaddr_cdb_sig;
	assign udpport_sig = (FIXED_UDP_PORT)? FIXED_UDP_PORT[15:0] : udpport_cdb_sig;

	assign packet_macaddr_sig = (FIXED_MAC_ADDRESS)? FIXED_MAC_ADDRESS[47:0] : macaddr;
	assign packet_ipaddr_sig = (FIXED_IP_ADDRESS)? FIXED_IP_ADDRESS[31:0] : ipaddr;
	assign packet_udpport_sig = (FIXED_UDP_PORT)? FIXED_UDP_PORT[15:0] : udp_port;


	// PAUSEフレーム処理 

	peridot_ethio_cdb_get #(
		.DATA_BITWIDTH	(8+16)
	)
	u_cdb_pause (
		.reset_a	(reset_sig),
		.clk_a		(clock_sig),
		.in_data	({pause_less, pause_value}),

		.reset_b	(rst_mac_sig),
		.clk_b		(clk_mac_sig),
		.get_req	(rx_sop_sig),
		.out_data	({pause_less_cdb_sig, pause_value_cdb_sig})
	);

	assign pause_less_sig = (FIXED_PAUSE_LESS)? FIXED_PAUSE_LESS[7:0] : pause_less_cdb_sig;
	assign pause_value_sig = (FIXED_PAUSE_VALUE)? FIXED_PAUSE_VALUE[15:0] : pause_value_cdb_sig;


	// パケット処理 

	peridot_ethio_udp2packet #(
		.RXFIFO_BLOCKNUM_BITWIDTH	(RXFIFO_BLOCKNUM_BITWIDTH),
		.TXFIFO_BLOCKNUM_BITWIDTH	(TXFIFO_BLOCKNUM_BITWIDTH),
		.FIFO_BLOCKSIZE_BITWIDTH	(FIFO_BLOCKSIZE_BITWIDTH),
		.UDPPAYLOAD_LENGTH_MAX		(UDPPAYLOAD_LENGTH_MAX),
		.ENABLE_UDP_CHECKSUM		(ENABLE_UDP_CHECKSUM)
	)
	u_packet (
		.reset				(reset_sig),
		.clk				(clock_sig),
		.enable				(enable_sig),
		.busy				(busy_sig),

		.macaddr			(packet_macaddr_sig),
		.ipaddr				(packet_ipaddr_sig),
		.udp_port			(packet_udpport_sig),

		.rxfifo_ready		(rxfifo_ready_b_sig),
		.rxfifo_update		(rxfifo_update_b_sig),
		.rxfifo_blocknum	(rxfifo_blocknum_b_sig),
		.rxfifo_empty		(rxfifo_empty_b_sig),
		.rxfifo_address		(rxfifo_address_b_sig),
		.rxfifo_readdata	(rxfifo_readdata_b_sig),

		.txfifo_ready		(txfifo_ready_a_sig),
		.txfifo_update		(txfifo_update_a_sig),
		.txfifo_blocknum	(txfifo_blocknum_a_sig),
		.txfifo_free		(txfifo_free_a_sig),
		.txfifo_address		(txfifo_address_a_sig),
		.txfifo_writedata	(txfifo_writedata_a_sig),
		.txfifo_writeenable	(txfifo_writeenable_a_sig),

		.out_ready			(out_ready),
		.out_valid			(out_valid),
		.out_data			(out_data),
		.out_sop			(out_sop),
		.out_eop			(out_eop),

		.in_ready			(in_ready),
		.in_valid			(in_valid),
		.in_data			(in_data),
		.in_sop				(in_sop),
		.in_eop				(in_eop),
		.in_error			(in_error)
	);


	// 受信FIFO

	peridot_ethio_memfifo #(
		.FIFO_BLOCKNUM_BITWIDTH		(RXFIFO_BLOCKNUM_BITWIDTH),
		.FIFO_BLOCKSIZE_BITWIDTH	(FIFO_BLOCKSIZE_BITWIDTH),
		.MEM_ADDRESS_BITWIDTH		(11),
		.MEM_WORDSIZE_BITWIDTH		(4),
		.RAM_READOUT_REGISTER		("ON")
	)
	u_rxfifo (
		.reset_a		(rst_mac_sig),
		.clk_a			(clk_mac_sig),

		.ready_a		(rxfifo_ready_a_sig),
		.update_a		(rxfifo_update_a_sig),
		.blocknum_a		(rxfifo_blocknum_a_sig),
		.free_a			(rxfifo_free_a_sig),
		.full_a			(),
		.enable_a		(1'b1),
		.address_a		(rxfifo_address_a_sig),
		.writedata_a	(rxfifo_writedata_a_sig),
		.writeenable_a	(rxfifo_writeenable_a_sig),
		.readdata_a		(),
		.writeerror_a	(rxfifo_writeerror_a_sig),

		.reset_b		(rst_fifo_sig),
		.clk_b			(clock_sig),
		.ready_b		(rxfifo_ready_b_sig),
		.update_b		(rxfifo_update_b_sig),
		.blocknum_b		(rxfifo_blocknum_b_sig),
		.remain_b		(),
		.empty_b		(rxfifo_empty_b_sig),
		.enable_b		(1'b1),
		.address_b		(rxfifo_address_b_sig),
		.readdata_b		(rxfifo_readdata_b_sig)
	);


	// 送信FIFO

	peridot_ethio_memfifo #(
		.FIFO_BLOCKNUM_BITWIDTH		(TXFIFO_BLOCKNUM_BITWIDTH),
		.FIFO_BLOCKSIZE_BITWIDTH	(FIFO_BLOCKSIZE_BITWIDTH),
		.MEM_ADDRESS_BITWIDTH		(11),
		.MEM_WORDSIZE_BITWIDTH		(4),
		.RAM_READOUT_REGISTER		("ON"),
		.RAM_OVERRUN_PROTECTION		("OFF")
	)
	u_txfifo (
		.reset_a		(rst_fifo_sig),
		.clk_a			(clock_sig),

		.ready_a		(txfifo_ready_a_sig),
		.update_a		(txfifo_update_a_sig),
		.blocknum_a		(txfifo_blocknum_a_sig),
		.free_a			(txfifo_free_a_sig),
		.full_a			(),
		.enable_a		(1'b1),
		.address_a		(txfifo_address_a_sig),
		.writedata_a	(txfifo_writedata_a_sig),
		.writeenable_a	(txfifo_writeenable_a_sig),
		.readdata_a		(),
		.writeerror_a	(),

		.reset_b		(rst_mac_sig),
		.clk_b			(clk_mac_sig),
		.ready_b		(txfifo_ready_b_sig),
		.update_b		(txfifo_update_b_sig),
		.blocknum_b		(txfifo_blocknum_b_sig),
		.remain_b		(),
		.empty_b		(txfifo_empty_b_sig),
		.enable_b		(1'b1),
		.address_b		(txfifo_address_b_sig),
		.readdata_b		(txfifo_readdata_b_sig)
	);


	// パケットフィルタリングおよび受信コントローラー 

	peridot_ethio_rxctrl #(
		.PACKET_LENGTH_MAX			(PACKET_LENGTH_MAX),
		.FIFO_BLOCKNUM_BITWIDTH		(RXFIFO_BLOCKNUM_BITWIDTH),
		.FIFO_BLOCKSIZE_BITWIDTH	(FIFO_BLOCKSIZE_BITWIDTH),
		.ACCEPT_PAUSE_FRAME			(SUPPORT_PAUSEFRAME),
		.ACCEPT_ARP_PACKETS			(1),
		.ACCEPT_FRAGMENT_PACKETS	(0),
		.ACCEPT_BROADCAST_IPADDR	(0),
		.ACCEPT_ICMP_PACKETS		(1),
		.ACCEPT_UDP_PACKETS			(1),
		.ACCEPT_TCP_PACKETS			(0)
	)
	u_rxctrl (
		.reset				(rst_mac_sig),
		.clk				(clk_mac_sig),
		.reject_overflow	(),
		.pause_less			(pause_less_sig),
		.pause_value		(pause_value_sig),
		.ipaddr				(ipaddr_sig),
		.subnet				(32'h0),
		.udp_port			(udpport_sig),

		.txpause_req		(txpause_req_sig),
		.txpause_value		(txpause_value_sig),
		.txpause_ack		(txpause_ack_sig),

		.rxmac_ready		(rx_ready_sig),
		.rxmac_data			(rx_data_sig),
		.rxmac_valid		(rx_valid_sig),
		.rxmac_sop			(rx_sop_sig),
		.rxmac_eop			(rx_eop_sig),
		.rxmac_error		(rx_error_sig[1]),

		.rxfifo_ready		(rxfifo_ready_a_sig),
		.rxfifo_update		(rxfifo_update_a_sig),
		.rxfifo_blocknum	(rxfifo_blocknum_a_sig),
		.rxfifo_free		(rxfifo_free_a_sig),
		.rxfifo_address		(rxfifo_address_a_sig),
		.rxfifo_writedata	(rxfifo_writedata_a_sig),
		.rxfifo_writeenable	(rxfifo_writeenable_a_sig),
		.rxfifo_writeerror	(rxfifo_writeerror_a_sig)
	);


	// パケット送出コントローラー 

	peridot_ethio_txctrl #(
		.PACKET_LENGTH_MAX			(PACKET_LENGTH_MAX),
		.FIFO_BLOCKNUM_BITWIDTH		(TXFIFO_BLOCKNUM_BITWIDTH),
		.FIFO_BLOCKSIZE_BITWIDTH	(FIFO_BLOCKSIZE_BITWIDTH),
		.IGNORE_LENGTH_CHECK		(1),
		.IGNORE_COLLISION_DETECT	(IGNORE_COLLISION_DETECT),
		.ACCEPT_PAUSE_FRAME			(SUPPORT_PAUSEFRAME)
	)
	u_txctrl (
		.reset				(rst_mac_sig),
		.clk				(clk_mac_sig),
		.sel_speed10m		(speed10m_sig),
		.cancel_resend		(),
		.error_header		(error_header_sig),

		.rxpause_req		(rxpause_req_sig),
		.rxpause_value		(rxpause_value_sig),
		.rxpause_ack		(rxpause_ack_sig),

		.txfifo_ready		(txfifo_ready_b_sig),
		.txfifo_update		(txfifo_update_b_sig),
		.txfifo_blocknum	(txfifo_blocknum_b_sig),
		.txfifo_empty		(txfifo_empty_b_sig),
		.txfifo_address		(txfifo_address_b_sig),
		.txfifo_readdata	(txfifo_readdata_b_sig),

		.txmac_ready		(tx_ready_sig),
		.txmac_data			(tx_data_sig),
		.txmac_valid		(tx_valid_sig),
		.txmac_sop			(tx_sop_sig),
		.txmac_eop			(tx_eop_sig),
		.txmac_error		(tx_error_sig[1])
	);


	// RMII入出力 

	peridot_ethio_stream #(
		.TX_INTERFRAMEGAP_COUNT		(48),
		.RX_INTERFRAMEGAP_COUNT		(48),
		.LATECOLLISION_GATE_COUNT	(16),
		.IGNORE_RXFCS_CHECK			(IGNORE_RXFCS_CHECK),
		.IGNORE_UNDERFLOW_ERROR		(1),
		.IGNORE_OVERFLOW_ERROR		(1),
		.SUPPORT_SPEED_10M			(SUPPORT_SPEED_10M),
		.SUPPORT_HALFDUPLEX			(SUPPORT_HARFDUPLEX),
		.SUPPORT_PAUSEFRAME			(SUPPORT_PAUSEFRAME)
	)
	u_rmii (
		.reset			(rst_mac_sig),
		.clk			(clk_mac_sig),
		.sel_speed10m	(speed10m_sig),
		.sel_halfduplex	(halfduplex_sig),
		.macaddr		(macaddr_sig),

		.rxpause_req	(rxpause_req_sig),
		.rxpause_value	(rxpause_value_sig),
		.rxpause_ack	(rxpause_ack_sig),

		.out_ready		(rx_ready_sig),
		.out_data		(rx_data_sig),
		.out_valid		(rx_valid_sig),
		.out_sop		(rx_sop_sig),
		.out_eop		(rx_eop_sig),
		.out_error		(rx_error_sig),

		.txpause_req	(txpause_req_sig),
		.txpause_value	(txpause_value_sig),
		.txpause_ack	(txpause_ack_sig),

		.in_ready		(tx_ready_sig),
		.in_data		(tx_data_sig),
		.in_valid		(tx_valid_sig),
		.in_sop			(tx_sop_sig),
		.in_eop			(tx_eop_sig),
		.in_error		(tx_error_sig),

		.rmii_rxd		(rmii_rxd),
		.rmii_crsdv		(rmii_crsdv),
		.rmii_txd		(rmii_txd),
		.rmii_txen		(rmii_txen),
		.rx_frame		(rx_frame_sig),
		.tx_frame		(tx_frame_sig)
	);



endmodule

`default_nettype wire
