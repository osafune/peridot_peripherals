// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / RMII-Stream
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
//   フレーム再送制御   → in_readyアサート時にin_errorがアサートされていたら再送 
//                         衝突時は送信後に再送回数からバックオフ時間を取得して待つ 
//                         再送回数のカウント、再送破棄、バックオフは後段で処理する 
//   フレーム受信側制御 → out_eof時にout_errorがアサートされていたら受信データは破棄 
//

// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_ethio_stream #(
	parameter TX_INTERFRAMEGAP_COUNT	= 48,	// 送信側フレーム間ギャップカウント(48=96bit分)
	parameter RX_INTERFRAMEGAP_COUNT	= 48,	// 受信側フレーム間ギャップカウント(48=96bit分)
	parameter LATECOLLISION_GATE_COUNT	= 16,	// 遅延コリジョン検出時間(16=32bit分)
	parameter IGNORE_RXFCS_CHECK		= 0,	// 1=受信FCSチェックを無視する 
	parameter IGNORE_UNDERFLOW_ERROR	= 0,	// 1=アンダーフローエラーを無視する 
	parameter IGNORE_OVERFLOW_ERROR		= 0,	// 1=オーバーフローエラーを無視する 
	parameter IGNORE_MACADDR_FIELD		= 0,	// 1=MACアドレスフィールド挿入/破棄をしない 
	parameter SUPPORT_SPEED_10M			= 1,	// 1=10Mbpsをサポート 
	parameter SUPPORT_HALFDUPLEX		= 1,	// 1=半二重モードをサポート 
	parameter SUPPORT_PAUSEFRAME		= 0		// 1=PAUSEフレーム処理を行う 
) (
	output wire			test_crs,		// この信号とtxenをandすると擬似的なCRSDV信号になる 


	input wire			reset,
	input wire			clk,			// RMII_CLK (50MHz)
	input wire			sel_speed10m,	// 0=100Mbps, 1=10Mbps (SUPPORT_SPEED_10M=1の時のみ)
	input wire			sel_halfduplex,	// 0=Full-duplex, 1=Half-duplex (SUPPORT_HALFDUPLEX=1の時のみ)
	input wire  [47:0]	macaddr,

	// PAUSE受信リクエスト 
	output wire			rxpause_req,	// Full-duplexの時のみ有効
	output wire [15:0]	rxpause_value,
	input wire			rxpause_ack,

	// 受信データストリーム 
	input wire			out_ready,
	output wire			out_valid,
	output wire [7:0]	out_data,
	output wire			out_sop,
	output wire			out_eop,
	output wire [1:0]	out_error,		// [0] 1=オーバーフロー発生, 次のフレーム開始でクリア 
										// [1] 1=フレームエラーまたはリジェクト要求発生, EOPのとき有効 
	// PAUSE送信リクエスト 
	input wire			txpause_req,	// Full-duplexの時のみ有効
	input wire [15:0]	txpause_value,
	output wire			txpause_ack,

	// 送信データストリーム 
	output wire			in_ready,
	input wire			in_valid,
	input wire  [7:0]	in_data,
	input wire			in_sop,
	input wire			in_eop,
	output wire [1:0]	in_error,		// [0] 1=アンダーフロー発生, SOP入力でクリア 
										// [1] 1=コリジョン発生(半二重のとき有効), SOP入力でクリア 
	// RMII信号 
	input wire  [1:0]	rmii_rxd,
	input wire			rmii_crsdv,
	output wire [1:0]	rmii_txd,
	output wire			rmii_txen,
	output wire			rx_frame,		// フレーム受信信号 
	output wire			tx_frame		// フレーム送信信号 
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam IGNORE_COLLISION_DETECT = (!SUPPORT_HALFDUPLEX)? 1 : 0;

	localparam LATE_COUNT_VALUE = (LATECOLLISION_GATE_COUNT > 31)? 31 : LATECOLLISION_GATE_COUNT-1;
	localparam RXIFG_COUNT_VALUE = (RX_INTERFRAMEGAP_COUNT > 63)? 1 : 64-RX_INTERFRAMEGAP_COUNT;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
	wire			reset_sig = reset;		// モジュール内部駆動非同期リセット 
	wire			clock_sig = clk;		// モジュール内部駆動クロック 

	wire			tx_datavalid_sig;
	wire			tx_fcs_sig;
	reg				test_crs1_reg, test_crs2_reg, test_crs3_reg;


	reg				clkena_reg = 1'b0;
	reg  [3:0]		clkdiv_count_reg = 1'd0;

	wire			hafduplex_sig;
	reg  [6:0]		rxifg_count_reg;
	reg  [5:0]		late_count_reg;
	reg				crs_reg;
	reg				reject_reg;
	reg				collision_reg;

	wire			rx_enable_sig;
	wire			rx_pausereq_sig;
	wire			rx_working_sig;
	wire			crs_sig;
	wire			reject_sig;
	wire			overflow_sig;
	wire [1:0]		out_error_sig;

	wire			tx_enable_sig;
	wire			tx_pausereq_sig;
	wire			tx_working_sig;
	wire			tx_ready_sig;
	wire			collision_sig;
	wire			underflow_sig;
	wire [0:0]		in_error_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */

	always @(posedge clock_sig) begin
		if (clkena_reg) begin
			if (!tx_datavalid_sig && tx_fcs_sig) test_crs1_reg <= ~test_crs1_reg;
			else test_crs1_reg <= 1'b1;
			test_crs2_reg <= test_crs1_reg;
		end
		test_crs3_reg <= test_crs2_reg;
	end
	assign test_crs = test_crs3_reg;



/* ===== モジュール構造記述 ============== */

	// 10Mbps クロック分周

	always @(posedge clock_sig) begin
		if (SUPPORT_SPEED_10M && sel_speed10m) begin
			clkena_reg <= (!clkdiv_count_reg);
		end
		else begin
			clkena_reg <= 1'b1;
		end

		if (!clkdiv_count_reg) begin
			clkdiv_count_reg <= 4'd9;
		end
		else begin
			clkdiv_count_reg <= clkdiv_count_reg - 1'd1;
		end
	end


	// 半二重時のコリジョン検出 

	assign hafduplex_sig = (SUPPORT_HALFDUPLEX)? sel_halfduplex : 1'b0;

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			rxifg_count_reg <= 1'd0;
			late_count_reg <= 1'd0;
			crs_reg <= 1'b0;
			reject_reg <= 1'b0;
			collision_reg <= 1'b0;
		end
		else begin

			// キャリア占有時間カウンタ 
			if (crs_sig) begin
				rxifg_count_reg <= {1'b1, RXIFG_COUNT_VALUE[5:0]};
			end
			else if (clkena_reg && rxifg_count_reg[5:0] != 6'd0) begin
				rxifg_count_reg <= rxifg_count_reg + 1'd1;
			end

			// レイトコリジョンカウンタ 
			if (tx_ready_sig && in_sop && in_valid) begin
				late_count_reg <= {1'b1, LATE_COUNT_VALUE[4:0]};
			end
			else if (clkena_reg && !tx_working_sig && late_count_reg[5]) begin
				late_count_reg <= late_count_reg - 1'd1;
			end

			// コリジョン発生時の受信側破棄フラグ 
			if (clkena_reg) begin
				crs_reg <= crs_sig;

				if ((!crs_reg && crs_sig) || (crs_reg && !reject_reg)) begin
					reject_reg <= late_count_reg[5] & hafduplex_sig;
				end
			end

			// 送信側コリジョン検出 
			if (tx_ready_sig && in_sop && in_valid) begin
				collision_reg <= 1'b0;
			end
			else if (rx_working_sig && !collision_reg && late_count_reg[5]) begin
				collision_reg <= 1'b1;
			end

		end
	end

//	assign rx_enable_sig = (hafduplex_sig && !tx_working_sig);
	assign rx_working_sig = (hafduplex_sig)? (crs_sig | rxifg_count_reg[6]) : 1'b0;
	assign reject_sig = (IGNORE_COLLISION_DETECT)? 1'b0 : reject_reg;
	assign overflow_sig = (IGNORE_OVERFLOW_ERROR)? 1'b0 : out_error_sig[0];

	assign tx_enable_sig = ~rx_working_sig;
	assign tx_pausereq_sig = (!hafduplex_sig)? txpause_req : 1'b0;
	assign collision_sig = (IGNORE_COLLISION_DETECT)? 1'b0 : collision_reg;
	assign underflow_sig = (IGNORE_UNDERFLOW_ERROR)? 1'b0 : in_error_sig[0];


	// RMII受信モジュール 

	assign rxpause_req = (!hafduplex_sig)? rx_pausereq_sig : 1'b0;
	assign out_error = {out_error_sig[1] | reject_sig, overflow_sig};

	peridot_ethio_rmii_rx #(
		.IGNORE_FCS_CHECK		(IGNORE_RXFCS_CHECK),
		.IGNORE_MACADDR_FIELD	(IGNORE_MACADDR_FIELD),
		.ACCEPT_PAUSE_FRAME		(SUPPORT_PAUSEFRAME)
	)
	u_rx (
		.reset			(reset_sig),
		.clk			(clock_sig),
		.macaddr		(macaddr),
//		.rx_enable		(rx_enable_sig),
		.rx_enable		(1'b1),

		.pause_req		(rx_pausereq_sig),
		.pause_value	(rxpause_value),
		.pause_ack		(rxpause_ack),

		.out_ready		(out_ready),
		.out_valid		(out_valid),
		.out_data		(out_data),
		.out_sop		(out_sop),
		.out_eop		(out_eop),
		.out_error		(out_error_sig),

		.timing			(clkena_reg),
		.frame			(rx_frame),
		.crs			(crs_sig),
		.rmii_rxd		(rmii_rxd),
		.rmii_crsdv		(rmii_crsdv)
	);


	// RMII送信モジュール 

	assign in_ready = tx_ready_sig;
	assign in_error = {collision_sig, underflow_sig};

	peridot_ethio_rmii_tx #(
		.INTERFRAMEGAP_COUNT	(TX_INTERFRAMEGAP_COUNT),
		.IGNORE_MACADDR_FIELD	(IGNORE_MACADDR_FIELD),
		.ACCEPT_PAUSE_FRAME		(SUPPORT_PAUSEFRAME)
	)
	u_tx (
		.test_datavalid	(tx_datavalid_sig),		// テスト信号生成用 
		.test_fcs		(tx_fcs_sig),

		.reset			(reset_sig),
		.clk			(clock_sig),
		.macaddr		(macaddr),
		.tx_enable		(tx_enable_sig),

		.pause_req		(tx_pausereq_sig),
		.pause_value	(txpause_value),
		.pause_ack		(txpause_ack),

		.in_ready		(tx_ready_sig),
		.in_data		(in_data),
		.in_valid		(in_valid),
		.in_sop			(in_sop),
		.in_eop			(in_eop),
		.in_error		(in_error_sig),

		.timing			(clkena_reg),
		.frame			(tx_working_sig),
		.jam			(collision_sig | underflow_sig),
		.rmii_txd		(rmii_txd),
		.rmii_txen		(rmii_txen)
	);

	assign tx_frame = tx_working_sig;



endmodule

`default_nettype wire
