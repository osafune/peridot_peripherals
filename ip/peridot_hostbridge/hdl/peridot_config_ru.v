// ===================================================================
// TITLE : PERIDOT-NGS / Remote Update
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2017/01/21 -> 2017/01/30
//   UPDATE : 2017/03/01
//
// ===================================================================
// *******************************************************************
//    (C)2016-2017, J-7SYSTEM WORKS LIMITED.  All rights Reserved.
//
// * This module is a free sourcecode and there is NO WARRANTY.
// * No restriction on use. You can use, modify and redistribute it
//   for personal, non-profit or commercial products UNDER YOUR
//   RESPONSIBILITY.
// * Redistributions of source code must retain the above copyright
//   notice.
// *******************************************************************

module peridot_config_ru #(
	parameter DEVICE_FAMILY			= "",
	parameter RECONF_DELAY_CYCLE	= 10,		// less than 80000000 
	parameter CONFIG_CYCLE			= 28,
	parameter RESET_TIMER_CYCLE		= 40
) (
	// Interface: clk
	input wire			clk,			// up to 80MHz
	input wire			reset,

	// Interface: config - async signal
	output wire			ru_ready,
	output wire			ru_bootsel,
	input wire			ru_nconfig,
	output wire			ru_nstatus
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam	STATE_INIT			= 5'd0,
				STATE_GET_BOOTSEL	= 5'd1,
				STATE_IO_WRITE_2	= 5'd2,
				STATE_IO_READ_3		= 5'd3,
				STATE_IO_READDATA_3	= 5'd4,
				STATE_IO_READ_4		= 5'd5,
				STATE_IO_READDATA_4	= 5'd6,
				STATE_IDLE			= 5'd7,
				STATE_DO_RECONFIG	= 5'd8,
				STATE_IO_WRITE_0	= 5'd9,
				STATE_HALT			= 5'd10;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = reset;				// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;				// モジュール内部駆動クロック 

	reg  [2:0]		nconfig_in_reg;
	wire			nconfig_rise_sig;

	reg  [4:0]		state_reg;
	reg  [4:0]		inittimer_reg;
	reg				ready_reg;
	reg				bootsel_reg;
	reg  [26:0]		reconftimer_reg;

	wire			dc_nreset_sig;
	wire [2:0]		dc_address_sig;
	wire			dc_write_sig;
	wire [31:0]		dc_writedata_sig;
	wire			dc_read_sig;
	wire [31:0]		dc_readdata_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	///// 非同期信号の同期化 /////
	// ru_nconfigの立ち上がりエッジで再コンフィグを発行 

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			nconfig_in_reg <= 3'b111;
		end
		else begin
			nconfig_in_reg <= {nconfig_in_reg[1:0], ru_nconfig};
		end
	end

	assign nconfig_rise_sig = (!nconfig_in_reg[2] && nconfig_in_reg[1]);



	///// リモートアップデートシーケンサ /////

	always @(posedge clock_sig or posedge reset_sig) begin
		if (reset_sig) begin
			state_reg <= STATE_INIT;
			inittimer_reg <= 1'd0;
			ready_reg <= 1'b0;
			bootsel_reg <= 1'b0;
		end
		else begin
			case (state_reg)

			STATE_INIT : begin
				if (inittimer_reg[4]) begin
					state_reg <= STATE_GET_BOOTSEL;
				end
				else begin
					inittimer_reg <= inittimer_reg + 1'd1;
				end
			end

			STATE_GET_BOOTSEL : begin
				state_reg <= STATE_IO_WRITE_2;
			end
			STATE_IO_WRITE_2 : begin
				state_reg <= STATE_IO_READ_3;
			end
			STATE_IO_READ_3 : begin
				state_reg <= STATE_IO_READDATA_3;
			end
			STATE_IO_READDATA_3 : begin
				if (dc_readdata_sig[0] == 1'b1) begin
					state_reg <= STATE_IO_READ_3;
				end
				else begin
					state_reg <= STATE_IO_READ_4;
				end
			end
			STATE_IO_READ_4 : begin
				state_reg <= STATE_IO_READDATA_4;
			end
			STATE_IO_READDATA_4 : begin
				state_reg <= STATE_IDLE;
				ready_reg <= 1'b1;

				if (dc_readdata_sig[15] != dc_readdata_sig[13]) begin	// mem_cs = 0100,0011 : image1
					bootsel_reg <= 1'b1;
				end
				else begin												// mem_cs = 0010,0101 : image0
					bootsel_reg <= 1'b0;
				end
			end


			STATE_IDLE : begin
				if (nconfig_rise_sig) begin
					state_reg <= STATE_DO_RECONFIG;
					ready_reg <= 1'b0;
					reconftimer_reg <= RECONF_DELAY_CYCLE[26:0];
				end
			end
			STATE_DO_RECONFIG : begin
				if (reconftimer_reg == 1'd0) begin
					state_reg <= STATE_IO_WRITE_0;
				end
				else begin
					reconftimer_reg <= reconftimer_reg - 1'd1;
				end
			end
			STATE_IO_WRITE_0 : begin
				state_reg <= STATE_HALT;
			end
			STATE_HALT : begin
			end

			endcase

		end
	end

	assign ru_ready = ready_reg;
	assign ru_bootsel = bootsel_reg;
	assign ru_nstatus = (ready_reg)? nconfig_in_reg[2] : 1'b0;

	assign dc_nreset_sig = inittimer_reg[4];

	assign dc_address_sig =
						(state_reg == STATE_IO_WRITE_2)? 3'h2 :
						(state_reg == STATE_IO_READ_3 || state_reg == STATE_IO_READDATA_3)? 3'h3 :
						(state_reg == STATE_IO_READ_4 || state_reg == STATE_IO_READDATA_4)? 3'h4 :
						(state_reg == STATE_IO_WRITE_0)? 3'h0 :
						{3{1'bx}};

	assign dc_write_sig = (state_reg == STATE_IO_WRITE_0 || state_reg == STATE_IO_WRITE_2)? 1'b1 : 1'b0;

	assign dc_writedata_sig =
						(state_reg == STATE_IO_WRITE_2)? 32'h00000001 :		// request read msm_cs & wdt
						(state_reg == STATE_IO_WRITE_0)? 32'h00000001 :		// reconfig trig
						{32{1'bx}};

	assign dc_read_sig = (state_reg == STATE_IO_READ_3 || state_reg == STATE_IO_READDATA_3 ||
							state_reg == STATE_IO_READ_4 || state_reg == STATE_IO_READDATA_4)? 1'b1 : 1'b0;



	///// コンフィグレーションモジュールインスタンス /////

generate
	if (DEVICE_FAMILY == "MAX 10") begin
		alt_dual_boot_avmm #(
			.LPM_TYPE				("ALTERA_DUAL_BOOT"),
			.INTENDED_DEVICE_FAMILY	("MAX 10"),
			.A_WIDTH				(3),
			.MAX_DATA_WIDTH			(32),
			.WD_WIDTH				(4),
			.RD_WIDTH				(17),
			.CONFIG_CYCLE			(CONFIG_CYCLE),
			.RESET_TIMER_CYCLE		(RESET_TIMER_CYCLE)
		)
		u0 (
			.clk				(clock_sig),
			.nreset				(dc_nreset_sig),
			.avmm_rcv_address	(dc_address_sig),
			.avmm_rcv_writedata	(dc_writedata_sig),
			.avmm_rcv_write		(dc_write_sig),
			.avmm_rcv_read		(dc_read_sig),
			.avmm_rcv_readdata	(dc_readdata_sig)
		);
	end
	else begin
		assign dc_readdata_sig = 32'h00000000;
	end
endgenerate



endmodule
