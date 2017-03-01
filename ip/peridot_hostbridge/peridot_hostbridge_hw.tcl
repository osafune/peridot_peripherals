# ===================================================================
# TITLE : PERIDOT-NGS / "PERIDOT Host Bridge"
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2017/01/24 -> 2017/03/01
#
# ===================================================================
# *******************************************************************
#    (C)2016-2017, J-7SYSTEM WORKS LIMITED.  All rights Reserved.
#
# * This module is a free sourcecode and there is NO WARRANTY.
# * No restriction on use. You can use, modify and redistribute it
#   for personal, non-profit or commercial products UNDER YOUR
#   RESPONSIBILITY.
# * Redistributions of source code must retain the above copyright
#   notice.
# *******************************************************************

# 
# request TCL package from ACDS 16.1
# 
package require -exact qsys 16.1


# 
# module peridot_hostbridge
# 
set_module_property NAME peridot_hostbridge
set_module_property DISPLAY_NAME "PERIDOT Host Bridge (beta test version)"
set_module_property DESCRIPTION "PERIDOT Host to Avalon-MM bridge"
set_module_property AUTHOR "J-7SYSTEM WORKS LIMITED"
set_module_property VERSION 16.1
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property HIDE_FROM_SOPC true
set_module_property HIDE_FROM_QUARTUS true
set_module_property EDITABLE false
set_module_property ELABORATION_CALLBACK elaboration_callback


# 
# file sets
# 
add_fileset quartus_synth QUARTUS_SYNTH generate_synth
set_fileset_property quartus_synth TOP_LEVEL peridot_hostbridge


# 
# parameters
# 
set debugview false

add_parameter DEVICE_FAMILY string
set_parameter_property DEVICE_FAMILY SYSTEM_INFO {DEVICE_FAMILY}
set_parameter_property DEVICE_FAMILY HDL_PARAMETER true
set_parameter_property DEVICE_FAMILY ENABLED false
set_parameter_property DEVICE_FAMILY VISIBLE $debugview
add_parameter PART_NAME string
set_parameter_property PART_NAME SYSTEM_INFO {DEVICE}
set_parameter_property PART_NAME ENABLED false
set_parameter_property PART_NAME VISIBLE $debugview

add_parameter AVM_CLOCKFREQ integer
set_parameter_property AVM_CLOCKFREQ UNITS hertz
set_parameter_property AVM_CLOCKFREQ SYSTEM_INFO {CLOCK_RATE avmclock}
set_parameter_property AVM_CLOCKFREQ HDL_PARAMETER true
set_parameter_property AVM_CLOCKFREQ ENABLED false
set_parameter_property AVM_CLOCKFREQ VISIBLE $debugview

add_parameter AVS_CLOCKFREQ integer
set_parameter_property AVS_CLOCKFREQ UNITS hertz
set_parameter_property AVS_CLOCKFREQ SYSTEM_INFO {CLOCK_RATE avsclock}
set_parameter_property AVS_CLOCKFREQ HDL_PARAMETER true
set_parameter_property AVS_CLOCKFREQ ENABLED false
set_parameter_property AVS_CLOCKFREQ VISIBLE $debugview

add_parameter RECONFIG_FEATURE string
set_parameter_property RECONFIG_FEATURE HDL_PARAMETER true
set_parameter_property RECONFIG_FEATURE ENABLED false
set_parameter_property RECONFIG_FEATURE DERIVED true
set_parameter_property RECONFIG_FEATURE VISIBLE $debugview
add_parameter USE_RECONFIG boolean true
set_parameter_property USE_RECONFIG DISPLAY_NAME "Use reconfiguration function"
set_parameter_property USE_RECONFIG DISPLAY_HINT boolean

add_parameter INSTANCE_ALTDUALBOOT string
set_parameter_property INSTANCE_ALTDUALBOOT HDL_PARAMETER true
set_parameter_property INSTANCE_ALTDUALBOOT ENABLED false
set_parameter_property INSTANCE_ALTDUALBOOT DERIVED true
set_parameter_property INSTANCE_ALTDUALBOOT VISIBLE $debugview
add_parameter USE_ALTDUALBOOT boolean true
set_parameter_property USE_ALTDUALBOOT DISPLAY_NAME "Instance alt_dual_boot cores"
set_parameter_property USE_ALTDUALBOOT DESCRIPTION "When not using a reconfiguration function by a dual configuration scheme, is turned on."
set_parameter_property USE_ALTDUALBOOT DISPLAY_HINT boolean

add_parameter CHIPUID_FEATURE string
set_parameter_property CHIPUID_FEATURE HDL_PARAMETER true
set_parameter_property CHIPUID_FEATURE ENABLED false
set_parameter_property CHIPUID_FEATURE DERIVED true
set_parameter_property CHIPUID_FEATURE VISIBLE $debugview
add_parameter USE_CHIPUID boolean true
set_parameter_property USE_CHIPUID DISPLAY_NAME "Use chip-UID for a board serial number"
set_parameter_property USE_CHIPUID DISPLAY_HINT boolean

add_parameter HOSTINTERFACE_TYPE string "UART"
set_parameter_property HOSTINTERFACE_TYPE DISPLAY_NAME "Host interface type"
#set_parameter_property HOSTINTERFACE_TYPE ALLOWED_RANGES {"UART:Generic UART" "FT245:FT245 Async FIFO" "FT600:Multi Sync FIFO"}
set_parameter_property HOSTINTERFACE_TYPE ALLOWED_RANGES {"UART:Generic UART" "FT245:FT245 Async FIFO"}
set_parameter_property HOSTINTERFACE_TYPE HDL_PARAMETER true

add_parameter HOSTUART_BAUDRATE integer 115200
set_parameter_property HOSTUART_BAUDRATE DISPLAY_NAME "UART baudrate"
set_parameter_property HOSTUART_BAUDRATE UNITS bitspersecond
set_parameter_property HOSTUART_BAUDRATE ALLOWED_RANGES {38400 57600 115200 230400 460800 921600}
set_parameter_property HOSTUART_BAUDRATE HDL_PARAMETER true

add_parameter HOSTUART_INFIFODEPTH integer 6
set_parameter_property HOSTUART_INFIFODEPTH DISPLAY_NAME "UART infifo depth"
set_parameter_property HOSTUART_INFIFODEPTH ALLOWED_RANGES {"2:4 words" "4:16 words" "6:64 words" "8:256 words" "10:1024 words"}
set_parameter_property HOSTUART_INFIFODEPTH HDL_PARAMETER true

add_parameter PERIDOT_GENCODE integer 78
set_parameter_property PERIDOT_GENCODE DISPLAY_NAME "PERIDOT identifier"
set_parameter_property PERIDOT_GENCODE ALLOWED_RANGES {"65:Standard" "66:Virtual" "78:NewGenerations" "88:Generic"}
set_parameter_property PERIDOT_GENCODE HDL_PARAMETER true

add_parameter RECONF_DELAY_CYCLE integer
set_parameter_property RECONF_DELAY_CYCLE HDL_PARAMETER true
set_parameter_property RECONF_DELAY_CYCLE ENABLED false
set_parameter_property RECONF_DELAY_CYCLE DERIVED true
set_parameter_property RECONF_DELAY_CYCLE VISIBLE $debugview
add_parameter RECONF_DELAY_TIME integer 200
set_parameter_property RECONF_DELAY_TIME UNITS milliseconds
set_parameter_property RECONF_DELAY_TIME DISPLAY_NAME "Reconfiguration delay time"
set_parameter_property RECONF_DELAY_TIME ALLOWED_RANGES 1:1000

add_parameter CONFIG_CYCLE integer
set_parameter_property CONFIG_CYCLE HDL_PARAMETER true
set_parameter_property CONFIG_CYCLE ENABLED false
set_parameter_property CONFIG_CYCLE DERIVED true
set_parameter_property CONFIG_CYCLE VISIBLE $debugview

add_parameter RESET_TIMER_CYCLE integer
set_parameter_property RESET_TIMER_CYCLE HDL_PARAMETER true
set_parameter_property RESET_TIMER_CYCLE ENABLED false
set_parameter_property RESET_TIMER_CYCLE DERIVED true
set_parameter_property RESET_TIMER_CYCLE VISIBLE $debugview

add_parameter SWI_EPCSBOOT_FEATURE string
set_parameter_property SWI_EPCSBOOT_FEATURE HDL_PARAMETER true
set_parameter_property SWI_EPCSBOOT_FEATURE ENABLED false
set_parameter_property SWI_EPCSBOOT_FEATURE DERIVED true
set_parameter_property SWI_EPCSBOOT_FEATURE VISIBLE $debugview
add_parameter SWI_USE_EPCSBOOT boolean true
set_parameter_property SWI_USE_EPCSBOOT DISPLAY_NAME "Use EPCS/EPCQ access registers"
set_parameter_property SWI_USE_EPCSBOOT DISPLAY_HINT boolean

add_parameter SWI_UIDREAD_FEATURE string
set_parameter_property SWI_UIDREAD_FEATURE HDL_PARAMETER true
set_parameter_property SWI_UIDREAD_FEATURE ENABLED false
set_parameter_property SWI_UIDREAD_FEATURE DERIVED true
set_parameter_property SWI_UIDREAD_FEATURE VISIBLE $debugview
add_parameter SWI_USE_UIDREAD boolean true
set_parameter_property SWI_USE_UIDREAD DISPLAY_NAME "Use chip-UID readout registers"
set_parameter_property SWI_USE_UIDREAD DISPLAY_HINT boolean

add_parameter SWI_MESSAGE_FEATURE string
set_parameter_property SWI_MESSAGE_FEATURE HDL_PARAMETER true
set_parameter_property SWI_MESSAGE_FEATURE ENABLED false
set_parameter_property SWI_MESSAGE_FEATURE DERIVED true
set_parameter_property SWI_MESSAGE_FEATURE VISIBLE $debugview
add_parameter SWI_USE_MESSAGE boolean true
set_parameter_property SWI_USE_MESSAGE DISPLAY_NAME "Use message and software interrput registers"
set_parameter_property SWI_USE_MESSAGE DISPLAY_HINT boolean

add_parameter SWI_CLASSID std_logic_vector 0x72a00000
set_parameter_property SWI_CLASSID WIDTH 32
set_parameter_property SWI_CLASSID DISPLAY_NAME "32 bit Class ID"
set_parameter_property SWI_CLASSID HDL_PARAMETER true

add_parameter SWI_TIMECODE integer 0
set_parameter_property SWI_TIMECODE SYSTEM_INFO {GENERATION_ID}
set_parameter_property SWI_TIMECODE HDL_PARAMETER true
set_parameter_property SWI_TIMECODE ENABLED false
set_parameter_property SWI_TIMECODE VISIBLE $debugview

add_parameter SWI_CPURESET_KEY std_logic_vector 0xdead
set_parameter_property SWI_CPURESET_KEY WIDTH 16
set_parameter_property SWI_CPURESET_KEY DISPLAY_NAME "cpureset key value"
set_parameter_property SWI_CPURESET_KEY ALLOWED_RANGES 0:65535
set_parameter_property SWI_CPURESET_KEY HDL_PARAMETER true

add_parameter SWI_CPURESET_INIT integer 0
set_parameter_property SWI_CPURESET_INIT DISPLAY_NAME "cpureset initial value"
set_parameter_property SWI_CPURESET_INIT ALLOWED_RANGES {"0:Negate" "1:Assert"}
set_parameter_property SWI_CPURESET_INIT HDL_PARAMETER true


# 
# display items
# 
add_display_item Hostbridge HOSTINTERFACE_TYPE parameter
add_display_item Hostbridge HOSTUART_BAUDRATE parameter
add_display_item Hostbridge HOSTUART_INFIFODEPTH parameter

add_display_item ConfigurationLayer USE_RECONFIG parameter
add_display_item ConfigurationLayer RECONF_DELAY_TIME parameter
add_display_item ConfigurationLayer USE_ALTDUALBOOT parameter
add_display_item ConfigurationLayer USE_CHIPUID parameter
add_display_item ConfigurationLayer PERIDOT_GENCODE parameter

add_display_item SoftwareInterface SWI_CLASSID parameter
add_display_item SoftwareInterface SWI_CPURESET_KEY parameter
add_display_item SoftwareInterface SWI_CPURESET_INIT parameter
add_display_item SoftwareInterface SWI_USE_UIDREAD parameter
add_display_item SoftwareInterface SWI_USE_EPCSBOOT parameter
add_display_item SoftwareInterface SWI_USE_MESSAGE parameter

add_display_item Information info_avsfreq text "Maximum frequency of avsclock signal is 80.0MHz."
add_display_item Information info_mreset text "<html>Input a external reset signal to port <i>corereset.mreset_n</i>.</html>"



#-----------------------------------
# Avalon-MM master interface
#-----------------------------------
#
# connection point avmclock
#
add_interface avmclock clock end
set_interface_property avmclock clockRate 0

add_interface_port avmclock csi_avmclock_clk clk Input 1

#
# connection point avmreset
#
add_interface avmreset reset end
set_interface_property avmreset associatedClock avmclock
set_interface_property avmreset synchronousEdges DEASSERT

add_interface_port avmreset csi_avmclock_reset reset Input 1

#
# connection point m1
#
add_interface m1 avalon start
set_interface_property m1 addressUnits SYMBOLS
set_interface_property m1 associatedClock avmclock
set_interface_property m1 associatedReset avmreset
set_interface_property m1 bitsPerSymbol 8
set_interface_property m1 burstOnBurstBoundariesOnly false
set_interface_property m1 burstcountUnits WORDS
set_interface_property m1 doStreamReads false
set_interface_property m1 doStreamWrites false
set_interface_property m1 holdTime 0
set_interface_property m1 linewrapBursts false
set_interface_property m1 maximumPendingReadTransactions 0
set_interface_property m1 maximumPendingWriteTransactions 0
set_interface_property m1 readLatency 0
set_interface_property m1 readWaitTime 1
set_interface_property m1 setupTime 0
set_interface_property m1 timingUnits Cycles
set_interface_property m1 writeWaitTime 0

add_interface_port m1 avm_m1_address address Output 32
add_interface_port m1 avm_m1_readdata readdata Input 32
add_interface_port m1 avm_m1_read read Output 1
add_interface_port m1 avm_m1_write write Output 1
add_interface_port m1 avm_m1_byteenable byteenable Output 4
add_interface_port m1 avm_m1_writedata writedata Output 32
add_interface_port m1 avm_m1_waitrequest waitrequest Input 1
add_interface_port m1 avm_m1_readdatavalid readdatavalid Input 1


#-----------------------------------
# Avalon-MM slave interface
#-----------------------------------
# 
# connection point avsclock
# 
add_interface avsclock clock end
set_interface_property avsclock clockRate 0

add_interface_port avsclock csi_avsclock_clk clk Input 1

# 
# connection point avsreset
# 
add_interface avsreset reset end
set_interface_property avsreset associatedClock avsclock
set_interface_property avsreset synchronousEdges DEASSERT

add_interface_port avsreset csi_avsclock_reset reset Input 1

# 
# connection point s1
# 
add_interface s1 avalon end
set_interface_property s1 addressUnits WORDS
set_interface_property s1 associatedClock avsclock
set_interface_property s1 associatedReset avsreset
set_interface_property s1 bitsPerSymbol 8
set_interface_property s1 burstOnBurstBoundariesOnly false
set_interface_property s1 burstcountUnits WORDS
set_interface_property s1 explicitAddressSpan 0
set_interface_property s1 holdTime 0
set_interface_property s1 linewrapBursts false
set_interface_property s1 maximumPendingReadTransactions 0
set_interface_property s1 maximumPendingWriteTransactions 0
set_interface_property s1 readLatency 0
set_interface_property s1 readWaitTime 1
set_interface_property s1 setupTime 0
set_interface_property s1 timingUnits Cycles
set_interface_property s1 writeWaitTime 0

add_interface_port s1 avs_s1_address address Input 3
add_interface_port s1 avs_s1_read read Input 1
add_interface_port s1 avs_s1_readdata readdata Output 32
add_interface_port s1 avs_s1_write write Input 1
add_interface_port s1 avs_s1_writedata writedata Input 32
set_interface_assignment s1 embeddedsw.configuration.isFlash 0
set_interface_assignment s1 embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment s1 embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment s1 embeddedsw.configuration.isPrintableDevice 0

# 
# connection point avsirq
# 
add_interface avsirq interrupt end
set_interface_property avsirq associatedClock avmclock
set_interface_property avsirq associatedReset busreset

add_interface_port avsirq ins_avsirq_irq irq Output 1


#-----------------------------------
# Avalon-MM Reset source
#-----------------------------------
# 
# connection point busreset
# 

add_interface busreset reset start
set_interface_property busreset associatedClock avmclock
set_interface_property busreset associatedResetSinks avmreset
set_interface_property busreset synchronousEdges DEASSERT

add_interface_port busreset rso_busreset_reset reset Output 1


#-----------------------------------
# Other condit interface
#-----------------------------------
# 
# connection point host
# 
add_interface corereset conduit end
set_interface_property corereset associatedClock avmclock
add_interface_port corereset coe_mreset_n mreset_n Input 1

add_interface hostuart conduit end
set_interface_property hostuart associatedClock avmclock
add_interface_port hostuart coe_rxd rxd Input 1
add_interface_port hostuart coe_txd txd Output 1

add_interface hostft conduit end
set_interface_property hostft associatedClock avmclock
add_interface_port hostft coe_ft_d data Bidir 8
add_interface_port hostft coe_ft_rd_n rd_n Output 1
add_interface_port hostft coe_ft_wr wr Output 1
add_interface_port hostft coe_ft_rxf_n rxf_n Input 1
add_interface_port hostft coe_ft_txe_n txe_n Input 1
add_interface_port hostft coe_ft_siwu_n siwu_n Output 1


# 
# connection point swi
# 
add_interface swi conduit end
set_interface_property swi associatedClock avsclock
set_interface_property swi associatedReset avsreset
add_interface_port swi coe_cpureset cpu_resetrequest Output 1
add_interface_port swi coe_led led Output 4

add_interface swi_epcs conduit end
set_interface_property swi_epcs associatedClock avsclock
set_interface_property swi_epcs associatedReset avsreset
add_interface_port swi_epcs coe_cso_n cso_n Output 1
add_interface_port swi_epcs coe_dclk dclk Output 1
add_interface_port swi_epcs coe_asdo asdo Output 1
add_interface_port swi_epcs coe_data0 data0 Input 1




# *******************************************************************
#
#  File generate callback
#
# *******************************************************************

proc generate_synth {entityname} {
	send_message info "generating top-level entity ${entityname}"

	#-----------------------------------
	# PERIDOT ip files
	#-----------------------------------

#	set hdlpath "../../.."
	set hdlpath "./hdl"

	add_fileset_file peridot_board_eeprom.v VERILOG PATH "${hdlpath}/peridot_board_eeprom.v"
	add_fileset_file peridot_board_i2c.v VERILOG PATH "${hdlpath}/peridot_board_i2c.v"
	add_fileset_file peridot_board_romdata.v VERILOG PATH "${hdlpath}/peridot_board_romdata.v"
	add_fileset_file peridot_config.v VERILOG PATH "${hdlpath}/peridot_config.v"
	add_fileset_file peridot_config_proc.v VERILOG PATH "${hdlpath}/peridot_config_proc.v"
	add_fileset_file peridot_config_ru.v VERILOG PATH "${hdlpath}/peridot_config_ru.v"
	add_fileset_file peridot_csr_spi.v VERILOG PATH "${hdlpath}/peridot_csr_spi.v"
	add_fileset_file peridot_csr_swi.v VERILOG PATH "${hdlpath}/peridot_csr_swi.v"
	add_fileset_file peridot_hostbridge.sdc SDC PATH "${hdlpath}/peridot_hostbridge.sdc"
	add_fileset_file peridot_hostbridge.v VERILOG PATH "${hdlpath}/peridot_hostbridge.v" TOP_LEVEL_FILE
	add_fileset_file peridot_mm_master.v VERILOG PATH "${hdlpath}/peridot_mm_master.v"
	add_fileset_file peridot_phy_ft245.v VERILOG PATH "${hdlpath}/peridot_phy_ft245.v"
	add_fileset_file peridot_phy_rxd.v VERILOG PATH "${hdlpath}/peridot_phy_rxd.v"
	add_fileset_file peridot_phy_txd.v VERILOG PATH "${hdlpath}/peridot_phy_txd.v"


	#-----------------------------------
	# Altera ip files
	#-----------------------------------

	set quartus_ip "${::env(QUARTUS_ROOTDIR)}/../ip/altera"

	add_fileset_file altera_avalon_packets_to_master.v VERILOG PATH "${quartus_ip}/sopc_builder_ip/altera_avalon_packets_to_master/altera_avalon_packets_to_master.v"
	add_fileset_file altera_avalon_st_bytes_to_packets.v VERILOG PATH "${quartus_ip}/sopc_builder_ip/altera_avalon_st_bytes_to_packets/altera_avalon_st_bytes_to_packets.v"
	add_fileset_file altera_avalon_st_packets_to_bytes.v VERILOG PATH "${quartus_ip}/sopc_builder_ip/altera_avalon_st_packets_to_bytes/altera_avalon_st_packets_to_bytes.v"

	if {[get_parameter_value CHIPUID_FEATURE] == "ENABLE"} {
		add_fileset_file altchip_id.v VERILOG PATH "${quartus_ip}/altchip_id/source/altchip_id.v"
	}

	if {[get_parameter_value RECONFIG_FEATURE] == "ENABLE" || [get_parameter_value INSTANCE_ALTDUALBOOT] == "ENABLE"} {
		add_fileset_file ../rtl/alt_dual_boot_avmm.v VERILOG PATH "${quartus_ip}/altera_dual_boot/rtl/alt_dual_boot_avmm.v"
		add_fileset_file ../rtl/alt_dual_boot.v VERILOG PATH "${quartus_ip}/altera_dual_boot/rtl/alt_dual_boot.v"
	}

}



# *******************************************************************
#
#  Elaboration callback
#
# *******************************************************************

proc elaboration_callback {} {

	#-----------------------------------
	# setup host intrface type
	#-----------------------------------

	set host_interface_type [get_parameter_value HOSTINTERFACE_TYPE]

	set_parameter_property HOSTUART_BAUDRATE ENABLED false
	set_parameter_property HOSTUART_INFIFODEPTH ENABLED false
	set_interface_property hostuart ENABLED false
	set_interface_property hostft ENABLED false

	switch $host_interface_type {
	"UART" {
		set_parameter_property HOSTUART_BAUDRATE ENABLED true
		set_parameter_property HOSTUART_INFIFODEPTH ENABLED true
		set_interface_property hostuart ENABLED true

		# validate uart baudrate error
		set uart_clock [get_parameter_value AVM_CLOCKFREQ]
		set uart_baudrate [get_parameter_value HOSTUART_BAUDRATE]
		set uart_divcount [expr (ceil($uart_clock / $uart_baudrate)) - 1]
		set uart_maxdiv [expr (ceil(pow(2,12))) - 1]

		if {$uart_clock == 0} {
			send_message error "avmclock signal clock frequency is unknown."
		} else {
			if {$uart_divcount > $uart_maxdiv} {
				send_message error "This baudrate is not supported. avmclock signal is changed to the slow clock frequency."
			} elseif {$uart_divcount < 8} {
				send_message error "This baudrate is not supported. avmclock signal is changed to the fast clock frequency."
			} else {
				if {[expr (abs($uart_baudrate - ($uart_clock /($uart_divcount + 1)))*100)/ $uart_baudrate] > 1.0} {
					send_message warning "An error of this baudrate is more than 1%. Recommend to change a clock frequency or baudrate."
				}
			}
		}
	}

	"FT245" {
		set_interface_property hostft ENABLED true
	}

	default {
		send_message error "${host_interface_type} is not defined interface type."
	}}


	#-----------------------------------
	# setup feature option
	#-----------------------------------

	set devfamily [get_parameter_value DEVICE_FAMILY]
	if {$devfamily == "MAX 10"} {
		set_parameter_property USE_RECONFIG ENABLED true
	} else {
		set_parameter_property USE_RECONFIG ENABLED false
		send_message info "${devfamily} isn't supporting reconfiguration function."
	}

#	if {$devfamily == "MAX 10" || $devfamily == "Cyclone V" || $devfamily == "Arria V" || $devfamily == "Arria V GZ" || $devfamily == "Straix V"} {
#	}
	if {$devfamily == "MAX 10" || $devfamily == "Cyclone V"} {
		set_parameter_property USE_CHIPUID ENABLED true
	} else {
		send_message info "${devfamily} isn't supporting chip-UID function."
		set_parameter_property USE_CHIPUID ENABLED false
	}


	if {[get_parameter_value USE_RECONFIG] && [get_parameter_property USE_RECONFIG ENABLED]} {
		set_parameter_value RECONFIG_FEATURE "ENABLE"
		set_parameter_property RECONF_DELAY_TIME ENABLED true
		set_parameter_property USE_ALTDUALBOOT ENABLED false
	} else {
		set_parameter_value RECONFIG_FEATURE "DISABLE"
		set_parameter_property RECONF_DELAY_TIME ENABLED false

		if {$devfamily == "MAX 10"} {
			set_parameter_property USE_ALTDUALBOOT ENABLED true
		} else {
			set_parameter_property USE_ALTDUALBOOT ENABLED false
		}
	}

	if {[get_parameter_value USE_ALTDUALBOOT] && [get_parameter_property USE_ALTDUALBOOT ENABLED]} {
		set_parameter_value INSTANCE_ALTDUALBOOT "ENABLE"
	} else {
		set_parameter_value INSTANCE_ALTDUALBOOT "DISABLE"
	}

	if {[get_parameter_value USE_CHIPUID] && [get_parameter_property USE_CHIPUID ENABLED]} {
		set_parameter_value CHIPUID_FEATURE "ENABLE"
	} else {
		set_parameter_value CHIPUID_FEATURE "DISABLE"
	}


	if {[get_parameter_value SWI_USE_EPCSBOOT]} {
		set_parameter_value SWI_EPCSBOOT_FEATURE "ENABLE"
		set_interface_property swi_epcs ENABLED true
	} else {
		set_parameter_value SWI_EPCSBOOT_FEATURE "DISABLE"
		set_interface_property swi_epcs ENABLED false
	}

	if {[get_parameter_value SWI_USE_UIDREAD]} {
		set_parameter_value SWI_UIDREAD_FEATURE "ENABLE"

		if {[get_parameter_value CHIPUID_FEATURE] != "ENABLE"} {
			send_message warning "The fixed value is read for chip-UID register of swi peripherals."
		}
	} else {
		set_parameter_value SWI_UIDREAD_FEATURE "DISABLE"
	}

	if {[get_parameter_value SWI_USE_MESSAGE]} {
		set_parameter_value SWI_MESSAGE_FEATURE "ENABLE"
		set_interface_property avsirq ENABLED true
	} else {
		set_parameter_value SWI_MESSAGE_FEATURE "DISABLE"
		set_interface_property avsirq ENABLED false
	}


	#-----------------------------------
	# setup reconfig parameter
	#-----------------------------------

	set dc_clock_frequency [get_parameter_value AVS_CLOCKFREQ]

	if {$dc_clock_frequency == 0} {
		set dc_clock_frequency 80000000
		send_message error "avsclock signal clock frequency is unknown."

	} elseif {$dc_clock_frequency > 80000000} {
		set dc_clock_frequency 80000000
		send_message warning "avsclock signal clock frequency is set to ${dc_clock_frequency} Hz, but the target device only supports maximum 80000000 Hz."
	}

	set dc_reconf_delay_time [get_parameter_value RECONF_DELAY_TIME]
	set dc_delay_cycle [expr (ceil($dc_reconf_delay_time*(pow(10,-3)) * $dc_clock_frequency))]
	set_parameter_value RECONF_DELAY_CYCLE $dc_delay_cycle

	set dc_config_cycle [expr (ceil(350*(pow(10,-9)) * $dc_clock_frequency))]
	set_parameter_value CONFIG_CYCLE $dc_config_cycle

	set dc_reset_cycle [expr (ceil(500*(pow(10,-9)) * $dc_clock_frequency))]
	set_parameter_value RESET_TIMER_CYCLE $dc_reset_cycle


	#-----------------------------------
	# SWI Validation
	#-----------------------------------

	# Software assignments for system.h
	set_module_assignment embeddedsw.CMacro.ID				[format 0x%08x [get_parameter_value SWI_CLASSID]]
	set_module_assignment embeddedsw.CMacro.TIMESTAMP		[format %u [get_parameter_value SWI_TIMECODE]]
	set_module_assignment embeddedsw.CMacro.CPURESET_KEY	[format 0x%04x [get_parameter_value SWI_CPURESET_KEY]]
	set_module_assignment embeddedsw.CMacro.USE_UIDREAD		[expr ([get_parameter_value SWI_USE_UIDREAD]? 1 : 0)]
	set_module_assignment embeddedsw.CMacro.USE_EPCSBOOT	[expr ([get_parameter_value SWI_USE_EPCSBOOT]? 1 : 0)]
	set_module_assignment embeddedsw.CMacro.USE_MESSAGE		[expr ([get_parameter_value SWI_USE_MESSAGE]? 1 : 0)]

	# Explain that timestamp will only be known during generation thus will not be shown
	send_message info "Time code and clock rate will be automatically updated when this component is generated."
}

