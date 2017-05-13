// ===================================================================
// TITLE : PERIDOT-NGS / Configuration Layer
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2017/01/22 -> 2017/01/30
//   MODIFY : 2017/03/01
//          : 2017/05/11 EPCQ-UIDの読み出しに対応、EPCSデュアルブート対応 
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

module peridot_config #(
	parameter RECONFIG_FEATURE		= "ENABLE",
	parameter EPCSDUALBOOT_FEATURE	= "DISABLE",
	parameter CHIPUID_FEATURE		= "ENABLE",
	parameter EPCQUID_FEATURE		= "DISABLE",
	parameter INSTANCE_ALTDUALBOOT  = "ENABLE",
	parameter DEVICE_FAMILY			= "",
	parameter PERIDOT_GENCODE		= 8'h4e,		// generation code
	parameter RECONF_DELAY_CYCLE	= 20000000,		// 250ms delay (less than 80000000)
	parameter CONFIG_CYCLE			= 28,
	parameter RESET_TIMER_CYCLE		= 40
) (
	// module async reset
	input wire			reset,			// config layer async reset (external input)

	// Interface: clk
	input wire			clk,			// Host bridge and Avalon-MM master clock (up to 100MHz)
	output wire			reset_request,	// to Qsys system reset request

	// Interface: ST in (Up-stream side)
	output wire			rx_ready,		// from rxd or usbin
	input wire			rx_valid,
	input wire  [7:0]	rx_data,

	input wire			b2p_ready,		// to infifo or byte2packet
	output wire			b2p_valid,
	output wire [7:0]	b2p_data,

	// Interface: ST in (Down-stream side)
	output wire			p2b_ready,		// from packet2byte
	input wire			p2b_valid,
	input wire  [7:0]	p2b_data,

	input wire			tx_ready,		// to txd or usbout
	output wire			tx_valid,
	output wire [7:0]	tx_data,

	// Interface: Condit - async signal
	input wire			peri_clk,		// Peripheals clock (1-80MHz)
	input wire			boot_select,	// External bootsel signal
	output wire			ft_si,			// FTDI Send Immediate
	output wire			ru_bootsel,
	output wire			uid_enable,
	output wire [63:0]	uid,
	output wire			uid_valid,
	input wire  [63:0]	spiuid,
	input wire			spiuid_valid
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */



/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			reset_sig = reset;				// モジュール内部駆動非同期リセット 

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			clock_sig = clk;				// モジュール内部駆動クロック 
	wire			periclock_sig = peri_clk;

	reg  [1:0]		streset_reg;
	wire			streset_sig;
	reg  [1:0]		perireset_reg;
	wire			perireset_sig;

	wire			i2c_scl_sig, i2c_sda_sig;
	wire			conf_scl_o_sig, conf_sda_o_sig;
	wire			rom_scl_o_sig, rom_sda_o_sig;
	wire			ru_bootsel_sig;
	wire			ru_nconfig_sig;
	wire			ru_nstatus_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	///// リセット信号の同期化 /////

	always @(posedge clock_sig) begin
		streset_reg <= {streset_reg[0], reset_sig};
	end

	assign streset_sig = streset_reg[1];

	always @(posedge periclock_sig) begin
		perireset_reg <= {perireset_reg[0], reset_sig};
	end

	assign perireset_sig = perireset_reg[1];



	///// コンフィグレーションレイヤ・プロトコル処理部 /////

	peridot_config_proc
	u0 (
		.clk			(clock_sig),
		.reset			(streset_sig),

		.in_ready		(rx_ready),
		.in_valid		(rx_valid),
		.in_data		(rx_data),
		.out_ready		(b2p_ready),
		.out_valid		(b2p_valid),
		.out_data		(b2p_data),

		.pk_ready		(p2b_ready),
		.pk_valid		(p2b_valid),
		.pk_data		(p2b_data),
		.resp_ready		(tx_ready),
		.resp_valid		(tx_valid),
		.resp_data		(tx_data),

		.reset_request	(reset_request),
		.ft_si			(ft_si),
		.i2c_scl_o		(conf_scl_o_sig),
		.i2c_scl_i		(i2c_scl_sig),
		.i2c_sda_o		(conf_sda_o_sig),
		.i2c_sda_i		(i2c_sda_sig),
		.ru_bootsel		(ru_bootsel_sig),
		.ru_nconfig		(ru_nconfig_sig),
		.ru_nstatus		(ru_nstatus_sig)
	);

	assign ru_bootsel = ru_bootsel_sig;

	assign i2c_scl_sig = (!conf_scl_o_sig || !rom_scl_o_sig)? 1'b0 : 1'b1;
	assign i2c_sda_sig = (!conf_sda_o_sig || !rom_sda_o_sig)? 1'b0 : 1'b1;



	///// ボードシリアルEEPROM /////

	peridot_board_eeprom #(
		.CHIPUID_FEATURE	(CHIPUID_FEATURE),
		.EPCQUID_FEATURE	(EPCQUID_FEATURE),
		.I2C_DEV_ADDRESS	(7'b1010000),
		.DEVICE_FAMILY		(DEVICE_FAMILY),
		.PERIDOT_GENCODE	(PERIDOT_GENCODE),
		.UID_VALUE			(64'hffffffffffffffff)
	)
	u1 (
		.clk			(periclock_sig),
		.reset			(perireset_sig),

		.i2c_scl_i		(i2c_scl_sig),
		.i2c_scl_o		(rom_scl_o_sig),
		.i2c_sda_i		(i2c_sda_sig),
		.i2c_sda_o		(rom_sda_o_sig),

		.uid_enable		(uid_enable),
		.uid			(uid),
		.uid_valid		(uid_valid),
		.spiuid			(spiuid),
		.spiuid_valid	(spiuid_valid)
	);



	///// リコンフィグレーションユニット /////

generate
	if (DEVICE_FAMILY == "MAX 10") begin

		// MAX10 : リコンフィグ機能を使う 
		if (RECONFIG_FEATURE == "ENABLE") begin
			peridot_config_ru #(
				.DEVICE_FAMILY			("MAX 10"),
				.RECONF_DELAY_CYCLE		(RECONF_DELAY_CYCLE),
				.CONFIG_CYCLE			(CONFIG_CYCLE),
				.RESET_TIMER_CYCLE		(RESET_TIMER_CYCLE)
			)
			u2_max10_ru (
				.clk			(periclock_sig),
				.reset			(perireset_sig),
				.ru_ready		(),
				.ru_bootsel		(ru_bootsel_sig),
				.ru_nconfig		(ru_nconfig_sig),
				.ru_nstatus		(ru_nstatus_sig)
			);
		end

		// MAX10 : リコンフィグ機能は使わないが、alt_dual_bootコアはインスタンスする 
		else if (INSTANCE_ALTDUALBOOT == "ENABLE") begin
			alt_dual_boot_avmm #(
				.LPM_TYPE				("ALTERA_DUAL_BOOT"),
				.INTENDED_DEVICE_FAMILY	("MAX 10"),
				.A_WIDTH				(3),
				.MAX_DATA_WIDTH			(32),
				.WD_WIDTH				(4),
				.RD_WIDTH				(17),
				.CONFIG_CYCLE			(28),
				.RESET_TIMER_CYCLE		(40)
			)
			u2_max10_dualboot (
				.clk				(periclock_sig),
				.nreset				(1'b0),
				.avmm_rcv_address	(3'h0),
				.avmm_rcv_writedata	(32'h0),
				.avmm_rcv_write		(1'b0),
				.avmm_rcv_read		(1'b0),
				.avmm_rcv_readdata	()
			);

			assign ru_bootsel_sig = 1'b1;
			assign ru_nstatus_sig = 1'b1;
		end

		// MAX10 : リコンフィグ機能は使わない 
		else begin
			assign ru_bootsel_sig = 1'b1;
			assign ru_nstatus_sig = 1'b1;
		end
	end

	// それ以外のデバイスではリコンフィグ機能は無効 
	else begin
		if (EPCSDUALBOOT_FEATURE == "ENABLE") begin
			assign ru_bootsel_sig = boot_select;
		end
		else begin
			assign ru_bootsel_sig = 1'b1;
		end

		assign ru_nstatus_sig = 1'b1;
	end
endgenerate




endmodule
