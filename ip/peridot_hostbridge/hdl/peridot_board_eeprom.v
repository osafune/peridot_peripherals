// ===================================================================
// TITLE : PERIDOT-NGS / board serial-rom emu
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2017/01/20 -> 2017/01/25
//   MODIFY : 2017/03/01
//          : 2017/05/11 EPCQ-UIDの読み出しに対応 
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

module peridot_board_eeprom #(
	parameter CHIPUID_FEATURE	= "ENABLE",
	parameter EPCQUID_FEATURE	= "DISABLE",
	parameter I2C_DEV_ADDRESS	= 7'b1010000,
	parameter DEVICE_FAMILY		= "",
	parameter PERIDOT_GENCODE	= 8'h4e,				// generation code
	parameter UID_VALUE			= 64'hffffffffffffffff	// fixed uid value
) (
	// Interface: clk
	input wire			clk,
	input wire			reset,

	// Interface: Condit (I2C)
	input wire			i2c_scl_i,
	output wire			i2c_scl_o,
	input wire			i2c_sda_i,
	output wire			i2c_sda_o,

	// Interface: Condit (UID)
	output wire			uid_enable,			// uid functon valid = '1' / invalid = '0'
	output wire [63:0]	uid,				// uid data
	output wire			uid_valid,			// uid datavalid = '1' / invalid = '0'
	input wire  [63:0]	spiuid,				// epcq uid data
	input wire			spiuid_valid		// epcq uid datavalid = '1' / invalid = '0'
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam	STATE_IDLE		= 5'd0,
				STATE_DEVSEL1	= 5'd1,
				STATE_SETADDR	= 5'd2,
				STATE_REPSTART	= 5'd3,
				STATE_DEVSEL2	= 5'd4,
				STATE_READBYTE	= 5'd5,
				STATE_WRITEBYTE	= 5'd6;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = reset;				// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;				// モジュール内部駆動クロック 

	wire			condi_start_sig;
	wire			condi_stop_sig;
	wire			done_byte_sig;
	wire			done_ack_sig;
	wire [7:0]		senddata_sig;
	wire			senddatavalid_sig;
	wire [7:0]		recievedata_sig;
	wire			recieveack_sig;
	reg				sendack_reg;

	reg  [4:0]		state_reg;
	reg  [4:0]		bytecount_reg;
	wire			romready_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	///// I2Cシリアルインターフェース /////

	peridot_board_i2c
	u0 (
		.clk				(clock_sig),
		.reset				(reset_sig),
		.i2c_scl_i			(i2c_scl_i),
		.i2c_scl_o			(i2c_scl_o),
		.i2c_sda_i			(i2c_sda_i),
		.i2c_sda_o			(i2c_sda_o),
		.condi_start		(condi_start_sig),
		.condi_stop			(condi_stop_sig),
		.done_byte			(done_byte_sig),
		.ackwaitrequest		(~romready_sig),
		.done_ack			(done_ack_sig),
		.send_bytedata		(senddata_sig),
		.send_bytedatavalid	(senddatavalid_sig),
		.recieve_bytedata	(recievedata_sig),
		.send_ackdata		(sendack_reg),
		.recieve_ackdata	(recieveack_sig)
	);



	///// EEPROMエミュレーションFSM /////

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			state_reg <= STATE_IDLE;
			sendack_reg <= 1'b0;
			bytecount_reg <= 1'd0;
		end
		else begin
			if (condi_stop_sig) begin
				state_reg <= STATE_IDLE;
				sendack_reg <= 1'b0;
			end
			else begin
				case (state_reg)

				STATE_IDLE : begin
					if (condi_start_sig) begin
						state_reg <= STATE_DEVSEL1;
					end
				end


				// カレントアドレスセット 

				STATE_DEVSEL1 : begin
					if (done_byte_sig) begin
						if (recievedata_sig[7:1] == I2C_DEV_ADDRESS && !recievedata_sig[0]) begin
							state_reg <= STATE_SETADDR;
							sendack_reg <= 1'b1;
						end
						else begin
							state_reg <= STATE_IDLE;
							sendack_reg <= 1'b0;
						end
					end
				end
				STATE_SETADDR : begin
					if (done_byte_sig) begin
						state_reg <= STATE_REPSTART;
						bytecount_reg <= recievedata_sig[4:0];
					end
				end


				// データリードライト 

				STATE_REPSTART : begin
					if (condi_start_sig) begin
						state_reg <= STATE_DEVSEL2;
					end
				end
				STATE_DEVSEL2 : begin
					if (done_byte_sig) begin
						if (recievedata_sig[7:1] == I2C_DEV_ADDRESS) begin
							sendack_reg <= 1'b1;

							if (recievedata_sig[0]) begin
								state_reg <= STATE_READBYTE;
							end
							else begin
								state_reg <= STATE_WRITEBYTE;
							end
						end
						else begin
							state_reg <= STATE_IDLE;
							sendack_reg <= 1'b0;
						end
					end
				end
				STATE_READBYTE : begin
					if (done_ack_sig) begin
						sendack_reg <= 1'b0;
					end

					if (done_byte_sig) begin
						bytecount_reg <= bytecount_reg + 1'd1;
					end
				end
				STATE_WRITEBYTE : begin			// データライトはダミー 
				end

				endcase
			end

		end
	end



	///// EEPROMデータ生成(UIDペリフェラル内蔵) /////

	peridot_board_romdata #(
		.CHIPUID_FEATURE	(CHIPUID_FEATURE),
		.EPCQUID_FEATURE	(EPCQUID_FEATURE),
		.DEVICE_FAMILY		(DEVICE_FAMILY),
		.PERIDOT_GENCODE	(PERIDOT_GENCODE),
		.UID_VALUE			(UID_VALUE)
	)
	u1 (
		.clk			(clock_sig),
		.reset			(reset_sig),
		.ready			(romready_sig),

		.byteaddr		(bytecount_reg),
		.bytedata		(senddata_sig),

		.uid_enable		(uid_enable),
		.uid			(uid),
		.uid_valid		(uid_valid),
		.spiuid			(spiuid),
		.spiuid_valid	(spiuid_valid)
	);

	assign senddatavalid_sig = (recieveack_sig && state_reg == STATE_READBYTE)? 1'b1 : 1'b0;



endmodule
