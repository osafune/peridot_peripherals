// ===================================================================
// TITLE : PERIDOT-NGS / OV9655 I/F
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


module peridot_cam(
	// Interface: clk
	input wire			csi_global_reset,
	input wire			csi_global_clk,

	// Interface: Avalon-MM Slave
	input wire  [1:0]	avs_s1_address,
	input wire			avs_s1_write,
	input wire  [31:0]	avs_s1_writedata,
	input wire			avs_s1_read,
	output wire [31:0]	avs_s1_readdata,
	output wire			avs_s1_irq,

	// Interface: Avalon-MM master
	input wire			avm_m1_clk,				// Avalonマスタ側クロック 
	output wire [31:0]	avm_m1_address,
	output wire			avm_m1_write,
	output wire [31:0]	avm_m1_writedata,
	output wire [3:0]	avm_m1_byteenable,
	output wire [4:0]	avm_m1_burstcount,
	input wire			avm_m1_waitrequest,

	// External Interface
	input			cam_clk,					// カメラクロック(48MHz)
	input  [9:2]	cam_data,
	input			cam_href,
	input			cam_vsync
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = csi_global_reset;	// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = csi_global_clk;		// モジュール内部駆動クロック 
	wire			avmclk_sig = avm_m1_clk;		// AvalonMMマスタクロック 
	wire			camclk_sig = cam_clk;			// カメラデータクロック 

	wire			start_sig;
	wire			done_sig;
	wire			framesync_sig;
	wire			infiforeset_sig;
	wire [31:0]		capaddress_sig;
	wire [15:0]		capcyclenum_sig;

	reg  [7:0]		camdata_reg;
	reg				camhref_reg;
	reg				camvsync_reg;
	wire [8:0]		rdusedw_sig;

	wire			writedataready_sig;
	wire [31:0]		writedata_sig;
	wire			writedatardack_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */

//	assign test_rdusedw = rdusedw_sig;
//	assign test_dataready = writedataready_sig;
//	assign test_datardack = writedatardack_sig;


/* ===== モジュール構造記述 ============== */


	// AvalonMM-スレーブモジュール 

	peridot_cam_avs
	u0 (
		.csi_global_reset	(reset_sig),
		.avs_s1_clk			(clock_sig),
		.avs_s1_address		(avs_s1_address),
		.avs_s1_write		(avs_s1_write),
		.avs_s1_writedata	(avs_s1_writedata),
		.avs_s1_read		(avs_s1_read),
		.avs_s1_readdata	(avs_s1_readdata),
		.avs_s1_irq			(avs_s1_irq),

		.start				(start_sig),		// '1'パルスでフレーム処理開始 
		.done				(done_sig),
		.framesync			(framesync_sig),	// フレーム開始信号 
		.infiforeset		(infiforeset_sig),	// 入力FIFO非同期リセット出力 
		.capaddress_top		(capaddress_sig),
		.capcycle_num		(capcyclenum_sig)
	);



	// OV9655入力FIFO 

	always @(posedge camclk_sig) begin
		camdata_reg  <= cam_data;
		camhref_reg  <= cam_href;
		camvsync_reg <= cam_vsync;
	end
/*
	cam_infifo
	u1 (
		.aclr		(infiforeset_sig),

		.wrclk		(camclk_sig),
		.wrreq		(camhref_reg),
		.data		(camdata_reg),

		.rdclk		(avmclk_sig),
		.rdreq		(writedatardack_sig),
		.q			(writedata_sig),
		.rdusedw	(rdusedw_sig)
	);
*/
	dcfifo_mixed_widths #(
		.add_usedw_msb_bit	("ON"),
		.lpm_numwords		(1024),
		.lpm_showahead		("ON"),
		.lpm_type			("dcfifo_mixed_widths"),
		.lpm_width			(8),
		.lpm_widthu			(11),
		.lpm_width_r		(32),
		.lpm_widthu_r		(9),
		.overflow_checking	("ON"),
		.rdsync_delaypipe	(4),
		.read_aclr_synch	("ON"),
		.underflow_checking	("ON"),
		.use_eab			("ON"),
		.write_aclr_synch	("ON"),
		.wrsync_delaypipe	(4)
	)
	u1 (
		.aclr		(infiforeset_sig),
		.wrclk		(camclk_sig),
		.wrreq		(camhref_reg),
		.data		(camdata_reg),

		.rdclk		(avmclk_sig),
		.rdreq		(writedatardack_sig),
		.q			(writedata_sig),
		.rdusedw	(rdusedw_sig)
	);

	assign writedataready_sig = (rdusedw_sig > 9'd15)? 1'b1 : 1'b0;		// 16ワード以上FIFOに入っている 
	assign framesync_sig      = camvsync_reg;



	// AvalonMM-マスタモジュール 

	peridot_cam_avm
	u2 (
		.csi_global_reset	(reset_sig),
		.avm_m1_clk			(avmclk_sig),
		.avm_m1_address		(avm_m1_address),
		.avm_m1_write		(avm_m1_write),
		.avm_m1_writedata	(avm_m1_writedata),
		.avm_m1_byteenable	(avm_m1_byteenable),
		.avm_m1_burstcount	(avm_m1_burstcount),
		.avm_m1_waitrequest	(avm_m1_waitrequest),

		.address_top		(capaddress_sig),
		.transcycle_num		(capcyclenum_sig),
		.start				(start_sig),
		.done				(done_sig),

		.writedata_ready	(writedataready_sig),
		.writedata			(writedata_sig),
		.writedata_rdack	(writedatardack_sig)
	);



endmodule
