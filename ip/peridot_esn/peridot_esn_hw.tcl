# ===================================================================
# TITLE : PERIDOT-NGS / "PERIDOT ESN Accelerator"
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2026/03/20 -> 2026/06/10
#
# ===================================================================
#
# The MIT License (MIT)
# Copyright (c) 2026 J-7SYSTEM WORKS LIMITED.
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
# module peridot_esn
# 
set_module_property NAME peridot_esn
set_module_property DISPLAY_NAME "PERIDOT ESN Accelerator (beta test version)"
set_module_property DESCRIPTION "PERIDOT ESN Accelerator"
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
#set_module_property SUPPORTED_DEVICE_FAMILIES {"MAX 10" "Cyclone 10 LP" "Cyclone IV E" "Cyclone IV GX" "Cyclone V" "Cyclone 10 GX"}


# 
# file sets
# 
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL peridot_esn
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false

add_fileset_file peridot_esn_dcdpram.v		VERILOG PATH ./hdl/peridot_esn_dcdpram.v
add_fileset_file peridot_esn_xorshift.v		VERILOG PATH ./hdl/peridot_esn_xorshift.v
add_fileset_file peridot_esn_csr.v			VERILOG PATH ./hdl/peridot_esn_csr.v
add_fileset_file peridot_esn_input.v		VERILOG PATH ./hdl/peridot_esn_input.v
add_fileset_file peridot_esn_readout.v		VERILOG PATH ./hdl/peridot_esn_readout.v
add_fileset_file peridot_esn_reservoir.v	VERILOG PATH ./hdl/peridot_esn_reservoir.v
add_fileset_file peridot_esn.v				VERILOG PATH ./hdl/peridot_esn.v TOP_LEVEL_FILE
add_fileset_file peridot_esn.sdc			SDC PATH ./hdl/peridot_esn.sdc


# 
# parameters
# 
set debugview false

add_parameter DEVICE_FAMILY string
set_parameter_property DEVICE_FAMILY SYSTEM_INFO {DEVICE_FAMILY}
set_parameter_property DEVICE_FAMILY HDL_PARAMETER true
set_parameter_property DEVICE_FAMILY ENABLED false
set_parameter_property DEVICE_FAMILY VISIBLE $debugview

add_parameter MAX_NODE_BITWIDTH integer 9
set_parameter_property MAX_NODE_BITWIDTH HDL_PARAMETER true
set_parameter_property MAX_NODE_BITWIDTH DISPLAY_NAME "Maximum number of nodes"
set_parameter_property MAX_NODE_BITWIDTH ALLOWED_RANGES {"8:255 nodes" "9:511 nodes" "10:1023 nodes" "11:2047 nodes" "12:4095 nodes"}

add_parameter MAX_INPUT_BITWIDTH integer 8
set_parameter_property MAX_INPUT_BITWIDTH HDL_PARAMETER true
set_parameter_property MAX_INPUT_BITWIDTH DISPLAY_NAME "Maximum number of inputs"
set_parameter_property MAX_INPUT_BITWIDTH ALLOWED_RANGES {"7:127 inputs" "8:255 inputs" "9:511 inputs" "10:1023 inputs"}

add_parameter MAX_OUTPUT_BITWIDTH integer 6
set_parameter_property MAX_OUTPUT_BITWIDTH HDL_PARAMETER true
set_parameter_property MAX_OUTPUT_BITWIDTH DISPLAY_NAME "Maximum number of outputs"
set_parameter_property MAX_OUTPUT_BITWIDTH ALLOWED_RANGES {"5:31 outputs" "6:63 outputs" "7:127 outputs" "8:255 outputs"}

add_parameter WOUTMEM_BITWIDTH integer 12
set_parameter_property WOUTMEM_BITWIDTH HDL_PARAMETER true
set_parameter_property WOUTMEM_BITWIDTH DISPLAY_NAME "Wout table memory size"
set_parameter_property WOUTMEM_BITWIDTH ALLOWED_RANGES {"10:1024 words" "11:2048 words" "12:4096 words" "13:8192 words" "14:16384 words"}

add_parameter VERSION_VALUE std_logic_vector 0x7a99
set_parameter_property VERSION_VALUE HDL_PARAMETER true
set_parameter_property VERSION_VALUE DISPLAY_NAME "ID and version values"
set_parameter_property VERSION_VALUE DISPLAY_HINT hexadeciaml
set_parameter_property VERSION_VALUE WIDTH 16
set_parameter_property VERSION_VALUE DESCRIPTION "Specify the ID and version values as 16bit-hexadecimal numbers."


# 
# display items
# 

add_parameter ESN_SETTINGS_REDUCEDCSR boolean false
set_parameter_property ESN_SETTINGS_REDUCEDCSR DISPLAY_NAME "Use a reduced control/status register"
set_parameter_property ESN_SETTINGS_REDUCEDCSR DISPLAY_HINT boolean
set_parameter_property ESN_SETTINGS_REDUCEDCSR ENABLED false


#-----------------------------------
# Clock and Reset interface
#-----------------------------------
# 
# connection point core_clock
# 
add_interface core_clock clock end
set_interface_property core_clock clockRate 0

add_interface_port core_clock csi_coreclock_clk clk Input 1

# 
# connection point csr_clock
# 
add_interface csr_clock clock end
set_interface_property csr_clock clockRate 0

add_interface_port csr_clock csi_csrclock_clk clk Input 1

# 
# connection point csr_reset
# 
add_interface csr_reset reset end
set_interface_property csr_reset associatedClock csr_clock
set_interface_property csr_reset synchronousEdges DEASSERT

add_interface_port csr_reset csi_csrclock_reset reset Input 1


#-----------------------------------
# Avalon-MM agent interface
#-----------------------------------
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
set_interface_property csr readWaitStates 0
set_interface_property csr readWaitTime 0
set_interface_property csr setupTime 2
set_interface_property csr timingUnits Cycles
set_interface_property csr writeWaitTime 0

add_interface_port csr avs_csr_address address Input 3
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

add_interface_port csr_interrupt ins_avsirq_irq irq Output 1



# *******************************************************************
#
#  Elaboration callback
#
# *******************************************************************

proc elaboration_callback {} {

	#-----------------------------------
	# Check node value
	#-----------------------------------

	set n_node		[get_parameter_value MAX_NODE_BITWIDTH]
	set n_input		[get_parameter_value MAX_INPUT_BITWIDTH]
	set n_output	[get_parameter_value MAX_OUTPUT_BITWIDTH]
	set n_wout		[get_parameter_value WOUTMEM_BITWIDTH]

	if { [expr $n_node < ($n_input + 1)]} {
		send_message error "A number of nodes must be at least twice a number of inputs."
	}
	if {[expr $n_input < ($n_output + 1)]} {
		send_message error "A number of inputs must be at least twice a number of outputs."
	}
	if {[expr $n_wout < $n_node]} {
		send_message error "A Wout table memory size must be at least equal to the number of nodes."
	}


	#-----------------------------------
	# SWI Validation
	#-----------------------------------

	# Software assignments for system.h
	set max_node_number		[expr (1 << $n_node) - 1]
	set max_input_number	[expr (1 << $n_input) - 1]
	set max_output_number	[expr (1 << $n_output) - 1]
	set wout_memory_size	[expr (1 << $n_wout)]

	set_module_assignment embeddedsw.CMacro.MAX_NODE_NUMBER		[format %u $max_node_number]
	set_module_assignment embeddedsw.CMacro.MAX_INPUT_NUMBER	[format %u $max_input_number]
	set_module_assignment embeddedsw.CMacro.MAX_OUTPUT_NUMBER	[format %u $max_output_number]
	set_module_assignment embeddedsw.CMacro.WOUT_MEMORY_SIZE	[format %u $wout_memory_size]
	set_module_assignment embeddedsw.CMacro.ID_VERSION			[format 0x%04x [get_parameter_value VERSION_VALUE]]
	set_module_assignment embeddedsw.CMacro.REDUCED_CSR			[format %u [expr ([get_parameter_value ESN_SETTINGS_REDUCEDCSR]? 1 : 0)]]
}
