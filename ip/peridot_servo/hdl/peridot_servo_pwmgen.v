// ===================================================================
// TITLE : PERIDOT-NGS / RC Servo PWM Generator
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2015/05/17 -> 2015/05/17
//   UPDATE : 2015/05/19 1bit⊿Σ変調出力追加 
//            2018/11/26 17.1 beta
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

module peridot_servo_pwmgen #(
	parameter STARTSTEP		= 0,		// PWM開始ステップ数(0～2240)
	parameter MINWIDTHSTEP	= 64		// PWM最低幅(width_num=128の時に1.5ms幅となる値を指定する)
) (
	input wire			reset,
	input wire			clk,

	input wire			reg_write,
	input wire  [7:0]	reg_writedata,		// PWM幅レジスタ(0:最小～255:最大)
	output wire [7:0]	reg_readdata,

	input wire			pwm_enable,
	input wire			pwm_timing,
	input wire [12:0]	step_num,			// 0→2559のカウントアップ 
	output wire			pwm_out,			// サーボ波形の出力 
	output wire			dsm_out				// アナログ出力(1bit⊿Σ変調) 
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	wire [31:0]		pwmwidth_init_sig = STARTSTEP + MINWIDTHSTEP;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = reset;				// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;				// モジュール内部駆動クロック 

	reg  [7:0]		width_reg;
	reg  [12:0]		pwmwidth_reg;
	reg				pwmout_reg;
	reg  [8:0]		dsm_reg;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	assign reg_readdata = width_reg;
	assign pwm_out = pwmout_reg;
	assign dsm_out = dsm_reg[8];

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			width_reg  <= 8'd128;
			pwmout_reg <= 1'b0;
			dsm_reg    <= 1'd0;
		end
		else begin
			if (reg_write) begin
				width_reg <= reg_writedata;
			end

			if (pwm_enable) begin
				if (pwm_timing) begin
					if (step_num == STARTSTEP) begin
						pwmout_reg   <= 1'b1;
						pwmwidth_reg <= pwmwidth_init_sig[12:0] + {5'b0, width_reg};
					end
					else if (step_num == pwmwidth_reg) begin
						pwmout_reg <= 1'b0;
					end
				end
			end
			else begin
				pwmout_reg <= 1'b0;
			end

			dsm_reg <= {1'b0, dsm_reg[7:0]} + {1'b0, width_reg};
		end
	end


endmodule
