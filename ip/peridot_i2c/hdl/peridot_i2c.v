// ===================================================================
// TITLE : PERIDOT-NGS / I2C master
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2015/05/21 -> 2015/05/22
//   UPDATE : 2017/03/01
//
// ===================================================================
// *******************************************************************
//    (C)2015-2017, J-7SYSTEM WORKS LIMITED.  All rights Reserved.
//
// * This module is a free sourcecode and there is NO WARRANTY.
// * No restriction on use. You can use, modify and redistribute it
//   for personal, non-profit or commercial products UNDER YOUR
//   RESPONSIBILITY.
// * Redistributions of source code must retain the above copyright
//   notice.
// *******************************************************************

// reg00(+0)  bit15:irqena(RW), bit12:sta(WO), bit11:stp(WO), bit10:rd_nwr(WO), bit9:start(W)/ready(R), bit8:nack(RW), bit7-0:txdata(W)/rxdata(R)
// reg01(+4)  bit15:devrst(RW), bit9-0:clkdiv(RW)

module peridot_i2c (
	// Interface: clk
	input wire			csi_clk,
	input wire			rsi_reset,

	// Interface: Avalon-MM slave
	input wire  [0:0]	avs_address,
	input wire			avs_read,			// read  0-setup,1-wait,0-hold
	output wire [31:0]	avs_readdata,
	input wire			avs_write,			// write 0-setup,0-wait,0-hold
	input wire  [31:0]	avs_writedata,

	// Interface: Avalon-MM Interrupt sender
	output wire			ins_irq,

	// External Interface
	output wire			i2c_scl_oe,
	output wire			i2c_sda_oe,
	input wire			i2c_scl,
	input wire			i2c_sda
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam	STATE_IDLE		= 5'd0,
				STATE_INIT		= 5'd1,
				STATE_SC_1		= 5'd2,
				STATE_SC_2		= 5'd3,
				STATE_SC_3		= 5'd4,
				STATE_SC_4		= 5'd5,
				STATE_SC_5		= 5'd6,
				STATE_BIT_ENTRY	= 5'd7,
				STATE_BIT_1		= 5'd8,
				STATE_BIT_2		= 5'd9,
				STATE_BIT_3		= 5'd10,
				STATE_BIT_4		= 5'd11,
				STATE_PC_1		= 5'd13,
				STATE_PC_2		= 5'd14,
				STATE_PC_3		= 5'd15,
				STATE_DONE		= 5'd31;

	localparam	STATE_IO_IDLE	= 5'd0,
				STATE_IO_SETSCL	= 5'd1,
				STATE_IO_SETSDA	= 5'd2,
				STATE_IO_WAIT	= 5'd3,
				STATE_IO_DONE	= 5'd31;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = rsi_reset;			// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = csi_clk;			// モジュール内部駆動クロック 

	wire			begintransaction_sig;
	reg				irqena_reg;
	reg				sendstp_reg;
	reg				i2crst_reg;
	reg  [9:0]		divref_reg;

	reg  [4:0]		state_reg;
	reg				ready_reg;
	reg  [8:0]		txbyte_reg, rxbyte_reg;
	reg  [3:0]		bitcount;
	reg				setsclreq_reg, setsdareq_reg, pindata_reg;

	reg  [4:0]		state_io_reg;
	reg  [9:0]		divcount;
	wire			stateio_ack_sig;
	reg				scl_oe_reg, sda_oe_reg;
	reg  [1:0]		i2c_scl_in_reg, i2c_sda_in_reg;
	wire			scl_sig, sda_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	///// Avalon-MMインターフェース /////

	assign ins_irq = (irqena_reg)? ready_reg : 1'b0;

	assign avs_readdata =
			(avs_address == 1'd0)? {16'b0, irqena_reg, 5'b0, ready_reg, rxbyte_reg[0], rxbyte_reg[8:1]}:
			(avs_address == 1'd1)? {16'b0, i2crst_reg, 5'b0, divref_reg} :
			{32{1'bx}};

	assign begintransaction_sig = (avs_write && avs_address == 1'd0 && avs_writedata[9]);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			i2crst_reg <= 1'b1;
			irqena_reg <= 1'b0;
			divref_reg <= 10'h3ff;
		end
		else begin

			// リセットレジスタの読み書き 
			if (avs_write && avs_address == 1'd1) begin
				i2crst_reg <= avs_writedata[15];
			end

			// ステータスレジスタの読み書き 
			if (i2crst_reg) begin
				irqena_reg <= 1'b0;
			end
			else begin
				if (avs_write && ready_reg) begin
					case (avs_address)
					1'd0 : begin
						irqena_reg  <= avs_writedata[15];
					end
					1'd1 : begin
						divref_reg  <= avs_writedata[9:0];
					end
					endcase
				end
			end

		end
	end



	///// I2C送受信処理 /////

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			state_reg  <= STATE_INIT;
			ready_reg  <= 1'b0;
			setsclreq_reg <= 1'b0;
			setsdareq_reg <= 1'b0;
		end
		else begin
			if (i2crst_reg) begin
				state_reg  <= STATE_INIT;
				ready_reg  <= 1'b0;
				setsclreq_reg <= 1'b0;
				setsdareq_reg <= 1'b0;
			end
			else begin

				case (state_reg)

				// 初期化 

				STATE_INIT : begin
					if (sda_sig == 1'b1 && scl_sig == 1'b1) begin
						state_reg <= STATE_IDLE;
						ready_reg <= 1'b1;
					end
				end


				// トランザクション開始受付 

				STATE_IDLE : begin
					if (begintransaction_sig) begin
						ready_reg <= 1'b0;

						if (avs_writedata[12]) begin
							state_reg <= STATE_SC_1;
						end
						else begin
							state_reg <= STATE_BIT_ENTRY;
						end

						sendstp_reg <= avs_writedata[11];

						if (avs_writedata[10]) begin	// read
							txbyte_reg <= {8'hff, avs_writedata[8]};
						end
						else begin						// write
							txbyte_reg <= {avs_writedata[7:0], 1'b1};
						end
					end
				end


				// STARTコンディション発行 (SDA = 'H'の状態で開始する)

				STATE_SC_1 : begin				// SCL = 'H'
					state_reg <= STATE_SC_2;
					setsclreq_reg <= 1'b1;
					pindata_reg   <= 1'b1;
				end
				STATE_SC_2 : begin				// SDA = 'L'
					if (stateio_ack_sig) begin
						state_reg <= STATE_SC_3;
						setsclreq_reg <= 1'b0;
						setsdareq_reg <= 1'b1;
						pindata_reg   <= 1'b0;
					end
				end
				STATE_SC_3 : begin				// tSU(STA) wait
					if (stateio_ack_sig) begin
						state_reg <= STATE_SC_4;
					end
				end
				STATE_SC_4 : begin				// SCL = 'L'
					if (stateio_ack_sig) begin
						state_reg <= STATE_SC_5;
						setsclreq_reg <= 1'b1;
						setsdareq_reg <= 1'b0;
						pindata_reg   <= 1'b0;
					end
				end
				STATE_SC_5 : begin
					if (stateio_ack_sig) begin
						state_reg <= STATE_BIT_ENTRY;
						setsclreq_reg <= 1'b0;
					end
				end


				// ビット読み書き (SCL = 'L'の状態で開始する) 

				STATE_BIT_ENTRY : begin				// data set 
					state_reg <= STATE_BIT_1;
					setsdareq_reg <= 1'b1;
					pindata_reg   <= txbyte_reg[8];

					bitcount <= 1'd0;
				end
				STATE_BIT_1 : begin					// SCL = 'H'
					if (stateio_ack_sig) begin
						state_reg <= STATE_BIT_2;
						setsclreq_reg <= 1'b1;
						setsdareq_reg <= 1'b0;
						pindata_reg   <= 1'b1;
					end
				end
				STATE_BIT_2 : begin					// data latch & shift
					if (stateio_ack_sig) begin
						state_reg <= STATE_BIT_3;

						txbyte_reg <= {txbyte_reg[7:0], 1'b0};
						rxbyte_reg <= {rxbyte_reg[7:0], sda_sig};
					end
				end
				STATE_BIT_3 : begin					// SCL = 'L'
					if (stateio_ack_sig) begin
						state_reg <= STATE_BIT_4;
						pindata_reg <= 1'b0;
					end
				end
				STATE_BIT_4 : begin					// next data set
					if (stateio_ack_sig) begin
						setsclreq_reg <= 1'b0;
						setsdareq_reg <= 1'b1;

						if (bitcount == 8) begin
							if (sendstp_reg) begin		// SDA = 'L' (STOP condition)
								state_reg <= STATE_PC_1;
								pindata_reg <= 1'b0;
							end
							else begin					// SDA = 'H' (ACK release)
								state_reg <= STATE_DONE;
								pindata_reg <= 1'b1;
							end
						end
						else begin						// SDA = next bit (bit transfer)
							state_reg <= STATE_BIT_1;
							pindata_reg <= txbyte_reg[8];
						end

						bitcount <= bitcount + 1'd1;
					end
				end


				// STOPコンディション発行 

				STATE_PC_1 : begin					// SCL = 'H'
					if (stateio_ack_sig) begin
						state_reg <= STATE_PC_2;
						setsclreq_reg <= 1'b1;
						setsdareq_reg <= 1'b0;
						pindata_reg   <= 1'b1;
					end
				end
				STATE_PC_2 : begin					// tH(STO) wait
					if (stateio_ack_sig) begin
						state_reg <= STATE_PC_3;
					end
				end
				STATE_PC_3 : begin					// SDA = 'H'
					if (stateio_ack_sig) begin
						state_reg <= STATE_DONE;
						setsclreq_reg <= 1'b0;
						setsdareq_reg <= 1'b1;
						pindata_reg   <= 1'b1;
					end
				end


				// トランザクション終了 

				STATE_DONE : begin
					if (stateio_ack_sig) begin
						state_reg <= STATE_IDLE;
						setsclreq_reg <= 1'b0;
						setsdareq_reg <= 1'b0;
						ready_reg <= 1'b1;
					end
				end

				endcase
			end
		end
	end



	///// I2C信号入出力 /////

	assign i2c_scl_oe = scl_oe_reg;
	assign i2c_sda_oe = sda_oe_reg;
	assign scl_sig = i2c_scl_in_reg[1];
	assign sda_sig = i2c_sda_in_reg[1];

	assign stateio_ack_sig = (state_io_reg == STATE_IO_DONE);

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			i2c_scl_in_reg <= 2'b00;
			i2c_sda_in_reg <= 2'b00;

			state_io_reg <= STATE_IO_IDLE;
			scl_oe_reg   <= 1'b0;
			sda_oe_reg   <= 1'b0;
		end
		else begin
			i2c_scl_in_reg <= {i2c_scl_in_reg[0], i2c_scl};
			i2c_sda_in_reg <= {i2c_sda_in_reg[0], i2c_sda};

			if (i2crst_reg) begin
				state_io_reg <= STATE_IO_IDLE;
				scl_oe_reg   <= 1'b0;
				sda_oe_reg   <= 1'b0;
			end
			else begin
				case (state_io_reg)

				STATE_IO_IDLE : begin
					if (setsclreq_reg) begin
						state_io_reg <= STATE_IO_SETSCL;
						scl_oe_reg   <= ~pindata_reg;
					end
					else if (setsdareq_reg) begin
						state_io_reg <= STATE_IO_SETSDA;
						sda_oe_reg   <= ~pindata_reg;
					end
				end

				// SCL set
				STATE_IO_SETSCL : begin
					if (scl_sig != scl_oe_reg) begin
						state_io_reg <= STATE_IO_WAIT;
						divcount     <= divref_reg;
					end
				end

				// SDA set
				STATE_IO_SETSDA : begin
					state_io_reg <= STATE_IO_WAIT;
					divcount     <= divref_reg;
				end

				// wait
				STATE_IO_WAIT : begin
					if (divcount == 0) begin
						state_io_reg <= STATE_IO_DONE;
					end
					else begin
						divcount <= divcount - 1'd1;
					end
				end

				STATE_IO_DONE : begin
					state_io_reg <= STATE_IO_IDLE;
				end

				endcase
			end
		end
	end



endmodule
