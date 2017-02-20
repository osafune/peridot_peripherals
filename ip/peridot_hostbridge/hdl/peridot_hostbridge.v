// ===================================================================
// TITLE : PERIDOT-NG / Host bridge (SWI including)
//
//   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
//   DATE   : 2017/01/23 -> 2017/02/15
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

`timescale 1ns / 100ps

module peridot_hostbridge #(
	parameter DEVICE_FAMILY			= "MAX 10",
	parameter AVM_CLOCKFREQ			= 100000000,		// master drive clock freq(Hz)
	parameter AVS_CLOCKFREQ			= 25000000,			// peripheral drive clock freq(Hz)
	parameter RECONFIG_FEATURE		= "ENABLE",			// config:device remote update enable
	parameter INSTANCE_ALTDUALBOOT  = "DISABLE",		// config:instanse dummy alt_dual_boot(RECONFIG_FEATURE = "DISABLE")
	parameter CHIPUID_FEATURE		= "ENABLE",			// config:device chip UID readout enable
	parameter HOSTINTERFACE_TYPE	= "UART",			// "UART" or "FT245"
	parameter HOSTUART_BAUDRATE		= 115200,			// Host Interface baudrate (HOSTINTERFACE_TYPE = "UART")
	parameter HOSTUART_INFIFODEPTH	= 6,				// bit width of infifo word depth (HOSTINTERFACE_TYPE = "UART")
	parameter PERIDOT_GENCODE		= 8'h4e,			// generation code
	parameter RECONF_DELAY_CYCLE	= 20000000,			// 200ms delay (avsclock cycle)
	parameter CONFIG_CYCLE			= 28,				// > 350ns (avsclock cycle)
	parameter RESET_TIMER_CYCLE		= 40,				// > 500ns (avsclock cycle)
	parameter SWI_EPCSBOOT_FEATURE	= "ENABLE",			// swi:EPCS access register enable
	parameter SWI_UIDREAD_FEATURE	= "ENABLE",			// swi:chip uid readout register enable
	parameter SWI_MESSAGE_FEATURE	= "ENABLE",			// swi:message and swi register enable
	parameter SWI_CLASSID			= 32'h72A00000,		// swi:PERIDOT Class ID
	parameter SWI_TIMECODE			= 32'd1234567890,	// swi:Generation Time stamp
	parameter SWI_CPURESET_KEY		= 16'hdead,			// swi:cpureset register assert key
	parameter SWI_CPURESET_INIT		= 0					// swi:Initialize coe_cpureset condition
) (
	// Interface: Avalon-MM Master
	input			csi_avmclock_clk,
	input			csi_avmclock_reset,

	output [31:0]	avm_m1_address,
	input  [31:0]	avm_m1_readdata,
	output			avm_m1_read,
	output			avm_m1_write,
	output [3:0]	avm_m1_byteenable,
	output [31:0]	avm_m1_writedata,
	input			avm_m1_waitrequest,
	input			avm_m1_readdatavalid,

	// Interface: Avalon-MM reset source
	output			rso_busreset_reset,

	// Interface: Avalon-MM Slave
	input			csi_avsclock_clk,
	input			csi_avsclock_reset,

	input  [2:0]	avs_s1_address,
	input			avs_s1_read,
	output [31:0]	avs_s1_readdata,
	input			avs_s1_write,
	input  [31:0]	avs_s1_writedata,

	// Interface: Avalon-MM Interrupt sender
	output			ins_avsirq_irq,

	// Interface: Condit
	input			coe_mreset_n,
	input			coe_rxd,
	output			coe_txd,
	inout  [7:0]	coe_ft_d,
	output			coe_ft_rd_n,
	output			coe_ft_wr,
	input			coe_ft_rxf_n,
	input			coe_ft_txe_n,
	output			coe_ft_siwu_n,

	output [3:0]	coe_led,
	output			coe_cpureset,
	output			coe_cso_n,
	output			coe_dclk,
	output			coe_asdo,
	input			coe_data0
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam UARTINFIFO_NUMWORDS	= 2**HOSTUART_INFIFODEPTH;


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* 内部は全て正論理リセットとする。ここで定義していないノードの使用は禁止 */
	wire			avmreset_sig = csi_avmclock_reset;		// モジュール内部駆動非同期リセット 
	wire			avsreset_sig = csi_avsclock_reset;
	wire			masterreset_sig = ~coe_mreset_n;

				/* 内部は全て正エッジ駆動とする。ここで定義していないクロックノードの使用は禁止 */
	wire			avmclock_sig = csi_avmclock_clk;		// モジュール内部駆動クロック 
	wire			avsclock_sig = csi_avsclock_clk;

	wire			phy_up_ready_sig;
	wire			phy_up_valid_sig;
	wire [7:0]		phy_up_data_sig;
	wire			phy_down_ready_sig;
	wire			phy_down_valid_sig;
	wire [7:0]		phy_down_data_sig;

	wire			infifo_rdack_sig;
	wire			infifo_empty_sig;
	wire [7:0]		infifo_q_sig;
	wire			b2p_ready_sig;
	wire			b2p_valid_sig;
	wire [7:0]		b2p_data_sig;

	wire			rx_ready_sig;
	wire			rx_valid_sig;
	wire [7:0]		rx_data_sig;
	wire			tx_ready_sig;
	wire			tx_valid_sig;
	wire [7:0]		tx_data_sig;

	wire			ft_si_sig;
	wire			ru_bootsel_sig;
	wire			uid_enable_sig;
	wire [63:0]		uid_sig;
	wire			uid_valid_sig;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */



/* ===== モジュール構造記述 ============== */

	///// Avalon-MMブリッジモジュール /////

	peridot_mm_master
	inst_mm_master (
		.clk				(avmclock_sig),
		.reset				(avmreset_sig),

		.in_ready			(phy_up_ready_sig),
		.in_valid			(phy_up_valid_sig),
		.in_data			(phy_up_data_sig),
		.out_ready			(phy_down_ready_sig),
		.out_valid			(phy_down_valid_sig),
		.out_data			(phy_down_data_sig),

		.avm_address		(avm_m1_address),
		.avm_readdata		(avm_m1_readdata),
		.avm_read			(avm_m1_read),
		.avm_write			(avm_m1_write),
		.avm_byteenable		(avm_m1_byteenable),
		.avm_writedata		(avm_m1_writedata),
		.avm_waitrequest	(avm_m1_waitrequest),
		.avm_readdatavalid	(avm_m1_readdatavalid)
	);



	///// PERIDOTコンフィグレーションレイヤ /////

generate
	if (HOSTINTERFACE_TYPE == "UART") begin
		scfifo #(
			.lpm_type				("scfifo"),
			.lpm_numwords			(UARTINFIFO_NUMWORDS),
			.lpm_width				(8),
			.lpm_widthu				(HOSTUART_INFIFODEPTH),
			.lpm_showahead			("ON"),
			.add_ram_output_register("OFF"),
			.overflow_checking		("ON"),
			.underflow_checking		("ON"),
			.use_eab				("ON")
		)
		inst_infifo (
			.aclr			(avmreset_sig),
			.clock			(avmclock_sig),
			.wrreq			(b2p_valid_sig),
			.data			(b2p_data_sig),
			.usedw			(),
			.rdreq			(infifo_rdack_sig),
			.q				(infifo_q_sig),
			.empty			(infifo_empty_sig)
		);

		assign infifo_rdack_sig = (!infifo_empty_sig && phy_up_ready_sig)? 1'b1 : 1'b0;
		assign phy_up_valid_sig = ~infifo_empty_sig;
		assign phy_up_data_sig = infifo_q_sig;

		assign b2p_ready_sig = 1'b1;
	end
	else begin
		assign phy_up_valid_sig = b2p_valid_sig;
		assign phy_up_data_sig = b2p_data_sig;

		assign b2p_ready_sig = phy_up_ready_sig;
	end
endgenerate


	peridot_config #(
		.RECONFIG_FEATURE		(RECONFIG_FEATURE),
		.CHIPUID_FEATURE		(CHIPUID_FEATURE),
		.INSTANCE_ALTDUALBOOT	(INSTANCE_ALTDUALBOOT),
		.DEVICE_FAMILY			(DEVICE_FAMILY),
		.PERIDOT_GENCODE		(PERIDOT_GENCODE),
		.RECONF_DELAY_CYCLE		(RECONF_DELAY_CYCLE),
		.CONFIG_CYCLE			(CONFIG_CYCLE),
		.RESET_TIMER_CYCLE		(RESET_TIMER_CYCLE)
	)
	inst_config (
		.reset				(masterreset_sig),
		.clk				(avmclock_sig),
		.reset_request		(rso_busreset_reset),

		.rx_ready			(rx_ready_sig),			// from rxd or usbin
		.rx_valid			(rx_valid_sig),
		.rx_data			(rx_data_sig),
		.b2p_ready			(b2p_ready_sig),		// to infifo or byte2packet
		.b2p_valid			(b2p_valid_sig),
		.b2p_data			(b2p_data_sig),

		.p2b_ready			(phy_down_ready_sig),	// from packet2byte
		.p2b_valid			(phy_down_valid_sig),
		.p2b_data			(phy_down_data_sig),
		.tx_ready			(tx_ready_sig),			// to txd or usbout
		.tx_valid			(tx_valid_sig),
		.tx_data			(tx_data_sig),

		.peri_clk			(avsclock_sig),
		.ft_si				(ft_si_sig),
		.ru_bootsel			(ru_bootsel_sig),
		.uid_enable			(uid_enable_sig),
		.uid				(uid_sig),
		.uid_valid			(uid_valid_sig)
	);



	///// ホスト通信物理層 /////

generate
	// Generic UART (FT230X or others)
	if (HOSTINTERFACE_TYPE == "UART") begin
		peridot_phy_rxd #(
			.CLOCK_FREQUENCY	(AVM_CLOCKFREQ),
			.UART_BAUDRATE		(HOSTUART_BAUDRATE)
		)
		inst_rxd (
			.clk			(avmclock_sig),
			.reset			(masterreset_sig),
			.out_valid		(rx_valid_sig),
			.out_data		(rx_data_sig),
			.rxd			(coe_rxd)
		);

		peridot_phy_txd #(
			.CLOCK_FREQUENCY	(AVM_CLOCKFREQ),
			.UART_BAUDRATE		(HOSTUART_BAUDRATE)
		)
		inst_txd (
			.clk			(avmclock_sig),
			.reset			(masterreset_sig),
			.in_ready		(tx_ready_sig),
			.in_valid		(tx_valid_sig),
			.in_data		(tx_data_sig),
			.txd			(coe_txd)
		);

		assign coe_ft_d = {8{1'bz}};
		assign coe_ft_rd_n = 1'b1;
		assign coe_ft_wr = 1'b0;
		assign coe_ft_siwu_n = 1'b1;
	end

	// FT245 Async FIFO (FT245R,FT240X,FT232H)
	else if (HOSTINTERFACE_TYPE == "FT245") begin
		peridot_phy_ft245 #(
			.CLOCK_FREQUENCY		(AVM_CLOCKFREQ),
			.RD_ACTIVE_PULSE_WIDTH	(60),
			.RD_PRECHARGE_TIME		(50),
			.WR_ACTIVE_PULSE_WIDTH	(60),
			.WR_PRECHARGE_TIME		(50)
		)
		inst_ft245 (
			.clk			(avmclock_sig),
			.reset			(masterreset_sig),
			.out_ready		(rx_ready_sig),
			.out_valid		(rx_valid_sig),
			.out_data		(rx_data_sig),
			.in_ready		(tx_ready_sig),
			.in_valid		(tx_valid_sig),
			.in_data		(tx_data_sig),

			.ft_d			(coe_ft_d),
			.ft_rd_n		(coe_ft_rd_n),
			.ft_wr			(coe_ft_wr),
			.ft_rxf_n		(coe_ft_rxf_n),
			.ft_txe_n		(coe_ft_txe_n)
		);

		assign coe_ft_siwu_n = (ft_si_sig)? 1'b0 : 1'b1;
		assign coe_txd = 1'b1;
	end

	// Multi Sync FIFO (FT600)
	else if (HOSTINTERFACE_TYPE == "FT600") begin

		/* まだ */

		assign coe_ft_siwu_n = 1'b1;
		assign coe_txd = 1'b1;
	end

endgenerate



	///// SWIペリフェラル /////

	peridot_csr_swi #(
		.EPCSBOOT_FEATURE		(SWI_EPCSBOOT_FEATURE),
		.UIDREAD_FEATURE		(SWI_UIDREAD_FEATURE),
		.MESSAGE_FEATURE		(SWI_MESSAGE_FEATURE),
		.CLOCKFREQ				(AVS_CLOCKFREQ),
		.CLASSID				(SWI_CLASSID),
		.TIMECODE				(SWI_TIMECODE),
		.CPURESET_KEY			(SWI_CPURESET_KEY),
		.CPURESET_INIT			(SWI_CPURESET_INIT)
	)
	inst_swi (
		.csi_clk			(avsclock_sig),
		.rsi_reset			(avsreset_sig),

		.avs_address		(avs_s1_address),
		.avs_read			(avs_s1_read),
		.avs_readdata		(avs_s1_readdata),
		.avs_write			(avs_s1_write),
		.avs_writedata		(avs_s1_writedata),
		.ins_irq			(ins_avsirq_irq),

		.coe_cpureset		(coe_cpureset),
		.coe_led			(coe_led),
		.coe_cso_n			(coe_cso_n),
		.coe_dclk			(coe_dclk),
		.coe_asdo			(coe_asdo),
		.coe_data0			(coe_data0),

		.ru_bootsel			(ru_bootsel_sig),
		.uid_enable			(uid_enable_sig),
		.uid				(uid_sig),
		.uid_valid			(uid_valid_sig)
	);



endmodule
