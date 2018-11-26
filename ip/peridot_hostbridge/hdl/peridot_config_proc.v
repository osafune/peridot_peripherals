// ===================================================================
// TITLE : PERIDOT-NGS / Configuration Layer Protocol
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2017/01/20 -> 2017/01/30
//   UPDATE : 2017/03/01
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


module peridot_config_proc (
	// Interface: clk
	input wire			clk,
	input wire			reset,

	// Interface: ST in (Up-stream side)
	output wire			in_ready,		// from rxd or usbin
	input wire			in_valid,
	input wire  [7:0]	in_data,

	input wire			out_ready,		// to infifo or byte2packet
	output wire			out_valid,
	output wire [7:0]	out_data,

	// Interface: ST in (Down-stream side)
	output wire			pk_ready,		// from packet2byte
	input wire			pk_valid,
	input wire  [7:0]	pk_data,

	input wire			resp_ready,		// to txd or usbout
	output wire			resp_valid,
	output wire [7:0]	resp_data,

	// Interface: Condit (i2c, config) - async signal
	output wire			reset_request,	// Qsys reset request signal

	output wire			ft_si,			// FTDI Send Immediate
	output wire			i2c_scl_o,
	input wire			i2c_scl_i,
	output wire			i2c_sda_o,
	input wire			i2c_sda_i,

	input wire			ru_bootsel,
	output wire			ru_nconfig,
	input wire			ru_nstatus
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam	STATE_IDLE		= 5'd0,
				STATE_ESCAPE	= 5'd1,
				STATE_CONFDATA	= 5'd2,
				STATE_SENDRESP	= 5'd3;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = reset;				// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;				// モジュール内部駆動クロック 

	reg  [4:0]		state_reg;
	reg				nconfig_reg;
	reg				ft_si_reg;
	reg				mode_reg;
	reg				scl_out_reg;
	reg				sda_out_reg;
	reg				bootsel_reg;
	reg				nstatus_reg;
	reg  			scl_in_reg;
	reg  			sda_in_reg;
	wire [7:0]		confresp_data_sig;

	wire			is_command_byte_sig;
	wire			in_valid_sig;
	wire [7:0]		in_data_sig;
	wire			out_ack_sig;
	wire			out_ready_sig;
	wire			out_valid_sig;
	wire			pk_valid_sig;
	wire [7:0]		pk_data_sig;
	wire			resp_ack_sig;
	wire			resp_ready_sig;
	wire			resp_valid_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	// コンフィグレーションレイヤシーケンサ 

	assign is_command_byte_sig = (state_reg == STATE_IDLE && in_valid_sig &&(in_data_sig == 8'h3a || in_data_sig == 8'h3d));

	assign in_ready = (is_command_byte_sig || state_reg == STATE_CONFDATA)? 1'b1 :
						(state_reg == STATE_SENDRESP)? 1'b0 :
						out_ready_sig;
	assign in_valid_sig = in_valid;
	assign in_data_sig = in_data;

	assign out_ack_sig = (out_ready_sig && out_valid_sig);
	assign out_ready_sig = (mode_reg)? out_ready : 1'b1;
	assign out_valid_sig = (is_command_byte_sig || state_reg == STATE_CONFDATA || state_reg == STATE_SENDRESP)? 1'b0 : in_valid_sig;
	assign out_valid = (mode_reg)? out_valid_sig : 1'b0;
														// コンフィグモード時にはデータを破棄する 
	assign out_data = (state_reg == STATE_ESCAPE)? in_data_sig ^ 8'h20 : in_data_sig;

	assign pk_ready = (state_reg == STATE_CONFDATA || state_reg == STATE_SENDRESP)? 1'b0 : resp_ready_sig;
	assign pk_valid_sig = pk_valid;
	assign pk_data_sig = pk_data;

	assign resp_ack_sig = (resp_ready_sig && resp_valid_sig);
	assign resp_ready_sig = resp_ready;
	assign resp_valid_sig = (state_reg == STATE_SENDRESP)? 1'b1 :
							(state_reg == STATE_CONFDATA)? 1'b0 :
							pk_valid_sig;
	assign resp_valid = resp_valid_sig;
	assign resp_data = (state_reg == STATE_SENDRESP)? confresp_data_sig : pk_data;


	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			state_reg <= STATE_IDLE;
			nconfig_reg <= 1'b1;
			ft_si_reg <= 1'b0;
			mode_reg <= 1'b1;
			scl_out_reg <= 1'b1;
			sda_out_reg <= 1'b1;
			bootsel_reg <= 1'b0;
			nstatus_reg <= 1'b0;
			scl_in_reg <= 1'b1;
			sda_in_reg <= 1'b1;
		end
		else begin
			case (state_reg)

			STATE_IDLE : begin
				if (in_valid_sig) begin
					if (in_data_sig == 8'h3a) begin			// コンフィグコマンド受信 
						state_reg <= STATE_CONFDATA;
					end
					else if (in_data_sig == 8'h3d) begin	// エスケープ指示子受信 
						state_reg <= STATE_ESCAPE;
					end
				end
			end

			STATE_ESCAPE : begin						// エスケープ指示子の2バイト目 
				if (out_ack_sig) begin
					state_reg <= STATE_IDLE;
				end
			end


			STATE_CONFDATA : begin						// コンフィグコマンドの2バイト目 
				if (in_valid_sig) begin
					state_reg <= STATE_SENDRESP;
					nconfig_reg <= in_data_sig[0];
					ft_si_reg <= in_data_sig[1];
					mode_reg <= in_data_sig[3];
					scl_out_reg <= in_data_sig[4];
					sda_out_reg <= in_data_sig[5];

					bootsel_reg <= ru_bootsel;
					nstatus_reg <= ru_nstatus;
					scl_in_reg <= i2c_scl_i;
					sda_in_reg <= i2c_sda_i;
				end
			end
			STATE_SENDRESP : begin						// レスポンスを返す 
				if (resp_ack_sig) begin
					state_reg <= STATE_IDLE;
				end
			end

			endcase

		end
	end


	// データ入出力 

	assign confresp_data_sig = {2'b00, sda_in_reg, scl_in_reg, 1'b0, {2{nstatus_reg}}, bootsel_reg};

	assign ru_nconfig = (!mode_reg)? nconfig_reg : 1'b1;

	assign reset_request = (!mode_reg)? 1'b1 : 1'b0;

	assign ft_si = ft_si_reg;

	assign i2c_scl_o = scl_out_reg;
	assign i2c_sda_o = sda_out_reg;



endmodule
