# ===================================================================
# TITLE : PERIDOT-NGS / "PERIDOT Compact CNN Accelerator"
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2020/07/31 -> 2020/09/23
#
# ===================================================================
#
# The MIT License (MIT)
# Copyright (c) 2020 J-7SYSTEM WORKS LIMITED.
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
# module peridot_cnn_accelerator
# 
set_module_property NAME peridot_cnn_accelerator
set_module_property DISPLAY_NAME "PERIDOT Compact CNN Accelerator (beta test version)"
set_module_property DESCRIPTION "PERIDOT Compact CNN Accelerator"
set_module_property GROUP "PERIDOT Peripherals"
set_module_property AUTHOR "J-7SYSTEM WORKS LIMITED"
set_module_property VERSION 17.1
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property HIDE_FROM_SOPC true
set_module_property HIDE_FROM_QUARTUS true
set_module_property EDITABLE false
set_module_property ELABORATION_CALLBACK elaboration_callback
set_module_property SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone IV E" "Cyclone IV GX" "Cyclone V" "Arria II GX" "Arria II GZ" "Arria V" "Arria V GZ" "Stratix IV" "Stratix V"}

# 
# file sets
# 
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL peridot_cnn
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false
add_fileset_file peridot_cnn_core_package.vhd VHDL PATH hdl/peridot_cnn_core_package.vhd
add_fileset_file peridot_cnn_core.vhd		VHDL PATH hdl/peridot_cnn_core.vhd
add_fileset_file peridot_cnn_mainfsm.vhd	VHDL PATH hdl/peridot_cnn_mainfsm.vhd
add_fileset_file peridot_cnn_kernel.vhd		VHDL PATH hdl/peridot_cnn_kernel.vhd
add_fileset_file peridot_cnn_accum.vhd		VHDL PATH hdl/peridot_cnn_accum.vhd
add_fileset_file peridot_cnn_writeback.vhd	VHDL PATH hdl/peridot_cnn_writeback.vhd
add_fileset_file peridot_cnn_arbiter.vhd	VHDL PATH hdl/peridot_cnn_arbiter.vhd
add_fileset_file peridot_cnn_ctrlregs.vhd	VHDL PATH hdl/peridot_cnn_ctrlregs.vhd
add_fileset_file peridot_cnn.vhd			VHDL PATH hdl/peridot_cnn.vhd TOP_LEVEL_FILE


# 
# parameters
# 
set debugview true

add_parameter DEVICE_FAMILY string
set_parameter_property DEVICE_FAMILY SYSTEM_INFO {DEVICE_FAMILY}
set_parameter_property DEVICE_FAMILY HDL_PARAMETER true
set_parameter_property DEVICE_FAMILY ENABLED false
set_parameter_property DEVICE_FAMILY VISIBLE $debugview
add_parameter PART_NAME string
set_parameter_property PART_NAME SYSTEM_INFO {DEVICE}
set_parameter_property PART_NAME ENABLED false
set_parameter_property PART_NAME VISIBLE $debugview

add_parameter MAXLINEBYTES_POW2_NUMBER integer 15
set_parameter_property MAXLINEBYTES_POW2_NUMBER HDL_PARAMETER true
set_parameter_property MAXLINEBYTES_POW2_NUMBER DERIVED true
set_parameter_property MAXLINEBYTES_POW2_NUMBER VISIBLE $debugview

add_parameter FIFODEPTH_POW2_NUMBER integer 9
set_parameter_property FIFODEPTH_POW2_NUMBER HDL_PARAMETER true
set_parameter_property FIFODEPTH_POW2_NUMBER DERIVED true
set_parameter_property FIFODEPTH_POW2_NUMBER VISIBLE $debugview

add_parameter USE_KERNELREAD_FUSION string "ON"
set_parameter_property USE_KERNELREAD_FUSION HDL_PARAMETER true
set_parameter_property USE_KERNELREAD_FUSION DERIVED true
set_parameter_property USE_KERNELREAD_FUSION VISIBLE $debugview

add_parameter USE_FIFO_FLOW_CHECKING string "ON"
set_parameter_property USE_FIFO_FLOW_CHECKING HDL_PARAMETER true
set_parameter_property USE_FIFO_FLOW_CHECKING DERIVED true
set_parameter_property USE_FIFO_FLOW_CHECKING VISIBLE $debugview


# 
# display items
# 

add_parameter SETNUMBER_POW2_NUMBER integer 16
set_parameter_property SETNUMBER_POW2_NUMBER HDL_PARAMETER true
set_parameter_property SETNUMBER_POW2_NUMBER DISPLAY_NAME "Maximum number of filter sets"
set_parameter_property SETNUMBER_POW2_NUMBER ALLOWED_RANGES {"10:1023sets" "11:2047sets" "12:4095sets" "13:8191sets" "14:16383sets" "15:32767sets" "16:65535sets"}

add_parameter MAXCONVSIZE_POW2_NUMBER integer 9
set_parameter_property MAXCONVSIZE_POW2_NUMBER HDL_PARAMETER true
set_parameter_property MAXCONVSIZE_POW2_NUMBER DISPLAY_NAME "Maximum image size of convolution"
set_parameter_property MAXCONVSIZE_POW2_NUMBER ALLOWED_RANGES {"8:256x256" "9:512x512" "10:1024x1024" "11:2048x2048"}

add_parameter DATABUS_POW2_NUMBER integer 5
set_parameter_property DATABUS_POW2_NUMBER HDL_PARAMETER true
set_parameter_property DATABUS_POW2_NUMBER DISPLAY_NAME "Avalon-MM master data bus width"
set_parameter_property DATABUS_POW2_NUMBER ALLOWED_RANGES {"5:32bit" "6:64bit" "7:128bit" "8:256bit"}

add_parameter MAXKERNEL_NUMBER integer 4
set_parameter_property MAXKERNEL_NUMBER HDL_PARAMETER true
set_parameter_property MAXKERNEL_NUMBER DISPLAY_NAME "Number of kernels to instance"
set_parameter_property MAXKERNEL_NUMBER ALLOWED_RANGES {1 2 3 4 5 6 7 8}

add_parameter CNN_SETTINGS_WORKINGFIFODEPTH integer 0
set_parameter_property CNN_SETTINGS_WORKINGFIFODEPTH DISPLAY_NAME "Working FIFO depth"
set_parameter_property CNN_SETTINGS_WORKINGFIFODEPTH ALLOWED_RANGES {"0:AUTO" "7:128words" "8:256words" "9:512words" "10:1024words" "11:2048words" "12:4096words"}

add_parameter CNN_SETTINGS_READFUSION boolean true
set_parameter_property CNN_SETTINGS_READFUSION DISPLAY_NAME "Use a fusion of kernel data read commands"
set_parameter_property CNN_SETTINGS_READFUSION DISPLAY_HINT boolean

add_parameter CNN_SETTINGS_FLOWCHECKING boolean true
set_parameter_property CNN_SETTINGS_FLOWCHECKING DISPLAY_NAME "Use the FIFO flow check function"
set_parameter_property CNN_SETTINGS_FLOWCHECKING DISPLAY_HINT boolean



#-----------------------------------
# Avalon-MM master interface
#-----------------------------------
# 
# connection point m1_clock
# 
add_interface m1_clock clock end
set_interface_property m1_clock clockRate 0

add_interface_port m1_clock csi_m1_clk clk Input 1

# 
# connection point m1_reset
# 
add_interface m1_reset reset end
set_interface_property m1_reset associatedClock m1_clock
set_interface_property m1_reset synchronousEdges DEASSERT

add_interface_port m1_reset csi_m1_reset reset Input 1

# 
# connection point m1
# 
add_interface m1 avalon start
set_interface_property m1 addressUnits SYMBOLS
set_interface_property m1 associatedClock m1_clock
set_interface_property m1 associatedReset m1_reset
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
add_interface_port m1 avm_m1_waitrequest waitrequest Input 1
add_interface_port m1 avm_m1_read read Output 1
add_interface_port m1 avm_m1_readdatavalid readdatavalid Input 1
add_interface_port m1 avm_m1_write write Output 1


#-----------------------------------
# Avalon-MM slave interface
#-----------------------------------
# 
# connection point csr_clock
# 
add_interface csr_clock clock end
set_interface_property csr_clock clockRate 0

add_interface_port csr_clock csi_csr_clk clk Input 1

# 
# connection point csr_reset
# 
add_interface csr_reset reset end
set_interface_property csr_reset associatedClock csr_clock
set_interface_property csr_reset synchronousEdges DEASSERT

add_interface_port csr_reset csi_csr_reset reset Input 1

# 
# connection point csr
# 
add_interface csr avalon end
set_interface_property csr addressUnits WORDS
set_interface_property csr associatedClock csr_clock
set_interface_property csr associatedReset csr_reset
set_interface_property csr bitsPerSymbol 8
set_interface_property csr burstOnBurstBoundariesOnly false
set_interface_property csr burstcountUnits WORDS
set_interface_property csr explicitAddressSpan 0
set_interface_property csr holdTime 0
set_interface_property csr linewrapBursts false
set_interface_property csr maximumPendingReadTransactions 0
set_interface_property csr maximumPendingWriteTransactions 0
set_interface_property csr readLatency 0
set_interface_property csr readWaitTime 1
set_interface_property csr setupTime 0
set_interface_property csr timingUnits Cycles
set_interface_property csr writeWaitTime 0

add_interface_port csr avs_csr_address address Input 2
add_interface_port csr avs_csr_read read Input 1
add_interface_port csr avs_csr_readdata readdata Output 32
add_interface_port csr avs_csr_write write Input 1
add_interface_port csr avs_csr_writedata writedata Input 32
set_interface_assignment csr embeddedsw.configuration.isFlash 0
set_interface_assignment csr embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment csr embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment csr embeddedsw.configuration.isPrintableDevice 0

# 
# connection point csr_interrupt
# 
add_interface csr_interrupt interrupt end
set_interface_property csr_interrupt associatedAddressablePoint csr
set_interface_property csr_interrupt associatedClock csr_clock
set_interface_property csr_interrupt associatedReset csr_reset

add_interface_port csr_interrupt ins_csr_irq irq Output 1



# *******************************************************************
#
#  Elaboration callback
#
# *******************************************************************

proc elaboration_callback {} {

	#-----------------------------------
	# Check box settings
	#-----------------------------------

	set readfusion_enable true
	set readfusion "ON"

	if {[get_parameter_value MAXKERNEL_NUMBER] == 1} {
		set readfusion_enable false
		set readfusion "OFF"
	} else {
		if {![get_parameter_value CNN_SETTINGS_READFUSION]} {
			set readfusion "OFF"
		}
	}

	set_parameter_property CNN_SETTINGS_READFUSION ENABLED $readfusion_enable
	set_parameter_value USE_KERNELREAD_FUSION $readfusion


	set cnnfifodepth [get_parameter_value CNN_SETTINGS_WORKINGFIFODEPTH]
	set fifodepth [get_parameter_value MAXCONVSIZE_POW2_NUMBER]
	set fifochecking_enable false
	set flowchecking "ON"

	if {$cnnfifodepth >= 7} {
		set fifodepth $cnnfifodepth
		set fifochecking_enable true

		if {![get_parameter_value CNN_SETTINGS_FLOWCHECKING]} {
			set flowchecking "OFF"
		}
	}

	set_parameter_value FIFODEPTH_POW2_NUMBER $fifodepth
	set_parameter_property CNN_SETTINGS_FLOWCHECKING ENABLED $fifochecking_enable
	set_parameter_value USE_FIFO_FLOW_CHECKING $flowchecking


	#-----------------------------------
	# Avalon-MM master port settings
	#-----------------------------------

	set burstcount_width	[expr int([get_parameter_value MAXCONVSIZE_POW2_NUMBER] - ([get_parameter_value DATABUS_POW2_NUMBER] - 3) + 1)]
	set databus_width		[expr int(pow(2, [get_parameter_value DATABUS_POW2_NUMBER]))]
	set byteenable_width	[expr int(pow(2, [get_parameter_value DATABUS_POW2_NUMBER] - 3))]

	add_interface_port m1 avm_m1_burstcount burstcount Output $burstcount_width
	add_interface_port m1 avm_m1_readdata readdata Input $databus_width
	add_interface_port m1 avm_m1_writedata writedata Output $databus_width
	add_interface_port m1 avm_m1_byteenable byteenable Output $byteenable_width


	#-----------------------------------
	# Software assignments
	#-----------------------------------

	set_module_assignment embeddedsw.CMacro.KERNELNUM		[format %u [get_parameter_value MAXKERNEL_NUMBER]]
	set_module_assignment embeddedsw.CMacro.MAX_FILTERSET	[format %u [expr int(pow(2, [get_parameter_value SETNUMBER_POW2_NUMBER]) - 1)]]
	set_module_assignment embeddedsw.CMacro.MAX_CONVSIZE_X	[format %u [expr int(pow(2, [get_parameter_value MAXCONVSIZE_POW2_NUMBER]))]]
	set_module_assignment embeddedsw.CMacro.MAX_CONVSIZE_Y	[format %u [expr int(pow(2, [get_parameter_value MAXCONVSIZE_POW2_NUMBER]))]]
	set_module_assignment embeddedsw.CMacro.MAX_LINEBYTES	[format %u [expr int(pow(2, [get_parameter_value MAXLINEBYTES_POW2_NUMBER]))]]
}
