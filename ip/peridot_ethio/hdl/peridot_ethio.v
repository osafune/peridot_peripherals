// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender
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

// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_ethio #(
	parameter RXFIFO_SIZE			= 4096,	// 受信FIFOバイト数(4096, 8192, 16384, 32768, 65536 のどれか)
	parameter TXFIFO_SIZE			= 4096,	// 送信FIFOバイト数(4096, 8192, 16384, 32768, 65536 のどれか)
	parameter FIFO_BLOCKSIZE		= 64,	// FIFOの1ブロックのバイト数(64, 128, 256 のどれか)

	parameter SUPPORT_SPEED_10M		= 1,	// 0=100Mbpsのみ / 1=10Mbpsをサポート 
	parameter SUPPORT_HARFDUPLEX	= 1,	// 0=全二重のみ / 1=半二重およびコリジョン検出をサポート
	parameter SUPPORT_PAUSEFRAME	= 0,	// 0=PAUSEフレームを使わない / 1=PAUSEフレームによるフロー制御を行う 
	parameter MTU_SIZE				= 1500,	// MTUサイズ 
	parameter ENABLE_UDP_CHECKSUM	= 1,	// 1=UDPのチェックサムを行う 
	parameter IGNORE_RXFCS_CHECK	= 0,	// 1=受信FCSチェックを無視する 

	parameter FIXED_MAC_ADDRESS		= 48'h0,	// ≠0 ならコンパイル時に固定(macaddrポートは無視)
	parameter FIXED_IP_ADDRESS		= 32'h0,	// ≠0 ならコンパイル時に固定(ipaddrポートは無視)
	parameter FIXED_UDP_PORT		= 16241,	// ≠0 ならコンパイル時に固定(udpportポートは無視)
	parameter FIXED_PAUSE_LESS		= 48,		// ≠0 ならコンパイル時に固定(pause_lessポートは無視)
	parameter FIXED_PAUSE_VALUE		= 65535,	// ≠0 ならコンパイル時に固定(pause_valueポートは無視)

	parameter SUPPORT_MEMORYHOST	= 1,	// 1=メモリバスマスター機能を有効にする 
	parameter AVALONMM_FASTMODE		= 0,	// 1=Avalon-MM Hostのファーストアクセスモード有効 

	parameter SUPPORT_STREAMFIFO	= 1,	// 1=ストリームFIFO機能を有効にする 
	parameter SRCFIFO_NUMBER		= 4,	// 有効にするSRCFIFOの数 (0～4)
	parameter SINKFIFO_NUMBER		= 4,	// 有効にするSINKFIFOの数 (0～4)
	parameter SRCFIFO_0_SIZE		= 2048,	// SRCFIFO 0 バイト数(1024, 2048, 4096, 8192, 16384, 32768, 65536 のどれか)
	parameter SRCFIFO_1_SIZE		= 2048,	// SRCFIFO 1 バイト数( 〃 )
	parameter SRCFIFO_2_SIZE		= 2048,	// SRCFIFO 2 バイト数( 〃 )
	parameter SRCFIFO_3_SIZE		= 2048,	// SRCFIFO 3 バイト数( 〃 )
	parameter SINKFIFO_0_SIZE		= 2048,	// SINKFIFO 0 バイト数(1024, 2048, 4096, 8192, 16384, 32768, 65536 のどれか)
	parameter SINKFIFO_1_SIZE		= 2048,	// SINKFIFO 1 バイト数( 〃 )
	parameter SINKFIFO_2_SIZE		= 2048,	// SINKFIFO 2 バイト数( 〃 )
	parameter SINKFIFO_3_SIZE		= 2048	// SINKFIFO 3 バイト数( 〃 )
) (
	// Interface: Avalon Clock sink
	input wire			csi_clock_clk,

	// Interface: Avalon Reset sink
	input wire			rsi_reset_reset,

	// Interface: Avalon-MM Host
	input wire			avm_m1_waitrequest,
	output wire [31:0]	avm_m1_address,
	output wire			avm_m1_read,
	input wire  [31:0]	avm_m1_readdata,
	input wire			avm_m1_readdatavalid,
	output wire			avm_m1_write,
	output wire [31:0]	avm_m1_writedata,
	output wire [3:0]	avm_m1_byteenable,

	// Interface: Avalon-ST Source
	input wire			aso_src0_ready,
	output wire			aso_src0_valid,
	output wire [7:0]	aso_src0_data,

	input wire			aso_src1_ready,
	output wire			aso_src1_valid,
	output wire [7:0]	aso_src1_data,

	input wire			aso_src2_ready,
	output wire			aso_src2_valid,
	output wire [7:0]	aso_src2_data,

	input wire			aso_src3_ready,
	output wire			aso_src3_valid,
	output wire [7:0]	aso_src3_data,

	// Interface: Avalon-ST Sink
	output wire			asi_sink0_ready,
	input wire			asi_sink0_valid,
	input wire  [7:0]	asi_sink0_data,

	output wire			asi_sink1_ready,
	input wire			asi_sink1_valid,
	input wire  [7:0]	asi_sink1_data,

	output wire			asi_sink2_ready,
	input wire			asi_sink2_valid,
	input wire  [7:0]	asi_sink2_data,

	output wire			asi_sink3_ready,
	input wire			asi_sink3_valid,
	input wire  [7:0]	asi_sink3_data,

	// Interface: Conduit
	input wire			coe_enable,			// 1=動作イネーブル / 0=動作停止
	output wire [2:0]	coe_status,			// 動作ステータス 
	input wire			coe_speed10m,		// 0=100Mbps, 1=10Mbps (SUPPORT_SPEED_10M=1の時のみ)
	input wire			coe_halfduplex,		// 0=Full-duplex, 1=Half-duplex (SUPPORT_HARFDUPLEX=1の時のみ)
	input wire  [47:0]	coe_macaddr,		// 自分のMACアドレス 
	input wire  [31:0]	coe_ipaddr,			// 自分のIPアドレス 
	input wire  [15:0]	coe_udpport,		// 自分のUDPポート番号 (リクエストを受信するポート)
	input wire  [7:0]	coe_pause_less,		// フレーム受信完了時にFIFO空きがこの値以下ならPAUSE送信 
	input wire  [15:0]	coe_pause_value,	// リクエストする待ち時間 

	input wire			coe_rmii_clk,		// RMII/MAC側クロック(50MHz)
	input wire  [1:0]	coe_rmii_rxd,
	input wire			coe_rmii_crsdv,
	output wire [1:0]	coe_rmii_txd,
	output wire			coe_rmii_txen
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	// UDPペイロードの最大データグラム数(512～1472, 1500-(IPヘッダ+UDPヘッダ))
	localparam UDPPAYLOAD_LENGTH_MAX = MTU_SIZE - 28;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			reset_sig = rsi_reset_reset;	// モジュール内部駆動非同期リセット 
	wire			clock_sig = csi_clock_clk;		// モジュール内部駆動クロック 

	wire			req_ready_sig, req_valid_sig, req_sop_sig, req_eop_sig;
	wire [7:0]		req_data_sig;
	wire			rsp_ready_sig, rsp_valid_sig, rsp_sop_sig, rsp_eop_sig, rsp_error_sig;
	wire [7:0]		rsp_data_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	// Avalon-ST Serverモジュール 

	peridot_ethio_avstserver #(
		.RXFIFO_SIZE			(RXFIFO_SIZE),
		.TXFIFO_SIZE			(TXFIFO_SIZE),
		.FIFO_BLOCKSIZE			(FIFO_BLOCKSIZE),
		.SUPPORT_SPEED_10M		(SUPPORT_SPEED_10M),
		.SUPPORT_HARFDUPLEX		(SUPPORT_HARFDUPLEX),
		.SUPPORT_PAUSEFRAME		(SUPPORT_PAUSEFRAME),
		.UDPPAYLOAD_LENGTH_MAX	(UDPPAYLOAD_LENGTH_MAX),
		.ENABLE_UDP_CHECKSUM	(ENABLE_UDP_CHECKSUM),
		.IGNORE_RXFCS_CHECK		(IGNORE_RXFCS_CHECK),
		.FIXED_MAC_ADDRESS		(FIXED_MAC_ADDRESS),
		.FIXED_IP_ADDRESS		(FIXED_IP_ADDRESS),
		.FIXED_UDP_PORT			(FIXED_UDP_PORT),
		.FIXED_PAUSE_LESS		(FIXED_PAUSE_LESS),
		.FIXED_PAUSE_VALUE		(FIXED_PAUSE_VALUE)
	)
	u_avst (
		.reset			(reset_sig),
		.clk			(clock_sig),
		.enable			(coe_enable),
		.status			(coe_status),

		.sel_speed10m	(coe_speed10m),
		.sel_halfduplex	(coe_halfduplex),
		.macaddr		(coe_macaddr),
		.ipaddr			(coe_ipaddr),
		.udp_port		(coe_udpport),
		.pause_less		(coe_pause_less),
		.pause_value	(coe_pause_value),

		.out_ready		(req_ready_sig),
		.out_valid		(req_valid_sig),
		.out_data		(req_data_sig),
		.out_sop		(req_sop_sig),
		.out_eop		(req_eop_sig),
		.in_ready		(rsp_ready_sig),
		.in_valid		(rsp_valid_sig),
		.in_data		(rsp_data_sig),
		.in_sop			(rsp_sop_sig),
		.in_eop			(rsp_eop_sig),
		.in_error		(rsp_error_sig),

		.rmii_clk		(coe_rmii_clk),
		.rmii_rxd		(coe_rmii_rxd),
		.rmii_crsdv		(coe_rmii_crsdv),
		.rmii_txd		(coe_rmii_txd),
		.rmii_txen		(coe_rmii_txen)
	);


	// Avalon-MM ブリッジモジュール 

	peridot_ethio_avmm #(
		.SUPPORT_MEMORYHOST		(SUPPORT_MEMORYHOST),
		.AVALONMM_FASTMODE		(AVALONMM_FASTMODE),
		.SUPPORT_STREAMFIFO		(SUPPORT_STREAMFIFO),
		.SRCFIFO_NUMBER			(SRCFIFO_NUMBER),
		.SINKFIFO_NUMBER		(SINKFIFO_NUMBER),
		.SRCFIFO_0_SIZE			(SRCFIFO_0_SIZE),
		.SRCFIFO_1_SIZE			(SRCFIFO_1_SIZE),
		.SRCFIFO_2_SIZE			(SRCFIFO_2_SIZE),
		.SRCFIFO_3_SIZE			(SRCFIFO_3_SIZE),
		.SINKFIFO_0_SIZE		(SINKFIFO_0_SIZE),
		.SINKFIFO_1_SIZE		(SINKFIFO_1_SIZE),
		.SINKFIFO_2_SIZE		(SINKFIFO_2_SIZE),
		.SINKFIFO_3_SIZE		(SINKFIFO_3_SIZE)
	)
	u_avmm (
		.reset				(reset_sig),
		.clk				(clock_sig),

		.in_ready			(req_ready_sig),
		.in_valid			(req_valid_sig),
		.in_data			(req_data_sig),
		.in_sop				(req_sop_sig),
		.in_eop				(req_eop_sig),
		.out_ready			(rsp_ready_sig),
		.out_valid			(rsp_valid_sig),
		.out_data			(rsp_data_sig),
		.out_sop			(rsp_sop_sig),
		.out_eop			(rsp_eop_sig),
		.out_error			(rsp_error_sig),

		.avm_waitrequest	(avm_m1_waitrequest),
		.avm_address		(avm_m1_address),
		.avm_read			(avm_m1_read),
		.avm_readdata		(avm_m1_readdata),
		.avm_readdatavalid	(avm_m1_readdatavalid),
		.avm_write			(avm_m1_write),
		.avm_writedata		(avm_m1_writedata),
		.avm_byteenable		(avm_m1_byteenable),

		.aso_0_ready		(aso_src0_ready),
		.aso_0_valid		(aso_src0_valid),
		.aso_0_data			(aso_src0_data),
		.aso_1_ready		(aso_src1_ready),
		.aso_1_valid		(aso_src1_valid),
		.aso_1_data			(aso_src1_data),
		.aso_2_ready		(aso_src2_ready),
		.aso_2_valid		(aso_src2_valid),
		.aso_2_data			(aso_src2_data),
		.aso_3_ready		(aso_src3_ready),
		.aso_3_valid		(aso_src3_valid),
		.aso_3_data			(aso_src3_data),

		.asi_0_ready		(asi_sink0_ready),
		.asi_0_valid		(asi_sink0_valid),
		.asi_0_data			(asi_sink0_data),
		.asi_1_ready		(asi_sink1_ready),
		.asi_1_valid		(asi_sink1_valid),
		.asi_1_data			(asi_sink1_data),
		.asi_2_ready		(asi_sink2_ready),
		.asi_2_valid		(asi_sink2_valid),
		.asi_2_data			(asi_sink2_data),
		.asi_3_ready		(asi_sink3_ready),
		.asi_3_valid		(asi_sink3_valid),
		.asi_3_data			(asi_sink3_data)
	);



endmodule

`default_nettype wire
