# ===================================================================
# TITLE : PERIDOT-NGS / "PERIDOT Ethernet I/O Bridge"
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2022/07/01 -> 2022/09/29
#
# ===================================================================
#
# The MIT License (MIT)
# Copyright (c) 2022 J-7SYSTEM WORKS LIMITED.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is furnished to do
# so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

# 
# request TCL package from ACDS 16.1
# 
package require -exact qsys 16.1


# 
# module peridot_ethio
# 
set_module_property NAME peridot_ethio
set_module_property DISPLAY_NAME "PERIDOT Ethernet I/O Bridge (Alpha test version)"
set_module_property DESCRIPTION "PERIDOT Ethernet I/O Bridge"
set_module_property GROUP "PERIDOT Peripherals"
set_module_property AUTHOR "J-7SYSTEM WORKS LIMITED"
set_module_property VERSION 20.1
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property HIDE_FROM_SOPC true
set_module_property HIDE_FROM_QUARTUS false
set_module_property EDITABLE false
set_module_property ELABORATION_CALLBACK elaboration_callback
#set_module_property SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone IV E" "Cyclone IV GX" "Cyclone V" "Arria II GX" "Arria II GZ" "Arria V" "Arria V GZ" "Stratix IV" "Stratix V"}


# 
# file sets
# 
add_fileset quartus_synth QUARTUS_SYNTH generate_synth
set_fileset_property QUARTUS_SYNTH TOP_LEVEL peridot_ethio


# 
# parameters
# 
set debugview false

add_parameter DEVICE_FAMILY string
set_parameter_property DEVICE_FAMILY SYSTEM_INFO {DEVICE_FAMILY}
set_parameter_property DEVICE_FAMILY ENABLED false
set_parameter_property DEVICE_FAMILY VISIBLE $debugview
add_parameter PART_NAME string
set_parameter_property PART_NAME SYSTEM_INFO {DEVICE}
set_parameter_property PART_NAME ENABLED false
set_parameter_property PART_NAME VISIBLE $debugview

add_parameter RXFIFO_SIZE integer 4096
set_parameter_property RXFIFO_SIZE DISPLAY_NAME "MAC frame RX-FIFO Size"
set_parameter_property RXFIFO_SIZE UNITS bytes
set_parameter_property RXFIFO_SIZE ALLOWED_RANGES {4096 8192 16384 32768 65536}
set_parameter_property RXFIFO_SIZE HDL_PARAMETER true

add_parameter TXFIFO_SIZE integer 4096
set_parameter_property TXFIFO_SIZE DISPLAY_NAME "MAC frame TX-FIFO Size"
set_parameter_property TXFIFO_SIZE UNITS bytes
set_parameter_property TXFIFO_SIZE ALLOWED_RANGES {4096 8192 16384 32768 65536}
set_parameter_property TXFIFO_SIZE HDL_PARAMETER true

add_parameter FIFO_BLOCKSIZE integer 64
set_parameter_property FIFO_BLOCKSIZE HDL_PARAMETER true
set_parameter_property FIFO_BLOCKSIZE DERIVED true
set_parameter_property FIFO_BLOCKSIZE VISIBLE $debugview

add_parameter SUPPORT_SPEED_10M integer 1
set_parameter_property SUPPORT_SPEED_10M DISPLAY_NAME "Support 10Mbps mode."
set_parameter_property SUPPORT_SPEED_10M DESCRIPTION "When using 10Mbps speed switching, is turned on. Fixed at 100Mbps when off."
set_parameter_property SUPPORT_SPEED_10M DISPLAY_HINT boolean
set_parameter_property SUPPORT_SPEED_10M HDL_PARAMETER true

add_parameter SUPPORT_HARFDUPLEX integer 1
set_parameter_property SUPPORT_HARFDUPLEX DISPLAY_NAME "Support half-duplex mode."
set_parameter_property SUPPORT_HARFDUPLEX DESCRIPTION "When using half/full-duplex switching, is turned on. Fixed at full-duplex when off."
set_parameter_property SUPPORT_HARFDUPLEX DISPLAY_HINT boolean
set_parameter_property SUPPORT_HARFDUPLEX HDL_PARAMETER true

add_parameter SUPPORT_PAUSEFRAME integer 0
set_parameter_property SUPPORT_PAUSEFRAME DISPLAY_NAME "Support PAUSE frame."
set_parameter_property SUPPORT_PAUSEFRAME DESCRIPTION "Turn on to handle PAUSE frames. PAUSE frames are invalid in half-duplex mode."
set_parameter_property SUPPORT_PAUSEFRAME DISPLAY_HINT boolean
set_parameter_property SUPPORT_PAUSEFRAME HDL_PARAMETER true

add_parameter MTU_SIZE integer 1500
set_parameter_property MTU_SIZE DISPLAY_NAME "MTU Size (576-1500)"
set_parameter_property MTU_SIZE UNITS bytes
set_parameter_property MTU_SIZE ALLOWED_RANGES 576:1500
set_parameter_property MTU_SIZE HDL_PARAMETER true

add_parameter ENABLE_UDP_CHECKSUM integer 1
set_parameter_property ENABLE_UDP_CHECKSUM DISPLAY_NAME "Enable UDP header checksum."
set_parameter_property ENABLE_UDP_CHECKSUM DISPLAY_HINT boolean
set_parameter_property ENABLE_UDP_CHECKSUM HDL_PARAMETER true

add_parameter IGNORE_RXFCS_CHECK integer 0
set_parameter_property IGNORE_RXFCS_CHECK DISPLAY_NAME "Ignore FCS in received frames."
set_parameter_property IGNORE_RXFCS_CHECK DISPLAY_HINT boolean
set_parameter_property IGNORE_RXFCS_CHECK HDL_PARAMETER true
set_parameter_property IGNORE_RXFCS_CHECK ENABLED false

add_parameter FIXED_MAC_ADDRESS std_logic_vector 0
set_parameter_property FIXED_MAC_ADDRESS WIDTH 48
set_parameter_property FIXED_MAC_ADDRESS HDL_PARAMETER true
set_parameter_property FIXED_MAC_ADDRESS DERIVED true
set_parameter_property FIXED_MAC_ADDRESS VISIBLE $debugview

add_parameter FIXED_IP_ADDRESS std_logic_vector 0
set_parameter_property FIXED_IP_ADDRESS WIDTH 32
set_parameter_property FIXED_IP_ADDRESS HDL_PARAMETER true
set_parameter_property FIXED_IP_ADDRESS DERIVED true
set_parameter_property FIXED_IP_ADDRESS VISIBLE $debugview

add_parameter FIXED_UDP_PORT integer 0
set_parameter_property FIXED_UDP_PORT HDL_PARAMETER true
set_parameter_property FIXED_UDP_PORT DERIVED true
set_parameter_property FIXED_UDP_PORT VISIBLE $debugview

add_parameter FIXED_PAUSE_LESS integer 0
set_parameter_property FIXED_PAUSE_LESS HDL_PARAMETER true
set_parameter_property FIXED_PAUSE_LESS DERIVED true
set_parameter_property FIXED_PAUSE_LESS VISIBLE $debugview

add_parameter FIXED_PAUSE_VALUE integer 0
set_parameter_property FIXED_PAUSE_VALUE HDL_PARAMETER true
set_parameter_property FIXED_PAUSE_VALUE DERIVED true
set_parameter_property FIXED_PAUSE_VALUE VISIBLE $debugview

add_parameter SUPPORT_MEMORYHOST integer 1
set_parameter_property SUPPORT_MEMORYHOST DISPLAY_NAME "Use Avalon-MM memory host interface."
set_parameter_property SUPPORT_MEMORYHOST DISPLAY_HINT boolean
set_parameter_property SUPPORT_MEMORYHOST HDL_PARAMETER true

add_parameter AVALONMM_FASTMODE integer 0
set_parameter_property AVALONMM_FASTMODE DISPLAY_NAME "Enable Avalon-MM FAST mode."
set_parameter_property AVALONMM_FASTMODE DISPLAY_HINT boolean
set_parameter_property AVALONMM_FASTMODE HDL_PARAMETER true

add_parameter SUPPORT_STREAMFIFO integer 1
set_parameter_property SUPPORT_STREAMFIFO DISPLAY_NAME "Use Avalon-ST stream interface."
set_parameter_property SUPPORT_STREAMFIFO DISPLAY_HINT boolean
set_parameter_property SUPPORT_STREAMFIFO HDL_PARAMETER true

add_parameter SRCFIFO_NUMBER integer 1
set_parameter_property SRCFIFO_NUMBER DISPLAY_NAME "Number of Source ports"
set_parameter_property SRCFIFO_NUMBER ALLOWED_RANGES {0:none 1 2 3 4}
set_parameter_property SRCFIFO_NUMBER HDL_PARAMETER true

add_parameter SINKFIFO_NUMBER integer 1
set_parameter_property SINKFIFO_NUMBER DISPLAY_NAME "Number of Sink ports"
set_parameter_property SINKFIFO_NUMBER ALLOWED_RANGES {0:none 1 2 3 4}
set_parameter_property SINKFIFO_NUMBER HDL_PARAMETER true

add_parameter SRCFIFO_0_SIZE integer 2048
set_parameter_property SRCFIFO_0_SIZE DISPLAY_NAME "Source 0 FIFO Size"
set_parameter_property SRCFIFO_0_SIZE UNITS bytes
set_parameter_property SRCFIFO_0_SIZE ALLOWED_RANGES {1024 2048 4096 8192 16384 32768 65536}
set_parameter_property SRCFIFO_0_SIZE HDL_PARAMETER true

add_parameter SRCFIFO_1_SIZE integer 2048
set_parameter_property SRCFIFO_1_SIZE DISPLAY_NAME "Source 1 FIFO Size"
set_parameter_property SRCFIFO_1_SIZE UNITS bytes
set_parameter_property SRCFIFO_1_SIZE ALLOWED_RANGES {1024 2048 4096 8192 16384 32768 65536}
set_parameter_property SRCFIFO_1_SIZE HDL_PARAMETER true

add_parameter SRCFIFO_2_SIZE integer 2048
set_parameter_property SRCFIFO_2_SIZE DISPLAY_NAME "Source 2 FIFO Size"
set_parameter_property SRCFIFO_2_SIZE UNITS bytes
set_parameter_property SRCFIFO_2_SIZE ALLOWED_RANGES {1024 2048 4096 8192 16384 32768 65536}
set_parameter_property SRCFIFO_2_SIZE HDL_PARAMETER true

add_parameter SRCFIFO_3_SIZE integer 2048
set_parameter_property SRCFIFO_3_SIZE DISPLAY_NAME "Source 3 FIFO Size"
set_parameter_property SRCFIFO_3_SIZE UNITS bytes
set_parameter_property SRCFIFO_3_SIZE ALLOWED_RANGES {1024 2048 4096 8192 16384 32768 65536}
set_parameter_property SRCFIFO_3_SIZE HDL_PARAMETER true

add_parameter SINKFIFO_0_SIZE integer 2048
set_parameter_property SINKFIFO_0_SIZE DISPLAY_NAME "Sink 0 FIFO Size"
set_parameter_property SINKFIFO_0_SIZE UNITS bytes
set_parameter_property SINKFIFO_0_SIZE ALLOWED_RANGES {1024 2048 4096 8192 16384 32768 65536}
set_parameter_property SINKFIFO_0_SIZE HDL_PARAMETER true

add_parameter SINKFIFO_1_SIZE integer 2048
set_parameter_property SINKFIFO_1_SIZE DISPLAY_NAME "Sink 1 FIFO Size"
set_parameter_property SINKFIFO_1_SIZE UNITS bytes
set_parameter_property SINKFIFO_1_SIZE ALLOWED_RANGES {1024 2048 4096 8192 16384 32768 65536}
set_parameter_property SINKFIFO_1_SIZE HDL_PARAMETER true

add_parameter SINKFIFO_2_SIZE integer 2048
set_parameter_property SINKFIFO_2_SIZE DISPLAY_NAME "Sink 2 FIFO Size"
set_parameter_property SINKFIFO_2_SIZE UNITS bytes
set_parameter_property SINKFIFO_2_SIZE ALLOWED_RANGES {1024 2048 4096 8192 16384 32768 65536}
set_parameter_property SINKFIFO_2_SIZE HDL_PARAMETER true

add_parameter SINKFIFO_3_SIZE integer 2048
set_parameter_property SINKFIFO_3_SIZE DISPLAY_NAME "Sink 3 FIFO Size"
set_parameter_property SINKFIFO_3_SIZE UNITS bytes
set_parameter_property SINKFIFO_3_SIZE ALLOWED_RANGES {1024 2048 4096 8192 16384 32768 65536}
set_parameter_property SINKFIFO_3_SIZE HDL_PARAMETER true


add_parameter USE_FIXED_PAUSE boolean true
set_parameter_property USE_FIXED_PAUSE DISPLAY_NAME "Use fixed PAUSE frame value."
set_parameter_property USE_FIXED_PAUSE DISPLAY_HINT boolean
add_parameter PAUSELESS_VALUE integer 0
set_parameter_property PAUSELESS_VALUE DISPLAY_NAME "RX-FIFO threshold"
set_parameter_property PAUSELESS_VALUE DESCRIPTION "A PAUSE frame is sent when the free amount of RXFIFO is less than to this setting."
set_parameter_property PAUSELESS_VALUE ALLOWED_RANGES {0:Auto 1:Quarter 2:Half}
add_parameter PAUSEFRAME_VALUE integer 65535
set_parameter_property PAUSEFRAME_VALUE DISPLAY_NAME "Request wait timeslot"
set_parameter_property PAUSEFRAME_VALUE ALLOWED_RANGES 1:65535

add_parameter USE_FIXED_MACADDR boolean false
set_parameter_property USE_FIXED_MACADDR DISPLAY_NAME "Use fixed MAC address (NIC ID)."
set_parameter_property USE_FIXED_MACADDR DISPLAY_HINT boolean
add_parameter MACADDR_VALUE std_logic_vector 0xfeffff000001
set_parameter_property MACADDR_VALUE DISPLAY_NAME "MAC address"
set_parameter_property MACADDR_VALUE DESCRIPTION "If the MAC address to be set is 11-22-33-44-55-66, enter 0x112233445566."
set_parameter_property MACADDR_VALUE WIDTH 48
set_parameter_property MACADDR_VALUE ALLOWED_RANGES 0x000000000001:0xffffffffffff

add_parameter USE_FIXED_IPADDR boolean false
set_parameter_property USE_FIXED_IPADDR DISPLAY_NAME "Use fixed IP address."
set_parameter_property USE_FIXED_IPADDR DISPLAY_HINT boolean
add_parameter IPADDR_VALUE std_logic_vector 0xc0a80172
set_parameter_property IPADDR_VALUE DISPLAY_NAME "IP address"
set_parameter_property IPADDR_VALUE DESCRIPTION "If the IP address to be set is 192.168.0.100, enter 0xc0a80064."
set_parameter_property IPADDR_VALUE WIDTH 32
set_parameter_property IPADDR_VALUE ALLOWED_RANGES 0x00000001:0xffffffff

add_parameter USE_FIXED_UDPPORT boolean true
set_parameter_property USE_FIXED_UDPPORT DISPLAY_NAME "Use fixed UDP ports number."
set_parameter_property USE_FIXED_UDPPORT DISPLAY_HINT boolean
add_parameter UDPPORT_VALUE integer 16241
set_parameter_property UDPPORT_VALUE DISPLAY_NAME "UDP Listen port"
set_parameter_property UDPPORT_VALUE ALLOWED_RANGES 1:65535


# 
# display items
# 
add_display_item "Ethernet Configuration" MTU_SIZE parameter
add_display_item "Ethernet Configuration" RXFIFO_SIZE parameter
add_display_item "Ethernet Configuration" TXFIFO_SIZE parameter
add_display_item "Ethernet Configuration" IGNORE_RXFCS_CHECK parameter
add_display_item "Ethernet Configuration" SUPPORT_SPEED_10M parameter
add_display_item "Ethernet Configuration" SUPPORT_HARFDUPLEX parameter
add_display_item "Ethernet Configuration" SUPPORT_PAUSEFRAME parameter
add_display_item "Ethernet Configuration" USE_FIXED_PAUSE parameter
add_display_item "Ethernet Configuration" PAUSELESS_VALUE parameter
add_display_item "Ethernet Configuration" PAUSEFRAME_VALUE parameter
add_display_item "Ethernet Configuration" USE_FIXED_MACADDR parameter
add_display_item "Ethernet Configuration" MACADDR_VALUE parameter
add_display_item "Ethernet Configuration" USE_FIXED_IPADDR parameter
add_display_item "Ethernet Configuration" IPADDR_VALUE parameter
add_display_item "Ethernet Configuration" USE_FIXED_UDPPORT parameter
add_display_item "Ethernet Configuration" UDPPORT_VALUE parameter
add_display_item "Ethernet Configuration" ENABLE_UDP_CHECKSUM parameter

add_display_item "Interface" SUPPORT_MEMORYHOST parameter
add_display_item "Interface" AVALONMM_FASTMODE parameter
add_display_item "Interface" SUPPORT_STREAMFIFO parameter
add_display_item "Interface" SRCFIFO_NUMBER parameter
add_display_item "Interface" SRCFIFO_0_SIZE parameter
add_display_item "Interface" SRCFIFO_1_SIZE parameter
add_display_item "Interface" SRCFIFO_2_SIZE parameter
add_display_item "Interface" SRCFIFO_3_SIZE parameter
add_display_item "Interface" SINKFIFO_NUMBER parameter
add_display_item "Interface" SINKFIFO_0_SIZE parameter
add_display_item "Interface" SINKFIFO_1_SIZE parameter
add_display_item "Interface" SINKFIFO_2_SIZE parameter
add_display_item "Interface" SINKFIFO_3_SIZE parameter


#-----------------------------------
# Clock and Reset interface
#-----------------------------------
# 
# connection point clock
# 
add_interface clock clock sink
set_interface_property clock clockRate 0

add_interface_port clock csi_clock_clk clk Input 1

# 
# connection point reset
# 
add_interface reset reset sink
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT

add_interface_port reset rsi_reset_reset reset Input 1

#-----------------------------------
# Avalon-MM master interface
#-----------------------------------
# 
# connection point m1
# 
add_interface m1 avalon master
set_interface_property m1 addressUnits SYMBOLS
set_interface_property m1 associatedClock clock
set_interface_property m1 associatedReset reset
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

add_interface_port m1 avm_m1_waitrequest waitrequest Input 1
add_interface_port m1 avm_m1_address address Output 32
add_interface_port m1 avm_m1_read read Output 1
add_interface_port m1 avm_m1_readdata readdata Input 32
add_interface_port m1 avm_m1_readdatavalid readdatavalid Input 1
add_interface_port m1 avm_m1_write write Output 1
add_interface_port m1 avm_m1_writedata writedata Output 32
add_interface_port m1 avm_m1_byteenable byteenable Output 4

#-----------------------------------
# Avalon-ST Source interface
#-----------------------------------
# 
# connection point src0
# 
add_interface src0 avalon_streaming source
set_interface_property src0 associatedClock clock
set_interface_property src0 associatedReset reset
set_interface_property src0 dataBitsPerSymbol 8
set_interface_property src0 maxChannel 0
set_interface_property src0 readyLatency 0
set_interface_property src0 symbolsPerBeat 1

add_interface_port src0 aso_src0_ready ready Input 1
add_interface_port src0 aso_src0_valid valid Output 1
add_interface_port src0 aso_src0_data data Output 8

# 
# connection point src1
# 
add_interface src1 avalon_streaming source
set_interface_property src1 associatedClock clock
set_interface_property src1 associatedReset reset
set_interface_property src1 dataBitsPerSymbol 8
set_interface_property src1 maxChannel 0
set_interface_property src1 readyLatency 0
set_interface_property src1 symbolsPerBeat 1

add_interface_port src1 aso_src1_ready ready Input 1
add_interface_port src1 aso_src1_valid valid Output 1
add_interface_port src1 aso_src1_data data Output 8

# 
# connection point src2
# 
add_interface src2 avalon_streaming source
set_interface_property src2 associatedClock clock
set_interface_property src2 associatedReset reset
set_interface_property src2 dataBitsPerSymbol 8
set_interface_property src2 maxChannel 0
set_interface_property src2 readyLatency 0
set_interface_property src2 symbolsPerBeat 1

add_interface_port src2 aso_src2_ready ready Input 1
add_interface_port src2 aso_src2_valid valid Output 1
add_interface_port src2 aso_src2_data data Output 8

# 
# connection point src3
# 
add_interface src3 avalon_streaming source
set_interface_property src3 associatedClock clock
set_interface_property src3 associatedReset reset
set_interface_property src3 dataBitsPerSymbol 8
set_interface_property src3 maxChannel 0
set_interface_property src3 readyLatency 0
set_interface_property src3 symbolsPerBeat 1

add_interface_port src3 aso_src3_ready ready Input 1
add_interface_port src3 aso_src3_valid valid Output 1
add_interface_port src3 aso_src3_data data Output 8

#-----------------------------------
# Avalon-ST Sink interface
#-----------------------------------
# 
# connection point sink0
# 
add_interface sink0 avalon_streaming sink
set_interface_property sink0 associatedClock clock
set_interface_property sink0 associatedReset reset
set_interface_property sink0 dataBitsPerSymbol 8
set_interface_property sink0 maxChannel 0
set_interface_property sink0 readyLatency 0
set_interface_property sink0 symbolsPerBeat 1

add_interface_port sink0 asi_sink0_ready ready Output 1
add_interface_port sink0 asi_sink0_valid valid Input 1
add_interface_port sink0 asi_sink0_data data Input 8

# 
# connection point sink1
# 
add_interface sink1 avalon_streaming sink
set_interface_property sink1 associatedClock clock
set_interface_property sink1 associatedReset reset
set_interface_property sink1 dataBitsPerSymbol 8
set_interface_property sink1 maxChannel 0
set_interface_property sink1 readyLatency 0
set_interface_property sink1 symbolsPerBeat 1

add_interface_port sink1 asi_sink1_ready ready Output 1
add_interface_port sink1 asi_sink1_valid valid Input 1
add_interface_port sink1 asi_sink1_data data Input 8

# 
# connection point sink2
# 
add_interface sink2 avalon_streaming sink
set_interface_property sink2 associatedClock clock
set_interface_property sink2 associatedReset reset
set_interface_property sink2 dataBitsPerSymbol 8
set_interface_property sink2 maxChannel 0
set_interface_property sink2 readyLatency 0
set_interface_property sink2 symbolsPerBeat 1

add_interface_port sink2 asi_sink2_ready ready Output 1
add_interface_port sink2 asi_sink2_valid valid Input 1
add_interface_port sink2 asi_sink2_data data Input 8

# 
# connection point sink3
# 
add_interface sink3 avalon_streaming sink
set_interface_property sink3 associatedClock clock
set_interface_property sink3 associatedReset reset
set_interface_property sink3 dataBitsPerSymbol 8
set_interface_property sink3 maxChannel 0
set_interface_property sink3 readyLatency 0
set_interface_property sink3 symbolsPerBeat 1

add_interface_port sink3 asi_sink3_ready ready Output 1
add_interface_port sink3 asi_sink3_valid valid Input 1
add_interface_port sink3 asi_sink3_data data Input 8

#-----------------------------------
# Conduit interface
#-----------------------------------
# 
# connection point export
# 
add_interface ethio conduit end
set_interface_property ethio associatedClock clock
add_interface_port ethio coe_enable enable Input 1
add_interface_port ethio coe_status status Output 3

add_interface speed10m conduit end
set_interface_property speed10m associatedClock clock
add_interface_port speed10m coe_speed10m sel Input 1

add_interface halfduplex conduit end
set_interface_property halfduplex associatedClock clock
add_interface_port halfduplex coe_halfduplex sel Input 1

add_interface macaddr conduit end
set_interface_property macaddr associatedClock clock
add_interface_port macaddr coe_macaddr value Input 48

add_interface ipaddr conduit end
set_interface_property ipaddr associatedClock clock
add_interface_port ipaddr coe_ipaddr value Input 32

add_interface udpport conduit end
set_interface_property udpport associatedClock clock
add_interface_port udpport coe_udpport valur Input 16

add_interface pause conduit end
set_interface_property pause associatedClock clock
add_interface_port pause coe_pause_less less Input 8
add_interface_port pause coe_pause_value value Input 16

add_interface rmii conduit end
add_interface_port rmii coe_rmii_clk clk Input 1
add_interface_port rmii coe_rmii_rxd rxd Input 2
add_interface_port rmii coe_rmii_crsdv crs_dv Input 1
add_interface_port rmii coe_rmii_txd txd Output 2
add_interface_port rmii coe_rmii_txen tx_en Output 1


# *******************************************************************
#
#  File generate callback
#
# *******************************************************************

proc generate_synth {entityname} {
	send_message info "generating top-level entity ${entityname}"

	#-----------------------------------
	# PERIDOT source files
	#-----------------------------------

	set hdlpath "./hdl"

	add_fileset_file peridot_ethio.v VERILOG PATH "${hdlpath}/peridot_ethio.v" TOP_LEVEL_FILE
	add_fileset_file peridot_ethio_avmm.v VERILOG PATH "${hdlpath}/peridot_ethio_avmm.v"
	add_fileset_file peridot_ethio_avmm_arbiter.v VERILOG PATH "${hdlpath}/peridot_ethio_avmm_arbiter.v"
	add_fileset_file peridot_ethio_avstserver.v VERILOG PATH "${hdlpath}/peridot_ethio_avstserver.v"
	add_fileset_file peridot_ethio_cdb.v VERILOG PATH "${hdlpath}/peridot_ethio_cdb.v"
	add_fileset_file peridot_ethio_crc32.v VERILOG PATH "${hdlpath}/peridot_ethio_crc32.v"
	add_fileset_file peridot_ethio_dpram.v VERILOG PATH "${hdlpath}/peridot_ethio_dpram.v"
	add_fileset_file peridot_ethio_memfifo.v VERILOG PATH "${hdlpath}/peridot_ethio_memfifo.v"
#	add_fileset_file peridot_ethio_packet_to_axi.v VERILOG PATH "${hdlpath}/peridot_ethio_packet_to_axi.v"
	add_fileset_file peridot_ethio_reset.v VERILOG PATH "${hdlpath}/peridot_ethio_reset.v"
	add_fileset_file peridot_ethio_rmii_rx.v VERILOG PATH "${hdlpath}/peridot_ethio_rmii_rx.v"
	add_fileset_file peridot_ethio_rmii_tx.v VERILOG PATH "${hdlpath}/peridot_ethio_rmii_tx.v"
	add_fileset_file peridot_ethio_rxctrl.v VERILOG PATH "${hdlpath}/peridot_ethio_rxctrl.v"
	add_fileset_file peridot_ethio_scfifo.v VERILOG PATH "${hdlpath}/peridot_ethio_scfifo.v"
	add_fileset_file peridot_ethio_stream.v VERILOG PATH "${hdlpath}/peridot_ethio_stream.v"
	add_fileset_file peridot_ethio_txctrl.v VERILOG PATH "${hdlpath}/peridot_ethio_txctrl.v"
	add_fileset_file peridot_ethio_udp2packet.v VERILOG PATH "${hdlpath}/peridot_ethio_udp2packet.v"

	add_fileset_file peridot_ethio.sdc SDC PATH "${hdlpath}/peridot_ethio.sdc"


	#-----------------------------------
	# Altera ip files
	#-----------------------------------

	set quartus_ip "${::env(QUARTUS_ROOTDIR)}/../ip/altera"

	if {[get_parameter_value SUPPORT_MEMORYHOST]} {
		add_fileset_file altera_avalon_packets_to_master.v VERILOG PATH "${quartus_ip}/sopc_builder_ip/altera_avalon_packets_to_master/altera_avalon_packets_to_master.v"
	}
}


# *******************************************************************
#
#  Elaboration callback
#
# *******************************************************************

proc elaboration_callback {} {

	#-----------------------------------
	# FIFO blocksize
	#-----------------------------------

	set fifo_blocksize 64
	set rxfifo_size [get_parameter_value RXFIFO_SIZE]
	set txfifo_size [get_parameter_value TXFIFO_SIZE]

	if {$rxfifo_size > $txfifo_size} {
		set fifo_blocksize [expr $rxfifo_size > 32768 ? 256 : $rxfifo_size > 16384 ? 128 : 64]
	} else {
		set fifo_blocksize [expr $txfifo_size > 32768 ? 256 : $txfifo_size > 16384 ? 128 : 64]
	}
	set_parameter_value FIFO_BLOCKSIZE $fifo_blocksize


	#-----------------------------------
	# SUPPORT_SPEED_10M settings
	#-----------------------------------

	set_interface_property speed10m ENABLED [get_parameter_value SUPPORT_SPEED_10M]


	#-----------------------------------
	# SUPPORT_HARFDUPLEX settigns
	#-----------------------------------

	set_interface_property halfduplex ENABLED [get_parameter_value SUPPORT_HARFDUPLEX]


	#-----------------------------------
	# PAUSE settigns
	#-----------------------------------

	set_interface_property pause ENABLED [expr [get_parameter_value SUPPORT_PAUSEFRAME] && ![get_parameter_value USE_FIXED_PAUSE]]

	set ena_pause_value [expr [get_parameter_value SUPPORT_PAUSEFRAME] && [get_parameter_value USE_FIXED_PAUSE]]
	set_parameter_property USE_FIXED_PAUSE ENABLED [get_parameter_value SUPPORT_PAUSEFRAME]
	set_parameter_property PAUSELESS_VALUE ENABLED $ena_pause_value
	set_parameter_property PAUSEFRAME_VALUE ENABLED $ena_pause_value

	set pause_less_value 0
	set pause_timeslot_value 0
	if {$ena_pause_value} {
		switch [get_parameter_value PAUSELESS_VALUE] {
			1 {
				# Less than quarter
				set pause_less_value [expr ceil(($rxfifo_size / 4) / $fifo_blocksize)]
			}
			2 {
				# Less than half
				set pause_less_value [expr ceil(($rxfifo_size / 2) / $fifo_blocksize)]
			}
			default {
				# Less than 2-frame
				set pause_less_value [expr ceil(([get_parameter_value MTU_SIZE] + 12.0) / $fifo_blocksize) * 2]
			}
		}
		set pause_timeslot_value [get_parameter_value PAUSEFRAME_VALUE]
	}
	set_parameter_value FIXED_PAUSE_LESS $pause_less_value
	set_parameter_value FIXED_PAUSE_VALUE $pause_timeslot_value


	#-----------------------------------
	# FIXED_MAC_ADDRESS settings
	#-----------------------------------

	set ena_fixed_macaddr [get_parameter_value USE_FIXED_MACADDR]
	set_interface_property macaddr ENABLED [expr !$ena_fixed_macaddr]

	set_parameter_property MACADDR_VALUE ENABLED $ena_fixed_macaddr
	set_parameter_value FIXED_MAC_ADDRESS [expr $ena_fixed_macaddr ? [get_parameter_value MACADDR_VALUE] : 0]

	if {$ena_fixed_macaddr} {
		set macaadr_value [get_parameter_value MACADDR_VALUE]
		set _str1 [format %02X [expr ($macaadr_value >> 40) & 255]]
		set _str2 [format %02X [expr ($macaadr_value >> 32) & 255]]
		set _str3 [format %02X [expr ($macaadr_value >> 24) & 255]]
		set _str4 [format %02X [expr ($macaadr_value >> 16) & 255]]
		set _str5 [format %02X [expr ($macaadr_value >> 8) & 255]]
		set _str6 [format %02X [expr ($macaadr_value >> 0) & 255]]
		send_message info "Set fixed MAC address ${_str1}-${_str2}-${_str3}-${_str4}-${_str5}-${_str6}"
	}


	#-----------------------------------
	# FIXED_IP_ADDRESS settings
	#-----------------------------------

	set ena_fixed_ipaddr [get_parameter_value USE_FIXED_IPADDR]
	set_interface_property ipaddr ENABLED [expr !$ena_fixed_ipaddr]

	set_parameter_property IPADDR_VALUE ENABLED $ena_fixed_ipaddr
	set_parameter_value FIXED_IP_ADDRESS [expr $ena_fixed_ipaddr ? [get_parameter_value IPADDR_VALUE] : 0]

	if {$ena_fixed_ipaddr} {
		set ipaadr_value [get_parameter_value IPADDR_VALUE]
		set _dec1 [format %u [expr ($ipaadr_value >> 24) & 255]]
		set _dec2 [format %u [expr ($ipaadr_value >> 16) & 255]]
		set _dec3 [format %u [expr ($ipaadr_value >> 8) & 255]]
		set _dec4 [format %u [expr ($ipaadr_value >> 0) & 255]]
		send_message info "Set fixed IP address ${_dec1}.${_dec2}.${_dec3}.${_dec4}"
	}


	#-----------------------------------
	# FIXED_UDP_PORT settings
	#-----------------------------------

	set ena_fixed_udpport [get_parameter_value USE_FIXED_UDPPORT]
	set_interface_property udpport ENABLED [expr !$ena_fixed_udpport]

	set_parameter_property UDPPORT_VALUE ENABLED $ena_fixed_udpport
	set_parameter_value FIXED_UDP_PORT [expr $ena_fixed_udpport ? [get_parameter_value UDPPORT_VALUE] : 0]


	#-----------------------------------
	# SUPPORT_MEMORYHOST settings
	#-----------------------------------

	set_interface_property m1 ENABLED [get_parameter_value SUPPORT_MEMORYHOST]
	set_parameter_property AVALONMM_FASTMODE ENABLED [get_parameter_value SUPPORT_MEMORYHOST]


	#-----------------------------------
	# SUPPORT_STREAMFIFO settngs
	#-----------------------------------

	set ena_streamfifo [get_parameter_value SUPPORT_STREAMFIFO]
	set_parameter_property SRCFIFO_NUMBER ENABLED $ena_streamfifo
	set_parameter_property SINKFIFO_NUMBER ENABLED $ena_streamfifo

	set ena_srcfifo0 [expr $ena_streamfifo && [get_parameter_value SRCFIFO_NUMBER] > 0]
	set_interface_property src0 ENABLED $ena_srcfifo0
	set_parameter_property SRCFIFO_0_SIZE ENABLED $ena_srcfifo0

	set ena_srcfifo1 [expr $ena_streamfifo && [get_parameter_value SRCFIFO_NUMBER] > 1]
	set_interface_property src1 ENABLED $ena_srcfifo1
	set_parameter_property SRCFIFO_1_SIZE ENABLED $ena_srcfifo1

	set ena_srcfifo2 [expr $ena_streamfifo && [get_parameter_value SRCFIFO_NUMBER] > 2]
	set_interface_property src2 ENABLED $ena_srcfifo2
	set_parameter_property SRCFIFO_2_SIZE ENABLED $ena_srcfifo2

	set ena_srcfifo3 [expr $ena_streamfifo && [get_parameter_value SRCFIFO_NUMBER] > 3]
	set_interface_property src3 ENABLED $ena_srcfifo3
	set_parameter_property SRCFIFO_3_SIZE ENABLED $ena_srcfifo3


	set ena_sinkfifo0 [expr $ena_streamfifo && [get_parameter_value SINKFIFO_NUMBER] > 0]
	set_interface_property sink0 ENABLED $ena_sinkfifo0
	set_parameter_property SINKFIFO_0_SIZE ENABLED $ena_sinkfifo0

	set ena_sinkfifo1 [expr $ena_streamfifo && [get_parameter_value SINKFIFO_NUMBER] > 1]
	set_interface_property sink1 ENABLED $ena_sinkfifo1
	set_parameter_property SINKFIFO_1_SIZE ENABLED $ena_sinkfifo1

	set ena_sinkfifo2 [expr $ena_streamfifo && [get_parameter_value SINKFIFO_NUMBER] > 2]
	set_interface_property sink2 ENABLED $ena_sinkfifo2
	set_parameter_property SINKFIFO_2_SIZE ENABLED $ena_sinkfifo2

	set ena_sinkfifo3 [expr $ena_streamfifo && [get_parameter_value SINKFIFO_NUMBER] > 3]
	set_interface_property sink3 ENABLED $ena_sinkfifo3
	set_parameter_property SINKFIFO_3_SIZE ENABLED $ena_sinkfifo3

}
