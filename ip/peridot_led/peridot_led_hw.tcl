# ===================================================================
# TITLE : PERIDOT-NGS / "PERIDOT Serial LED Controller"
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2018/10/21 -> 2018/11/24
#   MODIFY : 2018/11/25 17.1 beta
#            2019/01/14 17.1 beta update1
#            2019/06/22 17.1 rev2
#            2022/09/25 19.1 release
#
# ===================================================================
#
# The MIT License (MIT)
# Copyright (c) 2018-2019 J-7SYSTEM WORKS LIMITED.
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
# module peridot_led_controller
# 
set_module_property NAME peridot_wsled_controller
set_module_property DISPLAY_NAME "PERIDOT Serial LED controller"
set_module_property DESCRIPTION "PERIDOT Serial LED controller"
set_module_property GROUP "PERIDOT Peripherals"
set_module_property AUTHOR "J-7SYSTEM WORKS LIMITED"
set_module_property VERSION 19.1
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
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL peridot_led
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false
add_fileset_file peridot_led_colorconv.vhd	VHDL PATH hdl/peridot_led_colorconv.vhd
add_fileset_file peridot_led_fluctuator.vhd	VHDL PATH hdl/peridot_led_fluctuator.vhd
add_fileset_file peridot_led_serializer.vhd	VHDL PATH hdl/peridot_led_serializer.vhd
add_fileset_file peridot_led_vram.vhd		VHDL PATH hdl/peridot_led_vram.vhd
add_fileset_file peridot_led_control.vhd	VHDL PATH hdl/peridot_led_control.vhd
add_fileset_file peridot_led.vhd			VHDL PATH hdl/peridot_led.vhd TOP_LEVEL_FILE


# 
# parameters
# 
set debugview false

add_parameter CLOCKFREQ integer
set_parameter_property CLOCKFREQ UNITS hertz
set_parameter_property CLOCKFREQ SYSTEM_INFO {CLOCK_RATE clock}
set_parameter_property CLOCKFREQ ENABLED false
set_parameter_property CLOCKFREQ VISIBLE $debugview

add_parameter LED_COLOR_TRANSORDER string
set_parameter_property LED_COLOR_TRANSORDER HDL_PARAMETER true
set_parameter_property LED_COLOR_TRANSORDER DERIVED true
set_parameter_property LED_COLOR_TRANSORDER VISIBLE $debugview

add_parameter LED_CHANNEL_NUMBER integer
set_parameter_property LED_CHANNEL_NUMBER HDL_PARAMETER true
set_parameter_property LED_CHANNEL_NUMBER DERIVED true
set_parameter_property LED_CHANNEL_NUMBER VISIBLE $debugview

add_parameter LED_PIXELNUM_WIDTH integer 8
set_parameter_property LED_PIXELNUM_WIDTH HDL_PARAMETER true
set_parameter_property LED_PIXELNUM_WIDTH DERIVED true
set_parameter_property LED_PIXELNUM_WIDTH VISIBLE $debugview

add_parameter LED_RAM_ADDRESS_WIDTH integer
set_parameter_property LED_RAM_ADDRESS_WIDTH HDL_PARAMETER true
set_parameter_property LED_RAM_ADDRESS_WIDTH DERIVED true
set_parameter_property LED_RAM_ADDRESS_WIDTH VISIBLE $debugview

add_parameter USE_LAYER_BLEND string "ON"
set_parameter_property USE_LAYER_BLEND HDL_PARAMETER true
set_parameter_property USE_LAYER_BLEND DERIVED true
set_parameter_property USE_LAYER_BLEND VISIBLE $debugview

add_parameter USE_FLUCTUATOR_EFFECT string "ON"
set_parameter_property USE_FLUCTUATOR_EFFECT HDL_PARAMETER true
set_parameter_property USE_FLUCTUATOR_EFFECT DERIVED true
set_parameter_property USE_FLUCTUATOR_EFFECT VISIBLE $debugview

add_parameter BIT_TOTAL_NUNBER integer
set_parameter_property BIT_TOTAL_NUNBER HDL_PARAMETER true
set_parameter_property BIT_TOTAL_NUNBER DERIVED true
set_parameter_property BIT_TOTAL_NUNBER VISIBLE $debugview

add_parameter BIT_SYMBOL0_WIDTH integer
set_parameter_property BIT_SYMBOL0_WIDTH HDL_PARAMETER true
set_parameter_property BIT_SYMBOL0_WIDTH DERIVED true
set_parameter_property BIT_SYMBOL0_WIDTH VISIBLE $debugview

add_parameter BIT_SYMBOL1_WIDTH integer
set_parameter_property BIT_SYMBOL1_WIDTH HDL_PARAMETER true
set_parameter_property BIT_SYMBOL1_WIDTH DERIVED true
set_parameter_property BIT_SYMBOL1_WIDTH VISIBLE $debugview

add_parameter RES_COUNT_NUMBER integer
set_parameter_property RES_COUNT_NUMBER HDL_PARAMETER true
set_parameter_property RES_COUNT_NUMBER DERIVED true
set_parameter_property RES_COUNT_NUMBER VISIBLE $debugview


add_parameter LED_SETTINGS_CHANNELS integer 12
set_parameter_property LED_SETTINGS_CHANNELS DISPLAY_NAME "Number of LED channels"
set_parameter_property LED_SETTINGS_CHANNELS ALLOWED_RANGES {1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16}

add_parameter LED_SETTINGS_PIXELNUM integer 256
set_parameter_property LED_SETTINGS_PIXELNUM DISPLAY_NAME "Number of Pixel per channels"
set_parameter_property LED_SETTINGS_PIXELNUM ALLOWED_RANGES {256 512 1024 2048 4096}

add_parameter LED_SETTINGS_LAYER boolean true
set_parameter_property LED_SETTINGS_LAYER DISPLAY_NAME "Use a layer blending"
set_parameter_property LED_SETTINGS_LAYER DISPLAY_HINT boolean

add_parameter LED_SETTINGS_FLUCTUATOR boolean true
set_parameter_property LED_SETTINGS_FLUCTUATOR DISPLAY_NAME "Use a fluctuator effect"
set_parameter_property LED_SETTINGS_FLUCTUATOR DISPLAY_HINT boolean

add_parameter LED_SETTINGS_EXTTRIG boolean true
set_parameter_property LED_SETTINGS_EXTTRIG DISPLAY_NAME "Use a external trigger"
set_parameter_property LED_SETTINGS_EXTTRIG DISPLAY_HINT boolean


add_parameter LED_SETTINGS_DEVICETYPE integer 0
set_parameter_property LED_SETTINGS_DEVICETYPE DISPLAY_NAME "LED device"
set_parameter_property LED_SETTINGS_DEVICETYPE ALLOWED_RANGES {"0:WS2812B/WS2815B" "1:SK6812" "2:APA104" "3:PL9823" "99:Custom timing"}

add_parameter LED_SETTINGS_TRANSORDER integer 0
set_parameter_property LED_SETTINGS_TRANSORDER DISPLAY_NAME "Color transfer order"
set_parameter_property LED_SETTINGS_TRANSORDER ALLOWED_RANGES {"0:G->R->B" "1:R->G->B"}
set_parameter_property LED_SETTINGS_TRANSORDER DISPLAY_HINT radio

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

add_display_item "LED Settings" LED_SETTINGS_CHANNELS parameter
add_display_item "LED Settings" LED_SETTINGS_PIXELNUM parameter
add_display_item "LED Settings" LED_SETTINGS_LAYER parameter
add_display_item "LED Settings" LED_SETTINGS_FLUCTUATOR parameter
add_display_item "LED Settings" LED_SETTINGS_EXTTRIG parameter

add_display_item "Timing Settings" LED_SETTINGS_DEVICETYPE parameter
add_display_item "Timing Settings" LED_SETTINGS_TRANSORDER parameter
add_display_item "Timing Settings" LED_SETTINGS_BITPERIOD parameter
add_display_item "Timing Settings" LED_SETTINGS_BITSYMBOL0 parameter
add_display_item "Timing Settings" LED_SETTINGS_BITSYMBOL1 parameter
add_display_item "Timing Settings" LED_SETTINGS_RESETWIDTH parameter



#-----------------------------------
# Avalon-MM slave interface
#-----------------------------------
# 
# connection point clock and reset
# 
add_interface clock clock end
set_interface_property clock clockRate 0
add_interface_port clock csi_clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset csi_reset reset Input 1


# 
# connection point csr
# 
add_interface csr avalon end
set_interface_property csr addressUnits WORDS
set_interface_property csr associatedClock clock
set_interface_property csr associatedReset reset
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
# connection point irq
# 
add_interface irq interrupt end
set_interface_property irq associatedAddressablePoint csr
set_interface_property irq associatedClock clock
set_interface_property irq associatedReset reset

add_interface_port irq ins_csr_irq irq Output 1


# 
# connection point mem
# 
add_interface mem avalon end
set_interface_property mem addressUnits SYMBOLS
set_interface_property mem associatedClock clock
set_interface_property mem associatedReset reset
set_interface_property mem bitsPerSymbol 8
set_interface_property mem burstOnBurstBoundariesOnly false
set_interface_property mem burstcountUnits WORDS
set_interface_property mem explicitAddressSpan 0
set_interface_property mem holdTime 0
set_interface_property mem linewrapBursts false
set_interface_property mem maximumPendingReadTransactions 0
set_interface_property mem maximumPendingWriteTransactions 0
set_interface_property mem readLatency 0
set_interface_property mem readWaitStates 0
set_interface_property mem readWaitTime 0
set_interface_property mem setupTime 2
set_interface_property mem timingUnits Cycles
set_interface_property mem writeWaitTime 0

add_interface_port mem avs_mem_address address Input {LED_RAM_ADDRESS_WIDTH}
add_interface_port mem avs_mem_read read Input 1
add_interface_port mem avs_mem_readdata readdata Output 32
add_interface_port mem avs_mem_write write Input 1
add_interface_port mem avs_mem_writedata writedata Input 32
add_interface_port mem avs_mem_byteenable byteenable Input 4
set_interface_assignment mem embeddedsw.configuration.isFlash 0
set_interface_assignment mem embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment mem embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment mem embeddedsw.configuration.isPrintableDevice 0



#-----------------------------------
# Other condit interface
#-----------------------------------
# 
# connection point ext_trig
# 
add_interface ext_trig conduit end
set_interface_property ext_trig associatedClock clock
set_interface_property ext_trig associatedReset reset
add_interface_port ext_trig coe_ext_trig trig Input 1
add_interface_port ext_trig coe_ext_sel sel Output 4


# 
# connection point led
# 
add_interface led conduit end
set_interface_property led associatedClock clock
set_interface_property led associatedReset reset
add_interface_port led coe_led data Output {LED_CHANNEL_NUMBER}



# *******************************************************************
#
#  Elaboration callback
#
# *******************************************************************

proc elaboration_callback {} {

	#-----------------------------------
	# external trigger port settings
	#-----------------------------------

	if {[get_parameter_value LED_SETTINGS_EXTTRIG]} {
		set_interface_property ext_trig ENABLED true
	} else {
		set_interface_property ext_trig ENABLED false
	}


	#-----------------------------------
	# layer and effect settings
	#-----------------------------------

	if {[get_parameter_value LED_SETTINGS_FLUCTUATOR]} {
		set fluctuator_enable "ON"
	} else {
		set fluctuator_enable "OFF"
	}

	if {[get_parameter_value LED_SETTINGS_LAYER]} {
		set layer_enable "ON"
		set pixel_per_bytes 8
		set_parameter_property LED_SETTINGS_FLUCTUATOR ENABLED true
	} else {
		set layer_enable "OFF"
		set pixel_per_bytes 4
		set_parameter_property LED_SETTINGS_FLUCTUATOR ENABLED false
		set fluctuator_enable "OFF"
	}

	set_parameter_value USE_LAYER_BLEND $layer_enable
	set_parameter_value USE_FLUCTUATOR_EFFECT $fluctuator_enable


	#-----------------------------------
	# vram area settings
	#-----------------------------------

	set pixelnum [get_parameter_value LED_SETTINGS_PIXELNUM]

	if {$layer_enable == "ON" && $pixelnum > 2048} {
		send_message error "The number of pixels is up to 2048 when using layer blend."
		return
	} elseif {$layer_enable != "ON" && $pixelnum < 512} {
		send_message error "The number of pixels is 512 or more when not using layer blend."
		return
	}

	set led_chnum [get_parameter_value LED_SETTINGS_CHANNELS]
	set pixelwidth [expr (ceil(log10($pixelnum) / log10(2)))]
	set memaddrwidth [expr (ceil(log10($led_chnum * $pixelnum * $pixel_per_bytes) / log10(2)))]

	set_parameter_value LED_CHANNEL_NUMBER $led_chnum
	set_parameter_value LED_PIXELNUM_WIDTH $pixelwidth
	set_parameter_value LED_RAM_ADDRESS_WIDTH $memaddrwidth



	#-----------------------------------
	# led type settings
	#-----------------------------------

	set led_devicetype [get_parameter_value LED_SETTINGS_DEVICETYPE]
	set custom_setting false

	switch $led_devicetype {
	"0" {
		set led_devicename	"WS2812B"
		set led_transorder	"GRB"
		set bitperiod_time	1100
		set bitsymbol0_time 300
		set bitsymbol1_time 750
		set resetwidth_time 280
	}
	"1" {
		set led_devicename	"SK6812"
		set led_transorder	"GRB"
		set bitperiod_time	1200
		set bitsymbol0_time 300
		set bitsymbol1_time 600
		set resetwidth_time 80
	}
	"2" {
		set led_devicename	"APA104"
		set led_transorder	"RGB"
		set bitperiod_time	1650
		set bitsymbol0_time 350
		set bitsymbol1_time 1300
		set resetwidth_time 50
	}
	"3" {
		set led_devicename	"PL9823"
		set led_transorder	"RGB"
		set bitperiod_time	1710
		set bitsymbol0_time 350
		set bitsymbol1_time 1360
		set resetwidth_time 50
	}
	"99" {
		set led_devicename	""
		set bitperiod_time [get_parameter_value LED_SETTINGS_BITPERIOD]
		set bitsymbol0_time [get_parameter_value LED_SETTINGS_BITSYMBOL0]
		set bitsymbol1_time [get_parameter_value LED_SETTINGS_BITSYMBOL1]
		set resetwidth_time [get_parameter_value LED_SETTINGS_RESETWIDTH]

		switch [get_parameter_value LED_SETTINGS_TRANSORDER] {
		"1" {
			set led_transorder "RGB"
		}
		default {
			set led_transorder "GRB"
		}}

		set custom_setting true
	}

	default {
		send_message error "Don't defined device."
		return
	}}

	set_parameter_value LED_COLOR_TRANSORDER $led_transorder

	set_parameter_property LED_SETTINGS_TRANSORDER ENABLED $custom_setting
	set_parameter_property LED_SETTINGS_BITPERIOD ENABLED $custom_setting
	set_parameter_property LED_SETTINGS_BITSYMBOL0 ENABLED $custom_setting
	set_parameter_property LED_SETTINGS_BITSYMBOL1 ENABLED $custom_setting
	set_parameter_property LED_SETTINGS_RESETWIDTH ENABLED $custom_setting



	#-----------------------------------
	# timing parameter calc
	#-----------------------------------

	set clock_frequency [get_parameter_value CLOCKFREQ]

	if {$clock_frequency == 0} {
		send_message error "A connection of a clock is necessary for setting of timing."
		return
	} elseif {$clock_frequency < 25000000} {
		send_message warning "Recommended, clock more than 25 MHz. Below that, the accuracy of a timing deteriorates."
	}

	set bitperiod_count [expr (ceil(($bitperiod_time * pow(10,-9))* $clock_frequency))]

	set bitsymbol1_count [expr (ceil(($bitsymbol1_time * pow(10,-9))* $clock_frequency))]
	set bitsymbol1_max [expr ($bitperiod_count - 8)]

	set bitsymbol0_count [expr (ceil(($bitsymbol0_time * pow(10,-9))* $clock_frequency))]
	set bitsymbol0_max [expr ($bitsymbol1_count - 1)]

	if {$bitsymbol1_count >= $bitsymbol1_max || $bitsymbol0_count >= $bitsymbol0_max} {
		send_message error "The timing setting of the LED is incorrect."
		return
	}

	set resetwidth_count [expr (ceil(($resetwidth_time * pow(10,-6) * $clock_frequency) / ($bitperiod_count * 8)))]
	if {$resetwidth_count < 1} {
		set resetwidth_count 1
	}

	set_parameter_value BIT_TOTAL_NUNBER $bitperiod_count
	set_parameter_value BIT_SYMBOL0_WIDTH $bitsymbol0_count
	set_parameter_value BIT_SYMBOL1_WIDTH $bitsymbol1_count
	set_parameter_value RES_COUNT_NUMBER $resetwidth_count

	set bitperiod_time [expr int(ceil(($bitperiod_count * pow(10,9))/ $clock_frequency))]
	set resetwidth_time [expr int(ceil(($resetwidth_count * $bitperiod_count * 8 * pow(10,6))/ $clock_frequency))]

	set bitsymbol0_time [expr int(ceil(($bitsymbol0_count * pow(10,9))/ $clock_frequency))]
	set bitsymbol1_time [expr int(ceil(($bitsymbol1_count * pow(10,9))/ $clock_frequency))]
	set bitsymbol0l_time [expr $bitperiod_time - $bitsymbol0_time]
	set bitsymbol1l_time [expr $bitperiod_time - $bitsymbol1_time]
	send_message info "Output timing : T0H = ${bitsymbol0_time}ns, T0L = ${bitsymbol0l_time}ns, T1H = ${bitsymbol1_time}ns, T1L = ${bitsymbol1l_time}ns, RES = ${resetwidth_time}us"


	#-----------------------------------
	# Software assignments
	#-----------------------------------

	set_module_assignment embeddedsw.CMacro.CHANNEL			[format %u [get_parameter_value LED_CHANNEL_NUMBER]]
	set_module_assignment embeddedsw.CMacro.PIXELNUM		[format %u [get_parameter_value LED_SETTINGS_PIXELNUM]]
	set_module_assignment embeddedsw.CMacro.USE_LAYER		[expr ([get_parameter_value LED_SETTINGS_LAYER]? 1 : 0)]
	set_module_assignment embeddedsw.CMacro.USE_FLUCTUATOR	[expr ([get_parameter_value LED_SETTINGS_FLUCTUATOR]? 1 : 0)]
	set_module_assignment embeddedsw.CMacro.USE_EXTTRIG		[expr ([get_parameter_value LED_SETTINGS_EXTTRIG]? 1 : 0)]
	set_module_assignment embeddedsw.CMacro.DEVICE			$led_devicename
	set_module_assignment embeddedsw.CMacro.TRANSORDER		$led_transorder
	set_module_assignment embeddedsw.CMacro.BITPERIOD_NS	[format %u $bitperiod_time]
	set_module_assignment embeddedsw.CMacro.RESETWIDTH_US	[format %u $resetwidth_time]
}
