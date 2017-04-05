// ===================================================================
// TITLE : PERIDOT-NGS / OV9655 AvalonMM burst master(32bit×16burst)
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2017/04/04 -> 2017/04/06
//   UPDATE : 
//
// ===================================================================
// *******************************************************************
//        (C)2017 J-7SYSTEM WORKS LIMITED.  All rights Reserved.
//
// * This module is a free sourcecode and there is NO WARRANTY.
// * No restriction on use. You can use, modify and redistribute it
//   for personal, non-profit or commercial products UNDER YOUR
//   RESPONSIBILITY.
// * Redistributions of source code must retain the above copyright
//   notice.
// *******************************************************************


module peridot_cam_avm(
	// Interface: clk
	input wire			csi_global_reset,
	input wire			avm_m1_clk,

	// Interface: Avalon-MM master
	output wire [31:0]	avm_m1_address,
	output wire			avm_m1_write,
	output wire [31:0]	avm_m1_writedata,
	output wire [3:0]	avm_m1_byteenable,
	output wire [4:0]	avm_m1_burstcount,			// 16バースト固定 
	input wire			avm_m1_waitrequest,

	// External Interface
	input wire [31:0]	address_top,				// ストア先頭アドレス(下位6bit無効) 
	input wire [15:0]	transcycle_num,				// ストア回数(最大65535回=4194240バイト) 
	input wire			start,
	output wire			done,

	input wire			writedata_ready,			// データFIFOに16個揃ったら'1'になる 
	input wire [31:0]	writedata,
	output wire			writedata_rdack
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam STATE_IDLE         = 5'd0;
	localparam STATE_SETUP        = 5'd1;
	localparam STATE_BURSTWRITE   = 5'd2;
	localparam STATE_LOOP         = 5'd30;
	localparam STATE_DONE         = 5'd31;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = csi_global_reset;	// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			avm_clk_sig = avm_m1_clk;		// Avalonバス駆動クロック 

	reg  [4:0]		avmstate_reg;
	reg				done_reg;
	reg  [15:0]		chunkcount_reg;

	reg  [4:0]		datacount_reg;
	reg  [31:0]		address_reg;
	reg				write_reg;

	wire [31:0]		avm_writedata_sig;
	wire			avm_wriredataack_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	assign done = done_reg;

	assign avm_writedata_sig = writedata;
	assign writedata_rdack   = avm_wriredataack_sig;


	///// AvalonMMトランザクション処理 /////

	assign avm_wriredataack_sig = (write_reg && !avm_m1_waitrequest)? 1'b1 : 1'b0;	// データ要求 

	assign avm_m1_address    = {address_reg[31:6], 6'b000000};
	assign avm_m1_write      = write_reg;
	assign avm_m1_writedata  = avm_writedata_sig;
	assign avm_m1_byteenable = 4'b1111;				// 4バイトライト固定 
	assign avm_m1_burstcount = 5'd16;				// 16ポイントバースト固定 


	always @(posedge avm_clk_sig or posedge reset_sig) begin
		if (reset_sig) begin
			avmstate_reg <= STATE_IDLE;
			done_reg     <= 1'b1;
			write_reg    <= 1'b0;

			chunkcount_reg <= 16'd0;
			datacount_reg  <= 5'd0;
		end
		else begin

			case (avmstate_reg)
				STATE_IDLE : begin					// IDLE 
					if ( start ) begin
						avmstate_reg   <= STATE_SETUP;
						done_reg       <= 1'b0;
						chunkcount_reg <= transcycle_num;
						address_reg    <= address_top;
					end
				end

				STATE_SETUP : begin					// バーストセットアップ 
					if ( writedata_ready ) begin
						avmstate_reg   <= STATE_BURSTWRITE;
						write_reg      <= 1'b1;
						datacount_reg  <= 5'd15;
					end
				end

				STATE_BURSTWRITE : begin			// データバーストライト 
					if ( !avm_m1_waitrequest ) begin
						if (datacount_reg == 1'd0) begin
							avmstate_reg  <= STATE_LOOP;
							write_reg     <= 1'b0;
							chunkcount_reg<= chunkcount_reg - 1'd1;
						end
						else begin
							datacount_reg <= datacount_reg - 1'd1;
						end
					end
				end

				STATE_LOOP : begin					// ループカウント 
					if ( chunkcount_reg == 1'd0 ) begin
						avmstate_reg <= STATE_DONE;
					end
					else begin
						avmstate_reg <= STATE_SETUP;
						address_reg  <= address_reg + 32'd64;
					end

				end

				STATE_DONE : begin					// ステート終了 
					avmstate_reg <= STATE_IDLE;
					done_reg     <= 1'b1;
				end

			endcase

		end
	end



endmodule
