// ===================================================================
// TITLE : PERIDOT-NGS / Simple SCCB host
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2018/01/22 -> 2018/01/22
//   MODIFY : 2022/12/07 レジスタマップ修正(4-phase writeモード対応)
//
// ===================================================================
//
// The MIT License (MIT)
// Copyright (c) 2017,2018 J-7SYSTEM WORKS LIMITED.
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

// reg00(+0)  bit31:waitena(W)/busy(R)
//            bit22-16:devaddr(W), bit15-8:subaddr(W), bit7-0:data(W) : 3-phase write (bit30-24 must be 0)
//            bit30-24:devaddr(W), bit23-8:subaddr(W), bit7-0:data(W) : 4-phase write


// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_cam_sccb #(
	parameter AVS_CLOCKFREQ			= 25000000,			// peripheral drive clock freq(Hz) - up to 100MHz
	parameter SCCB_CLOCKFREQ		= 400000			// SCCB clock freq(Hz) - 400kHz typ
) (
	// Interface: clk
	input wire			csi_clk,
	input wire			rsi_reset,

	// Interface: Avalon-MM slave
	input wire			avs_read,			// read  0-setup,0-wait,0-hold
	output wire [31:0]	avs_readdata,
	input wire			avs_write,			// write 0-setup,0-wait,0-hold
	input wire  [31:0]	avs_writedata,
	output wire			avs_waitrequest,

	// External Interface
	output wire			sccb_clk_oe,
	output wire			sccb_data_oe
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam CLOCK_DIVNUM = ((AVS_CLOCKFREQ + (SCCB_CLOCKFREQ * 2) - 1) / (SCCB_CLOCKFREQ * 2)) - 1;
//	localparam CLOCK_DIVNUM = 3;
	localparam DIVCOUNT_WIDTH = 9;

	localparam	STATE_IDLE		= 5'd0,
				STATE_START		= 5'd1,
				STATE_BIT		= 5'd2,
				STATE_STOP		= 5'd3,
				STATE_WAIT		= 5'd4,
				STATE_DONE		= 5'd31;

	localparam	STATE_IO_HOLD	= 5'd0,
				STATE_IO_SET0	= 5'd1,
				STATE_IO_SET1	= 5'd2;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = rsi_reset;			// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = csi_clk;			// モジュール内部駆動クロック 

	reg  [4:0]		state_reg;
	reg				ready_reg;
	reg				waitreq_reg;
	reg  [5:0]		bitcount;
	reg				iostart_req_reg;
	reg  [35:0]		txdara_reg;
	wire			begintransaction_sig;
	wire [1:0]		txclk_sig, txdata_sig;


	reg  [4:0]		state_io_reg;
	reg  [DIVCOUNT_WIDTH-1:0] divcount;
	wire			stateio_ack_sig;
	reg				cout_reg, dout_reg;



/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	///// Avalon-MMインターフェース /////

	assign avs_readdata = {~ready_reg, {31{1'bx}}};
	assign avs_waitrequest = ((avs_write || avs_read) && waitreq_reg)? ~ready_reg : 1'b0;


	///// SCCBのwriteトランザクションを発行する /////

	assign begintransaction_sig = iostart_req_reg;

	assign txclk_sig = 	(state_reg == STATE_START)?	2'b10 :
						(state_reg == STATE_BIT)?	2'b01 :
						(state_reg == STATE_STOP)?	2'b01 :
						2'b11;
	assign txdata_sig = (state_reg == STATE_START)?	2'b00 :
						(state_reg == STATE_BIT)?	{2{txdara_reg[35]}} :
						(state_reg == STATE_STOP)?	2'b00 :
						2'b11;


	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			state_reg <= STATE_IDLE;
			ready_reg <= 1'b1;
			waitreq_reg <= 1'b0;
			iostart_req_reg <= 1'b0;
		end
		else begin
			case (state_reg)

			// Avalon-MMレジスタ書き込みおよびトランザクション開始 
			STATE_IDLE : begin
				if (avs_write) begin
					state_reg <= STATE_START;
					ready_reg <= 1'b0;
					iostart_req_reg <= 1'b1;
					waitreq_reg <= avs_writedata[31];
					txdara_reg[8:0] <= {avs_writedata[7:0], 1'b1};

					if (avs_writedata[30:24]) begin		// 4-phase write
						txdara_reg[35:27] <= {avs_writedata[30:24], 2'b01};
						txdara_reg[26:18] <= {avs_writedata[23:16], 1'b1};
						txdara_reg[17: 9] <= {avs_writedata[15: 8], 1'b1};
						bitcount <= 6'd35;
					end
					else begin							// 3-phase write
						txdara_reg[35:27] <= {avs_writedata[22:16], 2'b01};
						txdara_reg[26:18] <= {avs_writedata[15: 8], 1'b1};
						txdara_reg[17: 9] <= {avs_writedata[ 7: 0], 1'b1};
						bitcount <= 6'd26;
					end
				end
			end


			// スタートコンディション発行 
			STATE_START : begin
				if (stateio_ack_sig) begin
					state_reg <= STATE_BIT;
				end
			end

			// データビット送信 
			STATE_BIT : begin
				if (stateio_ack_sig) begin
					txdara_reg <= {txdara_reg[34:0], 1'b0};
					bitcount <= bitcount - 1'd1;

					if (bitcount) begin
						state_reg <= STATE_BIT;
					end
					else begin
						state_reg <= STATE_STOP;
					end
				end
			end

			// ストップコンディション発行 
			STATE_STOP : begin
				if (stateio_ack_sig) begin
					state_reg <= STATE_WAIT;
				end
			end

			// ステート終了およびカメラ側レジスタ更新待ち 
			STATE_WAIT : begin
				if (stateio_ack_sig) begin
					state_reg <= STATE_DONE;
				end
			end

			STATE_DONE : begin
				if (iostart_req_reg) begin
					iostart_req_reg <= 1'b0;
				end
				else if (stateio_ack_sig) begin
					state_reg <= STATE_IDLE;
					ready_reg <= 1'b1;
				end
			end

			endcase
		end
	end



    ///// SCCBの1ビット分の送信をする /////

	assign sccb_clk_oe  = (!cout_reg)? 1'b1 : 1'b0;
	assign sccb_data_oe = (!dout_reg)? 1'b1 : 1'b0;

	assign stateio_ack_sig = (state_io_reg == STATE_IO_SET1 && !divcount);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			state_io_reg <= STATE_IO_HOLD;
			cout_reg <= 1'b1;
			dout_reg <= 1'b1;
		end
		else begin
			case (state_io_reg)

			STATE_IO_HOLD : begin
				if (begintransaction_sig) begin
					state_io_reg <= STATE_IO_SET0;
					divcount <= CLOCK_DIVNUM[DIVCOUNT_WIDTH-1:0];
					cout_reg <= txclk_sig[1];
					dout_reg <= txdata_sig[1];
				end
			end

			// 前半シンボル 
			STATE_IO_SET0 : begin
				if (divcount) begin
					divcount <= divcount - 1'd1;
				end
				else begin
					state_io_reg <= STATE_IO_SET1;
					divcount <= CLOCK_DIVNUM[DIVCOUNT_WIDTH-1:0];
					cout_reg <= txclk_sig[0];
					dout_reg <= txdata_sig[0];
				end
			end

			// 後半シンボル 
			STATE_IO_SET1 : begin
				if (divcount) begin
					divcount <= divcount - 1'd1;
				end
				else begin
					state_io_reg <= STATE_IO_HOLD;
				end
			end

			endcase
		end
	end



endmodule
