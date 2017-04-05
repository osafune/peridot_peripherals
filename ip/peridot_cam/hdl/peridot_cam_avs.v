// ===================================================================
// TITLE : PERIDOT-NGS / OV9655 I/F Register
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

// レジスタマップ 
// reg00 : bit31:irqena  bit30:irqreq  bit1:ready  bit0:start
// reg01 : bit15-0:Transfer Cycle
// reg02 : bit31-6:Destination Address
// reg03 : bit31-0:reserved

module peridot_cam_avs(
	// Interface: clk
	input wire			csi_global_reset,
	input wire			avs_s1_clk,

	// Interface: Avalon-MM Slave
	input wire [1:0]	avs_s1_address,
	input wire			avs_s1_write,
	input wire [31:0]	avs_s1_writedata,
	input wire			avs_s1_read,
	output wire [31:0]	avs_s1_readdata,
	output wire			avs_s1_irq,

	// External Interface
	output wire			start,						// '1'パルスでフレーム処理開始 
	input wire			done,
	input wire			framesync,					// フレーム開始信号 '0'→'1'の立ち上がりでフレーム同期 
	output wire			infiforeset,				// 入力FIFO非同期リセット出力 

	output wire [31:0]	capaddress_top,
	output wire [15:0]	capcycle_num
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */



/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = csi_global_reset;	// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			avs_clk_sig = avs_s1_clk;		// モジュール内部駆動クロック 

	reg  [2:0]		fsync_in_reg;
	wire			fsync_rise_sig;
	wire			fsync_fall_sig;
	reg  [2:0]		done_in_reg;
	wire			done_rise_sig;
	wire			done_fall_sig;

	reg				execution_reg;
	reg				fiforeset_reg;
	reg				irqena_reg;
	reg				irqreq_reg;
	reg  [31:6]		capaddress_reg;
	reg  [15:0]		capcyclenum_reg;

	(* altera_attribute = "-name CUT ON -to fsync_in_reg[0]; -name CUT ON -to done_in_reg[0]; -name CUT ON -from fiforeset_reg" *)


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	///// 非同期信号の同期化 /////

	always @(posedge avs_clk_sig or posedge reset_sig) begin
		if (reset_sig) begin
			fsync_in_reg <= 3'b000;
			done_in_reg  <= 3'b111;
		end
		else begin
			fsync_in_reg <= {fsync_in_reg[1:0], framesync};
			done_in_reg  <= {done_in_reg[1:0], done};
		end
	end

	assign fsync_rise_sig = (!fsync_in_reg[2] && fsync_in_reg[1])? 1'b1 : 1'b0;
	assign fsync_fall_sig = (fsync_in_reg[2] && !fsync_in_reg[1])? 1'b1 : 1'b0;

	assign done_rise_sig = (!done_in_reg[2] && done_in_reg[1])? 1'b1 : 1'b0;
	assign done_fall_sig = (done_in_reg[2] && !done_in_reg[1])? 1'b1 : 1'b0;



	///// Avalon-MMインターフェース /////

	assign start			= (execution_reg && fsync_rise_sig);
	assign infiforeset		= fiforeset_reg;

	assign capaddress_top	= {capaddress_reg, 6'b0};
	assign capcycle_num		= capcyclenum_reg;

	assign avs_s1_readdata	=	(avs_s1_address == 2'h0)? {irqena_reg, irqreq_reg, 28'b0, ~execution_reg, 1'b0} :
								(avs_s1_address == 2'h1)? {16'b0, capcyclenum_reg}	:
								(avs_s1_address == 2'h2)? {capaddress_reg, 6'b0}	:
								32'h00000000;

	assign avs_s1_irq		= (irqena_reg && irqreq_reg)? 1'b1 : 1'b0;


	always @(posedge avs_clk_sig or posedge reset_sig) begin
		if (reset_sig) begin
			execution_reg <= 1'b0;
			fiforeset_reg <= 1'b1;
			irqena_reg    <= 1'b0;
			irqreq_reg    <= 1'b0;
		end
		else begin
			if (fsync_rise_sig && execution_reg) begin
				fiforeset_reg <= 1'b0;
			end
			else if (done_rise_sig) begin
				fiforeset_reg <= 1'b1;
			end

			if (!execution_reg) begin
				if (avs_s1_write && avs_s1_address == 4'h0) begin
					execution_reg <= avs_s1_writedata[0];
				end
			end
			else if (done_rise_sig) begin
				execution_reg <= 1'b0;
			end

			if (done_rise_sig) begin
				irqreq_reg <= 1'b1;
			end
			else if (avs_s1_write && avs_s1_address == 4'h0 && avs_s1_writedata[30] == 1'b0) begin
				irqreq_reg <= 1'b0;
			end

			if (avs_s1_write) begin
				case (avs_s1_address)
					4'h0 : begin
						irqena_reg <= avs_s1_writedata[31];
					end
					4'h1 : begin
						capcyclenum_reg <= avs_s1_writedata[15:0];
					end
					4'h2 : begin
						capaddress_reg  <= avs_s1_writedata[31:6];
					end
				endcase
			end

		end
	end



endmodule
