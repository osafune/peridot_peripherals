# ===================================================================
# TITLE : PERIDOT-NGS / "PERIDOT CAM"
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2017/04/05 -> 2017/04/06
#   MODIFY : 2018/11/26 17.1 beta
#            2021/12/28 17.2 beta
#            2022/09/25 19.1 beta
#            2023/01/04 20.1
#
# ===================================================================
#
# The MIT License (MIT)
# Copyright (c) 2017,2018 J-7SYSTEM WORKS LIMITED.
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
# module peridot_cam
# 
set_module_property NAME peridot_cam
set_module_property DISPLAY_NAME "PERIDOT CAM interface"
set_module_property DESCRIPTION "PERIDOT OmniVision DVP capture interface"
set_module_property GROUP "PERIDOT Peripherals"
set_module_property AUTHOR "J-7SYSTEM WORKS LIMITED"
set_module_property VERSION 20.1
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
set_fileset_property quartus_synth TOP_LEVEL peridot_cam


# 
# parameters
# 
set debugview false
#set debugview true
add_parameter HW_TCL_DEBUG boolean true
set_parameter_property HW_TCL_DEBUG ENABLED false
set_parameter_property HW_TCL_DEBUG VISIBLE $debugview


add_parameter AVM_CLOCKFREQ integer
set_parameter_property AVM_CLOCKFREQ UNITS hertz
set_parameter_property AVM_CLOCKFREQ SYSTEM_INFO {CLOCK_RATE m1_clock}
set_parameter_property AVM_CLOCKFREQ HDL_PARAMETER true
set_parameter_property AVM_CLOCKFREQ VISIBLE $debugview

add_parameter AVS_CLOCKFREQ integer
set_parameter_property AVS_CLOCKFREQ UNITS hertz
set_parameter_property AVS_CLOCKFREQ SYSTEM_INFO {CLOCK_RATE s1_clock}
set_parameter_property AVS_CLOCKFREQ HDL_PARAMETER true
set_parameter_property AVS_CLOCKFREQ VISIBLE $debugview

add_parameter BURSTCOUNT_WIDTH integer 4
set_parameter_property BURSTCOUNT_WIDTH HDL_PARAMETER true
set_parameter_property BURSTCOUNT_WIDTH DISPLAY_NAME "Burst units"
set_parameter_property BURSTCOUNT_WIDTH ALLOWED_RANGES {"4:16 bursts" "5:32 bursts" "6:64 bursts" "7:128 bursts" "8:256 bursts"}

add_parameter TRANSCYCLE_WIDTH integer 22
set_parameter_property TRANSCYCLE_WIDTH HDL_PARAMETER true
set_parameter_property TRANSCYCLE_WIDTH VISIBLE $debugview

add_parameter DVP_FIFO_DEPTH integer 10
set_parameter_property DVP_FIFO_DEPTH HDL_PARAMETER true
set_parameter_property DVP_FIFO_DEPTH DISPLAY_NAME "DVP input fifo size"
set_parameter_property DVP_FIFO_DEPTH ALLOWED_RANGES {"10:1024 bytes" "11:2048 bytes" "12:4096 bytes"}

add_parameter DVP_BYTESWAP string "ON"
set_parameter_property DVP_BYTESWAP HDL_PARAMETER true
set_parameter_property DVP_BYTESWAP DISPLAY_NAME "Alignment unit of DVP data"
set_parameter_property DVP_BYTESWAP ALLOWED_RANGES {"OFF:Byte(8bit)" "ON:Word(16bit)"}
set_parameter_property DVP_BYTESWAP DISPLAY_HINT radio

add_parameter USE_SCCBINTERFACE string "ON"
set_parameter_property USE_SCCBINTERFACE HDL_PARAMETER true
set_parameter_property USE_SCCBINTERFACE DERIVED true
set_parameter_property USE_SCCBINTERFACE VISIBLE $debugview
add_parameter USE_SCCB boolean true
set_parameter_property USE_SCCB DISPLAY_NAME "Use the built-in SCCB interface"
set_parameter_property USE_SCCB DISPLAY_HINT boolean

add_parameter USE_PERIDOT_I2C string "OFF"
set_parameter_property USE_PERIDOT_I2C HDL_PARAMETER true
set_parameter_property USE_PERIDOT_I2C DISPLAY_NAME "SCCB interface module"
set_parameter_property USE_PERIDOT_I2C ALLOWED_RANGES {"OFF:Simple SCCB" "ON:PERIDOT I2C"}
set_parameter_property USE_PERIDOT_I2C DISPLAY_HINT radio

add_parameter SCCB_CLOCKFREQ integer 400000
set_parameter_property SCCB_CLOCKFREQ HDL_PARAMETER true
set_parameter_property SCCB_CLOCKFREQ DISPLAY_NAME "SCCB bit rate"
set_parameter_property SCCB_CLOCKFREQ ALLOWED_RANGES {"100000:100 Kbps" "400000:400 Kbps"}


# 
# display items
# 



# 
# connection point s1_clock
# 
add_interface s1_clock clock end
set_interface_property s1_clock clockRate 0

add_interface_port s1_clock csi_global_clk clk Input 1

# 
# connection point s1_reset
# 
add_interface s1_reset reset end
set_interface_property s1_reset associatedClock s1_clock
set_interface_property s1_reset synchronousEdges DEASSERT

add_interface_port s1_reset csi_global_reset reset Input 1

# 
# connection point s1
# 
add_interface s1 avalon end
set_interface_property s1 addressUnits WORDS
set_interface_property s1 associatedClock s1_clock
set_interface_property s1 associatedReset s1_reset
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

add_interface_port s1 avs_s1_address address Input 2
add_interface_port s1 avs_s1_write write Input 1
add_interface_port s1 avs_s1_writedata writedata Input 32
add_interface_port s1 avs_s1_read read Input 1
add_interface_port s1 avs_s1_readdata readdata Output 32
add_interface_port s1 avs_s1_waitrequest waitrequest Output 1
set_interface_assignment s1 embeddedsw.configuration.isFlash 0
set_interface_assignment s1 embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment s1 embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment s1 embeddedsw.configuration.isPrintableDevice 0

# 
# connection point irq_s1
# 
add_interface irq_s1 interrupt end
set_interface_property irq_s1 associatedAddressablePoint s1
set_interface_property irq_s1 associatedClock s1_clock
set_interface_property irq_s1 associatedReset s1_reset

add_interface_port irq_s1 avs_s1_irq irq Output 1


# 
# connection point m1_clock
# 
add_interface m1_clock clock end
set_interface_property m1_clock clockRate 0

add_interface_port m1_clock avm_m1_clk clk Input 1

# 
# connection point m1
# 
add_interface m1 avalon start
set_interface_property m1 addressUnits SYMBOLS
set_interface_property m1 associatedClock m1_clock
set_interface_property m1 associatedReset s1_reset
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
add_interface_port m1 avm_m1_write write Output 1
add_interface_port m1 avm_m1_writedata writedata Output 32
add_interface_port m1 avm_m1_byteenable byteenable Output 4
add_interface_port m1 avm_m1_burstcount burstcount Output 5
add_interface_port m1 avm_m1_waitrequest waitrequest Input 1


# 
# connection point dvp
# 
add_interface dvp conduit end

add_interface_port dvp cam_clk pclk Input 1
add_interface_port dvp cam_data data Input 8
add_interface_port dvp cam_href href Input 1
add_interface_port dvp cam_vsync vsync Input 1
add_interface_port dvp cam_reset_n reseto_n Output 1

# 
# connection point sccb
# 
add_interface sccb conduit end

add_interface_port sccb sccb_sck sck bidir 1
add_interface_port sccb sccb_data data bidir 1



# *******************************************************************
#
#  File generate callback
#
# *******************************************************************

proc generate_synth {entityname} {
	add_fileset_file peridot_cam.v		VERILOG PATH hdl/peridot_cam.v TOP_LEVEL_FILE
	add_fileset_file peridot_cam_avm.v	VERILOG PATH hdl/peridot_cam_avm.v
	add_fileset_file peridot_cam_avs.v	VERILOG PATH hdl/peridot_cam_avs.v
	add_fileset_file peridot_cam.sdc	SDC PATH hdl/peridot_cam.sdc

	if {[get_parameter_value USE_SCCBINTERFACE] == "ON"} {
		if {[get_parameter_value USE_PERIDOT_I2C] == "ON"} {
			add_fileset_file peridot_i2c.v		VERILOG PATH ../peridot_i2c/hdl/peridot_i2c.v
		} else {
			add_fileset_file peridot_cam_sccb.v	VERILOG PATH hdl/peridot_cam_sccb.v
		}
	}
}



# *******************************************************************
#
#  Elaboration callback
#
# *******************************************************************

proc elaboration_callback {} {

	#-----------------------------------
	# setup Burst size
	#-----------------------------------

	set bcwidth		[get_parameter_value BURSTCOUNT_WIDTH]
	set fifodepth	[get_parameter_value DVP_FIFO_DEPTH]

	if {[expr $bcwidth >= ($fifodepth-2)]} {
		send_message error "Set a fifo size value greater than."
	}

	add_interface_port m1 avm_m1_burstcount burstcount Output [expr $bcwidth+1]


	#-----------------------------------
	# setup SCCB interface type
	#-----------------------------------

	if {[get_parameter_value USE_SCCB]} {
		set_parameter_value USE_SCCBINTERFACE "ON"
		set_interface_property sccb ENABLED true
		set_parameter_property SCCB_CLOCKFREQ ENABLED true

		if {[file exists "../peridot_i2c/hdl/peridot_i2c.v"]} {
			set_parameter_property USE_PERIDOT_I2C ENABLED true
		} else {
			set_parameter_property USE_PERIDOT_I2C ENABLED false
		}
	} else {
		set_parameter_value USE_SCCBINTERFACE "OFF"
		set_interface_property sccb ENABLED false
		set_parameter_property SCCB_CLOCKFREQ ENABLED false
		set_parameter_property USE_PERIDOT_I2C ENABLED false
	}


	#-----------------------------------
	# SWI Validation
	#-----------------------------------

	# Software assignments for system.h
	set value_use_sccb		[expr [get_parameter_value USE_SCCBINTERFACE] == "ON" ? 1 : 0]
	set value_use_i2c		[expr [get_parameter_value USE_PERIDOT_I2C] == "ON" ? 1 : 0]

	set_module_assignment embeddedsw.CMacro.USE_BUILTIN_SCCB	$value_use_sccb
	set_module_assignment embeddedsw.CMacro.USE_PERIDOT_I2C		$value_use_i2c
	set_module_assignment embeddedsw.CMacro.SCCB_BITRATE		[get_parameter_value SCCB_CLOCKFREQ]


	#-----------------------------------
	# Debug view
	#-----------------------------------

	if {[get_parameter_property HW_TCL_DEBUG VISIBLE]} {
		set sccbinterface_value [get_parameter_value USE_SCCBINTERFACE]
		set peridot_i2c_valie [get_parameter_value USE_PERIDOT_I2C]
		set sccb_bitrate_value [get_parameter_value SCCB_CLOCKFREQ]
		set dvp_byteswap_value [get_parameter_value DVP_BYTESWAP]
		set dvp_fifodepth_value [get_parameter_value DVP_FIFO_DEPTH]

		send_message info "USE_SCCBINTERFACE = $sccbinterface_value, USE_PERIDOT_I2C = $peridot_i2c_valie, SCCB_CLOCKFREQ = $sccb_bitrate_value, DVP_FIFO_DEPTH = $dvp_fifodepth_value, DVP_BYTESWAP = $dvp_byteswap_value"
		send_message info "value_use_sccb = $value_use_sccb, value_use_i2c = $value_use_i2c"
	}
}
