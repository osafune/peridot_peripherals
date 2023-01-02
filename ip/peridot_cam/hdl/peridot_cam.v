// ===================================================================
// TITLE : PERIDOT-NGS / OmniVision DVP I/F
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2017/04/04 -> 2017/04/06
//   MODIFY : 2018/01/22
//            2021/12/30 Byte swapオプション追加、開始信号の同期化を修正 
//            2022/01/11 SCCB I/Fオプション追加 
//            2022/12/22 SDC修正, IOEレジスタオプション追加 
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


// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_cam #(
	parameter AVM_CLOCKFREQ			= 100000000,	// AVM drive clock freq(Hz)
	parameter AVS_CLOCKFREQ			= 25000000,		// AVS drive clock freq(Hz) - up to 100MHz
	parameter DVP_FIFO_DEPTH		= 10,			// DVP input fifo 10:1024bytes, 11:2048bytes, 12:4096bytes
	parameter DVP_BYTESWAP			= "ON",			// Upper byte and lower byte are exchanged and stored.
	parameter USE_SCCBINTERFACE		= "ON",			// Use internal sccb module
	parameter USE_PERIDOT_I2C		= "OFF",		// Instance PERIDOT_I2C as an sccb module
	parameter SCCB_CLOCKFREQ		= 400000		// SCCB clock freq(Hz) - 400kHz typ
) (
	// Interface: clk
	input wire			csi_global_reset,
	input wire			csi_global_clk,

	// Interface: Avalon-MM Slave
	input wire  [1:0]	avs_s1_address,
	input wire			avs_s1_write,
	input wire  [31:0]	avs_s1_writedata,
	input wire			avs_s1_read,
	output wire [31:0]	avs_s1_readdata,
	output wire			avs_s1_waitrequest,
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
	input wire			cam_clk,				// カメラクロック(typ 48MHz)
	input wire  [9:2]	cam_data,
	input wire			cam_href,
	input wire			cam_vsync,
	output wire			cam_reset_n,
	inout wire			sccb_sck,
	inout wire			sccb_data
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam DC_FIFO_NUMWORDS = 2**DVP_FIFO_DEPTH;
	localparam DC_FIFO_WIDTHU = DVP_FIFO_DEPTH + 1;
	localparam DC_FIFO_WIDTHU_R = DVP_FIFO_DEPTH - 1;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = csi_global_reset;	// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = csi_global_clk;		// モジュール内部駆動クロック 
	wire			avmclk_sig = avm_m1_clk;		// AvalonMMマスタクロック 
	wire			camclk_sig = cam_clk;			// カメラデータクロック 

	wire			execution_sig;
	wire			done_sig;
	wire			framesync_sig;
	wire			infiforeset_sig;
	wire [31:0]		capaddress_sig;
	wire [15:0]		capcyclenum_sig;

	reg  [7:0]		camdata_reg /* synthesis ALTERA_ATTRIBUTE = "FAST_INPUT_REGISTER=ON" */;
	reg				camhref_reg /* synthesis ALTERA_ATTRIBUTE = "FAST_INPUT_REGISTER=ON" */;
	reg				camvsync_reg /* synthesis ALTERA_ATTRIBUTE = "FAST_INPUT_REGISTER=ON" */;
	wire [DC_FIFO_WIDTHU_R-1:0] rdusedw_sig;
	wire [31:0]		dcfifo_q_sig;

	reg  [2:0]		fsync_in_reg;
	reg  [1:0]		exec_in_reg;
	wire			start_sig;

	wire			writedataready_sig;
	wire [31:0]		writedata_sig;
	wire			writedatardack_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	// AvalonMM-スレーブモジュール 

	peridot_cam_avs #(
		.AVS_CLOCKFREQ		(AVS_CLOCKFREQ),
		.USE_SCCBINTERFACE	(USE_SCCBINTERFACE),
		.USE_PERIDOT_I2C	(USE_PERIDOT_I2C),
		.SCCB_CLOCKFREQ		(SCCB_CLOCKFREQ)
	)
	u_csr (
		.csi_global_reset	(reset_sig),
		.avs_s1_clk			(clock_sig),
		.avs_s1_address		(avs_s1_address),
		.avs_s1_write		(avs_s1_write),
		.avs_s1_writedata	(avs_s1_writedata),
		.avs_s1_read		(avs_s1_read),
		.avs_s1_readdata	(avs_s1_readdata),
		.avs_s1_waitrequest	(avs_s1_waitrequest),
		.avs_s1_irq			(avs_s1_irq),

		.execution			(execution_sig),	// '1'でフレーム処理をリクエスト 
		.done				(done_sig),
		.framesync			(framesync_sig),	// フレーム開始信号 
		.infiforeset		(infiforeset_sig),	// 入力FIFO非同期リセット出力 
		.capaddress_top		(capaddress_sig),
		.capcycle_num		(capcyclenum_sig),

		.cam_reset_n		(cam_reset_n),
		.sccb_sck			(sccb_sck),
		.sccb_data			(sccb_data)
	);



	// DVP入力FIFO 

	always @(posedge camclk_sig) begin
		camdata_reg <= cam_data;
		camhref_reg <= cam_href;
		camvsync_reg <= cam_vsync;
	end

	dcfifo_mixed_widths #(
		.add_usedw_msb_bit	("ON"),
		.lpm_numwords		(DC_FIFO_NUMWORDS),
		.lpm_showahead		("ON"),
		.lpm_type			("dcfifo_mixed_widths"),
		.lpm_width			(8),
		.lpm_widthu			(DC_FIFO_WIDTHU),
		.lpm_width_r		(32),
		.lpm_widthu_r		(DC_FIFO_WIDTHU_R),
		.overflow_checking	("ON"),
		.rdsync_delaypipe	(4),
		.read_aclr_synch	("ON"),
		.underflow_checking	("ON"),
		.use_eab			("ON"),
		.write_aclr_synch	("ON"),
		.wrsync_delaypipe	(4)
	)
	u_fifo (
		.aclr		(infiforeset_sig),
		.wrclk		(camclk_sig),
		.wrreq		(camhref_reg),
		.data		(camdata_reg),

		.rdclk		(avmclk_sig),
		.rdreq		(writedatardack_sig),
		.q			(dcfifo_q_sig),
		.rdusedw	(rdusedw_sig)
	);

	assign writedataready_sig = (rdusedw_sig > 15)? 1'b1 : 1'b0;		// 16ワード以上FIFOに入っている 
	assign framesync_sig = camvsync_reg;

generate
	if (DVP_BYTESWAP == "ON") begin
		assign writedata_sig = {dcfifo_q_sig[23:16], dcfifo_q_sig[31:24], dcfifo_q_sig[7:0], dcfifo_q_sig[15:8]};
	end
	else begin
		assign writedata_sig = dcfifo_q_sig;
	end
endgenerate



	// AvalonMM-マスタモジュール 

	always @(posedge avmclk_sig or posedge reset_sig) begin
		if (reset_sig) begin
			fsync_in_reg <= 3'b000;
			exec_in_reg <= 2'b00;
		end
		else begin
			fsync_in_reg <= {fsync_in_reg[1:0], framesync_sig};
			exec_in_reg <= {exec_in_reg[0], execution_sig};
		end
	end

	assign start_sig = (!fsync_in_reg[2] && fsync_in_reg[1])? exec_in_reg[1] : 1'b0;


	peridot_cam_avm
	u_avm (
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
