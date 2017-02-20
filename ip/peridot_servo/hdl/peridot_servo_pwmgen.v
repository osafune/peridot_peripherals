// ===================================================================
// TITLE : PERIDOT / RC Servo PWM Generator
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM Works)
//   DATE   : 2015/05/17 -> 2015/05/17
//   UPDATE : 2015/05/19 1bit⊿Σ変調出力追加 
//            2017/02/20
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

module peridot_servo_pwmgen #(
	parameter STARTSTEP		= 0,		// PWM開始ステップ数(0～2240)
	parameter MINWIDTHSTEP	= 64		// PWM最低幅(width_num=128の時に1.5ms幅となる値を指定する)
) (
	input			reset,
	input			clk,

	input			reg_write,
	input  [7:0]	reg_writedata,		// PWM幅レジスタ(0:最小～255:最大)
	output [7:0]	reg_readdata,

	input			pwm_enable,
	input			pwm_timing,
	input [12:0]	step_num,			// 0→2559のカウントアップ 
	output			pwm_out,			// サーボ波形の出力 
	output			dsm_out				// アナログ出力(1bit⊿Σ変調) 
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
