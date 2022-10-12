# ===================================================================
# TITLE : PERIDOT-NGS / "PERIDOT Ethernet I/O Bridge" - WSLED
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2022/09/28 -> 2022/09/29
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
set_module_property NAME peridot_serialled
set_module_property DISPLAY_NAME "PERIDOT Avalon-ST Serial LED Driver"
set_module_property DESCRIPTION "PERIDOT Avalon-ST Serial LED Driver"
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
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL peridot_ethio_wsled
add_fileset_file peridot_ethio_wsled.v VERILOG PATH "hdl/peridot_ethio_wsled.v" TOP_LEVEL_FILE


# 
# parameters
# 
set debugview false

add_parameter CLOCKFREQ integer
set_parameter_property CLOCKFREQ SYSTEM_INFO {CLOCK_RATE clock}
set_parameter_property CLOCKFREQ ENABLED false
set_parameter_property CLOCKFREQ VISIBLE $debugview
add_parameter DEVICE_FAMILY string
set_parameter_property DEVICE_FAMILY SYSTEM_INFO {DEVICE_FAMILY}
set_parameter_property DEVICE_FAMILY ENABLED false
set_parameter_property DEVICE_FAMILY VISIBLE $debugview
add_parameter PART_NAME string
set_parameter_property PART_NAME SYSTEM_INFO {DEVICE}
set_parameter_property PART_NAME ENABLED false
set_parameter_property PART_NAME VISIBLE $debugview

add_parameter BIT_PERIOD_COUNT integer
set_parameter_property BIT_PERIOD_COUNT HDL_PARAMETER true
set_parameter_property BIT_PERIOD_COUNT DERIVED true
set_parameter_property BIT_PERIOD_COUNT VISIBLE $debugview

add_parameter SYMBOL1_COUNT integer
set_parameter_property SYMBOL1_COUNT HDL_PARAMETER true
set_parameter_property SYMBOL1_COUNT DERIVED true
set_parameter_property SYMBOL1_COUNT VISIBLE $debugview

add_parameter SYMBOL0_COUNT integer
set_parameter_property SYMBOL0_COUNT HDL_PARAMETER true
set_parameter_property SYMBOL0_COUNT DERIVED true
set_parameter_property SYMBOL0_COUNT VISIBLE $debugview

add_parameter RESET_BITCOUNT integer
set_parameter_property RESET_BITCOUNT HDL_PARAMETER true
set_parameter_property RESET_BITCOUNT DERIVED true
set_parameter_property RESET_BITCOUNT VISIBLE $debugview


add_parameter LED_SETTINGS_BITPERIOD integer 1250
set_parameter_property LED_SETTINGS_BITPERIOD UNITS nanoseconds
set_parameter_property LED_SETTINGS_BITPERIOD DISPLAY_NAME "Period of one bit (600-2500)"
set_parameter_property LED_SETTINGS_BITPERIOD ALLOWED_RANGES 600:2500

add_parameter LED_SETTINGS_BITSYMBOL0 integer 350
set_parameter_property LED_SETTINGS_BITSYMBOL0 UNITS nanoseconds
set_parameter_property LED_SETTINGS_BITSYMBOL0 DISPLAY_NAME "'H' signal time of symbol-0 (150-500)"
set_parameter_property LED_SETTINGS_BITSYMBOL0 ALLOWED_RANGES 150:500

add_parameter LED_SETTINGS_BITSYMBOL1 integer 900
set_parameter_property LED_SETTINGS_BITSYMBOL1 UNITS nanoseconds
set_parameter_property LED_SETTINGS_BITSYMBOL1 DISPLAY_NAME "'H' signal time of symbol-1 (500-1600)"
set_parameter_property LED_SETTINGS_BITSYMBOL1 ALLOWED_RANGES 500:1600

add_parameter LED_SETTINGS_RESETWIDTH integer 280
set_parameter_property LED_SETTINGS_RESETWIDTH UNITS microseconds
set_parameter_property LED_SETTINGS_RESETWIDTH DISPLAY_NAME "Pulse width of symbol-reset (50-1000)"
set_parameter_property LED_SETTINGS_RESETWIDTH ALLOWED_RANGES 50:1000


# 
# display items
# 



#-----------------------------------
# Clock and Reset interface
#-----------------------------------
# 
# connection point clock
# 
add_interface clock clock sink
set_interface_property clock clockRate 0

add_interface_port clock clk clk Input 1

# 
# connection point reset
# 
add_interface reset reset sink
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT

add_interface_port reset reset reset Input 1

# 
# connection point sink
# 
add_interface sink avalon_streaming sink
set_interface_property sink associatedClock clock
set_interface_property sink associatedReset reset
set_interface_property sink dataBitsPerSymbol 8
set_interface_property sink maxChannel 0
set_interface_property sink readyLatency 0
set_interface_property sink symbolsPerBeat 1

add_interface_port sink in_ready ready Output 1
add_interface_port sink in_valid valid Input 1
add_interface_port sink in_data data Input 8

# 
# connection point export
# 
add_interface export conduit end
set_interface_property export associatedClock clock
add_interface_port export wsled out Output 1



# *******************************************************************
#
#  Elaboration callback
#
# *******************************************************************

proc elaboration_callback {} {

	#-----------------------------------
	# timing parameter calc
	#-----------------------------------

	set bitperiod_time [get_parameter_value LED_SETTINGS_BITPERIOD]
	set bitsymbol0_time [get_parameter_value LED_SETTINGS_BITSYMBOL0]
	set bitsymbol1_time [get_parameter_value LED_SETTINGS_BITSYMBOL1]
	set resetwidth_time [get_parameter_value LED_SETTINGS_RESETWIDTH]

	set clock_frequency [get_parameter_value CLOCKFREQ]

	if {$clock_frequency == 0} {
		send_message error "A connection of a clock is necessary for setting of timing."
		return
	} elseif {$clock_frequency < 25000000} {
		send_message warning "Recommended, clock more than 25 MHz. Below that, the accuracy of a timing deteriorates."
	}

	set bitperiod_count [expr ceil($clock_frequency * pow(10,-9) * $bitperiod_time)]
	set bitsymbol1_count [expr ceil($clock_frequency * pow(10,-9) * $bitsymbol1_time)]
	set bitsymbol0_count [expr ceil($clock_frequency * pow(10,-9) * $bitsymbol0_time)]

	if {$bitsymbol1_count >= $bitperiod_count || $bitsymbol0_count >= $bitsymbol1_count} {
		send_message error "The timing setting of the LED is incorrect."
		return
	}

	set resetwidth_count [expr ceil(($clock_frequency * pow(10,-6) * $resetwidth_time) / $bitperiod_count)]
	if {$resetwidth_count < 2} {
		set resetwidth_count 2
	}

	set_parameter_value BIT_PERIOD_COUNT $bitperiod_count
	set_parameter_value SYMBOL0_COUNT $bitsymbol0_count
	set_parameter_value SYMBOL1_COUNT $bitsymbol1_count
	set_parameter_value RESET_BITCOUNT $resetwidth_count

	set bitperiod_time [expr ceil((pow(10,9) / $clock_frequency) * $bitperiod_count)]
	set bitsymbol0_time [expr ceil((pow(10,9) / $clock_frequency) * $bitsymbol0_count)]
	set bitsymbol1_time [expr ceil((pow(10,9) / $clock_frequency) * $bitsymbol1_count)]
	set bitsymbol0l_time [expr $bitperiod_time - $bitsymbol0_time]
	set bitsymbol1l_time [expr $bitperiod_time - $bitsymbol1_time]
	set resetwidth_time [expr ceil((pow(10,6) / $clock_frequency) * $resetwidth_count * $bitperiod_count)]
	send_message info "Output timing : T0H = ${bitsymbol0_time}ns, T0L = ${bitsymbol0l_time}ns, T1H = ${bitsymbol1_time}ns, T1L = ${bitsymbol1l_time}ns, RES = ${resetwidth_time}us"

}
