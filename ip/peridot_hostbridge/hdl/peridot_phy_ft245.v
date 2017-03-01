// ===================================================================
// TITLE : PERIDOT-NGS / FT245 Asynchronous FIFO phy
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2017/01/31 -> 2017/02/15
//   UPDATE : 2017/03/01
//
// ===================================================================
// *******************************************************************
//      (C)2017, J-7SYSTEM WORKS LIMITED.  All rights Reserved.
//
// * This module is a free sourcecode and there is NO WARRANTY.
// * No restriction on use. You can use, modify and redistribute it
//   for personal, non-profit or commercial products UNDER YOUR
//   RESPONSIBILITY.
// * Redistributions of source code must retain the above copyright
//   notice.
// *******************************************************************

// アービトレーション動作 
//   受信データ優先、FIFOに送信されてきたデータがあれば全てなくなるまでTX側は待たされる。 
//   PERIDOTではホスト側が通信権を持つため、常にRX側を優先する。 

`timescale 1ns / 100ps

module peridot_phy_ft245 #(
	parameter CLOCK_FREQUENCY		= 50000000,
	parameter RD_ACTIVE_PULSE_WIDTH	= 60,		// rd_nの最短アサート時間(ns)
	parameter RD_PRECHARGE_TIME		= 50,		// rd_nの最短ネゲート時間(ns)
	parameter WR_ACTIVE_PULSE_WIDTH	= 60,		// wrの最短アサート時間(ns)
	parameter WR_PRECHARGE_TIME		= 50		// wrの最短ネゲート時間(ns)
) (
	// Interface: clk
	input wire			clk,
	input wire			reset,

	// Interface: ST source (RX)
	input wire			out_ready,
	output wire			out_valid,
	output wire [7:0]	out_data,

	// Interface: ST sink (TX)
	output wire			in_ready,
	input wire			in_valid,
	input wire  [7:0]	in_data,

	// Interface: Condit FT245 Async FIFO
	inout wire  [7:0]	ft_d,
	output wire			ft_rd_n,
	output wire			ft_wr,
	input wire			ft_rxf_n,
	input wire			ft_txe_n
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam CLOCK_FREQUENCY_KHZ = CLOCK_FREQUENCY / 1000;
	localparam NS_DIVIDE_NUMBER = 1000000;
	localparam RD_ASSERT_CYCLE = (RD_ACTIVE_PULSE_WIDTH * CLOCK_FREQUENCY_KHZ + (NS_DIVIDE_NUMBER-1)) / NS_DIVIDE_NUMBER;
	localparam RD_NEGATE_CYCLE = (RD_PRECHARGE_TIME     * CLOCK_FREQUENCY_KHZ + (NS_DIVIDE_NUMBER-1)) / NS_DIVIDE_NUMBER;
	localparam WR_ASSERT_CYCLE = (WR_ACTIVE_PULSE_WIDTH * CLOCK_FREQUENCY_KHZ + (NS_DIVIDE_NUMBER-1)) / NS_DIVIDE_NUMBER;
	localparam WR_NEGATE_CYCLE = (WR_PRECHARGE_TIME     * CLOCK_FREQUENCY_KHZ + (NS_DIVIDE_NUMBER-1)) / NS_DIVIDE_NUMBER;

	localparam RD_ASSERT_COUNT = (RD_ASSERT_CYCLE > 1)? RD_ASSERT_CYCLE-2 : 0;
	localparam RD_NEGATE_COUNT = (RD_NEGATE_CYCLE > 0)? RD_NEGATE_CYCLE-1 : 0;
	localparam WR_ASSERT_COUNT = (WR_ASSERT_CYCLE > 0)? WR_ASSERT_CYCLE-1 : 0;
	localparam WR_NEGATE_COUNT = (WR_NEGATE_CYCLE > 0)? WR_NEGATE_CYCLE-1 : 0;

	localparam 	STATE_IDLE		= 5'd0,
				STATE_RDWAIT	= 5'd1,
				STATE_GETDATA	= 5'd2,
				STATE_WRWAIT	= 5'd3,
				STATE_WRHOLD	= 5'd4,
				STATE_NEGATEWAIT= 5'd5;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = reset;				// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;				// モジュール内部駆動クロック 

	reg [1:0]		rxf_in_reg;
	reg [1:0]		txe_in_reg;
	reg [4:0]		state_reg;
	reg [6:0]		wait_count_reg;
	reg				rd_reg;
	reg				wr_reg;
	reg				oe_reg;
	reg  [7:0]		data_out_reg;
	wire [7:0]		data_in_sig;

	reg  [7:0]		outdata_reg;
	reg				outvalid_reg;
	wire			getdatareq_sig;
	wire			getdataack_sig;
	wire [7:0]		getdata_sig;

	wire			setdatareq_sig;
	wire [7:0]		setdata_sig;
	wire			setdataack_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	/////  Avalon-ST 出力 (RX) /////

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			outvalid_reg <= 1'b0;
		end
		else begin
			if (outvalid_reg) begin
				if (out_ready) begin
					outvalid_reg <= 1'b0;
				end
			end
			else begin
				if (getdataack_sig) begin
					outdata_reg <= getdata_sig;
					outvalid_reg <= 1'b1;
				end
			end
		end
	end

	assign getdatareq_sig = (!outvalid_reg);

	assign out_valid = outvalid_reg;
	assign out_data = outdata_reg;



	/////  Avalon-ST 入力 (TX) /////

	assign setdatareq_sig = (in_valid);
	assign setdata_sig = in_data;

	assign in_ready = (setdataack_sig)? 1'b1 : 1'b0;



	/////  FT245 非同期FIFOインターフェース /////

	assign getdataack_sig = (state_reg == STATE_GETDATA);
	assign getdata_sig = data_in_sig;

	assign setdataack_sig = (state_reg == STATE_WRHOLD);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			rxf_in_reg <= 2'b00;
			txe_in_reg <= 2'b00;
			state_reg <= STATE_IDLE;
			rd_reg <= 1'b0;
			wr_reg <= 1'b0;
			oe_reg <= 1'b0;
		end
		else begin
			rxf_in_reg <= {rxf_in_reg[0], ~ft_rxf_n};
			txe_in_reg <= {txe_in_reg[0], ~ft_txe_n};

			case (state_reg)
			STATE_IDLE : begin
				if (getdatareq_sig && rxf_in_reg[1]) begin
					state_reg <= STATE_RDWAIT;
					rd_reg <= 1'b1;
					wait_count_reg <= RD_ASSERT_COUNT[6:0];
				end
				else if (setdatareq_sig && txe_in_reg[1]) begin
					state_reg <= STATE_WRWAIT;
					wr_reg <= 1'b1;
					oe_reg <= 1'b1;
					data_out_reg <= setdata_sig;
					wait_count_reg <= WR_ASSERT_COUNT[6:0];
				end
			end

			STATE_RDWAIT : begin
				if (wait_count_reg == 0) begin
					state_reg <= STATE_GETDATA;
				end
				else begin
					wait_count_reg <= wait_count_reg - 1'd1;
				end
			end
			STATE_GETDATA : begin
				state_reg <= STATE_NEGATEWAIT;
				rd_reg <= 1'b0;
				wait_count_reg <= RD_NEGATE_COUNT[6:0];
			end

			STATE_WRWAIT : begin
				if (wait_count_reg == 0) begin
					state_reg <= STATE_WRHOLD;
					wr_reg <= 1'b0;
				end
				else begin
					wait_count_reg <= wait_count_reg - 1'd1;
				end
			end
			STATE_WRHOLD : begin
				state_reg <= STATE_NEGATEWAIT;
				oe_reg <= 1'b0;
				wait_count_reg <= WR_NEGATE_COUNT[6:0];
			end

			STATE_NEGATEWAIT : begin
				if (wait_count_reg == 0) begin
					state_reg <= STATE_IDLE;
				end
				else begin
					wait_count_reg <= wait_count_reg - 1'd1;
				end
			end

			endcase
		end
	end

	assign ft_d = (oe_reg)? data_out_reg : {8{1'bz}};
	assign data_in_sig = ft_d;
	assign ft_rd_n = ~rd_reg;
	assign ft_wr = wr_reg;



endmodule
